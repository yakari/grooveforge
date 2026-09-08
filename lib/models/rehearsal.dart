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

/// A Lamport stamp on one field, for last-writer-wins merging.
///
/// A wall clock cannot be used: phones disagree about the time, and a device
/// whose clock is a day slow would lose every edit it ever made. A Lamport
/// counter only has to be monotonic per device and larger than anything it has
/// seen, which is achievable offline.
///
/// [device] breaks ties. Two devices editing the same field while apart will
/// arrive at the same counter, and without a tiebreak they would each keep
/// their own value and never converge. Comparing device ids is arbitrary but
/// *symmetric*, which is the property that matters.
class FieldClock {
  const FieldClock(this.counter, this.device);

  final int counter;
  final String device;

  /// Whether this stamp wins against [other].
  bool beats(FieldClock other) {
    if (counter != other.counter) return counter > other.counter;
    return device.compareTo(other.device) > 0;
  }

  Map<String, dynamic> toJson() => {'c': counter, 'd': device};

  factory FieldClock.fromJson(Map<String, dynamic> json) => FieldClock(
        json['c'] as int? ?? 0,
        json['d'] as String? ?? '',
      );

  static const FieldClock zero = FieldClock(0, '');
}

/// Names of the mergeable metadata fields, so a typo cannot silently create a
/// field nobody ever compares.
class RehearsalField {
  static const title = 'title';
  static const bpm = 'bpm';
  static const beatsPerBar = 'beatsPerBar';
  static const beatUnit = 'beatUnit';
  static const countInBars = 'countInBars';
  static const master = 'master';
  static const joinKey = 'joinKey';

  static const all = [
    title,
    bpm,
    beatsPerBar,
    beatUnit,
    countInBars,
    master,
    joinKey,
  ];
}

/// A member of the group.
class RehearsalMember {
  RehearsalMember({
    required this.id,
    required this.displayName,
    required this.instrument,
    this.deviceId,
  });

  final String id;
  final String displayName;

  /// Instrument identifier from the curated list (see [kInstruments]).
  final String instrument;

