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
  final Map<String, Uint8List> takes = {};
  Uint8List? master;
  int saves = 0;

  @override
  Future<Rehearsal?> load(String rehearsalId) async => doc;

  @override
  Future<void> save(Rehearsal rehearsal) async {
    doc = rehearsal;
    saves++;
  }

  @override
  Future<Uint8List?> readTake(String rehearsalId, String partId) async =>
      takes[partId];

  @override
  Future<void> writeTake(
      String rehearsalId, String partId, Uint8List bytes) async {
    takes[partId] = bytes;
  }

  @override
  Future<Uint8List?> readMaster(String rehearsalId) async => master;

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

void main() {
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
        ..takes['p1'] = Uint8List.fromList(List.generate(5000, (i) => i % 256));

      final clientStore = _MemoryStore(_doc());

      final (server, client) = await _sync(serverStore, clientStore);

      expect(server.ok, isTrue, reason: server.error ?? '');
      expect(client.ok, isTrue, reason: client.error ?? '');
      expect(client.takesReceived, 1);
      expect(server.takesSent, 1);
      expect(clientStore.takes['p1'], serverStore.takes['p1']);
      expect(clientStore.doc!.parts.single.take!.revision, 1);
    });

    test('moves takes in both directions at once', () async {
      final serverStore = _MemoryStore(_doc()..parts.add(_part('pS', revision: 1)))
        ..takes['pS'] = Uint8List.fromList(List.filled(3000, 7));
      final clientStore = _MemoryStore(_doc()..parts.add(_part('pC', revision: 1)))
        ..takes['pC'] = Uint8List.fromList(List.filled(2000, 9));

      final (server, client) = await _sync(serverStore, clientStore);

      expect(server.ok && client.ok, isTrue);
      expect(clientStore.takes['pS'], hasLength(3000));
      expect(serverStore.takes['pC'], hasLength(2000));
      expect(clientStore.doc!.parts.map((p) => p.id).toSet(), {'pC', 'pS'});
      expect(serverStore.doc!.parts.map((p) => p.id).toSet(), {'pC', 'pS'});
    });

    test('a take larger than one chunk arrives byte-for-byte', () async {
      // Deliberately not a multiple of the chunk size, so the last chunk is
      // short — the case an off-by-one in the loop would corrupt.
      final big = Uint8List.fromList(
          List.generate(kBlobChunkBytes * 3 + 1234, (i) => (i * 31) % 256));
      final serverStore = _MemoryStore(_doc()..parts.add(_part('p1', revision: 1)))
        ..takes['p1'] = big;
      final clientStore = _MemoryStore(_doc());

      final (_, client) = await _sync(serverStore, clientStore);

      expect(client.ok, isTrue, reason: client.error ?? '');
      expect(clientStore.takes['p1'], big);
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
        ..takes['p1'] = Uint8List.fromList([1, 2, 3]);
      final clientStore = _MemoryStore(_doc()..parts.add(_part('p1', revision: 2)))
        ..takes['p1'] = Uint8List.fromList([1, 2, 3]);

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
        ..takes['p1'] = Uint8List.fromList([1, 2, 3]);
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
      expect(clientStore.takes, isEmpty);
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
