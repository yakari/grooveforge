import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/audio_input_ffi.dart';
import '../services/rehearsal_engine.dart' show kLatencyCompensationKey;
import '../services/gfpa_android_bindings.dart';

/// Measures the overdub round trip on this device, through the app's own
/// audio devices.
///
/// A musician overdubbing plays along to what they *hear*, which left the
/// engine some milliseconds ago; what they play then takes further
/// milliseconds to reach the engine. The captured take is therefore late
/// against the grid by the sum of the two, and has to be shifted earlier by
/// exactly that amount or every overdub sits behind the beat.
///
/// The measurement emits six short frequency sweeps at known positions on the
/// playback timeline and finds them again in the microphone stream by
/// cross-correlation. It deliberately runs on the devices the app already has
/// open, because the answer is only valid for the configuration it was
/// measured in.
///
/// This is developer instrumentation for the Rehearsals work (see
/// `docs/dev/REHEARSALS.md` §6.1), reached from Preferences.
class LatencyProbeScreen extends StatefulWidget {
  const LatencyProbeScreen({super.key});

  @override
  State<LatencyProbeScreen> createState() => _LatencyProbeScreenState();
}

/// Mirrors the native state machine in `gf_probe_poll`.
enum _ProbeState { idle, running, ready, failed }

class _LatencyProbeScreenState extends State<LatencyProbeScreen> {
  _ProbeState _state = _ProbeState.idle;

  /// Polls the native side while a run is in flight.
  ///
  /// The cross-correlation happens inside `probePoll`, so this deliberately
  /// runs on a timer rather than anywhere near a build method.
  Timer? _poller;

  /// Set when a run finished but the microphone never heard anything — the
  /// expected outcome on headphones, and worth saying plainly rather than
  /// reporting as a generic failure.
  bool _silentInput = false;

  /// Set when the run never even played out. The probe rides on the app's
  /// audio devices, so if capture is not running no callback ever fires, the
  /// native state stays at "running" forever, and without this the screen
  /// would spin indefinitely with nothing to show for it.
  bool _timedOut = false;

  /// How long to wait before concluding the audio devices are not running.
  /// One run is about 3.7 s of audio plus the correlation, so this leaves
  /// generous headroom over the slowest legitimate case.
  static const Duration _timeout = Duration(seconds: 12);
  DateTime? _startedAt;

  /// True once the probe has been registered on the Android output bus, so it
  /// is removed exactly once.
  ///
  /// Registered for the whole lifetime of the screen rather than per run. The
  /// probe's playback frame counter only advances while its render callback is
  /// being called, so removing the source between runs would freeze that clock
  /// while the capture clock kept going — and the next run would then schedule
  /// its sweeps at a playback frame many seconds in the future and time out.
  /// The render is a no-op when no measurement is in flight.
  bool _busSourceAdded = false;

  /// Android renders through Oboe, not through the miniaudio playback device
  /// (`start_audio_capture` logs "PLAYBACK device: skipped"), so on Android the
  /// sweep has to come from a registered bus source. Everywhere else the
  /// miniaudio playback callback emits it directly and there is nothing to
  /// register.
  bool get _needsBusSource => !kIsWeb && Platform.isAndroid;

  void _addBusSource() {
    if (!_needsBusSource || _busSourceAdded) return;
    final addr = AudioInputFFI().probeBusRenderFnAddr();
    if (addr == 0) return;
    GfpaAndroidBindings.instance
        .oboeStreamAddSource(addr, kBusSlotLatencyProbe);
    _busSourceAdded = true;
  }

  void _removeBusSource() {
    if (!_busSourceAdded) return;
    GfpaAndroidBindings.instance.oboeStreamRemoveSource(kBusSlotLatencyProbe);
    _busSourceAdded = false;
  }

  @override
  void initState() {
    super.initState();
    _addBusSource();
  }

  @override
  void dispose() {
    _poller?.cancel();
    AudioInputFFI().probeCancel();
    _removeBusSource();
    super.dispose();
  }

