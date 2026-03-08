import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/plugin_instance.dart';
import '../models/plugin_role.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import 'audio_engine.dart';

/// Manages the ordered list of plugin slots in the GrooveForge rack.
///
/// Each [PluginInstance] in [plugins] corresponds to one synthesizer lane
/// with its own MIDI channel, sound source, and Jam Mode role. [RackState]
/// keeps the [AudioEngine]'s jam master/slave channel assignments in sync
/// whenever the rack is modified.
///
/// Persistence is handled externally by [ProjectService], which calls
/// [toJson] / [fromJson] and manages .gf file I/O. [RackState] itself
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

  PluginInstance? get masterPlugin => _plugins.firstWhere(
    (p) => p.role == PluginRole.master,
    orElse: () => _plugins.isEmpty ? _dummy : _plugins.first,
  );

  // Sentinel used only when the list is empty — never stored.
  static final _dummy = GrooveForgeKeyboardPlugin(
    id: '__dummy__',
    midiChannel: 1,
    role: PluginRole.master,
  );

  List<PluginInstance> get slavePlugins =>
      _plugins.where((p) => p.role == PluginRole.slave).toList();

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
    _syncJamChannelsToEngine();
    notifyListeners();
  }

  /// Creates the factory defaults: one slave on MIDI channel 1, one master
  /// on MIDI channel 2, both using whatever the engine already has for those
  /// channels (i.e., the default soundfont restored from SharedPreferences).
  void initDefaults() {
    _plugins.clear();

    final ch0 = _engine.channels[0];
    _plugins.add(
      GrooveForgeKeyboardPlugin(
        id: 'slot-0',
        midiChannel: 1,
        role: PluginRole.slave,
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
        role: PluginRole.master,
        soundfontPath: ch1.soundfontPath,
        bank: ch1.bank,
        program: ch1.program,
      ),
    );

    _syncJamChannelsToEngine();
    notifyListeners();
    _notifyChanged();
  }

  // ─── Mutations ────────────────────────────────────────────────────────────

  void addPlugin(PluginInstance plugin) {
    _plugins.add(plugin);
    if (plugin is GrooveForgeKeyboardPlugin) {
      _applyPluginToEngine(plugin);
    }
    _syncJamChannelsToEngine();
    notifyListeners();
    _notifyChanged();
  }

  void removePlugin(String id) {
    _plugins.removeWhere((p) => p.id == id);
    _syncJamChannelsToEngine();
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
    _syncJamChannelsToEngine();
    notifyListeners();
    _notifyChanged();
  }

  /// Toggle a slot between master and slave roles.
  void setPluginRole(String id, PluginRole role) {
    final plugin = _findById(id);
    if (plugin == null) return;
    plugin.role = role;
    _syncJamChannelsToEngine();
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
      // Only assign if the soundfont is actually loaded (or is vocoderMode)
      final isLoaded = plugin.soundfontPath == 'vocoderMode' ||
          _engine.loadedSoundfonts.contains(plugin.soundfontPath);
      if (isLoaded) {
        _engine.assignSoundfontToChannel(idx, plugin.soundfontPath!);
      }
    }
    if (plugin.soundfontPath != 'vocoderMode') {
      _engine.assignPatchToChannel(idx, plugin.program, bank: plugin.bank);
    }
    // If this slot is in vocoder mode, apply its stored vocoder params
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

  /// Derives the engine's jam master/slave channel assignments from the rack's
  /// plugin roles, replacing the old hand-configured dropdowns in JamWidget.
  void _syncJamChannelsToEngine() {
    PluginInstance? master;
    for (final p in _plugins) {
      if (p.role == PluginRole.master) {
        master = p;
        break;
      }
    }
    if (master != null) {
      _engine.jamMasterChannel.value = master.midiChannel - 1;
    }

    final slaves = _plugins
        .where((p) => p.role == PluginRole.slave)
        .map((p) => p.midiChannel - 1)
        .toSet();
    _engine.jamSlaveChannels.value = slaves;
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
    // Defer so that the calling frame can finish its setState first.
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
