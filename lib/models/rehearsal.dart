/// A rehearsal: one tune a group works on together.
///
/// Rehearsals live in their own library rather than inside `.gf` project files
/// (see `docs/dev/REHEARSALS.md` §5.1). They hold multi-megabyte audio, they
/// are collaboratively owned, and they are never opened from a file picker —
/// all three pull the opposite way from a project file.
///
/// Everything in this file is the *shared* document: the part that will
/// eventually sync between band members. Personal mix decisions (mute, gain)
/// deliberately live elsewhere, in [RehearsalLocalState], because they are one
/// player's choice about their own monitoring and have no business travelling
/// to anyone else.
library;

import 'dart:math';

/// A member of the group.
class RehearsalMember {
  RehearsalMember({
    required this.id,
    required this.displayName,
    required this.instrument,
  });

  final String id;
  final String displayName;

  /// Instrument identifier from the curated list (see [kInstruments]).
  final String instrument;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'instrument': instrument,
      };

  factory RehearsalMember.fromJson(Map<String, dynamic> json) =>
      RehearsalMember(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        instrument: json['instrument'] as String? ?? 'other',
      );
}

/// One slot in the arrangement, owned by exactly one member.
///
/// Keyed separately from the member (decision D6) because one phone routinely
/// records a singer who also plays guitar; two parts, one member, and no
/// migration needed later to express it.
class RehearsalPart {
  RehearsalPart({
    required this.id,
    required this.memberId,
    required this.instrument,
    this.take,
  });

  final String id;
  final String memberId;
  final String instrument;

  /// The current take, or null if this part has not been recorded yet.
  RehearsalTake? take;

  bool get isRecorded => take != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'instrument': instrument,
        if (take != null) 'take': take!.toJson(),
      };

  factory RehearsalPart.fromJson(Map<String, dynamic> json) => RehearsalPart(
        id: json['id'] as String,
        memberId: json['memberId'] as String? ?? '',
        instrument: json['instrument'] as String? ?? 'other',
        take: json['take'] == null
            ? null
            : RehearsalTake.fromJson(json['take'] as Map<String, dynamic>),
      );
}

/// The audio for one part, aligned to grid frame 0.
///
/// Immutable once recorded: re-recording produces a new take with the next
/// [revision] rather than editing this one. That is what makes merging
/// conflict-free when parts start arriving from other devices — for each part,
/// the highest revision wins, and no two devices ever write the same one.
class RehearsalTake {
  RehearsalTake({
    required this.fileName,
    required this.revision,
    required this.frames,
    required this.sampleRate,
    required this.compensationFrames,
    required this.recordedAt,
  });

  /// File name within the rehearsal's `takes/` directory.
  final String fileName;

  final int revision;
  final int frames;
  final int sampleRate;

  /// Latency compensation applied when this take was cut, kept for the record
  /// rather than for playback — the shift is already baked into the audio.
  final int compensationFrames;

  final DateTime recordedAt;

  Duration get duration =>
      Duration(milliseconds: sampleRate > 0 ? frames * 1000 ~/ sampleRate : 0);

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'revision': revision,
        'frames': frames,
        'sampleRate': sampleRate,
        'compensationFrames': compensationFrames,
        'recordedAt': recordedAt.toIso8601String(),
      };

  factory RehearsalTake.fromJson(Map<String, dynamic> json) => RehearsalTake(
        fileName: json['fileName'] as String,
        revision: json['revision'] as int? ?? 1,
        frames: json['frames'] as int? ?? 0,
        sampleRate: json['sampleRate'] as int? ?? 48000,
        compensationFrames: json['compensationFrames'] as int? ?? 0,
        recordedAt:
            DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
                DateTime.now(),
      );
}

/// An imported recording the whole group plays along to.
///
/// Not a part: it belongs to the rehearsal rather than to a member, nobody
/// records over it, and it does not count towards "parts recorded". School
/// groups take on famous tunes, so starting from the real recording is often
/// how a rehearsal begins (REHEARSALS.md §7).
class RehearsalMaster {
  RehearsalMaster({
    required this.fileName,
    required this.sourceName,
    required this.frames,
    required this.sampleRate,
    this.offsetFrames = 0,
    this.importedAt,
  });

  /// Decoded mono 16-bit WAV inside the rehearsal's `master/` directory.
  final String fileName;

  /// Name of the file the user picked, shown so they can tell what this is.
  final String sourceName;

  final int frames;
  final int sampleRate;

  /// Which frame of the recording is grid frame 0 — the tune's first downbeat.
  ///
  /// Commercial recordings start with an intro, a count-in or simply a moment
  /// of room tone, so the grid has to be anchored to the downbeat rather than
  /// to the start of the file. Audio before this point is not played, because
  /// there is no grid there to play it against.
  int offsetFrames;

  final DateTime? importedAt;

  Duration get duration =>
      Duration(milliseconds: sampleRate > 0 ? frames * 1000 ~/ sampleRate : 0);

  /// Where the first downbeat sits, as a time into the recording.
  Duration get offset => Duration(
      milliseconds: sampleRate > 0 ? offsetFrames * 1000 ~/ sampleRate : 0);

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'sourceName': sourceName,
        'frames': frames,
        'sampleRate': sampleRate,
        'offsetFrames': offsetFrames,
        if (importedAt != null) 'importedAt': importedAt!.toIso8601String(),
      };

  factory RehearsalMaster.fromJson(Map<String, dynamic> json) =>
      RehearsalMaster(
        fileName: json['fileName'] as String,
        sourceName: json['sourceName'] as String? ?? '',
        frames: json['frames'] as int? ?? 0,
        sampleRate: json['sampleRate'] as int? ?? 48000,
        offsetFrames: json['offsetFrames'] as int? ?? 0,
        importedAt: DateTime.tryParse(json['importedAt'] as String? ?? ''),
      );
}