  Future<void> _start() async {
    // The probe rides on the app's own devices, and those are only opened when
    // something asks for the microphone. From a cold launch nothing has, so
    // starting capture here is what makes the screen work on its own rather
    // than only after the user happens to have opened a live input.
    // startCapture is idempotent — it returns immediately if already running.
    //
    // permission_handler is only registered for Android and iOS in this
    // project (see ThereminDistanceService, which works around the same gap on
    // macOS). Calling it on a desktop build throws MissingPluginException, and
    // there is nothing to ask for anyway: the desktop builds open the
    // microphone directly, exactly as the Live Input module already does.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        if (!mounted) return;
        setState(() {
          _state = _ProbeState.failed;
          _silentInput = true;
          _timedOut = false;
        });
        return;
      }
    }
    AudioInputFFI().startCapture();
    if (!mounted) return;
    // Normally added in initState; this covers the case where the bus was not
    // yet available then (the Oboe stream starts with the first audio source).
    _addBusSource();

    // The measurement needs both devices to have delivered at least one
    // callback, because it aligns their clocks from the timestamps taken
    // there. Capture has only just been asked to start, so give it a few
    // chances rather than failing on a device that is merely still spinning up.
    var started = AudioInputFFI().probeStart();
    for (var attempt = 0; started == -4 && attempt < 10; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
      started = AudioInputFFI().probeStart();
    }
    if (started != 0) {
      setState(() {
        _state = _ProbeState.failed;
        _silentInput = false;
      });
      return;
    }
    setState(() {
      _state = _ProbeState.running;
      _silentInput = false;
      _timedOut = false;
    });
    _startedAt = DateTime.now();
    _poller = Timer.periodic(const Duration(milliseconds: 250), (_) => _poll());
  }

  void _poll() {
    final native = AudioInputFFI().probePoll();
    if (native == 1) {
      final started = _startedAt;
      if (started == null ||
          DateTime.now().difference(started) < _timeout) {
        return; // still capturing
      }
      AudioInputFFI().probeCancel();
      _poller?.cancel();
      _poller = null;
      if (!mounted) return;
      setState(() {
        _state = _ProbeState.failed;
        _silentInput = false;
        _timedOut = true;
      });
      return;
    }
    _poller?.cancel();
    _poller = null;
    // A good measurement is the whole point of the screen, so it is stored
    // where the rehearsal engine will find it rather than left on screen for
    // the user to copy down.
    if (native == 2) _storeCompensation(AudioInputFFI().probeRoundTripFrames);
    if (!mounted) return;
    setState(() {
      _state = native == 2 ? _ProbeState.ready : _ProbeState.failed;
      _timedOut = false;
      // A run that captured nothing at all is a different problem from a run
      // whose correlation failed, and the fix is different too.
      _silentInput = native != 2 && AudioInputFFI().probeInputPeak < 1e-4;
    });
  }

  /// Persists the measured round trip for the rehearsal engine to pick up.
  Future<void> _storeCompensation(int frames) async {
    if (frames <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kLatencyCompensationKey, frames);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.latencyProbeTitle)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Single column on a phone, centred and width-capped on anything
            // larger — a results list gains nothing from a 1600 px measure.
            final maxWidth = constraints.maxWidth >= 600 ? 560.0 : double.infinity;
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: _buildBody(context, l10n),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildBody(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return [
      Text(l10n.latencyProbeExplain, style: theme.textTheme.bodyMedium),
      const SizedBox(height: 8),
      Text(
        l10n.latencyProbeHint,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _state == _ProbeState.running ? null : _start,
        icon: _state == _ProbeState.running
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.graphic_eq),
        label: Text(_state == _ProbeState.running
            ? l10n.latencyProbeMeasuring
            : l10n.latencyProbeStart),
      ),
      const SizedBox(height: 24),
      ..._buildResult(context, l10n),
    ];
  }

  List<Widget> _buildResult(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    if (_state == _ProbeState.idle || _state == _ProbeState.running) {
      return const [];
    }
    if (_state == _ProbeState.failed) {
      return [
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _timedOut
                  ? l10n.latencyProbeNeedsAudio
                  : _silentInput
                      ? l10n.latencyProbeSilentInput
                      : l10n.latencyProbeFailed,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ),
      ];
    }

    final ffi = AudioInputFFI();
    final drift = ffi.probeDriftPpm;
    // What the drift costs over a real take is the figure that means
    // something; parts per million on its own does not land.
    final slideMs = drift * 1e-6 * 4 * 60 * 1000;

    return [
      _headline(context, l10n, ffi.probeRoundTripMs, ffi.probeRoundTripFrames),
      const SizedBox(height: 16),
      _row(context, l10n.latencyProbeJitter,
          l10n.latencyProbeMs(ffi.probeJitterMs.toStringAsFixed(2))),
      _row(context, l10n.latencyProbeConfidence,
          ffi.probeConfidence.toStringAsFixed(1)),
      _row(context, l10n.latencyProbeShots,
          l10n.latencyProbeShotsValue(ffi.probeShotsFound, 6)),
      _row(context, l10n.latencyProbeDrift,
          l10n.latencyProbePpm(drift.toStringAsFixed(1))),
      _row(context, '', l10n.latencyProbeDriftOverTake(slideMs.toStringAsFixed(0)),
          subdued: true),
      _row(context, l10n.latencyProbeSkew,
          l10n.latencyProbeMs(ffi.probeSkewMs.toStringAsFixed(2))),
    ];
  }

  /// The round trip, set large because it is the one number that matters.
  Widget _headline(BuildContext context, AppLocalizations l10n, double ms,
      int frames) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.latencyProbeRoundTrip,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(
              l10n.latencyProbeMs(ms.toStringAsFixed(2)),
              style: theme.textTheme.displaySmall
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            Text(l10n.latencyProbeFramesSuffix(frames),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool subdued = false}) {
    final theme = Theme.of(context);
    final style = subdued
        ? theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)
        : theme.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value,
            style: style?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}
