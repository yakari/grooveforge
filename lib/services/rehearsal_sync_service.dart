import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/rehearsal.dart';
import 'rehearsal_discovery.dart';
import 'rehearsal_library.dart';
import 'rehearsal_protocol.dart';
import 'rehearsal_sync.dart';

/// Bridges [SyncSession]'s storage needs onto the real library.
///
/// Kept apart from the session so the protocol can be tested over a socket
/// without a filesystem behind it — the session sees an interface, and this is
/// the one implementation that touches disk.
class LibrarySyncStore implements SyncStore {
  LibrarySyncStore(this.library);

  final RehearsalLibrary library;

  @override
  Future<Rehearsal?> load(String rehearsalId) async =>
      library.rehearsals.where((r) => r.id == rehearsalId).firstOrNull;

  @override
  Future<void> save(Rehearsal rehearsal) => library.save(rehearsal);

  @override
  Future<Uint8List?> readTake(String rehearsalId, String partId) async {
    final rehearsal = await load(rehearsalId);
    final part = rehearsal?.parts.where((p) => p.id == partId).firstOrNull;
    final take = part?.take;
    if (rehearsal == null || take == null) return null;
    final file = File(await library.takePath(rehearsalId, take));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeTake(
      String rehearsalId, String partId, Uint8List bytes) async {
    final rehearsal = await load(rehearsalId);
    final part = rehearsal?.parts.where((p) => p.id == partId).firstOrNull;
    final take = part?.take;
    if (rehearsal == null || take == null) return;
    // The manifest already carries the take that these bytes belong to — the
    // merge put it there — so the file name is known and this simply fills in
    // the audio the document is already pointing at.
    final file = File(await library.takePath(rehearsalId, take));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<Uint8List?> readMaster(String rehearsalId) async {
    final rehearsal = await load(rehearsalId);
    final master = rehearsal?.master;
    if (master == null) return null;
    final file = File(await library.masterPath(rehearsalId, master));
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeMaster(String rehearsalId, Uint8List bytes) async {
    final rehearsal = await load(rehearsalId);
    final master = rehearsal?.master;
    if (master == null) return;
    final file = File(await library.masterPath(rehearsalId, master));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }
}

/// A peer that has synced, or is syncing, with us.
class SyncPeer {
  SyncPeer({required this.deviceId, required this.address, this.status = ''});

  final String deviceId;
  final String address;
  String status;
}

/// Hosts and joins rehearsal sync sessions.
///
/// One rehearsal is "open for sharing" at a time. The host listens; joiners
/// connect with the ticket from the QR. Both then run the *same* exchange —
/// there is no authority, because the merge is symmetric.
class RehearsalSyncService extends ChangeNotifier {
  RehearsalSyncService(this._library, this.discovery);

  final RehearsalLibrary _library;

  /// Finds peers that this device has already been introduced to.
  final RehearsalDiscovery discovery;

  /// Called after a sync that brought in audio.
  ///
  /// The manifest and the engine are separate things: merging a take makes it
  /// appear in the list, but the engine only plays tracks it has been told to
  /// open. Without this a part arrives, shows up in the lane, and is silent.
  void Function()? onAudioReceived;

  ServerSocket? _server;
  StreamSubscription<Socket>? _connections;
  JoinTicket? _ticket;

  final List<SyncPeer> _peers = [];
  String? _lastError;
  bool _busy = false;

  /// What a live session is following. The rehearsal and its key are fixed;
  /// the address is resolved afresh each tick, with [_liveTicket] as the
  /// fallback for a network where discovery does not work.
  String? _liveRehearsalId;
  Uint8List? _liveKey;
  JoinTicket? _liveTicket;
  Timer? _liveTimer;
  int _liveFailures = 0;

  List<SyncPeer> get peers => List.unmodifiable(_peers);
  JoinTicket? get ticket => _ticket;
  bool get isHosting => _server != null;

  /// True while this device is re-syncing on its own with a peer.
  bool get isLive => _liveTimer != null;
  bool get isBusy => _busy;
  String? get lastError => _lastError;

  /// This device's identity, shared with the library so both stamp edits with
  /// the same id.
  Future<String> deviceId() => rehearsalDeviceId();

  // ── Hosting ───────────────────────────────────────────────────────────────

  /// Opens [rehearsal] for sharing and returns the ticket to put in a QR code.
  ///
  /// Binds to any free port and puts the address straight in the ticket, so a
  /// joiner standing next to the host needs no discovery at all — the QR *is*
  /// the discovery (REHEARSALS.md §4.2).
  Future<JoinTicket?> startHosting(Rehearsal rehearsal) async {
    await stopHosting();
    try {
      final address = await _localAddress();
      if (address == null) {
        _lastError = 'no-network';
        notifyListeners();
        return null;
      }
      // The rehearsal's own key, not a fresh one: a peer that rediscovers this
      // device tomorrow already holds it, and a per-session key would leave
      // them unable to say anything.
      final key = rehearsal.joinKey;
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      _server = server;
      _ticket = JoinTicket(
        rehearsalId: rehearsal.id,
        key: key != null
            ? Uint8List.fromList(base64.decode(key))
            : JoinTicket.newKey(),
        host: address,
        port: server.port,
        title: rehearsal.title,
      );
      _connections = server.listen(
        _onIncoming,
        onError: (Object e) => debugPrint('RehearsalSyncService: $e'),
      );

      // Announce it, so anyone already invited finds this device again without
      // a code. Failing is fine — a network without mDNS still has the QR.
      await discovery.advertise(
        rehearsalId: rehearsal.id,
        port: server.port,
        deviceId: await deviceId(),
        title: rehearsal.title,
      );

      _lastError = null;
      notifyListeners();
      return _ticket;
    } catch (e) {
      debugPrint('RehearsalSyncService: could not host — $e');
      _lastError = '$e';
      notifyListeners();
      return null;
    }
  }

  Future<void> stopHosting() async {
    await discovery.stopAdvertising();
    await _connections?.cancel();
    _connections = null;
    await _server?.close();
    _server = null;
    _ticket = null;
    _peers.clear();
    notifyListeners();
  }

  Future<void> _onIncoming(Socket socket) async {
    final ticket = _ticket;
    if (ticket == null) {
      socket.destroy();
      return;
    }
    final peer = SyncPeer(
      deviceId: '',
      address: socket.remoteAddress.address,
      status: 'connecting',
    );
    _peers.add(peer);
    _busy = true;
    notifyListeners();

    final session = SyncSession(
      socket: socket,
      store: LibrarySyncStore(_library),
      key: ticket.key,
      rehearsalId: ticket.rehearsalId,
      deviceId: await deviceId(),
      isClient: false,
      onProgress: (step) {
        peer.status = step;
        notifyListeners();
      },
    );
    final report = await session.run();
    peer.status = report.ok ? 'done' : (report.error ?? 'failed');
    _busy = false;
    if (report.takesReceived > 0 || report.masterReceived) {
      onAudioReceived?.call();
    }
    notifyListeners();
  }


  // ── Staying in step ───────────────────────────────────────────────────────

  /// How often a live session re-syncs.
  ///
  /// A sync where nothing has changed costs a TCP connect, a handshake and two
  /// manifests — a few kilobytes — and the tests assert it moves no audio. Six
  /// seconds is therefore cheap, and it is short enough that a part someone
  /// has just finished recording turns up while they are still putting their
  /// instrument down.
  static const Duration _livePeriod = Duration(seconds: 6);

  /// Give up after this many consecutive failures.
  ///
  /// Someone who has walked out of the room, or closed the app, would
  /// otherwise have every device in the band retrying them forever.
  static const int _maxLiveFailures = 5;

  /// Keeps this device in step with anyone sharing [rehearsalId].
  ///
  /// [key] is the rehearsal's own key, which every member holds; the address
  /// comes from discovery each time. That is what makes a second meeting work
  /// without a second introduction — the host's port changes on every restart,
  /// and only the key stays put.
  void startLiveSync({
    required String rehearsalId,
    required Uint8List key,
    JoinTicket? fallback,
  }) {
    stopLiveSync();
    _liveRehearsalId = rehearsalId;
    _liveKey = key;
    _liveTicket = fallback;
    _liveFailures = 0;
    _liveTimer = Timer.periodic(_livePeriod, (_) => _tick());
    notifyListeners();
  }

  void stopLiveSync() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _liveTicket = null;
    _liveRehearsalId = null;
    _liveKey = null;
    notifyListeners();
  }

  /// Where to sync next: a discovered peer if there is one, otherwise the
  /// address this device was last introduced at.
  ///
  /// Discovery is preferred because the remembered address goes stale the
  /// moment the host restarts sharing, while a discovered one is current by
  /// definition.
  JoinTicket? _nextTarget() {
    final id = _liveRehearsalId;
    final key = _liveKey;
    if (id == null || key == null) return _liveTicket;

    final found = discovery.peersFor(id);
    if (found.isNotEmpty) {
      final peer = found.first;
      return JoinTicket(
        rehearsalId: id,
        key: key,
        host: peer.host,
        port: peer.port,
        title: '',
      );
    }
    return _liveTicket;
  }

  Future<void> _tick() async {
    if (_busy) return; // never stack syncs on each other
    final target = _nextTarget();
    if (target == null) return;

    final report = await join(target, quiet: true);
    if (report.ok) {
      _liveFailures = 0;
      return;
    }
    _liveFailures++;
    // Only give up when there is nothing discoverable either. A peer that is
    // still advertising is worth retrying: they may simply be busy syncing
    // with someone else.
    if (_liveFailures >= _maxLiveFailures &&
        discovery.peersFor(_liveRehearsalId ?? '').isEmpty) {
      debugPrint('RehearsalSyncService: nobody reachable, stopping live sync');
      stopLiveSync();
    }
  }

  /// Pushes straight away rather than waiting for the next tick.
  ///
  /// Called the moment a take is committed: the player has just stopped
  /// recording and the others should hear it without a six-second pause.
  Future<void> syncNow() async {
    if (_busy) return;
    final target = _nextTarget();
    if (target == null) return;
    await join(target, quiet: true);
  }

  // ── Joining ───────────────────────────────────────────────────────────────

  /// Connects to the host named in [ticket] and syncs once.
  ///
  /// If this device does not know the rehearsal yet, an empty shell is created
  /// first so the merge has something to merge *into* — the peer's manifest
  /// then fills it in, and the audio follows.
  Future<SyncReport> join(JoinTicket ticket, {bool quiet = false}) async {
    _busy = true;
    if (!quiet) _lastError = null;
    if (!quiet) notifyListeners();
    try {
      await _ensureRehearsalExists(ticket);

      final socket = await Socket.connect(ticket.host, ticket.port,
          timeout: const Duration(seconds: 8));
      final session = SyncSession(
        socket: socket,
        store: LibrarySyncStore(_library),
        key: ticket.key,
        rehearsalId: ticket.rehearsalId,
        deviceId: await deviceId(),
        isClient: true,
        onProgress: (step) {
          if (_peers.isEmpty) {
            _peers.add(SyncPeer(deviceId: '', address: ticket.host));
          }
          _peers.first.status = step;
          notifyListeners();
        },
      );
      final report = await session.run();
      if (!report.ok && !quiet) _lastError = report.error;

      // Deliberately no reload here. The merge mutates the library's live
      // document in place and the session saves it, so memory and disk are
      // already correct — and reloading would swap in fresh objects underneath
      // whatever screen is open, leaving it holding a stale one.
      if (report.takesReceived > 0 || report.masterReceived) {
        onAudioReceived?.call();
      }
      return report;
    } catch (e) {
      if (!quiet) debugPrint('RehearsalSyncService: join failed — $e');
      if (!quiet) _lastError = '$e';
      return SyncReport(ok: false, error: '$e');
    } finally {
      _busy = false;
      if (!quiet) notifyListeners();
    }
  }

  /// Creates a placeholder for a rehearsal this device has never seen.
  ///
  /// Everything in it loses to the peer's copy: no field has been touched, so
  /// every clock is zero and the merge takes the peer's values wholesale.
  Future<void> _ensureRehearsalExists(JoinTicket ticket) async {
    if (!_library.isLoaded) await _library.load();
    final known =
        _library.rehearsals.where((r) => r.id == ticket.rehearsalId).isNotEmpty;
    if (known) return;

    final shell = Rehearsal(
      id: ticket.rehearsalId,
      title: ticket.title,
      bpm: 120,
      beatsPerBar: 4,
      beatUnit: 4,
      countInBars: 2,
      createdAt: DateTime.now(),
      members: [],
      parts: [],
    );
    await _library.save(shell);
    await _library.load();
  }

  /// This device's address on the LAN.
  ///
  /// Interfaces are *ranked*, not just filtered, because taking the first
  /// private-range address that turns up is wrong in a way that looks right:
  /// a phone with a VPN on offers a tunnel address like 10.5.0.2 ahead of its
  /// Wi-Fi one, and the QR then advertises an endpoint nobody in the room can
  /// reach. Real hardware found this — the test phone had a VPN running and
  /// happily published its tunnel address.
  Future<String?> _localAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      String? best;
      var bestScore = -1;
      for (final interface in interfaces) {
        final rank = _rankInterface(interface.name);
        if (rank < 0) continue; // a tunnel, or otherwise unreachable from here
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('169.254.')) continue; // link-local, unroutable
          // A private address on a real adapter beats anything else; among
          // those, the interface ranking decides.
          final score = rank + (_isPrivate(ip) ? 10 : 0);
          if (score > bestScore) {
            bestScore = score;
            best = ip;
          }
        }
      }
      return best;
    } catch (e) {
      debugPrint('RehearsalSyncService: no address — $e');
    }
    return null;
  }

  /// How much an interface is worth as a rehearsal-room endpoint.
  ///
  /// Negative means never: a VPN tunnel is reachable only by whatever sits at
  /// the far end of it, which is not the person standing next to you.
  int _rankInterface(String name) {
    final n = name.toLowerCase();
    for (final prefix in ['tun', 'tap', 'ppp', 'wg', 'ipsec', 'utun']) {
      if (n.startsWith(prefix)) return -1;
    }
    // Cellular: routable, but never to someone in the same room.
    if (n.startsWith('rmnet') || n.startsWith('ccmni')) return -1;
    // Wi-Fi first, then wired, then whatever is left.
    if (n.startsWith('wlan') || n.startsWith('wl') || n.startsWith('wifi')) {
      return 3;
    }
    if (n.startsWith('eth') || n.startsWith('en')) return 2;
    return 1;
  }

  bool _isPrivate(String ip) =>
      ip.startsWith('192.168.') || ip.startsWith('10.') || _isCarrierGrade(ip);

  /// 172.16.0.0 – 172.31.255.255, the third private range.
  bool _isCarrierGrade(String ip) {
    if (!ip.startsWith('172.')) return false;
    final second = int.tryParse(ip.split('.')[1]) ?? 0;
    return second >= 16 && second <= 31;
  }

  @override
  void dispose() {
    stopLiveSync();
    stopHosting();
    super.dispose();
  }
}
