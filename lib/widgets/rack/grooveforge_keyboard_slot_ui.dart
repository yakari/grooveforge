import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants/soundfont_sentinels.dart';
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
/// ## Rebuild strategy
///
/// Layer 1 (this widget's [ListenableBuilder]) subscribes only to own-channel
/// notifiers and [AudioEngine.gfpaJamEntries].  Cross-channel notifiers are
/// absent: a note on any other channel never triggers a rebuild here.
///
/// When this slot is a GFPA Jam follower, a [_GfkFollowerBody] child (layer 2)
/// is inserted.  It subscribes to exactly one master-channel notifier so that
/// only the master's chord/bass-note updates reach this widget tree.
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
        // Cross-channel notifiers removed: followers subscribe to exactly one
        // master-channel notifier inside _GfkFollowerBody (layer 2) so that
        // notes on unrelated channels cause zero rebuilds in this slot.
      ]),
      builder: (context, _) {
        final gfpaEntry = engine.gfpaJamEntries.value
            .where((e) => e.followerCh == channelIndex)
            .firstOrNull;

        final isLocked = state.isScaleLocked.value;
        final currentScale = state.currentScaleType.value;
        final activeNotes = state.activeNotes.value;

        if (gfpaEntry == null) {
          // Non-follower: all display data comes from this channel alone.
          final lastChord = state.lastChord.value;
          final descriptiveName =
              engine.getDescriptiveScaleName(lastChord, currentScale);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ChannelPatchInfo(
              engine: engine,
              channelIndex: channelIndex,
              hideInstrumentPickers:
                  plugin.soundfontPath == kMidiControllerOnlySoundfont,
              onPatchChanged: (program, bank) =>
                  rack.setPluginPatch(plugin.id, program, bank: bank),
              onSoundfontChanged: (sf) =>
                  rack.setPluginSoundfont(plugin.id, sf),
              isDimmed: activeNotes.isEmpty && !isLocked,
              isLocked: isLocked,
              displayChord: lastChord,
              referenceChord: lastChord,
              currentScale: currentScale,
              descriptiveScaleName: descriptiveName,
              isJamSlave: false,
              showLockControls: true,
              onLockToggled: () {
                state.isScaleLocked.value = !state.isScaleLocked.value;
              },
              onScaleChanged: (ScaleType? newValue) {
                if (newValue != null) {
                  state.currentScaleType.value = newValue;
                }
              },
            ),
          );
        }

        // Follower: hand off to a widget that listens only to the master.
        return _GfkFollowerBody(
          engine: engine,
          rack: rack,
          plugin: plugin,
          channelIndex: channelIndex,
          gfpaEntry: gfpaEntry,
          ownState: state,
          activeNotes: activeNotes,
        );
      },
    );
  }
}

/// Layer-2 body for GFPA Jam follower slots.
///
/// Subscribes to exactly one master-channel notifier:
/// [ChannelState.activeNotes] in bass-note mode, or [ChannelState.lastChord]
/// in chord-detection mode. This ensures that a chord change on the master
/// updates only the follower's header — not every slot in the rack.
///
/// The [activeNotes] field from the outer layer-1 builder is used for dimming
/// so that own-note changes (already handled by layer 1) remain accurate.
class _GfkFollowerBody extends StatelessWidget {
  final AudioEngine engine;
  final RackState rack;
  final GrooveForgeKeyboardPlugin plugin;
  final int channelIndex;
  final GFpaJamEntry gfpaEntry;
  final ChannelState ownState;

  /// Own-channel active notes snapshot from layer 1, used only for dimming.
  final Set<int> activeNotes;

  const _GfkFollowerBody({
    required this.engine,
    required this.rack,
    required this.plugin,
    required this.channelIndex,
    required this.gfpaEntry,
    required this.ownState,
    required this.activeNotes,
  });

  @override
  Widget build(BuildContext context) {
    final masterState = engine.channels[gfpaEntry.masterCh];

    // Subscribe to the one notifier that drives this follower's display.
    final Listenable masterNotifier = gfpaEntry.bassNoteMode
        ? masterState.activeNotes
        : masterState.lastChord;

    return ListenableBuilder(
      listenable: masterNotifier,
      builder: (ctx, _) {
        final refChord = _computeRefChord(masterState);
        final descriptiveName =
            engine.getDescriptiveScaleName(refChord, gfpaEntry.scaleType);

        // Build the display chord: root note + scale name in the chord header.
        final chordToDisplay = refChord != null
            ? ChordMatch(
                '${refChord.name.split(' ')[0]} $descriptiveName',
                refChord.scalePitchClasses,
                refChord.rootPc,
                refChord.isMinor,
              )
            : ownState.lastChord.value;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: ChannelPatchInfo(
            engine: engine,
            channelIndex: channelIndex,
            hideInstrumentPickers:
                plugin.soundfontPath == kMidiControllerOnlySoundfont,
            onPatchChanged: (program, bank) =>
                rack.setPluginPatch(plugin.id, program, bank: bank),
            onSoundfontChanged: (sf) =>
                rack.setPluginSoundfont(plugin.id, sf),
            // Follower is treated as always locked: scale is set by the Jam rack.
            isDimmed: activeNotes.isEmpty,
            isLocked: true,
            displayChord: chordToDisplay,
            referenceChord: refChord,
            currentScale: gfpaEntry.scaleType,
            descriptiveScaleName: descriptiveName,
            isJamSlave: true,
            showLockControls: true,
            // Lock and scale are controlled by the Jam Mode rack slot, not here.
            onLockToggled: null,
            onScaleChanged: (_) {},
          ),
        );
      },
    );
  }

  /// Computes the reference chord from the master channel state.
  ///
  /// In bass-note mode: synthesises a [ChordMatch] whose root is the lowest
  /// active MIDI note on the master channel, so the scale name shows the
  /// correct root even when no full chord is detected.
  /// In chord mode: reads the last detected chord directly.
  ChordMatch? _computeRefChord(ChannelState masterState) {
    if (gfpaEntry.bassNoteMode) {
      final active = masterState.activeNotes.value;
      if (active.isNotEmpty) {
        final rootPc = active.reduce(min) % 12;
        return ChordMatch(_noteNameFromPc(rootPc), const {}, rootPc, false);
      }
      return null;
    }
    return masterState.lastChord.value;
  }
}

/// Maps a MIDI pitch class (0–11) to a display note name.
String _noteNameFromPc(int pc) {
  const names = [
    'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'
  ];
  return names[pc % 12];
}
