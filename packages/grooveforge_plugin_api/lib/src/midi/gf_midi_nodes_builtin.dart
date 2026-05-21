import 'dart:math';

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

/// Filters out notes that fall outside a velocity range or a pitch range.
///
/// **Node type key**: `"gate"`
///
/// **Parameters**
/// | name        | normalised range | semantic range       |
/// |-------------|-----------------|----------------------|
/// | minVelocity | 0.0 → 1.0       | 0 → 127 velocity     |
/// | maxVelocity | 0.0 → 1.0       | 0 → 127 velocity     |
/// | minPitch    | 0.0 → 1.0       | 0 → 127 MIDI note    |
/// | maxPitch    | 0.0 → 1.0       | 0 → 127 MIDI note    |
///
/// A note-on passes only if both conditions hold:
///   `minVelocity ≤ velocity ≤ maxVelocity` **and**
///   `minPitch ≤ pitch ≤ maxPitch`.
///
/// Suppressed note-ons are tracked so that the matching note-off is also
/// suppressed — preventing stuck notes when parameters change mid-hold.
///
/// Events that are not note-on/note-off (CC, pitch-bend, …) always pass
/// through unchanged. The fast path exits immediately when all parameters
/// are at their defaults (gate fully open).
class GateNode extends GFMidiNode {
  /// Lower velocity threshold (0–127). Default: 0 (no lower limit).
  int _minVelocity = 0;

  /// Upper velocity threshold (0–127). Default: 127 (no upper limit).
  int _maxVelocity = 127;

  /// Lowest MIDI note number that may pass (0–127). Default: 0 (all pitches).
  int _minPitch = 0;

