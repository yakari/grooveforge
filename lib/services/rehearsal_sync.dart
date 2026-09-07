import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/rehearsal.dart';
import 'rehearsal_merge.dart';
import 'rehearsal_protocol.dart';

/// Everything a sync session needs from the outside world.
///
/// An interface rather than a direct dependency on [RehearsalLibrary] so the
/// session can be driven over a real socket in a test without a filesystem, a
/// documents directory or a plugin behind it. The protocol is the part most
/// likely to be subtly wrong, and it should be testable on its own.
abstract class SyncStore {
  /// The local document, or null if this device does not know the rehearsal.
  Future<Rehearsal?> load(String rehearsalId);

  /// Persists a merged document.
  Future<void> save(Rehearsal rehearsal);

  /// Bytes of a part's current take, or null if it is not here.
  Future<Uint8List?> readTake(String rehearsalId, String partId);

  /// Stores audio received for a part.
  Future<void> writeTake(String rehearsalId, String partId, Uint8List bytes);

  /// Bytes of the master, or null.
  Future<Uint8List?> readMaster(String rehearsalId);

  Future<void> writeMaster(String rehearsalId, Uint8List bytes);
}

/// How a sync ended, for the UI to report.
class SyncReport {
  SyncReport({
    required this.ok,
    this.error,
    this.takesReceived = 0,
    this.takesSent = 0,
    this.masterReceived = false,
    this.changed = false,
  });

  final bool ok;
  final String? error;
  final int takesReceived;
  final int takesSent;
  final bool masterReceived;
  final bool changed;
}

/// Runs one sync over an already-connected socket.
///
/// Both sides run the *same* exchange, differing only in who speaks first.
/// That is deliberate: the merge is symmetric (see [mergeRehearsal]), so there
/// is no reason for one device to be the authority, and making them the same
/// removes a whole category of "works when A hosts, fails when B does" bugs.
///
/// The shape of a session:
///
/// 1. handshake — nonces both ways, an HMAC proof from each side
/// 2. manifests — each sends its whole document, both merge
/// 3. wants — each asks for the audio the merge told it is missing
/// 4. blobs — each sends what the other asked for
/// 5. done
class SyncSession {
  SyncSession({
    required this.socket,
    required this.store,
    required this.key,
    required this.rehearsalId,
    required this.deviceId,
    required this.isClient,
    this.onProgress,
  }) : _crypto = SyncCrypto(key);

  final Socket socket;
  final SyncStore store;
  final Uint8List key;
  final String rehearsalId;
  final String deviceId;

  /// The client speaks first. Nothing else differs.
  final bool isClient;

  /// Reports a human-readable step, for the Nearby screen.
  final void Function(String step)? onProgress;

  final SyncCrypto _crypto;
  final FrameReader _reader = FrameReader();
  late final StreamQueue<Frame> _incoming;

  /// How long to wait for any single expected frame.
  ///
  /// A peer that stops responding mid-transfer must not leave the UI spinning
  /// forever; ten seconds is far longer than a LAN needs and short enough that
  /// a user notices something is wrong rather than waiting.
  static const Duration _timeout = Duration(seconds: 10);

  Future<SyncReport> run() async {
    _incoming = StreamQueue<Frame>(_reader.frames);
    final sub = socket.listen(
      _reader.add,
      onError: (Object e) => debugPrint('SyncSession: socket error $e'),
      onDone: () => _reader.close(),
    );

    try {
      await _handshake();
      final report = await _exchange();
      return report;
    } on TimeoutException {
      return SyncReport(ok: false, error: 'timeout');
    } catch (e) {
      debugPrint('SyncSession: $e');
      return SyncReport(ok: false, error: '$e');
    } finally {
      await sub.cancel();
      await _incoming.cancel(immediate: true);
      socket.destroy();
    }
  }

  // ── Framing helpers ───────────────────────────────────────────────────────

  void _sendPlain(Map<String, dynamic> message) {
    socket.add(encodeControl(message));
  }

  /// Sends a control message through the encrypted channel.
  Future<void> _send(Map<String, dynamic> message) async {
    final sealed = await _crypto.seal(utf8.encode(jsonEncode(message)));
    socket.add(encodeFrame(FrameKind.control, sealed));
  }

