import 'dart:math' show min;

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
        engine.gfpaJamEntries,
        engine.stateNotifier,
        state.lastChord,
        state.isScaleLocked,
        state.currentScaleType,
        state.activeNotes,
        // Listen to all channels so follower updates when master plays.
        ...engine.channels.map((ch) => ch.lastChord),
        ...engine.channels.map((ch) => ch.activeNotes),
      ]),
      builder: (context, _) {
        // GFPA Jam follower detection
        final gfpaEntry = engine.gfpaJamEntries.value
            .where((e) => e.followerCh == channelIndex)
            .firstOrNull;
        final isFollower = gfpaEntry != null;

        final lastChord = state.lastChord.value;
        final isLocked = state.isScaleLocked.value;
        final currentScale = state.currentScaleType.value;

        // Determine master channel + scale type for this follower
        final int masterChIdx;
        final ScaleType scaleToDisplay;
        if (gfpaEntry != null) {
          masterChIdx = gfpaEntry.masterCh;
          scaleToDisplay = gfpaEntry.scaleType;
        } else {
          masterChIdx = -1;
          scaleToDisplay = currentScale;
        }

        // Reference chord: from master (chord mode) or synthesised from bass
        // note (bass note mode), falling back to own chord when standalone.
        ChordMatch? refChord;
        if (gfpaEntry != null) {
          if (gfpaEntry.bassNoteMode) {
            final active = engine.channels[masterChIdx].activeNotes.value;
            if (active.isNotEmpty) {
              final rootPc = active.reduce(min) % 12;
              // Synthetic chord so the scale name carries the root note.
              refChord = ChordMatch(
                  _noteNameFromPc(rootPc), const {}, rootPc, false);
            }
          } else {
            refChord = masterChIdx >= 0
                ? engine.channels[masterChIdx].lastChord.value
                : null;
          }
        } else {
          refChord = lastChord;
        }

        final descriptiveName =
            engine.getDescriptiveScaleName(refChord, scaleToDisplay);
        final activeNotes = state.activeNotes.value;

        final chordToDisplay = isFollower && refChord != null
            ? ChordMatch(
                '${refChord.name.split(' ')[0]} $descriptiveName',
                refChord.scalePitchClasses,
                refChord.rootPc,
                refChord.isMinor,
              )
            : lastChord;

        final lockToDisplay = isFollower || isLocked;

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
            showLockControls: true,
            // GFPA followers: lock is controlled by the Jam rack, not per-channel
            onLockToggled: isFollower
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

/// Maps a MIDI pitch class (0–11) to a display note name.
String _noteNameFromPc(int pc) {
  const names = [
    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'
  ];
  return names[pc % 12];
}
