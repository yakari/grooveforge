import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/chord_detector.dart';
import '../../models/grooveforge_keyboard_plugin.dart';
import '../../services/audio_engine.dart';
import '../../services/rack_state.dart';
import '../channel/channel_patch_info.dart';

/// The inner body of a rack slot for a [GrooveForgeKeyboardPlugin].
///
/// Reuses the existing [ChannelPatchInfo] (soundfont/bank/patch + vocoder)
/// widget, bridging the per-slot plugin model to [AudioEngine]'s
/// channel-indexed API.
///
/// Jam Mode display: when this slot is configured as a Jam follower
/// ([GrooveForgeKeyboardPlugin.jamEnabled] is true and a master is set), this
/// widget shows the master slot's chord and scale context instead of its own.
class GrooveForgeKeyboardSlotUI extends StatelessWidget {
  final GrooveForgeKeyboardPlugin plugin;

  const GrooveForgeKeyboardSlotUI({super.key, required this.plugin});

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    final rack = context.read<RackState>();
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
        engine.jamFollowerMap,
        engine.jamScaleType,
        engine.stateNotifier,
        state.lastChord,
        state.isScaleLocked,
        state.currentScaleType,
        state.activeNotes,
        // Listen to all channels' chords so the follower updates when the
        // master plays, without needing a dynamic listener.
        ...engine.channels.map((ch) => ch.lastChord),
      ]),
      builder: (context, _) {
        final lockMode = engine.lockModePreference.value;
        final followerMap = engine.jamFollowerMap.value;
        final isFollower =
            engine.jamEnabled.value && followerMap.containsKey(channelIndex);

        final masterCh = isFollower ? followerMap[channelIndex]! : -1;
        final jamScale = engine.jamScaleType.value;
        final lastChord = state.lastChord.value;
        final isLocked = state.isScaleLocked.value;
        final currentScale = state.currentScaleType.value;

        final refChord = (isFollower && masterCh >= 0)
            ? engine.channels[masterCh].lastChord.value
            : lastChord;
        final scaleToDisplay = isFollower ? jamScale : currentScale;
        final descriptiveName = engine.getDescriptiveScaleName(
          refChord,
          scaleToDisplay,
        );

        final activeNotes = state.activeNotes.value;

        final chordToDisplay = isFollower && refChord != null
            ? ChordMatch(
                '${refChord.name.split(' ')[0]} $descriptiveName',
                refChord.scalePitchClasses,
                refChord.rootPc,
                refChord.isMinor,
              )
            : lastChord;

        final lockToDisplay =
            isFollower || (lockMode == ScaleLockMode.classic && isLocked);

        final shouldShowLockUI = lockMode == ScaleLockMode.classic || isFollower;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ChannelPatchInfo(
            engine: engine,
            channelIndex: channelIndex,
            onPatchChanged: (program, bank) =>
                rack.setPluginPatch(plugin.id, program, bank: bank),
            onSoundfontChanged: (sf) =>
                rack.setPluginSoundfont(plugin.id, sf),
            isDimmed: activeNotes.isEmpty && !lockToDisplay,
            isLocked: lockToDisplay,
            displayChord: chordToDisplay,
            referenceChord: refChord,
            currentScale: scaleToDisplay,
            descriptiveScaleName: descriptiveName,
            isJamSlave: isFollower,
            showLockControls: shouldShowLockUI,
            onLockToggled: lockMode == ScaleLockMode.jam
                ? null
                : () {
                    state.isScaleLocked.value = !state.isScaleLocked.value;
                  },
            onScaleChanged: (ScaleType? newValue) {
              if (newValue != null && !isFollower) {
                state.currentScaleType.value = newValue;
              }
            },
          ),
        );
      },
    );
  }
}
