import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A horizontal semitone track for choosing a musical interval.
///
/// Replaces the rotary knob for parameters whose value is an interval — a
/// harmonizer voice, a transposer amount. Three things a knob cannot do:
///
///   1. **Show where the value sits.** The handle's position on the ruler is
///      the interval, read at a glance, with the root marked and every
///      octave ticked.
///   2. **Show the shape of a chord.** Stack four of these and the four
///      handles are the voicing.
///   3. **Land on an exact semitone.** A knob needs a 150 px drag to cross
///      the range; here the drag snaps to whole semitones and the step
///      buttons either side move one at a time, holding to repeat.
///
/// The bar fills whatever width it is given, so it belongs in an [Expanded]
/// inside a row. Below about 220 px the step buttons alone remain practical,
/// which is why they are always present rather than a wide-screen extra.
class GFIntervalBar extends StatefulWidget {
  const GFIntervalBar({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.label,
    this.valueLabel,
    this.detailLabel,
    this.tooltip,
    this.enabled = true,
    this.compact = false,
  });

  /// Current value in semitones. Rounded to a whole semitone for display.
  final double value;

  /// Lowest selectable interval, in semitones (e.g. -24).
  final double min;

  /// Highest selectable interval, in semitones (e.g. +24).
  final double max;

  /// Called with the new whole-semitone value.
  final ValueChanged<double> onChanged;

  /// Optional short name shown at the left of the track (e.g. `"V1"`).
  final String? label;

  /// Primary readout shown at the right (e.g. `"+7 st"`). Supplied by the
  /// host so it can be localised.
  final String? valueLabel;

  /// Secondary line under [valueLabel] naming the interval (e.g.
  /// `"Perfect 5th"`). Ellipsised if the column is too narrow for it.
  final String? detailLabel;

  /// Long-press text carrying the whole thing, never truncated.
  final String? tooltip;

  /// When false the bar renders dimmed and ignores input — used for a voice
  /// the plugin is not currently playing.
  final bool enabled;

  /// Moves the readout below the track so the ruler keeps the full width of
  /// the row. The track is the part squeezed out first on a phone, and it is
  /// the part that carries the meaning.
  final bool compact;

  @override
  State<GFIntervalBar> createState() => _GFIntervalBarState();
}

class _GFIntervalBarState extends State<GFIntervalBar> {
  /// Repeat timer for a held step button.
  Timer? _repeat;

  /// Track width at the last layout, needed to convert a drag in pixels
  /// into semitones.
  double _trackWidth = 1;

  /// Sub-semitone travel accumulated during the current drag.
  ///
  /// The handle itself is drawn from [GFIntervalBar.value] — the host's
  /// value — and never from a local copy. Mirroring the value locally is
  /// what made an earlier revision snap back on release: the mirror was
  /// updated first, the "has it changed?" test then compared the new value
  /// against itself, and the host was never told. Keeping only the residue
  /// here leaves one source of truth.
  double _residue = 0;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  double get _current => widget.value.roundToDouble();

  /// Hands [raw] to the host, snapped to a semitone and clamped to range.
  /// Silent when it would not change anything.
  void _emit(double raw) {
    final snapped = raw.roundToDouble().clamp(widget.min, widget.max);
    if (snapped == _current) return;
    widget.onChanged(snapped);
  }

  void _step(int semitones) => _emit(_current + semitones);

  /// Starts a step that repeats while the button stays held, so crossing an
  /// octave does not take twelve taps.
  void _startRepeat(int semitones) {
    _step(semitones);
    _repeat?.cancel();
    _repeat = Timer(const Duration(milliseconds: 400), () {
      _repeat = Timer.periodic(
        const Duration(milliseconds: 70),
        (_) => _step(semitones),
      );
    });
  }

  void _stopRepeat() {
    _repeat?.cancel();
    _repeat = null;
  }

  /// Value the track represents at horizontal position [dx].
  double _valueAt(double dx) =>
      widget.min + (dx / math.max(_trackWidth, 1)) * (widget.max - widget.min);