  /// Highest MIDI note number that may pass (0–127). Default: 127 (all pitches).
  int _maxPitch = 127;

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
    switch (paramName) {
      case 'minVelocity':
        _minVelocity = (normalizedValue * 127).round();
      case 'maxVelocity':
        _maxVelocity = (normalizedValue * 127).round();
      case 'minPitch':
        _minPitch = (normalizedValue * 127).round();
      case 'maxPitch':
        _maxPitch = (normalizedValue * 127).round();
    }
  }

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    // Fast path: gate fully open (all default values — every note passes).
    if (_minVelocity == 0 && _maxVelocity == 127 &&
        _minPitch == 0 && _maxPitch == 127) { return events; }

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

  /// Let the note-on through only if both velocity and pitch are in range.
  ///
  /// Blocked notes are added to [_gated] so the matching note-off is also
  /// suppressed — no stuck notes if parameters change while notes are held.
  void _processGateNoteOn(
    TimestampedMidiEvent e,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = e.midiChannel;
    final blocked = e.data2 < _minVelocity ||
        e.data2 > _maxVelocity ||
        e.data1 < _minPitch ||
        e.data1 > _maxPitch;
    if (blocked) {
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

// ─────────────────────────────────────────────────────────────────────────────
//  ArpeggiateNode  ("arpeggiate")
// ─────────────────────────────────────────────────────────────────────────────

/// Step division durations in quarter-note beats.
///
/// | Index | Name    | Beats    | At 120 BPM |
/// |-------|---------|----------|------------|
/// | 0     | 1/4     | 1.000    | 500 ms     |
/// | 1     | 1/8     | 0.500    | 250 ms     |
/// | 2     | 1/16    | 0.250    | 125 ms     |
/// | 3     | 1/32    | 0.125    |  62 ms     |
/// | 4     | 1/64    | 0.0625   |  31 ms     |
/// | 5     | 1/128   | 0.03125  |  16 ms     |
/// | 6     | 1/4T    | 0.667    | 333 ms     |
/// | 7     | 1/8T    | 0.333    | 167 ms     |
/// | 8     | 1/16T   | 0.167    |  83 ms     |
/// | 9     | 1/32T   | 0.083    |  42 ms     |
/// | 10    | 1/64T   | 0.0417   |  21 ms     |
/// | 11    | 1/128T  | 0.0208   |  10 ms     |
///
/// Triplet values use exact fractions (2/3, 1/3, 1/6, 1/12, 1/24, 1/48
/// beats) so they stay precisely in a three-against-two relationship at any
/// tempo.
const List<double> _kArpDivisionBeats = [
  1.0,       //  0 — 1/4
  0.5,       //  1 — 1/8
  0.25,      //  2 — 1/16
  0.125,     //  3 — 1/32
  0.0625,    //  4 — 1/64
  0.03125,   //  5 — 1/128
  2 / 3,     //  6 — 1/4T
  1 / 3,     //  7 — 1/8T
  1 / 6,     //  8 — 1/16T
  1 / 12,    //  9 — 1/32T
  1 / 24,    // 10 — 1/64T
  1 / 48,    // 11 — 1/128T
];

/// Arpeggiator playback pattern.
///
/// Controls the order in which held pitches are visited each cycle.
enum _ArpPattern {
  /// Pitches in ascending order: C → E → G → C → …
  up,

  /// Pitches in descending order: G → E → C → G → …
  down,

  /// Ping-pong ascending then descending, endpoints not repeated:
  /// C → E → G → E → C → E → …
  upDown,

  /// Ping-pong descending then ascending, endpoints not repeated:
  /// G → E → C → E → G → E → …
  downUp,

  /// Notes in the order the user pressed them.
  asPlayed,

  /// A random pitch from the held set is chosen each step.
  random,
}

/// Mutable arpeggiator state for a single MIDI channel.
///
/// Separated from [ArpeggiateNode] to keep per-channel bookkeeping tidy.
/// One instance lives in the 16-element [ArpeggiateNode._channels] list.
class _ArpChannelState {
  /// Pitches currently held by the player, in press order (oldest → index 0).
  ///
  /// Maintained as an ordered list so the [_ArpPattern.asPlayed] pattern
  /// can reproduce the exact key-press sequence.
  final List<int> heldOrder = [];

  /// Velocity at which each currently-held pitch was pressed.
  ///
  /// Used so arp-generated notes inherit the dynamics of the held note they
  /// originate from (or the closest one when octave-shifted).
  final Map<int, int> heldVelocity = {};

  /// Current step index, incremented each time a new step fires.
  ///
  /// The effective position in the pattern is `stepIndex % sequence.length`,
  /// so the arp loops indefinitely without overflow risk.
  int stepIndex = 0;

  /// MIDI pitch of the note currently sounding from the arpeggiator.
  ///
  /// Null when the arp is silent (between steps or fully stopped).
  int? currentPitch;

  /// Wall-clock timestamp (µs) when the current step started.
  ///
  /// Zero means the arp has not yet started for this channel (no notes held).
  int stepStartUs = 0;

  /// True once the gate note-off for the current step has been sent.
  ///
  /// Prevents double note-offs when the gate fraction of a step elapses
  /// before the full step duration does (i.e. gate < 100%).
  bool noteOffSent = false;

  /// Reset all state when the arp stops (held notes becomes empty).
  void clear() {
    heldOrder.clear();
    heldVelocity.clear();
    stepIndex = 0;
    currentPitch = null;
    stepStartUs = 0;
    noteOffSent = false;
  }
}

/// Arpeggiates held notes in a rhythmic sequence.
///
/// Incoming note-ons and note-offs are suppressed and used only to update the
/// "held notes" set. The arpeggiator then emits its own note-on / note-off
/// sequence at the configured tempo division, gate, and pattern.
///
/// **Node type key**: `"arpeggiate"`
///
/// **Parameters**
/// | name     | normalised range | semantic meaning                             |
/// |----------|-----------------|----------------------------------------------|
/// | pattern  | 0.0 → 1.0       | Up/Down/UpDown/DownUp/AsPlayed/Random (0–5)  |
/// | division | 0.0 → 1.0       | 1/4 / 1/8 / 1/16 / 1/32 / 1/64 / 1/4T / 1/8T / 1/16T / 1/32T |
/// | gate     | 0.0 → 1.0       | Note hold fraction: 10%–100% of step         |
/// | octaves  | 0.0 → 1.0       | 1, 2, or 3 octaves (0–2 → 1–3)              |
///
/// **Wall-clock timing**
/// Steps are driven by `DateTime.now().microsecondsSinceEpoch` rather than
/// `GFTransportContext.positionInBeats`. This ensures the arp plays during
/// live performance even when the sequencer transport is stopped.
///
/// **tick() / processMidi() feedback loop**
/// `GFMidiGraph` calls `tick()` before `processMidi()`, then merges tick
/// output into the incoming events stream for that same node.  The arp uses
/// per-channel `_arpNoteOns` and `_arpNoteOffs` sets so `processMidi()` can
/// distinguish its own tick-generated events (pass through) from the user's
/// note events (update held state, suppress from output).
class ArpeggiateNode extends GFMidiNode {
  // ── Parameters ──────────────────────────────────────────────────────────────

  /// Current playback pattern (see [_ArpPattern]). Default: ascending.
  _ArpPattern _pattern = _ArpPattern.up;

  /// Index into [_kArpDivisionBeats]. Default: 1/8 note.
  int _divisionIndex = 1;

  /// Fraction of each step that the note sounds: 0.1 (10 %) → 1.0 (100 %).
  ///
  /// Short gates (< 0.5) produce a staccato feel; long gates (> 0.9) blur
  /// adjacent steps together and are useful for legato-style arpeggios.
  double _gateRatio = 0.75;

  /// Number of octaves the arpeggio spans: 1, 2, or 3.
  ///
  /// With octaves > 1 the base pitch set is repeated at +12 / +24 semitones
  /// so the arp climbs up before cycling back to the root octave.
  int _octaves = 1;

  // ── Per-channel state ────────────────────────────────────────────────────────

  /// Independent arpeggiator state for each of the 16 MIDI channels.
  final List<_ArpChannelState> _channels =
      List.generate(16, (_) => _ArpChannelState());

  /// Pitches of arp-generated note-ons pending recognition in [processMidi].
  ///
  /// `tick()` adds a pitch here before emitting the note-on event.
  /// `processMidi()` removes it when it sees the matching event, knowing to
  /// pass it through rather than treating it as a user event.
  final List<Set<int>> _arpNoteOns = List.generate(16, (_) => {});

  /// Pitches of arp-generated note-offs pending recognition in [processMidi].
  final List<Set<int>> _arpNoteOffs = List.generate(16, (_) => {});

  // ── Misc ─────────────────────────────────────────────────────────────────────

  /// Random number generator for the [_ArpPattern.random] mode.
  final Random _random = Random();

  ArpeggiateNode(super.nodeId);

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initialize(GFMidiNodeContext context) {
    // Clear any stale held-note state (e.g. after a project reload).
    for (final ch in _channels) {
      ch.clear();
    }
  }

  // ── Parameters ───────────────────────────────────────────────────────────────

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'pattern':
        // 6 patterns → normalise by (6 − 1) = 5.
        final idx = (normalizedValue * 5).round().clamp(0, 5);
        _pattern = _ArpPattern.values[idx];
      case 'division':
        // 12 options (indices 0–11) → normalise by (12 − 1) = 11.
        _divisionIndex = (normalizedValue * 11).round().clamp(0, 11);
      case 'gate':
        // Map [0, 1] → [0.10, 1.0] so gate can never be fully silent.
        _gateRatio = 0.1 + normalizedValue * 0.9;
      case 'octaves':
        // 3 options → normalise by 2; add 1 so the range is [1, 3].
        _octaves = (normalizedValue * 2).round().clamp(0, 2) + 1;
    }
  }

  // ── Time-driven event generation ─────────────────────────────────────────────

  /// Generate arp note-ons / note-offs based on elapsed wall-clock time.
  ///
  /// Called by [GFMidiGraph] once per block, before [processMidi]. Output
  /// events are then merged with incoming user events in the same block.
  @override
  List<TimestampedMidiEvent> tick(GFTransportContext transport) {
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    final stepDurationUs = _computeStepDurationUs(transport.bpm);
    // Gate note-off fires at this fraction of the step duration.
    final gateOffUs = (stepDurationUs * _gateRatio).toInt();

    final output = <TimestampedMidiEvent>[];
    for (var ch = 0; ch < 16; ch++) {
      _tickChannel(ch, nowUs, stepDurationUs, gateOffUs, output);
    }
    return output;
  }

  /// Advance the arpeggiator for channel [ch].
  ///
  /// Emits a gate note-off when [gateOffUs] has elapsed since the step start,
  /// then advances to the next step when the full [stepDurationUs] has elapsed.
  void _tickChannel(
    int ch,
    int nowUs,
    int stepDurationUs,
    int gateOffUs,
    List<TimestampedMidiEvent> output,
  ) {
    final state = _channels[ch];
    // Skip channels that have no held notes or have not yet started.
    if (state.heldOrder.isEmpty || state.stepStartUs == 0) return;

    final elapsed = nowUs - state.stepStartUs;

    // ── Gate note-off: mute the note at (gateRatio × stepDuration) ───────────
    if (!state.noteOffSent &&
        state.currentPitch != null &&
        elapsed >= gateOffUs) {
      _emitArpNoteOff(ch, state.currentPitch!, output);
      state.noteOffSent = true;
    }

    // ── Step advance: fire the next note once the step duration has elapsed ──
    if (elapsed >= stepDurationUs) {
      // Guarantee the gate note-off went out before the new note-on.
      if (!state.noteOffSent && state.currentPitch != null) {
        _emitArpNoteOff(ch, state.currentPitch!, output);
        state.noteOffSent = true;
      }
      state.stepIndex++;
      _fireStep(ch, state, output);
      // Reset step clock — add overshoot to next step for drift-free timing.
      state.stepStartUs = nowUs - (elapsed - stepDurationUs);
    }
  }

  // ── MIDI event processing ────────────────────────────────────────────────────

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    final output = <TimestampedMidiEvent>[];
    for (final e in events) {
      _processEvent(e, transport, output);
    }
    return output;
  }

  /// Route a single event to the appropriate handler.
  ///
  /// Arp-generated events (tracked in [_arpNoteOns] / [_arpNoteOffs]) are
  /// passed through immediately. User note events update the held-note state
  /// and are suppressed from the output stream. All other events pass through.
  void _processEvent(
    TimestampedMidiEvent e,
    GFTransportContext transport,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = e.midiChannel;

    // Arp-generated note-on: recognised and passed straight to the output.
    if (e.isNoteOn && _arpNoteOns[ch].remove(e.data1)) {
      output.add(e);
      return;
    }

    // Arp-generated note-off: same pass-through treatment.
    if (e.isNoteOff && _arpNoteOffs[ch].remove(e.data1)) {
      output.add(e);
      return;
    }

    // User note-on: update held state, fire first arp step if idle.
    if (e.isNoteOn) {
      _handleUserNoteOn(e, output);
      return;
    }

    // User note-off: update held state, stop arp if all keys released.
    if (e.isNoteOff) {
      _handleUserNoteOff(e, output);
      return;
    }

    // CC, pitch-bend, aftertouch, etc. pass through unchanged.
    output.add(e);
  }

  /// Handle a user note-on: add the pitch to the held set.
  ///
  /// If the arp was idle (no held notes before this event), fires the first
  /// arp step immediately — eliminating the one-tick latency that would occur
  /// if we waited for the next [tick()] call (~10 ms).
  void _handleUserNoteOn(
    TimestampedMidiEvent e,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = e.midiChannel;
    final pitch = e.data1;
    final state = _channels[ch];
    final wasEmpty = state.heldOrder.isEmpty;

    // Avoid duplicating a pitch if the same key is re-triggered (e.g. glide).
    if (!state.heldVelocity.containsKey(pitch)) {
      state.heldOrder.add(pitch);
    }
    state.heldVelocity[pitch] = e.data2;

    if (wasEmpty) {
      // First key pressed: start the arp at step 0 with no delay.
      state.stepIndex = 0;
      state.stepStartUs = DateTime.now().microsecondsSinceEpoch;
      _fireStep(ch, state, output);
      // _fireStep() always adds the pitch to _arpNoteOns so that tick()-generated
      // events can be recognised when GFMidiGraph merges them with incoming events.
      // Here we are already *inside* processMidi — the note-on went straight to
      // output and there is no pending tick event to consume the sentinel.  Leaving
      // it in the set means a subsequent press of the same pitch (e.g. on a return
      // glissando stroke) would be silently misidentified as an arp-generated event,
      // causing _handleUserNoteOn to be skipped and the eventual release to emit no
      // note-off — the note would then stick visually in activeNotes forever.
      _arpNoteOns[ch].remove(state.currentPitch);
    }
    // When additional keys are pressed while the arp is already running,
    // the new pitch will appear in the pattern on the next step naturally.
  }

  /// Handle a user note-off: remove the pitch from the held set.
  ///
  /// When the last held key is released, the currently-sounding arp note
  /// receives an immediate note-off and all per-channel state is cleared.
  void _handleUserNoteOff(
    TimestampedMidiEvent e,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = e.midiChannel;
    final pitch = e.data1;
    final state = _channels[ch];

    state.heldOrder.remove(pitch);
    state.heldVelocity.remove(pitch);

    if (state.heldOrder.isEmpty) {
      // All keys released — stop the arp and silence any ringing note.
      if (!state.noteOffSent && state.currentPitch != null) {
        // Emit note-off directly (not via _arpNoteOffs; we are already
        // inside processMidi and can write straight to output).
        output.add(TimestampedMidiEvent(
          ppqPosition: e.ppqPosition,
          status: _noteOffStatus(ch),
          data1: state.currentPitch!,
          data2: 0,
        ));
      }
      // If tick() generated note-ons earlier in this same processMidi batch
      // (GFMidiGraph calls tick() before processMidi), those events are about
      // to be recognised and passed through by _processEvent. Without a
      // matching gate note-off they would produce stuck notes — the arp state
      // is now clear so no future tick will silence them.  Emit anticipatory
      // note-offs for every orphaned pitch so the caller receives balanced
      // note-on / note-off pairs.
      for (final orphanPitch in _arpNoteOns[ch]) {
        output.add(TimestampedMidiEvent(
          ppqPosition: e.ppqPosition,
          status: _noteOffStatus(ch),
          data1: orphanPitch,
          data2: 0,
        ));
      }
      state.clear();
    }
  }

  // ── Step helpers ─────────────────────────────────────────────────────────────

  /// Emit the arp note for the current step of [state] on channel [ch].
  ///
  /// Builds the pitch set from the held notes (expanded across octaves),
  /// picks the pitch for [state.stepIndex] according to [_pattern], and
  /// appends a note-on event to [output].  The pitch is also added to
  /// [_arpNoteOns] so [processMidi] can recognise it when tick() output is
  /// merged into the incoming stream.
  void _fireStep(
    int ch,
    _ArpChannelState state,
    List<TimestampedMidiEvent> output,
  ) {
    final pitches = _buildPitches(state);
    if (pitches.isEmpty) return;

    final pitch = _patternPitch(pitches, state.stepIndex);
    final velocity = _closestVelocity(pitch, state.heldVelocity);

    _arpNoteOns[ch].add(pitch);
    output.add(TimestampedMidiEvent(
      ppqPosition: 0,
      status: _noteOnStatus(ch),
      data1: pitch,
      data2: velocity,
    ));
    state.currentPitch = pitch;
    state.noteOffSent = false;
  }

  /// Add an arp-generated note-off to [output] and track it in [_arpNoteOffs].
  void _emitArpNoteOff(
      int ch, int pitch, List<TimestampedMidiEvent> output) {
    _arpNoteOffs[ch].add(pitch);
    output.add(TimestampedMidiEvent(
      ppqPosition: 0,
      status: _noteOffStatus(ch),
      data1: pitch,
      data2: 0,
    ));
  }

  // ── Pattern builders ─────────────────────────────────────────────────────────

  /// Build the list of pitches the arpeggiator cycles through.
  ///
  /// For sorted patterns (Up / Down / UpDown / DownUp) the base pitches are
  /// sorted ascending. For [_ArpPattern.asPlayed] / [_ArpPattern.random] the
  /// press order is preserved. The list is then replicated at +12 / +24 st
  /// when [_octaves] > 1, clipping at MIDI note 127.
  List<int> _buildPitches(_ArpChannelState state) {
    if (state.heldOrder.isEmpty) return const [];

    // Choose base ordering: sorted for harmonic patterns, press-order otherwise.
    final List<int> base;
    if (_pattern == _ArpPattern.asPlayed || _pattern == _ArpPattern.random) {
      base = List<int>.from(state.heldOrder);
    } else {
      base = List<int>.from(state.heldOrder)..sort();
    }

    if (_octaves == 1) return base;

    // Expand across octaves: e.g. octaves=2 → [C4, E4, G4, C5, E5, G5].
    final expanded = <int>[];
    for (var oct = 0; oct < _octaves; oct++) {
      for (final p in base) {
        final shifted = p + oct * 12;
        if (shifted <= 127) expanded.add(shifted);
      }
    }
    return expanded;
  }

  /// Pick the arp pitch for the given [stepIndex] from [pitches].
  ///
  /// [_ArpPattern.random] ignores [stepIndex] and picks randomly.
  /// All other patterns use [_buildSequence] to create a looping sequence.
  int _patternPitch(List<int> pitches, int stepIndex) {
    if (_pattern == _ArpPattern.random) {
      return pitches[_random.nextInt(pitches.length)];
    }
    final seq = _buildSequence(pitches);
    return seq[stepIndex % seq.length];
  }

  /// Build the full looping sequence for [pitches] based on [_pattern].
  ///
  /// | Pattern | Example for [C, E, G]     | Length  |
  /// |---------|---------------------------|---------|
  /// | Up      | [C, E, G]                 | N       |
  /// | Down    | [G, E, C]                 | N       |
  /// | UpDown  | [C, E, G, E] (ping-pong)  | 2(N−1)  |
  /// | DownUp  | [G, E, C, E] (pong-ping)  | 2(N−1)  |
  /// | AsPlayed| press order               | N       |
  ///
  /// For N = 1, all patterns return the single note (no ping-pong needed).
  List<int> _buildSequence(List<int> pitches) {
    if (pitches.length <= 1) return pitches;

    switch (_pattern) {
      case _ArpPattern.up:
      case _ArpPattern.asPlayed:
        return pitches;
      case _ArpPattern.down:
        return pitches.reversed.toList();
      case _ArpPattern.upDown:
        // Ascending + descending: skip both endpoints on the return to avoid
        // repeating the top and bottom notes twice in a row.
        // [C, E, G] → [C, E, G, E] — length = 2 × (N − 1)
        return [
          ...pitches,
          ...pitches.reversed.skip(1).take(pitches.length - 2),
        ];
      case _ArpPattern.downUp:
        final desc = pitches.reversed.toList();
        return [
          ...desc,
          ...desc.reversed.skip(1).take(desc.length - 2),
        ];
      case _ArpPattern.random:
        return pitches; // handled in _patternPitch, never reached here
    }
  }

  // ── Utilities ────────────────────────────────────────────────────────────────

  /// Compute the step duration in microseconds for the current [bpm] and
  /// division index.
  ///
  /// Clamps [bpm] to 1 to avoid division by zero at stopped transport.
  int _computeStepDurationUs(double bpm) {
    final safeBpm = bpm < 1.0 ? 1.0 : bpm;
    return (60000000.0 / safeBpm * _kArpDivisionBeats[_divisionIndex])
        .toInt();
  }

  /// Return the velocity for an arp-generated [pitch] from [heldVelocity].
  ///
  /// Tries an exact pitch match first, then a pitch-class match (for notes
  /// shifted up by octaves), and finally falls back to 100 (forte).
  int _closestVelocity(int pitch, Map<int, int> heldVelocity) {
    if (heldVelocity.isEmpty) return 100;
    if (heldVelocity.containsKey(pitch)) return heldVelocity[pitch]!;
    // Pitch-class match: C5 (60) velocity matches C4 (48) when octave-expanded.
    final pc = pitch % 12;
    for (final entry in heldVelocity.entries) {
      if (entry.key % 12 == pc) return entry.value;
    }
    return heldVelocity.values.first;
  }

  /// NOTE ON status byte for [channel] (0x9n, velocity > 0 required).
  int _noteOnStatus(int channel) => 0x90 | (channel & 0x0F);

  /// NOTE OFF status byte for [channel] (0x8n).
  int _noteOffStatus(int channel) => 0x80 | (channel & 0x0F);
}

