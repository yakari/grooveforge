import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/plugin_instance.dart';
import '../models/plugin_role.dart';
import '../models/vst3_plugin_instance.dart';
import '../services/audio_engine.dart';
import '../services/rack_state.dart';
import '../widgets/virtual_piano.dart';
import 'rack/grooveforge_keyboard_slot_ui.dart';
import 'rack/vst3_slot_ui.dart';

/// One slot in the GrooveForge rack.
///
/// Composed of:
///   - A collapsible header: drag handle, plugin name, MIDI channel badge,
///     master/slave toggle chip, active-note indicator, delete button.
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
    final channelIndex =
        (plugin.midiChannel - 1).clamp(0, 15);
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
              _SlotHeader(
                plugin: plugin,
                isFlashing: isFlashing,
              ),
              _buildBody(context),
              if (plugin is GrooveForgeKeyboardPlugin)
                SizedBox(
                  height: pianoHeight,
                  child: _RackSlotPiano(channelIndex: channelIndex),
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
            child: const Icon(
              Icons.circle,
              color: Colors.greenAccent,
              size: 10,
            ),
          ),
          const SizedBox(width: 6),

          // ── Plugin name
          Expanded(
            child: Row(
              children: [
                Icon(
                  _iconFor(plugin),
                  color: Colors.deepPurpleAccent,
                  size: 16,
                ),
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

          // ── Master / Slave toggle chip
          _RoleChip(plugin: plugin),
          const SizedBox(width: 4),

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

// ─── Piano (full channel card piano logic, adapted for rack slot) ─────────────

class _RackSlotPiano extends StatelessWidget {
  final int channelIndex;
  const _RackSlotPiano({required this.channelIndex});

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
          engine.jamSlaveChannels,
          engine.jamMasterChannel,
        ]),
        builder: (context, _) {
          final keysToShow = engine.pianoKeysToShow.value;
          final vAction = engine.verticalGestureAction.value;
          final hAction = engine.horizontalGestureAction.value;
          final validPcs = state.validPitchClasses.value;
          final jamEnabled = engine.jamEnabled.value;
          final lockMode = engine.lockModePreference.value;
          final slaves = engine.jamSlaveChannels.value;
          final isSlave =
              lockMode == ScaleLockMode.jam &&
              jamEnabled &&
              slaves.contains(channelIndex);

          int? rootPc;
          if (isSlave) {
            final masterCh = engine.jamMasterChannel.value;
            if (masterCh >= 0 && masterCh < engine.channels.length) {
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
              validPitchClasses: isSlave ? validPcs : null,
              rootPitchClass: isSlave ? rootPc : null,
              showJamModeBorders: engine.showJamModeBorders.value,
              highlightWrongNotes: engine.highlightWrongNotes.value,
              onNotePressed: (note) =>
                  engine.playNote(channel: channelIndex, key: note, velocity: 100),
              onNoteReleased: (note) =>
                  engine.stopNote(channel: channelIndex, key: note),
              onPitchBend: (val) =>
                  engine.setPitchBend(channel: channelIndex, value: val),
              onControlChange: (cc, val) =>
                  engine.setControlChange(channel: channelIndex, controller: cc, value: val),
              onInteractingChanged: engine.updateGestureState,
            ),
          );
        },
      ),
    );
  }
}

// ─── Role chip ────────────────────────────────────────────────────────────────

class _RoleChip extends StatelessWidget {
  final PluginInstance plugin;
  const _RoleChip({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final rack = context.read<RackState>();
    final l10n = AppLocalizations.of(context)!;
    final isMaster = plugin.role == PluginRole.master;

    return GestureDetector(
      onTap: () {
        rack.setPluginRole(
          plugin.id,
          isMaster ? PluginRole.slave : PluginRole.master,
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isMaster
              ? Colors.amber.withValues(alpha: 0.2)
              : Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isMaster
                ? Colors.amber.withValues(alpha: 0.6)
                : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isMaster ? Icons.star : Icons.link,
              size: 11,
              color: isMaster ? Colors.amber : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              isMaster ? l10n.rackRoleMaster : l10n.rackRoleSlave,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isMaster ? Colors.amber : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
