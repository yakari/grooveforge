import 'package:flutter/material.dart';
import 'package:grooveforge/models/chord_detector.dart';
import 'package:grooveforge/services/audio_engine.dart';

class ChannelScaleLock extends StatelessWidget {
  final AudioEngine engine;
  final bool isDimmed;
  final bool isLocked;
  final ChordMatch lastChord;
  final ScaleType currentScale;
  final String? descriptiveScaleName;
  final bool isJamSlave;
  final VoidCallback onLockToggled;
  final ValueChanged<ScaleType?> onScaleChanged;

  const ChannelScaleLock({
    super.key,
    required this.engine,
    required this.isDimmed,
    required this.isLocked,
    required this.lastChord,
    required this.currentScale,
    this.descriptiveScaleName,
    required this.isJamSlave,
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
          onTap: isJamSlave ? null : onLockToggled,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color:
                  isJamSlave
                      ? Colors.blueAccent.withValues(alpha: 0.9)
                      : (isLocked
                          ? Colors.redAccent.withValues(alpha: 0.9)
                          : Colors.amber.withValues(
                            alpha: isDimmed ? 0.3 : 0.8,
                          )),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isJamSlave ? 'JAM: ${lastChord.name}' : lastChord.name,
                  style: TextStyle(
                    color:
                        (isLocked || isJamSlave) ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (isLocked || isJamSlave) ...[
                  const SizedBox(width: 4),
                  Icon(
                    isJamSlave ? Icons.link : Icons.lock,
                    size: 14,
                    color: Colors.white,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (isLocked || isJamSlave) ...[
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<ScaleType>(
              value: currentScale,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
              dropdownColor: Colors.grey[850],
              style: const TextStyle(color: Colors.white, fontSize: 12),
              onChanged: isJamSlave ? null : onScaleChanged,
              items:
                  ScaleType.values.map<DropdownMenuItem<ScaleType>>((
                    ScaleType value,
                  ) {
                    return DropdownMenuItem<ScaleType>(
                      value: value,
                      child: Text(
                        engine.getDescriptiveScaleName(lastChord, value),
                        style: TextStyle(
                          color: isJamSlave ? Colors.white54 : Colors.white,
                        ),
                      ),
                    );
                  }).toList(),
            ),
          ),
        ],
      ],
    );
  }
}
