import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/looper_plugin_instance.dart';
import '../models/plugin_instance.dart';
import '../models/virtual_piano_plugin.dart';
import '../models/vst3_plugin_instance.dart';
import '../models/audio_graph_connection.dart';
import '../models/audio_port_id.dart';
import '../services/audio_engine.dart';
import '../services/audio_graph.dart';
import '../services/looper_engine.dart';
import '../services/rack_state.dart';
import '../services/vst_host_service.dart';
import '../models/keyboard_display_config.dart';
import '../widgets/keyboard_config_dialog.dart';
import '../widgets/virtual_piano.dart';
import 'rack/gfpa_jam_mode_slot_ui.dart';
import 'rack/gfpa_vocoder_slot_ui.dart';
import 'rack/grooveforge_keyboard_slot_ui.dart';
import 'rack/looper_slot_ui.dart';
import 'rack/virtual_piano_slot_ui.dart';
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
    debugPrint('RackSlotWidget: build START for ${plugin.displayName}');
    final engine = context.read<AudioEngine>();
    // midiChannel == 0 for MIDI FX / effect GFPA slots — use ch 0 as fallback.
    final channelIndex = (plugin.midiChannel - 1).clamp(0, 15);

    // ── Looper: glow when actively playing back to connected slots ──────────
    if (plugin is LooperPluginInstance) {
      return ListenableBuilder(
        listenable: context.read<LooperEngine>(),
        builder: (context, _) {
          final session =
              context.read<LooperEngine>().session(plugin.id);
          final isFlashing = session?.isPlayingActive ?? false;
          return _buildSlotContent(context, isFlashing, channelIndex);
        },
      );
    }

    // ── Jam Mode: glow while keys are held on the master channel ─────────────
    // Both detect modes (chord and bass-note) share the same glow condition:
    // activeNotes is non-empty ↔ the master is currently sending input.
    // lastChord is intentionally NOT used: it persists after keys are released
    // (it stores the last recognised chord), which would keep the header lit
    // permanently after a single chord is played.
    // No glow when Jam Mode is disabled or no master slot is configured.
    if (plugin is GFpaPluginInstance &&
        (plugin as GFpaPluginInstance).pluginId == 'com.grooveforge.jammode') {
      return ListenableBuilder(
        listenable: Listenable.merge([
          engine.gfpaJamEntries,
          ...engine.channels.map((ch) => ch.activeNotes),
        ]),
        builder: (context, _) {
          final jamPlugin = plugin as GFpaPluginInstance;
          final enabled = jamPlugin.state['enabled'] != false;
          if (!enabled) return _buildSlotContent(context, false, channelIndex);

          // Find the master slot to know which channel to watch.
          final rack = context.read<RackState>();
          final masterSlot = rack.plugins
              .cast<PluginInstance?>()
              .firstWhere(
                (p) => p?.id == jamPlugin.masterSlotId,
                orElse: () => null,
              );
          if (masterSlot == null) {
            return _buildSlotContent(context, false, channelIndex);
          }

          final masterCh = (masterSlot.midiChannel - 1).clamp(0, 15);
          final isFlashing =
              engine.channels[masterCh].activeNotes.value.isNotEmpty;

          return _buildSlotContent(context, isFlashing, channelIndex);
        },
      );
    }

    // ── Instrument slots: glow when notes are active on their channel ───────
    final channelState = engine.channels[channelIndex];
    debugPrint(
        'RackSlotWidget: building ValueListenableBuilder for ${plugin.displayName}');
    return ValueListenableBuilder<Set<int>>(
      valueListenable: channelState.activeNotes,
      builder: (context, activeNotes, _) {
        final isFlashing = _shouldShowNoteGlow && activeNotes.isNotEmpty;
        return _buildSlotContent(context, isFlashing, channelIndex);
      },
    );
  }

  /// Builds the animated slot container with [isFlashing] glow state.
  ///
  /// Extracted so that Looper, Jam Mode, and instrument slots can each use a
  /// different reactive listener while sharing the same decoration logic.
  Widget _buildSlotContent(
    BuildContext context,
    bool isFlashing,
    int channelIndex,
  ) {
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
              height: _effectivePianoHeight,
              child: _RackSlotPiano(
                channelIndex: channelIndex,
                plugin: plugin,
              ),
            ),
        ],
      ),
    );
  }

  /// Returns the piano area height for this slot.
  ///
  /// If the plugin has a per-slot [KeyboardDisplayConfig] with an explicit
  /// [KeyHeightOption], that height takes precedence over [pianoHeight].
  /// Otherwise the default [pianoHeight] passed by the parent is used.
  double get _effectivePianoHeight {
    KeyboardDisplayConfig? cfg;
    if (plugin is GrooveForgeKeyboardPlugin) {
      cfg = (plugin as GrooveForgeKeyboardPlugin).keyboardConfig;
    } else if (plugin is VirtualPianoPlugin) {
      cfg = (plugin as VirtualPianoPlugin).keyboardConfig;
    }
    if (cfg == null) return pianoHeight;
    // Only override height when the user has explicitly chosen non-normal,
    // OR when a config object exists (it always carries a keyHeightOption).
    return cfg.keyHeightOption.pianoPixelHeight;
  }

  bool get _showPiano {
    if (plugin is GrooveForgeKeyboardPlugin) return true;
    if (plugin is VirtualPianoPlugin) return true;
    if (plugin is GFpaPluginInstance) {
      final gfpa = plugin as GFpaPluginInstance;
      // Vocoder has a MIDI channel and responds to notes.
      return gfpa.pluginId == 'com.grooveforge.vocoder';
    }
    return false;
  }

  /// Whether this slot should flash blue when notes are active on its channel.
  ///
  /// Jam Mode and Looper are MIDI FX / recorder slots — they share channel 0
  /// with any instrument on MIDI channel 1, so they must be excluded from the
  /// note-activity glow to avoid false highlights when an unconnected VP is
  /// played.  Only slots that directly produce or respond to notes should glow.
  bool get _shouldShowNoteGlow {
    if (plugin is LooperPluginInstance) return false;
    if (plugin is GFpaPluginInstance) {
      final gfpa = plugin as GFpaPluginInstance;
      // Only the vocoder is an instrument; Jam Mode and other MIDI FX are not.
      return gfpa.pluginId == 'com.grooveforge.vocoder';
    }
    return true; // VP, GFK, VST3 all respond to notes and should glow.
  }

  Widget _buildBody(BuildContext context) {
    debugPrint('RackSlotWidget: _buildBody for ${plugin.displayName}');
    if (plugin is GrooveForgeKeyboardPlugin) {
      return GrooveForgeKeyboardSlotUI(
        plugin: plugin as GrooveForgeKeyboardPlugin,
      );
    }
    if (plugin is VirtualPianoPlugin) {
      return VirtualPianoSlotUI(plugin: plugin as VirtualPianoPlugin);
    }
    if (plugin is LooperPluginInstance) {
      return LooperSlotUI(plugin: plugin as LooperPluginInstance);
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
          debugPrint('RackSlotWidget: returning GFpaJamModeSlotUI');
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

          // ── Keyboard config button — only for piano-type slots
          if (plugin is GrooveForgeKeyboardPlugin ||
              plugin is VirtualPianoPlugin) ...[
            IconButton(
              icon: const Icon(Icons.tune, size: 16, color: Colors.white38),
              tooltip: 'Keyboard config',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => showKeyboardConfigDialog(context, plugin),
            ),
            const SizedBox(width: 4),
          ],

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
    if (p is VirtualPianoPlugin) return Icons.piano_outlined;
    if (p is LooperPluginInstance) return Icons.loop;
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

  /// Returns the per-slot [KeyboardDisplayConfig] if the plugin has one.
  KeyboardDisplayConfig? get _keyboardConfig {
    if (plugin is GrooveForgeKeyboardPlugin) {
      return (plugin as GrooveForgeKeyboardPlugin).keyboardConfig;
    }
    if (plugin is VirtualPianoPlugin) {
      return (plugin as VirtualPianoPlugin).keyboardConfig;
    }
    return null;
  }

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
          engine.gfpaJamEntries,
          // Listen to all channels so rootPc and scale borders refresh when any
          // master chord or active-note set changes (e.g. bass-note mode).
          ...engine.channels.map((ch) => ch.lastChord),
          ...engine.channels.map((ch) => ch.activeNotes),
        ]),
        builder: (context, _) {
          // Resolve effective values: per-slot config overrides global prefs.
          final cfg = _keyboardConfig;
          final keysToShow =
              cfg?.keysToShow ?? engine.pianoKeysToShow.value;
          final vAction =
              cfg?.verticalGestureAction ?? engine.verticalGestureAction.value;
          final hAction = cfg?.horizontalGestureAction ??
              engine.horizontalGestureAction.value;
          final validPcs = state.validPitchClasses.value;
          final gfpaEntry = engine.gfpaJamEntries.value
              .where((e) => e.followerCh == channelIndex)
              .firstOrNull;
          final isFollower = gfpaEntry != null;

          int? rootPc;
          if (gfpaEntry != null) {
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
              onNotePressed: (note) => _onNotePressed(context, engine, note),
              onNoteReleased: (note) => _onNoteReleased(context, engine, note),
              onPitchBend: (val) =>
                  _onPitchBend(context, engine, val),
              onControlChange: (cc, val) =>
                  _onControlChange(context, engine, cc, val),
              onInteractingChanged: engine.updateGestureState,
            ),
          );
        },
      ),
    );
  }

  /// Handles a note-on event from the on-screen piano keyboard.
  ///
  /// Routing logic per plugin type:
  /// - [VirtualPianoPlugin]: has no soundfont; highlights its own keys for
  ///   visual feedback, then forwards the note to every slot wired to its
  ///   MIDI OUT jack via the [AudioGraph] cable map.
  /// - [Vst3PluginInstance]: sends via [VstHostService] (bypasses FluidSynth)
  ///   and marks the key as active on the engine for UI highlighting.
  /// - All other slots (GFK, GFPA, etc.): routes to FluidSynth AND forwards
  ///   the note to any [LooperPluginInstance] wired to this slot's MIDI OUT.
  void _onNotePressed(BuildContext context, AudioEngine engine, int note) {
    if (plugin is VirtualPianoPlugin) {
      // Highlight VP's own key for visual feedback — no audio produced here.
      engine.noteOnUiOnly(channel: channelIndex, key: note);
      // Route the note to every slot connected to this VP's MIDI OUT jack.
      _dispatchMidiNoteOn(context, engine, note);
    } else if (plugin is Vst3PluginInstance) {
      // VST3 audio goes to VstHostService; engine only tracks UI state.
      context.read<VstHostService>().noteOn(plugin.id, 0, note, 1.0);
      engine.noteOnUiOnly(channel: channelIndex, key: note);
    } else {
      engine.playNote(channel: channelIndex, key: note, velocity: 100);
      // Also feed any loopers connected to this slot's MIDI OUT so
      // on-screen keys are captured by the looper (e.g. GFK → Looper cable).
      _feedConnectedLoopers(context, note, 100, isNoteOn: true);
    }
  }

  /// Handles a note-off event from the on-screen piano keyboard.
  void _onNoteReleased(BuildContext context, AudioEngine engine, int note) {
    if (plugin is VirtualPianoPlugin) {
      engine.noteOffUiOnly(channel: channelIndex, key: note);
      _dispatchMidiNoteOff(context, engine, note);
    } else if (plugin is Vst3PluginInstance) {
      context.read<VstHostService>().noteOff(plugin.id, 0, note);
      engine.noteOffUiOnly(channel: channelIndex, key: note);
    } else {
      engine.stopNote(channel: channelIndex, key: note);
      // Mirror the note-on looper feed for note-off so held notes are
      // properly terminated in the recorded loop.
      _feedConnectedLoopers(context, note, 0, isNoteOn: false);
    }
  }

  /// Forwards a MIDI note-on event to all slots wired to this slot's MIDI OUT
  /// jack. Called only for [VirtualPianoPlugin] slots.
  ///
  /// Each connected target is routed according to its type:
  /// - [LooperPluginInstance] → [LooperEngine.feedMidiEvent] (records the note)
  /// - VST3 → [VstHostService.noteOn] + [AudioEngine.noteOnUiOnly]
  /// - FluidSynth (GFK, Vocoder, generic GFPA) → [AudioEngine.playNote]
  void _dispatchMidiNoteOn(
    BuildContext context,
    AudioEngine engine,
    int note,
  ) {
    final status = 0x90 | (channelIndex & 0x0F); // note-on on this channel
    for (final cable in _midiOutCables(context)) {
      final target = _findPlugin(context, cable.toSlotId);
      if (target == null) continue;
      if (target is LooperPluginInstance) {
        context.read<LooperEngine>().feedMidiEvent(target.id, status, note, 100);
        continue;
      }
      final targetCh = (target.midiChannel - 1).clamp(0, 15);
      if (target is Vst3PluginInstance) {
        context.read<VstHostService>().noteOn(target.id, 0, note, 1.0);
        engine.noteOnUiOnly(channel: targetCh, key: note);
      } else {
        engine.playNote(channel: targetCh, key: note, velocity: 100);
      }
    }
  }

  /// Forwards a MIDI note-off event to all slots wired to this slot's MIDI OUT
  /// jack. Mirrors the logic of [_dispatchMidiNoteOn].
  void _dispatchMidiNoteOff(
    BuildContext context,
    AudioEngine engine,
    int note,
  ) {
    final status = 0x80 | (channelIndex & 0x0F); // note-off on this channel
    for (final cable in _midiOutCables(context)) {
      final target = _findPlugin(context, cable.toSlotId);
      if (target == null) continue;
      if (target is LooperPluginInstance) {
        context.read<LooperEngine>().feedMidiEvent(target.id, status, note, 0);
        continue;
      }
      final targetCh = (target.midiChannel - 1).clamp(0, 15);
      if (target is Vst3PluginInstance) {
        context.read<VstHostService>().noteOff(target.id, 0, note);
        engine.noteOffUiOnly(channel: targetCh, key: note);
      } else {
        engine.stopNote(channel: targetCh, key: note);
      }
    }
  }

  /// Feeds a note event only to [LooperPluginInstance] targets connected to
  /// this slot's MIDI OUT jack.
  ///
  /// Unlike [_dispatchMidiNoteOn]/[_dispatchMidiNoteOff] (which route to ALL
  /// downstream targets), this method intentionally skips non-looper targets
  /// to avoid double-playing instruments that are already driven by FluidSynth.
  ///
  /// Called for GFK and other non-VP, non-VST3 slots so that on-screen key
  /// presses are recorded by any connected looper without disturbing audio.
  void _feedConnectedLoopers(
    BuildContext context,
    int note,
    int velocity, {
    required bool isNoteOn,
  }) {
    final looperEngine = context.read<LooperEngine>();
    final status = isNoteOn
        ? (0x90 | (channelIndex & 0x0F))
        : (0x80 | (channelIndex & 0x0F));
    for (final cable in _midiOutCables(context)) {
      final target = _findPlugin(context, cable.toSlotId);
      if (target is LooperPluginInstance) {
        looperEngine.feedMidiEvent(target.id, status, note, velocity);
      }
    }
  }

  /// Returns all [AudioGraphConnection]s originating from this slot's
  /// [AudioPortId.midiOut] jack.
  List<AudioGraphConnection> _midiOutCables(BuildContext context) =>
      context
          .read<AudioGraph>()
          .connectionsFrom(plugin.id)
          .where((c) => c.fromPort == AudioPortId.midiOut)
          .toList();

  /// Looks up a plugin instance by its slot ID in [RackState].
  /// Returns null if the slot has been removed since the cable was drawn.
  PluginInstance? _findPlugin(BuildContext context, String slotId) =>
      context
          .read<RackState>()
          .plugins
          .where((p) => p.id == slotId)
          .firstOrNull;

  // ─── Expression (pitch bend / CC) routing ────────────────────────────────

  /// Handles a pitch-bend gesture from the on-screen piano.
  ///
  /// - **[VirtualPianoPlugin]**: VP produces no audio of its own, so the bend
  ///   is forwarded through its MIDI OUT cable to every connected target slot,
  ///   matching the same routing that notes follow in [_dispatchMidiNoteOn].
  /// - **[Vst3PluginInstance]**: dispatched to [VstHostService] (no-op until
  ///   the native binding is added; avoids incorrect FluidSynth bend).
  /// - **All others** (GFK, vocoder, GFPA): sent directly to [AudioEngine].
  void _onPitchBend(BuildContext context, AudioEngine engine, int rawValue) {
    if (plugin is VirtualPianoPlugin) {
      _dispatchMidiPitchBend(context, engine, rawValue);
    } else if (plugin is Vst3PluginInstance) {
      final semitones = (rawValue - 8192) / 8192.0 * 2.0;
      context.read<VstHostService>().pitchBend(plugin.id, 0, semitones);
    } else {
      engine.setPitchBend(channel: channelIndex, value: rawValue);
    }
  }

  /// Handles a control-change gesture from the on-screen piano.
  ///
  /// Same routing logic as [_onPitchBend]: VP slots forward through cables,
  /// VST3 slots go to [VstHostService], everything else to [AudioEngine].
  ///
  /// CC 1 (vibrato gesture) is remapped to the per-slot aftertouch destination
  /// when a [KeyboardDisplayConfig] override is active; otherwise it falls back
  /// to [AudioEngine.aftertouchDestCc].
  void _onControlChange(
    BuildContext context,
    AudioEngine engine,
    int cc,
    int value,
  ) {
    // Remap CC 1 (the vibrato-gesture default) to the effective aftertouch CC.
    final effectiveCc = (cc == 1)
        ? (_keyboardConfig?.aftertouchDestCc ?? engine.aftertouchDestCc.value)
        : cc;

    if (plugin is VirtualPianoPlugin) {
      _dispatchMidiCC(context, engine, effectiveCc, value);
    } else if (plugin is Vst3PluginInstance) {
      context.read<VstHostService>().controlChange(plugin.id, 0, effectiveCc, value);
    } else {
      engine.setControlChange(
          channel: channelIndex, controller: effectiveCc, value: value);
    }
  }

  /// Forwards a pitch-bend value through every slot wired to this VP's MIDI OUT.
  ///
  /// Converts the raw 14-bit value to semitones when the target is VST3,
  /// and reconstructs the correct 14-bit word for FluidSynth channels.
  void _dispatchMidiPitchBend(
    BuildContext context,
    AudioEngine engine,
    int rawValue,
  ) {
    final vstSvc = context.read<VstHostService>();
    for (final cable in _midiOutCables(context)) {
      final target = _findPlugin(context, cable.toSlotId);
      if (target == null) continue;
      if (target is Vst3PluginInstance) {
        final semitones = (rawValue - 8192) / 8192.0 * 2.0;
        vstSvc.pitchBend(target.id, 0, semitones);
      } else {
        final targetCh = (target.midiChannel - 1).clamp(0, 15);
        engine.setPitchBend(channel: targetCh, value: rawValue);
      }
    }
  }

  /// Forwards a control-change message through every slot wired to this VP's MIDI OUT.
  void _dispatchMidiCC(
    BuildContext context,
    AudioEngine engine,
    int cc,
    int value,
  ) {
    final vstSvc = context.read<VstHostService>();
    for (final cable in _midiOutCables(context)) {
      final target = _findPlugin(context, cable.toSlotId);
      if (target == null) continue;
      if (target is Vst3PluginInstance) {
        vstSvc.controlChange(target.id, 0, cc, value);
      } else {
        final targetCh = (target.midiChannel - 1).clamp(0, 15);
        engine.setControlChange(channel: targetCh, controller: cc, value: value);
      }
    }
  }
}
