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

  /// A peer not seen for this long is treated as gone.
  ///
  /// mDNS goodbyes are unreliable — a phone that goes into a pocket or leaves
  /// the room often just stops answering — so peers are also aged out.
  static const Duration peerTimeout = Duration(seconds: 45);

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
        // The visible name is the tune, because on the rare occasion a user
        // sees this list it should read as music rather than as networking.
        name: title.isEmpty ? 'GrooveForge' : title,
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
      _sweep = Timer.periodic(const Duration(seconds: 10), (_) => _sweepStale());
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
        _remember(event.service);
      case BonsoirDiscoveryServiceUpdatedEvent():
        _remember(event.service);
      case BonsoirDiscoveryServiceLostEvent():
        if (_peers.remove(_keyFor(event.service)) != null) notifyListeners();
      default:
        break;
    }
  }

  String _keyFor(BonsoirService service) =>
      '${service.name}|${service.attributes[_txtDevice] ?? ''}';

  void _remember(BonsoirService service) {
    final rehearsalId = service.attributes[_txtRehearsal];
    final deviceId = service.attributes[_txtDevice] ?? '';
    if (rehearsalId == null) return;

    // A resolved service can carry several addresses — link-local IPv6 among
    // them on some stacks. The IPv4 one is what the sync socket connects to.
    final address = service.hostAddresses
        .where((a) => a.contains('.') && !a.startsWith('169.254.'))
        .firstOrNull;
    if (address == null) return;

    _peers[_keyFor(service)] = DiscoveredPeer(
      rehearsalId: rehearsalId,
      host: address,
      port: service.port,
      deviceId: deviceId,
      seenAt: DateTime.now(),
    );
    notifyListeners();
  }

  void _sweepStale() {
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
