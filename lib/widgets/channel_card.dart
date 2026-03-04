import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/widgets/virtual_piano.dart';
import 'package:grooveforge/models/chord_detector.dart';

import 'channel/channel_header.dart';
import 'channel/channel_patch_info.dart';

/// Represents a single MIDI channel's complete user interface within the synthesizer.
///
/// **Composition:**
/// - [ChannelHeader]: Displays the channel number and volume/pan controls.
/// - [ChannelPatchInfo]: Displays the assigned soundfont, patch name, and active scale/chord information.
/// - [VirtualPiano]: The interactive keyboard surface for playing notes on this channel.
///
/// **Reactivity:**
/// The card uses multiple [ListenableBuilder] and [ValueListenableBuilder] widgets to selectively
/// rebuild only the necessary UI components when underlying [AudioEngine] state changes
/// (e.g., active notes flashing the border, Jam Mode toggles updating the scale display),
/// ensuring high performance even during rapid MIDI playback.
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
    // Retrieve the audio engine and the specific state for this MIDI channel
    final engine = context.read<AudioEngine>();
    final state = engine.channels[channelIndex];

    return SizedBox(
      height: itemHeight,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2.0),
        child: ValueListenableBuilder<Set<int>>(
          // Listen to active notes to trigger a visual flashing effect when notes are played
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
                    // Display the header (Channel number, volume, etc.)
                    ChannelHeader(
                      channelIndex: channelIndex,
                      isFlashing: isFlashing,
                    ),
                    const SizedBox(height: 2),

                    // Combine listeners to update the ChannelPatchInfo UI reactively.
                    // This listens to global Jam settings AND channel-specific state (locking, current chord).
                    // Crucially, if this channel is NOT the Jam Master, we must ALSO listen to
                    // the Master channel's lastChord to reactively display the Master's chord locally.
                    ListenableBuilder(
                      listenable: Listenable.merge([
                        engine.lockModePreference,
                        engine.jamEnabled,
                        engine.jamMasterChannel,
                        engine.jamSlaveChannels,
                        engine.jamScaleType,
                        engine.stateNotifier,
                        state.lastChord,
                        state.isScaleLocked,
                        state.currentScaleType,
                        if (channelIndex != engine.jamMasterChannel.value &&
                            engine.jamMasterChannel.value >= 0 &&
                            engine.jamMasterChannel.value <
                                engine.channels.length)
                          engine
                              .channels[engine.jamMasterChannel.value]
                              .lastChord,
                      ]),
                      builder: (context, _) {
                        final lockMode = engine.lockModePreference.value;
                        final jamEnabled = engine.jamEnabled.value;
                        final masterCh = engine.jamMasterChannel.value;
                        final slaves = engine.jamSlaveChannels.value;
                        final jamScale = engine.jamScaleType.value;
                        final lastChord = state.lastChord.value;
                        final isLocked = state.isScaleLocked.value;
                        final currentScale = state.currentScaleType.value;

                        // Determine Jam Mode roles for this specific channel.
                        // Master: Defines the scale/chord that Slaves will follow.
                        // Slave: Adopts the Master's scale/chord constraints.
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

                        // Effective UI values
                        final ownChord = lastChord;
                        final showOwnChord =
                            isMaster || !isSlave || activeNotes.isNotEmpty;
                        final refChord =
                            (isSlave && masterCh >= 0)
                                ? engine.channels[masterCh].lastChord.value
                                : ownChord;
                        final scaleToDisplay =
                            isSlave ? jamScale : currentScale;
                        String descriptiveName = engine.getDescriptiveScaleName(
                          refChord,
                          scaleToDisplay,
                        );

                        // Construct a composite chord object for display.
                        // If this is a Slave, we force the display to show the Master's chord root
                        // combined with the current global Jam scale descriptor.
                        final chordToDisplay =
                            (showOwnChord || isSlave)
                                ? (isSlave && refChord != null
                                    ? ChordMatch(
                                      '${refChord.name.split(' ')[0]} $descriptiveName',
                                      refChord.scalePitchClasses,
                                      refChord.rootPc,
                                      refChord.isMinor,
                                    )
                                    : ownChord)
                                : null;

                        final lockToDisplay =
                            isSlave ||
                            (lockMode == ScaleLockMode.classic && isLocked);

                        // Dim the card if it's inactive (no notes, not locked, not master)
                        // This helps focus attention on active or locked channels
                        bool isDimmed =
                            activeNotes.isEmpty && !lockToDisplay && !isMaster;

                        return ChannelPatchInfo(
                          engine: engine,
                          channelIndex: channelIndex,
                          isDimmed: isDimmed,
                          isLocked: lockToDisplay,
                          displayChord: chordToDisplay,
                          referenceChord: refChord,
                          currentScale: scaleToDisplay,
                          descriptiveScaleName: descriptiveName,
                          isJamSlave: isSlave,
                          showLockControls: shouldShowLockUI,
                          onLockToggled:
                              (lockMode == ScaleLockMode.jam)
                                  ? null
                                  : () {
                                    state.isScaleLocked.value =
                                        !state.isScaleLocked.value;
                                  },
                          onScaleChanged: (ScaleType? newValue) {
                            if (newValue != null && !isSlave) {
                              state.currentScaleType.value = newValue;
                            }
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
                        child: ListenableBuilder(
                          listenable: Listenable.merge([
                            engine.stateNotifier,
                            engine.pianoKeysToShow,
                            engine.verticalGestureAction,
                            engine.horizontalGestureAction,
                            state.validPitchClasses,
                            engine.jamEnabled,
                            engine.lockModePreference,
                            engine.jamSlaveChannels,
                            engine.jamMasterChannel,
                            if (engine.jamMasterChannel.value >= 0 &&
                                engine.jamMasterChannel.value <
                                    engine.channels.length)
                              engine
                                  .channels[engine.jamMasterChannel.value]
                                  .lastChord,
                          ]),
                          builder: (context, _) {
                            final keysToShow = engine.pianoKeysToShow.value;
                            final vAction = engine.verticalGestureAction.value;
                            final hAction =
                                engine.horizontalGestureAction.value;
                            final validPcs = state.validPitchClasses.value;

                            // Calculate root for labeling
                            int? rootPc;
                            // Re-check jam status for the piano builder
                            final jamEnabled = engine.jamEnabled.value;
                            final lockMode = engine.lockModePreference.value;
                            final slaves = engine.jamSlaveChannels.value;
                            final isSlave =
                                lockMode == ScaleLockMode.jam &&
                                jamEnabled &&
                                slaves.contains(channelIndex);

                            if (isSlave) {
                              // By grabbing the Master's active chord, the VirtualPiano
                              // can visually reflect the current tonal center.
                              final masterCh = engine.jamMasterChannel.value;
                              if (masterCh >= 0 &&
                                  masterCh < engine.channels.length) {
                                final masterChord =
                                    engine.channels[masterCh].lastChord.value;
                                if (masterChord != null) {
                                  rootPc = masterChord.rootPc;
                                }
                              }
                            }

                            return VirtualPiano(
                              activeNotes: activeNotes,
                              verticalAction: vAction,
                              horizontalAction: hAction,
                              keysToShow: keysToShow,
                              validPitchClasses: isSlave ? validPcs : null,
                              rootPitchClass: isSlave ? rootPc : null,
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
                              onPitchBend:
                                  (val) => engine.setPitchBend(
                                    channel: channelIndex,
                                    value: val,
                                  ),
                              onControlChange:
                                  (cc, val) => engine.setControlChange(
                                    channel: channelIndex,
                                    controller: cc,
                                    value: val,
                                  ),
                              onInteractingChanged: engine.updateGestureState,
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
