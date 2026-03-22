import 'package:flutter/material.dart';

/// An illuminated LED toggle button styled like a stomp-box footswitch.
///
/// When [value] is true the button glows with an orange LED indicator and the
/// metal body is highlighted. When false the LED is dark and the body sits in
/// shadow — matching the "engaged" vs "bypassed" states familiar from guitar
/// pedals.
///
/// Tapping the button calls [onChanged] with the toggled state.
class GFToggleButton extends StatelessWidget {
  const GFToggleButton({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.size = 36.0,
    this.activeColor = Colors.orange,
  });

  /// Whether the toggle is currently on.
  final bool value;

  /// Called with the new boolean state when the user taps.
  final ValueChanged<bool> onChanged;

  /// Label shown below the button.
  final String label;

  /// Outer diameter of the button in logical pixels.
  final double size;

  /// Colour of the LED when active. Defaults to orange (GrooveForge accent).
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _TogglePainter(active: value, activeColor: activeColor),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: value ? Colors.orange : Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a round stomp-box style button with metallic body and LED dot.
class _TogglePainter extends CustomPainter {
  final bool active;
  final Color activeColor;

  _TogglePainter({required this.active, required this.activeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // ── Outer shadow ─────────────────────────────────────────────────────────
    canvas.drawCircle(
      center.translate(0, active ? 0 : 2),
      radius,
      Paint()
        ..color = Colors.black87
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, active ? 2 : 5),
    );

    // ── Metallic body ─────────────────────────────────────────────────────────
    // The body is slightly smaller when active (pressed in).
    final bodyRadius = active ? radius - 1 : radius;
    canvas.drawCircle(
      center,
      bodyRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          radius: 1.0,
          colors: active
              ? const [Color(0xFF555555), Color(0xFF2A2A2A)]
              : const [Color(0xFF666666), Color(0xFF333333)],
        ).createShader(Rect.fromCircle(center: center, radius: bodyRadius)),
    );

    // ── Rim highlight ─────────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      bodyRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: active ? 0.06 : 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // ── LED indicator dot ─────────────────────────────────────────────────────
    // Small circle near the top of the button face.
    final ledCenter = center - Offset(0, bodyRadius * 0.42);
    final ledRadius = bodyRadius * 0.18;

    if (active) {
      // Glowing LED.
      canvas.drawCircle(
        ledCenter,
        ledRadius * 2.5,
        Paint()
          ..color = activeColor.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        ledCenter,
        ledRadius,
        Paint()..color = activeColor,
      );
      // Inner bright spot.
      canvas.drawCircle(
        ledCenter - Offset(ledRadius * 0.25, ledRadius * 0.25),
        ledRadius * 0.35,
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
    } else {
      // Dark LED.
      canvas.drawCircle(
        ledCenter,
        ledRadius,
        Paint()..color = const Color(0xFF1A1A1A),
      );
      canvas.drawCircle(
        ledCenter,
        ledRadius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }
  }

  @override
  bool shouldRepaint(_TogglePainter old) =>
      old.active != active || old.activeColor != activeColor;
}
