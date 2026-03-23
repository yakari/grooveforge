import '../gf_midi_event.dart';
import '../gf_transport_context.dart';
import 'gf_midi_node.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Chord type table
// ─────────────────────────────────────────────────────────────────────────────

/// Semitone offsets above the root for each chord type.
///
/// The root itself (offset 0) is **not** included because the original
/// incoming MIDI note always passes through unchanged and acts as the root.
///
/// Index mapping (matches the `chord_type` selector in `chord_expand.gfpd`):
/// | Index | Name         | Intervals (semitones above root)          |
/// |-------|--------------|-------------------------------------------|
/// | 0     | Major        | major 3rd (4), perfect 5th (7)            |
/// | 1     | Minor        | minor 3rd (3), perfect 5th (7)            |
/// | 2     | Diminished   | minor 3rd (3), diminished 5th (6)         |
/// | 3     | Augmented    | major 3rd (4), augmented 5th (8)          |
/// | 4     | Sus2         | major 2nd (2), perfect 5th (7)            |
/// | 5     | Sus4         | perfect 4th (5), perfect 5th (7)          |
/// | 6     | Dominant 7   | M3 (4), P5 (7), minor 7th (10)            |
/// | 7     | Major 7      | M3 (4), P5 (7), major 7th (11)            |
/// | 8     | Minor 7      | m3 (3), P5 (7), minor 7th (10)            |
/// | 9     | Half-dim 7   | m3 (3), dim5 (6), minor 7th (10)          |
/// | 10    | Diminished 7 | m3 (3), dim5 (6), diminished 7th (9)      |
const List<List<int>> _kChordIntervals = [
  [4, 7],      // 0 — Major
  [3, 7],      // 1 — Minor
  [3, 6],      // 2 — Diminished
  [4, 8],      // 3 — Augmented
  [2, 7],      // 4 — Sus2
  [5, 7],      // 5 — Sus4
  [4, 7, 10],  // 6 — Dominant 7
  [4, 7, 11],  // 7 — Major 7
  [3, 7, 10],  // 8 — Minor 7
  [3, 6, 10],  // 9 — Half-dim 7
  [3, 6, 9],   // 10 — Diminished 7
];

// ─────────────────────────────────────────────────────────────────────────────
//  TransposeNode  ("transpose")
// ─────────────────────────────────────────────────────────────────────────────

/// Shifts all note-on/note-off pitches by a fixed number of semitones.
///
/// **Node type key**: `"transpose"`
///
/// **Parameters**
/// | name       | normalised range | semantic range       |
/// |------------|-----------------|----------------------|
/// | semitones  | 0.0 → 1.0       | −24 → +24 semitones  |
///
/// The default normalised value of 0.5 maps to 0 semitones (no shift).
/// Events that are not note-on/note-off pass through unchanged.
class TransposeNode extends GFMidiNode {
  /// Semitone shift in the range [−24, +24]. Updated atomically from UI thread.
  int _semitones = 0;

  TransposeNode(super.nodeId);

  @override
  void initialize(GFMidiNodeContext context) {
    // No host state needed — transpose is self-contained.
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    if (paramName == 'semitones') {
      // Map [0, 1] → [−24, +24] semitones.
      _semitones = ((normalizedValue * 48) - 24).round();
    }
  }

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    if (_semitones == 0) return events; // fast path — nothing to do

    return events.map((e) {
      if (!e.isNoteOn && !e.isNoteOff) return e; // non-note events pass through

      final shifted = (e.data1 + _semitones).clamp(0, 127);
      return TimestampedMidiEvent(
        ppqPosition: e.ppqPosition,
        status: e.status,
        data1: shifted,
        data2: e.data2,
      );
    }).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  GateNode  ("gate")
// ─────────────────────────────────────────────────────────────────────────────

/// Filters out notes whose velocity falls below a threshold.
///
/// **Node type key**: `"gate"`
///
/// **Parameters**
/// | name        | normalised range | semantic range   |
/// |-------------|-----------------|------------------|
/// | minVelocity | 0.0 → 1.0       | 0 → 127 velocity |
///
/// Note-on events with `velocity < minVelocity` are suppressed. The
/// corresponding note-off events are also suppressed so no stuck notes occur.
/// Events that are not note-on/note-off pass through unchanged.
class GateNode extends GFMidiNode {
  /// Minimum velocity (0–127) for a note to pass the gate.
  int _minVelocity = 0;

  /// Pitches currently gated (suppressed note-on received, note-off pending).
  ///
  /// Stored per channel: `_gated[channel]` is the set of active gated pitches.
  final List<Set<int>> _gated = List.generate(16, (_) => {});

