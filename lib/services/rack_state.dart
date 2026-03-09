import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/vst3_plugin_instance.dart';
import 'audio_engine.dart';

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

  final List<PluginInstance> _plugins = [];

  /// Called after every mutation; use to trigger autosave.
  VoidCallback? onChanged;

  RackState(this._engine);

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
  }

  /// Creates the factory defaults: two independent GrooveForge Keyboard slots
  /// with no Jam following configured (users opt in per-slot).
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

    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  // ─── Mutations ────────────────────────────────────────────────────────────

  void addPlugin(PluginInstance plugin) {
    _plugins.add(plugin);
    if (plugin is GrooveForgeKeyboardPlugin) {
      _applyPluginToEngine(plugin);
    }
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  void removePlugin(String id) {
    // Clear jamMasterSlotId references to the removed slot on other plugins.
    for (final p in _plugins) {
      if (p is GrooveForgeKeyboardPlugin && p.jamMasterSlotId == id) {
        p.jamMasterSlotId = null;
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

  /// Enable or disable Jam following on a slot, optionally setting the master
  /// at the same time.
  void setPluginJamEnabled(
    String id, {
    required bool enabled,
    String? masterSlotId,
  }) {
    final plugin = _findGKById(id);
    if (plugin == null) return;
    plugin.jamEnabled = enabled;
    if (masterSlotId != null) plugin.jamMasterSlotId = masterSlotId;
    _syncJamFollowerMapToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Change the master slot that a follower slot is watching.
  void setPluginJamMaster(String id, String? masterSlotId) {
    final plugin = _findGKById(id);
    if (plugin == null) return;
    plugin.jamMasterSlotId = masterSlotId;
    _syncJamFollowerMapToEngine();
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

  /// Snapshot the engine's current vocoder parameters into a GK plugin's
  /// state (called when the slot is in vocoder mode so .gf saves the latest).
  void snapshotVocoderParams(String id) {
    final plugin = _findGKById(id);
    if (plugin == null || !plugin.isVocoderMode) return;
    plugin.vocoderWaveform = _engine.vocoderWaveform.value;
    plugin.vocoderNoiseMix = _engine.vocoderNoiseMix.value;
    plugin.vocoderEnvRelease = _engine.vocoderEnvRelease.value;
    plugin.vocoderBandwidth = _engine.vocoderBandwidth.value;
    plugin.vocoderGateThreshold = _engine.vocoderGateThreshold.value;
    plugin.vocoderInputGain = _engine.vocoderInputGain.value;
  }

  // ─── Serialisation ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> toJson() =>
      _plugins.map((p) => p.toJson()).toList();

  // ─── Engine sync ──────────────────────────────────────────────────────────

  void _applyAllPluginsToEngine() {
    for (final p in _plugins) {
      if (p is GrooveForgeKeyboardPlugin) _applyPluginToEngine(p);
    }
  }

  void _applyPluginToEngine(GrooveForgeKeyboardPlugin plugin) {
    final idx = plugin.midiChannel - 1;
    if (idx < 0 || idx > 15) return;

    if (plugin.soundfontPath != null) {
      final isLoaded = plugin.soundfontPath == 'vocoderMode' ||
          _engine.loadedSoundfonts.contains(plugin.soundfontPath);
      if (isLoaded) {
        _engine.assignSoundfontToChannel(idx, plugin.soundfontPath!);
      }
    }
    if (plugin.soundfontPath != 'vocoderMode') {
      _engine.assignPatchToChannel(idx, plugin.program, bank: plugin.bank);
    }
    if (plugin.isVocoderMode) {
      _engine.vocoderWaveform.value = plugin.vocoderWaveform;
      _engine.vocoderNoiseMix.value = plugin.vocoderNoiseMix;
      _engine.vocoderEnvRelease.value = plugin.vocoderEnvRelease;
      _engine.vocoderBandwidth.value = plugin.vocoderBandwidth;
      _engine.vocoderGateThreshold.value = plugin.vocoderGateThreshold;
      _engine.vocoderInputGain.value = plugin.vocoderInputGain;
      _engine.updateVocoderParameters();
    }
  }

  /// Builds the follower map from the current rack's per-slot jam configuration
  /// and pushes it to [AudioEngine.jamFollowerMap].
  ///
  /// follower channel (0-indexed) → master channel (0-indexed).
  void _syncJamFollowerMapToEngine() {
    final map = <int, int>{};

    for (final p in _plugins) {
      if (p is! GrooveForgeKeyboardPlugin) continue;
      if (!p.jamEnabled || p.jamMasterSlotId == null) continue;

      final master = _findById(p.jamMasterSlotId!);
      if (master == null) continue;

      final followerCh = p.midiChannel - 1;
      final masterCh = master.midiChannel - 1;
      if (followerCh >= 0 && followerCh < 16 &&
          masterCh >= 0 && masterCh < 16 &&
          followerCh != masterCh) {
        map[followerCh] = masterCh;
      }
    }

    _engine.jamFollowerMap.value = map;
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

  void _notifyChanged() {
    Timer.run(() => onChanged?.call());
  }

  /// Returns the next unused MIDI channel (1-16), or -1 if all are taken.
  int nextAvailableMidiChannel() {
    final used = _plugins.map((p) => p.midiChannel).toSet();
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
