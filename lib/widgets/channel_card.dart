import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/widgets/virtual_piano.dart';
import 'package:grooveforge/models/chord_detector.dart';

import 'channel/channel_header.dart';
import 'channel/channel_patch_info.dart';

class ChannelCard extends StatelessWidget {
  final int channelIndex;
  final double itemHeight;
  const ChannelCard({
    super.key,
    required this.channelIndex,
    required this.itemHeight,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    final state = engine.channels[channelIndex];

    return SizedBox(
      height: itemHeight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2.0),
        child: ValueListenableBuilder<Set<int>>(
          valueListenable: state.activeNotes,
          builder: (context, activeNotes, _) {
            bool isFlashing = activeNotes.isNotEmpty;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color:
                    isFlashing
                        ? Colors.blueAccent.withValues(alpha: 0.2)
                        : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isFlashing ? Colors.blueAccent : Colors.transparent,
                  width: 2,
                ),
                boxShadow: [
                  if (isFlashing)
                    BoxShadow(
                      color: Colors.blueAccent.withValues(alpha: 0.3),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ChannelHeader(
                      channelIndex: channelIndex,
                      isFlashing: isFlashing,
                    ),
                    const SizedBox(height: 2),

                    // Combine listeners to update UI on notes, last chord, or lock toggle
                    ValueListenableBuilder<ScaleLockMode>(
                      valueListenable: engine.lockModePreference,
                      builder: (context, lockMode, _) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: engine.jamEnabled,
                          builder: (context, jamEnabled, _) {
                            return ValueListenableBuilder<int>(
                              valueListenable: engine.jamMasterChannel,
                              builder: (context, masterCh, _) {
                                return ValueListenableBuilder<Set<int>>(
                                  valueListenable: engine.jamSlaveChannels,
                                  builder: (context, slaves, _) {
                                    return ValueListenableBuilder<ScaleType>(
                                      valueListenable: engine.jamScaleType,
                                      builder: (context, jamScale, _) {
                                        // Jam mode logic
                                        bool isMaster =
                                            lockMode == ScaleLockMode.jam &&
                                            channelIndex == masterCh;
                                        bool isSlave =
                                            lockMode == ScaleLockMode.jam &&
                                            jamEnabled &&
                                            slaves.contains(channelIndex);

                                        // If Jam Mode is chosen, we ONLY show lock UI for Master or Slave
                                        bool shouldShowLockUI =
                                            lockMode == ScaleLockMode.classic ||
                                            isMaster ||
                                            isSlave;

                                        if (!shouldShowLockUI) {
                                          return const SizedBox.shrink();
                                        }

                                        // Choose whose state to listen to
                                        final listenState =
                                            isSlave
                                                ? engine.channels[masterCh]
                                                : state;

                                        return ValueListenableBuilder<
                                          ChordMatch?
                                        >(
                                          valueListenable:
                                              listenState.lastChord,
                                          builder: (context, lastChord, _) {
                                            if (lastChord == null) {
                                              return const SizedBox.shrink();
                                            }

                                            return ValueListenableBuilder<bool>(
                                              valueListenable:
                                                  state.isScaleLocked,
                                              builder: (context, isLocked, _) {
                                                return ValueListenableBuilder<
                                                  ScaleType
                                                >(
                                                  valueListenable:
                                                      state.currentScaleType,
                                                  builder: (
                                                    context,
                                                    currentScale,
                                                    _,
                                                  ) {
                                                    // Effective UI values
                                                    final chordToDisplay =
                                                        lastChord;
                                                    final scaleToDisplay =
                                                        isSlave
                                                            ? jamScale
                                                            : currentScale;
                                                    final descriptiveName = engine
                                                        .getDescriptiveScaleName(
                                                          chordToDisplay,
                                                          scaleToDisplay,
                                                        );
                                                    final lockToDisplay =
                                                        isSlave ||
                                                        (lockMode ==
                                                                ScaleLockMode
                                                                    .classic &&
                                                            isLocked);

                                                    // Highlight for Jam Master (Yellow/Green) or Slave (Blue)
                                                    bool isDimmed =
                                                        activeNotes.isEmpty &&
                                                        !lockToDisplay &&
                                                        !isMaster;

                                                    return ChannelPatchInfo(
                                                      engine: engine,
                                                      channelIndex:
                                                          channelIndex,
                                                      isDimmed: isDimmed,
                                                      isLocked: lockToDisplay,
                                                      lastChord: chordToDisplay,
                                                      currentScale:
                                                          scaleToDisplay,
                                                      descriptiveScaleName:
                                                          descriptiveName,
                                                      isJamSlave: isSlave,
                                                      onLockToggled: () {
                                                        state
                                                            .isScaleLocked
                                                            .value = !state
                                                                .isScaleLocked
                                                                .value;
                                                      },
                                                      onScaleChanged: (
                                                        ScaleType? newValue,
                                                      ) {
                                                        if (newValue != null &&
                                                            !isSlave) {
                                                          state
                                                              .currentScaleType
                                                              .value = newValue;
                                                        }
                                                      },
                                                    );
                                                  },
                                                );
                                              },
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 2),
                    // Native Live Virtual Piano
                    Expanded(
                      child: GestureDetector(
                        onTap:
                            () {}, // Swallow taps so they don't trigger anything underneath
                        child: ValueListenableBuilder<bool>(
                          valueListenable: engine.dragToPlay,
                          builder: (context, dragToPlay, _) {
                            return ValueListenableBuilder<int>(
                              valueListenable: engine.pianoKeysToShow,
                              builder: (context, keysToShow, _) {
                                return VirtualPiano(
                                  activeNotes: activeNotes,
                                  dragToPlay: dragToPlay,
                                  keysToShow: keysToShow,
                                  onNotePressed:
                                      (note) => engine.playNote(
                                        channel: channelIndex,
                                        key: note,
                                        velocity: 100,
                                      ),
                                  onNoteReleased:
                                      (note) => engine.stopNote(
                                        channel: channelIndex,
                                        key: note,
                                      ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