// ─────────────────────────────────────────────────────────────────────────────
//  VelocityCurveNode  ("velocity_curve")
// ─────────────────────────────────────────────────────────────────────────────

/// Curve mode for [VelocityCurveNode].
///
/// Selects the mathematical function used to remap incoming note velocities.
enum _VelocityCurveMode {
  /// Power curve: v_out = (v_in / 127)^exponent × 127.
  ///
  /// The exponent is controlled by [VelocityCurveNode._amount]:
  /// - 0.0 → exponent 0.25 (soft response: gentle press sounds louder)
  /// - 0.5 → exponent 1.0  (linear: no change)
  /// - 1.0 → exponent 4.0  (hard response: strong press needed for loud output)
  power,

  /// Sigmoid S-curve: compresses the mid-range and pushes extremes outward.
  ///
  /// Controlled by [VelocityCurveNode._amount]:
  /// - 0.0 → gentle S (near-linear; almost no effect)
  /// - 1.0 → steep S (sharp contrast between soft and loud zones)
  ///
  /// The output is always rescaled to span the full [1, 127] range.
  sigmoid,

  /// Fixed velocity: every note-on is given the same velocity regardless of
  /// how hard the key was pressed.
  ///
  /// Controlled by [VelocityCurveNode._amount]:
  /// - 0.0 → velocity 1 (minimum audible; 0 would be interpreted as note-off)
  /// - 1.0 → velocity 127 (maximum)
  fixed,
}

