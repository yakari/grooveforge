import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/drum_generator_plugin_instance.dart';
import '../models/drum_pattern_data.dart';
import '../models/drum_song_form.dart';
import 'audio_engine.dart';
import 'drum_arranger.dart';
import 'drum_form_arranger.dart';
import 'drum_pattern_parser.dart';
import 'drum_pattern_registry.dart';
import 'transport_engine.dart';

// ── Constants ─────────────────────────────────────────────────────────────────

/// How often the scheduling tick runs in milliseconds.
///
/// 10 ms gives ~0.05 beats of jitter at 300 BPM, well below perceptible latency.
const _kTickMs = 10;

/// How many bars ahead of the current position to pre-schedule hits.
///
/// 3 bars gives a generous buffer even at very slow BPM values.
const _kLookaheadBars = 3;

// ── ScheduledHit ──────────────────────────────────────────────────────────────

/// One pre-computed, humanised MIDI note event ready to fire.
///
/// Immutable so instances can be freely inserted into sorted lists without
/// defensive copying.  All timing values are in **absolute beats** from
/// the start of transport playback.
@immutable
class ScheduledHit {
  /// Beat timestamp at which to send note-on (transport.positionInBeats).
  final double beatTimestamp;

  /// Beat timestamp at which to send note-off.
  final double noteOffBeat;

  /// GM MIDI note number.
  final int note;

  /// Humanised MIDI velocity (0–127), already clamped.
  final int velocity;

  /// The bar this hit was scheduled for. A hit can sit slightly before its
  /// bar's first beat (a pushed kick, timing jitter), so the bar cannot be
  /// told from the timestamp; [DrumGeneratorSession.refreshSchedule] needs
  /// it to drop exactly the bars it reschedules.
  final int bar;

  /// Constructs a [ScheduledHit].
  const ScheduledHit({
    required this.beatTimestamp,
    required this.noteOffBeat,
    required this.note,
    required this.velocity,
    required this.bar,
  });
}

// ── DrumFormPosition ──────────────────────────────────────────────────────────

/// Where playback is in a song form: block [block], bar [bar] of it (both
/// from 0).
@immutable
class DrumFormPosition {
  /// Index of the block being played.
  final int block;

  /// Bar within [block], from 0.
  final int bar;

  /// Constructs a [DrumFormPosition].
  const DrumFormPosition(this.block, this.bar);

  @override
  bool operator ==(Object other) =>
      other is DrumFormPosition && other.block == block && other.bar == bar;

  @override
  int get hashCode => Object.hash(block, bar);
}

// ── DrumGeneratorSession ──────────────────────────────────────────────────────

/// Runtime scheduling state for one drum generator slot.
///
/// Each [DrumGeneratorPluginInstance] that is added to the rack gets its own
/// session.  The session maintains the pre-computed hit queues and tracks
/// which bars have already been scheduled to avoid double-scheduling.
class DrumGeneratorSession {
  /// The plugin instance this session belongs to.
  final DrumGeneratorPluginInstance instance;

  /// Resolved pattern data for the current pattern, or null if not yet loaded.
  DrumPatternData? patternData;

  /// Set of absolute bar indices that have already been scheduled.
  final Set<int> _scheduledBars = {};

  /// Pending note-on events, kept sorted by [ScheduledHit.beatTimestamp].
  final List<ScheduledHit> _noteOns = [];

  /// Pending note-off events, kept sorted by [ScheduledHit.noteOffBeat].
  final List<ScheduledHit> _noteOffs = [];

  /// Seed for the arrangement of this play: which groove variation each
  /// phrase uses, where breaks fall, how long random phrases are. Drawn
  /// again at every [reset], so two takes do not sound identical.
  int seed = Random().nextInt(0x7fffffff);

  /// The transport beat position at the moment this session's playback started.
  ///
  /// All bar timestamps are computed as `grooveEpoch + barIndex * barDuration`
  /// rather than as raw transport-absolute beats.  This prevents count-in hits
  /// from being in the "past" when the transport fires beat 1 immediately at
  /// position 1.0 on startup, which would cause all count-in notes to drain
  /// simultaneously on the very first scheduler tick.
  double grooveEpoch = 0.0;

  /// Where playback is in the song form: the block and the bar within it,
  /// or null when stopped, counting in, past the ending, or without a form.
  /// Changes once per bar at most, so the form editor can light the block
  /// being played without rebuilding anything else.
  final ValueNotifier<DrumFormPosition?> formPosition = ValueNotifier(null);