  void _onDragStart(DragStartDetails _) => _residue = 0;

  /// Accumulates the drag and emits once per semitone crossed.
  ///
  /// Emitting on every pixel would spam the host with the same value; only
  /// whole semitones are meaningful, so the fractional part is carried until
  /// it adds up to one.
  void _onDragUpdate(DragUpdateDetails details) {
    final perPixel = (widget.max - widget.min) / math.max(_trackWidth, 1);
    _residue += details.delta.dx * perPixel;
    final steps = _residue.truncate();
    if (steps == 0) return;
    _residue -= steps;
    _emit(_current + steps);
  }

  void _onDragEnd(DragEndDetails _) => _residue = 0;

  /// Jumps the handle straight to a tapped position on the track.
  void _onTapDown(TapDownDetails details) {
    _residue = 0;
    _emit(_valueAt(details.localPosition.dx));
  }

  @override
  Widget build(BuildContext context) {
    final track = Row(
      children: [
        if (widget.label != null)
          SizedBox(
            width: 26,
            child: Text(
              widget.label!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        _StepButton(
          icon: Icons.remove,
          onPressed: widget.enabled ? () => _startRepeat(-1) : null,
          onReleased: _stopRepeat,
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (_, constraints) {
              _trackWidth = constraints.maxWidth;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: widget.enabled ? _onTapDown : null,
                onHorizontalDragStart: widget.enabled ? _onDragStart : null,
                onHorizontalDragUpdate: widget.enabled ? _onDragUpdate : null,
                onHorizontalDragEnd: widget.enabled ? _onDragEnd : null,
                child: SizedBox(
                  height: 28,
                  child: CustomPaint(
                    painter: _IntervalTrackPainter(
                      value: _current,
                      min: widget.min,
                      max: widget.max,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        _StepButton(
          icon: Icons.add,
          onPressed: widget.enabled ? () => _startRepeat(1) : null,
          onReleased: _stopRepeat,
        ),
      ],
    );

    // On a phone the readout drops below the track instead of sitting beside
    // it. Side by side, a fixed readout column and the step buttons leave the
    // ruler about a quarter of the row — and a ruler that short says nothing
    // about where the interval sits, which was the whole reason for it.
    final body = widget.compact
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              track,
              _Readout(
                value: widget.valueLabel,
                detail: widget.detailLabel,
                tooltip: widget.tooltip,
                inline: true,
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: track),
              _Readout(
                value: widget.valueLabel,
                detail: widget.detailLabel,
                tooltip: widget.tooltip,
                width: 112,
              ),
            ],
          );

    return Opacity(opacity: widget.enabled ? 1.0 : 0.35, child: body);
  }
}

// ── Readout ──────────────────────────────────────────────────────────────────

/// The value printed beside the track.
///
/// Two lines rather than one: the semitone count is the number the player
/// acts on, the interval's name is what it means musically, and running them
/// together as "+7 st · P5" made a dense little blob at a size nobody could
/// read. The name is also spelled out — "Perfect 5th" rather than "P5" —
/// because the abbreviations distinguish major from minor by letter case
/// alone, which is exactly what stops being legible when the text is small.
///
/// The full text is repeated in a tooltip, so a name too long for the column
/// is still reachable by holding the readout.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.value,
    required this.detail,
    required this.tooltip,
    this.width,
    this.inline = false,
  });

  final String? value;
  final String? detail;
  final String? tooltip;

  /// Fixed column width for the beside-the-track form. Null when [inline].
  final double? width;

  /// Lay the two parts out on one line, sized by the row they sit in.
  /// Used under the track on narrow screens, where there is width to spare
  /// horizontally and none to spare in the row itself.
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (value == null) return const SizedBox.shrink();
    final content = inline ? _buildInline() : _buildStacked();
    if (tooltip == null) return content;
    return Tooltip(
      message: tooltip!,
      triggerMode: TooltipTriggerMode.tap,
      child: content,
    );
  }

  /// Value and name on one line, right-aligned under the track.
  Widget _buildInline() {
    return Padding(
      padding: const EdgeInsets.only(top: 1, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            value!,
            style: const TextStyle(
              color: Colors.orange,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Value over name, in a fixed column beside the track.
  Widget _buildStacked() {
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value!,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.orange,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        // Shrunk to fit rather than clipped: the longest names are the
        // compound ones ("Major 2nd +1 oct"), and an ellipsis there hides
        // the octave — the very part that says which one it is.
        if (detail != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              detail!,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                height: 1.1,
              ),
            ),
          ),
      ],
    );

    // A fixed width so the track does not shift every time the value crosses
    // a digit or lands on a longer interval name.
    return SizedBox(width: width, child: column);
  }
}

// ── Track painting ───────────────────────────────────────────────────────────

/// Draws the semitone ruler, the root marker, the travel from root to the
/// current interval, and the handle.
class _IntervalTrackPainter extends CustomPainter {
  _IntervalTrackPainter({
    required this.value,
    required this.min,
    required this.max,
  });

