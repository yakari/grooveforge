import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/audio_latency_status.dart';
import 'gfpa_android_bindings.dart';

/// Watches which output path the Android audio bus is on, so the user is told
/// when the app is playing slowly instead of having to guess.
///
/// The engine degrades itself on purpose when the platform's audio server
/// aborts on a low-latency stream: it drops to the legacy path, which costs
/// hundreds of milliseconds but keeps the phone from going silent. That trade
/// is right, and the code that makes it explains itself at length. What was
/// missing is any way for the person holding the instrument to know it
/// happened — the decision was only ever written to `logcat`.
///
/// The difference matters most on stage. A latched session stays slow until
/// the app is restarted, so a player who does not know about the latch has no
/// reason to suspect that force-quitting GrooveForge would give them a
/// playable instrument back, and reasonably concludes the app is broken.
///
/// Android only: every other platform either picks its device explicitly or
/// has no AAudio bus to degrade.
class AudioLatencyMonitor extends ChangeNotifier {
  /// Production monitor, wired to the native bus.
  static final AudioLatencyMonitor instance = AudioLatencyMonitor(
    readStatus: () => GfpaAndroidBindings.instance.oboeStreamGetLatencyStatus(),
    clearLatches: () =>
        GfpaAndroidBindings.instance.oboeStreamClearLatencyLatches(),
    enabled: !kIsWeb && Platform.isAndroid,
  );

  /// Builds a monitor from its inputs and outputs; tests pass fakes.
  ///
  /// [readStatus]   — reads the native bus status.
  /// [clearLatches] — clears the sticky latches and reopens the stream.
  /// [enabled]      — false on platforms with no AAudio bus, where the monitor
  ///   reports [AudioLatencyStatus.unavailable] and never polls.
  AudioLatencyMonitor({
    required AudioLatencyStatus Function() readStatus,
    required void Function() clearLatches,
    required this.enabled,
    Duration pollInterval = const Duration(seconds: 2),
  })  : _readStatus = readStatus,
        _clearLatches = clearLatches,
        _pollInterval = pollInterval;

  final AudioLatencyStatus Function() _readStatus;
  final void Function() _clearLatches;
  final Duration _pollInterval;

  /// Whether this platform has an AAudio bus worth watching.
  final bool enabled;

  Timer? _pollTimer;

  /// Follow-up read scheduled after a recovery, cancelled on dispose.
  Timer? _recoveryTimer;

  AudioLatencyStatus _status = AudioLatencyStatus.unavailable;

  /// The last status read from the bus.
  AudioLatencyStatus get status => _status;

  /// Whether a recovery is in flight.
  ///
  /// The native reopen happens on its own thread and takes a moment, during
  /// which the status still reads as degraded. Without this the button would
  /// look like it did nothing.
  bool get recovering => _recovering;
  bool _recovering = false;

  /// Starts polling. Safe to call more than once.
  void start() {
    if (!enabled || _pollTimer != null) return;
    _poll();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  /// Stops polling. The last known status stays readable.
  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Reads the bus once, notifying only when something changed.
  ///
  /// Polling is cheap but not free — the native side takes the stream mutex —
  /// so this runs a few times a minute, not a few times a second. Nothing here
  /// is time-critical: a latch that is minutes old is as worth showing as one
  /// that is seconds old.
  void _poll() {
    if (!enabled) return;
    final next = _readStatus();
    final changed = next.isDegraded != _status.isDegraded ||
        next.isLatched != _status.isLatched ||
        next.exclusiveGranted != _status.exclusiveGranted ||
        next.streamOpen != _status.streamOpen ||
        next.externalClock != _status.externalClock ||
        next.bufferMs != _status.bufferMs;

    _status = next;
    if (changed) notifyListeners();
  }

  /// Clears the sticky latches and asks the engine to retry the fast path.
  ///
  /// Deliberately only ever called from a user action. The engine used to
  /// re-arm itself on route changes and that made the crash it guards against
  /// feed itself — the audio server churns its device list as it restarts, so
  /// every restart looked like new hardware worth another try. A person
  /// pressing a button once is not that loop.
  void recover() {
    if (!enabled || _recovering) return;
    _recovering = true;
    notifyListeners();
    _clearLatches();

    // Read back sooner than the next scheduled poll so the UI settles quickly,
    // but not immediately: the native reopen is on another thread and has not
    // finished yet.
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(_recoverySettle, _finishRecovery);
  }

  /// How long to let the native reopen run before reading the result.
  ///
  /// The reopen is a stream close and open on a native thread; a few hundred
  /// milliseconds covers it on the devices this was measured on. Being late is
  /// harmless — the periodic poll corrects any reading taken too early — so
  /// this errs on the generous side.
  static const _recoverySettle = Duration(milliseconds: 600);

  /// Ends the recovery and reports whatever came of it.
  ///
  /// Unconditional: the attempt is over whether or not it worked. Clearing
  /// this only on success would leave the button spinning forever on the one
  /// device where the platform refuses the fast path no matter what, which is
  /// precisely where the user most needs to be told to restart the app
  /// instead.
  void _finishRecovery() {
    _recoveryTimer = null;
    _recovering = false;
    _poll();
    // _poll() stays quiet when the status did not move — which is exactly what
    // a failed recovery looks like — so the end of the attempt is announced
    // here rather than left to it.
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    super.dispose();
  }
}