/// Remaps incoming note-on velocities using a configurable curve function.
///
/// **Node type key**: `"velocity_curve"`
///
/// **Parameters**
/// | name   | normalised range | semantic meaning                                      |
/// |--------|-----------------|-------------------------------------------------------|
/// | mode   | 0.0 → 1.0       | Curve type: Power / Sigmoid / Fixed (index / 2)       |
/// | amount | 0.0 → 1.0       | Curve intensity — or fixed output velocity in Fixed mode|
///
/// **Power mode** (mode = 0, default)
/// Applies a power function: v_out = round(127 × (v_in / 127)^exponent), where
/// exponent = 2^((amount − 0.5) × 4).  This spans 0.25 (soft response) through
/// 1.0 (linear) to 4.0 (hard response) and short-circuits at amount ≈ 0.5.
///
/// **Sigmoid mode** (mode = 1)
/// Applies a logistic S-curve centred at velocity 64.  The steepness parameter
/// k = 4 + amount × 16 controls how sharply the curve transitions from the
/// soft zone to the loud zone.  Output is always renormalised to [1, 127].
///
/// **Fixed mode** (mode = 2)
/// Replaces every note-on velocity with a constant value derived from amount:
/// v_out = max(1, round(amount × 127)).  Velocity 0 is never returned as it
/// would be interpreted as a note-off by MIDI receivers.
///
/// Note-off events and all non-note events (CC, pitch-bend, …) are passed
/// through unchanged.
class VelocityCurveNode extends GFMidiNode {
  /// Current curve mode. Default: power at the linear centre (no change).
  _VelocityCurveMode _mode = _VelocityCurveMode.power;

  /// Normalised curve intensity or fixed velocity [0.0, 1.0].
  ///
  /// Meaning depends on [_mode] — see class-level documentation.
  /// Default 0.5 = linear (power exponent = 1.0, no remapping).
  double _amount = 0.5;

  VelocityCurveNode(super.nodeId);

