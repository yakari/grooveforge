import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/gfpa_plugin_instance.dart';
import '../models/keyboard_display_config.dart';
import '../models/looper_plugin_instance.dart';
import '../models/plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/virtual_piano_plugin.dart';
import '../models/vst3_plugin_instance.dart';
import '../plugins/gf_vocoder_plugin.dart';
import 'audio_engine.dart';
import 'audio_graph.dart';
import 'transport_engine.dart';
import 'vst_host_service_desktop.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Manages the ordered list of plugin slots in the GrooveForge rack.
///
/// Each [PluginInstance] in [plugins] corresponds to one synthesizer lane
/// with its own MIDI channel and sound source. Per-slot Jam Mode configuration
/// (enabled flag + chosen master slot) is stored on [GFpaPluginInstance]
/// and synced to [AudioEngine.jamFollowerMap] after every mutation.
///
/// When a slot is deleted, [RackState] also notifies [AudioGraph] so that any
/// dangling MIDI/Audio cables connected to the removed slot are cleaned up.
///
/// Persistence is handled externally by [ProjectService], which calls
/// [toJson] / [loadFromJson] and manages .gf file I/O. [RackState] itself
/// notifies an optional [onChanged] callback after every mutation so that
/// the project service can trigger an autosave.
class RackState extends ChangeNotifier {
  final AudioEngine _engine;
  final TransportEngine _transport;
  final AudioGraph _audioGraph;

  final List<PluginInstance> _plugins = [];

  /// Called after every mutation; use to trigger autosave.
  VoidCallback? onChanged;

  // Tracks transport settings to detect user-driven changes and trigger
  // autosave (TransportEngine.notifyListeners is not otherwise wired into
  // RackState.onChanged).
  bool _lastMetronomeEnabled = false;
  double _lastBpm = 120.0;
  int _lastTimeSigNumerator = 4;
  int _lastTimeSigDenominator = 4;

  // Debounce timer for BPM saves — nudge fires every 80 ms so we wait until
  // the user stops adjusting before persisting.
  Timer? _bpmSaveDebounce;

  RackState(this._engine, this._transport, this._audioGraph) {
    _engine.bpmProvider = () => _transport.bpm;
    _engine.isPlayingProvider = () => _transport.isPlaying;
    _transport.onBeat = (bool isDownbeat) {
      if (_transport.metronomeEnabled) {
        _engine.playMetronomeClick(isDownbeat);
      }
    };
    _lastMetronomeEnabled = _transport.metronomeEnabled;
    _lastBpm = _transport.bpm;
    _lastTimeSigNumerator = _transport.timeSigNumerator;
    _lastTimeSigDenominator = _transport.timeSigDenominator;
    _transport.addListener(_onTransportChanged);
    // Phase 5.4: whenever the audio graph changes, push the new topological
    // order and routing rules to the native ALSA/CoreAudio processing loop.
    _audioGraph.addListener(_onAudioGraphChanged);
  }

  /// Called whenever the [AudioGraph] changes (connection added/removed).
  ///
  /// Pushes the updated topological processing order and routing table to the
  /// native audio loop so audio flows through the new cable configuration
  /// immediately without restarting the ALSA/CoreAudio thread.
  void _onAudioGraphChanged() {
    VstHostService.instance.syncAudioRouting(_audioGraph, _plugins);
  }

  void _onTransportChanged() {
    bool saveNow = false;

    // Metronome toggle — save immediately.
    if (_transport.metronomeEnabled != _lastMetronomeEnabled) {
      _lastMetronomeEnabled = _transport.metronomeEnabled;
      saveNow = true;
    }

    // Time signature — save immediately.
    if (_transport.timeSigNumerator != _lastTimeSigNumerator ||
        _transport.timeSigDenominator != _lastTimeSigDenominator) {
      _lastTimeSigNumerator = _transport.timeSigNumerator;
      _lastTimeSigDenominator = _transport.timeSigDenominator;
      saveNow = true;
    }

    if (saveNow) Timer.run(() => onChanged?.call());

    // BPM — debounced: save 1.5 s after the user stops nudging/typing.
    if (_transport.bpm != _lastBpm) {
      _lastBpm = _transport.bpm;
      _bpmSaveDebounce?.cancel();
      _bpmSaveDebounce = Timer(
        const Duration(milliseconds: 1500),
        () => onChanged?.call(),
      );
    }
  }

  @override
  void dispose() {
    _bpmSaveDebounce?.cancel();
    _transport.removeListener(_onTransportChanged);
    _audioGraph.removeListener(_onAudioGraphChanged);
    super.dispose();
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
    // Sync native routing: new slot may alter the topological sort order.
    VstHostService.instance.syncAudioRouting(_audioGraph, _plugins);
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
    // Inform the AudioGraph so any MIDI/Audio cables connected to the
    // removed slot are automatically cleaned up (fires _onAudioGraphChanged
    // if any connections were removed).
    _audioGraph.onSlotRemoved(id);
    _syncJamFollowerMapToEngine();
    // Sync native routing even if no cables pointed to the removed slot.
    VstHostService.instance.syncAudioRouting(_audioGraph, _plugins);
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


  /// Update the per-slot keyboard display and expression config.
  ///
  /// Pass `null` as [config] to clear all overrides and revert to global prefs.
  /// Changes are persisted immediately via the autosave callback.
  void setKeyboardConfig(String id, KeyboardDisplayConfig? config) {
    final plugin = _findById(id);
    if (plugin is GrooveForgeKeyboardPlugin) {
      plugin.keyboardConfig = config;
    } else if (plugin is VirtualPianoPlugin) {
      plugin.keyboardConfig = config;
    } else if (plugin is GFpaPluginInstance) {
      // Only vocoder GFPA slots have an embedded piano that can be configured.
      plugin.keyboardConfig = config;
    } else {
      return;
    }
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

  /// Toggles whether a [GFpaPluginInstance] Jam Mode slot is pinned below the
  /// transport bar for quick access.
  void toggleJamModePinned(String id) {
    final plugin = _findGfpaById(id);
    if (plugin == null || plugin.pluginId != 'com.grooveforge.jammode') return;
    plugin.pinned = !plugin.pinned;
    notifyListeners();
    _notifyChanged();
  }

  /// Toggles whether a [LooperPluginInstance] is pinned below the transport bar.
  void toggleLooperPinned(String id) {
    final plugin = plugins.whereType<LooperPluginInstance>().where((p) => p.id == id).firstOrNull;
    if (plugin == null) return;
    plugin.pinned = !plugin.pinned;
    notifyListeners();
    _notifyChanged();
  }

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
        final bpmLockBeats =
            (p.state['bpmLockBeats'] as num?)?.toInt().clamp(0, 4) ?? 0;

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
              bpmLockBeats: bpmLockBeats,
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

  /// Public helper for plugin slot widgets that need to trigger both a
  /// [notifyListeners] rebuild and an autosave without calling the protected
  /// [notifyListeners] directly from outside this class.
  void markDirty() {
    notifyListeners();
    _notifyChanged();
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
