/// The wire format two devices use to sync a rehearsal.
///
/// Deliberately small. Everything is a length-prefixed frame; control frames
/// carry JSON, blob frames carry raw audio. The previous prototype sent
/// base64-encoded PCM inside JSON and polled every two seconds, which cost
/// about five times the bytes it needed and still felt slow.
///
/// ```
///   [4 bytes big-endian length][1 byte kind][payload …]
/// ```
///
/// Big-endian because that is what every "network order" reader expects, and
/// this is the one place in the app where the bytes leave the machine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// Both packages export a `Hmac`, and only one of them is a function. `crypto`
// supplies the HMAC and SHA-256 used in the handshake; `cryptography` supplies
// AES-GCM, behind a prefix so the collision cannot come back.
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as aead;

/// Frame kinds.
class FrameKind {
  /// JSON control message.
  static const control = 0;

  /// Raw audio bytes, following the `blob` control frame that describes them.
  static const blob = 1;
}

/// Largest frame we will accept, as a guard against a peer (or a stray
/// connection) claiming a gigabyte and making us allocate it. Audio arrives in
/// chunks well under this.
const int kMaxFrameBytes = 8 * 1024 * 1024;

/// Bytes of audio per blob frame. Big enough that the framing overhead is
/// irrelevant, small enough that progress moves visibly and a cancel is felt.
const int kBlobChunkBytes = 64 * 1024;

/// Protocol version, so a future change can be refused politely rather than
/// misparsed.
const int kProtocolVersion = 1;

/// One decoded frame.
class Frame {
  Frame(this.kind, this.bytes);

  final int kind;
  final Uint8List bytes;

  /// The payload decoded as JSON. Only valid for [FrameKind.control].
  Map<String, dynamic> get json =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
}

/// Encodes one frame.
Uint8List encodeFrame(int kind, List<int> payload) {
  final out = Uint8List(5 + payload.length);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, payload.length + 1, Endian.big);
  out[4] = kind;
  out.setRange(5, out.length, payload);
  return out;
}

/// Encodes a JSON control frame.
Uint8List encodeControl(Map<String, dynamic> message) =>
    encodeFrame(FrameKind.control, utf8.encode(jsonEncode(message)));

/// Reassembles frames from a byte stream.
///
/// TCP gives no message boundaries: a frame can arrive split across five reads
/// or four frames can arrive in one. This buffers until a whole frame is
/// present, which is the bug every hand-rolled socket protocol has at least
/// once.
class FrameReader {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final StreamController<Frame> _out = StreamController<Frame>();

  Stream<Frame> get frames => _out.stream;

  /// Feeds bytes from the socket. Throws [FormatException] if a peer announces
  /// an implausible frame, which is the point at which to hang up.
  void add(List<int> data) {
    _buffer.add(data);
    var bytes = _buffer.toBytes();
    var offset = 0;

    while (bytes.length - offset >= 4) {
      final view = ByteData.view(bytes.buffer, bytes.offsetInBytes + offset);
      final length = view.getUint32(0, Endian.big);
      if (length < 1 || length > kMaxFrameBytes) {
        _out.addError(FormatException('frame length $length out of range'));
        return;
      }
      if (bytes.length - offset - 4 < length) break; // wait for the rest

      final kind = bytes[offset + 4];
      final payload = Uint8List.sublistView(
          bytes, offset + 5, offset + 4 + length);
      _out.add(Frame(kind, Uint8List.fromList(payload)));
      offset += 4 + length;
    }

    _buffer.clear();
    if (offset < bytes.length) {
      _buffer.add(Uint8List.sublistView(bytes, offset));
    }
  }

  Future<void> close() => _out.close();
}

// ─── Join code and key ───────────────────────────────────────────────────────

/// Everything a device needs to join a rehearsal, as carried by the QR code.
///
/// The joiner is standing next to the host when they scan, so the QR carries
/// the endpoint itself and first contact needs no discovery protocol at all —
/// no mDNS, no timeouts, no "searching…" spinner (REHEARSALS.md §4.2).
class JoinTicket {
  JoinTicket({
    required this.rehearsalId,
    required this.key,
    required this.host,
    required this.port,
    required this.title,
  });

  final String rehearsalId;

  /// The shared secret. Authenticates the handshake and keys the channel.
  final Uint8List key;

  final String host;
  final int port;
  final String title;