  GateNode(super.nodeId);

  @override
  void initialize(GFMidiNodeContext context) {
    for (final s in _gated) { s.clear(); }
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    if (paramName == 'minVelocity') {
      _minVelocity = (normalizedValue * 127).round();
    }
  }

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    if (_minVelocity == 0) return events; // fast path — gate fully open

    final output = <TimestampedMidiEvent>[];
    for (final e in events) {
      if (e.isNoteOn) {
        _processGateNoteOn(e, output);
      } else if (e.isNoteOff) {
        _processGateNoteOff(e, output);
      } else {
        output.add(e); // CC, pitch-bend, etc. always pass through
      }
    }
    return output;
  }

  void _processGateNoteOn(
    TimestampedMidiEvent e,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = e.midiChannel;
    if (e.data2 < _minVelocity) {
      // Velocity too low — suppress and remember for matching note-off.
      _gated[ch].add(e.data1);
    } else {
      output.add(e);
    }
  }

  void _processGateNoteOff(
    TimestampedMidiEvent e,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = e.midiChannel;
    final wasGated = _gated[ch].remove(e.data1);
    // Only forward the note-off if the note-on was forwarded (not gated).
    if (!wasGated) output.add(e);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  HarmonizeNode  ("harmonize")
// ─────────────────────────────────────────────────────────────────────────────

/// Adds harmony voices above each incoming note, optionally locked to the
/// host's active Jam Mode scale.
///
/// **Node type key**: `"harmonize"`
///
/// **Parameters**
/// | name         | normalised range | semantic meaning                          |
/// |--------------|-----------------|-------------------------------------------|
/// | interval1    | 0.0 → 1.0       | 1st harmony offset: 0–24 semitones (0=off)|
/// | interval2    | 0.0 → 1.0       | 2nd harmony offset: 0–24 semitones (0=off)|
/// | snapToScale  | 0.0 / 1.0       | 0 = chromatic, 1 = snap to host scale     |
///
/// **Note-off tracking**
/// The node stores a map of `original pitch → [harmony pitches emitted]` so
/// that note-offs always match the note-ons that were sent, even if the
/// interval parameters change between note-on and note-off.
///
/// **Scale snapping**
/// When `snapToScale` is on and the host's Jam Mode provides a pitch-class
/// set, harmony pitches are moved to the nearest allowed pitch class
/// (down-first tie-breaking).
class HarmonizeNode extends GFMidiNode {
  /// 1st harmony interval in semitones (0 = off).
  int _interval1 = 0;

  /// 2nd harmony interval in semitones (0 = off).
  int _interval2 = 0;

  /// Whether to snap harmony pitches to the host scale.
  bool _snapToScale = false;

  /// Callback from [GFMidiNodeContext] — may return null when Jam Mode is off.
  Set<int>? Function() _scaleProvider = () => null;

  /// Note-off tracking: maps original pitch (per channel) to the harmony
  /// pitches that were emitted in the corresponding note-on.
  ///
  /// Structure: `_activeHarmonies[channel][originalPitch] = [harmonyPitch1, ...]`
  ///
  /// This guarantees that note-offs are always symmetric with their note-ons,
  /// even when [_interval1] / [_interval2] change between note-on and note-off.
  final List<Map<int, List<int>>> _activeHarmonies =
      List.generate(16, (_) => {});

  HarmonizeNode(super.nodeId);

  @override
  void initialize(GFMidiNodeContext context) {
    _scaleProvider = context.scaleProvider;
    for (final m in _activeHarmonies) { m.clear(); }
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'interval1':
        // Map [0, 1] → [0, 24] semitones.
        _interval1 = (normalizedValue * 24).round();
      case 'interval2':
        _interval2 = (normalizedValue * 24).round();
      case 'snapToScale':
        _snapToScale = normalizedValue >= 0.5;
    }
  }

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    // Read the host scale once per block — avoids repeated callback overhead.
    final scale = _snapToScale ? _scaleProvider() : null;

    final output = <TimestampedMidiEvent>[];
    for (final e in events) {
      output.add(e); // original event always passes through

      if (e.isNoteOn) {
        _emitHarmonyNoteOns(e, scale, output);
      } else if (e.isNoteOff) {
        _emitHarmonyNoteOffs(e, output);
      }
    }
    return output;
  }

