import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/gfpa_plugin_instance.dart';
import '../models/plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/vst3_plugin_instance.dart';
import '../plugins/gf_vocoder_plugin.dart';
import 'audio_engine.dart';
import 'transport_engine.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Manages the ordered list of plugin slots in the GrooveForge rack.
///
/// Each [PluginInstance] in [plugins] corresponds to one synthesizer lane
/// with its own MIDI channel and sound source. Per-slot Jam Mode configuration
/// (enabled flag + chosen master slot) is stored on [GrooveForgeKeyboardPlugin]
/// and synced to [AudioEngine.jamFollowerMap] after every mutation.
///
/// Persistence is handled externally by [ProjectService], which calls
/// [toJson] / [loadFromJson] and manages .gf file I/O. [RackState] itself
/// notifies an optional [onChanged] callback after every mutation so that
/// the project service can trigger an autosave.
class RackState extends ChangeNotifier {
  final AudioEngine _engine;
  final TransportEngine _transport;

  final List<PluginInstance> _plugins = [];

  /// Called after every mutation; use to trigger autosave.
  VoidCallback? onChanged;

  RackState(this._engine, this._transport) {
    _engine.transportProvider = () => GFTransportContext(
      bpm: _transport.bpm,
      timeSigNumerator: _transport.timeSigNumerator,
      timeSigDenominator: _transport.timeSigDenominator,
      isPlaying: _transport.isPlaying,
      isRecording: _transport.isRecording,
      positionInBeats: _transport.positionInBeats,
    );
  }

  /// Read-only view of the current plugin list (in display order).
  List<PluginInstance> get plugins => List.unmodifiable(_plugins);

  int get pluginCount => _plugins.length;

  // ─── Initialisation ───────────────────────────────────────────────────────