  @override
  void initialize(GFMidiNodeContext context) {
    // No host state needed — velocity remapping is self-contained.
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'mode':
        // 3 options (0–2) → normalise by (3 − 1) = 2.
        final idx = (normalizedValue * 2).round().clamp(0, 2);
        _mode = _VelocityCurveMode.values[idx];
      case 'amount':
        _amount = normalizedValue.clamp(0.0, 1.0);
    }
  }

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    // Fast path: power mode at the linear centre — no remapping needed.
    if (_mode == _VelocityCurveMode.power && (_amount - 0.5).abs() < 0.01) {
      return events;
    }

    final output = <TimestampedMidiEvent>[];
    for (final e in events) {
      // Remap only genuine note-ons (data2 > 0 distinguishes them from the
      // "note-on with velocity 0" alternative note-off form used by some gear).
      output.add(e.isNoteOn && e.data2 > 0 ? _remapVelocity(e) : e);
    }
    return output;
  }

  /// Return [noteOn] with its velocity field replaced by the curve output.
  ///
  /// If the curve happens to produce the same velocity (e.g., linear power
  /// at centre), the original event object is returned unchanged.
  TimestampedMidiEvent _remapVelocity(TimestampedMidiEvent noteOn) {
    final newVel = _computeVelocity(noteOn.data2);
    if (newVel == noteOn.data2) return noteOn;
    return TimestampedMidiEvent(
      ppqPosition: noteOn.ppqPosition,
      status: noteOn.status,
      data1: noteOn.data1,
      data2: newVel,
    );
  }

  /// Route the velocity through the active curve function.
  int _computeVelocity(int velocity) {
    switch (_mode) {
      case _VelocityCurveMode.power:
        return _applyPower(velocity);
      case _VelocityCurveMode.sigmoid:
        return _applySigmoid(velocity);
      case _VelocityCurveMode.fixed:
        return _applyFixed();
    }
  }

  /// Power-curve remapping.
  ///
  /// Exponent = 2^((amount − 0.5) × 4), giving a range of [0.25, 4.0]:
  /// - Exponent < 1 (amount < 0.5): concave — soft press → brighter output.
  /// - Exponent = 1 (amount ≈ 0.5): identity mapping (linear, no change).
  /// - Exponent > 1 (amount > 0.5): convex — strong press required for volume.
  int _applyPower(int velocity) {
    final exponent = pow(2.0, (_amount - 0.5) * 4.0);
    return (127.0 * pow(velocity / 127.0, exponent)).round().clamp(1, 127);
  }

  /// Sigmoid S-curve remapping.
  ///
  /// Maps velocity through 1 / (1 + e^(−k × (v/127 − 0.5))) and renormalises
  /// so the output always spans [1, 127]:
  /// - k = 4 + amount × 16 (steepness range: 4 → 20).
  /// - Low k: gentle S-curve, near-linear. High k: sharp "snap" at v = 64.
  int _applySigmoid(int velocity) {
    final k = 4.0 + _amount * 16.0;

    // Shift the input so 0.5 (velocity 64) sits at zero — centres the curve.
    final x = velocity / 127.0 - 0.5;

    // Compute the sigmoid output and its limits at the input extremes so we
    // can renormalise back to [0, 1] regardless of steepness.
    final halfK  = k * 0.5;
    final sigMin = 1.0 / (1.0 + exp(halfK));   // sigmoid(−0.5) at v_in = 0
    final sigMax = 1.0 / (1.0 + exp(-halfK));  // sigmoid(+0.5) at v_in = 127
    final sigX   = 1.0 / (1.0 + exp(-k * x));

    final normalized = (sigX - sigMin) / (sigMax - sigMin);
    return (1 + (normalized * 126.0)).round().clamp(1, 127);
  }

  /// Fixed-velocity output: ignore the incoming velocity entirely.
  ///
  /// amount = 0.0 → velocity 1 (minimum audible);
  /// amount = 1.0 → velocity 127 (maximum).
  /// Velocity 0 is never returned to avoid it being misread as a note-off.
  int _applyFixed() => max(1, (_amount * 127.0).round());
}

// ─────────────────────────────────────────────────────────────────────────────
//  MicrotoneNode  ("microtone")
// ─────────────────────────────────────────────────────────────────────────────

/// How [MicrotoneNode] computes the cluster target pitch.
///
/// Two musical interpretations of "where does a cluster of held notes point?".
enum _MicrotoneClusterMode {
  /// Midpoint between the lowest and highest held pitch.
  ///
  /// Example: C (60) + E (64) → target 62 (D). C (60) + C# (61) → 60.5
  /// (a quarter-tone above C). Behaves predictably with two-finger gestures
  /// and ignores the inner voices of a wider cluster.
  outerAverage,

  /// Arithmetic mean of all held pitches.
  ///
  /// Example: C (60) + E (64) + G (67) → 63.67 (between Eb and E).
  /// More sensitive to chord inversions than [outerAverage] — useful for
  /// expressive shaping when the player adds inner voices to nudge the pitch.
  meanOfAll,
}

/// How [MicrotoneNode] derives the velocity of the single output note.
enum _MicrotoneVelocityMode {
  /// Arithmetic mean of all currently-held note velocities.
  ///
  /// Smoother dynamics: harder/softer keys in the cluster average out,
  /// matching the way a single touch surface would respond to fingertip
  /// pressure across multiple contact points.
  average,

  /// Velocity of the most recently pressed key.
  ///
  /// Lets the player accent the cluster by re-pressing one of the keys —
  /// useful as an expression gesture even though the cluster pitch does not
  /// re-trigger a new note-on.
  lastNote,
}

/// Combines simultaneously-held notes into a single microtonal pitch.
///
/// Inspired by mTonal (24-tone quarter-tone keyboards) and the MTS-ESP
/// pitch-bend approach used by ODDSound and KOMA Monoplex. Makes a standard
/// MIDI keyboard expressive for microtonal/xenharmonic music without special
/// hardware: hold C + C# and you get a quarter-tone between them; hold C + E
/// and you get a D with a slight detune.
///
/// **Node type key**: `"microtone"`
///
/// **Output behaviour — re-attack model**
/// The plugin treats the keyboard as monotonic: only one voice sounds at a
/// time. Every time the held set changes (note added or released) the node
/// emits a fresh attack at the new cluster target — Note-Off the previous
/// voice, set the pitch-bend, then Note-On the new voice. The synth always
/// hears a clean attack that is already pre-bent to the microtonal pitch.
///
/// **[attackDelay] selects how the first note of a cluster fires:**
/// - **0 ms (immediate)** — the first key press fires Note-On instantly at
///   the chromatic pitch (zero latency). A two-finger microtone therefore
///   starts with a brief chromatic onset until the second finger re-attacks.
/// - **> 0 ms (deferred)** — the first press starts a gather window; all keys
///   pressed within it accumulate silently, and a single attack at the cluster
///   median fires when the window expires. This produces a clean single
///   microtonal note with no chromatic onset. A tap released before the window
///   expires fires (and immediately releases) so notes are never silently
///   dropped.
///
/// Once a cluster is sounding:
/// - **Pressing** another key re-attacks immediately at the new target pitch
///   (Note-Off old → PitchBend → Note-On new).
/// - **Releasing** a key while others remain held re-attacks at the smaller
///   cluster too — but the re-attack is deferred by one settle window
///   ([attackDelay]). If the rest of the cluster lifts within that window the
///   re-attack is cancelled, so releasing a whole cluster to *stop* produces a
///   single Note-Off with no extra note; if the player instead peels off one
///   finger and holds, the re-attack fires and the pitch steps to the smaller
///   cluster — handy for fast finger-peel melodic patterns. In immediate mode
///   (delay 0) release re-attacks fire at once.
/// - **The last key released** fires Note-Off. The pitch-bend is left where
///   it is (not reset to centre) so the voice's release tail decays at the
///   correct microtone instead of audibly snapping to the chromatic pitch.
///
/// **Parameters**
/// | name         | normalised range | semantic meaning                          |
/// |--------------|------------------|-------------------------------------------|
/// | chordWindow  | 0.0 → 1.0        | 0–80 ms attack delay (0 = immediate fire) |
/// | clusterMode  | 0.0 → 1.0        | 0 = OuterAverage, 1 = MeanOfAll           |
/// | bendRange    | 0.0 → 1.0        | 0 = ±2 st, 0.5 = ±12 st, 1 = ±24 st       |
/// | velocityMode | 0.0 → 1.0        | 0 = Average, 1 = LastNote                 |
///
/// **Pitch-bend encoding**
/// MIDI pitch-bend is 14-bit, centred at 8192 (no bend). The output bend value
/// is `8192 + round((targetPitch - basePitch) / bendRange * 8191)` where
/// `basePitch` is the lowest currently-held pitch. The `bendRange` parameter
/// MUST match the downstream synth's configured pitch-bend range — otherwise
/// the audible pitch will not equal the cluster target. ±2 semitones is the
/// General MIDI default; ±12 or ±24 require the receiving synth to support
/// extended bend ranges (most modern soft-synths and VSTs do).
///
/// **Time-driven behaviour**
/// Deferred attacks and release re-attacks are fired at the end of every
/// [processMidi] block using wall-clock time — independent of the transport.
/// `RackState` pumps an empty [processMidi] block every ~10 ms, so a deferred
/// event still fires when the player holds a chord and stops moving. Firing at
/// the end of the block (after the block's own events are handled) is what
/// makes the timing race-free: an emptying release cancels a pending re-attack
/// before it can fire, and a fast second press joins the cluster before the
/// gather attack fires.
class MicrotoneNode extends GFMidiNode {
  // ── Parameters ──────────────────────────────────────────────────────────────

