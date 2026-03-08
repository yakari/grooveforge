import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chord_detector.dart';
import '../../models/grooveforge_keyboard_plugin.dart';
import '../../services/audio_engine.dart';
import '../channel/channel_patch_info.dart';
import '../channel/channel_scale_lock.dart';

/// The inner body of a rack slot for a [GrooveForgeKeyboardPlugin].
///
/// Reuses the existing [ChannelPatchInfo] (soundfont/bank/patch + vocoder)
/// and [ChannelScaleLock] widgets, bridging them from the per-slot plugin
/// model to [AudioEngine]'s channel-indexed API.
class GrooveForgeKeyboardSlotUI extends StatelessWidget {
  final GrooveForgeKeyboardPlugin plugin;

  const GrooveForgeKeyboardSlotUI({super.key, required this.plugin});

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    final channelIndex = plugin.midiChannel - 1;

    if (channelIndex < 0 || channelIndex > 15) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Invalid MIDI channel',
          style: TextStyle(color: Colors.orange),
        ),
      );
    }

    final state = engine.channels[channelIndex];

    return ListenableBuilder(
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
        // Also listen to the master chord so slaves update live.
        if (engine.jamMasterChannel.value >= 0 &&
            engine.jamMasterChannel.value < engine.channels.length)
          engine.channels[engine.jamMasterChannel.value].lastChord,
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

        final isMaster =
            lockMode == ScaleLockMode.jam && channelIndex == masterCh;
        final isSlave =
            lockMode == ScaleLockMode.jam &&
            jamEnabled &&
            slaves.contains(channelIndex);

        final shouldShowLockUI =
            lockMode == ScaleLockMode.classic || isMaster || isSlave;

        final refChord =
            (isSlave && masterCh >= 0)
                ? engine.channels[masterCh].lastChord.value
                : lastChord;
        final scaleToDisplay = isSlave ? jamScale : currentScale;
        final descriptiveName = engine.getDescriptiveScaleName(
          refChord,
          scaleToDisplay,
        );

        final activeNotes = state.activeNotes.value;
        final showOwnChord =
            isMaster || !isSlave || activeNotes.isNotEmpty;

        final chordToDisplay =
            (showOwnChord || isSlave)
                ? (isSlave && refChord != null
                    ? ChordMatch(
                        '${refChord.name.split(' ')[0]} $descriptiveName',
                        refChord.scalePitchClasses,
                        refChord.rootPc,
                        refChord.isMinor,
                      )
                    : lastChord)
                : null;

        final lockToDisplay =
            isSlave || (lockMode == ScaleLockMode.classic && isLocked);

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ChannelPatchInfo(
            engine: engine,
            channelIndex: channelIndex,
            isDimmed: activeNotes.isEmpty && !lockToDisplay && !isMaster,
            isLocked: lockToDisplay,
            displayChord: chordToDisplay,
            referenceChord: refChord,
            currentScale: scaleToDisplay,
            descriptiveScaleName: descriptiveName,
            isJamSlave: isSlave,
            showLockControls: shouldShowLockUI,
            onLockToggled:
                lockMode == ScaleLockMode.jam
                    ? null
                    : () {
                        state.isScaleLocked.value = !state.isScaleLocked.value;
                      },
            onScaleChanged: (ScaleType? newValue) {
              if (newValue != null && !isSlave) {
                state.currentScaleType.value = newValue;
              }
            },
          ),
        );
      },
    );
  }
}