  /// The bar [formPosition] was last computed for, so it is worked out once
  /// per bar rather than on every 10 ms tick.
  int _positionBar = -1;

  /// Constructs a [DrumGeneratorSession] for [instance].
  DrumGeneratorSession(this.instance);

  /// Resets all scheduling state so the session starts fresh from bar 0.
  void reset() {
    _scheduledBars.clear();
    _noteOns.clear();
    _noteOffs.clear();
    grooveEpoch = 0.0;
    _positionBar = -1;
    formPosition.value = null;
    // A new arrangement for a new play.
    seed = Random().nextInt(0x7fffffff);
  }

  /// Forgets bars [fromBar] and later, so the next lookahead tick schedules
  /// them again with the current settings.
  ///
  /// Unlike [reset], this preserves [grooveEpoch] so the bar clock stays in
  /// sync with the transport. Called by [DrumGeneratorEngine.markDirty] so
  /// that a change (swing, humanisation, structure) is heard from the next
  /// bar instead of after the whole lookahead window.
  ///
  /// The bar being played is left alone. Scheduling it again would fire at
  /// once every hit whose time has already passed: a burst of drums each
  /// time a knob moves. Its note-offs stay too, so no note is left hanging.
  void refreshSchedule(int fromBar) {
    _scheduledBars.removeWhere((b) => b >= fromBar);
    // Only hits that have not sounded yet are dropped, with their note-offs.
    // A hit that already fired (a kick pushed ahead of the next bar) keeps
    // its note-off, so its note still ends.
    final dropped = _noteOns.where((h) => h.bar >= fromBar).toSet();
    _noteOns.removeWhere(dropped.contains);
    _noteOffs.removeWhere(dropped.contains);
  }
}

// ── DrumGeneratorEngine ───────────────────────────────────────────────────────

/// Transport-synchronised drum beat scheduler.
///
/// The engine maintains one [DrumGeneratorSession] per active slot and
/// pre-computes MIDI hits up to [_kLookaheadBars] bars ahead of the current
/// transport position.  A 10 ms `Timer.periodic` drains the hit queues and
/// dispatches note-on / note-off events to [AudioEngine].
///
/// All hit scheduling happens on the Dart event loop (single-threaded), so
/// no locks are needed.  The tick method is deliberately allocation-free:
/// all [ScheduledHit] objects are pre-allocated in [_scheduleBar].
class DrumGeneratorEngine extends ChangeNotifier {
  /// Reference to the global transport clock.
  final TransportEngine _transport;

  /// Reference to the audio engine for MIDI dispatch.
  final AudioEngine _engine;

  /// Active sessions, keyed by slot ID.
  final Map<String, DrumGeneratorSession> _sessions = {};

  /// The 10 ms scheduling tick timer.  Running only while transport is playing.
  Timer? _ticker;

  /// Whether the transport was playing on the last [_onTransportChanged] call.
  /// Used to detect play→stop and stop→play transitions.
  bool _wasPlaying = false;

  /// Optional callback fired (via [Timer.run]) after every mutation that
  /// changes persisted state — pattern selection, soundfont, swing override,
  /// humanisation amount, and structure config.
  ///
  /// Wired by [SplashScreen] to [ProjectService.autosave] so the project file
  /// stays in sync without requiring the user to manually save.
  VoidCallback? onChanged;

