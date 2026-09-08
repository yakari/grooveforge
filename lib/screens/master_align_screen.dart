import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../services/audio_input_ffi.dart';
import '../services/master_silence.dart';
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

  /// How much of the recording is on screen, as a fraction.
  ///
  /// 1 is the whole thing. Aligning a downbeat by eye needs far more than
  /// that: at a phone's width, a three-minute track puts a whole bar inside
  /// two pixels, which is why this screen used to be a matter of nudging and
  /// listening rather than looking.
  double _zoom = 1.0;

  /// Left edge of the visible window, in frames.
  int _viewStart = 0;

  /// Where the recording stops being silent, once known.
  int _firstSound = 0;


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
    final path = await widget.engine.masterFilePath();
    if (path == null) return;
    // Resolution follows the zoom: the whole file at 600 bins is about one per
    // two pixels, and zooming in on that would magnify the bins rather than
    // the sound. Capped, because past this the drawing is finer than the
    // screen and the only thing that grows is the wait.
    final bins = (600 * _zoom).round().clamp(600, 24000);
    final wave = AudioInputFFI().mediaWaveform(path, bins);
    if (!mounted) return;
    setState(() => _waveform = wave);
    unawaited(_findSilence(path));
  }

  /// Looks for where the recording starts, so the marker can skip a lead-in.
  Future<void> _findSilence(String path) async {
    if (_firstSound > 0) return;
    final at = await MasterSilence.firstSound(path, sampleRate: _sampleRate);
    if (!mounted || at <= 0) return;
    setState(() => _firstSound = at);
  }

  /// Frames currently on screen.
  int get _viewFrames =>
      (_master.frames / _zoom).round().clamp(1, _master.frames);

  /// Keeps the window inside the recording after a zoom or a scroll.
  void _clampView() {
    final maxStart = _master.frames - _viewFrames;
    _viewStart = _viewStart.clamp(0, maxStart < 0 ? 0 : maxStart);
  }

  /// Zooms about the downbeat marker, which is the thing being aimed at.
  ///
  /// Zooming about the centre of the screen would walk the marker off the edge
  /// after two presses, and it is the only reason anyone is zooming.
  void _setZoom(double zoom) {
    final next = zoom.clamp(1.0, 400.0);
    if (next == _zoom) return;
    setState(() {
      _zoom = next;
      _viewStart = _offsetFrames - _viewFrames ~/ 2;
      _clampView();
    });
    _loadWaveform();
  }

  void _scrollBy(double fractionOfView) {
    setState(() {
      _viewStart += (_viewFrames * fractionOfView).round();
      _clampView();
    });
  }

  /// Adjusts the tempo by a tenth of a beat.
  ///
  /// The tap tempo lands within a beat or so; the last tenth is what decides
  /// whether the beat lines still sit on the sound thirty bars later, and it
  /// is not something anybody can tap.
  void _nudgeBpm(double by) {
    setState(() => _bpm = (_bpm + by).clamp(40.0, 240.0));
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

  /// Plays from the top so the alignment can be judged by ear.
  ///
  /// Through the tune's count-in, so a recording with a lead-in is heard
  /// before the downbeat and you can tell whether the first beat of the music
  /// lands on the first beat of the grid.
  Future<void> _check() async {
    await widget.engine.setMasterOffset(_offsetFrames);
    await widget.engine.setMasterTempo(_bpm);
    widget.engine.play();
  }

  Future<void> _done() async {
    await widget.engine.setMasterOffset(_offsetFrames);
    // setMasterTempo, not setBpm: measuring the recording's tempo must not
    // stretch the recording being measured.
    await widget.engine.setMasterTempo(_bpm);
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
                      // Dragging places the marker while zoomed out and while
                      // zoomed in alike; the buttons below are for scrolling,
                      // because a drag here means "the downbeat is there".
                      onHorizontalDragUpdate: (d) =>
                          _setFromX(d.localPosition.dx, width),
                      child: SizedBox(
                        height: 140,
                        child: CustomPaint(
                          painter: _WaveformPainter(
                            waveform: _waveform,
                            totalFrames: _master.frames,
                            viewStart: _viewStart,
                            viewFrames: _viewFrames,
                            markerFrames: _offsetFrames,
                            framesPerBeat:
                                _bpm > 0 ? _sampleRate * 60 / _bpm : 0,
                            beatsPerBar: widget.rehearsal.beatsPerBar,
                            waveColor: theme.colorScheme.primary
                                .withValues(alpha: 0.55),
                            markerColor: theme.colorScheme.tertiary,
                            beatColor: const Color(0xFFE53935),
                            gridColor: theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),

                // ── Zoom and scroll ───────────────────────────────────────
                Row(
                  children: [
                    IconButton(
                      onPressed: _viewStart <= 0
                          ? null
                          : () => _scrollBy(-0.5),
                      tooltip: l10n.masterNudgeBack,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      onPressed:
                          _zoom <= 1.0 ? null : () => _setZoom(_zoom / 2),
                      tooltip: l10n.masterZoomOut,
                      icon: const Icon(Icons.zoom_out),
                    ),
                    Text(
                      l10n.masterZoomLevel(_zoom.round()),
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    IconButton(
                      onPressed:
                          _zoom >= 400 ? null : () => _setZoom(_zoom * 2),
                      tooltip: l10n.masterZoomIn,
                      icon: const Icon(Icons.zoom_in),
                    ),
                    IconButton(
                      onPressed: _zoom == 1.0 ? null : () => _setZoom(1),
                      tooltip: l10n.masterZoomReset,
                      icon: const Icon(Icons.fit_screen_outlined),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed:
                          _viewStart + _viewFrames >= _master.frames
                              ? null
                              : () => _scrollBy(0.5),
                      tooltip: l10n.masterNudgeForward,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
                Text(
                  l10n.masterBeatLinesHint,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.masterDownbeatAt(_formatTime(_offsetFrames)),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _nudge(-10),
                      icon: const Icon(Icons.chevron_left, size: 18),
                      label: Text(l10n.masterNudgeBack),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _nudge(10),
                      icon: const Icon(Icons.chevron_right, size: 18),
                      label: Text(l10n.masterNudgeForward),
                    ),
                    // Offered only once the scan has found something, and
                    // never when the marker is already there — a button that
                    // does nothing is worse than one that is absent.
                    if (_firstSound > 0 && _offsetFrames != _firstSound)
                      OutlinedButton.icon(
                        onPressed: () => setState(() {
                          _offsetFrames = _firstSound;
                          _viewStart = _firstSound - _viewFrames ~/ 3;
                          _clampView();
                        }),
                        icon: const Icon(Icons.content_cut, size: 18),
                        label: Text(l10n.masterSkipSilence),
                      ),
                  ],
                ),

                const Divider(height: 40),

                // ── Tap tempo ─────────────────────────────────────────────
                // The value between its two buttons, because the last tenth
                // of a beat decides whether the lines still sit on the sound
                // thirty bars later — and it is not something anyone can tap.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: widget.rehearsal.isGridFrozen
                          ? null
                          : () => _nudgeBpm(-0.1),
                      tooltip: l10n.masterBpmFiner,
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Text(
                        l10n.rehearsalBpmValue(_bpm.toStringAsFixed(1)),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: widget.rehearsal.isGridFrozen
                          ? null
                          : () => _nudgeBpm(0.1),
                      tooltip: l10n.masterBpmFaster,
                      icon: const Icon(Icons.add),
                    ),
                  ],
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

  /// Places the downbeat at the frame under the finger.
  ///
  /// Through the visible window rather than the whole file, or every tap while
  /// zoomed in would land somewhere near the start of the recording.
  void _setFromX(double dx, double width) {
    if (width <= 0 || _master.frames == 0) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    setState(() {
      _offsetFrames = (_viewStart + fraction * _viewFrames)
          .round()
          .clamp(0, _master.frames);
    });
  }
}

/// Draws the peak envelope with a marker at the chosen downbeat.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.waveform,
    required this.totalFrames,
    required this.viewStart,
    required this.viewFrames,
    required this.markerFrames,
    required this.framesPerBeat,
    required this.beatsPerBar,
    required this.waveColor,
    required this.markerColor,
    required this.beatColor,
    required this.gridColor,
  });

  /// The whole recording, at whatever resolution it was fetched.
  final List<double> waveform;

  final int totalFrames;

  /// The visible window, in frames.
  final int viewStart;
  final int viewFrames;

  /// Where the tune's first downbeat sits, in frames.
  final int markerFrames;

  /// Spacing of the beat lines. Zero draws none.
  final double framesPerBeat;
  final int beatsPerBar;

  final Color waveColor;
  final Color markerColor;
  final Color beatColor;
  final Color gridColor;

  /// Where a frame lands on screen.
  double _x(double frames, double width) =>
      (frames - viewStart) / viewFrames * width;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;

    // Centre line, so a quiet passage still reads as audio rather than as an
    // empty box.
    canvas.drawLine(Offset(0, mid), Offset(size.width, mid),
        Paint()..color = gridColor..strokeWidth = 1);

    if (waveform.isNotEmpty && totalFrames > 0) {
      final paint = Paint()
        ..color = waveColor
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round;
      final framesPerBin = totalFrames / waveform.length;
      // Only the bins inside the window, so zooming costs no more to draw
      // than the whole file did.
      final first = (viewStart / framesPerBin).floor().clamp(0, waveform.length);
      final last = ((viewStart + viewFrames) / framesPerBin)
          .ceil()
          .clamp(0, waveform.length);
      for (var i = first; i < last; i++) {
        final x = _x(i * framesPerBin, size.width);
        final h = waveform[i].clamp(0.0, 1.0) * mid;
        canvas.drawLine(Offset(x, mid - h), Offset(x, mid + h), paint);
      }
    }

    // ── Beats ───────────────────────────────────────────────────────────────
    //
    // The point of zooming: with the lines drawn from the downbeat at the
    // current tempo, a tempo that is a tenth out shows up as drift against the
    // sound after a few bars, which is not something anybody can hear in two
    // bars but is obvious at a glance.
    if (framesPerBeat > 1) {
      final beatPaint = Paint()
        ..color = beatColor.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      final barPaint = Paint()
        ..color = beatColor
        ..strokeWidth = 1.5;

      // Start from the first beat at or before the window, counting from the
      // downbeat so bar lines land where the bars actually do.
      final firstBeat =
          ((viewStart - markerFrames) / framesPerBeat).floor();
      final lastBeat =
          ((viewStart + viewFrames - markerFrames) / framesPerBeat).ceil();
      // A window holding thousands of beats would be a solid wash; below a
      // few pixels apart they say nothing.
      if ((lastBeat - firstBeat) * (size.width / viewFrames) * framesPerBeat >
          0) {
        final spacingPx = framesPerBeat / viewFrames * size.width;
        if (spacingPx >= 4) {
          for (var b = firstBeat; b <= lastBeat; b++) {
            final frames = markerFrames + b * framesPerBeat;
            if (frames < 0) continue;
            final x = _x(frames, size.width);
            if (x < 0 || x > size.width) continue;
            final isBar = beatsPerBar > 0 && b % beatsPerBar == 0;
            canvas.drawLine(
              Offset(x, isBar ? 0 : size.height * 0.18),
              Offset(x, isBar ? size.height : size.height * 0.82),
              isBar ? barPaint : beatPaint,
            );
          }
        }
      }
    }

    // ── The downbeat marker ────────────────────────────────────────────────
    final x = _x(markerFrames.toDouble(), size.width);
    if (x >= -8 && x <= size.width + 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height),
          Paint()..color = markerColor..strokeWidth = 2);
      // A grab handle, so the marker looks like something that can be moved.
      canvas.drawCircle(Offset(x, 8), 6, Paint()..color = markerColor);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.markerFrames != markerFrames ||
      old.viewStart != viewStart ||
      old.viewFrames != viewFrames ||
      old.framesPerBeat != framesPerBeat ||
      !identical(old.waveform, waveform);
}