  String toUri() {
    final k = base64Url.encode(key).replaceAll('=', '');
    return 'gf-rehearsal:v$kProtocolVersion'
        '?id=$rehearsalId'
        '&k=$k'
        '&h=$host:$port'
        '&n=${Uri.encodeComponent(title)}';
  }

  /// Parses a scanned or typed ticket. Returns null if it is not one of ours,
  /// which is the common case when a camera picks up some other QR code.
  static JoinTicket? parse(String text) {
    if (!text.startsWith('gf-rehearsal:')) return null;
    try {
      final q = text.substring(text.indexOf('?') + 1);
      final params = Uri.splitQueryString(q);
      final hostPort = (params['h'] ?? '').split(':');
      if (hostPort.length != 2) return null;
      var k = params['k'] ?? '';
      // base64Url without padding is what toUri emits; restore it to decode.
      k = k.padRight((k.length + 3) ~/ 4 * 4, '=');
      return JoinTicket(
        rehearsalId: params['id'] ?? '',
        key: Uint8List.fromList(base64Url.decode(k)),
        host: hostPort[0],
        port: int.parse(hostPort[1]),
        title: params['n'] ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// A fresh 32-byte key.
  static Uint8List newKey() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }
}

// ─── Handshake and channel ───────────────────────────────────────────────────

/// Authenticates both ends and encrypts what follows.
///
/// The join key never crosses the wire. Each side sends a random nonce and
/// proves it holds the key by returning an HMAC over both nonces — so an
/// eavesdropper who records a whole session learns nothing that lets them
/// impersonate either side later.
///
/// This is a LAN protocol between people standing in the same room, not a
/// public-internet one. It is not a replacement for TLS and does not try to
/// be: there is no forward secrecy and no certificate. What it does give is
/// that only someone who scanned the QR can join, and that the room's Wi-Fi
/// cannot read the band's recordings.
class SyncCrypto {
  SyncCrypto(this._key);

  final Uint8List _key;
  static final _aes = aead.AesGcm.with256bits();

  /// Proof that this side holds the key, over both nonces.
  ///
  /// Both nonces are included and always in the same order — client first —
  /// so the two sides compute the same value, and so a proof recorded from one
  /// session cannot be replayed into another.
  Uint8List proof(Uint8List clientNonce, Uint8List serverNonce) {
    final mac = Hmac(sha256, _key);
    return Uint8List.fromList(
        mac.convert([...clientNonce, ...serverNonce]).bytes);
  }

  /// Constant-time comparison.
  ///
  /// A `==` here leaks how many leading bytes matched through how long it took
  /// to fail, which is enough to forge a proof one byte at a time.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// Encrypts [plain]; the nonce and MAC travel with the ciphertext.
  Future<Uint8List> seal(List<int> plain) async {
    final secretKey = aead.SecretKey(_key);
    final box = await _aes.encrypt(plain, secretKey: secretKey);
    return Uint8List.fromList(
        [...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  /// Decrypts what [seal] produced. Throws if the MAC does not check out,
  /// which means the frame was tampered with or the keys differ.
  Future<Uint8List> open(Uint8List sealed) async {
    const nonceLength = 12;
    const macLength = 16;
    if (sealed.length < nonceLength + macLength) {
      throw const FormatException('sealed frame too short');
    }
    final box = aead.SecretBox(
      sealed.sublist(nonceLength, sealed.length - macLength),
      nonce: sealed.sublist(0, nonceLength),
      mac: aead.Mac(sealed.sublist(sealed.length - macLength)),
    );
    final plain = await _aes.decrypt(box, secretKey: aead.SecretKey(_key));
    return Uint8List.fromList(plain);
  }

  static Uint8List newNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  }
}

// ─── Message names ───────────────────────────────────────────────────────────

/// The control messages, named in one place so a typo cannot invent a message
/// the other side will simply ignore.
class Msg {
  /// Client → server: version, rehearsal id, client nonce.
  static const hello = 'hello';

  /// Server → client: server nonce, and its proof.
  static const challenge = 'challenge';

  /// Client → server: its proof. The channel is encrypted from here.
  static const auth = 'auth';

  /// Either way: the whole rehearsal document.
  static const manifest = 'manifest';

  /// Either way: "send me the audio for these".
  static const want = 'want';

  /// Precedes the raw bytes of one file.
  static const blob = 'blob';

  /// Nothing further to send.
  static const done = 'done';

  /// Something went wrong; carries a `reason` for the log.
  static const error = 'error';
}
