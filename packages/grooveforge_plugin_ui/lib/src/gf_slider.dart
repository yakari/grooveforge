import 'package:flutter/material.dart';

/// A styled vertical (or horizontal) fader control matching the knob aesthetic.
///
/// The fader displays a metallic track with an orange glow indicator and a
/// draggable thumb. It is the standard control for parameters like volume,
/// send level, or EQ band gain.
///
/// [normalizedValue] and [onChanged] operate on the 0–1 range consistent with
/// [GFPlugin.getParameter] / [GFPlugin.setParameter].
class GFSlider extends StatefulWidget {
  const GFSlider({
    super.key,
    required this.normalizedValue,
    required this.onChanged,
    required this.label,
    this.axis = Axis.vertical,
    this.size = 120.0,
    this.thickness = 28.0,
    this.unit = '',
  });

  /// Normalised value in [0.0, 1.0].
  final double normalizedValue;

  /// Called with a new normalised value when the user drags the fader.
  final ValueChanged<double> onChanged;

  /// Label shown below (vertical) or beside (horizontal) the fader.
  final String label;

  /// Fader orientation: vertical (default, like a mixer channel strip) or
  /// horizontal (for pan controls or ratio sliders).
  final Axis axis;

  /// Length of the fader in logical pixels along its main axis.
  final double size;

  /// Width/height of the fader cross-section.
  final double thickness;

  /// Unit string shown in the tooltip (e.g. `"dB"`, `"%"`).
  final String unit;

  @override
  State<GFSlider> createState() => _GFSliderState();
}

class _GFSliderState extends State<GFSlider> {
  late double _value;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _tooltip;

  @override
  void initState() {
    super.initState();
    _value = widget.normalizedValue;
  }

  @override
  void didUpdateWidget(GFSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.normalizedValue != widget.normalizedValue) {
      setState(() => _value = widget.normalizedValue);
    }
  }

  @override
  void dispose() {
    _removeTooltip();
    super.dispose();
  }

  void _showTooltip() {
    if (_tooltip != null) return;
    _tooltip = OverlayEntry(
      builder: (_) => Positioned(
        width: 80,
        child: IgnorePointer(
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(-26.0, -48.0),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  widget.unit.isNotEmpty
                      ? '${(_value * 100).toStringAsFixed(0)}${widget.unit}'
                      : (_value * 100).toStringAsFixed(0),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_tooltip!);
  }

  void _removeTooltip() {
    _tooltip?.remove();
    _tooltip = null;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final isVertical = widget.axis == Axis.vertical;
    final delta = isVertical ? -details.delta.dy : details.delta.dx;
    final change = delta / widget.size;
    setState(() => _value = (_value + change).clamp(0.0, 1.0));
    widget.onChanged(_value);
  }

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.axis == Axis.vertical;
    final faderWidget = CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onVerticalDragStart: isVertical ? (_) => _showTooltip() : null,
        onVerticalDragUpdate: isVertical ? _onDragUpdate : null,
        onVerticalDragEnd: isVertical ? (_) => _removeTooltip() : null,
        onHorizontalDragStart: !isVertical ? (_) => _showTooltip() : null,
        onHorizontalDragUpdate: !isVertical ? _onDragUpdate : null,
        onHorizontalDragEnd: !isVertical ? (_) => _removeTooltip() : null,
        child: SizedBox(
          width: isVertical ? widget.thickness : widget.size,
          height: isVertical ? widget.size : widget.thickness,
          child: CustomPaint(
            painter: _FaderPainter(
              value: _value,
              axis: widget.axis,
            ),
          ),
        ),
      ),
    );

    if (isVertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          faderWidget,
          const SizedBox(height: 4),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        faderWidget,
        const SizedBox(width: 6),
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

/// Custom painter for the fader track and thumb.
class _FaderPainter extends CustomPainter {
  final double value;
  final Axis axis;

  _FaderPainter({required this.value, required this.axis});

  @override
  void paint(Canvas canvas, Size size) {
    final isVertical = axis == Axis.vertical;
    final trackW = isVertical ? 6.0 : size.width;
    final trackH = isVertical ? size.height : 6.0;
    final trackX = isVertical ? (size.width - trackW) / 2 : 0.0;
    final trackY = isVertical ? 0.0 : (size.height - trackH) / 2;

    final trackRect = Rect.fromLTWH(trackX, trackY, trackW, trackH);
    final rr = trackW / 2;

    // ── Track background ──────────────────────────────────────────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, Radius.circular(rr)),
      Paint()..color = Colors.black54,
    );

    // ── Active fill (orange glow below/left of thumb) ─────────────────────
    final fillFraction = value;
    final Rect fillRect;
    if (isVertical) {
      final fillTop = trackY + trackH * (1.0 - fillFraction);
      fillRect = Rect.fromLTWH(trackX, fillTop, trackW, trackH * fillFraction);
    } else {
      fillRect = Rect.fromLTWH(trackX, trackY, trackW * fillFraction, trackH);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(fillRect, Radius.circular(rr)),
      Paint()
        ..color = Colors.orange
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1.5),
    );

    // ── Thumb cap ────────────────────────────────────────────────────────
    final thumbW = isVertical ? size.width : 14.0;
    final thumbH = isVertical ? 14.0 : size.height;
    final double thumbX, thumbY;
    if (isVertical) {
      thumbX = 0;
      thumbY = (trackH - thumbH) * (1.0 - value);
    } else {
      thumbX = (trackW - thumbW) * value;
      thumbY = 0;
    }

    final thumbRect = Rect.fromLTWH(thumbX, thumbY, thumbW, thumbH);

    // Shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        thumbRect.shift(const Offset(0, 2)),
        const Radius.circular(4),
      ),
      Paint()
        ..color = Colors.black87
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Metal gradient thumb body.
    const metalGrad = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF555555), Color(0xFF777777), Color(0xFF444444)],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(thumbRect, const Radius.circular(4)),
      Paint()
        ..shader = metalGrad.createShader(thumbRect)
        ..style = PaintingStyle.fill,
    );

    // Highlight rim.
    canvas.drawRRect(
      RRect.fromRectAndRadius(thumbRect, const Radius.circular(4)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Orange line across thumb centre (the grip indicator).
    final lineY = thumbY + thumbH / 2;
    final lineX = thumbX + thumbW / 2;
    if (isVertical) {
      canvas.drawLine(
        Offset(thumbX + 4, lineY),
        Offset(thumbX + thumbW - 4, lineY),
        Paint()
          ..color = Colors.orange
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawLine(
        Offset(lineX, thumbY + 4),
        Offset(lineX, thumbY + thumbH - 4),
        Paint()
          ..color = Colors.orange
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_FaderPainter old) =>
      old.value != value || old.axis != axis;
}