  /// Attack delay in microseconds — how long to gather a cluster before
  /// firing its first note. Default ≈ 30 ms.
  ///
  /// 0 fires the first press immediately (zero latency); a positive value
  /// defers the first attack so simultaneous presses collapse into one clean
  /// microtonal note. Named `_chordWindowUs` because the bound descriptor
  /// parameter id is still `chord_window` for save-file stability.
  int _chordWindowUs = 30 * 1000;

  /// How to compute the cluster target pitch.
  _MicrotoneClusterMode _clusterMode = _MicrotoneClusterMode.outerAverage;

  /// Pitch-bend half-range in semitones — must match the downstream synth.
  ///
  /// Defaults to 2 semitones (General MIDI standard). When the player's
  /// cluster spans more than this range, the bend saturates at ±8191 and the
  /// effective target pitch is clamped — the user should raise [bendRange]
  /// to ±12 or ±24 for wider chromatic clusters.
  int _bendRangeSemitones = 2;

  /// How to derive the output velocity.
  _MicrotoneVelocityMode _velocityMode = _MicrotoneVelocityMode.average;

  // ── Per-channel state ───────────────────────────────────────────────────────

  /// Independent microtone state for each of the 16 MIDI channels.
  final List<_MicrotoneChannelState> _channels =
      List.generate(16, (_) => _MicrotoneChannelState());

  MicrotoneNode(super.nodeId);

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initialize(GFMidiNodeContext context) {
    // Clear stale state from a previous project / hot reload.
    for (final ch in _channels) { ch.clear(); }
  }