  /// Emit note-on events for all active harmony intervals.
  void _emitHarmonyNoteOns(
    TimestampedMidiEvent noteOn,
    Set<int>? scale,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = noteOn.midiChannel;
    final originalPitch = noteOn.data1;
    final emitted = <int>[];

    for (final interval in [_interval1, _interval2]) {
      if (interval == 0) continue; // interval 0 means "off"

      var pitch = (originalPitch + interval).clamp(0, 127);
      if (scale != null) pitch = _snapPitch(pitch, scale);

      emitted.add(pitch);
      output.add(TimestampedMidiEvent(
        ppqPosition: noteOn.ppqPosition,
        status: noteOn.status, // same channel
        data1: pitch,
        data2: noteOn.data2,
      ));
    }

    // Record which harmony pitches were emitted so note-offs match.
    _activeHarmonies[ch][originalPitch] = emitted;
  }

  /// Emit note-off events for the harmony pitches stored at note-on time.
  void _emitHarmonyNoteOffs(
    TimestampedMidiEvent noteOff,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = noteOff.midiChannel;
    final originalPitch = noteOff.data1;

    final harmonies = _activeHarmonies[ch].remove(originalPitch);
    if (harmonies == null) return;

    for (final pitch in harmonies) {
      output.add(TimestampedMidiEvent(
        ppqPosition: noteOff.ppqPosition,
        status: noteOff.status, // same status byte (NOTE OFF or NOTE ON vel=0)
        data1: pitch,
        data2: noteOff.data2,
      ));
    }
  }

  /// Snap [midiNote] to the nearest pitch class in [scale].
  ///
  /// Searches outward ±1 semitone at a time. Down-first tie-breaking: when
  /// both −n and +n land on an allowed pitch class, the lower note wins.
  /// This matches Western harmonic convention (prefer the bass note).
  ///
  /// Returns [midiNote] unchanged if no match is found within an octave
  /// (which can only happen if [scale] is empty — an unusual edge case).
  int _snapPitch(int midiNote, Set<int> scale) {
    final pc = midiNote % 12;
    if (scale.contains(pc)) return midiNote; // already in scale

    for (var delta = 1; delta <= 6; delta++) {
      final down = midiNote - delta;
      if (down >= 0 && scale.contains(down % 12)) return down;
      final up = midiNote + delta;
      if (up <= 127 && scale.contains(up % 12)) return up;
    }
    return midiNote; // fallback: scale empty or note at extreme range
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ChordExpandNode  ("chord_expand")
// ─────────────────────────────────────────────────────────────────────────────

/// Expands each incoming MIDI note into a full chord voicing.
///
/// The original note always passes through as the **root**. The node adds the
/// remaining chord tones above it based on the selected chord type and spread
/// mode.
///
/// **Node type key**: `"chord_expand"`
///
/// **Parameters**
/// | name         | normalised range | semantic meaning                              |
/// |--------------|-----------------|-----------------------------------------------|
/// | chordType    | 0.0 → 1.0       | Chord quality (index into 11-entry table)     |
/// | spread       | 0.0 → 1.0       | Voicing width: Close / Open / Wide (0–2)      |
/// | snapToScale  | 0.0 / 1.0       | 0 = chromatic, 1 = snap to host Jam Mode scale|
///
/// **Spread modes**
/// - **Close (0)**: all chord tones stacked above root within one octave.
///   Example — C major: C4 + E4 + G4.
/// - **Open (1)**: every other non-root tone (0-indexed) is raised an octave,
///   producing a wider, more airy voicing.
///   Example — C major: C4 + E4 + G5.
/// - **Wide (2)**: all non-root tones raised an octave above the close
///   position.
///   Example — C major: C4 + E5 + G5.
///
/// **Note-off tracking**
/// Chord pitches actually emitted for each root note are remembered so that
/// note-offs always match the note-ons that were sent, even when the user
/// changes chord type or spread while notes are held.
///
/// **Scale snapping**
/// When `snapToScale` is enabled, each chord tone (after spread is applied) is
/// moved to the nearest pitch class allowed by the host's Jam Mode scale.
/// This keeps chord tones diatonic when the user is in a specific key.
/// Down-first tie-breaking is used (same convention as [HarmonizeNode]).
class ChordExpandNode extends GFMidiNode {
  /// Index into [_kChordIntervals] for the current chord quality (0–10).
  int _chordTypeIndex = 0;

  /// Spread mode: 0 = close, 1 = open (alternate octave), 2 = wide (+1 oct).
  int _spreadMode = 0;

  /// Whether to snap chord tones to the host's active Jam Mode scale.
  bool _snapToScale = false;

  /// Callback from [GFMidiNodeContext] — may return null when Jam Mode is off.
  Set<int>? Function() _scaleProvider = () => null;

  /// Note-off tracking: maps original root pitch (per MIDI channel) to the
  /// list of chord-tone pitches that were emitted at note-on time.
  ///
  /// Structure: `_activeChords[channel][rootPitch] = [chordTonePitch1, ...]`
  ///
  /// Ensures that note-offs for chord tones match their note-ons exactly,
  /// even when parameters change while notes are still held.
  final List<Map<int, List<int>>> _activeChords =
      List.generate(16, (_) => {});

  ChordExpandNode(super.nodeId);

  @override
  void initialize(GFMidiNodeContext context) {
    _scaleProvider = context.scaleProvider;
    for (final m in _activeChords) { m.clear(); }
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'chordType':
        // 11 options → normalize by (11 - 1) = 10.
        _chordTypeIndex = (normalizedValue * 10).round().clamp(0, 10);
      case 'spread':
        // 3 options → normalize by (3 - 1) = 2.
        _spreadMode = (normalizedValue * 2).round().clamp(0, 2);
      case 'snapToScale':
        _snapToScale = normalizedValue >= 0.5;
    }
  }

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    // Read the host scale once per block to minimise callback overhead.
    final scale = _snapToScale ? _scaleProvider() : null;

    final output = <TimestampedMidiEvent>[];
    for (final e in events) {
      output.add(e); // root note always passes through

      if (e.isNoteOn) {
        _emitChordNoteOns(e, scale, output);
      } else if (e.isNoteOff) {
        _emitChordNoteOffs(e, output);
      }
    }
    return output;
  }