  /// Constructs a [DrumGeneratorEngine] and subscribes to the transport.
  DrumGeneratorEngine(this._transport, this._engine) {
    _transport.addListener(_onTransportChanged);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Ensures a [DrumGeneratorSession] exists for [slotId] with [instance].
  ///
  /// Called when a slot is added to the rack or restored from a project file.
  /// If a session already exists for [slotId] its instance is updated.
  /// Always initialises the drum MIDI channel with bank 128 (GM percussion).
  void ensureSession(String slotId, DrumGeneratorPluginInstance instance) {
    if (!_sessions.containsKey(slotId)) {
      final session = DrumGeneratorSession(instance);
      _sessions[slotId] = session;
      _resolvePattern(session);
      _initDrumChannel(session);
      // Notify only on first registration — the UI needs to redraw with
      // the newly resolved pattern name and controls.
      notifyListeners();
    } else {
      // Update the pattern if the instance changed.
      final existing = _sessions[slotId]!;
      final patternChanged =
          existing.instance.builtinPatternId != instance.builtinPatternId ||
          existing.instance.customPatternPath != instance.customPatternPath;
      if (patternChanged) {
        _resolvePattern(existing);
        notifyListeners();
      }
      // Re-apply bank 128 in case the channel was reset by another slot.
      // No notifyListeners — this is a silent MIDI-channel housekeeping call.
      _initDrumChannel(existing);
    }
  }

  /// Assigns a soundfont to the session's MIDI channel and re-applies the
  /// GM drum bank (128) so the channel keeps playing percussion.
  ///
  /// [path] must already be registered in [AudioEngine.loadedSoundfonts].
  /// Pass `null` to revert to the app-wide default soundfont.
  void setSoundfont(String slotId, String? path) {
    final session = _sessions[slotId];
    if (session == null) return;
    session.instance.soundfontPath = path;
    final channel = session.instance.midiChannel - 1;
    if (path != null) {
      _engine.assignSoundfontToChannel(channel, path);
    }
    // Always re-apply bank 128 after a soundfont change so the drum channel
    // stays mapped to the percussion bank, not the default melodic bank 0.
    _engine.assignPatchToChannel(channel, 0, bank: 128);
    notifyListeners();
    _notifyChanged();
  }

  /// The pattern the slot [slotId] is playing, or null before one loads.
  DrumPatternData? patternFor(String slotId) => _sessions[slotId]?.patternData;

  /// Where slot [slotId] is in its song form while playing (see
  /// [DrumGeneratorSession.formPosition]), or null for an unknown slot.
  ValueListenable<DrumFormPosition?>? formPositionFor(String slotId) =>
      _sessions[slotId]?.formPosition;

  /// Replaces the song form of slot [slotId]. Heard from the next bar when
  /// playing, like any other setting.
  void setSongForm(String slotId, DrumSongForm form) {
    final session = _sessions[slotId];
    if (session == null) return;
    session.instance.songForm = form;
    session._positionBar = -1; // the same bar may now be another block
    markDirty();
  }

  /// Removes the session for [slotId].
  ///
  /// Called when the slot is deleted from the rack.  Sends all-notes-off
  /// on the slot's MIDI channel to avoid stuck notes.
  void removeSession(String slotId) {
    final session = _sessions.remove(slotId);
    if (session != null) {
      _sendAllNotesOff(session);
      session.formPosition.dispose();
    }
    notifyListeners();
  }

  /// Notifies all listeners that a slot's configuration has changed, and
  /// forces a lookahead reschedule so the change takes effect immediately.
  ///
  /// Called by the UI when the user modifies properties on
  /// [DrumGeneratorPluginInstance] directly (swing, humanisation, structure
  /// config) without going through a dedicated setter.
  ///
  /// Without the reschedule, bars already queued in the 2-bar lookahead
  /// would play with the old parameters — making the slider feel broken.
  void markDirty() {
    // If transport is playing, flush the lookahead caches so the next ticker
    // tick (≤ 10 ms away) re-schedules upcoming bars with the new parameters.
    if (_wasPlaying) {
      for (final session in _sessions.values) {
        session.refreshSchedule(_currentBar(session) + 1);
      }
    }
    notifyListeners();
    _notifyChanged();
  }

  /// Fires [onChanged] asynchronously (via [Timer.run]) so that the callback
  /// runs after the current frame — the same pattern used by [RackState].
  void _notifyChanged() => Timer.run(() => onChanged?.call());

  /// Activates or deactivates a slot identified by [slotId].
  void setActive(String slotId, bool active) {
    final session = _sessions[slotId];
    if (session == null) return;
    session.instance.isActive = active;
    notifyListeners();
    _notifyChanged();
  }

  /// Loads a bundled pattern by [patternId] for the session at [slotId].
  void loadBuiltinPattern(String slotId, String patternId) {
    final session = _sessions[slotId];
    if (session == null) return;
    session.instance.builtinPatternId = patternId;
    session.instance.customPatternPath = null;
    _resolvePattern(session);
    if (session.patternData != null) {
      _transport.timeSigNumerator = session.patternData!.timeSigNumerator;
      _transport.timeSigDenominator = session.patternData!.timeSigDenominator;
    }
    // Reset the session so the new pattern starts cleanly.
    session.reset();
    notifyListeners();
    _notifyChanged();
  }

  /// Loads a user `.gfdrum` file for the session at [slotId].
  ///
  /// [yaml] is the file's text and [filePath] where it came from. Both are
  /// stored on the instance: the text so the project plays the pattern
  /// wherever it is opened, the path to show where it came from.
  ///
  /// The pattern stays with this slot. It is not added to the shared
  /// registry, where a file named like a bundled pattern (`rock_basic.gfdrum`)
  /// would replace that pattern for every slot.
  ///
  /// Returns false, changing nothing, when [yaml] is not a valid pattern.
  bool loadCustomPattern(String slotId, String yaml, String filePath) {
    final session = _sessions[slotId];
    if (session == null) return false;
    final patternData = parseCustomPattern(yaml, filePath);
    if (patternData == null) return false;

    session.instance.customPatternPath = filePath;
    session.instance.customPatternYaml = yaml;
    session.instance.builtinPatternId = null;
    session.patternData = patternData;

    // Automatically sync the transport to the new pattern's time signature.
    _transport.timeSigNumerator = patternData.timeSigNumerator;
    _transport.timeSigDenominator = patternData.timeSigDenominator;

    session.reset();
    notifyListeners();
    _notifyChanged();
    return true;
  }

  /// Parses a user pattern, giving it an id that cannot collide with a
  /// bundled one (`custom:` followed by the file name without extension).
  static DrumPatternData? parseCustomPattern(String yaml, String filePath) {
    final stem = filePath.split(RegExp(r'[/\\]')).last.replaceAll('.gfdrum', '');
    return DrumPatternParser.parse(yaml, id: 'custom:$stem');
  }

  // ── Transport listener ────────────────────────────────────────────────────

  /// Called whenever [TransportEngine] notifies listeners.
  ///
  /// Detects play/stop transitions and reacts accordingly:
  /// - stop → send all-notes-off and cancel the tick timer.
  /// - play → reset all active sessions and start the tick timer.
  void _onTransportChanged() {
    final isPlaying = _transport.isPlaying;

    if (_wasPlaying && !isPlaying) {
      // Transport just stopped.
      _stopTicker();
      for (final session in _sessions.values) {
        _sendAllNotesOff(session);
        session.reset();
      }
    }

    if (!_wasPlaying && isPlaying) {
      // Transport just started.  Capture the current beat position as the
      // epoch anchor so all scheduled hits are in the future, not the past.
      // The transport fires beat 1 before notifying listeners, so positionInBeats
      // is already 1.0 here — epoch-relative scheduling ensures count-in hits
      // land at grooveEpoch, grooveEpoch+1, …, never at beats < current.
      final epoch = _transport.positionInBeats;
      for (final session in _sessions.values) {
        session.reset();
        session.grooveEpoch = epoch;
      }
      _startTicker();
    }

    _wasPlaying = isPlaying;
  }

  // ── Ticker management ─────────────────────────────────────────────────────

  /// Starts the 10 ms scheduling tick timer.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(milliseconds: _kTickMs),
      (_) => _tick(),
    );
  }

  /// Cancels the tick timer.
  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // ── Main tick ─────────────────────────────────────────────────────────────

  /// Runs every 10 ms while the transport is playing.
  ///
  /// For each active session:
  /// 1. Pre-schedules hits up to [_kLookaheadBars] bars ahead.
  /// 2. Drains note-offs whose [ScheduledHit.noteOffBeat] has passed.
  /// 3. Fires note-ons whose [ScheduledHit.beatTimestamp] has passed.
  ///
  /// No new objects are allocated here — only list reads and engine calls.
  void _tick() {
    if (!_transport.isPlaying) return;
    final currentBeat = _transport.positionInBeats;

    for (final session in _sessions.values) {
      if (!session.instance.isActive) continue;
      if (session.patternData == null) continue;

      _scheduleLookahead(session, currentBeat);
      _drainNoteOffs(session, currentBeat);
      _drainNoteOns(session, currentBeat);
      if (_followForm(session, currentBeat)) {
        // The song is over and its ending stops the transport. Stopping
        // notifies [_onTransportChanged], which silences every slot.
        _transport.stop();
        return;
      }
    }
  }

  /// Updates [DrumGeneratorSession.formPosition] when a new bar starts, and
  /// returns true once the song form's ending is over and asks for the
  /// transport to stop.
  bool _followForm(DrumGeneratorSession session, double currentBeat) {
    final pattern = session.patternData!;
    final barDuration =
        pattern.timeSigNumerator * 4.0 / pattern.timeSigDenominator;
    final bar = _barAt(session, currentBeat, barDuration);
    if (bar == session._positionBar) return false;
    session._positionBar = bar;

    final form = session.instance.songForm;
    if (!form.isActive) {
      session.formPosition.value = null;
      return false;
    }
    final rel = bar - DrumArranger.introBarCount(
        session.instance.structureConfig, pattern);
    final spot = DrumFormArranger.locate(rel, form, pattern);
    session.formPosition.value =
        spot == null ? null : DrumFormPosition(spot.block, spot.bar);
    return form.hasEnding &&
        form.blocks.last.stopTransport &&
        rel >= DrumFormArranger.formBars(form, pattern);
  }

  // ── Lookahead scheduling ──────────────────────────────────────────────────

  /// Ensures bars up to [_kLookaheadBars] ahead of [currentBeat] are scheduled.
  ///
  /// Uses epoch-relative beat arithmetic so bar 0 always starts at
  /// [DrumGeneratorSession.grooveEpoch] rather than at transport beat 0.
  /// This prevents count-in hits from being scheduled in the past at
  /// transport start (where beat position has already advanced to 1.0).
  void _scheduleLookahead(DrumGeneratorSession session, double currentBeat) {
    final pattern = session.patternData!;
    // Correct bar duration in beats: timeSig numerator × (4 ÷ denominator).
    // For 4/4 → 4.0, for 6/8 → 3.0, for 3/4 → 3.0 beats per bar.
    final barDuration =
        pattern.timeSigNumerator * 4.0 / pattern.timeSigDenominator;

    final currentBar = _barAt(session, currentBeat, barDuration);

    for (var bar = currentBar; bar <= currentBar + _kLookaheadBars; bar++) {
      if (session._scheduledBars.contains(bar)) continue;
      _scheduleBar(session, bar);
    }
  }

  /// The bar (from 0, count-in included) that [session] is playing now.
  int _currentBar(DrumGeneratorSession session) {
    final pattern = session.patternData;
    if (pattern == null) return 0;
    final barDuration =
        pattern.timeSigNumerator * 4.0 / pattern.timeSigDenominator;
    return _barAt(session, _transport.positionInBeats, barDuration);
  }

  /// The bar of [session] that contains transport beat [beat].
  int _barAt(DrumGeneratorSession session, double beat, double barDuration) {
    // Convert absolute beat to epoch-relative beat, then find the bar.
    final relativeBeat = beat - session.grooveEpoch;
    // Clamp to 0: floating-point rounding can give tiny negative values on
    // the very first tick, which would schedule bar -1 unexpectedly.
    return (relativeBeat / barDuration).floor().clamp(0, 0x7fffffff);
  }

  // ── Bar scheduling ────────────────────────────────────────────────────────

  /// Pre-computes and enqueues all [ScheduledHit]s for one absolute bar.
  ///
  /// Steps:
  /// 1. Determine which section to play based on structure config + bar index.
  /// 2. Pick a variation (weighted random or sequence index).
  /// 3. For each non-rest step: compute humanised beat position and velocity.
  /// 4. Insert hits into the sorted [DrumGeneratorSession._noteOns] and
  ///    [DrumGeneratorSession._noteOffs] lists.
  void _scheduleBar(DrumGeneratorSession session, int absoluteBar) {
    session._scheduledBars.add(absoluteBar);

    final pattern = session.patternData!;
    final barDuration =
        pattern.timeSigNumerator * 4.0 / pattern.timeSigDenominator;

    // Beat position of bar start, anchored to the session's groove epoch.
    // Bar 0 starts exactly at grooveEpoch (transport position when play was
    // pressed); subsequent bars step forward by barDuration each.
    final barStartBeat = session.grooveEpoch + absoluteBar * barDuration;

    // The arranger decides what this bar is: groove, fill, break or
    // count-in, which bar of it, and whether a crash lands on it.
    final plan = DrumArranger.planBar(
      bar: absoluteBar,
      config: session.instance.structureConfig,
      pattern: pattern,
      seed: session.seed,
      form: session.instance.songForm,
    );
    if (plan.section == DrumBarPlan.silence) return;
    // A "drop" bar plays the first step of the crash section: the single
    // hit on beat 1 that starts a break or ends a song.
    final isDrop = plan.section == DrumBarPlan.drop;
    final section = isDrop
        ? pattern.sections['crash']
        : pattern.sections[plan.section] ?? pattern.sections['groove'];
    if (section == null) return;

    if (plan.crash) {
      _scheduleSectionBar(
        session,
        pattern,
        pattern.sections['crash']!,
        absoluteBar,
        barStartBeat,
        plan: plan,
        isCrashOverlay: true,
      );
    }

    _scheduleSectionBar(
      session,
      pattern,
      section,
      absoluteBar,
      barStartBeat,
      plan: plan,
      isCrashOverlay: false,
      firstStepOnly: isDrop,
    );
  }

  /// Schedules hits for a specific section bar.
  void _scheduleSectionBar(
    DrumGeneratorSession session,
    DrumPatternData pattern,
    DrumSection section,
    int absoluteBar,
    double barStartBeat, {
    required DrumBarPlan plan,
    required bool isCrashOverlay,
    bool firstStepOnly = false,
  }) {
    // Count-in sections use hit-based generation, not step grids.
    if (section.kind == DrumSectionKind.countIn) {
      _scheduleCountIn(session, pattern, section, barStartBeat, absoluteBar);
      return;
    }

    // Resolve the step grid map for this bar. The crash overlay is a single
    // bar of its own, so it always starts at its first bar.
    final resolved = resolveStepGrid(
      section,
      barInSection: isCrashOverlay ? 0 : plan.barInSection,
      variationSeed: plan.variationSeed,
      variation: isCrashOverlay ? null : plan.variation,
    );
    if (resolved == null) return;
    final gridMap = firstStepOnly ? firstStepOf(resolved) : resolved;

    // Determine effective swing ratio.
    final swingRatio = session.instance.swingOverride ??
        pattern.feel.defaultSwingRatio;

    // Step duration in beats: bar duration divided by the number of steps.
    // For 4/4 at 16 steps: 4.0/16 = 0.25 beats.  For 6/8 at 12 steps:
    // 3.0/12 = 0.25 beats (each step = a 16th note in both cases).
    final barDur = pattern.timeSigNumerator * 4.0 / pattern.timeSigDenominator;
    final stepDuration = barDur / pattern.resolution;

    // Humanisation amounts, scaled by the slot's humanization knob.
    final humanFactor = session.instance.humanizationAmount;

    // Per-bar seeded random ensures same bar always produces same humanisation,
    // preventing flicker when the lookahead re-schedules the same bar.
    final barSeed = absoluteBar * 31 + (isCrashOverlay ? 7919 : 0);
    final rng = Random(barSeed);

    for (final entry in gridMap.entries) {
      final instrName = entry.key;
      final grid = entry.value;
      final instrDef = pattern.instruments[instrName];
      if (instrDef == null) continue;

      _scheduleInstrumentGrid(
        session: session,
        bar: absoluteBar,
        velocityScale: isCrashOverlay ? 1.0 : plan.velocityScale,
        instrDef: instrDef,
        grid: grid,
        barStartBeat: barStartBeat,
        stepDuration: stepDuration,
        swingRatio: swingRatio,
        humanFactor: humanFactor,
        rng: rng,
        humanization: pattern.humanization,
      );
    }
  }

  /// Resolves the step grid map to play for one bar of [section].
  ///
  /// For `sequence` sections: the bar at [barInSection], so a two-bar
  /// pattern starts on its first bar whatever came before (a count-in, a
  /// break).
  /// For `loop` sections: a weighted random variation drawn with
  /// [variationSeed]. The arranger keeps the seed for a whole phrase, so the
  /// same variation plays until the next fill. A [variation] name, chosen by
  /// a song-form block, wins over the draw when the section has it.
  @visibleForTesting
  static Map<String, String>? resolveStepGrid(
    DrumSection section, {
    required int barInSection,
    required int variationSeed,
    String? variation,
  }) {
    if (section.variations.isEmpty) return null;

    if (section.kind == DrumSectionKind.sequence) {
      final variation = section.variations.first;
      final barSeq = variation.barSequence;
      if (barSeq == null || barSeq.isEmpty) return null;
      return barSeq[barInSection.abs() % barSeq.length];
    }

    for (final v in section.variations) {
      if (v.name == variation) return v.stepGrids;
    }

    final totalWeight =
        section.variations.fold(0, (sum, v) => sum + v.weight);
    if (totalWeight == 0) return section.variations.first.stepGrids;

    var roll = Random(variationSeed).nextInt(totalWeight);
    for (final variation in section.variations) {
      roll -= variation.weight;
      if (roll < 0) return variation.stepGrids;
    }
    return section.variations.last.stepGrids;
  }

  /// Keeps only the first step of every grid in [grids]: what a drummer
  /// plays on beat 1 of the crash bar (the cymbal and the bass drum, or the
  /// style's own low drum and gong), and nothing after it.
  @visibleForTesting
  static Map<String, String> firstStepOf(Map<String, String> grids) => {
        for (final e in grids.entries)
          if (e.value.isNotEmpty && e.value[0] != '.')
            e.key: e.value[0] + '.' * (e.value.length - 1),
      };

  /// Schedules evenly-spaced hits for a count-in section.
  ///
  /// Generates [DrumSection.countInHits] notes evenly spread across the bar.
  void _scheduleCountIn(
    DrumGeneratorSession session,
    DrumPatternData pattern,
    DrumSection section,
    double barStartBeat,
    int bar,
  ) {
    final hits = section.countInHits ?? 4;
    final note = section.countInNote ?? 37;
    final barDuration =
        pattern.timeSigNumerator * 4.0 / pattern.timeSigDenominator;
    final beatInterval = barDuration / hits;
    final instrDef = DrumInstrumentDef(
      note: note,
      baseVelocity: 90,
      velocityRange: 8,
      timingJitter: 0.01,
      durationBeats: 0.08,
    );

    for (var i = 0; i < hits; i++) {
      final beatPos = barStartBeat + i * beatInterval;
      final noteOff = beatPos + instrDef.durationBeats;

      final hit = ScheduledHit(
        beatTimestamp: beatPos,
        noteOffBeat: noteOff,
        note: note,
        velocity: instrDef.baseVelocity,
        bar: bar,
      );
      _insertSortedNoteOn(session, hit);
      _insertSortedNoteOff(session, hit);
    }
  }

  /// Schedules hits for one instrument's step grid.
  ///
  /// Iterates through each character in [grid]:
  /// - Rests (`.`) are skipped.
  /// - Even-indexed steps receive a swing-ratio offset on odd positions.
  /// - Timing jitter and velocity randomisation are applied from [rng].
  void _scheduleInstrumentGrid({
    required DrumGeneratorSession session,
    required int bar,
    required double velocityScale,
    required DrumInstrumentDef instrDef,
    required String grid,
    required double barStartBeat,
    required double stepDuration,
    required double swingRatio,
    required double humanFactor,
    required Random rng,
    required DrumHumanizationDef humanization,
  }) {
    for (var step = 0; step < grid.length; step++) {
      final char = grid[step];
      final velScale = DrumPatternParser.velocityScale(char);
      if (velScale == 0.0) continue; // rest — skip

      // Base beat position on the step grid.
      var beat = barStartBeat + step * stepDuration;

      // Apply swing: odd steps (1, 3, 5…) are delayed by the swing offset.
      // Swing offset = (swingRatio - 0.5) * 2 * stepDuration.
      // At 0.5 (straight) the offset is 0; at 0.67 (triplet) it equals
      // one-third of a step duration, matching classic jazz swing feel.
      final isOddStep = step.isOdd;
      if (isOddStep && swingRatio > 0.5) {
        beat += (swingRatio - 0.5) * 2.0 * stepDuration;
      }

      // Apply the instrument's systematic offset, in beats: negative plays
      // ahead of the beat (a pushed kick), positive behind it (a lazy snare).
      beat += instrDef.rush;

      // Apply random timing jitter scaled by humanisation amount.
      final maxJitter = instrDef.timingJitter * humanFactor;
      if (maxJitter > 0) {
        final jitter = (rng.nextDouble() * 2.0 - 1.0) * maxJitter;
        beat += jitter;
      }

      // Compute humanised velocity. [velocityScale] is the phrase's dynamic
      // build: a little softer at its start, full at its end.
      final baseVel =
          (instrDef.baseVelocity * velScale * velocityScale).round();
      final maxVelJitter =
          (instrDef.velocityRange * humanFactor).round();
      final velJitter = maxVelJitter > 0
          ? rng.nextInt(maxVelJitter * 2 + 1) - maxVelJitter
          : 0;
      final velocity = (baseVel + velJitter).clamp(1, 127);

      final noteOff = beat + instrDef.durationBeats;

      final hit = ScheduledHit(
        beatTimestamp: beat,
        noteOffBeat: noteOff,
        note: instrDef.note,
        velocity: velocity,
        bar: bar,
      );
      _insertSortedNoteOn(session, hit);
      _insertSortedNoteOff(session, hit);
    }
  }

  // ── Queue drain ───────────────────────────────────────────────────────────

  /// Fires note-ons from the queue whose timestamp has arrived.
  void _drainNoteOns(DrumGeneratorSession session, double currentBeat) {
    final channel = session.instance.midiChannel - 1; // 0-indexed
    while (session._noteOns.isNotEmpty &&
        session._noteOns.first.beatTimestamp <= currentBeat) {
      final hit = session._noteOns.removeAt(0);
      _engine.playNote(
        channel: channel,
        key: hit.note,
        velocity: hit.velocity,
      );
    }
  }

  /// Fires note-offs from the queue whose timestamp has arrived.
  void _drainNoteOffs(DrumGeneratorSession session, double currentBeat) {
    final channel = session.instance.midiChannel - 1; // 0-indexed
    while (session._noteOffs.isNotEmpty &&
        session._noteOffs.first.noteOffBeat <= currentBeat) {
      final hit = session._noteOffs.removeAt(0);
      _engine.stopNote(channel: channel, key: hit.note);
    }
  }

  // ── Sorted list insertion ─────────────────────────────────────────────────

  /// Inserts [hit] into [session._noteOns] maintaining sort by beatTimestamp.
  void _insertSortedNoteOn(DrumGeneratorSession session, ScheduledHit hit) {
    final list = session._noteOns;
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].beatTimestamp <= hit.beatTimestamp) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    list.insert(lo, hit);
  }

  /// Inserts [hit] into [session._noteOffs] maintaining sort by noteOffBeat.
  void _insertSortedNoteOff(DrumGeneratorSession session, ScheduledHit hit) {
    final list = session._noteOffs;
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].noteOffBeat <= hit.noteOffBeat) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    list.insert(lo, hit);
  }

  // ── Channel initialisation ────────────────────────────────────────────────

  /// Sets the session's MIDI channel to GM drum bank 128, program 0
  /// (Standard Drum Kit).
  ///
  /// This is required because the default AudioEngine state uses bank 0
  /// (melodic instruments) for all channels.  Without this call, notes
  /// 35–81 on a melodic channel produce piano / string sounds instead of
  /// kick drums and cymbals.
  void _initDrumChannel(DrumGeneratorSession session) {
    final channel = session.instance.midiChannel - 1; // 0-indexed
    _engine.assignPatchToChannel(channel, 0, bank: 128);
  }

  // ── Pattern resolution ────────────────────────────────────────────────────

  /// Resolves the pattern data for [session] from the registry.
  ///
  /// After resolution, propagates the pattern's time signature to the
  /// transport (when not playing) so the metronome LED and bar counter
  /// reflect the drum pattern's metre — e.g. 6/8 for Bossa Nova.
  void _resolvePattern(DrumGeneratorSession session) {
    final builtinId = session.instance.builtinPatternId;
    final customPath = session.instance.customPatternPath;

    if (builtinId != null) {
      session.patternData = DrumPatternRegistry.instance.find(builtinId);
    } else if (customPath != null) {
      // A user pattern is read back from the text saved with the project.
      // Projects saved before that only have the path, which cannot be read
      // here; such a slot stays silent until the file is loaded again.
      final yaml = session.instance.customPatternYaml;
      session.patternData =
          yaml == null ? null : parseCustomPattern(yaml, customPath);
    } else {
      // Fall back to the first available pattern.
      final all = DrumPatternRegistry.instance.all;
      if (all.isNotEmpty) {
        session.patternData = all.first;
        session.instance.builtinPatternId = all.first.id;
      }
    }

    // Propagate the pattern's time signature to the transport so the
    // metronome and bar display stay in sync with the drum pattern metre.
    if (session.patternData != null) {
      _syncTransportTimeSignature(session.patternData!);
    }
  }

  /// Applies [pattern]'s time signature to the transport when not playing.
  ///
  /// Changing time signature during playback would desync all scheduled hits,
  /// so we only apply when the transport is stopped.  The user can always
  /// override the transport time sig manually from the transport bar.
  void _syncTransportTimeSignature(DrumPatternData pattern) {
    if (_transport.isPlaying) return;
    _transport.timeSigNumerator = pattern.timeSigNumerator;
    _transport.timeSigDenominator = pattern.timeSigDenominator;
  }

  // ── MIDI helpers ──────────────────────────────────────────────────────────

  /// Sends all-notes-off (CC 123) on the session's MIDI channel.
  ///
  /// Called when transport stops or a slot is removed, to prevent stuck notes.
  void _sendAllNotesOff(DrumGeneratorSession session) {
    final channel = session.instance.midiChannel - 1; // 0-indexed
    // GM drum notes range 35–81; send individual note-offs for robustness.
    for (var note = 35; note <= 81; note++) {
      _engine.stopNote(channel: channel, key: note);
    }
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _transport.removeListener(_onTransportChanged);
    _stopTicker();
    super.dispose();
  }
}
