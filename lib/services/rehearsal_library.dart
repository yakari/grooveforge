import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rehearsal.dart';
import 'audio_input_ffi.dart';
import 'rehearsal_protocol.dart';
import 'rehearsal_tempo_cache.dart';
import 'platform_media_decoder.dart';

/// Preference key for this device's stable identity.
const String kRehearsalDeviceIdKey = 'gf.rehearsal.deviceId';

String? _cachedDeviceId;

/// This device's identity, stable across launches.
///
/// It breaks ties when two devices edit the same field while apart, so it has
/// to survive a restart: a fresh id each launch would make the tiebreak
/// non-deterministic and two devices could fail to converge.
Future<String> rehearsalDeviceId() async {
  if (_cachedDeviceId != null) return _cachedDeviceId!;
  try {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(kRehearsalDeviceIdKey);
    if (id == null || id.isEmpty) {
      id = newRehearsalId();
      await prefs.setString(kRehearsalDeviceIdKey, id);
    }
    _cachedDeviceId = id;
    return id;
  } catch (e) {
    // Preferences being unavailable must not stop someone creating a
    // rehearsal. The cost of this fallback is that the id lasts only as long
    // as the process, so the merge's tiebreak stops being deterministic across
    // restarts — a far smaller problem than refusing to work at all.
    debugPrint('rehearsalDeviceId: falling back to a temporary id — $e');
    _cachedDeviceId = newRehearsalId();
    return _cachedDeviceId!;
  }
}

/// Owns the on-disk library of rehearsals.
///
/// Layout under the app documents directory (REHEARSALS.md §5.1):
///
/// ```
/// rehearsals/
///   <rehearsalId>/
///     rehearsal.json   the shared document — title, grid, members, parts
///     takes/
///       <partId>-<rev>.wav
///     self.json        never leaves the device — my mutes, gains, nudge
/// ```
///
/// Deliberately separate from [ProjectService] and the `.gf` format: different
/// lifetime, different ownership, and orders of magnitude more bytes.
class RehearsalLibrary extends ChangeNotifier {
  RehearsalLibrary({Directory? rootOverride, this.deviceIdOverride})
      : _rootOverride = rootOverride;

  /// Injected by tests so they can run against a temporary directory instead
  /// of the real documents directory.
  final Directory? _rootOverride;

  Directory? _root;
  final List<Rehearsal> _rehearsals = [];
  bool _loaded = false;

  List<Rehearsal> get rehearsals => List.unmodifiable(_rehearsals);
  bool get isLoaded => _loaded;

