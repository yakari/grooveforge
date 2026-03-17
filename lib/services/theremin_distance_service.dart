import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Streams normalized camera focal distance for the Theremin camera mode.
///
/// Communicates with the native camera plugins via three platform channels:
///
///   Method channel  — [_kMethodChannel]:  start / stop / isSupported calls.
///   Event channel   — [_kEventChannel]:   per-frame [Double] stream, [0.0, 1.0].
///   Preview channel — [_kPreviewChannel]: 5 fps JPEG thumbnails as [Uint8List].
///
/// The raw per-frame values are smoothed with an exponential moving average
/// (EMA) before being written to [distance]. This removes high-frequency AF
/// jitter while keeping the response time short enough for musical use.
///
/// ### Platform mapping
///
/// | Platform | Source                                       | Range       |
/// |----------|----------------------------------------------|-------------|
/// | Android  | Camera2 `LENS_FOCUS_DISTANCE` (diopters),    | [0.0, 1.0]  |
/// |          | normalized by `LENS_INFO_MINIMUM_FOCUS_DIST` |             |
/// | iOS      | `AVCaptureDevice.lensPosition`               | [0.0, 1.0]  |
/// | macOS    | `AVCaptureDevice.lensPosition`               | [0.0, 1.0]  |
///
/// In all cases: 0.0 = hand far (or no hand), 1.0 = hand at minimum focus.
///
/// ### Usage
///
/// ```dart
/// final svc = ThereminDistanceService();
/// final error = await svc.start();
/// if (error == null) {
///   svc.distance.addListener(() => print(svc.distance.value));
/// }
/// // later:
/// await svc.stop();
/// svc.dispose();
/// ```
class ThereminDistanceService {
  // ─── Platform channel names ───────────────────────────────────────────────

  static const _kMethodChannel =
      MethodChannel('com.grooveforge/theremin_camera');
  static const _kEventChannel =
      EventChannel('com.grooveforge/theremin_camera_events');
  static const _kPreviewChannel =
      EventChannel('com.grooveforge/theremin_camera_preview');

  // ─── Public state ─────────────────────────────────────────────────────────

  /// EMA-smoothed focal distance, normalized to [0.0, 1.0].
  ///
  /// 0.0 = hand far from camera (plays lowest note / silence).
  /// 1.0 = hand at the camera's minimum focus distance (plays highest note).
  ///
  /// Notifies on every frame callback (~30 fps) while [isActive] is true.
  final distance = ValueNotifier<double>(0.0);

  /// Latest JPEG thumbnail from the camera preview channel, or null if not
  /// yet received.  Updated at ≈ 10 fps while the camera is active.
  final previewFrame = ValueNotifier<Uint8List?>(null);

  /// True while the native camera session is running.
  bool get isActive => _subscription != null;

  // ─── EMA parameters ───────────────────────────────────────────────────────

  /// EMA smoothing factor α ∈ (0, 1].
  ///
  /// Higher α → faster response but more jitter.
  /// Lower  α → smoother but sluggish (laggy pitch changes).
  ///
  /// At α = 0.40 and 30 fps the step response reaches 63 % of a new target
  /// in ≈ 2 frames (~ 67 ms) — fast enough for musical playing without
  /// perceptible lag, while still removing single-frame noise spikes.
  ///
  /// Previously 0.15, which combined with the native-side EMA (also 0.15)
  /// created a double-smoothing effect with ~400 ms settling time.  The
  /// native-side EMA has been removed so this is now the only smoothing pass.
  static const double _alpha = 0.40;

  // ─── Private ──────────────────────────────────────────────────────────────

  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<dynamic>? _previewSubscription;

  // ─── Platform support ─────────────────────────────────────────────────────

  /// Whether the current platform has a native focal-distance implementation.
  ///
  /// Linux and Windows have no Flutter camera plugin support in this build;
  /// returning false here lets the slot UI disable the CAM button gracefully.
  bool get isPlatformSupported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  /// Requests camera permission and starts the native camera session.
  ///
  /// Returns null on success, or one of these error-code strings:
  ///   - `'PLATFORM_UNSUPPORTED'` — Linux, Windows, or web.
  ///   - `'NO_PERMISSION'`        — user denied camera permission.
  ///   - `'NO_CAMERA'`            — no suitable camera found on device.
  ///   - `'FIXED_FOCUS'`          — camera has no autofocus (common on webcams).
  ///   - `'CONFIG_ERROR'`         — AVFoundation / Camera2 configuration error.
  Future<String?> start() async {
    if (!isPlatformSupported) return 'PLATFORM_UNSUPPORTED';
    if (isActive) return null; // already running

    // ── Camera permission ──────────────────────────────────────────────────
    if (Platform.isMacOS) {
      // Workaround: permission_handler fails to register on macOS in this project.
      // Call the native permission request directly on our custom channel.
      final bool granted =
          await _kMethodChannel.invokeMethod<bool>('requestPermission') ?? false;
      if (!granted) return 'NO_PERMISSION';
    } else {
      // permission_handler covers Android and iOS correctly.
      final status = await Permission.camera.request();
      if (!status.isGranted) return 'NO_PERMISSION';
    }

    // ── Start native session ───────────────────────────────────────────────
    try {
      await _kMethodChannel.invokeMethod<void>('start');
    } on PlatformException catch (e) {
      return e.code; // propagates NO_CAMERA, FIXED_FOCUS, etc.
    }

    // ── Subscribe to distance event stream ────────────────────────────────
    _subscription = _kEventChannel.receiveBroadcastStream().listen(
      (raw) => _onRawFrame((raw as num).toDouble()),
      onError: (_) {}, // errors are handled; stream just stops
    );

    // ── Subscribe to preview thumbnail stream ─────────────────────────────
    _previewSubscription = _kPreviewChannel.receiveBroadcastStream().listen(
      (raw) {
        if (raw is Uint8List) previewFrame.value = raw;
      },
      onError: (_) {},
    );

    return null; // success
  }

  /// Stops the native camera session and releases the EventChannel subscription.
  ///
  /// Resets [distance] and [previewFrame] to their default values.
  /// Safe to call when already stopped.
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _previewSubscription?.cancel();
    _previewSubscription = null;

    if (isPlatformSupported) {
      // Ignore errors on stop (e.g. if the session never started).
      await _kMethodChannel.invokeMethod<void>('stop').catchError((_) {});
    }

    distance.value = 0.0;
    previewFrame.value = null;
  }

  /// Releases [distance], [previewFrame], and stops the session if running.
  void dispose() {
    stop();
    distance.dispose();
    previewFrame.dispose();
  }

  // ─── EMA smoothing ────────────────────────────────────────────────────────

  /// Applies an exponential moving average to each raw per-frame reading.
  ///
  /// EMA formula:  smoothed_n = smoothed_{n-1} × (1 − α) + raw_n × α
  ///
  /// Because α = 0.15, the impulse response decays to 1/e in ≈ 6 frames,
  /// which gives smooth pitch control without perceptible lag at 30 fps.
  void _onRawFrame(double raw) {
    final prev = distance.value;
    distance.value = prev * (1.0 - _alpha) + raw.clamp(0.0, 1.0) * _alpha;
  }
}
