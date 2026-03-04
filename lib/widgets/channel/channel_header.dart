import 'package:flutter/material.dart';

/// A simple header row for the [ChannelCard].
///
/// Displays the channel number (1-indexed for the user) and a flashing
/// status indicator when MIDI notes are currently active on this channel.
class ChannelHeader extends StatelessWidget {
  final int channelIndex;
  final bool isFlashing;

  const ChannelHeader({
    super.key,
    required this.channelIndex,
    required this.isFlashing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'CH ${channelIndex + 1}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.blueAccent,
          ),
        ),
        Row(
          children: [
            // Visual indicator that flashes green when [isFlashing] is true,
            // typically driven by the activeNotes list in ChannelState.
            if (isFlashing)
              const Icon(Icons.circle, color: Colors.greenAccent, size: 12),
            const SizedBox(width: 8),
            const Icon(Icons.piano, color: Colors.grey, size: 20),
          ],
        ),
      ],
    );
  }
}
