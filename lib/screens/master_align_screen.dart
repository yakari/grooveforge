import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../services/audio_input_ffi.dart';
import '../services/rehearsal_engine.dart';

/// Anchors the bar grid to an imported recording.
///
/// Two numbers are needed: the tempo, and which frame of the recording is the
/// tune's first downbeat. Both are set by hand here, deliberately.
///
/// There is no automatic beat detection, and that is a decision rather than an
/// omission (REHEARSALS.md §7.2). A tracker that is right most of the time is
/// worse than none, because the player cannot tell which times it was wrong —
/// they would have to check every result anyway, and a wrong grid quietly
/// misplaces every part recorded against it. Tapping along and dragging a
/// marker takes about twenty seconds and the player knows it is right.
class MasterAlignScreen extends StatefulWidget {
  const MasterAlignScreen({
    super.key,
    required this.engine,
    required this.rehearsal,
  });

  final RehearsalEngine engine;
  final Rehearsal rehearsal;

  @override
  State<MasterAlignScreen> createState() => _MasterAlignScreenState();
}

class _MasterAlignScreenState extends State<MasterAlignScreen> {
  List<double> _waveform = const [];
  late int _offsetFrames;
  late double _bpm;

  /// Times of the taps in the current run, used for the tempo estimate.
  final List<DateTime> _taps = [];

  RehearsalMaster get _master => widget.rehearsal.master!;
  int get _sampleRate => _master.sampleRate;

  @override
  void initState() {
    super.initState();
    _offsetFrames = _master.offsetFrames;
    _bpm = widget.rehearsal.bpm;
    _loadWaveform();
  }

  Future<void> _loadWaveform() async {
    // 600 bins is about one per two pixels on a phone — enough to see a
    // transient without turning the drawing into a solid block.
    final path = await widget.engine.masterFilePath();
    if (path == null) return;
    final wave = AudioInputFFI().mediaWaveform(path, 600);
    if (!mounted) return;
    setState(() => _waveform = wave);
  }

  /// Records a tap and re-estimates the tempo from the run so far.
  void _tap() {
    final now = DateTime.now();
    // A gap longer than two seconds means the player stopped and started
    // again; the previous run tells us nothing about this one.
    if (_taps.isNotEmpty && now.difference(_taps.last).inMilliseconds > 2000) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length < 3) {
      setState(() {});
      return;
    }

    // Average the intervals rather than dividing the total span, so one late
    // tap in the middle does not bias everything after it.
    var totalMs = 0;
    for (var i = 1; i < _taps.length; i++) {
      totalMs += _taps[i].difference(_taps[i - 1]).inMilliseconds;
    }
    final avg = totalMs / (_taps.length - 1);
    if (avg <= 0) return;
    final bpm = (60000 / avg).clamp(40.0, 240.0);
    setState(() => _bpm = bpm);
  }

  void _nudge(int ms) {
    setState(() {
      _offsetFrames =
          (_offsetFrames + ms * _sampleRate ~/ 1000).clamp(0, _master.frames);
    });
  }

  /// Plays two bars from the downbeat so the alignment can be judged by ear.
  Future<void> _check() async {
    await widget.engine.setMasterOffset(_offsetFrames);
    await widget.engine.setBpm(_bpm);
    widget.engine.playFrom(0);
  }

  Future<void> _done() async {
    await widget.engine.setMasterOffset(_offsetFrames);
    await widget.engine.setBpm(_bpm);
    await widget.engine.stop();
    if (mounted) Navigator.of(context).pop();
  }

  String _formatTime(int frames) {
    final ms = _sampleRate > 0 ? frames * 1000 ~/ _sampleRate : 0;
    final s = ms ~/ 1000;
    final rem = ms % 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'
        '.${(rem ~/ 10).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.masterAlignTitle),
        actions: [
          TextButton(onPressed: _done, child: Text(l10n.masterDone)),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(l10n.masterAlignHint, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 20),

                // ── Waveform with a draggable downbeat marker ──────────────
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => _setFromX(d.localPosition.dx, width),
                      onHorizontalDragUpdate: (d) =>
                          _setFromX(d.localPosition.dx, width),
                      child: SizedBox(
                        height: 120,
                        child: CustomPaint(
                          painter: _WaveformPainter(
                            waveform: _waveform,
                            markerFraction: _master.frames == 0
                                ? 0
                                : _offsetFrames / _master.frames,
                            waveColor: theme.colorScheme.primary
                                .withValues(alpha: 0.55),
                            markerColor: theme.colorScheme.error,
                            gridColor: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.masterDownbeatAt(_formatTime(_offsetFrames)),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _nudge(-10),
                      icon: const Icon(Icons.chevron_left, size: 18),
                      label: Text(l10n.masterNudgeBack),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _nudge(10),
                      icon: const Icon(Icons.chevron_right, size: 18),
                      label: Text(l10n.masterNudgeForward),
                    ),
                  ],
                ),

                const Divider(height: 40),

                // ── Tap tempo ─────────────────────────────────────────────
                Text(
                  l10n.rehearsalBpmValue(_bpm.toStringAsFixed(1)),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: widget.rehearsal.isGridFrozen ? null : _tap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(_taps.length < 3
                        ? l10n.masterTapTempo
                        : l10n.masterTapMore),
                  ),
                ),
                if (widget.rehearsal.isGridFrozen) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.rehearsalGridFrozen,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],

                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _check,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.masterCheck),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _setFromX(double dx, double width) {
    if (width <= 0 || _master.frames == 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _offsetFrames = (fraction * _master.frames).round();
    });
  }
}

/// Draws the peak envelope with a marker at the chosen downbeat.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.waveform,
    required this.markerFraction,
    required this.waveColor,
    required this.markerColor,
    required this.gridColor,
  });

  final List<double> waveform;
  final double markerFraction;
  final Color waveColor;
  final Color markerColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;

    // Centre line, so a quiet passage still reads as audio rather than as an
    // empty box.
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid),
        Paint()..color = gridColor..strokeWidth = 1);

    if (waveform.isNotEmpty) {
      final paint = Paint()
        ..color = waveColor
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < waveform.length; i++) {
        final x = size.width * i / waveform.length;
        final h = (waveform[i].clamp(0.0, 1.0)) * mid;
        canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), paint);
      }
    }

    final x = size.width * markerFraction.clamp(0.0, 1.0);
    canvas.drawLine(Offset(x, 0), Offset(x, size.height),
        Paint()..color = markerColor..strokeWidth = 2);
    // A grab handle, so the marker looks like something that can be moved.
    canvas.drawCircle(Offset(x, 8), 6, Paint()..color = markerColor);
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.markerFraction != markerFraction ||
      !identical(old.waveform, waveform);
}