  final double value;
  final double min;
  final double max;

  /// Horizontal position of [semitones] on the track.
  double _x(double semitones, double width) =>
      ((semitones - min) / (max - min)) * width;

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final rootX = _x(0, size.width).clamp(0.0, size.width);
    final handleX = _x(value, size.width).clamp(0.0, size.width);

    // Groove the handle runs in.
    final groove = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(2, midY), Offset(size.width - 2, midY), groove);

    // Semitone ticks, drawn only when there is room for them to read as
    // separate marks rather than a grey smear.
    final semitoneSpacing = size.width / (max - min);
    if (semitoneSpacing >= 5) {
      final tick = Paint()..color = Colors.white12;
      for (var s = min; s <= max; s += 1) {
        final x = _x(s, size.width);
        canvas.drawRect(Rect.fromLTWH(x - 0.5, midY - 3, 1, 6), tick);
      }
    }

    // Octave ticks — the landmarks that make a position readable.
    final octaveTick = Paint()..color = Colors.white24;
    for (var s = (min / 12).ceil() * 12; s <= max; s += 12) {
      final x = _x(s.toDouble(), size.width);
      canvas.drawRect(Rect.fromLTWH(x - 0.5, midY - 8, 1, 16), octaveTick);
    }

    // Root line: where the played note itself sits.
    final root = Paint()..color = Colors.white54;
    canvas.drawRect(Rect.fromLTWH(rootX - 1, midY - 10, 2, 20), root);

    // Travel from the root to the handle, so distance and direction are
    // visible without reading the number.
    final travel = Paint()
      ..color = Colors.orange.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    if ((handleX - rootX).abs() > 0.5) {
      canvas.drawLine(Offset(rootX, midY), Offset(handleX, midY), travel);
    }

    // Handle.
    canvas.drawCircle(
      Offset(handleX, midY),
      7,
      Paint()..color = const Color(0xFF2E2E2E),
    );
    canvas.drawCircle(
      Offset(handleX, midY),
      7,
      Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_IntervalTrackPainter old) =>
      old.value != value || old.min != min || old.max != max;
}

// ── Step button ──────────────────────────────────────────────────────────────

/// A small square +/- button that repeats while held.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.onPressed,
    required this.onReleased,
  });

  final IconData icon;

  /// Null disables the button (the voice is not playing).
  final VoidCallback? onPressed;

  /// Called when the press ends, to stop the repeat timer.
  final VoidCallback onReleased;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => onPressed!() : null,
      onTapUp: (_) => onReleased(),
      onTapCancel: onReleased,
      child: Container(
        width: 24,
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: const Color(0xFF1F1F1F),
          border: Border.all(
            color: Colors.orange.withValues(alpha: enabled ? 0.35 : 0.15),
          ),
        ),
        child: Icon(icon, size: 14, color: Colors.white70),
      ),
    );
  }
}