  Future<void> _sendBlob(List<int> bytes) async {
    // Chunked so a large take does not have to be sealed as one buffer, and so
    // progress can move while it transfers.
    for (var offset = 0; offset < bytes.length; offset += kBlobChunkBytes) {
      final end = (offset + kBlobChunkBytes).clamp(0, bytes.length);
      final sealed = await _crypto.seal(bytes.sublist(offset, end));
      socket.add(encodeFrame(FrameKind.blob, sealed));
    }
  }

  Future<Frame> _nextFrame() async {
    if (!await _incoming.hasNext.timeout(_timeout)) {
      throw StateError('peer closed the connection');
    }
    return _incoming.next().timeout(_timeout);
  }

  Future<Map<String, dynamic>> _nextPlain() async {
    final frame = await _nextFrame();
    return frame.json;
  }

  Future<Map<String, dynamic>> _nextMessage() async {
    final frame = await _nextFrame();
    final plain = await _crypto.open(frame.bytes);
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  // ── 1. Handshake ──────────────────────────────────────────────────────────

  Future<void> _handshake() async {
    onProgress?.call('handshake');
    final myNonce = SyncCrypto.newNonce();

    if (isClient) {
      _sendPlain({
        'type': Msg.hello,
        'v': kProtocolVersion,
        'id': rehearsalId,
        'nonce': base64.encode(myNonce),
        'device': deviceId,
      });
      final challenge = await _nextPlain();
      if (challenge['type'] != Msg.challenge) {
        throw StateError('expected a challenge, got ${challenge['type']}');
      }
      final theirNonce = base64.decode(challenge['nonce'] as String);
      final expected = _crypto.proof(myNonce, Uint8List.fromList(theirNonce));
      if (!SyncCrypto.constantTimeEquals(
          expected, base64.decode(challenge['proof'] as String))) {
        // The other side does not hold the same key: a different rehearsal, a
        // stale QR, or someone who should not be here.
        throw StateError('the other device has a different join code');
      }
      _sendPlain({
        'type': Msg.auth,
        'proof': base64.encode(expected),
        'device': deviceId,
      });
    } else {
      final hello = await _nextPlain();
      if (hello['type'] != Msg.hello) {
        throw StateError('expected hello, got ${hello['type']}');
      }
      if (hello['v'] != kProtocolVersion) {
        _sendPlain({'type': Msg.error, 'reason': 'version'});
        throw StateError('protocol version ${hello['v']} is not supported');
      }
      if (hello['id'] != rehearsalId) {
        _sendPlain({'type': Msg.error, 'reason': 'rehearsal'});
        throw StateError('that device is syncing a different rehearsal');
      }
      final theirNonce =
          Uint8List.fromList(base64.decode(hello['nonce'] as String));
      final proof = _crypto.proof(theirNonce, myNonce);
      _sendPlain({
        'type': Msg.challenge,
        'nonce': base64.encode(myNonce),
        'proof': base64.encode(proof),
        'device': deviceId,
      });
      final auth = await _nextPlain();
      if (auth['type'] != Msg.auth ||
          !SyncCrypto.constantTimeEquals(
              proof, base64.decode(auth['proof'] as String))) {
        throw StateError('the other device has a different join code');
      }
    }
  }

  // ── 2-5. Manifests, wants, blobs ──────────────────────────────────────────

  Future<SyncReport> _exchange() async {
    onProgress?.call('manifest');

    final local = await store.load(rehearsalId);
    if (local == null) throw StateError('rehearsal $rehearsalId is not here');

    // Both sides send before either reads, so neither waits for the other to
    // go first — the exchange is symmetric and cannot deadlock on politeness.
    await _send({'type': Msg.manifest, 'doc': local.toJson()});
    final theirManifest = await _nextMessage();
    if (theirManifest['type'] != Msg.manifest) {
      throw StateError('expected a manifest, got ${theirManifest['type']}');
    }

    final remote =
        Rehearsal.fromJson(theirManifest['doc'] as Map<String, dynamic>);
    final outcome = mergeRehearsal(local, remote);
    if (outcome.changed) await store.save(local);

    // Ask for what the merge says is missing, and hear what they want.
    await _send({
      'type': Msg.want,
      'parts': outcome.partsToFetch,
      'master': outcome.masterToFetch,
    });
    final theirWant = await _nextMessage();
    if (theirWant['type'] != Msg.want) {
      throw StateError('expected a want list, got ${theirWant['type']}');
    }

    final wantedParts =
        (theirWant['parts'] as List<dynamic>).map((e) => e as String).toList();
    final wantsMaster = theirWant['master'] as bool? ?? false;

    // Send first: a peer that has nothing to send still has to drain what is
    // coming, and both sides doing the same thing in the same order keeps that
    // simple.
    final sent = await _sendWanted(wantedParts, wantsMaster);
    final received = await _receiveWanted(
        outcome.partsToFetch.length, outcome.masterToFetch);

    return SyncReport(
      ok: true,
      takesSent: sent,
      takesReceived: received.$1,
      masterReceived: received.$2,
      changed: outcome.changed,
    );
  }

  Future<int> _sendWanted(List<String> parts, bool master) async {
    var sent = 0;
    for (final partId in parts) {
      final bytes = await store.readTake(rehearsalId, partId);
      if (bytes == null) continue;
      onProgress?.call('sending');
      await _send({
        'type': Msg.blob,
        'kind': 'take',
        'partId': partId,
        'length': bytes.length,
      });
      await _sendBlob(bytes);
      sent++;
    }
    if (master) {
      final bytes = await store.readMaster(rehearsalId);
      if (bytes != null) {
        onProgress?.call('sending');
        await _send({
          'type': Msg.blob,
          'kind': 'master',
          'length': bytes.length,
        });
        await _sendBlob(bytes);
      }
    }
    await _send({'type': Msg.done});
    return sent;
  }

  /// Reads blobs until the peer says it is done.
  ///
  /// The counts we asked for are not trusted as a stopping condition: a peer
  /// may not have a take it advertised, and waiting for a file that will never
  /// arrive would hang the session until the timeout.
  Future<(int, bool)> _receiveWanted(int expectedParts, bool expectMaster) async {
    var takes = 0;
    var master = false;

    while (true) {
      final message = await _nextMessage();
      if (message['type'] == Msg.done) break;
      if (message['type'] != Msg.blob) {
        throw StateError('expected a blob, got ${message['type']}');
      }

      final length = message['length'] as int;
      onProgress?.call('receiving');
      final builder = BytesBuilder(copy: false);
      while (builder.length < length) {
        final frame = await _nextFrame();
        if (frame.kind != FrameKind.blob) {
          throw StateError('expected blob bytes, got a control frame');
        }
        builder.add(await _crypto.open(frame.bytes));
      }
      final bytes = builder.takeBytes();

      if (message['kind'] == 'master') {
        await store.writeMaster(rehearsalId, bytes);
        master = true;
      } else {
        await store.writeTake(
            rehearsalId, message['partId'] as String, bytes);
        takes++;
      }
    }
    return (takes, master);
  }
}

/// A tiny pull-based queue over a stream.
///
/// `package:async` has `StreamQueue`, but pulling in a package for forty lines
/// of queue in the one place the app needs it is not a good trade.
class StreamQueue<T> {
  StreamQueue(Stream<T> stream) {
    _sub = stream.listen(
      (event) {
        if (_waiting.isNotEmpty) {
          _waiting.removeAt(0).complete(event);
        } else {
          _buffered.add(event);
        }
      },
      onError: (Object e) {
        if (_waiting.isNotEmpty) _waiting.removeAt(0).completeError(e);
      },
      onDone: () {
        _closed = true;
        for (final c in _waiting) {
          c.completeError(StateError('stream closed'));
        }
        _waiting.clear();
      },
    );
  }

  late final StreamSubscription<T> _sub;
  final List<T> _buffered = [];
  final List<Completer<T>> _waiting = [];
  bool _closed = false;

  Future<bool> get hasNext async {
    if (_buffered.isNotEmpty) return true;
    if (_closed) return false;
    // Wait for either an event or the close, without consuming the event.
    final completer = Completer<T>();
    _waiting.add(completer);
    try {
      final event = await completer.future;
      _buffered.insert(0, event);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<T> next() async {
    if (_buffered.isNotEmpty) return _buffered.removeAt(0);
    if (_closed) throw StateError('stream closed');
    final completer = Completer<T>();
    _waiting.add(completer);
    return completer.future;
  }

  Future<void> cancel({bool immediate = false}) => _sub.cancel();
}
