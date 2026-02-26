import 'package:flutter/material.dart';
import 'package:grooveforge/models/chord_detector.dart';
import 'package:grooveforge/services/audio_engine.dart';

class ChannelScaleLock extends StatelessWidget {
  final bool isDimmed;
  final bool isLocked;
  final ChordMatch lastChord;
  final ScaleType currentScale;
  final VoidCallback onLockToggled;
  final ValueChanged<ScaleType?> onScaleChanged;

  const ChannelScaleLock({
    super.key,
    required this.isDimmed,
    required this.isLocked,
    required this.lastChord,
    required this.currentScale,
    required this.onLockToggled,
    required this.onScaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onLockToggled,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isLocked 
                ? Colors.redAccent.withValues(alpha: 0.9) 
                : Colors.amber.withValues(alpha: isDimmed ? 0.3 : 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  lastChord.name,
                  style: TextStyle(
                    color: isLocked ? Colors.white : Colors.black, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 14,
                  ),
                ),
                if (isLocked) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.lock, size: 14, color: Colors.white),
                ]
              ],
            ),
          ),
        ),
        if (isLocked) ...[
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<ScaleType>(
              value: currentScale,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white, fontSize: 12),
              onChanged: onScaleChanged,
              items: ScaleType.values.map<DropdownMenuItem<ScaleType>>((ScaleType value) {
                return DropdownMenuItem<ScaleType>(
                  value: value,
                  child: Text(value.name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => ' ${m.group(0)}').toUpperCase()),
                );
              }).toList(),
            ),
          ),
        ]
      ],
    );
  }
}
