import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

/// A device advertising a rehearsal on the local network.
class DiscoveredPeer {
  DiscoveredPeer({
    required this.rehearsalId,
    required this.host,
    required this.port,
    required this.deviceId,
    required this.seenAt,
  });

  final String rehearsalId;
  final String host;
  final int port;

  /// Which device is advertising, so a peer never tries to sync with itself.
  final String deviceId;

  final DateTime seenAt;

  /// Same peer, sighted at a different moment.
  DiscoveredPeer copyWith({DateTime? seenAt}) => DiscoveredPeer(
        rehearsalId: rehearsalId,
        host: host,
        port: port,
        deviceId: deviceId,
        seenAt: seenAt ?? this.seenAt,
      );

  @override
  String toString() => '$host:$port for $rehearsalId';
}

/// Finds and advertises rehearsals on the local network.
///
/// The QR is what introduces two devices; this is what lets them find each
/// other *again*. Without it, a band that met last week has to repeat the whole
/// introduction every time they sit down, because the host's port — and,
/// before the key moved into the document, its key — changed in between.
///
/// Only the address is discovered. The shared key never touches the network:
/// it lives in the rehearsal document, which a device only has because it was
/// invited once. Anyone can see that a GrooveForge rehearsal is being shared
/// and which id it has; nobody can join without having been introduced.
class RehearsalDiscovery extends ChangeNotifier {
  /// Service type, following the DNS-SD convention.
  static const String serviceType = '_gfrehearsal._tcp';

  /// TXT keys. Kept short: DNS-SD records are small, and some stacks truncate.
  static const String _txtRehearsal = 'r';
  static const String _txtDevice = 'd';

  /// A peer neither sighted nor talked to for this long is treated as gone.
  ///
  /// Comfortably longer than mDNS's own refresh cycle. Browsers re-query at
  /// around 80% of a two-minute record TTL, so an alive peer can easily go a
  /// minute and a half without producing a single event. The previous 45
  /// seconds was shorter than that, which meant every peer aged out while
  /// still sitting there advertising — the room went quiet on a timer.
  static const Duration peerTimeout = Duration(minutes: 3);

  /// How long a peer survives a goodbye before the sweep takes it.
  ///
  /// Long enough for a sync tick or two to confirm the peer is still there,
  /// short enough that someone who really left stops being a sync target
  /// quickly. See [_onLost] for why a goodbye is not taken at face value.
  static const Duration lostGrace = Duration(seconds: 20);

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _events;
  Timer? _sweep;

  final Map<String, DiscoveredPeer> _peers = {};
  String? _selfDeviceId;

  /// Everything currently visible, newest sighting first.
  List<DiscoveredPeer> get peers => _peers.values.toList()
    ..sort((a, b) => b.seenAt.compareTo(a.seenAt));

  /// Peers advertising [rehearsalId], excluding this device.
  List<DiscoveredPeer> peersFor(String rehearsalId) => peers
      .where((p) => p.rehearsalId == rehearsalId && p.deviceId != _selfDeviceId)
      .toList();

  bool get isAdvertising => _broadcast != null;
  bool get isBrowsing => _discovery != null;

  // ── Advertising ───────────────────────────────────────────────────────────

  /// Announces that this device is sharing [rehearsalId] on [port].
  Future<void> advertise({
    required String rehearsalId,
    required int port,
    required String deviceId,
    required String title,
  }) async {
    await stopAdvertising();
    _selfDeviceId = deviceId;
    try {
      final service = BonsoirService(
        name: instanceName(title, deviceId),
        type: serviceType,
        port: port,
        attributes: {
          _txtRehearsal: rehearsalId,
          _txtDevice: deviceId,
        },
      );
      final broadcast = BonsoirBroadcast(service: service);
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
      notifyListeners();
    } catch (e) {
      // A network without mDNS — a locked-down guest Wi-Fi, or a desktop with
      // no Avahi — is a normal condition, not a failure worth surfacing. The
      // QR still works, which is the whole reason it carries the endpoint.
      debugPrint('RehearsalDiscovery: cannot advertise — $e');
    }
  }

  /// The name this device advertises under.
  ///
  /// The tune, so that on the rare occasion a user sees this list it reads as
  /// music rather than as networking — but with a slice of the device id
  /// appended, because DNS-SD instance names have to be unique on the link and
  /// everyone in a rehearsal is sharing the *same tune*. Without the suffix
  /// every device after the first collided, and the daemon resolved it by
  /// renaming them: "test2", "test2 (2)", "test2 (3)". Each rename withdrew a
  /// name, and every withdrawal read as a peer leaving the room.
  ///
  /// The title is truncated because the whole name has to fit in a 63-byte
  /// DNS label.
  @visibleForTesting
  static String instanceName(String title, String deviceId) {
    final tune = title.isEmpty ? 'GrooveForge' : title;
    final short = tune.length > 40 ? tune.substring(0, 40) : tune;
    final suffix =
        deviceId.length > 6 ? deviceId.substring(0, 6) : deviceId;
    return '$short · $suffix';
  }

  Future<void> stopAdvertising() async {
    try {
      await _broadcast?.stop();
    } catch (e) {
      debugPrint('RehearsalDiscovery: stop advertise — $e');
    }
    _broadcast = null;
    notifyListeners();
  }

  // ── Browsing ──────────────────────────────────────────────────────────────

