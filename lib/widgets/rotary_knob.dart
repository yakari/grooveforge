import 'package:flutter/material.dart';
import 'dart:math' as math;

class RotaryKnob extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String label;
  final ValueChanged<double> onChanged;
  final double size;

  const RotaryKnob({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    required this.label,
    required this.onChanged,
    this.size = 50.0,
  });

  @override
  State<RotaryKnob> createState() => _RotaryKnobState();
}

class _RotaryKnobState extends State<RotaryKnob> {
  late double _currentValue;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
  }

  @override
  void didUpdateWidget(RotaryKnob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _currentValue = widget.value;
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Up or Right -> increase, Down or Left -> decrease
    final delta = -details.delta.dy + details.delta.dx;
    final range = widget.max - widget.min;

    // ~150px drag covers the full range
    final change = (delta / 150.0) * range;

    setState(() {
      _currentValue = (_currentValue + change).clamp(widget.min, widget.max);
    });
    widget.onChanged(_currentValue);
  }

  @override
  Widget build(BuildContext context) {
    final normalizedValue =
        (_currentValue - widget.min) / (widget.max - widget.min);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onPanUpdate: _onPanUpdate,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(painter: _KnobPainter(value: normalizedValue)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
          ..color = Colors.white.withOpacity(0.15)
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