  // ── Parameters ──────────────────────────────────────────────────────────────

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'chordWindow':
        // Map [0, 1] → [0 ms, 80 ms] then convert to microseconds.
        _chordWindowUs = (normalizedValue * 80.0 * 1000).round();
      case 'clusterMode':
        // 2 options → midpoint 0.5 is the boundary.
        _clusterMode = normalizedValue < 0.5
            ? _MicrotoneClusterMode.outerAverage
            : _MicrotoneClusterMode.meanOfAll;
      case 'bendRange':
        // 3 options → ±2 / ±12 / ±24 semitones.
        // Boundaries at 0.33 and 0.67 keep the three zones evenly spaced.
        if (normalizedValue < 1.0 / 3.0) {
          _bendRangeSemitones = 2;
        } else if (normalizedValue < 2.0 / 3.0) {
          _bendRangeSemitones = 12;
        } else {
          _bendRangeSemitones = 24;
        }
      case 'velocityMode':
        _velocityMode = normalizedValue < 0.5
            ? _MicrotoneVelocityMode.average
            : _MicrotoneVelocityMode.lastNote;
    }
  }

  // ── MIDI event processing ───────────────────────────────────────────────────

  /// Process a block of incoming events, then fire any deferred attack /
  /// re-attack whose window has expired.
  ///
  /// **Ordering is the whole point.** Input events are handled *first*, then
  /// the deferred firing runs at the end. This means:
  /// - a release that empties the cluster clears `releasePending` before the
  ///   end-of-block check, so a near-simultaneous full release never fires a
  ///   stray re-attack (no stuck note);
  /// - a fast second press is accumulated into the gathering cluster before
  ///   the gather fires, so it collapses into one microtonal attack (no
  ///   doubled note).
  ///
  /// Deferred events are appended straight to the output here — they are never
  /// re-fed into [processMidi], so (unlike a `tick()` + merge design) no
  /// self-emission tagging is needed and there is no event-ordering race.
  ///
  /// `RackState._midiFxTicker` calls this with an empty list every ~10 ms, so
  /// deferred events still fire when the player holds a chord and stops moving.
  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    final output = <TimestampedMidiEvent>[];
    for (final e in events) {
      _processEvent(e, output);
    }
    _fireDeferred(output);
    return output;
  }

  /// Fire any per-channel deferred attack / re-attack whose window has expired.
  /// Run at the end of every [processMidi] block (see that method for why the
  /// timing matters).
  void _fireDeferred(List<TimestampedMidiEvent> output) {
    final nowUs = DateTime.now().microsecondsSinceEpoch;
    for (var ch = 0; ch < 16; ch++) {
      final s = _channels[ch];
      if (s.gathering && (nowUs - s.gatherStartUs) >= _chordWindowUs) {
        _emitFirstAttack(ch, s, output);
        s.gathering = false;
        s.sounding = true;
      } else if (s.releasePending &&
          (nowUs - s.releaseStartUs) >= _chordWindowUs) {
        _emitReattack(ch, s, output);
        s.releasePending = false;
      }
    }
  }

  /// Route a single incoming event.
  ///
  /// - User note-on / note-off drive the cluster state machine (deferred or
  ///   immediate first attack, re-attack, release).
  /// - Pitch-bend, CC, channel pressure, aftertouch — pass through unchanged.
  void _processEvent(
    TimestampedMidiEvent e,
    List<TimestampedMidiEvent> output,
  ) {
    final ch = e.midiChannel;
    final s = _channels[ch];

    if (e.isNoteOn) {
      _handleUserNoteOn(e, s, output);
      return;
    }
    if (e.isNoteOff) {
      _handleUserNoteOff(e, s, output);
      return;
    }

    output.add(e);
  }

  /// Add the pressed pitch to the held set and advance the cluster phase.
  ///
  /// Phase transitions (see [_MicrotoneChannelState]):
  /// - **idle** → if [_chordWindowUs] is 0, fire the first attack immediately
  ///   (zero latency) and go *sounding*; otherwise start *gathering* and let
  ///   the end-of-block deferred check fire the attack when the window expires.
  /// - **gathering** → just accumulate; the deferred attack will see the full
  ///   cluster.
  /// - **sounding** → re-attack now at the new cluster target. A press also
  ///   cancels any pending release re-attack: the player is changing the
  ///   cluster, which resolves the "is this a stop?" ambiguity.
  void _handleUserNoteOn(
    TimestampedMidiEvent e,
    _MicrotoneChannelState s,
    List<TimestampedMidiEvent> output,
  ) {
    // Avoid duplicating a pitch if the same key is re-triggered.
    if (!s.heldVelocity.containsKey(e.data1)) {
      s.heldOrder.add(e.data1);
    }
    s.heldVelocity[e.data1] = e.data2;
    s.lastVelocity = e.data2;

    final nowUs = DateTime.now().microsecondsSinceEpoch;

    if (s.sounding) {
      // Established cluster — re-attack now at the new target. A fresh press
      // always fires immediately (no settle window): you want the note you
      // just pressed to sound at once.
      s.releasePending = false;
      _emitReattack(e.midiChannel, s, output);
      return;
    }

    if (s.gathering) {
      // Still gathering the initial cluster — accumulate silently.
      return;
    }

    // idle: first press of a fresh cluster.
    if (_chordWindowUs <= 0) {
      // Immediate mode — fire now.
      _emitFirstAttack(e.midiChannel, s, output);
      s.sounding = true;
    } else {
      // Deferred mode — gather; the end-of-block check fires the attack once
      // the window ends.
      s.gathering = true;
      s.gatherStartUs = nowUs;
    }
  }

  /// Remove the released pitch from the held set and advance the phase.
  ///
  /// - **gathering** → if this empties the held set the player did a quick
  ///   tap; fire the gathered attack *now* (so it is audible) and immediately
  ///   release it, instead of dropping the note. If keys remain, keep
  ///   gathering with the smaller cluster.
  /// - **sounding, last key lifts** → Note-Off (the bend is left untouched so
  ///   the release tail keeps its microtone). Any pending release re-attack is
  ///   cancelled — this is what makes a near-simultaneous full release a clean
  ///   stop with no extra note.
  /// - **sounding, keys remain** → schedule a *deferred* re-attack at the
  ///   smaller cluster after the settle window ([_chordWindowUs]). If the rest
  ///   of the cluster lifts within that window the re-attack is cancelled
  ///   (clean stop); if not, the end-of-block check fires it — letting the
  ///   player peel one finger to melodically step the pitch down. In immediate
  ///   mode (delay 0) the re-attack fires at once.
  void _handleUserNoteOff(
    TimestampedMidiEvent e,
    _MicrotoneChannelState s,
    List<TimestampedMidiEvent> output,
  ) {
    final pitch = e.data1;

    if (s.gathering) {
      final isLastHeld =
          s.heldOrder.length == 1 && s.heldOrder.first == pitch;
      if (isLastHeld) {
        // Quick tap released before the gather window expired. Fire the
        // attack now (held set still contains `pitch`) so the note is never
        // silently dropped, then release it for a short staccato note.
        _emitFirstAttack(e.midiChannel, s, output);
        s.gathering = false;
        s.sounding = true;
        s.heldOrder.remove(pitch);
        s.heldVelocity.remove(pitch);
        _emitClusterNoteOff(e.midiChannel, s, output);
        return;
      }
      // Keys remain — keep gathering with the reduced cluster.
      s.heldOrder.remove(pitch);
      s.heldVelocity.remove(pitch);
      return;
    }

    s.heldOrder.remove(pitch);
    s.heldVelocity.remove(pitch);

    final nowUs = DateTime.now().microsecondsSinceEpoch;

    if (s.heldOrder.isEmpty) {
      // Last key lifted — end the note and cancel any pending re-attack so a
      // near-simultaneous full release does not sound an extra note.
      s.releasePending = false;
      if (s.sounding) {
        _emitClusterNoteOff(e.midiChannel, s, output);
      }
      s.gatherStartUs = 0;
      return;
    }

    // Keys remain — re-attack at the smaller cluster.
    if (_chordWindowUs <= 0) {
      // Immediate mode — re-attack now.
      _emitReattack(e.midiChannel, s, output);
    } else {
      // Deferred: wait one settle window. The end-of-block check fires the
      // re-attack unless the rest of the cluster lifts first (a stop) or a
      // press supersedes it.
      s.releasePending = true;
      s.releaseStartUs = nowUs;
    }
  }

  // ── Cluster emission ────────────────────────────────────────────────────────

  /// Fire the first Note-On of a fresh cluster, pre-bent to the cluster's
  /// target microtone.
  ///
  /// There is no prior voice to silence, so the sequence is PitchBend then
  /// Note-On. In immediate mode (attack delay 0) the cluster usually holds a
  /// single key, so the bend is centred and the note is chromatic; in deferred
  /// mode the gather may have collected several keys, so the very first attack
  /// already lands on the bent median — no chromatic onset.
  void _emitFirstAttack(
    int ch,
    _MicrotoneChannelState s,
    List<TimestampedMidiEvent> output,
  ) {
    if (s.heldOrder.isEmpty) return; // safety — caller should have checked

    final basePitch = _lowestHeld(s);
    final targetPitch = _computeClusterTargetPitch(s);
    final bend = _bendForOffset(targetPitch - basePitch);
    final velocity = _resolveOutputVelocity(s);

    s.basePitch = basePitch;

    output.add(_pitchBendEvent(ch, bend));
    output.add(TimestampedMidiEvent(
      ppqPosition: 0,
      status: _noteOnStatus(ch),
      data1: basePitch,
      data2: velocity,
    ));
  }

  /// Silence the currently-sounding voice and attack a fresh one at the
  /// current cluster's target microtone.
  ///
  /// Sequence: Note-Off (old voice) → PitchBend (new bend) → Note-On (new
  /// voice). The synth always hears a clean attack at a pre-bent pitch — the
  /// envelope, vibrato LFO etc. retrigger from scratch, which is the whole
  /// point of the re-attack model (vs. continuous pitch-bend during a single
  /// envelope, which would feel like a slide and is NOT what this plugin
  /// emulates).
  ///
  /// `basePitch` is re-locked to the lowest currently-held pitch on every
  /// re-attack — this minimises bend saturation when the cluster moves
  /// significantly (e.g. user releases the original lowest key and the new
  /// lowest key is much higher).
  void _emitReattack(
    int ch,
    _MicrotoneChannelState s,
    List<TimestampedMidiEvent> output,
  ) {
    if (s.heldOrder.isEmpty) return; // safety — caller should have checked

    final oldBasePitch = s.basePitch;
    final newBasePitch = _lowestHeld(s);
    final targetPitch = _computeClusterTargetPitch(s);
    final newBend = _bendForOffset(targetPitch - newBasePitch);
    final velocity = _resolveOutputVelocity(s);

    if (s.sounding) {
      output.add(TimestampedMidiEvent(
        ppqPosition: 0,
        status: _noteOffStatus(ch),
        data1: oldBasePitch,
        data2: 0,
      ));
    }

    output.add(_pitchBendEvent(ch, newBend));

    output.add(TimestampedMidiEvent(
      ppqPosition: 0,
      status: _noteOnStatus(ch),
      data1: newBasePitch,
      data2: velocity,
    ));

    s.basePitch = newBasePitch;
    s.sounding = true;
  }

  /// Emit the cluster Note-Off.
  ///
  /// The pitch-bend is deliberately **not** reset to centre here. Pitch-bend
  /// is per-channel and also affects a voice in its release/decay tail, so
  /// snapping the bend to centre at Note-Off would audibly drop the still-
  /// ringing tail from the microtone down to the chromatic pitch — heard as a
  /// phantom note (most obvious on wide clusters like C+E, a whole-tone drop).
  /// We leave the bend where it is so the tail decays at the correct
  /// microtone; the next attack always sets its own bend before its Note-On,
  /// so no stale bend ever transposes a fresh note within the plugin.
  ///
  /// Always called from [processMidi]; see [_emitFirstAttack] for the
  /// rationale for not tagging events when the source is processMidi.
  void _emitClusterNoteOff(
    int ch,
    _MicrotoneChannelState s,
    List<TimestampedMidiEvent> output,
  ) {
    output.add(TimestampedMidiEvent(
      ppqPosition: 0,
      status: _noteOffStatus(ch),
      data1: s.basePitch,
      data2: 0,
    ));
    s.sounding = false;
  }

  /// Lowest currently-held MIDI pitch — the [_emitReattack] base note.
  ///
  /// Returns the held-set min so the bend offset is always upward (toward the
  /// cluster centre). Falls back to 60 (middle C) if the set is empty — a
  /// defensive value; callers must check `heldOrder.isNotEmpty` first.
  int _lowestHeld(_MicrotoneChannelState s) {
    if (s.heldOrder.isEmpty) return 60;
    var lo = s.heldOrder.first;
    for (final p in s.heldOrder) {
      if (p < lo) lo = p;
    }
    return lo;
  }

  // ── Cluster math ────────────────────────────────────────────────────────────

  /// Compute the target microtonal pitch (as a fractional MIDI number) for
  /// the current cluster, honouring [_clusterMode].
  ///
  /// **OuterAverage**: `(min + max) / 2` — midpoint between extremes.
  /// Two-note clusters always land halfway between the two notes.
  ///
  /// **MeanOfAll**: arithmetic mean of every held pitch — sensitive to
  /// inner-voice changes.
  double _computeClusterTargetPitch(_MicrotoneChannelState s) {
    if (s.heldOrder.isEmpty) return 60.0;
    if (s.heldOrder.length == 1) return s.heldOrder.first.toDouble();

    switch (_clusterMode) {
      case _MicrotoneClusterMode.outerAverage:
        var lo = s.heldOrder.first, hi = s.heldOrder.first;
        for (final p in s.heldOrder) {
          if (p < lo) lo = p;
          if (p > hi) hi = p;
        }
        return (lo + hi) / 2.0;
      case _MicrotoneClusterMode.meanOfAll:
        var sum = 0;
        for (final p in s.heldOrder) { sum += p; }
        return sum / s.heldOrder.length;
    }
  }

  /// Derive the single output velocity from the held set per [_velocityMode].
  ///
  /// Returns 100 (forte) as a defensive fallback for empty clusters — this
  /// should never be hit in normal use since velocity is only read at fire
  /// time, when at least one note is always held.
  int _resolveOutputVelocity(_MicrotoneChannelState s) {
    if (s.heldVelocity.isEmpty) return 100;

    switch (_velocityMode) {
      case _MicrotoneVelocityMode.average:
        var sum = 0;
        for (final v in s.heldVelocity.values) { sum += v; }
        return (sum / s.heldVelocity.length).round().clamp(1, 127);
      case _MicrotoneVelocityMode.lastNote:
        // _lastVelocity is updated on every user note-on, so it always
        // reflects the most recently pressed key in the cluster.
        return s.lastVelocity.clamp(1, 127);
    }
  }

  /// Convert a fractional semitone offset to a 14-bit pitch-bend value.
  ///
  /// MIDI pitch-bend uses a 14-bit unsigned integer centred at 8192:
  /// - 0 = full down by [_bendRangeSemitones] semitones,
  /// - 8192 = no bend,
  /// - 16383 = full up by [_bendRangeSemitones] semitones.
  ///
  /// Saturates at the extremes when the cluster spans more than the
  /// configured bend range — the user should raise [bendRange] in that case.
  int _bendForOffset(double offsetSemitones) {
    if (_bendRangeSemitones == 0) return _bendCentre;
    final scaled =
        (offsetSemitones / _bendRangeSemitones) * (_bendCentre - 1);
    return (_bendCentre + scaled.round()).clamp(0, 16383);
  }

  /// Pack a 14-bit pitch-bend value into a [TimestampedMidiEvent] on [ch].
  ///
  /// MIDI pitch-bend encoding: status = 0xE0 | channel, data1 = LSB (lower
  /// 7 bits), data2 = MSB (upper 7 bits). The receiver reconstructs the
  /// 14-bit value as `(data2 << 7) | data1`.
  TimestampedMidiEvent _pitchBendEvent(int ch, int bend14) {
    final clamped = bend14.clamp(0, 16383);
    return TimestampedMidiEvent(
      ppqPosition: 0,
      status: 0xE0 | (ch & 0x0F),
      data1: clamped & 0x7F,         // LSB — low 7 bits
      data2: (clamped >> 7) & 0x7F,  // MSB — high 7 bits
    );
  }

  // ── Utilities ───────────────────────────────────────────────────────────────

  /// Centre value of the 14-bit pitch-bend range — corresponds to "no bend".
  static const int _bendCentre = 8192;

  /// NOTE ON status byte for [channel] (0x9n, velocity > 0 required).
  int _noteOnStatus(int channel) => 0x90 | (channel & 0x0F);

  /// NOTE OFF status byte for [channel] (0x8n).
  int _noteOffStatus(int channel) => 0x80 | (channel & 0x0F);
}

