import 'package:flutter/material.dart';

import 'package:grooveforge/models/chord_detector.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'channel_scale_lock.dart';

class ChannelPatchInfo extends StatelessWidget {
  final String sfName;
  final String patchName;
  final int program;
  final int bank;
  final bool isDimmed;
  final bool isLocked;
  final ChordMatch? lastChord;
  final ScaleType currentScale;
  final VoidCallback onLockToggled;
  final ValueChanged<ScaleType?> onScaleChanged;

  const ChannelPatchInfo({
    super.key,
    required this.sfName,
    required this.patchName,
    required this.program,
    required this.bank,
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sfName, 
                style: const TextStyle(color: Colors.white70, fontSize: 14), 
                maxLines: 1, 
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      patchName, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white), 
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (lastChord != null)
                    ChannelScaleLock(
                      isDimmed: isDimmed,
                      isLocked: isLocked,
                      lastChord: lastChord!,
                      currentScale: currentScale,
                      onLockToggled: onLockToggled,
                      onScaleChanged: onScaleChanged,
                    ),
                ],
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Prog: $program', style: const TextStyle(fontSize: 14)),
            Text('Bank: $bank', style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ],
        ),
      ],
    );
  }
}
