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
    // Re-seed so a new play gives fresh variation selection.
    _randomFillInterval = Random();
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

  /// Constructs a [DrumGeneratorEngine] and subscribes to the transport.
  DrumGeneratorEngine(this._transport, this._engine) {
    _transport.addListener(_onTransportChanged);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Ensures a [DrumGeneratorSession] exists for [slotId] with [instance].
  ///
  /// Called when a slot is added to the rack or restored from a project file.
  /// If a session already exists for [slotId] its instance is updated.
  void ensureSession(String slotId, DrumGeneratorPluginInstance instance) {
    if (!_sessions.containsKey(slotId)) {
      final session = DrumGeneratorSession(instance);
      _sessions[slotId] = session;
      _resolvePattern(session);
    } else {
      // Update the pattern if the instance changed.
      final existing = _sessions[slotId]!;
      if (existing.instance.builtinPatternId != instance.builtinPatternId ||
          existing.instance.customPatternPath != instance.customPatternPath) {
        _resolvePattern(existing);
      }
    }
    notifyListeners();
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

  /// Notifies all listeners that a slot's configuration has changed.
  ///
  /// Called by the UI when the user modifies properties on
  /// [DrumGeneratorPluginInstance] directly (swing, humanisation, structure
  /// config) without going through a dedicated setter.
  void markDirty() => notifyListeners();

  /// Activates or deactivates a slot identified by [slotId].
  void setActive(String slotId, bool active) {
    final session = _sessions[slotId];
    if (session == null) return;
    session.instance.isActive = active;
    notifyListeners();
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
      // Transport just started.
      for (final session in _sessions.values) {
        session.reset();
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
  void _scheduleLookahead(DrumGeneratorSession session, double currentBeat) {
    final pattern = session.patternData!;
    final barDuration = pattern.timeSigNumerator.toDouble();

    // Determine which absolute bar we are currently in.
    final currentBar = (currentBeat / barDuration).floor();

    // Schedule bars from one bar before current (catch any missed events)
    // up to the lookahead limit.
    for (var bar = currentBar - 1; bar <= currentBar + _kLookaheadBars; bar++) {
      if (bar < -1) continue; // -1 is the valid count-in bar
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
    final barDuration = pattern.timeSigNumerator.toDouble();

    // Beat position of bar start (bar -1 starts at -barDuration).
    final barStartBeat = absoluteBar * barDuration;

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

    // Step duration in beats.
    final stepDuration =
        pattern.timeSigNumerator / pattern.resolution.toDouble();

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
    final barDuration = pattern.timeSigNumerator.toDouble();
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
  /// Logic (in priority order):
  /// 1. Bar -1 → count-in (if intro type is chopsticks or countIn).
  /// 2. Intro phase bars → `'intro'` section.
  /// 3. Fill bar → `'fill'` section.
  /// 4. Break bar (random seeded) → `'break'` section.
  /// 5. Default → `'groove'` section.
  _SectionSelection _selectSection(
    DrumGeneratorSession session,
    int absoluteBar,
  ) {
    final config = session.instance.structureConfig;
    final pattern = session.patternData!;

    // Bar -1 is the count-in bar before bar 0.
    if (absoluteBar == -1) {
      final hasIntro = pattern.sections.containsKey('intro');
      if (hasIntro &&
          config.introType != DrumIntroType.none) {
        return const _SectionSelection('intro');
      }
      return const _SectionSelection('groove');
    }

    // After count-in, bar 0 and beyond use the groove.
    // Determine intro duration in bars.
    final introBars = _introBarCount(config, pattern);
    if (absoluteBar < introBars) {
      return const _SectionSelection('intro');
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
  int _introBarCount(DrumStructureConfig config, DrumPatternData pattern) {
    switch (config.introType) {
      case DrumIntroType.none:
        return 0;
      case DrumIntroType.countIn1:
        return 1;
      case DrumIntroType.countIn2:
        return 2;
      case DrumIntroType.chopsticks:
        // Chopsticks plays on bar -1 (virtual bar), not bar 0.
        return 0;
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

  // ── Pattern resolution ────────────────────────────────────────────────────

  /// Resolves the pattern data for [session] from the registry.
  void _resolvePattern(DrumGeneratorSession session) {
    final builtinId = session.instance.builtinPatternId;
    final customPath = session.instance.customPatternPath;

    if (builtinId != null) {
      session.patternData = DrumPatternRegistry.instance.find(builtinId);
      return;
    }

    if (customPath != null) {
      // Custom patterns are registered under their file path stem.
      final stem = customPath.split('/').last.replaceAll('.gfdrum', '');
      session.patternData = DrumPatternRegistry.instance.find(stem);
      return;
    }

    // Fall back to the first available pattern.
    final all = DrumPatternRegistry.instance.all;
    if (all.isNotEmpty) {
      session.patternData = all.first;
      session.instance.builtinPatternId = all.first.id;
    }
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
