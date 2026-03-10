import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/plugin_instance.dart';
import '../models/vst3_plugin_instance.dart';
import '../services/audio_engine.dart';
import '../services/rack_state.dart';
import '../services/vst_host_service.dart';
import '../widgets/virtual_piano.dart';
import 'rack/gfpa_jam_mode_slot_ui.dart';
import 'rack/gfpa_vocoder_slot_ui.dart';
import 'rack/grooveforge_keyboard_slot_ui.dart';
import 'rack/vst3_slot_ui.dart';

/// One slot in the GrooveForge rack.
///
/// Composed of:
///   - A header: drag handle, plugin name, MIDI channel badge, JAM chip,
///     active-note indicator, delete button.
///   - A plugin-specific body ([GrooveForgeKeyboardSlotUI] or [Vst3SlotUI]).
///   - A [VirtualPiano] (only for [GrooveForgeKeyboardPlugin] slots).
class RackSlotWidget extends StatelessWidget {
  final PluginInstance plugin;
  final double pianoHeight;

  const RackSlotWidget({
    super.key,
    required this.plugin,
    required this.pianoHeight,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    // midiChannel == 0 for MIDI FX / effect GFPA slots — use ch 0 as fallback.
    final channelIndex = (plugin.midiChannel - 1).clamp(0, 15);
    final channelState = engine.channels[channelIndex];

    return ValueListenableBuilder<Set<int>>(
      valueListenable: channelState.activeNotes,
      builder: (context, activeNotes, _) {
        final isFlashing = activeNotes.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: isFlashing
                ? Colors.blueAccent.withValues(alpha: 0.2)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFlashing ? Colors.blueAccent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SlotHeader(plugin: plugin, isFlashing: isFlashing),
              _buildBody(context),
              // Piano is shown for built-in GK slots and GFPA instrument slots
              // (keyboard and vocoder). MIDI FX / VST3 / effect slots get none.
              if (_showPiano)
                SizedBox(
                  height: pianoHeight,
                  child: _RackSlotPiano(
                    channelIndex: channelIndex,
                    plugin: plugin,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  bool get _showPiano {
    if (plugin is GrooveForgeKeyboardPlugin) return true;
    if (plugin is GFpaPluginInstance) {
      final gfpa = plugin as GFpaPluginInstance;
      // Vocoder has a MIDI channel and responds to notes.
      return gfpa.pluginId == 'com.grooveforge.vocoder';
    }
    return false;
  }

  Widget _buildBody(BuildContext context) {
    if (plugin is GrooveForgeKeyboardPlugin) {
      return GrooveForgeKeyboardSlotUI(
        plugin: plugin as GrooveForgeKeyboardPlugin,
      );
    }
    if (plugin is Vst3PluginInstance) {
      return Vst3SlotUI(plugin: plugin as Vst3PluginInstance);
    }
    if (plugin is GFpaPluginInstance) {
      final gfpa = plugin as GFpaPluginInstance;
      switch (gfpa.pluginId) {
        case 'com.grooveforge.vocoder':
          return GFpaVocoderSlotUI(plugin: gfpa);
        case 'com.grooveforge.jammode':
          return GFpaJamModeSlotUI(plugin: gfpa);
        default:
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Plugin not installed: ${gfpa.pluginId}',
              style: const TextStyle(color: Colors.orange, fontSize: 12),
            ),
          );
      }
    }
    return const SizedBox.shrink();
  }
}

// ─── Slot Header ─────────────────────────────────────────────────────────────

class _SlotHeader extends StatelessWidget {
  final PluginInstance plugin;
  final bool isFlashing;

  const _SlotHeader({required this.plugin, required this.isFlashing});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          // ── Drag handle
          ReorderableDragStartListener(
            index: rack.plugins.indexOf(plugin),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Icon(Icons.drag_handle, color: Colors.white38, size: 20),
            ),
          ),

          // ── Active-note indicator
          AnimatedOpacity(
            duration: const Duration(milliseconds: 100),
            opacity: isFlashing ? 1.0 : 0.0,
            child: const Icon(Icons.circle, color: Colors.greenAccent, size: 10),
          ),
          const SizedBox(width: 6),

          // ── Plugin name
          Expanded(
            child: Row(
              children: [
                Icon(_iconFor(plugin), color: Colors.deepPurpleAccent, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    plugin.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // ── MIDI channel badge — hidden for MIDI FX / effect GFPA slots
          if (plugin.midiChannel > 0) ...[
            _MidiChannelBadge(plugin: plugin),
            const SizedBox(width: 4),
          ],

          // ── Delete button
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white38),
            tooltip: l10n.rackRemovePlugin,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _confirmRemove(context, l10n, rack),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(PluginInstance p) {
    if (p is GrooveForgeKeyboardPlugin) return Icons.piano;
    if (p is GFpaPluginInstance) {
      switch (p.pluginId) {
        case 'com.grooveforge.keyboard': return Icons.piano;
        case 'com.grooveforge.vocoder': return Icons.mic;
        case 'com.grooveforge.jammode': return Icons.link;
      }
    }
    return Icons.extension;
  }

  void _confirmRemove(
    BuildContext context,
    AppLocalizations l10n,
    RackState rack,
  ) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.rackRemovePlugin,
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.rackRemovePluginConfirm,
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              rack.removePlugin(plugin.id);
            },
            child: Text(l10n.rackRemove),
          ),
        ],
      ),
    );
  }
}

// ─── MIDI channel badge ───────────────────────────────────────────────────────

