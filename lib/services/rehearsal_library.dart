import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/rehearsal.dart';

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
  RehearsalLibrary({Directory? rootOverride}) : _rootOverride = rootOverride;

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

  Future<File> _manifestFile(String id) async =>
      File('${(await rehearsalDir(id)).path}/rehearsal.json');

  Future<File> _localStateFile(String id) async =>
      File('${(await rehearsalDir(id)).path}/self.json');

  /// Absolute path of a take's audio file.
  Future<String> takePath(String rehearsalId, RehearsalTake take) async =>
      '${(await takesDir(rehearsalId)).path}/${take.fileName}';

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Reads every rehearsal in the library, newest first.
  ///
  /// A rehearsal whose manifest is unreadable is skipped rather than allowed
  /// to abort the whole load: one corrupt folder should cost the user that
  /// rehearsal, not their entire library.
  Future<void> load() async {
    _rehearsals.clear();
    final root = await _rootDir();
    final entries = await root.list().toList();
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final id = entry.path.split(Platform.pathSeparator).last;
      try {
        final file = await _manifestFile(id);
        if (!await file.exists()) continue;
        final json = jsonDecode(await file.readAsString());
        _rehearsals.add(Rehearsal.fromJson(json as Map<String, dynamic>));
      } catch (e) {
        debugPrint('RehearsalLibrary: skipping $id — $e');
      }
    }
    _rehearsals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _loaded = true;
    notifyListeners();
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
    final rehearsal = Rehearsal(
      id: newRehearsalId(),
      title: title,
      bpm: bpm,
      beatsPerBar: beatsPerBar,
      beatUnit: beatUnit,
      countInBars: countInBars,
      createdAt: DateTime.now(),
      members: [
        RehearsalMember(
          id: memberId,
          displayName: memberName,
          instrument: instrument,
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
  Future<void> save(Rehearsal rehearsal) async {
    final dir = await rehearsalDir(rehearsal.id);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = await _manifestFile(rehearsal.id);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
        const JsonEncoder.withIndent('  ').convert(rehearsal.toJson()));
    await tmp.rename(file.path);
    notifyListeners();
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
  }) async {
    final previous = part.take;
    part.take = RehearsalTake(
      fileName: fileName,
      revision: (previous?.revision ?? 0) + 1,
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
  String nextTakeFileName(RehearsalPart part) =>
      '${part.id}-${(part.take?.revision ?? 0) + 1}.wav';

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
