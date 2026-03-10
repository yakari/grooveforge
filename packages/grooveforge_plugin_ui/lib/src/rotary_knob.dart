import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:async';

class RotaryKnob extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String label;
  final IconData? icon;
  final ValueChanged<double> onChanged;
  final double size;
  final bool isCompact;

  const RotaryKnob({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    required this.label,
    this.icon,
    required this.onChanged,
    this.size = 50.0,
    this.isCompact = false,
  });

  @override
  State<RotaryKnob> createState() => _RotaryKnobState();
}

class _RotaryKnobState extends State<RotaryKnob> {
  late double _currentValue;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  // Use a ValueNotifier to update the overlay without triggering a full rebuild of the knob widget.
  // This prevents "setState() during build" errors when the knob value is updated by the engine.
  late final ValueNotifier<double> _overlayValueNotifier;
  Timer? _overlayTimer;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _overlayValueNotifier = ValueNotifier<double>(widget.value);
  }

  @override
  void didUpdateWidget(RotaryKnob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _currentValue = widget.value;
      // Use addPostFrameCallback to avoid "setState() during build" if this update
      // happens during a build phase (which is common for ValueListenableBuilder updates).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _overlayValueNotifier.value = widget.value;
        }
      });
    }
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _hideOverlay();
    _overlayValueNotifier.dispose();
    super.dispose();
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 140,
          child: IgnorePointer(
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: const Offset(-45.0, -120.0), // Positioned above the knob
              child: ValueListenableBuilder<double>(
                valueListenable: _overlayValueNotifier,
                builder: (context, val, _) {
                  final normalizedValue =
                      (val - widget.min) / (widget.max - widget.min);
                  return Material(
                    color: Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.6),
                          width: 2.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 15,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.icon != null) ...[
                                Icon(
                                  widget.icon,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                widget.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 70,
                            height: 70,
                            child: CustomPaint(
                              painter: _KnobPainter(value: normalizedValue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayTimer?.cancel();
    _overlayTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onPanDown(DragDownDetails details) {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 200), () {
      _showOverlay();
    });
  }

  void _onPanStart(DragStartDetails details) {
    _overlayTimer?.cancel();
    _showOverlay();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Up or Right -> increase, Down or Left -> decrease
    final delta = -details.delta.dy + details.delta.dx;
    final range = widget.max - widget.min;

    // ~150px drag covers the full range
    final change = (delta / 150.0) * range;

    setState(() {
      _currentValue = (_currentValue + change).clamp(widget.min, widget.max);
      _overlayValueNotifier.value = _currentValue;
    });
    widget.onChanged(_currentValue);
  }

  void _onPanEnd(DragEndDetails details) {
    _hideOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final normalizedValue =
        (_currentValue - widget.min) / (widget.max - widget.min);

    return CompositedTransformTarget(
      link: _layerLink,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onPanDown: _onPanDown,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onPanCancel: _hideOverlay,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: CustomPaint(painter: _KnobPainter(value: normalizedValue)),
            ),
          ),
          SizedBox(height: widget.isCompact ? 1 : 4),
          if (widget.isCompact && widget.icon != null)
            Icon(widget.icon, size: 14, color: Colors.white70)
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 12, color: Colors.white70),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double value; // Always 0.0 to 1.0

  _KnobPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Outer track background
    final startAngle = math.pi * 0.75;
    final sweepAngle = math.pi * 1.5;

    final trackPaint =
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 2),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // LED Indicator strip (Glowing orange)
    final activePaint =
        Paint()
          ..color = Colors.orange
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 2),
      startAngle,
      sweepAngle * value,
      false,
      activePaint,
    );

    // Inner Metallic Body
    final innerRadius = radius - 8;

    // Shadow under the knob body
    canvas.drawCircle(
      center.translate(0, 2),
      innerRadius,
      Paint()
        ..color = Colors.black87
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0),
    );

    // Metallic conical gradient
    final metalGradient = SweepGradient(
      colors: const [
        Color(0xFF333333), // Dark
        Color(0xFF666666), // Light
        Color(0xFF333333), // Dark
        Color(0xFF666666), // Light
        Color(0xFF333333), // Dark
      ],
      stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
      transform: GradientRotation(math.pi / 4),
    );

    final metalPaint =
        Paint()
          ..shader = metalGradient.createShader(
            Rect.fromCircle(center: center, radius: innerRadius),
          )
          ..style = PaintingStyle.fill;

    canvas.drawCircle(center, innerRadius, metalPaint);

    // Top rim highlight for realistic bevel
    final innerBevelPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.15)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
    canvas.drawCircle(center, innerRadius, innerBevelPaint);

    // Draw the indicator mark on the metal knob
    final currentAngle = startAngle + (sweepAngle * value);
    final lineStart = Offset(
      center.dx + math.cos(currentAngle) * (innerRadius * 0.2),
      center.dy + math.sin(currentAngle) * (innerRadius * 0.2),
    );
    final lineEnd = Offset(
      center.dx + math.cos(currentAngle) * (innerRadius * 0.8),
      center.dy + math.sin(currentAngle) * (innerRadius * 0.8),
    );

    final indicatorPaint =
        Paint()
          ..color = Colors.orange
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.0;

    canvas.drawLine(lineStart, lineEnd, indicatorPaint);

    // A small black line shadow next to indicator for depth
    final shadowIndicatorPaint =
        Paint()
          ..color = Colors.black54
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.0;

    canvas.drawLine(
      lineStart.translate(1, 1),
      lineEnd.translate(1, 1),
      shadowIndicatorPaint,
    );
  }

  @override
  bool shouldRepaint(_KnobPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}