  /// Which device this member plays on, so the room can tell who is present.
  ///
  /// Discovery works in device ids while the arrangement works in member ids;
  /// this is the only thing joining the two, and it is what lets a lane say
  /// whether the person who owns it is here right now.
  ///
  /// Nullable because rehearsals written before this existed have none, and
  /// because a member is not required to have a device at all — someone may
  /// have been added to the arrangement before they ever opened the tune.
  /// Written once, by that member's own device.
  String? deviceId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'instrument': instrument,
        if (deviceId != null) 'deviceId': deviceId,
      };

  factory RehearsalMember.fromJson(Map<String, dynamic> json) =>
      RehearsalMember(
        id: json['id'] as String,
        displayName: json['displayName'] as String? ?? '',
        instrument: json['instrument'] as String? ?? 'other',
        deviceId: json['deviceId'] as String?,
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

  /// Highest revision that has been deleted, so the next recording counts on
  /// from it rather than reusing a number a peer may already hold.
  int deletedRevision = 0;

  bool get isRecorded => take != null;

  /// The revision the next recording of this part will carry.
  int get nextRevision {
    final current = take?.revision ?? 0;
    return (current > deletedRevision ? current : deletedRevision) + 1;
  }

  /// Whether this part belongs to [memberId].
  bool isOwnedBy(String? memberId) =>
      memberId != null && memberId == this.memberId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'memberId': memberId,
        'instrument': instrument,
        if (deletedRevision > 0) 'deletedRevision': deletedRevision,
        if (take != null) 'take': take!.toJson(),
      };

  factory RehearsalPart.fromJson(Map<String, dynamic> json) => RehearsalPart(
        id: json['id'] as String,
        memberId: json['memberId'] as String? ?? '',
        instrument: json['instrument'] as String? ?? 'other',
        take: json['take'] == null
            ? null
            : RehearsalTake.fromJson(json['take'] as Map<String, dynamic>),
      )..deletedRevision = json['deletedRevision'] as int? ?? 0;
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
    required this.recordedBpm,
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

  /// The tempo this take was actually played at.
  ///
  /// Playing the tune at any other tempo means stretching this audio by
  /// `recordedBpm / newTempo`, so the number has to travel with the recording
  /// rather than be assumed from the tune's current setting — which is exactly
  /// the thing that changes. It also lets someone record a part while the tune
  /// is slowed down for practice and have it line up at full speed.
  final double recordedBpm;

  Duration get duration =>
      Duration(milliseconds: sampleRate > 0 ? frames * 1000 ~/ sampleRate : 0);

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'revision': revision,
        'frames': frames,
        'sampleRate': sampleRate,
        'compensationFrames': compensationFrames,
        'recordedAt': recordedAt.toIso8601String(),
        'recordedBpm': recordedBpm,
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
        // Zero means "recorded before takes carried a tempo". The library
        // fills it in from the tune's own tempo on load, which is right,
        // because nobody could have changed it before the field existed.
        recordedBpm: (json['recordedBpm'] as num?)?.toDouble() ?? 0.0,
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
    this.nativeBpm = 0.0,
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

  /// The tempo the grid was lined up to when this recording was anchored.
  ///
  /// A commercial recording has whatever tempo it has; tapping the beat and
  /// dragging the downbeat marker is how the tune's grid was fitted to it. If
  /// the tune's tempo later changes, this is what says how far the recording
  /// has to stretch to still fit. Zero means it predates the field, and the
  /// library fills it in from the tune's tempo on load.
  double nativeBpm;

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
        'nativeBpm': nativeBpm,
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
        nativeBpm: (json['nativeBpm'] as num?)?.toDouble() ?? 0.0,
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
    this.joinKey,
    required this.createdAt,
    required this.members,
    required this.parts,
    this.master,
    this.lamport = 0,
    Map<String, FieldClock>? clocks,
    Set<String>? deletedPartIds,
    Set<String>? deletedMemberIds,
  })  : clocks = clocks ?? {},
        deletedPartIds = deletedPartIds ?? {},
        deletedMemberIds = deletedMemberIds ?? {};

  final String id;
  String title;

  double bpm;
  int beatsPerBar;
  int beatUnit;

  /// Bars of metronome before recording begins. Part of the shared document so
  /// the whole band counts in the same way (decision D13).
  int countInBars;

  /// The shared secret the band syncs with, base64.
  ///
  /// A property of the *rehearsal*, not of a hosting session. Generating a
  /// fresh key each time someone starts sharing would mean a device that
  /// rediscovers a peer tomorrow still could not talk to it — the whole point
  /// of discovery is to reconnect without another introduction, and that needs
  /// a secret that outlives the introduction.
  ///
  /// It travels inside the document, which is not circular: everyone who has
  /// the document is already a member. The consequence worth knowing is that
  /// anyone who ever joins keeps access, because there is no re-keying.
  String? joinKey;

  final DateTime createdAt;
  final List<RehearsalMember> members;
  final List<RehearsalPart> parts;

  /// The recording everyone plays along to, if one was imported.
  RehearsalMaster? master;

  /// Parts that have been removed, by id.
  ///
  /// A tombstone rather than simply dropping the part, because parts merge by
  /// union: without a record that it was deleted, the next sync with anyone
  /// who still has it would put it straight back. The set only ever grows,
  /// which is what makes it converge with no coordination.
  final Set<String> deletedPartIds;

  /// Members that have been removed, by id.
  ///
  /// The same tombstone as [deletedPartIds] and for the same reason: members
  /// merge by union, so dropping one locally would last until the next sync
  /// with anyone who still had them.
  ///
  /// This is what makes removal work without everyone being present. The
  /// tombstone wins on merge whenever two documents meet, in either direction
  /// and in any order, so a device that was offline when someone was removed
  /// arrives at the same answer whenever it next syncs — no agreement, no
  /// quorum, and nothing that can fail because a bandmate went home.
  final Set<String> deletedMemberIds;

  bool get hasMaster => master != null;

  /// Highest counter this document has seen, from any device. A new edit
  /// stamps `lamport + 1`, which is what keeps counters monotonic across
  /// devices that have never been online at the same time.
  int lamport;

  /// Per-field Lamport stamps, for merging. A field with no stamp is treated
  /// as [FieldClock.zero], so a rehearsal created before syncing existed
  /// merges without a migration — it simply loses to any device that has
  /// touched the field since.
  final Map<String, FieldClock> clocks;

  FieldClock clockFor(String field) => clocks[field] ?? FieldClock.zero;

  /// Stamps [field] as edited by [deviceId] and advances the document clock.
  ///
  /// Every local edit to a mergeable field must go through this, or the edit
  /// is invisible to the merge and will be silently overwritten by a peer.
  void touch(String field, String deviceId) {
    lamport += 1;
    clocks[field] = FieldClock(lamport, deviceId);
  }

  /// The grid is frozen once any take exists: every recorded part is already
  /// aligned to it, and moving it would silently put them all in the wrong
  /// place with nothing in the audio to say which grid they were cut to.
  ///
  /// A master alone does not freeze it — its alignment is exactly what the
  /// player is still adjusting, and re-anchoring it changes only where the
  /// grid sits inside the recording.
  /// Whether changing the metre would strand the recordings.
  ///
  /// The tempo is deliberately *not* frozen: takes carry the tempo they were
  /// played at, so a change is a matter of stretching them to the new one. The
  /// metre is another matter — moving from 4/4 to 3/4 re-bars everything that
  /// was played, and there is no honest way to reinterpret a recording that
  /// was phrased in fours.
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
        if (joinKey != null) 'joinKey': joinKey,
        'createdAt': createdAt.toIso8601String(),
        'lamport': lamport,
        if (clocks.isNotEmpty)
          'clocks': clocks.map((k, v) => MapEntry(k, v.toJson())),
        'members': members.map((m) => m.toJson()).toList(),
        'parts': parts.map((p) => p.toJson()).toList(),
        if (master != null) 'master': master!.toJson(),
        if (deletedPartIds.isNotEmpty)
          'deletedPartIds': deletedPartIds.toList(),
        if (deletedMemberIds.isNotEmpty)
          'deletedMemberIds': deletedMemberIds.toList(),
      };

  factory Rehearsal.fromJson(Map<String, dynamic> json) => Rehearsal(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        bpm: (json['bpm'] as num?)?.toDouble() ?? 120.0,
        beatsPerBar: json['beatsPerBar'] as int? ?? 4,
        beatUnit: json['beatUnit'] as int? ?? 4,
        countInBars: json['countInBars'] as int? ?? 2,
        joinKey: json['joinKey'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        lamport: json['lamport'] as int? ?? 0,
        clocks: (json['clocks'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, FieldClock.fromJson(v as Map<String, dynamic>)),
        ),
        members: (json['members'] as List<dynamic>? ?? [])
            .map((m) => RehearsalMember.fromJson(m as Map<String, dynamic>))
            .toList(),
        parts: (json['parts'] as List<dynamic>? ?? [])
            .map((p) => RehearsalPart.fromJson(p as Map<String, dynamic>))
            .toList(),
        master: json['master'] == null
            ? null
            : RehearsalMaster.fromJson(json['master'] as Map<String, dynamic>),
        deletedMemberIds: (json['deletedMemberIds'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toSet(),
        deletedPartIds: (json['deletedPartIds'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toSet(),
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
    this.practiceSpeed = 1.0,
  })  : gains = gains ?? {},
        mutedPartIds = mutedPartIds ?? {};

  /// Which member this device is.
  String? selfMemberId;

  /// Per-part linear gain. Absent means 1.0.
  final Map<String, double> gains;

  final Set<String> mutedPartIds;

  /// Latency compensation measured on this device, in frames.
  int compensationFrames;

  /// The last join ticket used for this rehearsal, so a live session can be
  /// resumed without another introduction.
  ///
  /// Device-local by nature — it holds the shared key, and `self.json` never
  /// leaves the phone. It goes stale when the host restarts sharing, because
  /// the port and key are both new; that is what makes discovery the real
  /// answer rather than this.
  String? lastTicketUri;

  bool metronomeEnabled;

  /// How fast to play the tune here, as a fraction of its own tempo.
  ///
  /// 1.0 is the tune as written; 0.7 is a good speed for learning a passage.
  /// Deliberately *not* part of the shared document — it sits beside gain and
  /// mute because it is the same kind of thing. One person working a hard bar
  /// at half speed should not drag the rest of the band down with them, nor
  /// make every other device re-render its tracks.
  double practiceSpeed;

  /// The speed a tune actually plays at here, given its own tempo.
  double effectiveBpm(double tuneBpm) => tuneBpm * practiceSpeed;

  double gainFor(String partId) => gains[partId] ?? 1.0;
  bool isMuted(String partId) => mutedPartIds.contains(partId);

  Map<String, dynamic> toJson() => {
        'selfMemberId': selfMemberId,
        'gains': gains,
        'mutedPartIds': mutedPartIds.toList(),
        'compensationFrames': compensationFrames,
        'metronomeEnabled': metronomeEnabled,
        'practiceSpeed': practiceSpeed,
        if (lastTicketUri != null) 'lastTicketUri': lastTicketUri,
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
        practiceSpeed:
            (json['practiceSpeed'] as num?)?.toDouble().clamp(0.5, 1.0) ?? 1.0,
      )..lastTicketUri = json['lastTicketUri'] as String?;
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