/// The whole rehearsal document.
class Rehearsal {
  Rehearsal({
    required this.id,
    required this.title,
    required this.bpm,
    required this.beatsPerBar,
    required this.beatUnit,
    required this.countInBars,
    required this.createdAt,
    required this.members,
    required this.parts,
    this.master,
    this.lamport = 0,
  });

  final String id;
  String title;

  double bpm;
  int beatsPerBar;
  int beatUnit;

  /// Bars of metronome before recording begins. Part of the shared document so
  /// the whole band counts in the same way (decision D13).
  int countInBars;

  final DateTime createdAt;
  final List<RehearsalMember> members;
  final List<RehearsalPart> parts;

  /// The recording everyone plays along to, if one was imported.
  RehearsalMaster? master;

  bool get hasMaster => master != null;

  /// Logical clock for last-writer-wins on the shared fields. Unused until
  /// syncing lands, but carried from the start so early rehearsals do not need
  /// a migration to gain it.
  int lamport;

  /// The grid is frozen once any take exists: every recorded part is already
  /// aligned to it, and moving it would silently put them all in the wrong
  /// place with nothing in the audio to say which grid they were cut to.
  ///
  /// A master alone does not freeze it — its alignment is exactly what the
  /// player is still adjusting, and re-anchoring it changes only where the
  /// grid sits inside the recording.
  bool get isGridFrozen => parts.any((p) => p.isRecorded);

  int get recordedPartCount => parts.where((p) => p.isRecorded).length;

  /// Longest take in frames — how much of the grid this rehearsal covers.
  int get lengthFrames => parts.fold(
      0, (m, p) => p.take != null && p.take!.frames > m ? p.take!.frames : m);

  Map<String, dynamic> toJson() => {
        'formatVersion': 1,
        'id': id,
        'title': title,
        'bpm': bpm,
        'beatsPerBar': beatsPerBar,
        'beatUnit': beatUnit,
        'countInBars': countInBars,
        'createdAt': createdAt.toIso8601String(),
        'lamport': lamport,
        'members': members.map((m) => m.toJson()).toList(),
        'parts': parts.map((p) => p.toJson()).toList(),
        if (master != null) 'master': master!.toJson(),
      };

  factory Rehearsal.fromJson(Map<String, dynamic> json) => Rehearsal(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        bpm: (json['bpm'] as num?)?.toDouble() ?? 120.0,
        beatsPerBar: json['beatsPerBar'] as int? ?? 4,
        beatUnit: json['beatUnit'] as int? ?? 4,
        countInBars: json['countInBars'] as int? ?? 2,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        lamport: json['lamport'] as int? ?? 0,
        members: (json['members'] as List<dynamic>? ?? [])
            .map((m) => RehearsalMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        parts: (json['parts'] as List<dynamic>? ?? [])
            .map((p) => RehearsalPart.fromJson(p as Map<String, dynamic>))
            .toList(),
        master: json['master'] == null
            ? null
            : RehearsalMaster.fromJson(json['master'] as Map<String, dynamic>),
      );
}

/// Per-device state that never leaves this phone.
///
/// Mute and gain are one player's monitoring choices, not facts about the
/// tune, so they are stored apart from the shared document and are never sent
/// to anyone (see REHEARSALS.md §5.1).
class RehearsalLocalState {
  RehearsalLocalState({
    this.selfMemberId,
    Map<String, double>? gains,
    Set<String>? mutedPartIds,
    this.compensationFrames = 0,
    this.metronomeEnabled = true,
  })  : gains = gains ?? {},
        mutedPartIds = mutedPartIds ?? {};

  /// Which member this device is.
  String? selfMemberId;

  /// Per-part linear gain. Absent means 1.0.
  final Map<String, double> gains;

  final Set<String> mutedPartIds;

  /// Latency compensation measured on this device, in frames.
  int compensationFrames;

  bool metronomeEnabled;

  double gainFor(String partId) => gains[partId] ?? 1.0;
  bool isMuted(String partId) => mutedPartIds.contains(partId);

  Map<String, dynamic> toJson() => {
        'selfMemberId': selfMemberId,
        'gains': gains,
        'mutedPartIds': mutedPartIds.toList(),
        'compensationFrames': compensationFrames,
        'metronomeEnabled': metronomeEnabled,
      };

  factory RehearsalLocalState.fromJson(Map<String, dynamic> json) =>
      RehearsalLocalState(
        selfMemberId: json['selfMemberId'] as String?,
        gains: (json['gains'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toDouble())),
        mutedPartIds: (json['mutedPartIds'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toSet(),
        compensationFrames: json['compensationFrames'] as int? ?? 0,
        metronomeEnabled: json['metronomeEnabled'] as bool? ?? true,
      );
}

/// The curated instrument list a part can be assigned.
///
/// Ported from the Sessions prototype and confirmed as covering a French
/// music-school intake, with `other` as the escape hatch so nobody is locked
/// out by an instrument nobody thought of.
const List<String> kInstruments = [
  'vocals',
  'guitar',
  'electricGuitar',
  'bassGuitar',
  'drums',
  'keyboard',
  'synth',
  'violin',
  'saxophone',
  'trumpet',
  'percussion',
  'other',
];

/// Generates an opaque identifier for a rehearsal, member, part or take.
///
/// Random rather than sequential because these identifiers become the keys the
/// sync layer merges on: two devices creating a part offline must not be able
/// to invent the same one.
String newRehearsalId([Random? rng]) {
  final r = rng ?? Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
}
