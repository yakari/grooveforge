import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the sound is currently coming out.
class AudioRoute {
  const AudioRoute({
    required this.key,
    required this.label,
    required this.kind,
  });

  /// Stable identifier a measurement is filed under.
  ///
  /// Named for Bluetooth (`bt:WH-1000XM4`) because someone may own several
  /// headsets and each has its own delay; plain for the rest, since wired
  /// headphones differ from one another by less than any of this can measure.
  final String key;

  /// What to call it on screen.
  final String label;

  /// `speaker`, `wired` or `bluetooth`.
  final String kind;

  bool get isBluetooth => kind == 'bluetooth';

  /// The route assumed where the platform cannot say.
  static const AudioRoute unknown =
      AudioRoute(key: 'speaker', label: 'Speaker', kind: 'speaker');

  @override
  bool operator ==(Object other) => other is AudioRoute && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Watches which output the device is playing through.
///
/// Overdub compensation belongs to the gear, not to the tune: a phone's own
/// speaker is a few milliseconds away, a wired headset a few more, a Bluetooth
/// headset can be two hundred. Knowing which one is connected is what lets a
/// measurement be looked up rather than guessed — and what lets the app notice
/// that this headset has never been measured at all.
///
/// Deliberately reports identity, not latency. Android has no API that gives
/// the latency of a path at runtime, which is exactly why the app measures it
/// acoustically instead.
class AudioRouteService extends ChangeNotifier {
  static const MethodChannel _methods =
      MethodChannel('com.grooveforge/audio_route');
  static const EventChannel _events =
      EventChannel('com.grooveforge/audio_route_events');

  AudioRoute _route = AudioRoute.unknown;
  AudioRoute get route => _route;

  StreamSubscription<dynamic>? _subscription;

  /// Only Android reports this today. Elsewhere the speaker is assumed, which
  /// is right for a laptop and harmless for a desktop.
  bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Starts following the output route.
  Future<void> start() async {
    if (!_supported || _subscription != null) return;
    try {
      await refresh();
      _subscription = _events.receiveBroadcastStream().listen(
        (event) => _apply(event),
        onError: (Object e) =>
            debugPrint('AudioRouteService: route stream — $e'),
      );
    } catch (e) {
      debugPrint('AudioRouteService: cannot follow the route — $e');
    }
  }

  Future<void> refresh() async {
    if (!_supported) return;
    try {
      _apply(await _methods.invokeMethod<dynamic>('current'));
    } catch (e) {
      debugPrint('AudioRouteService: cannot read the route — $e');
    }
  }

  /// Sets the route directly, for tests. There is no platform here to ask.
  @visibleForTesting
  void debugSetRoute(AudioRoute route) {
    if (route == _route && route.label == _route.label) return;
    _route = route;
    notifyListeners();
  }

  void _apply(dynamic event) {
    if (event is! Map) return;
    final next = AudioRoute(
      key: event['key'] as String? ?? 'speaker',
      label: event['label'] as String? ?? 'Speaker',
      kind: event['kind'] as String? ?? 'speaker',
    );
    if (next == _route && next.label == _route.label) return;
    _route = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
