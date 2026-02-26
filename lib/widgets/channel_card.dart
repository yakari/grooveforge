import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/models/gm_instruments.dart';
import 'package:grooveforge/widgets/virtual_piano.dart';
import 'package:grooveforge/models/chord_detector.dart';

import 'channel/channel_header.dart';
import 'channel/channel_patch_info.dart';

class ChannelCard extends StatelessWidget {
  final int channelIndex;
  final double itemHeight;
  final VoidCallback onConfigTapped;

  const ChannelCard({
    super.key,
    required this.channelIndex,
    required this.itemHeight,
    required this.onConfigTapped,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    final state = engine.channels[channelIndex];
    String sfName = state.soundfontPath?.split(Platform.pathSeparator).last ?? 'No Soundfont';
    String patchName = engine.getCustomPatchName(channelIndex) ?? GmInstruments.list[state.program] ?? 'Unknown Patch';

    return SizedBox(
      height: itemHeight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16.0),
        child: ValueListenableBuilder<Set<int>>(
          valueListenable: state.activeNotes,
          builder: (context, activeNotes, _) {
            bool isFlashing = activeNotes.isNotEmpty;
            
            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: isFlashing ? Colors.blueAccent.withValues(alpha: 0.2) : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFlashing ? Colors.blueAccent : Colors.transparent,
                  width: 2,
                ),
                boxShadow: [
                  if (isFlashing)
                      BoxShadow(color: Colors.blueAccent.withValues(alpha: 0.3), blurRadius: 10, spreadRadius: 2)
                ]
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onConfigTapped,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ChannelHeader(
                        channelIndex: channelIndex,
                        isFlashing: isFlashing,
                      ),
                      const SizedBox(height: 12),
                      
                      // Combine listeners to update UI on notes, last chord, or lock toggle
                      ValueListenableBuilder<ChordMatch?>(
                        valueListenable: state.lastChord,
                        builder: (context, lastChord, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: state.isScaleLocked,
                            builder: (context, isLocked, _) {
                              return ValueListenableBuilder<ScaleType>(
                                valueListenable: state.currentScaleType,
                                builder: (context, currentScale, _) {
                                  bool isDimmed = activeNotes.isEmpty && !isLocked;
                                  return ChannelPatchInfo(
                                    sfName: sfName,
                                    patchName: patchName,
                                    program: state.program,
                                    bank: state.bank,
                                    isDimmed: isDimmed,
                                    isLocked: isLocked,
                                    lastChord: lastChord,
                                    currentScale: currentScale,
                                    onLockToggled: () => state.isScaleLocked.value = !state.isScaleLocked.value,
                                    onScaleChanged: (ScaleType? newValue) {
                                      if (newValue != null) {
                                        state.currentScaleType.value = newValue;
                                      }
                                    },
                                  );
                                }
                              );
                            }
                          );
                        }
                      ),

                      const SizedBox(height: 16),
                      // Native Live Virtual Piano
                      Expanded(
                        child: GestureDetector(
                          onTap: () {}, // Swallow taps so they don't trigger the InkWell
                          child: ValueListenableBuilder<bool>(
                            valueListenable: engine.dragToPlay,
                            builder: (context, dragToPlay, _) {
                              return VirtualPiano(
                                activeNotes: activeNotes,
                                dragToPlay: dragToPlay,
                                onNotePressed: (note) => engine.playNote(channel: channelIndex, key: note, velocity: 100),
                                onNoteReleased: (note) => engine.stopNote(channel: channelIndex, key: note),
                              );
                            }
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
