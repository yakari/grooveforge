import 'package:flutter/material.dart';

/// A compact segmented selector for discrete parameter options.
///
/// Used for parameters like LFO waveform (Sine / Tri / Saw), beat division
/// (1/4 / 1/8 / 1/16), or filter mode (LP / HP / BP).
///
/// Each option is a small tappable segment. The active segment glows orange;
/// inactive ones use a dark metal appearance consistent with the knob palette.
///
/// [selectedIndex] is the integer index of the currently-selected option.
/// [onChanged] is called with the new index when the user taps a segment.
class GFOptionSelector extends StatelessWidget {
  const GFOptionSelector({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
    required this.label,
    this.maxWidth = 120.0,
    this.segmentHeight = 22.0,
  });

  /// Display labels for each option (e.g. `["Sine", "Tri", "Saw"]`).
  final List<String> options;

  /// Index of the currently active option.
  final int selectedIndex;

  /// Called with the new index when a segment is tapped.
  final ValueChanged<int> onChanged;

  /// Label shown below the selector.
  final String label;

  /// Maximum total width of the selector. Segments are divided equally.
  final double maxWidth;

  /// Height of each segment button.
  final double segmentHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: IntrinsicWidth(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(options.length, (i) {
                  final isFirst = i == 0;
                  final isLast = i == options.length - 1;
                  final isActive = i == selectedIndex;

                  return Flexible(
                    child: GestureDetector(
                      onTap: () => onChanged(i),
                      child: _Segment(
                        label: options[i],
                        isActive: isActive,
                        isFirst: isFirst,
                        isLast: isLast,
                        height: segmentHeight,
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
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

/// A single segment inside [GFOptionSelector].
class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isActive,
    required this.isFirst,
    required this.isLast,
    required this.height,
  });

  final String label;
  final bool isActive;
  final bool isFirst;
  final bool isLast;
  final double height;

  @override
  Widget build(BuildContext context) {
    // Compute border radius: only round the outer corners of the first/last.
    final borderRadius = BorderRadius.only(
      topLeft: isFirst ? const Radius.circular(5) : Radius.zero,
      bottomLeft: isFirst ? const Radius.circular(5) : Radius.zero,
      topRight: isLast ? const Radius.circular(5) : Radius.zero,
      bottomRight: isLast ? const Radius.circular(5) : Radius.zero,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: isActive
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.orange.withValues(alpha: 0.85),
                  Colors.orange.shade900.withValues(alpha: 0.9),
                ],
              )
            : const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF2E2E2E), Color(0xFF1E1E1E)],
              ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : Colors.white38,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }
}
