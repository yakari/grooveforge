import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/drum_generator_plugin_instance.dart';
import '../models/drum_pattern_data.dart';
import 'audio_engine.dart';
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

  /// Constructs a [ScheduledHit].
  const ScheduledHit({
    required this.beatTimestamp,
    required this.noteOffBeat,
    required this.note,
    required this.velocity,
  });
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

  /// Whether the last section played was a fill or break — used to trigger
  /// a crash on the following bar.
  bool _lastSectionWasFillOrBreak = false;

  /// Seeded random generator for the random fill-interval feature.
  /// Re-seeded at session reset so patterns feel different each play.
  late Random _randomFillInterval;

  /// The transport beat position at the moment this session's playback started.
  ///
  /// All bar timestamps are computed as `grooveEpoch + barIndex * barDuration`
  /// rather than as raw transport-absolute beats.  This prevents count-in hits
  /// from being in the "past" when the transport fires beat 1 immediately at
  /// position 1.0 on startup, which would cause all count-in notes to drain
  /// simultaneously on the very first scheduler tick.
  double grooveEpoch = 0.0;

  /// Constructs a [DrumGeneratorSession] for [instance].
  DrumGeneratorSession(this.instance) {
    _randomFillInterval = Random();
  }

  /// Resets all scheduling state so the session starts fresh from bar 0.
  void reset() {
    _scheduledBars.clear();
    _noteOns.clear();
    _noteOffs.clear();
    _lastSectionWasFillOrBreak = false;
    grooveEpoch = 0.0;
    // Re-seed so a new play gives fresh variation selection.
    _randomFillInterval = Random();
  }

  /// Clears the scheduled-bars cache and pending hit queues so the next
  /// lookahead tick re-schedules upcoming bars with current parameters.
  ///
  /// Unlike [reset], this preserves [grooveEpoch] so the bar clock stays in
  /// sync with the transport.  Called by [DrumGeneratorEngine.markDirty] so
  /// that parameter changes (swing override, humanisation amount) take effect
  /// within the next 10 ms tick instead of waiting for the current lookahead
  /// window to expire (~2 bars).
  void refreshSchedule() {
    _scheduledBars.clear();
    _noteOns.clear();
    _noteOffs.clear();
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

  /// Removes the session for [slotId].
  ///
  /// Called when the slot is deleted from the rack.  Sends all-notes-off
  /// on the slot's MIDI channel to avoid stuck notes.
  void removeSession(String slotId) {
    final session = _sessions.remove(slotId);
    if (session != null) {
      _sendAllNotesOff(session);
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
        session.refreshSchedule();
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
    // Reset the session so the new pattern starts cleanly.
    session.reset();
    notifyListeners();
    _notifyChanged();
  }

  /// Loads a parsed custom pattern for the session at [slotId].
  ///
  /// [patternData] must already be parsed by [DrumPatternParser].
  /// [filePath] is stored on the instance for project-file persistence.
  void loadCustomPattern(
    String slotId,
    DrumPatternData patternData,
    String filePath,
  ) {
    final session = _sessions[slotId];
    if (session == null) return;
    session.instance.customPatternPath = filePath;
    session.instance.builtinPatternId = null;
    // Register the custom pattern so it survives session resets.
    DrumPatternRegistry.instance.register(patternData);
    session.patternData = patternData;
    session.reset();
    notifyListeners();
    _notifyChanged();
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
    }
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

    // Convert absolute beat to epoch-relative beat, then find current bar.
    final relativeBeat = currentBeat - session.grooveEpoch;
    // Clamp to 0: floating-point rounding can give tiny negative values on
    // the very first tick, which would schedule bar -1 unexpectedly.
    final currentBar =
        (relativeBeat / barDuration).floor().clamp(0, 0x7fffffff);

    for (var bar = currentBar; bar <= currentBar + _kLookaheadBars; bar++) {
      if (session._scheduledBars.contains(bar)) continue;
      _scheduleBar(session, bar);
    }
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

    // Determine the section and variation for this bar.
    final sectionResult = _selectSection(session, absoluteBar);
    final sectionName = sectionResult.sectionName;
    final isFillOrBreak =
        sectionName == 'fill' || sectionName == 'break';
    final section = pattern.sections[sectionName];

    if (section == null) return;

    // Track fill/break for crash injection next bar.
    final wasLastFillOrBreak = session._lastSectionWasFillOrBreak;
    session._lastSectionWasFillOrBreak = isFillOrBreak;

    // If the previous bar was a fill/break and crash_after_fill is enabled,
    // overlay the crash section on this bar.
    if (wasLastFillOrBreak &&
        session.instance.structureConfig.crashAfterFill &&
        pattern.sections.containsKey('crash')) {
      _scheduleSectionBar(
        session,
        pattern,
        pattern.sections['crash']!,
        absoluteBar,
        barStartBeat,
        isCrashOverlay: true,
      );
    }

    _scheduleSectionBar(
      session,
      pattern,
      section,
      absoluteBar,
      barStartBeat,
      isCrashOverlay: false,
    );
  }

  /// Schedules hits for a specific section bar.
  void _scheduleSectionBar(
    DrumGeneratorSession session,
    DrumPatternData pattern,
    DrumSection section,
    int absoluteBar,
    double barStartBeat, {
    required bool isCrashOverlay,
  }) {
    // Count-in sections use hit-based generation, not step grids.
    if (section.kind == DrumSectionKind.countIn) {
      _scheduleCountIn(session, pattern, section, barStartBeat);
      return;
    }

    // Resolve the step grid map for this bar.
    final gridMap = _resolveStepGrid(section, absoluteBar);
    if (gridMap == null) return;

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

  /// Resolves the step grid map for [section] at [absoluteBar].
  ///
  /// For `sequence` sections: picks the bar grid by index mod sequence length.
  /// For `loop` sections: picks a weighted random variation (seeded by bar).
  Map<String, String>? _resolveStepGrid(DrumSection section, int absoluteBar) {
    if (section.variations.isEmpty) return null;

    if (section.kind == DrumSectionKind.sequence) {
      final variation = section.variations.first;
      final barSeq = variation.barSequence;
      if (barSeq == null || barSeq.isEmpty) return null;
      final idx = absoluteBar.abs() % barSeq.length;
      return barSeq[idx];
    }

    // Weighted random selection, seeded by bar index for determinism.
    final totalWeight =
        section.variations.fold(0, (sum, v) => sum + v.weight);
    if (totalWeight == 0) return section.variations.first.stepGrids;

    final rng = Random(absoluteBar * 31 + 137);
    var roll = rng.nextInt(totalWeight);
    for (final variation in section.variations) {
      roll -= variation.weight;
      if (roll < 0) return variation.stepGrids;
    }
    return section.variations.last.stepGrids;
  }

  /// Schedules evenly-spaced hits for a count-in section.
  ///
  /// Generates [DrumSection.countInHits] notes evenly spread across the bar.
  void _scheduleCountIn(
    DrumGeneratorSession session,
    DrumPatternData pattern,
    DrumSection section,
    double barStartBeat,
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

      // Apply systematic instrument rush (positive = early, negative = late).
      beat += instrDef.rush;

      // Apply random timing jitter scaled by humanisation amount.
      final maxJitter = instrDef.timingJitter * humanFactor;
      if (maxJitter > 0) {
        final jitter = (rng.nextDouble() * 2.0 - 1.0) * maxJitter;
        beat += jitter;
      }

      // Compute humanised velocity.
      final baseVel = (instrDef.baseVelocity * velScale).round();
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
      );
      _insertSortedNoteOn(session, hit);
      _insertSortedNoteOff(session, hit);
    }
  }

  // ── Section selection ─────────────────────────────────────────────────────

  /// Determines which section name to play for [absoluteBar].
  ///
  /// Bar indices start at 0 and are epoch-relative (0 = first bar after play
  /// was pressed, which may be a count-in bar if intro is enabled).
  ///
  /// Logic (in priority order):
  /// 1. Intro / count-in phase bars (0 … introBars-1) → `'intro'` section.
  /// 2. Fill bar → `'fill'` section.
  /// 3. Break bar (random seeded) → `'break'` section.
  /// 4. Default → `'groove'` section.
  _SectionSelection _selectSection(
    DrumGeneratorSession session,
    int absoluteBar,
  ) {
    final config = session.instance.structureConfig;
    final pattern = session.patternData!;
    final introBars = _introBarCount(config, pattern);

    // Intro / count-in phase: first introBars bars play the 'intro' section
    // (which may be a countIn kind, generating evenly-spaced rimshot clicks).
    if (absoluteBar < introBars) {
      if (pattern.sections.containsKey('intro')) {
        return const _SectionSelection('intro');
      }
      // Pattern has no 'intro' section — fall through to groove.
    }

    final relativeBar = absoluteBar - introBars;
    final fillEvery = _fillInterval(session);

    // Fill: last bar of each fill-interval cycle.
    if (fillEvery > 0 &&
        (relativeBar + 1) % fillEvery == 0 &&
        pattern.sections.containsKey('fill')) {
      return const _SectionSelection('fill');
    }

    // Break: random seeded per-bar check.
    if (config.breakFrequency != DrumBreakFrequency.none &&
        pattern.sections.containsKey('break') &&
        _isBreakBar(absoluteBar, config.breakFrequency)) {
      return const _SectionSelection('break');
    }

    return const _SectionSelection('groove');
  }

  /// Returns the number of intro bars for [config] given [pattern].
  ///
  /// The returned value is the number of bars (starting at bar 0) that use
  /// the `'intro'` section before the groove begins.
  int _introBarCount(DrumStructureConfig config, DrumPatternData pattern) {
    switch (config.introType) {
      case DrumIntroType.none:
        return 0;
      case DrumIntroType.countIn1:
        // One bar of evenly-spaced click/rimshot before groove.
        return 1;
      case DrumIntroType.countIn2:
        // Two bars: beat 1–4, beat 5–8 (quarter-note clicks), then groove.
        return 2;
      case DrumIntroType.chopsticks:
        // Chopsticks = one bar of rimshot clicks, same as countIn1.
        // Sound difference (note, velocity) is defined in the .gfdrum intro
        // section; the bar count is identical.
        return 1;
    }
  }

  /// Returns the fill interval in bars (distance between fills).
  int _fillInterval(DrumGeneratorSession session) {
    final freq = session.instance.structureConfig.fillFrequency;
    if (freq == DrumFillFrequency.off) return -1;
    if (freq == DrumFillFrequency.random) {
      // Derive a deterministic interval from the session's seeded random.
      // Range 8–24 bars, changes every play session.
      return 8 + session._randomFillInterval.nextInt(17);
    }
    return freq.bars;
  }

  /// Returns true if [absoluteBar] qualifies as a break bar.
  ///
  /// Uses a seeded deterministic check so the same transport position always
  /// produces the same result (prevents re-scheduling discrepancies).
  bool _isBreakBar(int absoluteBar, DrumBreakFrequency freq) {
    // Use a deterministic threshold based on frequency.
    const thresholds = {
      DrumBreakFrequency.rare: 0.04,
      DrumBreakFrequency.occasional: 0.08,
      DrumBreakFrequency.frequent: 0.15,
    };
    final threshold = thresholds[freq] ?? 0.0;
    final r = Random(absoluteBar * 7919).nextDouble();
    return r < threshold;
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
      // Custom patterns are registered under their file path stem.
      final stem = customPath.split('/').last.replaceAll('.gfdrum', '');
      session.patternData = DrumPatternRegistry.instance.find(stem);
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

// ── Private helper type ───────────────────────────────────────────────────────

/// Simple value type returned by [DrumGeneratorEngine._selectSection].
class _SectionSelection {
  /// The name of the section to play (e.g. `'groove'`, `'fill'`).
  final String sectionName;

  const _SectionSelection(this.sectionName);
}