/// Per-channel state for [MicrotoneNode].
///
/// Each of the 16 MIDI channels owns one of these to track the held set and
/// the cluster phase (idle → gathering → sounding).
class _MicrotoneChannelState {
  /// Pitches currently held by the player, in press order.
  final List<int> heldOrder = [];

  /// Velocity at which each held pitch was pressed.
  final Map<int, int> heldVelocity = {};

  /// Velocity of the most recently pressed key — used by [LastNote] mode.
  int lastVelocity = 100;

  /// Wall-clock timestamp (µs) when the current gather window opened — i.e.
  /// when the first key of a deferred cluster was pressed. The end-of-block
  /// check in [MicrotoneNode.processMidi] fires the deferred attack once
  /// `now - gatherStartUs >= _chordWindowUs`.
  int gatherStartUs = 0;

  /// True while a deferred cluster is gathering keys before its first attack.
  ///
  /// Set when the first key of a cluster is pressed and the attack delay is
  /// positive; cleared when the deferred attack (or an early release) fires.
  bool gathering = false;

  /// True while a release re-attack is waiting out its settle window.
  ///
  /// Set when a key is released from a sounding cluster (in deferred mode) and
  /// keys remain; cleared when the re-attack fires, when a press supersedes
  /// it, or when the rest of the cluster lifts (a clean stop).
  bool releasePending = false;

  /// Wall-clock timestamp (µs) when the pending release re-attack was queued.
  /// The end-of-block check fires it once `now - releaseStartUs >= _chordWindowUs`.
  int releaseStartUs = 0;

  /// True while the cluster Note-On is currently sounding.
  ///
  /// Goes true when the first attack fires; goes false on all-notes-off.
  bool sounding = false;

  /// MIDI pitch of the currently-sounding Note-On.
  ///
  /// Re-locked to the lowest held pitch on every re-attack so the bend offset
  /// stays small relative to the configured bend range.
  int basePitch = 60;

  /// Reset every field — called from [MicrotoneNode.initialize] so a project
  /// reload starts fresh.
  void clear() {
    heldOrder.clear();
    heldVelocity.clear();
    lastVelocity = 100;
    gatherStartUs = 0;
    gathering = false;
    releasePending = false;
    releaseStartUs = 0;
    sounding = false;
    basePitch = 60;
  }
}
