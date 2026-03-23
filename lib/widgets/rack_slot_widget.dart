import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../constants/soundfont_sentinels.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/looper_plugin_instance.dart';
import '../models/plugin_instance.dart';
import '../models/vst3_plugin_instance.dart';
import '../models/audio_graph_connection.dart';
import '../models/audio_port_id.dart';
import '../services/audio_engine.dart';
import '../services/audio_graph.dart';
import '../services/looper_engine.dart';
import '../services/rack_state.dart';
import '../services/transport_engine.dart';
import '../services/vst_host_service.dart';
import '../models/keyboard_display_config.dart';
import '../widgets/keyboard_config_dialog.dart';
import '../widgets/virtual_piano.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

import 'rack/gfpa_descriptor_slot_ui.dart';
import 'rack/gfpa_jam_mode_slot_ui.dart';
import 'rack/gfpa_stylophone_slot_ui.dart';
import 'rack/gfpa_theremin_slot_ui.dart';
import 'rack/gfpa_vocoder_slot_ui.dart';
import 'rack/grooveforge_keyboard_slot_ui.dart';
import 'rack/looper_slot_ui.dart';
import 'rack/vst3_effect_slot_ui.dart';
import 'rack/vst3_slot_ui.dart';

/// One slot in the GrooveForge rack.
///
/// Composed of:
///   - A header: drag handle, plugin name, MIDI channel badge, JAM chip,
///     active-note indicator, delete button.
///   - A plugin-specific body ([GrooveForgeKeyboardSlotUI] or [Vst3SlotUI]).
///   - A [VirtualPiano] (GF keyboard, MIDI-only keyboard, vocoder).
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
    } else if (plugin is GFpaPluginInstance) {
      cfg = (plugin as GFpaPluginInstance).keyboardConfig;
    }
    if (cfg == null) return pianoHeight;
    return cfg.keyHeightOption.pianoPixelHeight;
  }

  bool get _showPiano {
    if (plugin is GrooveForgeKeyboardPlugin) return true;
    if (plugin is GFpaPluginInstance) {
      final gfpa = plugin as GFpaPluginInstance;
      // Vocoder uses the shared rack piano. Stylophone and Theremin render
      // their own playing surface in the slot body — no piano needed.
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
      // Instrument slots that produce notes should glow; MIDI FX slots should not.
      switch (gfpa.pluginId) {
        case 'com.grooveforge.vocoder':
        case 'com.grooveforge.stylophone':
        case 'com.grooveforge.theremin':
          return true;
        default:
          return false;
      }
    }
    // Effect and analyzer VST3 slots process audio, not MIDI — no note glow.
    if (plugin is Vst3PluginInstance) {
      final vst3 = plugin as Vst3PluginInstance;
      return vst3.pluginType == Vst3PluginType.instrument;
    }
    return true; // GFK (synth or MIDI-only) responds to notes and should glow.
  }

  Widget _buildBody(BuildContext context) {
    debugPrint('RackSlotWidget: _buildBody for ${plugin.displayName}');
    if (plugin is GrooveForgeKeyboardPlugin) {
      return GrooveForgeKeyboardSlotUI(
        plugin: plugin as GrooveForgeKeyboardPlugin,
      );
    }
    if (plugin is LooperPluginInstance) {
      return LooperSlotUI(plugin: plugin as LooperPluginInstance);
    }
    if (plugin is Vst3PluginInstance) {
      final vst3 = plugin as Vst3PluginInstance;
      // Route effect and analyzer plugins to the dedicated effect slot UI.
      // Instrument plugins keep the standard Vst3SlotUI with MIDI routing.
      if (vst3.pluginType == Vst3PluginType.effect ||
          vst3.pluginType == Vst3PluginType.analyzer) {
        return Vst3EffectSlotUI(plugin: vst3);
      }
      return Vst3SlotUI(plugin: vst3);
    }
    if (plugin is GFpaPluginInstance) {
      final gfpa = plugin as GFpaPluginInstance;
      switch (gfpa.pluginId) {
        case 'com.grooveforge.vocoder':
          return GFpaVocoderSlotUI(plugin: gfpa);
        case 'com.grooveforge.jammode':
          debugPrint('RackSlotWidget: returning GFpaJamModeSlotUI');
          return GFpaJamModeSlotUI(plugin: gfpa);
        case 'com.grooveforge.stylophone':
          return GFpaStyloPhoneSlotUI(plugin: gfpa);
        case 'com.grooveforge.theremin':
          return GFpaThereminSlotUI(plugin: gfpa);
        default:
          // Check if this pluginId is a descriptor-backed (.gfpd) plugin.
          final registeredPlugin =
              GFPluginRegistry.instance.findById(gfpa.pluginId);
          if (registeredPlugin is GFMidiDescriptorPlugin) {
            return GFpaMidiFxDescriptorSlotUI(
              instance: gfpa,
              descriptor: registeredPlugin.descriptor,
            );
          }
          if (registeredPlugin is GFDescriptorPlugin) {
            return GFpaDescriptorSlotUI(
              instance: gfpa,
              descriptor: registeredPlugin.descriptor,
            );
          }
          // Unknown plugin — show a non-crashing placeholder.
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

          // ── Keyboard config button — piano-type slots and vocoder
          if (plugin is GrooveForgeKeyboardPlugin ||
              (plugin is GFpaPluginInstance &&
                  (plugin as GFpaPluginInstance).pluginId ==
                      'com.grooveforge.vocoder')) ...[
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
    if (p is GrooveForgeKeyboardPlugin) {
      return p.soundfontPath == kMidiControllerOnlySoundfont
          ? Icons.piano_outlined
          : Icons.piano;
    }
    if (p is LooperPluginInstance) return Icons.loop;
    if (p is Vst3PluginInstance) {
      // Effect and analyzer plugins use a wand icon to distinguish them from
      // instrument slots (generic extension icon).
      switch (p.pluginType) {
        case Vst3PluginType.effect:
        case Vst3PluginType.analyzer:
          return Icons.auto_fix_high;
        case Vst3PluginType.instrument:
          return Icons.extension;
      }
    }
    if (p is GFpaPluginInstance) {
      switch (p.pluginId) {
        case 'com.grooveforge.keyboard': return Icons.piano;
        case 'com.grooveforge.vocoder': return Icons.mic;
        case 'com.grooveforge.jammode': return Icons.link;
        case 'com.grooveforge.stylophone': return Icons.linear_scale;
        case 'com.grooveforge.theremin': return Icons.sensors;
        case 'com.grooveforge.reverb': return Icons.blur_on;
        case 'com.grooveforge.delay': return Icons.repeat;
        case 'com.grooveforge.wah': return Icons.graphic_eq;
        case 'com.grooveforge.eq': return Icons.equalizer;
        case 'com.grooveforge.compressor': return Icons.compress;
        case 'com.grooveforge.chorus': return Icons.waves;
      }
      // Generic icon for any other descriptor-backed plugin.
      if (GFPluginRegistry.instance.findById(p.pluginId) is GFDescriptorPlugin) {
        return Icons.tune;
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

/// True when this slot's on-screen keyboard acts as a MIDI-only controller
/// (no internal FluidSynth on its channel).
bool _routesMidiThroughCablesOnly(PluginInstance plugin) {
  return plugin is GrooveForgeKeyboardPlugin &&
      plugin.soundfontPath == kMidiControllerOnlySoundfont;
}

// ─── Piano (full channel logic, adapted for rack slot) ───────────────────────

/// Layer-1 widget: subscribes only to configuration notifiers.
///
/// Resolves the per-slot [KeyboardDisplayConfig], gesture actions, valid pitch
/// classes, and the GFPA Jam entry for this channel, then hands the resolved
/// values to [_PianoBody]. Cross-channel notifiers are deliberately absent
/// from this listener — that work is delegated to [_PianoBody] (layer 2/3).
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
    if (plugin is GFpaPluginInstance) {
      return (plugin as GFpaPluginInstance).keyboardConfig;
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
          // Cross-channel notifiers removed: followers subscribe to exactly one
          // master-channel notifier inside _PianoBody (layer 2), and
          // non-followers skip straight to the activeNotes layer (layer 3).
        ]),
        builder: (context, _) {
          // Resolve effective values: per-slot config overrides global prefs.
          final cfg = _keyboardConfig;
          final keysToShow = cfg?.keysToShow ?? engine.pianoKeysToShow.value;
          final vAction =
              cfg?.verticalGestureAction ?? engine.verticalGestureAction.value;
          final hAction = cfg?.horizontalGestureAction ??
              engine.horizontalGestureAction.value;
          final validPcs = state.validPitchClasses.value;

          // Determine whether this slot is a GFPA Jam follower.
          final gfpaEntry = engine.gfpaJamEntries.value
              .where((e) => e.followerCh == channelIndex)
              .firstOrNull;

          return _PianoBody(
            engine: engine,
            channelIndex: channelIndex,
            plugin: plugin,
            gfpaEntry: gfpaEntry,
            keysToShow: keysToShow,
            vAction: vAction,
            hAction: hAction,
            validPcs: validPcs,
            keyboardConfig: cfg,
          );
        },
      ),
    );
  }
}

/// Layer-2/3 widget: inserts a Jam-context listener only for GFPA followers.
///
/// **Non-follower** (layer 3 only): subscribes to its own channel's
/// [ChannelState.activeNotes] via [ValueListenableBuilder] and builds
/// [VirtualPiano] directly.  A note on any other channel causes zero rebuilds
/// here.
///
/// **Follower** (layers 2 + 3): wraps a [ListenableBuilder] that subscribes
/// to exactly one master-channel notifier — [ChannelState.activeNotes] in
/// bass-note mode, [ChannelState.lastChord] otherwise.  This computes [rootPc]
/// for key highlighting and then passes it down to the [ValueListenableBuilder]
/// for the own-notes layer.
class _PianoBody extends StatelessWidget {
  final AudioEngine engine;
  final int channelIndex;
  final PluginInstance plugin;

  /// Jam follower entry for this channel, or null if not a follower.
  final GFpaJamEntry? gfpaEntry;

  final int keysToShow;
  final GestureAction vAction;
  final GestureAction hAction;

  /// Valid pitch classes for scale highlighting on this channel.
  final Set<int>? validPcs;

  /// Per-slot keyboard config, used for the aftertouch CC remap.
  final KeyboardDisplayConfig? keyboardConfig;

  const _PianoBody({
    required this.engine,
    required this.channelIndex,
    required this.plugin,
    required this.gfpaEntry,
    required this.keysToShow,
    required this.vAction,
    required this.hAction,
    required this.validPcs,
    required this.keyboardConfig,
  });

  @override
  Widget build(BuildContext context) {
    final ownState = engine.channels[channelIndex];

    if (gfpaEntry == null) {
      // Fast path: not a Jam follower — only this slot's own activeNotes matters.
      return ValueListenableBuilder<Set<int>>(
        valueListenable: ownState.activeNotes,
        builder: (ctx, activeNotes, _) =>
            _buildPiano(ctx, activeNotes, rootPitchClass: null),
      );
    }

    // Follower path: subscribe to the specific master-channel notifier only.
    // Using activeNotes in bass-note mode (lowest held note → root pitch class),
    // or lastChord in chord-detection mode.
    final masterState = engine.channels[gfpaEntry!.masterCh];
    final Listenable masterNotifier = gfpaEntry!.bassNoteMode
        ? masterState.activeNotes
        : masterState.lastChord;

    return ListenableBuilder(
      listenable: masterNotifier,
      builder: (ctx, _) {
        final rootPc = _computeRootPc(masterState);
        return ValueListenableBuilder<Set<int>>(
          valueListenable: ownState.activeNotes,
          builder: (ctx, activeNotes, _) =>
              _buildPiano(ctx, activeNotes, rootPitchClass: rootPc),
        );
      },
    );
  }

  /// Derives the root pitch class from the master channel for key highlighting.
  ///
  /// In bass-note mode: lowest active MIDI note mod 12.
  /// In chord mode: root pitch class from the last detected chord.
  /// Returns null when no input is present.
  int? _computeRootPc(ChannelState masterState) {
    if (gfpaEntry!.bassNoteMode) {
      final active = masterState.activeNotes.value;
      if (active.isNotEmpty) {
        return active.reduce((a, b) => a < b ? a : b) % 12;
      }
      return null;
    }
    return masterState.lastChord.value?.rootPc;
  }

  /// Builds the [VirtualPiano] leaf widget with all gesture and MIDI callbacks.
  Widget _buildPiano(
    BuildContext context,
    Set<int> activeNotes, {
    required int? rootPitchClass,
  }) {
    return VirtualPiano(
      activeNotes: activeNotes,
      verticalAction: vAction,
      horizontalAction: hAction,
      keysToShow: keysToShow,
      validPitchClasses: gfpaEntry != null ? validPcs : null,
      rootPitchClass: rootPitchClass,
      showJamModeBorders: engine.showJamModeBorders.value,
      highlightWrongNotes: engine.highlightWrongNotes.value,
      onNotePressed: (note) => _onNotePressed(context, note),
      onNoteReleased: (note) => _onNoteReleased(context, note),
      onPitchBend: (val) => _onPitchBend(context, val),
      onControlChange: (cc, val) => _onControlChange(context, cc, val),
      onInteractingChanged: engine.updateGestureState,
    );
  }

  // ─── Note event routing ──────────────────────────────────────────────────

  /// Handles a note-on event from the on-screen piano keyboard.
  ///
  /// Routing logic per plugin type:
  /// - **MIDI-only GFK** ([kMidiControllerOnlySoundfont]): highlights keys and
  ///   forwards notes through MIDI OUT cables (no internal FluidSynth).
  /// - [Vst3PluginInstance]: sends via [VstHostService] (bypasses FluidSynth)
  ///   and marks the key as active on the engine for UI highlighting.
  /// - **Other slots**: MIDI FX chain (if any) then [AudioEngine.playNote] plus
  ///   looper feed on MIDI OUT.
  void _onNotePressed(BuildContext context, int note) {
    final midiOnly = _routesMidiThroughCablesOnly(plugin);
    if (midiOnly) {
      engine.noteOnUiOnly(channel: channelIndex, key: note);
      _dispatchMidiNoteOn(context, note);
    } else if (plugin is Vst3PluginInstance) {
      // VST3 audio goes to VstHostService; engine only tracks UI state.
      context.read<VstHostService>().noteOn(plugin.id, 0, note, 1.0);
      engine.noteOnUiOnly(channel: channelIndex, key: note);
    } else {
      // Route through any MIDI FX connected via patch cable (e.g. harmonizer)
      // before playing. Harmony notes are played on the same channel.
      final midiEvents = _applyMidiChain(context, note, 100);
      for (final e in midiEvents) {
        engine.playNote(channel: channelIndex, key: e.data1, velocity: e.data2);
      }
      // Also feed any loopers connected to this slot's MIDI OUT so
      // on-screen keys are captured by the looper (e.g. GFK → Looper cable).
      _feedConnectedLoopers(context, note, 100, isNoteOn: true);
    }
  }

  /// Handles a note-off event from the on-screen piano keyboard.
  void _onNoteReleased(BuildContext context, int note) {
    if (_routesMidiThroughCablesOnly(plugin)) {
      engine.noteOffUiOnly(channel: channelIndex, key: note);
      _dispatchMidiNoteOff(context, note);
    } else if (plugin is Vst3PluginInstance) {
      context.read<VstHostService>().noteOff(plugin.id, 0, note);
      engine.noteOffUiOnly(channel: channelIndex, key: note);
    } else {
      // Symmetric note-off for every voice the MIDI FX added at note-on time.
      for (final e in _applyMidiChain(context, note, 0)) {
        engine.stopNote(channel: channelIndex, key: e.data1);
      }
      // Mirror the note-on looper feed for note-off so held notes are
      // properly terminated in the recorded loop.
      _feedConnectedLoopers(context, note, 0, isNoteOn: false);
    }
  }

  /// Routes [note] through any MIDI FX slots wired to this slot's MIDI OUT jack.
  ///
  /// Returns the processed event list. When [velocity] > 0 the event is a
  /// note-on (status 0x9n); when [velocity] == 0 it is a note-off (status
  /// 0x8n) so harmonizers emit the correct symmetric note-off for each voice
  /// they added during the corresponding note-on.
  ///
  /// When no MIDI FX are connected the list contains the single original event
  /// unchanged, so the caller can always iterate without a special-case check.
  List<TimestampedMidiEvent> _applyMidiChain(
    BuildContext context,
    int note,
    int velocity,
  ) {
    // Use note-off status (0x80) for velocity=0, note-on (0x90) otherwise.
    final status = velocity > 0
        ? (0x90 | (channelIndex & 0x0F))
        : (0x80 | (channelIndex & 0x0F));

    final event = TimestampedMidiEvent(
      ppqPosition: 0.0,
      status: status,
      data1: note,
      data2: velocity,
    );

    // Find MIDI FX plugins wired to this slot's MIDI OUT jack.
    final rack = context.read<RackState>();
    final cables = _midiOutCables(context);
    final chain = cables
        .map((cable) => rack.midiFxInstanceForSlot(cable.toSlotId))
        .whereType<GFMidiDescriptorPlugin>()
        .toList(growable: false);

    if (chain.isEmpty) return [event];

    // Run events through each MIDI FX in cable order.
    final transport = context.read<TransportEngine>().toGFTransportContext();
    var events = <TimestampedMidiEvent>[event];
    for (final fx in chain) {
      events = fx.processMidi(events, transport);
    }
    return events;
  }

  /// Forwards a MIDI note-on event to all slots wired to this slot's MIDI OUT
  /// jack. Used for MIDI-only GFK slots.
  ///
  /// Each connected target is routed according to its type:
  /// - [LooperPluginInstance] → [LooperEngine.feedMidiEvent] (records the note)
  /// - VST3 → [VstHostService.noteOn] + [AudioEngine.noteOnUiOnly]
  /// - FluidSynth (GFK, Vocoder, generic GFPA) → [AudioEngine.playNote]
  void _dispatchMidiNoteOn(BuildContext context, int note) {
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
  void _dispatchMidiNoteOff(BuildContext context, int note) {
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
  /// - **MIDI-only GFK**: bend is forwarded through MIDI OUT cables.
  /// - **[Vst3PluginInstance]**: dispatched to [VstHostService] (no-op until
  ///   the native binding is added; avoids incorrect FluidSynth bend).
  /// - **All others** (GFK with synth, vocoder, GFPA): sent directly to [AudioEngine].
  void _onPitchBend(BuildContext context, int rawValue) {
    if (_routesMidiThroughCablesOnly(plugin)) {
      _dispatchMidiPitchBend(context, rawValue);
    } else if (plugin is Vst3PluginInstance) {
      final semitones = (rawValue - 8192) / 8192.0 * 2.0;
      context.read<VstHostService>().pitchBend(plugin.id, 0, semitones);
    } else {
      engine.setPitchBend(channel: channelIndex, value: rawValue);
    }
  }

  /// Handles a control-change gesture from the on-screen piano.
  ///
  /// Same routing logic as [_onPitchBend].
  ///
  /// CC 1 (vibrato gesture) is remapped to the per-slot aftertouch destination
  /// when a [KeyboardDisplayConfig] override is active; otherwise it falls back
  /// to [AudioEngine.aftertouchDestCc].
  void _onControlChange(BuildContext context, int cc, int value) {
    // Remap CC 1 (the vibrato-gesture default) to the effective aftertouch CC.
    final effectiveCc = (cc == 1)
        ? (keyboardConfig?.aftertouchDestCc ?? engine.aftertouchDestCc.value)
        : cc;

    if (_routesMidiThroughCablesOnly(plugin)) {
      _dispatchMidiCC(context, effectiveCc, value);
    } else if (plugin is Vst3PluginInstance) {
      context.read<VstHostService>().controlChange(plugin.id, 0, effectiveCc, value);
    } else {
      engine.setControlChange(
          channel: channelIndex, controller: effectiveCc, value: value);
    }
  }

  /// Forwards a pitch-bend value through every slot wired to this MIDI source's OUT.
  ///
  /// Converts the raw 14-bit value to semitones when the target is VST3,
  /// and reconstructs the correct 14-bit word for FluidSynth channels.
  void _dispatchMidiPitchBend(BuildContext context, int rawValue) {
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

  /// Forwards CC through every slot wired to this MIDI source's MIDI OUT.
  void _dispatchMidiCC(BuildContext context, int cc, int value) {
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
