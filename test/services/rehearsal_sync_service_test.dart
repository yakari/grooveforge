import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/rehearsal.dart';
import 'package:grooveforge/services/rehearsal_discovery.dart';
import 'package:grooveforge/services/rehearsal_library.dart';
import 'package:grooveforge/services/rehearsal_protocol.dart';
import 'package:grooveforge/services/rehearsal_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Two whole devices, syncing.
///
/// Where `rehearsal_sync_test.dart` exercises the protocol against an
/// in-memory store, this drives the real thing: two [RehearsalLibrary]
/// instances on two temporary directories, a real listening socket, and the
/// filesystem adapter in between. The adapter is where a take's bytes meet its
/// file name, and getting that wrong would produce a sync that reports success
/// and leaves silence on the other device.
void main() {
  late Directory hostDir;
  late Directory guestDir;
  late RehearsalLibrary hostLibrary;
  late RehearsalLibrary guestLibrary;
  late RehearsalSyncService hostSync;
  late RehearsalSyncService guestSync;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    hostDir = await Directory.systemTemp.createTemp('gf_sync_host');
    guestDir = await Directory.systemTemp.createTemp('gf_sync_guest');
    hostLibrary = RehearsalLibrary(rootOverride: hostDir);
    guestLibrary = RehearsalLibrary(rootOverride: guestDir);
    await hostLibrary.load();
    await guestLibrary.load();
    // A real discovery object, but never started: these tests drive the
    // sockets directly, and mDNS is not available in the test environment.
    hostSync = RehearsalSyncService(hostLibrary, RehearsalDiscovery());
    guestSync = RehearsalSyncService(guestLibrary, RehearsalDiscovery());
  });

  tearDown(() async {
    await hostSync.stopHosting();
    await guestSync.stopHosting();
    if (await hostDir.exists()) await hostDir.delete(recursive: true);
    if (await guestDir.exists()) await guestDir.delete(recursive: true);
  });

  /// Writes plausible take audio and points the manifest at it.
  Future<void> giveTake(RehearsalLibrary library, Rehearsal r, RehearsalPart part,
      {int bytes = 40000}) async {
    final name = library.nextTakeFileName(part);
    final takes = await library.takesDir(r.id);
    await File('${takes.path}/$name')
        .writeAsBytes(List.generate(bytes, (i) => i % 251));
    await library.commitTake(r, part,
        fileName: name,
        frames: bytes ~/ 2,
        sampleRate: 48000,
        compensationFrames: 1390);
  }

  test('a guest who has never seen the rehearsal receives all of it', () async {
    final r = await hostLibrary.create(
        title: 'Autumn Leaves', memberName: 'Yann', instrument: 'guitar');
    await giveTake(hostLibrary, r, r.parts.single);

    final ticket = await hostSync.startHosting(r);
    expect(ticket, isNotNull, reason: hostSync.lastError ?? '');

    final report = await guestSync.join(ticket!);

    expect(report.ok, isTrue, reason: report.error ?? '');
    expect(report.takesReceived, 1);

    await guestLibrary.load();
    final theirs = guestLibrary.rehearsals.single;
    expect(theirs.id, r.id);
    expect(theirs.title, 'Autumn Leaves');
    expect(theirs.members.single.displayName, 'Yann');
    expect(theirs.parts.single.take!.revision, 1);

    // And the audio actually landed where the manifest says it is — the thing
    // a "sync succeeded" message would otherwise happily lie about.
    final take = theirs.parts.single.take!;
    final file = File(await guestLibrary.takePath(theirs.id, take));
    expect(await file.exists(), isTrue);
    expect(await file.length(), 40000);
    final original = File(await hostLibrary.takePath(r.id, r.parts.single.take!));
    expect(await file.readAsBytes(), await original.readAsBytes());
  });

  test('both sides end up with both parts', () async {
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');
    await giveTake(hostLibrary, r, r.parts.single, bytes: 12000);

    final ticket = await hostSync.startHosting(r);
    await guestSync.join(ticket!);

    // The guest now records a part of their own and syncs again, which is the
    // ordinary rhythm of the feature: meet, sync, go home, record, meet again.
    await guestLibrary.load();
    final theirs = guestLibrary.rehearsals.single;
    final guestPart = await guestLibrary
        .addPart(theirs, memberId: theirs.members.single.id, instrument: 'vocals');
    await giveTake(guestLibrary, theirs, guestPart, bytes: 7000);

    final second = await guestSync.join(ticket);
    expect(second.ok, isTrue, reason: second.error ?? '');
    expect(second.takesSent, 1);

    await hostLibrary.load();
    final hostCopy = hostLibrary.rehearsals.single;
    expect(hostCopy.parts, hasLength(2));
    final received = hostCopy.parts.firstWhere((p) => p.id == guestPart.id);
    expect(received.take, isNotNull);
    final file = File(await hostLibrary.takePath(hostCopy.id, received.take!));
    expect(await file.length(), 7000);
  });

  test('a re-recorded part replaces the older one on the peer', () async {
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');
    final part = r.parts.single;
    await giveTake(hostLibrary, r, part, bytes: 5000);

    final ticket = await hostSync.startHosting(r);
    await guestSync.join(ticket!);

    // The host is not happy with it and records again.
    await giveTake(hostLibrary, r, part, bytes: 9000);
    expect(part.take!.revision, 2);

    final second = await guestSync.join(ticket);
    expect(second.takesReceived, 1);

    await guestLibrary.load();
    final theirs = guestLibrary.rehearsals.single;
    expect(theirs.parts.single.take!.revision, 2);
    final file =
        File(await guestLibrary.takePath(theirs.id, theirs.parts.single.take!));
    expect(await file.length(), 9000);
  });

  test('syncing twice with nothing new moves nothing', () async {
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');
    await giveTake(hostLibrary, r, r.parts.single, bytes: 3000);

    final ticket = await hostSync.startHosting(r);
    final first = await guestSync.join(ticket!);
    expect(first.takesReceived, 1);

    final second = await guestSync.join(ticket);
    expect(second.ok, isTrue, reason: second.error ?? '');
    expect(second.takesReceived, 0);
    expect(second.takesSent, 0);
    expect(second.changed, isFalse,
        reason: 'a settled pair must stop exchanging data');
  });

  test('a wrong key is refused and leaves the guest with nothing', () async {
    final r = await hostLibrary.create(
        title: 'Secret', memberName: 'Yann', instrument: 'guitar');
    await giveTake(hostLibrary, r, r.parts.single);

    final ticket = await hostSync.startHosting(r);
    // Right address, wrong key: someone who typed a code from a different
    // rehearsal, or a stale QR from last week.
    final forged = JoinTicket(
      rehearsalId: ticket!.rehearsalId,
      key: JoinTicket.newKey(),
      host: ticket.host,
      port: ticket.port,
      title: ticket.title,
    );

    final report = await guestSync.join(forged);

    expect(report.ok, isFalse);
    await guestLibrary.load();
    // The shell exists because joining creates one before connecting, but
    // nothing of the host's got in.
    final theirs = guestLibrary.rehearsals.single;
    expect(theirs.parts, isEmpty);
    expect(theirs.members, isEmpty);
  });

  test('the tempo and metre reach a guest who has never seen the rehearsal',
      () async {
    // The bug this covers: nothing stamped the metadata fields, so every clock
    // stayed at zero, the merge never preferred the host's values, and a guest
    // silently kept the placeholder tempo while believing it had synced.
    final r = await hostLibrary.create(
      title: 'Waltz',
      memberName: 'Yann',
      instrument: 'guitar',
      bpm: 88,
      beatsPerBar: 3,
      countInBars: 1,
    );

    final ticket = await hostSync.startHosting(r);
    final report = await guestSync.join(ticket!);
    expect(report.ok, isTrue, reason: report.error ?? '');

    await guestLibrary.load();
    final theirs = guestLibrary.rehearsals.single;
    expect(theirs.bpm, 88, reason: 'the guest kept its placeholder tempo');
    expect(theirs.beatsPerBar, 3);
    expect(theirs.countInBars, 1);
    expect(theirs.title, 'Waltz');
  });

  test('an imported master reaches the guest, audio and all', () async {
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');

    // Stand in for the decoded master: importMaster goes through the native
    // decoder, which a unit test has no access to, but everything after it —
    // the stamp, the merge, the transfer — is what broke.
    final masterDir = await hostLibrary.masterDir(r.id);
    final audio = List.generate(30000, (i) => (i * 13) % 251);
    await File('${masterDir.path}/master.wav').writeAsBytes(audio);
    await hostLibrary.updateField(r, RehearsalField.master, () {
      r.master = RehearsalMaster(
        fileName: 'master.wav',
        sourceName: 'tune.mp3',
        frames: 15000,
        sampleRate: 48000,
        offsetFrames: 64883,
      );
    });

    final ticket = await hostSync.startHosting(r);
    final report = await guestSync.join(ticket!);

    expect(report.ok, isTrue, reason: report.error ?? '');
    expect(report.masterReceived, isTrue,
        reason: 'the master never left the host');

    await guestLibrary.load();
    final theirs = guestLibrary.rehearsals.single;
    expect(theirs.master, isNotNull);
    expect(theirs.master!.sourceName, 'tune.mp3');
    expect(theirs.master!.offsetFrames, 64883,
        reason: 'the grid anchor has to travel with the recording');

    final file = File(await guestLibrary.masterPath(theirs.id, theirs.master!));
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), audio);
  });

  test('re-anchoring the master syncs without moving the audio again',
      () async {
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');
    final masterDir = await hostLibrary.masterDir(r.id);
    await File('${masterDir.path}/master.wav')
        .writeAsBytes(List.filled(20000, 5));
    await hostLibrary.updateField(r, RehearsalField.master, () {
      r.master = RehearsalMaster(
        fileName: 'master.wav',
        sourceName: 'tune.mp3',
        frames: 10000,
        sampleRate: 48000,
      );
    });

    final ticket = await hostSync.startHosting(r);
    await guestSync.join(ticket!);

    // The host nudges the downbeat and syncs again.
    await hostLibrary.setMasterOffset(r, 12345);
    final second = await guestSync.join(ticket);

    expect(second.ok, isTrue, reason: second.error ?? '');
    expect(second.masterReceived, isFalse,
        reason: 'same recording — only the grid anchor moved');
    await guestLibrary.load();
    expect(guestLibrary.rehearsals.single.master!.offsetFrames, 12345);
  });

  test('a take recorded after joining reaches the other side', () async {
    // The live-session case: everyone is connected, one person records, and
    // the rest should get it without a fresh introduction.
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');
    final ticket = await hostSync.startHosting(r);
    await guestSync.join(ticket!);

    // The guest registers itself and records, exactly as the UI does.
    await guestLibrary.load();
    final theirs = guestLibrary.rehearsals.single;
    final mine =
        await guestLibrary.joinAsMember(theirs, name: 'Léa', instrument: 'vocals');
    await giveTake(guestLibrary, theirs, mine, bytes: 5000);

    // syncNow() is what the engine calls the moment a take is committed.
    guestSync.startLiveSync(
      rehearsalId: theirs.id,
      key: ticket.key,
      fallback: ticket,
    );
    await guestSync.syncNow();
    guestSync.stopLiveSync();

    await hostLibrary.load();
    final hostCopy = hostLibrary.rehearsals.single;
    expect(hostCopy.members.map((m) => m.displayName), contains('Léa'));
    final received = hostCopy.parts.firstWhere((p) => p.id == mine.id);
    expect(received.take, isNotNull, reason: 'the take never arrived');
    final file = File(await hostLibrary.takePath(hostCopy.id, received.take!));
    expect(await file.length(), 5000);
  });

  test('a deleted take is removed from the other side too', () async {
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');
    final part = r.parts.single;
    await giveTake(hostLibrary, r, part, bytes: 4000);

    final ticket = await hostSync.startHosting(r);
    await guestSync.join(ticket!);
    await guestLibrary.load();
    expect(guestLibrary.rehearsals.single.parts.single.take, isNotNull);

    // The host is not happy with it and deletes rather than re-records.
    await hostLibrary.deleteTake(r, part);
    await guestSync.join(ticket);

    await guestLibrary.load();
    final theirs = guestLibrary.rehearsals.single.parts.single;
    expect(theirs.take, isNull, reason: 'the deletion did not travel');
    expect(theirs.deletedRevision, 1);

    // And it stays deleted: the guest must not hand it back next time.
    await guestSync.join(ticket);
    await hostLibrary.load();
    expect(hostLibrary.rehearsals.single.parts.single.take, isNull);
  });

  test('receiving audio signals that the engine must reload', () async {
    // The bug this covers: the take merged into the manifest and appeared in
    // the lane, but nothing told the engine to open the file, so it played
    // silence. Merging a document and opening an audio track are two separate
    // things and the second has to be asked for.
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');
    await giveTake(hostLibrary, r, r.parts.single, bytes: 6000);

    var signalled = 0;
    guestSync.onAudioReceived = () => signalled++;

    final ticket = await hostSync.startHosting(r);
    final first = await guestSync.join(ticket!);

    expect(first.takesReceived, 1);
    expect(signalled, 1, reason: 'the engine was never told to reload');

    // And a sync that brings nothing must not churn the engine.
    final second = await guestSync.join(ticket);
    expect(second.takesReceived, 0);
    expect(signalled, 1, reason: 'reloaded for a sync that moved no audio');
  });

  test('the merged document is the one the library is holding', () async {
    // Syncing used to reload the library afterwards, which swapped in fresh
    // objects and left any open screen holding a stale one. The merge mutates
    // the live document instead, so a caller's reference stays correct.
    final r = await hostLibrary.create(
        title: 'Tune', memberName: 'Yann', instrument: 'guitar');
    final ticket = await hostSync.startHosting(r);
    await guestSync.join(ticket!);

    await guestLibrary.load();
    final held = guestLibrary.rehearsals.single;

    // The guest records and pushes; the host's in-memory object must show it
    // without anyone reloading.
    final mine = await guestLibrary.joinAsMember(held,
        name: 'Léa', instrument: 'vocals');
    await giveTake(guestLibrary, held, mine, bytes: 2000);
    await guestSync.join(ticket);

    expect(identical(hostLibrary.rehearsals.single, r), isTrue,
        reason: 'the library swapped the document out from under its holder');
    expect(r.parts.any((p) => p.id == mine.id), isTrue,
        reason: 'the object the caller holds did not see the merge');
  });

  test('the device id survives a restart', () async {
    final first = await hostSync.deviceId();
    final again =
        await RehearsalSyncService(hostLibrary, RehearsalDiscovery()).deviceId();
    // A fresh id each launch would make the merge's tiebreak non-deterministic
    // and two devices could fail to converge.
    expect(again, first);
    expect(first, isNotEmpty);
  });
}
