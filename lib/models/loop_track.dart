import 'dart:collection';

import 'chord_detector.dart';

// ── MIDI event ────────────────────────────────────────────────────────────────

/// A raw MIDI event captured during looper recording, tagged with its beat
/// position inside the loop.
///
/// [beatOffset] is measured in beats from the moment recording started (0.0 =
/// first note at record-start, 1.0 = one beat later, etc.).  This offset is
/// used during playback to schedule events at the correct musical position
/// relative to the loop's phase in the transport timeline.
class TimestampedMidiEvent {
  /// Position within the loop, in beats from loop start.
  final double beatOffset;

  /// MIDI status byte (e.g. 0x90 = note-on ch1, 0x80 = note-off ch1).
  final int status;

  /// First data byte (note number for note-on/off, CC number for CC events).
  final int data1;

  /// Second data byte (velocity for note-on/off, CC value for CC events).
  final int data2;

  const TimestampedMidiEvent({
    required this.beatOffset,
    required this.status,
    required this.data1,
    required this.data2,
  });

  Map<String, dynamic> toJson() => {
        'beatOffset': beatOffset,
        'status': status,
        'data1': data1,
        'data2': data2,
      };

  factory TimestampedMidiEvent.fromJson(Map<String, dynamic> json) =>
      TimestampedMidiEvent(
        beatOffset: (json['beatOffset'] as num).toDouble(),
        status: json['status'] as int,
        data1: json['data1'] as int,
        data2: json['data2'] as int,
      );
}

// ── Speed modifier ────────────────────────────────────────────────────────────

/// Playback speed multiplier applied to the loop's event timeline.
///
/// [half] halves the playback rate (slower, loop sounds longer),
/// [normal] plays at the recorded tempo,
/// [double_] doubles the rate (faster, loop sounds shorter).
enum LoopTrackSpeed {
  half,
  normal,
  double_,
}

/// Returns the numeric multiplier for [speed] (how fast beats advance in the
/// loop relative to the transport).
double speedMultiplier(LoopTrackSpeed speed) => switch (speed) {
      LoopTrackSpeed.half => 0.5,
      LoopTrackSpeed.normal => 1.0,
      LoopTrackSpeed.double_ => 2.0,
    };

// ── Loop track ────────────────────────────────────────────────────────────────

/// A single MIDI recording layer within a [LooperPluginInstance] slot.
///
/// Multiple [LoopTrack]s can coexist and play in parallel inside one looper
/// slot, enabling multi-layer overdubbing.  Each track is independent: it has
/// its own length, speed modifier, mute state, reverse flag, and per-bar
/// chord analysis.
///
/// **Beat-based timing model**: all event offsets are stored in *beats* (not
/// wall-clock milliseconds) so the loop remains in sync when the user changes
/// the BPM after recording.
class LoopTrack {
  /// Unique identifier for this track within its looper session.
  final String id;

  /// Length of the loop in beats, rounded to the nearest bar boundary when
  /// recording ends.  Null while the track is still being recorded.
  double? lengthInBeats;

  /// Recorded MIDI events, sorted by [TimestampedMidiEvent.beatOffset].
  final List<TimestampedMidiEvent> events;

  /// Whether playback is currently silenced without clearing the recording.
  bool muted;

  /// Whether the loop plays backward (events fire in reverse order).
  bool reversed;

  /// Playback speed relative to the transport tempo.
  LoopTrackSpeed speed;

  /// Chord identified per bar (0-based bar index → chord name string, or null
  /// if no chord was detected for that bar).  Populated during recording as
  /// each bar boundary is crossed.
  final Map<int, String?> chordPerBar;

  /// MIDI notes currently "on" during playback, packed as
  /// `(channelNibble << 7) | pitchByte`.  Not persisted — reset on load.
  ///
  /// Updated by [LooperEngine] as playback events fire.  Used to emit
  /// matching note-offs when the loop restarts (wrap-around) or when
  /// playback stops, preventing notes from being held indefinitely.
  final Set<int> activePlaybackNotes;

  LoopTrack({
    required this.id,
    this.lengthInBeats,
    List<TimestampedMidiEvent>? events,
    this.muted = false,
    this.reversed = false,
    this.speed = LoopTrackSpeed.normal,
    Map<int, String?>? chordPerBar,
  })  : events = events ?? [],
        chordPerBar = chordPerBar ?? {},
        activePlaybackNotes = {};

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Returns an unmodifiable view of [chordPerBar] for safe external access.
  UnmodifiableMapView<int, String?> get chordPerBarView =>
      UnmodifiableMapView(chordPerBar);

  /// Records the notes active during [bar] (0-based) and runs [ChordDetector]
  /// to produce a human-readable chord name.  Stores the result in [chordPerBar].
  ///
  /// Called by [LooperEngine] at each bar boundary during recording.
  void detectAndStoreChord(int bar, Set<int> notePitches) {
    if (notePitches.length < 3) {
      chordPerBar[bar] = null;
      return;
    }
    final match = ChordDetector.identifyChord(notePitches);
    chordPerBar[bar] = match?.name;
  }

  // ── JSON ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'lengthInBeats': lengthInBeats,
        'events': events.map((e) => e.toJson()).toList(),
        'muted': muted,
        'reversed': reversed,
        'speed': speed.name,
        'chordPerBar': chordPerBar.map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      };

  factory LoopTrack.fromJson(Map<String, dynamic> json) => LoopTrack(
        id: json['id'] as String,
        lengthInBeats: (json['lengthInBeats'] as num?)?.toDouble(),
        events: (json['events'] as List<dynamic>)
            .map((e) => TimestampedMidiEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
        muted: (json['muted'] as bool?) ?? false,
        reversed: (json['reversed'] as bool?) ?? false,
        speed: LoopTrackSpeed.values.firstWhere(
          (s) => s.name == (json['speed'] as String?),
          orElse: () => LoopTrackSpeed.normal,
        ),
        chordPerBar: (json['chordPerBar'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(int.parse(k), v as String?),
            ) ??
            {},
      );
}