  /// Starts watching for rehearsals on the network.
  Future<void> startBrowsing(String deviceId) async {
    if (_discovery != null) return;
    _selfDeviceId = deviceId;
    try {
      final discovery = BonsoirDiscovery(type: serviceType);
      await discovery.initialize();
      _events = discovery.eventStream?.listen(_onEvent);
      await discovery.start();
      _discovery = discovery;
      // Peers are aged out as well as removed on goodbye, because a phone that
      // goes into a pocket usually just stops answering.
      _sweep = Timer.periodic(const Duration(seconds: 10), (_) => sweepStale());
      notifyListeners();
    } catch (e) {
      debugPrint('RehearsalDiscovery: cannot browse — $e');
    }
  }

  Future<void> stopBrowsing() async {
    await _events?.cancel();
    _events = null;
    _sweep?.cancel();
    _sweep = null;
    try {
      await _discovery?.stop();
    } catch (e) {
      debugPrint('RehearsalDiscovery: stop browse — $e');
    }
    _discovery = null;
    _peers.clear();
    notifyListeners();
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    switch (event) {
      // "Found" only says a service exists; its address arrives on resolution,
      // which has to be asked for.
      case BonsoirDiscoveryServiceFoundEvent():
        event.service.resolve(_discovery!.serviceResolver);
      case BonsoirDiscoveryServiceResolvedEvent():
        remember(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        remember(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        unawaited(onLost(event.service));
      default:
        break;
    }
  }

  /// Identifies a peer by *what it is*, not by what it is currently called.
  ///
  /// Deliberately not the service name: mDNS renames a service when its name
  /// collides on the link, so the same device can appear as "test2", then
  /// "test2 (2)", then "test2 (3)". Keying by name filed each rename as a new
  /// peer and left the old ones behind.
  String? _keyFor(BonsoirService service) {
    final device = service.attributes[_txtDevice];
    final rehearsal = service.attributes[_txtRehearsal];
    if (device == null || rehearsal == null) return null;
    return '$device|$rehearsal';
  }

  /// Checks a goodbye rather than believing it or ignoring it.
  ///
  /// A goodbye does not reliably mean the device left: renaming a service on a
  /// name collision withdraws the old name, and stacks emit a goodbye for it
  /// while the device is still very much in the room. Removing on the spot
  /// made that peer invisible for good, because mDNS has no reason to announce
  /// a registration it already considers live.
  ///
  /// So the peer is asked directly — [reachabilityProbe] knocks on the sync
  /// port. Nobody listening means they really left, and they go immediately;
  /// an answer means the goodbye was noise, and they stay. That is the whole
  /// question settled in about a second, rather than waiting out a timeout
  /// with the room showing a device that has already packed up.
  ///
  /// Without a probe the sighting is merely backdated, so the sweep takes the
  /// peer after [lostGrace] unless something confirms them first.
  @visibleForTesting
  Future<void> onLost(BonsoirService service) async {
    final key = _keyFor(service);
    final peer = key == null ? null : _peers[key];
    if (key == null || peer == null) return;

    final expiry = DateTime.now().subtract(peerTimeout).add(lostGrace);
    if (peer.seenAt.isAfter(expiry)) {
      _peers[key] = peer.copyWith(seenAt: expiry);
    }

    final probe = reachabilityProbe;
    if (probe == null) return;
    if (await probe(peer)) return; // still listening — a rename, not an exit

    // Re-read: the probe took a moment, and a sighting may have arrived in
    // the meantime that supersedes what we are acting on.
    if (_peers[key] != null && !_peers[key]!.seenAt.isAfter(expiry)) {
      _peers.remove(key);
      notifyListeners();
    }
  }

  /// Asks whether a peer is still answering on its sync port.
  ///
  /// Injected by the sync service, which owns the socket layer. Left null in
  /// tests that only care about the peer table, and on any platform where
  /// connecting is not the right question to ask.
  Future<bool> Function(DiscoveredPeer peer)? reachabilityProbe;

  /// Records that this device actually exchanged data with [host].
  ///
  /// The authoritative liveness signal, and much better than the one mDNS
  /// offers: a peer that just answered a sync is in the room by definition,
  /// whatever the daemon last said about it.
  void confirmReachable(String host) {
    var touched = false;
    for (final entry in _peers.entries.toList()) {
      if (entry.value.host != host) continue;
      _peers[entry.key] = entry.value.copyWith(seenAt: DateTime.now());
      touched = true;
    }
    if (touched) notifyListeners();
  }

  @visibleForTesting
  void remember(BonsoirService service) {
    final rehearsalId = service.attributes[_txtRehearsal];
    final deviceId = service.attributes[_txtDevice] ?? '';
    if (rehearsalId == null) return;

    // A resolved service can carry several addresses — link-local IPv6 among
    // them on some stacks. The IPv4 one is what the sync socket connects to.
    final address = service.hostAddresses
        .where((a) => a.contains('.') && !a.startsWith('169.254.'))
        .firstOrNull;
    if (address == null) return;

    final key = _keyFor(service);
    if (key == null) return;

    _peers[key] = DiscoveredPeer(
      rehearsalId: rehearsalId,
      host: address,
      port: service.port,
      deviceId: deviceId,
      seenAt: DateTime.now(),
    );
    notifyListeners();
  }

  @visibleForTesting
  void sweepStale() {
    final cutoff = DateTime.now().subtract(peerTimeout);
    final before = _peers.length;
    _peers.removeWhere((_, p) => p.seenAt.isBefore(cutoff));
    if (_peers.length != before) notifyListeners();
  }

  @override
  void dispose() {
    stopAdvertising();
    stopBrowsing();
    super.dispose();
  }
}