class _MidiChannelBadge extends StatelessWidget {
  final PluginInstance plugin;
  const _MidiChannelBadge({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final rack = context.read<RackState>();
    final l10n = AppLocalizations.of(context)!;

    return GestureDetector(
      onTap: () => _showChannelPicker(context, rack, l10n),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blueAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
        ),
        child: Text(
          '${l10n.rackMidiChannel} ${plugin.midiChannel}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
      ),
    );
  }

  void _showChannelPicker(
    BuildContext context,
    RackState rack,
    AppLocalizations l10n,
  ) {
    final used = rack.plugins
        .where((p) => p.id != plugin.id)
        .map((p) => p.midiChannel)
        .toSet();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(l10n.rackMidiChannel,
            style: const TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 200,
          height: 360,
          child: ListView.builder(
            itemCount: 16,
            itemBuilder: (_, i) {
              final ch = i + 1;
              final isCurrent = ch == plugin.midiChannel;
              final isUsed = used.contains(ch);
              return ListTile(
                dense: true,
                enabled: !isUsed || isCurrent,
                selected: isCurrent,
                selectedColor: Colors.blueAccent,
                title: Text('CH $ch${isUsed && !isCurrent ? ' (in use)' : ''}'),
                onTap: isCurrent || isUsed
                    ? null
                    : () {
                        rack.setPluginMidiChannel(plugin.id, ch);
                        Navigator.pop(ctx);
                      },
              );
            },
          ),
        ),
      ),
    );
  }
}

// ─── Piano (full channel logic, adapted for rack slot) ───────────────────────

class _RackSlotPiano extends StatelessWidget {
  final int channelIndex;
  final PluginInstance plugin;

  const _RackSlotPiano({
    required this.channelIndex,
    required this.plugin,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    final state = engine.channels[channelIndex];

    return GestureDetector(
      onTap: () {},
      child: ListenableBuilder(
        listenable: Listenable.merge([
          engine.stateNotifier,
          engine.pianoKeysToShow,
          engine.verticalGestureAction,
          engine.horizontalGestureAction,
          state.validPitchClasses,
          engine.jamEnabled,
          engine.lockModePreference,
          engine.jamFollowerMap,
          engine.gfpaJamEntries,
          // Listen to all channels so rootPc and scale borders refresh when any
          // master chord or active-note set changes (e.g. bass-note mode).
          ...engine.channels.map((ch) => ch.lastChord),
          ...engine.channels.map((ch) => ch.activeNotes),
        ]),
        builder: (context, _) {
          final keysToShow = engine.pianoKeysToShow.value;
          final vAction = engine.verticalGestureAction.value;
          final hAction = engine.horizontalGestureAction.value;
          final validPcs = state.validPitchClasses.value;
          final followerMap = engine.jamFollowerMap.value;
          final isLegacyFollower =
              engine.jamEnabled.value && followerMap.containsKey(channelIndex);
          final gfpaEntries = engine.gfpaJamEntries.value;
          final gfpaEntry = gfpaEntries.where((e) => e.followerCh == channelIndex).firstOrNull;
          final isFollower = isLegacyFollower || gfpaEntry != null;

          int? rootPc;
          if (isLegacyFollower) {
            final masterIdx = followerMap[channelIndex]!;
            if (masterIdx >= 0 && masterIdx < engine.channels.length) {
              rootPc = engine.channels[masterIdx].lastChord.value?.rootPc;
            }
          } else if (gfpaEntry != null) {
            final masterCh = gfpaEntry.masterCh;
            if (gfpaEntry.bassNoteMode) {
              final active = engine.channels[masterCh].activeNotes.value;
              if (active.isNotEmpty) rootPc = active.reduce((a, b) => a < b ? a : b) % 12;
            } else {
              rootPc = engine.channels[masterCh].lastChord.value?.rootPc;
            }
          }

          return ValueListenableBuilder<Set<int>>(
            valueListenable: state.activeNotes,
            builder: (context, activeNotes, _) => VirtualPiano(
              activeNotes: activeNotes,
              verticalAction: vAction,
              horizontalAction: hAction,
              keysToShow: keysToShow,
              validPitchClasses: isFollower ? validPcs : null,
              rootPitchClass: isFollower ? rootPc : null,
              showJamModeBorders: engine.showJamModeBorders.value,
              highlightWrongNotes: engine.highlightWrongNotes.value,
              onNotePressed: (note) {
                if (plugin is Vst3PluginInstance) {
                  // VST3 audio goes to VstHostService; engine only tracks
                  // UI state (key highlight) without routing to FluidSynth.
                  context.read<VstHostService>().noteOn(
                      plugin.id, 0, note, 1.0);
                  engine.noteOnUiOnly(channel: channelIndex, key: note);
                } else {
                  engine.playNote(
                      channel: channelIndex, key: note, velocity: 100);
                }
              },
              onNoteReleased: (note) {
                if (plugin is Vst3PluginInstance) {
                  context.read<VstHostService>().noteOff(plugin.id, 0, note);
                  engine.noteOffUiOnly(channel: channelIndex, key: note);
                } else {
                  engine.stopNote(channel: channelIndex, key: note);
                }
              },
              onPitchBend: (val) =>
                  engine.setPitchBend(channel: channelIndex, value: val),
              onControlChange: (cc, val) => engine.setControlChange(
                  channel: channelIndex, controller: cc, value: val),
              onInteractingChanged: engine.updateGestureState,
            ),
          );
        },
      ),
    );
  }
}