  /// Emit note-on events for all chord tones above the root.
  void _emitChordNoteOns(
    TimestampedMidiEvent noteOn,
    Set<int>? scale,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = noteOn.midiChannel;
    final root = noteOn.data1;

    // Fetch the raw semitone intervals for the chosen chord quality.
    final baseIntervals = _kChordIntervals[_chordTypeIndex];

    // Apply the spread mode to widen the voicing.
    final spreadIntervals = _applySpread(baseIntervals);

    final emitted = <int>[];
    for (final interval in spreadIntervals) {
      var pitch = (root + interval).clamp(0, 127);

      // If scale lock is on, snap each chord tone to the nearest diatonic note.
      if (scale != null) pitch = _snapPitch(pitch, scale);

      emitted.add(pitch);
      output.add(TimestampedMidiEvent(
        ppqPosition: noteOn.ppqPosition,
        status: noteOn.status, // same MIDI channel
        data1: pitch,
        data2: noteOn.data2, // preserve velocity
      ));
    }

    // Remember which chord pitches were emitted so note-offs match.
    _activeChords[ch][root] = emitted;
  }

  /// Emit note-off events for the chord pitches stored at note-on time.
  void _emitChordNoteOffs(
    TimestampedMidiEvent noteOff,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = noteOff.midiChannel;
    final root = noteOff.data1;

    // Retrieve and remove the stored chord tones for this root note.
    final chordTones = _activeChords[ch].remove(root);
    if (chordTones == null) return;

    for (final pitch in chordTones) {
      output.add(TimestampedMidiEvent(
        ppqPosition: noteOff.ppqPosition,
        status: noteOff.status, // preserves NOTE OFF status and channel
        data1: pitch,
        data2: noteOff.data2,
      ));
    }
  }

  /// Apply the current spread mode to a list of close-position intervals.
  ///
  /// - **Close (0)**: intervals returned unchanged.
  /// - **Open (1)**: odd-indexed intervals (1st, 3rd, …) are raised +12 st,
  ///   creating an alternating spread similar to drop-2 jazz voicings.
  /// - **Wide (2)**: all intervals raised +12 st, placing every chord tone
  ///   one octave higher than close position.
  List<int> _applySpread(List<int> intervals) {
    if (_spreadMode == 0) return intervals; // close — no transformation needed

    return [
      for (var i = 0; i < intervals.length; i++)
        _spreadMode == 2
            ? intervals[i] + 12        // wide: all tones up an octave
            : intervals[i] + (i.isOdd ? 12 : 0), // open: alternate octave
    ];
  }

  /// Snap [midiNote] to the nearest pitch class in [scale].
  ///
  /// Identical snapping logic to [HarmonizeNode._snapPitch]: searches outward
  /// ±1 semitone at a time with down-first tie-breaking.
  int _snapPitch(int midiNote, Set<int> scale) {
    final pc = midiNote % 12;
    if (scale.contains(pc)) return midiNote; // already in scale

    for (var delta = 1; delta <= 6; delta++) {
      final down = midiNote - delta;
      if (down >= 0 && scale.contains(down % 12)) return down;
      final up = midiNote + delta;
      if (up <= 127 && scale.contains(up % 12)) return up;
    }
    return midiNote; // fallback: scale empty or note at boundary
  }
}
