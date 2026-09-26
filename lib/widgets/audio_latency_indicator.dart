import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/audio_latency_status.dart';
import '../services/audio_latency_monitor.dart';

/// An app-bar action that appears only when the audio output has gone slow.
///
/// Placed where the instrument is played, not in a settings page. The failure
/// it reports is one a player meets mid-performance: the keyboard suddenly
/// answers a quarter of a second late, and nothing on screen says why. By the
/// time anyone thinks to look in Preferences the set is over.
///
/// Invisible while the output is healthy, which is nearly always. That is the
/// point — it costs no app-bar space until it has something to say, so it can
/// sit permanently in a bar that is already busy.
class AudioLatencyIndicator extends StatefulWidget {
  /// The monitor to watch; defaults to the app-wide one.
  final AudioLatencyMonitor? monitor;

  const AudioLatencyIndicator({super.key, this.monitor});

  @override
  State<AudioLatencyIndicator> createState() => _AudioLatencyIndicatorState();
}

class _AudioLatencyIndicatorState extends State<AudioLatencyIndicator> {
  AudioLatencyMonitor get _monitor =>
      widget.monitor ?? AudioLatencyMonitor.instance;

  @override
  void initState() {
    super.initState();
    _monitor.addListener(_onChanged);
  }

  @override
  void dispose() {
    _monitor.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_monitor.status.isDegraded) return const SizedBox.shrink();

    final loc = AppLocalizations.of(context)!;
    return IconButton(
      icon: Icon(
        Icons.slow_motion_video,
        // Amber, not red: the app is playing and usable, it is simply late.
        // Red here would read as a failure that stops the show.
        color: Colors.amberAccent,
      ),
      tooltip: loc.audioOutputPathIndicatorTooltip,
      onPressed: () => showAudioLatencySheet(context, monitor: _monitor),
    );
  }
}

/// Opens the audio-path explanation: a bottom sheet on phones, a dialog on
/// wider screens (Rule 1).
void showAudioLatencySheet(BuildContext context, {AudioLatencyMonitor? monitor}) {
  final target = monitor ?? AudioLatencyMonitor.instance;
  final wide = MediaQuery.sizeOf(context).width >= 600;
  if (wide) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AudioLatencyDetails(monitor: target),
        ),
      ),
    );
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => AudioLatencyDetails(monitor: target),
  );
}

/// What the output path is doing, in plain language, with the way out.
///
/// Written for a musician mid-rehearsal, so it leads with what they can do
/// about it rather than with what AAudio returned.
class AudioLatencyDetails extends StatefulWidget {
  /// The monitor to read and act on.
  final AudioLatencyMonitor monitor;

  const AudioLatencyDetails({super.key, required this.monitor});

  @override
  State<AudioLatencyDetails> createState() => _AudioLatencyDetailsState();
}

class _AudioLatencyDetailsState extends State<AudioLatencyDetails> {
  /// Whether a recovery was asked for here and left the latch standing.
  ///
  /// Tracked so the sheet can say "that did not work, restart the app"
  /// instead of silently going back to the same message the button was
  /// pressed to change.
  bool _recoveryFailed = false;

  /// Whether the button has been pressed at least once on this sheet.
  ///
  /// Without it a sheet opened on an already-latched session would accuse a
  /// recovery that never ran of having failed.
  bool _pressedRestore = false;

  /// [AudioLatencyMonitor.recovering] as of the previous notification, so the
  /// moment a recovery ends can be told from the states either side of it.
  bool _wasRecovering = false;

  @override
  void initState() {
    super.initState();
    _wasRecovering = widget.monitor.recovering;
    widget.monitor.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.monitor.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    final recovering = widget.monitor.recovering;

    // A recovery just finished. If the latch survived it, the escape hatch
    // did not work and the only remaining one is restarting the app.
    if (_wasRecovering && !recovering && _pressedRestore) {
      _recoveryFailed = widget.monitor.status.isLatched;
    }
    _wasRecovering = recovering;

    setState(() {});
  }

  void _restore() {
    setState(() {
      _recoveryFailed = false;
      _pressedRestore = true;
    });
    widget.monitor.recover();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final status = widget.monitor.status;
    final recovering = widget.monitor.recovering;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.slow_motion_video, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.audioOutputPathTitle,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(_statusText(loc, status), style: theme.textTheme.bodyMedium),
            if (status.canRecover) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: recovering
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restart_alt),
                label: Text(
                  recovering
                      ? loc.audioOutputPathRestoring
                      : loc.audioOutputPathRestore,
                ),
                onPressed: recovering ? null : _restore,
              ),
              const SizedBox(height: 12),
              Text(
                _recoveryFailed
                    ? loc.audioOutputPathRestoreFailed
                    : loc.audioOutputPathRestartHint,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One localized paragraph describing [status].
  String _statusText(AppLocalizations loc, AudioLatencyStatus status) {
    if (status.externalClock) return loc.audioOutputPathUsbDirect;
    if (!status.streamOpen) return loc.audioOutputPathNoStream;
    if (status.isLatched) return loc.audioOutputPathLatched;
    if (!status.lowLatencyGranted) return loc.audioOutputPathSlow;

    final ms = (status.bufferMs ?? 0).toStringAsFixed(1);
    return status.exclusiveGranted
        ? loc.audioOutputPathFast(ms)
        : loc.audioOutputPathFastShared(ms);
  }
}