  /// Populates the rack from a JSON list (e.g., loaded from a .gf file).
  void loadFromJson(List<dynamic> pluginsJson) {
    _plugins.clear();
    for (final entry in pluginsJson) {
      try {
        _plugins.add(PluginInstance.fromJson(entry as Map<String, dynamic>));
      } catch (e) {
        debugPrint('RackState: skipping unknown plugin entry — $e');
      }
    }
    _applyAllPluginsToEngine();
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Creates the factory defaults: two independent GrooveForge Keyboard slots
  /// (ch 1 = melody / right hand, ch 2 = harmony / left hand) plus a Jam Mode
  /// slot pre-configured with ch 2 as master and ch 1 as target, inactive by
  /// default so the user opts in by pressing the LED button.
  void initDefaults() {
    _plugins.clear();

    final ch0 = _engine.channels[0];
    _plugins.add(
      GrooveForgeKeyboardPlugin(
        id: 'slot-0',
        midiChannel: 1,
        soundfontPath: ch0.soundfontPath,
        bank: ch0.bank,
        program: ch0.program,
      ),
    );

    final ch1 = _engine.channels[1];
    _plugins.add(
      GrooveForgeKeyboardPlugin(
        id: 'slot-1',
        midiChannel: 2,
        soundfontPath: ch1.soundfontPath,
        bank: ch1.bank,
        program: ch1.program,
      ),
    );

    // Jam Mode slot: ch2 drives the harmony, ch1 follows.
    // Starts inactive so the user consciously enables it.
    _plugins.add(
      GFpaPluginInstance(
        id: 'slot-jam-0',
        pluginId: 'com.grooveforge.jammode',
        midiChannel: 0,
        masterSlotId: 'slot-1',
        targetSlotIds: ['slot-0'],
        state: {
          'enabled': false,
          'scaleType': 'standard',
          'detectionMode': 'chord',
          'bpmLockBeats': 0,
        },
      ),
    );

    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  // ─── Mutations ────────────────────────────────────────────────────────────

  void addPlugin(PluginInstance plugin) {
    _plugins.add(plugin);
    if (plugin is GrooveForgeKeyboardPlugin) {
      _applyPluginToEngine(plugin);
    } else if (plugin is GFpaPluginInstance) {
      _applyGfpaPluginToEngine(plugin);
    }
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  void removePlugin(String id) {
    // Clear references to the removed slot on all dependent plugins.
    for (final p in _plugins) {
      if (p is GFpaPluginInstance) {
        if (p.masterSlotId == id) p.masterSlotId = null;
        p.targetSlotIds.remove(id);
      }
    }
    _plugins.removeWhere((p) => p.id == id);
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Called by [ReorderableListView] — adjusts the index per Flutter's
  /// convention where the new index accounts for the removal of the old item.
  void reorderPlugins(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    final item = _plugins.removeAt(oldIndex);
    _plugins.insert(newIndex, item);
    notifyListeners();
    _notifyChanged();
  }

  /// Update the MIDI channel of a slot.
  void setPluginMidiChannel(String id, int midiChannel) {
    final plugin = _findById(id);
    if (plugin == null) return;
    plugin.midiChannel = midiChannel;
    if (plugin is GrooveForgeKeyboardPlugin) _applyPluginToEngine(plugin);
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Update the soundfont, bank, and patch for a GrooveForge Keyboard slot.
  void setPluginSoundfont(String id, String? soundfontPath) {
    final plugin = _findGKById(id);
    if (plugin == null) return;
    plugin.soundfontPath = soundfontPath;
    _applyPluginToEngine(plugin);
    notifyListeners();
    _notifyChanged();
  }

  void setPluginPatch(String id, int program, {int? bank}) {
    final plugin = _findGKById(id);
    if (plugin == null) return;
    plugin.program = program;
    if (bank != null) plugin.bank = bank;
    _engine.assignPatchToChannel(
      plugin.midiChannel - 1,
      program,
      bank: bank,
    );
    notifyListeners();
    _notifyChanged();
  }


  /// Persist a VST3 parameter value change in the rack model for .gf saving.
  void setVst3Parameter(String id, int paramId, double value) {
    final plugin = _findById(id);
    if (plugin is! Vst3PluginInstance) return;
    plugin.parameters[paramId] = value;
    _notifyChanged();
  }

  /// Snapshot the engine's current vocoder params into a GFPA vocoder slot's
  /// [GFpaPluginInstance.state] so they are persisted in .gf files.
  void snapshotGfpaVocoderParams(String id) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.vocoder') return;
    final registry = GFPluginRegistry.instance;
    final gfPlugin = registry.findById('com.grooveforge.vocoder');
    if (gfPlugin is GFVocoderPlugin) {
      gfPlugin.snapshotFromEngine();
      plugin.state = gfPlugin.getState();
    } else {
      // Fallback: read directly from engine notifiers.
      plugin.state = {
        'waveform': _engine.vocoderWaveform.value,
        'noiseMix': _engine.vocoderNoiseMix.value,
        'envRelease': _engine.vocoderEnvRelease.value,
        'bandwidth': _engine.vocoderBandwidth.value,
        'gateThreshold': _engine.vocoderGateThreshold.value,
        'inputGain': _engine.vocoderInputGain.value,
      };
    }
  }

  /// Update the master slot for a Jam Mode GFPA slot.
  void setJamModeMaster(String id, String? masterSlotId) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    plugin.masterSlotId = masterSlotId;
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Add a target slot to a Jam Mode GFPA slot (multi-target support).
  void addJamModeTarget(String id, String targetSlotId) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    if (!plugin.targetSlotIds.contains(targetSlotId)) {
      plugin.targetSlotIds.add(targetSlotId);
    }
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Remove a target slot from a Jam Mode GFPA slot.
  void removeJamModeTarget(String id, String targetSlotId) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    plugin.targetSlotIds.remove(targetSlotId);
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Toggle the enabled state of a GFPA Jam Mode slot.
  void setJamModeEnabled(String id, {required bool enabled}) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    plugin.state = {...plugin.state, 'enabled': enabled};
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }


  /// Update the full state map of a GFPA plugin slot (triggers autosave).
  void setGfpaPluginState(String id, Map<String, dynamic> state) {
    final plugin = _findGfpaById(id);
    if (plugin == null) return;
    plugin.state = state;
    // Re-sync the engine immediately so scale/detection-mode changes take
    // effect without requiring a stop/restart of Jam Mode.
    if (plugin.pluginId == 'com.grooveforge.jammode') {
      _syncJamFollowerMapToEngine();
    }
    _notifyChanged();
  }

  // ─── Serialisation ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> toJson() =>
      _plugins.map((p) => p.toJson()).toList();

  // ─── Engine sync ──────────────────────────────────────────────────────────

  void _applyAllPluginsToEngine() {
    for (final p in _plugins) {
      if (p is GrooveForgeKeyboardPlugin) {
        _applyPluginToEngine(p);
      } else if (p is GFpaPluginInstance) {
        _applyGfpaPluginToEngine(p);
      }
    }
  }

  void _applyGfpaPluginToEngine(GFpaPluginInstance plugin) {
    switch (plugin.pluginId) {
      case 'com.grooveforge.vocoder':
        if (plugin.midiChannel > 0) {
          _engine.assignSoundfontToChannel(
            plugin.midiChannel - 1,
            'vocoderMode',
          );
          // Restore saved params into the engine.
          final s = plugin.state;
          _engine.vocoderWaveform.value =
              (s['waveform'] as num?)?.toInt() ?? 0;
          _engine.vocoderNoiseMix.value =
              (s['noiseMix'] as num?)?.toDouble() ?? 0.05;
          _engine.vocoderEnvRelease.value =
              (s['envRelease'] as num?)?.toDouble() ?? 0.02;
          _engine.vocoderBandwidth.value =
              (s['bandwidth'] as num?)?.toDouble() ?? 0.2;
          _engine.vocoderGateThreshold.value =
              (s['gateThreshold'] as num?)?.toDouble() ?? 0.01;
          _engine.vocoderInputGain.value =
              (s['inputGain'] as num?)?.toDouble() ?? 1.0;
          _engine.updateVocoderParameters();
        }
    }
  }

  void _applyPluginToEngine(GrooveForgeKeyboardPlugin plugin) {
    final idx = plugin.midiChannel - 1;
    if (idx < 0 || idx > 15) return;

    if (plugin.soundfontPath != null &&
        _engine.loadedSoundfonts.contains(plugin.soundfontPath)) {
      _engine.assignSoundfontToChannel(idx, plugin.soundfontPath!);
    }
    _engine.assignPatchToChannel(idx, plugin.program, bank: plugin.bank);
  }

  /// Syncs jam state to the engine.
  ///
  /// - Legacy [GrooveForgeKeyboardPlugin] slots → [AudioEngine.jamFollowerMap]
  ///   (controlled by the global [AudioEngine.jamEnabled] toggle).
  /// Syncs GFPA Jam Mode slots → [AudioEngine.gfpaJamEntries]
  /// (independent per-slot enable/disable, own scale and detection mode).
  void _syncJamFollowerMapToEngine() {
    final gfpaEntries = <GFpaJamEntry>[];

    for (final p in _plugins) {
      if (p is GFpaPluginInstance &&
          p.pluginId == 'com.grooveforge.jammode') {
        // Slot-level enabled flag (defaults to true when absent).
        if (p.state['enabled'] == false) continue;
        if (p.targetSlotIds.isEmpty || p.masterSlotId == null) continue;
        final master = _findById(p.masterSlotId!);
        if (master == null) continue;
        final masterCh = master.midiChannel - 1;
        if (masterCh < 0 || masterCh >= 16) continue;

        final scaleType = _parseScaleType(p.state['scaleType'] as String?);
        final bassNoteMode = p.state['detectionMode'] == 'bassNote';

        for (final targetId in p.targetSlotIds) {
          final target = _findById(targetId);
          if (target == null) continue;
          final followerCh = target.midiChannel - 1;
          if (followerCh < 0 || followerCh >= 16 || followerCh == masterCh) {
            continue;
          }
          gfpaEntries.add(
            GFpaJamEntry(
              masterCh: masterCh,
              followerCh: followerCh,
              scaleType: scaleType,
              bassNoteMode: bassNoteMode,
            ),
          );
        }
      }
    }

    _engine.gfpaJamEntries.value = gfpaEntries;
  }

  ScaleType _parseScaleType(String? s) {
    if (s == null) return ScaleType.standard;
    return ScaleType.values.firstWhere(
      (v) => v.name == s,
      orElse: () => ScaleType.standard,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  PluginInstance? _findById(String id) {
    try {
      return _plugins.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  GrooveForgeKeyboardPlugin? _findGKById(String id) {
    final p = _findById(id);
    return p is GrooveForgeKeyboardPlugin ? p : null;
  }

  GFpaPluginInstance? _findGfpaById(String id) {
    final p = _findById(id);
    return p is GFpaPluginInstance ? p : null;
  }

  void _notifyChanged() {
    Timer.run(() => onChanged?.call());
  }

  /// Returns the next unused MIDI channel (1–16), or -1 if all are taken.
  /// Slots with [midiChannel] == 0 (MIDI FX / pure effect) are not counted.
  int nextAvailableMidiChannel() {
    final used = _plugins
        .where((p) => p.midiChannel > 0)
        .map((p) => p.midiChannel)
        .toSet();
    for (int ch = 1; ch <= 16; ch++) {
      if (!used.contains(ch)) return ch;
    }
    return -1;
  }

  /// Generates a unique slot ID (e.g. "slot-3").
  String generateSlotId() {
    int n = _plugins.length;
    while (_plugins.any((p) => p.id == 'slot-$n')) {
      n++;
    }
    return 'slot-$n';
  }
}
