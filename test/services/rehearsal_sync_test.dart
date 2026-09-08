import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/rehearsal.dart';
import 'package:grooveforge/services/rehearsal_protocol.dart';
import 'package:grooveforge/services/rehearsal_sync.dart';

/// Drives two real sync sessions against each other over a loopback socket.
///
/// Not a mock in sight for the transport: framing across TCP reads, the
/// handshake, and the encrypted channel are exactly the things a mock would
/// agree with while the real socket disagreed. The store is an in-memory
/// implementation, because the filesystem is not what is under test here.
class _MemoryStore implements SyncStore {
  _MemoryStore(this.doc);

  Rehearsal? doc;

  /// Audio keyed by *file name*, exactly as the real store keys it on disk.
  ///
  /// Not by part id: file names carry the revision, so keying by part would
  /// make "holds the old take but not the new one" unrepresentable — which is
  /// the whole state an interrupted transfer leaves behind.
  final Map<String, Uint8List> files = {};

  Uint8List? master;
  int saves = 0;

  /// Puts audio in place for a part's current take.
  void give(String partId, Uint8List bytes) {
    final name = _fileNameFor(partId);
    if (name != null) files[name] = bytes;
  }

  /// What a part's current take is stored under, or null if it has no take.
  String? _fileNameFor(String partId) =>
      doc?.parts.where((p) => p.id == partId).firstOrNull?.take?.fileName;

  /// Audio held for a part's current take, or null.
  Uint8List? audioFor(String partId) {
    final name = _fileNameFor(partId);
    return name == null ? null : files[name];
  }

  @override
  Future<Rehearsal?> load(String rehearsalId) async => doc;

  @override
  Future<void> save(Rehearsal rehearsal) async {
    doc = rehearsal;
    saves++;
  }

  @override
  Future<Uint8List?> readTake(String rehearsalId, String partId) async =>
      audioFor(partId);

  @override
  Future<void> writeTake(
      String rehearsalId, String partId, Uint8List bytes) async {
    final name = _fileNameFor(partId);
    if (name != null) files[name] = bytes;
  }

  @override
  Future<bool> hasTake(String rehearsalId, String partId) async =>
      audioFor(partId)?.isNotEmpty ?? false;

  @override
  Future<Uint8List?> readMaster(String rehearsalId) async => master;

  @override
  Future<bool> hasMaster(String rehearsalId) async =>
      master?.isNotEmpty ?? false;

  /// Documents, keyed by id. They never change, so unlike takes there is no
  /// revision for the key to have to carry.
  final Map<String, Uint8List> documents = {};

  @override
  Future<Uint8List?> readDocument(String rehearsalId, String documentId) async =>
      documents[documentId];

  @override
  Future<void> writeDocument(
      String rehearsalId, String documentId, Uint8List bytes) async {
    documents[documentId] = bytes;
  }

  @override
  Future<bool> hasDocument(String rehearsalId, String documentId) async =>
      documents[documentId]?.isNotEmpty ?? false;

  @override
  Future<void> writeMaster(String rehearsalId, Uint8List bytes) async {
    master = bytes;
  }
}

Rehearsal _doc({String title = 'Tune', int lamport = 0}) => Rehearsal(
      id: 'reh-1',
      title: title,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      createdAt: DateTime(2026, 1, 1),
      members: [],
      parts: [],
      lamport: lamport,
    );

RehearsalPart _part(String id, {int? revision}) {
  final p = RehearsalPart(id: id, memberId: 'm1', instrument: 'guitar');
  if (revision != null) {
    p.take = RehearsalTake(
      fileName: '$id-$revision.wav',
      revision: revision,
      frames: 1000,
      sampleRate: 48000,
      compensationFrames: 0,
      recordedAt: DateTime(2026, 1, 1),
      recordedBpm: 120,
    );
  }
  return p;
}

/// Runs both ends of a sync and returns their reports.
Future<(SyncReport, SyncReport)> _sync(
  _MemoryStore serverStore,
  _MemoryStore clientStore, {
  Uint8List? serverKey,
  Uint8List? clientKey,
}) async {
  final key = serverKey ?? JoinTicket.newKey();
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);

  final serverDone = Completer<SyncReport>();
  final sub = server.listen((socket) async {
    final session = SyncSession(
      socket: socket,
      store: serverStore,
      key: key,
      rehearsalId: 'reh-1',
      deviceId: 'server-device',
      isClient: false,
    );
    serverDone.complete(await session.run());
  });

  final socket = await Socket.connect(server.address, server.port);
  final clientSession = SyncSession(
    socket: socket,
    store: clientStore,
    key: clientKey ?? key,
    rehearsalId: 'reh-1',
    deviceId: 'client-device',
    isClient: true,
  );
  final clientReport = await clientSession.run();
  final serverReport = await serverDone.future;

  await sub.cancel();
  await server.close();
  return (serverReport, clientReport);
}

