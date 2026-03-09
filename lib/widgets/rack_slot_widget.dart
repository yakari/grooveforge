import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/plugin_instance.dart';
import '../models/vst3_plugin_instance.dart';
import '../services/audio_engine.dart';
import '../services/rack_state.dart';
import '../services/vst_host_service.dart';
import '../widgets/virtual_piano.dart';
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
              // Piano is only shown for built-in GK slots.
              // VST3 slots receive MIDI from the physical controller.
              if (plugin is GrooveForgeKeyboardPlugin)
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

  Widget _buildBody(BuildContext context) {
    if (plugin is GrooveForgeKeyboardPlugin) {
      return GrooveForgeKeyboardSlotUI(
        plugin: plugin as GrooveForgeKeyboardPlugin,
      );
    }
    if (plugin is Vst3PluginInstance) {
      return Vst3SlotUI(plugin: plugin as Vst3PluginInstance);
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

          // ── MIDI channel badge (dropdown)
          _MidiChannelBadge(plugin: plugin),
          const SizedBox(width: 4),

          // ── JAM chip (only for built-in keyboard slots)
          if (plugin is GrooveForgeKeyboardPlugin)
            _JamChip(plugin: plugin as GrooveForgeKeyboardPlugin),
          if (plugin is GrooveForgeKeyboardPlugin) const SizedBox(width: 4),

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

// ─── JAM chip ────────────────────────────────────────────────────────────────
//
// Shows "JAM OFF" / "JAM ON" for GrooveForge Keyboard slots.
//
// Behaviour:
//   • Tapping "JAM OFF" → if no master set yet, shows the master-picker modal
//     first, then enables Jam. If a master was previously set, re-enables
//     directly.
//   • Tapping "JAM ON" → disables Jam (keeps jamMasterSlotId for quick re-enable).
//   • When JAM ON: an adjacent tappable chip shows the master's MIDI channel and
//     allows the user to change it.

class _JamChip extends StatelessWidget {
  final GrooveForgeKeyboardPlugin plugin;
  const _JamChip({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final isOn = plugin.jamEnabled;
    final rack = context.read<RackState>();
    final l10n = AppLocalizations.of(context)!;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── JAM toggle button
        GestureDetector(
          onTap: () => _handleJamTap(context, rack, l10n),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isOn
                  ? Colors.deepPurpleAccent.withValues(alpha: 0.25)
                  : Colors.white10,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isOn
                    ? Colors.deepPurpleAccent.withValues(alpha: 0.8)
                    : Colors.white24,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOn ? Icons.link : Icons.link_off,
                  size: 11,
                  color: isOn ? Colors.deepPurpleAccent : Colors.white38,
                ),
                const SizedBox(width: 4),
                Text(
                  isOn ? l10n.jamSlotOn : l10n.jamSlotOff,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isOn ? Colors.deepPurpleAccent : Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Master picker chip (visible only when JAM ON)
        if (isOn) ...[
          const SizedBox(width: 3),
          _MasterPickerChip(plugin: plugin),
        ],
      ],
    );
  }

  void _handleJamTap(
    BuildContext context,
    RackState rack,
    AppLocalizations l10n,
  ) {
    if (plugin.jamEnabled) {
      // Toggle OFF — keep master for quick re-enable.
      rack.setPluginJamEnabled(plugin.id, enabled: false);
    } else if (plugin.jamMasterSlotId == null) {
      // First activation — must pick a master first.
      _showMasterPicker(
        context, rack, l10n,
        currentPluginId: plugin.id,
        onPicked: (masterId) {
          rack.setPluginJamEnabled(plugin.id, enabled: true, masterSlotId: masterId);
        },
      );
    } else {
      // Re-enable with previously chosen master.
      rack.setPluginJamEnabled(plugin.id, enabled: true);
    }
  }

  static void _showMasterPicker(
    BuildContext context,
    RackState rack,
    AppLocalizations l10n, {
    required String currentPluginId,
    void Function(String masterId)? onPicked,
  }) {
    // All other slots are candidates for being master.
    final candidates = rack.plugins
        .where((p) => p.id != currentPluginId)
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.jamSlotNoOtherSlots)),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.jamSlotSelectMaster,
            style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.jamSlotSelectMasterHint,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 8),
            ...candidates.map(
              (p) => ListTile(
                dense: true,
                leading: Icon(
                  p is GrooveForgeKeyboardPlugin ? Icons.piano : Icons.extension,
                  color: Colors.deepPurpleAccent,
                  size: 18,
                ),
                title: Text(
                  p.displayName,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'MIDI CH ${p.midiChannel}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onPicked?.call(p.id);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Master picker chip (shown next to JAM ON) ───────────────────────────────

class _MasterPickerChip extends StatelessWidget {
  final GrooveForgeKeyboardPlugin plugin;
  const _MasterPickerChip({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final rack = context.read<RackState>();
    final l10n = AppLocalizations.of(context)!;

    // Resolve the display label: show the master's MIDI channel if found.
    final master = plugin.jamMasterSlotId != null
        ? rack.plugins.where((p) => p.id == plugin.jamMasterSlotId).firstOrNull
        : null;

    final label = master != null
        ? 'CH ${master.midiChannel}'
        : l10n.jamSlotNoMasterSelected;

    final hasValidMaster = master != null;

    return GestureDetector(
      onTap: () => _JamChip._showMasterPicker(
        context,
        rack,
        l10n,
        currentPluginId: plugin.id,
        onPicked: (masterId) => rack.setPluginJamMaster(plugin.id, masterId),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: hasValidMaster
              ? Colors.deepPurpleAccent.withValues(alpha: 0.15)
              : Colors.orangeAccent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasValidMaster
                ? Colors.deepPurpleAccent.withValues(alpha: 0.5)
                : Colors.orangeAccent.withValues(alpha: 0.6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasValidMaster ? Icons.arrow_right_alt : Icons.warning_amber,
              size: 11,
              color: hasValidMaster ? Colors.deepPurpleAccent : Colors.orangeAccent,
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: hasValidMaster
                    ? Colors.deepPurpleAccent
                    : Colors.orangeAccent,
              ),
            ),
          ],
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
        ]),
        builder: (context, _) {
          final keysToShow = engine.pianoKeysToShow.value;
          final vAction = engine.verticalGestureAction.value;
          final hAction = engine.horizontalGestureAction.value;
          final validPcs = state.validPitchClasses.value;
          final followerMap = engine.jamFollowerMap.value;
          final isFollower =
              engine.jamEnabled.value && followerMap.containsKey(channelIndex);

          int? rootPc;
          if (isFollower) {
            final masterIdx = followerMap[channelIndex]!;
            if (masterIdx >= 0 && masterIdx < engine.channels.length) {
              rootPc = engine.channels[masterIdx].lastChord.value?.rootPc;
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
