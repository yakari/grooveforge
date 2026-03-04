import 'package:flutter/material.dart';
import 'package:grooveforge/models/chord_detector.dart';
import 'package:grooveforge/services/audio_engine.dart';

/// A widget that displays and controls the scale locking mechanism for a specific channel.
///
/// This widget shows the currently active chord and allows the user to lock the
/// channel to a specific scale. It visually differentiates between various modes:
/// - **Unlocked**: Displays the current chord (if any) with an amber background.
/// - **Locked (Classic)**: Displays the locked scale with a red background and a lock icon,
///   along with a dropdown to select the specific scale type.
/// - **Jam Mode Slave**: Displays the master's scale with a blue background and a link icon,
///   indicating that this channel's scale is synchronized with the master channel.
/// - **Dimmed**: Reduces opacity when the channel is inactive to reduce visual clutter.
class ChannelScaleLock extends StatelessWidget {
  final AudioEngine engine;
  final bool isDimmed;
  final bool isLocked;
  final ChordMatch? displayChord;
  final ChordMatch? referenceChord;
  final ScaleType currentScale;
  final String? descriptiveScaleName;
  final bool isJamSlave;
  final bool showLockControls;
  final VoidCallback? onLockToggled;
  final ValueChanged<ScaleType?> onScaleChanged;

  const ChannelScaleLock({
    super.key,
    required this.engine,
    required this.isDimmed,
    required this.isLocked,
    this.displayChord,
    this.referenceChord,
    required this.currentScale,
    this.descriptiveScaleName,
    required this.isJamSlave,
    required this.showLockControls,
    this.onLockToggled,
    required this.onScaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (displayChord != null)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: (isJamSlave || !showLockControls) ? null : onLockToggled,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                // The background color intuitively communicates the Jam/Lock state:
                // - Blue: Slave mode (locked to external Master)
                // - Red: Classic locked (locked to own specific scale)
                // - Amber: Unlocked but identifying a chord
                // - Grey: Disabled/Cannot lock
                color:
                    isJamSlave
                        ? Colors.blueAccent.withValues(alpha: 0.9)
                        : (!showLockControls
                            ? Colors.grey.withValues(alpha: 0.4)
                            : (isLocked
                                ? Colors.redAccent.withValues(alpha: 0.9)
                                : Colors.amber.withValues(
                                  alpha: isDimmed ? 0.3 : 0.8,
                                ))),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayChord!.name,
                    style: TextStyle(
                      color:
                          (isLocked || isJamSlave || !showLockControls)
                              ? Colors.white
                              : Colors.black,
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
        // Only show the scale selection dropdown if we are allowed to lock,
        // and we are actually locked in classic mode (not enslaved to Jam Master,
        // since the Master controls the scale for slaves).
        if (showLockControls && (isLocked && !isJamSlave)) ...[
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
                        engine.getDescriptiveScaleName(referenceChord, value),
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