/// The three-device relay: A records, B has the manifest but not yet the audio,
/// C syncs with B.
///
/// This is the shape that stranded a take in real use. B hands C a manifest for
/// a revision whose bytes B does not have, B skips the blob silently, and C
/// writes down the revision. From then on their revisions match and nothing is
/// ever fetched again.
void _relayGroup() {
  test('a manifest without its audio is asked for again next time', () async {
    // B knows about take 2 but has no bytes for it — mid-relay.
    final relayStore = _MemoryStore(_doc()..parts.add(_part('p1', revision: 2)));
    final tabletStore = _MemoryStore(_doc()..parts.add(_part('p1', revision: 1)))
      ..give('p1', Uint8List.fromList(List.filled(500, 7)));

    await _sync(relayStore, tabletStore);

    // The tablet took the manifest, as it should: the take really is newer.
    expect(tabletStore.doc!.parts.single.take!.revision, 2);
    // But the audio never came, because the relay had none to give. This is
    // the reported symptom exactly: the lane shows the new take's duration
    // while the only recording on disk belongs to the previous one.
    expect(tabletStore.audioFor('p1'), isNull,
        reason: 'the manifest moved to a take whose audio never arrived');
    expect(tabletStore.files.keys, contains('p1-1.wav'));

    // The relay catches up.
    relayStore.give('p1', Uint8List.fromList(List.filled(9000, 3)));

    // Revisions now match on both sides, so the merge alone would ask for
    // nothing. The audio has to be what decides it.
    final (_, second) = await _sync(relayStore, tabletStore);

    expect(second.takesReceived, 1,
        reason: 'a take whose audio is missing must be re-requested');
    expect(tabletStore.audioFor('p1')!.length, 9000);
  });

  test('a take with no audio anywhere is not re-fetched forever', () async {
    // Neither side has the bytes. Asking is harmless; the peer simply skips it.
    final a = _MemoryStore(_doc()..parts.add(_part('p1', revision: 1)));
    final b = _MemoryStore(_doc()..parts.add(_part('p1', revision: 1)));

    final (server, client) = await _sync(a, b);

    expect(server.ok, isTrue);
    expect(client.ok, isTrue);
    expect(client.takesReceived, 0);
  });

  test('an empty file counts as missing', () async {
    // An interrupted write leaves a file that exists and plays nothing.
    final full = _MemoryStore(_doc()..parts.add(_part('p1', revision: 1)))
      ..give('p1', Uint8List.fromList(List.filled(4000, 5)));
    final truncated = _MemoryStore(_doc()..parts.add(_part('p1', revision: 1)))
      ..give('p1', Uint8List(0));

    final (_, client) = await _sync(full, truncated);

    expect(client.takesReceived, 1);
    expect(truncated.audioFor('p1')!.length, 4000);
  });
}

/// Documents over the wire: added on one device, opened on another.
void _documentGroup() {
  RehearsalDocument score(String id) => RehearsalDocument(
        id: id,
        fileName: '$id.pdf',
        sourceName: 'score.pdf',
        bytes: 4000,
        addedBy: 'm1',
        addedAt: DateTime(2026, 1, 1),
      );

  test('a score and its file both reach the other side', () async {
    final owner = _MemoryStore(_doc()..documents.add(score('d1')))
      ..documents['d1'] = Uint8List.fromList(List.filled(4000, 9));
    final other = _MemoryStore(_doc());

    final (_, client) = await _sync(owner, other);

    expect(client.ok, isTrue);
    expect(other.doc!.documents.single.sourceName, 'score.pdf');
    expect(other.documents['d1'], hasLength(4000),
        reason: 'the manifest alone is a card that opens nothing');
  });

  test('a file that never arrived is asked for again next time', () async {
    // The same hazard as takes: the manifest saves before the bytes move, and
    // a document has no revision to compare, so nothing would ask twice.
    final relay = _MemoryStore(_doc()..documents.add(score('d1')));
    final other = _MemoryStore(_doc());

    await _sync(relay, other);
    expect(other.doc!.documents, hasLength(1));
    expect(other.documents['d1'], isNull, reason: 'the relay had no bytes');

    relay.documents['d1'] = Uint8List.fromList(List.filled(4000, 3));
    await _sync(relay, other);

    expect(other.documents['d1'], hasLength(4000));
  });

  test('a removed score is not handed back by a peer who kept it', () async {
    final keeper = _MemoryStore(_doc()..documents.add(score('d1')))
      ..documents['d1'] = Uint8List.fromList(List.filled(10, 1));
    final remover = _MemoryStore(_doc()..deletedDocumentIds.add('d1'));

    await _sync(keeper, remover);

    expect(remover.doc!.documents, isEmpty);
    expect(keeper.doc!.documents, isEmpty,
        reason: 'the tombstone travels the other way too');
  });
}

