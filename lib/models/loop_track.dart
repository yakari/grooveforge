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

// ── Record-stop quantization ──────────────────────────────────────────────────

/// Grid resolution applied to all recorded events when the user stops
/// recording, snapping each event's [TimestampedMidiEvent.beatOffset] to the
/// nearest rhythmic subdivision.
///
/// Quantization is destructive: the snapped offsets are written back into
/// [LoopTrack.events] so they persist in the project file.  The original
/// (loose) timings are not retained after the snap.
///
/// Values represent the note subdivision relative to a beat (quarter note):
/// - [off]          — no snapping; timings are kept exactly as played.
/// - [quarter]      — snap to the nearest quarter note (1 beat).
/// - [eighth]       — snap to the nearest eighth note (½ beat).
/// - [sixteenth]    — snap to the nearest sixteenth note (¼ beat).
/// - [thirtySecond] — snap to the nearest thirty-second note (⅛ beat).
enum LoopQuantize {
  off,
  quarter,
  eighth,
  sixteenth,
  thirtySecond;

  /// Returns the beat distance between adjacent grid lines for this quantize
  /// value, assuming a quarter-note beat unit.
  ///
  /// Returns 0.0 for [off] — callers should check for [off] before dividing.
  double get gridBeats => switch (this) {
        LoopQuantize.off => 0.0,
        LoopQuantize.quarter => 1.0,
        LoopQuantize.eighth => 0.5,
        LoopQuantize.sixteenth => 0.25,
        LoopQuantize.thirtySecond => 0.125,
      };

  /// Short display label used in the looper track controls chip.
  String get label => switch (this) {
        LoopQuantize.off => 'off',
        LoopQuantize.quarter => '1/4',
        LoopQuantize.eighth => '1/8',
        LoopQuantize.sixteenth => '1/16',
        LoopQuantize.thirtySecond => '1/32',
      };

  /// The next value in the cycling sequence for the UI chip toggle.
  LoopQuantize get next => switch (this) {
        LoopQuantize.off => LoopQuantize.quarter,
        LoopQuantize.quarter => LoopQuantize.eighth,
        LoopQuantize.eighth => LoopQuantize.sixteenth,
        LoopQuantize.sixteenth => LoopQuantize.thirtySecond,
        LoopQuantize.thirtySecond => LoopQuantize.off,
      };
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
/// its own length, speed modifier, mute state, reverse flag, and quantize
/// setting.
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

  /// Grid resolution applied to recorded events when the user presses stop.
  ///
  /// When set to anything other than [LoopQuantize.off], [LooperEngine] snaps
  /// every [TimestampedMidiEvent.beatOffset] in [events] to the nearest grid
  /// line at the end of each recording pass (including overdubs).  The setting
  /// is persisted in the project file and applies independently per track.
  LoopQuantize quantize;

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
    this.quantize = LoopQuantize.off,
  })  : events = events ?? [],
        activePlaybackNotes = {};

  // ── Helpers ─────────────────────────────────────────────────────────────

  /// Returns the total number of bars in this loop, given [beatsPerBar] from
  /// the transport's time signature numerator.  Returns 0 when the track has
  /// not finished recording yet.
  int barCount(int beatsPerBar) {
    final len = lengthInBeats;
    if (len == null || len <= 0) return 0;
    // Bars are always whole numbers because lengthInBeats is quantised to the
    // nearest bar boundary when recording stops.
    return (len / beatsPerBar).round();
  }

  // ── JSON ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id': id,
        'lengthInBeats': lengthInBeats,
        'events': events.map((e) => e.toJson()).toList(),
        'muted': muted,
        'reversed': reversed,
        'speed': speed.name,
        'quantize': quantize.name,
      };

  /// Deserializes a [LoopTrack] from JSON.
  ///
  /// Backward-compatible: silently ignores the legacy `chordPerBar` field
  /// present in project files saved before the chord-detection removal.
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
        quantize: LoopQuantize.values.firstWhere(
          (q) => q.name == (json['quantize'] as String?),
          orElse: () => LoopQuantize.off,
        ),
        // Note: 'chordPerBar' is intentionally not read — old files may still
        // contain it but we no longer use per-bar chord detection.
      );
}