  /// Root directory of the library, created on first use.
  Future<Directory> _rootDir() async {
    if (_root != null) return _root!;
    final base = _rootOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/rehearsals');
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  Future<Directory> rehearsalDir(String id) async =>
      Directory('${(await _rootDir()).path}/$id');

  Future<Directory> takesDir(String id) async {
    final dir = Directory('${(await rehearsalDir(id)).path}/takes');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> masterDir(String id) async {
    final dir = Directory('${(await rehearsalDir(id)).path}/master');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _manifestFile(String id) async =>
      File('${(await rehearsalDir(id)).path}/rehearsal.json');

  Future<File> _localStateFile(String id) async =>
      File('${(await rehearsalDir(id)).path}/self.json');

  /// Absolute path of a take's audio file.
  /// Where recordings rendered to a practice tempo live.
  ///
  /// Inside the rehearsal so deleting the tune takes them with it, and separate
  /// from `takes/` so the originals are never at risk from a cache sweep.
  /// Everything in here is derived and disposable.
  Future<Directory> tempoDir(String id) async {
    final dir = Directory(
        '${(await rehearsalDir(id)).path}/${RehearsalTempoCache.dirName}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<String> takePath(String rehearsalId, RehearsalTake take) async =>
      '${(await takesDir(rehearsalId)).path}/${take.fileName}';

  /// Absolute path of the decoded master.
  Future<String> masterPath(String rehearsalId, RehearsalMaster master) async =>
      '${(await masterDir(rehearsalId)).path}/${master.fileName}';

  // ── Master track ──────────────────────────────────────────────────────────

  /// Imports [sourcePath] as the rehearsal's master track.
  ///
  /// Decodes to the one format the engine streams — mono 16-bit at 48 kHz —
  /// rather than keeping the original and decoding on the fly: the conversion
  /// happens once, here, and playback then costs no more than a recorded take.
  ///
  /// Returns the new master, or null if the file could not be decoded. The
  /// decode is blocking and proportional to the file's length, so callers
  /// should show progress.
  Future<RehearsalMaster?> importMaster(
    Rehearsal rehearsal,
    String sourcePath, {
    int sampleRate = 48000,
  }) async {
    final ffi = AudioInputFFI();
    final dir = await masterDir(rehearsal.id);
    const fileName = 'master.wav';
    final dst = '${dir.path}/$fileName';

    // Two decoders, one path. The bundled one handles MP3, FLAC and WAV on
    // every platform; anything else goes through the platform's own codecs
    // first, which produce a WAV the bundled one can then fold to mono and
    // resample. That intermediate file is the price of not having to write a
    // resampler twice.
    var decodable = ffi.mediaCanDecode(sourcePath);
    String? intermediate;
    if (!decodable) {
      if (!PlatformMediaDecoder.isSupported) {
        debugPrint('RehearsalLibrary: cannot decode $sourcePath');
        return null;
      }
      intermediate = '${dir.path}/source-decoded.wav';
      final res = await PlatformMediaDecoder.decodeToWav(sourcePath, intermediate);
      if (res == null || res.frames <= 0) {
        debugPrint('RehearsalLibrary: platform decode failed for $sourcePath');
        await _deleteQuietly(intermediate);
        return null;
      }
      decodable = true;
    }

    final frames = ffi.mediaToMonoWav(
        intermediate ?? sourcePath, dst, sampleRate: sampleRate);
    // The intermediate has served its purpose either way; leaving it behind
    // would silently double what a rehearsal costs on disk.
    if (intermediate != null) await _deleteQuietly(intermediate);
    if (frames <= 0) {
      debugPrint('RehearsalLibrary: import failed ($frames)');
      return null;
    }

    rehearsal.master = RehearsalMaster(
      fileName: fileName,
      sourceName: sourcePath.split(Platform.pathSeparator).last,
      frames: frames,
      sampleRate: sampleRate,
      importedAt: DateTime.now(),
      // Whatever the tune is set to now is what this recording will be lined
      // up against, so it is also what it would have to stretch away from.
      nativeBpm: rehearsal.bpm,
    );
    rehearsal.touch(RehearsalField.master, await deviceId());
    await save(rehearsal);

    // With a recording to play along to, the click is redundant and mostly in
    // the way: the players hear the real thing and lock to it far better than
    // to a metronome. They can turn it back on.
    final local = await loadLocalState(rehearsal.id);
    local.metronomeEnabled = false;
    await saveLocalState(rehearsal.id, local);

    return rehearsal.master;
  }

  /// Deletes a file, ignoring the case where it was never created.
  Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('RehearsalLibrary: could not delete $path — $e');
    }
  }

  /// Moves the grid's first downbeat to [offsetFrames] inside the recording.
  Future<void> setMasterOffset(Rehearsal rehearsal, int offsetFrames) async {
    final master = rehearsal.master;
    if (master == null) return;
    master.offsetFrames = offsetFrames < 0 ? 0 : offsetFrames;
    rehearsal.touch(RehearsalField.master, await deviceId());
    await save(rehearsal);
  }

  /// Removes the master and its audio.
  Future<void> removeMaster(Rehearsal rehearsal) async {
    final master = rehearsal.master;
    if (master == null) return;
    try {
      final f = File(await masterPath(rehearsal.id, master));
      if (await f.exists()) await f.delete();
    } catch (e) {
      debugPrint('RehearsalLibrary: could not delete master — $e');
    }
    rehearsal.master = null;
    rehearsal.touch(RehearsalField.master, await deviceId());
    await save(rehearsal);
  }

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Reads every rehearsal in the library, newest first.
  ///
  /// A rehearsal whose manifest is unreadable is skipped rather than allowed
  /// to abort the whole load: one corrupt folder should cost the user that
  /// rehearsal, not their entire library.
  Future<void> load() async {
    // Built into a local list and swapped in at the end, rather than clearing
    // the live one first. Two loads can overlap — a sync finishing while the
    // UI reloads, say — and clear-then-append would have both of them append
    // to an already-cleared list, leaving every rehearsal in it twice.
    final loaded = <Rehearsal>[];
    final root = await _rootDir();
    final entries = await root.list().toList();
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final id = entry.path.split(Platform.pathSeparator).last;
      try {
        final file = await _manifestFile(id);
        if (!await file.exists()) continue;
        final json = jsonDecode(await file.readAsString());
        loaded.add(Rehearsal.fromJson(json as Map<String, dynamic>));
      } catch (e) {
        debugPrint('RehearsalLibrary: skipping $id — $e');
      }
    }
    loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final r in loaded) {
      await _stampIfUnstamped(r);
      await _claimOwnMember(r);
      await _stampTempos(r);
    }

    _rehearsals
      ..clear()
      ..addAll(loaded);
    _loaded = true;
    notifyListeners();
  }

  /// Stands in for the real device identity.
  ///
  /// The identity lives in shared preferences, which are per *process*, so two
  /// libraries running in one test would otherwise be the same device. That
  /// matters more than it sounds: a peer whose id matches your own is filtered
  /// out of discovery as yourself, which quietly turns a two-device test into
  /// a one-device one. Null everywhere outside tests.
  final String? deviceIdOverride;

  /// This device's identity, and the single place anything in the library asks
  /// for it, so a rehearsal's member stamps and its field clocks can never
  /// disagree about who wrote them.
  Future<String> deviceId() async =>
      deviceIdOverride ?? await rehearsalDeviceId();

  /// Gives a rehearsal written before field stamps existed a set of them.
  ///
  /// Without this, everything created earlier carries a zero clock on every
  /// field, loses every comparison, and can never sync its tempo, metre,
  /// count-in or master — the manifest transfers and the values quietly stay
  /// as they were.
  ///
  /// Only rehearsals with actual content are stamped. A placeholder created by
  /// joining has no members and no parts, and stamping *it* would let a
  /// joiner's default tempo beat the real one it is about to receive.
  Future<void> _stampIfUnstamped(Rehearsal r) async {
    if (r.clocks.isNotEmpty) return;
    final hasContent =
        r.members.isNotEmpty || r.parts.isNotEmpty || r.master != null;
    if (!hasContent) return;

    // A rehearsal from before keys belonged to the document needs one, or it
    // can never be rediscovered — only re-introduced by QR.
    r.joinKey ??= base64.encode(JoinTicket.newKey());

    final device = await deviceId();
    for (final field in RehearsalField.all) {
      if (field == RehearsalField.master && r.master == null) continue;
      r.touch(field, device);
    }
    await save(r);
    debugPrint('RehearsalLibrary: stamped "${r.title}" for syncing');
  }

  /// Records which device the local member plays on, if it is not already
  /// known.
  ///
  /// Rehearsals written before members carried a device id have none, so their
  /// owner would show as away in their own room. Only this device's own member
  /// is stamped: nobody else's device id is ours to write, and the others fill
  /// theirs in on their own machines and sync it across.
  /// Gives takes and masters written before tempo change existed their tempo.
  ///
  /// The tune's own tempo is the right answer for all of them: the fields did
  /// not exist, so nobody can have changed the tempo, so everything on disk
  /// was recorded and anchored at exactly this one.
  Future<void> _stampTempos(Rehearsal r) async {
    var changed = false;
    for (final part in r.parts) {
      final take = part.take;
      if (take == null || take.recordedBpm > 0) continue;
      part.take = RehearsalTake(
        fileName: take.fileName,
        revision: take.revision,
        frames: take.frames,
        sampleRate: take.sampleRate,
        compensationFrames: take.compensationFrames,
        recordedAt: take.recordedAt,
        recordedBpm: r.bpm,
      );
      changed = true;
    }
    final master = r.master;
    if (master != null && master.nativeBpm <= 0) {
      master.nativeBpm = r.bpm;
      changed = true;
    }
    if (changed) await save(r);
  }

  Future<void> _claimOwnMember(Rehearsal r) async {
    final selfId = (await loadLocalState(r.id)).selfMemberId;
    if (selfId == null) return;
    final me = r.members.where((m) => m.id == selfId).firstOrNull;
    if (me == null || me.deviceId != null) return;
    me.deviceId = await deviceId();
    await save(r);
  }

  // ── Creating and saving ───────────────────────────────────────────────────

  /// Creates a rehearsal with one member and one part for them, and writes it.
  Future<Rehearsal> create({
    required String title,
    required String memberName,
    required String instrument,
    double bpm = 120.0,
    int beatsPerBar = 4,
    int beatUnit = 4,
    int countInBars = 2,
  }) async {
    final memberId = newRehearsalId();
    final device = await deviceId();
    final rehearsal = Rehearsal(
      id: newRehearsalId(),
      title: title,
      bpm: bpm,
      beatsPerBar: beatsPerBar,
      beatUnit: beatUnit,
      countInBars: countInBars,
      joinKey: base64.encode(JoinTicket.newKey()),
      createdAt: DateTime.now(),
      members: [
        RehearsalMember(
          id: memberId,
          displayName: memberName,
          instrument: instrument,
          deviceId: device,
        ),
      ],
      parts: [
        RehearsalPart(
          id: newRehearsalId(),
          memberId: memberId,
          instrument: instrument,
        ),
      ],
    );

    // Every mergeable field is stamped here. Without it the creator's tempo,
    // metre and count-in all carry a zero clock, and a joiner's placeholder —
    // which also has zero clocks — would never be overwritten by them. The
    // rehearsal would sync its parts and quietly keep the wrong tempo.
    for (final field in RehearsalField.all) {
      if (field == RehearsalField.master) continue; // there is no master yet
      rehearsal.touch(field, device);
    }

    await save(rehearsal);
    await saveLocalState(
        rehearsal.id, RehearsalLocalState(selfMemberId: memberId));
    _rehearsals.insert(0, rehearsal);
    notifyListeners();
    return rehearsal;
  }

  /// Writes the shared document.
  ///
  /// Written to a temporary file and renamed, so a crash mid-write leaves the
  /// previous manifest intact rather than a truncated one that would take the
  /// rehearsal's whole track list with it.
  Future<void> save(Rehearsal rehearsal) {
    // Saves are serialised. Two can now overlap easily — a device both hosts
    // and polls, so an incoming sync and an outgoing one can be writing the
    // same manifest at once — and interleaved writes to one temporary file end
    // with the first rename succeeding and the second failing with ENOENT,
    // silently losing whatever the second was saving.
    _saveChain = _saveChain.then((_) => _save(rehearsal));
    return _saveChain;
  }

  Future<void> _saveChain = Future<void>.value();

  Future<void> _save(Rehearsal rehearsal) async {
    final dir = await rehearsalDir(rehearsal.id);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = await _manifestFile(rehearsal.id);
    // A unique temporary name as well as the queue, so nothing outside this
    // instance — a second library object, a crash mid-write — can collide.
    final tmp = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await tmp.writeAsString(
          const JsonEncoder.withIndent('  ').convert(rehearsal.toJson()));
      await tmp.rename(file.path);
    } catch (e) {
      debugPrint('RehearsalLibrary: save failed — $e');
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    notifyListeners();
  }

  /// Changes a mergeable field and stamps it, so the edit can win a merge.
  ///
  /// Everything that edits [Rehearsal.title], the grid or the count-in must go
  /// through here: an unstamped edit is invisible to the merge and will be
  /// silently replaced by whatever a peer has.
  Future<void> updateField(
    Rehearsal rehearsal,
    String field,
    void Function() apply,
  ) async {
    apply();
    rehearsal.touch(field, await deviceId());
    await save(rehearsal);
  }

  /// Registers this device's player in a rehearsal it has just joined, and
  /// gives them a part of their own.
  ///
  /// Joining creates an empty placeholder and the merge fills it with the
  /// host's members and parts — none of which are *this* player. Without this
  /// step the device has no identity in the rehearsal at all, so anything it
  /// records is attributed to whoever shared the tune, and every lane carries
  /// their name.
  Future<RehearsalPart> joinAsMember(
    Rehearsal rehearsal, {
    required String name,
    required String instrument,
  }) async {
    final member = RehearsalMember(
      id: newRehearsalId(),
      displayName: name,
      instrument: instrument,
      deviceId: await deviceId(),
    );
    rehearsal.members.add(member);

    final part = RehearsalPart(
      id: newRehearsalId(),
      memberId: member.id,
      instrument: instrument,
    );
    rehearsal.parts.add(part);
    await save(rehearsal);

    final local = await loadLocalState(rehearsal.id);
    local.selfMemberId = member.id;
    await saveLocalState(rehearsal.id, local);
    return part;
  }

  /// Removes a take and the audio it points at.
  ///
  /// The revision is *not* rolled back: the next recording carries on from
  /// where this one left off. A peer that already has revision 3 must not be
  /// sent a different revision 3 later — take numbers have to keep going up
  /// for the merge to stay conflict-free.
  Future<void> deleteTake(Rehearsal rehearsal, RehearsalPart part) async {
    final take = part.take;
    if (take == null) return;
    try {
      final file = File(await takePath(rehearsal.id, take));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('RehearsalLibrary: could not delete take — $e');
    }
    part.deletedRevision = take.revision;
    part.take = null;
    await save(rehearsal);
  }

  /// Removes a part entirely, along with any recording it holds.
  ///
  /// Different from [deleteTake], which keeps the lane so it can be recorded
  /// again. This is for a part that should not be there at all — added by
  /// mistake, or for an instrument nobody ended up playing.
  Future<void> deletePart(Rehearsal rehearsal, RehearsalPart part) async {
    final take = part.take;
    if (take != null) {
      try {
        final file = File(await takePath(rehearsal.id, take));
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('RehearsalLibrary: could not delete take — $e');
      }
    }
    // The tombstone has to be recorded before the part is dropped, or a sync
    // with anyone who still has it would put it straight back.
    rehearsal.deletedPartIds.add(part.id);
    rehearsal.parts.removeWhere((p) => p.id == part.id);
    await save(rehearsal);
  }

  /// Removes a member and everything they own.
  ///
  /// Wanted for a stale identity: a device that was wiped, reinstalled or
  /// handed on joins again as a *new* member, and the old one sits in the band
  /// for good because members merge by union.
  ///
  /// Deliberately not a vote among the people present. Removal is a tombstone,
  /// which is the conflict-free way to take something out of a grow-only set:
  /// it wins on merge in either direction and in any order, so every device
  /// reaches the same answer whenever it next syncs. A quorum would instead
  /// make this the one operation in the whole feature that needs everybody
  /// online at once — and a band between rehearsals is almost never that.
  ///
  /// Their parts go with them, because a part belongs to exactly one member
  /// (D6) and leaving them behind would attribute recordings to nobody. The
  /// caller is expected to say how many recordings that is before asking.
  Future<void> removeMember(Rehearsal rehearsal, String memberId) async {
    for (final part in rehearsal.parts.where((p) => p.memberId == memberId)) {
      final take = part.take;
      if (take == null) continue;
      try {
        final file = File(await takePath(rehearsal.id, take));
        if (await file.exists()) await file.delete();
      } catch (e) {
        debugPrint('RehearsalLibrary: could not delete take — $e');
      }
    }
    // Tombstones before the removal, or a sync with anyone who still has them
    // would put both the member and their parts straight back.
    rehearsal.deletedMemberIds.add(memberId);
    for (final part in rehearsal.parts.where((p) => p.memberId == memberId)) {
      rehearsal.deletedPartIds.add(part.id);
    }
    rehearsal.parts.removeWhere((p) => p.memberId == memberId);
    rehearsal.members.removeWhere((m) => m.id == memberId);
    await save(rehearsal);
  }

  /// Adds a part for [member], creating the member if this is their first.
  Future<RehearsalPart> addPart(
    Rehearsal rehearsal, {
    required String memberId,
    required String instrument,
  }) async {
    final part = RehearsalPart(
      id: newRehearsalId(),
      memberId: memberId,
      instrument: instrument,
    );
    rehearsal.parts.add(part);
    await save(rehearsal);
    return part;
  }

  /// Records a freshly captured take against [part], bumping its revision and
  /// deleting the file the previous revision used.
  ///
  /// Old revisions are removed because takes are the only thing here large
  /// enough to matter, and keeping every attempt would grow a band's storage
  /// without bound for no benefit — v1 keeps the latest (decision from §10).
  Future<void> commitTake(
    Rehearsal rehearsal,
    RehearsalPart part, {
    required String fileName,
    required int frames,
    required int sampleRate,
    required int compensationFrames,
    required double recordedBpm,
  }) async {
    final previous = part.take;
    part.take = RehearsalTake(
      fileName: fileName,
      // The tempo it was *played* at, which is not always the tune's: someone
      // learning a passage records at half speed, and this is what lets the
      // take be put back where it belongs when the band returns to tempo.
      recordedBpm: recordedBpm,
      // From nextRevision, not from the current take: after a deletion there
      // *is* no current take, and counting from zero would hand the new
      // recording the same number as the one just deleted. A peer holding that
      // number would then see "same revision, same take", refuse to fetch the
      // new audio, and apply the deletion tombstone to what it already had —
      // losing the part entirely while the re-recording never arrived.
      revision: part.nextRevision,
      frames: frames,
      sampleRate: sampleRate,
      compensationFrames: compensationFrames,
      recordedAt: DateTime.now(),
    );
    await save(rehearsal);

    if (previous != null && previous.fileName != fileName) {
      try {
        final old = File(await takePath(rehearsal.id, previous));
        if (await old.exists()) await old.delete();
      } catch (e) {
        debugPrint('RehearsalLibrary: could not delete old take — $e');
      }
    }
  }

  /// File name for the next take of [part].
  ///
  /// Counts on from whichever is higher: the take that is there, or the last
  /// one deleted. Reusing a number a peer already holds would make two
  /// different recordings share a revision, and the merge would keep whichever
  /// it saw first.
  String nextTakeFileName(RehearsalPart part) =>
      '${part.id}-${part.nextRevision}.wav';

  /// Deletes a rehearsal and every take it owns.
  Future<void> delete(String id) async {
    try {
      final dir = await rehearsalDir(id);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (e) {
      debugPrint('RehearsalLibrary: delete failed — $e');
    }
    _rehearsals.removeWhere((r) => r.id == id);
    notifyListeners();
  }

  /// Total bytes a rehearsal occupies, for the size shown in the library.
  Future<int> sizeOnDisk(String id) async {
    var total = 0;
    try {
      final dir = await rehearsalDir(id);
      if (!await dir.exists()) return 0;
      await for (final e in dir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } catch (e) {
      debugPrint('RehearsalLibrary: size failed — $e');
    }
    return total;
  }

  // ── Local state ───────────────────────────────────────────────────────────

  Future<RehearsalLocalState> loadLocalState(String id) async {
    try {
      final file = await _localStateFile(id);
      if (!await file.exists()) return RehearsalLocalState();
      final json = jsonDecode(await file.readAsString());
      return RehearsalLocalState.fromJson(json as Map<String, dynamic>);
    } catch (e) {
      debugPrint('RehearsalLibrary: local state unreadable — $e');
      return RehearsalLocalState();
    }
  }

  Future<void> saveLocalState(String id, RehearsalLocalState state) async {
    final dir = await rehearsalDir(id);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = await _localStateFile(id);
    await file.writeAsString(jsonEncode(state.toJson()));
  }
}