void main() {
  group('shared documents', _documentGroup);

  group('incomplete transfers', _relayGroup);

  group('framing', () {
    test('reassembles a frame split across reads', () async {
      final reader = FrameReader();
      final got = <Frame>[];
      reader.frames.listen(got.add);

      final frame = encodeControl({'type': 'hello', 'v': 1});
      // One byte at a time — the worst case TCP can hand us.
      for (final byte in frame) {
        reader.add([byte]);
      }
      await Future<void>.delayed(Duration.zero);

      expect(got, hasLength(1));
      expect(got.single.json['type'], 'hello');
    });

    test('splits several frames arriving in one read', () async {
      final reader = FrameReader();
      final got = <Frame>[];
      reader.frames.listen(got.add);

      reader.add([
        ...encodeControl({'type': 'a'}),
        ...encodeControl({'type': 'b'}),
        ...encodeControl({'type': 'c'}),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(got.map((f) => f.json['type']), ['a', 'b', 'c']);
    });

    test('rejects an implausible length instead of allocating it', () async {
      final reader = FrameReader();
      final errors = <Object>[];
      reader.frames.listen((_) {}, onError: errors.add);

      // A peer claiming a gigabyte, whether malicious or just desynchronised.
      reader.add([0xFF, 0xFF, 0xFF, 0xFF, 0x00]);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
    });
  });

  group('join ticket', () {
    test('round-trips through its URI form', () {
      final key = JoinTicket.newKey();
      final ticket = JoinTicket(
        rehearsalId: 'reh-1',
        key: key,
        host: '192.168.1.24',
        port: 47821,
        title: 'Autumn Leaves',
      );

      final parsed = JoinTicket.parse(ticket.toUri())!;
      expect(parsed.rehearsalId, 'reh-1');
      expect(parsed.key, key);
      expect(parsed.host, '192.168.1.24');
      expect(parsed.port, 47821);
      expect(parsed.title, 'Autumn Leaves');
    });

    test('a title with spaces and accents survives', () {
      final ticket = JoinTicket(
        rehearsalId: 'r',
        key: JoinTicket.newKey(),
        host: '10.0.0.1',
        port: 5,
        title: 'Les Feuilles mortes & Cie',
      );
      expect(JoinTicket.parse(ticket.toUri())!.title, 'Les Feuilles mortes & Cie');
    });

    test('some other QR code is not mistaken for ours', () {
      expect(JoinTicket.parse('https://example.com'), isNull);
      expect(JoinTicket.parse('WIFI:S:home;T:WPA;P:secret;;'), isNull);
      expect(JoinTicket.parse('gf-rehearsal:v1?id=x'), isNull,
          reason: 'ours, but missing the endpoint');
    });

    test('a bare short code is refused, because it cannot carry a key', () {
      // Six characters can hold neither the 32-byte key nor the address, so
      // there is no way to find the host or prove you were invited. Anything
      // that looks like one must be rejected rather than half-accepted.
      expect(JoinTicket.parse('YGFMDY'), isNull);
      expect(JoinTicket.parse('P272SX'), isNull);
    });
  });

  group('a full session', () {
    test('moves a take the peer does not have', () async {
      final serverDoc = _doc()..parts.add(_part('p1', revision: 1));
      final serverStore = _MemoryStore(serverDoc)
        ..give('p1', Uint8List.fromList(List.generate(5000, (i) => i % 256)));

      final clientStore = _MemoryStore(_doc());

      final (server, client) = await _sync(serverStore, clientStore);

      expect(server.ok, isTrue, reason: server.error ?? '');
      expect(client.ok, isTrue, reason: client.error ?? '');
      expect(client.takesReceived, 1);
      expect(server.takesSent, 1);
      expect(clientStore.audioFor('p1'), serverStore.audioFor('p1'));
      expect(clientStore.doc!.parts.single.take!.revision, 1);
    });

    test('moves takes in both directions at once', () async {
      final serverStore = _MemoryStore(_doc()..parts.add(_part('pS', revision: 1)))
        ..give('pS', Uint8List.fromList(List.filled(3000, 7)));
      final clientStore = _MemoryStore(_doc()..parts.add(_part('pC', revision: 1)))
        ..give('pC', Uint8List.fromList(List.filled(2000, 9)));

      final (server, client) = await _sync(serverStore, clientStore);

      expect(server.ok && client.ok, isTrue);
      expect(clientStore.audioFor('pS'), hasLength(3000));
      expect(serverStore.audioFor('pC'), hasLength(2000));
      expect(clientStore.doc!.parts.map((p) => p.id).toSet(), {'pC', 'pS'});
      expect(serverStore.doc!.parts.map((p) => p.id).toSet(), {'pC', 'pS'});
    });

    test('a take larger than one chunk arrives byte-for-byte', () async {
      // Deliberately not a multiple of the chunk size, so the last chunk is
      // short — the case an off-by-one in the loop would corrupt.
      final big = Uint8List.fromList(
          List.generate(kBlobChunkBytes * 3 + 1234, (i) => (i * 31) % 256));
      final serverStore = _MemoryStore(_doc()..parts.add(_part('p1', revision: 1)))
        ..give('p1', big);
      final clientStore = _MemoryStore(_doc());

      final (_, client) = await _sync(serverStore, clientStore);

      expect(client.ok, isTrue, reason: client.error ?? '');
      expect(clientStore.audioFor('p1'), big);
    });

    test('the master travels too', () async {
      final serverDoc = _doc()
        ..master = RehearsalMaster(
          fileName: 'master.wav',
          sourceName: 'tune.mp3',
          frames: 960000,
          sampleRate: 48000,
          offsetFrames: 64883,
        )
        ..touch(RehearsalField.master, 'server-device');
      final serverStore = _MemoryStore(serverDoc)
        ..master = Uint8List.fromList(List.filled(9000, 3));
      final clientStore = _MemoryStore(_doc());

      final (_, client) = await _sync(serverStore, clientStore);

      expect(client.ok, isTrue, reason: client.error ?? '');
      expect(client.masterReceived, isTrue);
      expect(clientStore.master, hasLength(9000));
      expect(clientStore.doc!.master!.offsetFrames, 64883);
    });

    test('nothing moves when both sides already agree', () async {
      final serverStore = _MemoryStore(_doc()..parts.add(_part('p1', revision: 2)))
        ..give('p1', Uint8List.fromList([1, 2, 3]));
      final clientStore = _MemoryStore(_doc()..parts.add(_part('p1', revision: 2)))
        ..give('p1', Uint8List.fromList([1, 2, 3]));

      final (server, client) = await _sync(serverStore, clientStore);

      expect(client.takesReceived, 0);
      expect(server.takesReceived, 0);
      expect(client.changed, isFalse);
      expect(clientStore.saves, 0, reason: 'no change means no write');
    });
  });

  group('authentication', () {
    test('a different join code is refused by both sides', () async {
      final serverStore = _MemoryStore(_doc()..parts.add(_part('p1', revision: 1)))
        ..give('p1', Uint8List.fromList([1, 2, 3]));
      final clientStore = _MemoryStore(_doc());

      final (server, client) = await _sync(
        serverStore,
        clientStore,
        serverKey: JoinTicket.newKey(),
        clientKey: JoinTicket.newKey(),
      );

      expect(client.ok, isFalse);
      expect(server.ok, isFalse);
      // And nothing leaked before the refusal.
      expect(clientStore.files, isEmpty);
      expect(clientStore.doc!.parts, isEmpty);
    });

    test('the proof both sides compute is identical, and key-specific', () {
      final key = JoinTicket.newKey();
      final a = SyncCrypto(key);
      final b = SyncCrypto(key);
      final n1 = SyncCrypto.newNonce();
      final n2 = SyncCrypto.newNonce();

      expect(a.proof(n1, n2), b.proof(n1, n2));
      expect(a.proof(n1, n2), isNot(a.proof(n2, n1)),
          reason: 'nonce order must matter, or a proof could be replayed back');
      expect(a.proof(n1, n2), isNot(SyncCrypto(JoinTicket.newKey()).proof(n1, n2)));
    });

    test('constant-time compare still gets the answer right', () {
      expect(SyncCrypto.constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
      expect(SyncCrypto.constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
      expect(SyncCrypto.constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });
  });

  group('the encrypted channel', () {
    test('round-trips, and rejects a tampered frame', () async {
      final crypto = SyncCrypto(JoinTicket.newKey());
      final plain = List.generate(500, (i) => i % 256);

      final sealed = await crypto.seal(plain);
      expect(await crypto.open(sealed), plain);

      // Flip one bit in the ciphertext: the MAC must catch it.
      final tampered = Uint8List.fromList(sealed);
      tampered[20] ^= 0x01;
      expect(() => crypto.open(tampered), throwsA(anything));
    });

    test('a different key cannot open it', () async {
      final sealed = await SyncCrypto(JoinTicket.newKey()).seal([1, 2, 3]);
      expect(() => SyncCrypto(JoinTicket.newKey()).open(sealed),
          throwsA(anything));
    });

    test('the same plaintext seals differently each time', () async {
      final crypto = SyncCrypto(JoinTicket.newKey());
      final a = await crypto.seal([1, 2, 3]);
      final b = await crypto.seal([1, 2, 3]);
      expect(a, isNot(b), reason: 'a fixed nonce would leak repeated messages');
    });
  });
}
