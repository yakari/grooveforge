import 'package:flutter/material.dart';

/// A compact dropdown control for discrete parameters with many options (> 5).
///
/// Displays the currently selected option name in a styled button that matches
/// the dark-metal plugin panel aesthetic. Tapping opens a scrollable popup menu
/// anchored below the button, showing all available options.
///
/// Use [GFOptionSelector] for small option sets (≤ 5 items) where a segmented
/// row fits comfortably. Use this widget when the option count would make
/// individual segments too narrow to read.
///
/// [selectedIndex] is the 0-based index of the current selection.
/// [onChanged] is called with the new index when the user picks an option.
class GFDropdownSelector extends StatelessWidget {
  const GFDropdownSelector({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onChanged,
    required this.label,
  });

  /// Display labels for all available options.
  final List<String> options;

  /// Index of the currently selected option.
  final int selectedIndex;

  /// Called with the new index when the user selects an option from the menu.
  final ValueChanged<int> onChanged;

  /// Label shown below the button (parameter name).
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Button showing the current selection — taps open the popup menu.
        GestureDetector(
          onTapUp: (details) => _showMenu(context),
          child: Container(
            height: 28,
            constraints: const BoxConstraints(minWidth: 72),
            padding: const EdgeInsets.symmetric(horizontal: 8),
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
              children: [
                // Current selection label — bold and fully visible.
                Text(
                  options[selectedIndex.clamp(0, options.length - 1)],
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(width: 4),
                // Chevron indicating this is a dropdown.
                Icon(
                  Icons.arrow_drop_down,
                  color: Colors.orange.withValues(alpha: 0.8),
                  size: 16,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        // Parameter name below the button, matching the knob/selector style.
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

  /// Opens a Material popup menu anchored to the button's position.
  void _showMenu(BuildContext context) {
    // Compute the button's screen position so the menu appears below it.
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final overlay =
        Navigator.of(context).overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight =
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );

    showMenu<int>(
      context: context,
      position: position,
      // Constrains the popup height so it scrolls when all options don't fit.
      constraints: const BoxConstraints(maxHeight: 280),
      color: const Color(0xFF222222),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: Colors.orange.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      items: List.generate(options.length, (i) {
        final isSelected = i == selectedIndex;
        return PopupMenuItem<int>(
          value: i,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            options[i],
            style: TextStyle(
              color: isSelected ? Colors.orange : Colors.white70,
              fontSize: 12,
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );
      }),
    ).then((value) {
      if (value != null) onChanged(value);
    });
  }
}
