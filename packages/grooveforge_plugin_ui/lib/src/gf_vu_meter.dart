import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A stereo VU meter widget with peak hold and orange/green gradient segments.
///
/// The meter displays left (L) and right (R) channel levels side by side as
/// segmented bars. The colour follows the classic broadcast convention:
/// - Green segments up to −6 dB (safe levels).
/// - Amber segments from −6 to 0 dB (approaching clipping).
/// - Red peak segment above 0 dBFS (digital clip — should not stay lit).
///
/// A small white peak-hold indicator freezes at the highest level seen,
/// then slowly decays back.
///
/// [updateStream] is an optional stream of [Float32List] pairs; if omitted the
/// meter can be driven manually by calling [GFVuMeterController.update].
class GFVuMeter extends StatefulWidget {
  const GFVuMeter({
    super.key,
    this.controller,
    this.width = 24.0,
    this.height = 80.0,
  });

  /// Controller to push amplitude updates from the audio thread.
  final GFVuMeterController? controller;

  /// Total widget width (covers both L + R bars).
  final double width;

  /// Total widget height.
  final double height;

  @override
  State<GFVuMeter> createState() => _GFVuMeterState();
}

/// Controller that lets the DSP thread push RMS amplitude values to the meter.
///
/// Create one controller per plugin/meter pair. Pass it to [GFVuMeter] and
/// call [update] from the audio-rendering pipeline with the latest
/// normalised amplitudes.
class GFVuMeterController extends ChangeNotifier {
  /// Left channel amplitude in [0.0, 1.0] (linear, not dB).
  double levelL = 0.0;

  /// Right channel amplitude in [0.0, 1.0] (linear, not dB).
  double levelR = 0.0;

  /// Push a new stereo level to the meter.
  ///
  /// Safe to call from any isolate; [notifyListeners] schedules a UI rebuild.
  void update(double l, double r) {
    levelL = l.clamp(0.0, 1.5); // allow slight over to show clip
    levelR = r.clamp(0.0, 1.5);
    notifyListeners();
  }
}

class _GFVuMeterState extends State<GFVuMeter>
    with SingleTickerProviderStateMixin {
  double _levelL = 0.0;
  double _levelR = 0.0;
  double _peakL = 0.0; // peak-hold values
  double _peakR = 0.0;
  int _peakHoldFramesL = 0; // countdown until peak starts decaying
  int _peakHoldFramesR = 0;

  late Ticker _ticker;

  // Peak hold: freeze for ~60 frames (~1 s at 60 fps) then decay.
  static const _kHoldFrames = 60;
  static const _kDecayRate = 0.015; // normalised per frame

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerUpdate);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(GFVuMeter old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.removeListener(_onControllerUpdate);
      widget.controller?.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerUpdate);
    _ticker.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    final c = widget.controller!;
    _levelL = c.levelL;
    _levelR = c.levelR;
    // Update peak hold.
    if (_levelL >= _peakL) {
      _peakL = _levelL;
      _peakHoldFramesL = _kHoldFrames;
    }
    if (_levelR >= _peakR) {
      _peakR = _levelR;
      _peakHoldFramesR = _kHoldFrames;
    }
  }

  void _onTick(Duration _) {
    // Decay: if no new peak, count down then slowly decay.
    bool changed = false;
    if (_peakHoldFramesL > 0) {
      _peakHoldFramesL--;
      changed = true;
    } else if (_peakL > 0) {
      _peakL = math.max(0, _peakL - _kDecayRate);
      changed = true;
    }
    if (_peakHoldFramesR > 0) {
      _peakHoldFramesR--;
      changed = true;
    } else if (_peakR > 0) {
      _peakR = math.max(0, _peakR - _kDecayRate);
      changed = true;
    }
    // Also decay bar level each frame (smooth fallback).
    if (_levelL > 0) {
      _levelL = math.max(0, _levelL - _kDecayRate * 0.5);
      changed = true;
    }
    if (_levelR > 0) {
      _levelR = math.max(0, _levelR - _kDecayRate * 0.5);
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _VuMeterPainter(
          levelL: _levelL,
          levelR: _levelR,
          peakL: _peakL,
          peakR: _peakR,
        ),
      ),
    );
  }
}

class _VuMeterPainter extends CustomPainter {
  final double levelL;
  final double levelR;
  final double peakL;
  final double peakR;

  _VuMeterPainter({
    required this.levelL,
    required this.levelR,
    required this.peakL,
    required this.peakR,
  });

  // Segment count and colour thresholds.
  static const _kSegments = 20;
  static const _kAmberThreshold = 0.7; // above this → amber
  static const _kRedThreshold = 0.95;  // above this → red
  static const _kGapPx = 2.0;          // gap between segments

  @override
  void paint(Canvas canvas, Size size) {
    final barW = (size.width - 2.0) / 2; // 2 bars + 2px gap in between
    _paintBar(canvas, 0, barW, size.height, levelL, peakL);
    _paintBar(canvas, barW + 2, barW, size.height, levelR, peakR);
  }

  void _paintBar(
    Canvas canvas,
    double x,
    double barW,
    double totalH,
    double level,
    double peak,
  ) {
    final segH = (totalH - _kGapPx * (_kSegments - 1)) / _kSegments;
    final activeSegments = (level.clamp(0.0, 1.0) * _kSegments).floor();
    final peakSeg = (peak.clamp(0.0, 1.0) * _kSegments).floor().clamp(0, _kSegments - 1);

    for (var s = 0; s < _kSegments; s++) {
      // Segments are drawn bottom-to-top.
      final segFraction = (s + 1) / _kSegments;
      final segY = totalH - (s + 1) * (segH + _kGapPx) + _kGapPx;
      final rect = Rect.fromLTWH(x, segY, barW, segH);

      final bool isActive = s < activeSegments;
      final bool isPeak = s == peakSeg && peak > 0.01;

      // Determine segment colour based on position (broadcast convention).
      final Color activeColour;
      if (segFraction > _kRedThreshold) {
        activeColour = const Color(0xFFFF2222); // red — clip warning
      } else if (segFraction > _kAmberThreshold) {
        activeColour = const Color(0xFFFFA500); // amber
      } else {
        activeColour = const Color(0xFF33CC44); // green
      }

      if (isActive) {
        // Lit segment with glow.
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
          Paint()
            ..color = activeColour
            ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.0),
        );
      } else {
        // Unlit segment (dark grey background).
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
          Paint()..color = const Color(0xFF1A1A1A),
        );
      }

      // Peak-hold indicator — a bright white/orange line on top of the segment.
      if (isPeak) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, segY, barW, 2.0),
            const Radius.circular(1),
          ),
          Paint()
            ..color = Colors.white
            ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5),
        );
      }
    }

    // Left/right label at the bottom of each bar.
  }

  @override
  bool shouldRepaint(_VuMeterPainter old) =>
      old.levelL != levelL ||
      old.levelR != levelR ||
      old.peakL != peakL ||
      old.peakR != peakR;
}
