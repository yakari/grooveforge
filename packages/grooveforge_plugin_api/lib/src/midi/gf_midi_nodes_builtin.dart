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

// ─────────────────────────────────────────────────────────────────────────────
//  ArpeggiateNode  ("arpeggiate")
// ─────────────────────────────────────────────────────────────────────────────

/// Step division durations in quarter-note beats.
///
/// | Index | Name   | Beats   | At 120 BPM |
/// |-------|--------|---------|------------|
/// | 0     | 1/4    | 1.000   | 500 ms     |
/// | 1     | 1/8    | 0.500   | 250 ms     |
/// | 2     | 1/16   | 0.250   | 125 ms     |
/// | 3     | 1/32   | 0.125   |  62 ms     |
/// | 4     | 1/64   | 0.0625  |  31 ms     |
/// | 5     | 1/4T   | 0.667   | 333 ms     |
/// | 6     | 1/8T   | 0.333   | 167 ms     |
/// | 7     | 1/16T  | 0.167   |  83 ms     |
/// | 8     | 1/32T  | 0.083   |  42 ms     |
///
/// Triplet values use exact fractions (2/3, 1/3, 1/6, 1/12 beats) so they
/// stay precisely in a three-against-two relationship at any tempo.
const List<double> _kArpDivisionBeats = [
  1.0,      // 0 — 1/4
  0.5,      // 1 — 1/8
  0.25,     // 2 — 1/16
  0.125,    // 3 — 1/32
  0.0625,   // 4 — 1/64
  2 / 3,    // 5 — 1/4T
  1 / 3,    // 6 — 1/8T
  1 / 6,    // 7 — 1/16T
  1 / 12,   // 8 — 1/32T
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
        // 9 options (indices 0–8) → normalise by (9 − 1) = 8.
        _divisionIndex = (normalizedValue * 8).round().clamp(0, 8);
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
