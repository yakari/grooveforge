import 'dart:io';

import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:flutter/foundation.dart';

import '../models/audio_port_id.dart';
import '../models/plugin_instance.dart';
import '../models/vst3_plugin_instance.dart';
import 'audio_graph.dart';

/// Desktop VST3 host service.
///
/// Wraps [VstHost] from `dart_vst_host` to provide plugin loading, MIDI
/// routing, parameter control, and ALSA audio output (Linux only).
///
/// One [VstHost] instance is shared for the lifetime of the app. Each loaded
/// plugin is tracked by its rack slot ID so that slot removal is clean.
class VstHostService {
  static final VstHostService instance = VstHostService._();
  VstHostService._();

  bool get isSupported =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  VstHost? _host;

  // Map from rack slot ID → loaded VstPlugin handle.
  final Map<String, VstPlugin> _plugins = {};

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (!isSupported) return;
    if (_host != null) return;
    _host = VstHost.create(sampleRate: 48000.0, maxBlock: 256);
    debugPrint('VstHostService: host created (version: ${_host!.getVersion()})');
  }

  void dispose() {
    stopAudio();
    for (final p in _plugins.values) {
      p.suspend();
      p.unload();
    }
    _plugins.clear();
    _host?.dispose();
    _host = null;
  }

  // ─── Plugin loading ────────────────────────────────────────────────────────

  /// Load a .vst3 plugin from [path] and associate it with [slotId].
  ///
  /// Returns a populated [Vst3PluginInstance] on success, null on failure.
  Future<Vst3PluginInstance?> loadPlugin(String path, String slotId) async {
    if (!isSupported || _host == null) return null;

    try {
      final plugin = _host!.load(path);
      final ok = plugin.resume(sampleRate: 48000.0, maxBlock: 256);
      if (!ok) {
        plugin.unload();
        return null;
      }

      // Suspend and unload any previously loaded plugin for this slot.
      final prevPlugin = _plugins[slotId];
      if (prevPlugin != null) {
        prevPlugin.suspend();
        prevPlugin.unload();
      }
      // Remove old plugin from audio loop if present.
      final old = _plugins[slotId];
      if (old != null && _audioRunning) _host!.removeFromAudioLoop(old);

      _plugins[slotId] = plugin;
      if (_audioRunning) _host!.addToAudioLoop(plugin);

      final name = path.split('/').last.replaceAll('.vst3', '');
      return Vst3PluginInstance(
        id: slotId,
        midiChannel: 1,
        path: path,
        pluginName: name,
      );
    } catch (e) {
      debugPrint('VstHostService: failed to load $path — $e');
      return null;
    }
  }

  void unloadPlugin(String slotId) {
    final plugin = _plugins.remove(slotId);
    if (plugin != null) {
      if (_audioRunning) _host!.removeFromAudioLoop(plugin);
      plugin.suspend();
      plugin.unload();
    }
  }

  void setTransport({
    required double bpm,
    required int timeSigNum,
    required int timeSigDen,
    required bool isPlaying,
    required double positionInBeats,
    required int positionInSamples,
  }) {
    _host?.setTransport(
      bpm: bpm,
      timeSigNum: timeSigNum,
      timeSigDen: timeSigDen,
      isPlaying: isPlaying,
      positionInBeats: positionInBeats,
      positionInSamples: positionInSamples,
    );
  }

  // ─── MIDI routing ──────────────────────────────────────────────────────────

  void noteOn(String slotId, int channel, int note, double velocity) {
    _plugins[slotId]?.noteOn(channel, note, velocity);
  }

  void noteOff(String slotId, int channel, int note) {
    _plugins[slotId]?.noteOff(channel, note, 0.0);
  }

  /// Forwards a pitch-bend message to a VST3 plugin.
  ///
  /// The dart_vst_host native library currently only exposes note on/off via
  /// dvh_note_on / dvh_note_off. Pitch bend for VST3 requires a dvh_pitch_bend
  /// native function — tracked as a future enhancement. No-op until then.
  void pitchBend(String slotId, int channel, double semitones) {
    // TODO(midi-expression): call dvh_pitch_bend once the native binding exists.
  }

  /// Forwards a control-change message to a VST3 plugin.
  ///
  /// Same limitation as [pitchBend] — native CC dispatch is not yet in
  /// dart_vst_host. No-op until the native binding is added.
  void controlChange(String slotId, int channel, int cc, int value) {
    // TODO(midi-expression): call dvh_control_change once the native binding exists.
  }

  // ─── Plugin editor GUI ─────────────────────────────────────────────────────

  /// Open the plugin's native editor window. Returns true if a window was opened.
  bool openEditor(String slotId, {String title = 'Plugin Editor'}) {
    final plugin = _plugins[slotId];
    if (plugin == null) return false;
    
    int windowId = 0;
    if (Platform.isMacOS) {
      windowId = plugin.openMacEditor(title: title);
    } else {
      windowId = plugin.openEditor(title: title);
    }
    
    debugPrint('VstHostService: openEditor slotId=$slotId windowId=$windowId');
    return windowId != 0;
  }

  /// Close the plugin's editor window.
  void closeEditor(String slotId) {
    if (Platform.isMacOS) {
      _plugins[slotId]?.closeMacEditor();
    } else {
      _plugins[slotId]?.closeEditor();
    }
  }

  /// Whether the plugin's editor window is currently open.
  bool isEditorOpen(String slotId) {
    if (Platform.isMacOS) {
      return _plugins[slotId]?.isMacEditorOpen ?? false;
    } else {
      return _plugins[slotId]?.isEditorOpen ?? false;
    }
  }

  // ─── Parameter control ─────────────────────────────────────────────────────

  bool setParameter(String slotId, int paramId, double normalized) =>
      _plugins[slotId]?.setParamNormalized(paramId, normalized) ?? false;

  double getParameter(String slotId, int paramId) =>
      _plugins[slotId]?.getParamNormalized(paramId) ?? 0.0;

  List<VstParamInfo> getParameters(String slotId) {
    final plugin = _plugins[slotId];
    if (plugin == null) return [];

    final count = plugin.paramCount();
    final result = <VstParamInfo>[];
    for (int i = 0; i < count; i++) {
      try {
        final info = plugin.paramInfoAt(i);
        result.add(VstParamInfo(
          id: info.id,
          title: info.title,
          units: info.units,
          unitId: info.unitId,
        ));
      } catch (_) {}
    }
    return result;
  }

  /// Returns a map of unitId → unit name for all declared parameter groups.
  /// Falls back to 'Group N' if the plugin doesn't implement IUnitInfo.
  Map<int, String> getUnitNames(String slotId) {
    final plugin = _plugins[slotId];
    if (plugin == null) return {};
    final count = plugin.unitCount();
    if (count == 0) return {};
    final result = <int, String>{};
    // We don't know unit IDs upfront; collect them from the parameters.
    final params = getParameters(slotId);
    final seenIds = params.map((p) => p.unitId).toSet();
    for (final uid in seenIds) {
      final name = plugin.unitNameForId(uid);
      result[uid] = name ?? (uid == -1 ? 'Root' : 'Group $uid');
    }
    return result;
  }

  // ─── Audio output (Linux ALSA) ─────────────────────────────────────────────

  bool _audioRunning = false;

  void startAudio() {
    if (!isSupported || _audioRunning || _host == null) return;
    // Register all currently loaded plugins with the audio loop.
    _host!.clearAudioLoop();
    for (final p in _plugins.values) {
      _host!.addToAudioLoop(p);
    }
    
    bool ok = false;
    if (Platform.isMacOS) {
      ok = _host!.startMacAudio();
    } else {
      ok = _host!.startAlsaThread();
    }
    
    if (ok) {
      _audioRunning = true;
      debugPrint('VstHostService: Audio thread started (Backend: ${Platform.operatingSystem})');
    } else {
      debugPrint('VstHostService: failed to start audio thread');
    }
  }

  void stopAudio() {
    if (!_audioRunning || _host == null) return;

    if (Platform.isMacOS) {
      _host!.stopMacAudio();
    } else {
      _host!.stopAlsaThread();
    }

    _audioRunning = false;
    debugPrint('VstHostService: Audio thread stopped');
  }

  // ─── Audio graph routing (Phase 5.4) ──────────────────────────────────────

  /// Synchronises the native ALSA processing order and audio routing table
  /// with the current state of the Dart [AudioGraph].
  ///
  /// Should be called whenever:
  ///   - An [AudioGraph] connection is added or removed.
  ///   - A VST3 plugin slot is added or removed from the rack.
  ///
  /// Only VST3 slots (those present in [_plugins]) participate in native
  /// routing. Built-in GFPA slots (FluidSynth, vocoder, Jam Mode) use their
  /// own audio paths and are not routed through the ALSA loop.
  void syncAudioRouting(AudioGraph graph, List<PluginInstance> allPlugins) {
    if (!isSupported || _host == null) return;

    // Build the topological processing order — VST3 slots only.
    final allSlotIds = allPlugins.map((p) => p.id).toList();
    final orderedIds = graph.topologicalOrder(allSlotIds);
    final orderedPlugins = orderedIds
        .map((id) => _plugins[id])
        .whereType<VstPlugin>()
        .toList();

    _host!.setProcessingOrder(orderedPlugins);

    // Rebuild routing table from audio connections between VST3 slots.
    _host!.clearRoutes();
    for (final conn in graph.connections) {
      // Only route audio-family port connections (not MIDI or Data cables).
      if (conn.fromPort.isDataPort || conn.toPort.isDataPort) continue;
      if (conn.fromPort == AudioPortId.midiOut || conn.toPort == AudioPortId.midiIn) continue;

      final from = _plugins[conn.fromSlotId];
      final to   = _plugins[conn.toSlotId];
      if (from == null || to == null) continue; // one or both endpoints not VST3

      _host!.routeAudio(from, to);
      debugPrint(
        'VstHostService: route ${conn.fromSlotId}:${conn.fromPort.name} '
        '→ ${conn.toSlotId}:${conn.toPort.name}',
      );
    }
  }

  // ─── Plugin scanner ────────────────────────────────────────────────────────

  /// Scan [searchPaths] for .vst3 bundles and return their paths.
  Future<List<String>> scanPluginPaths(List<String> searchPaths) async {
    final results = <String>[];
    for (final dir in searchPaths) {
      final d = Directory(dir);
      if (!d.existsSync()) continue;
      try {
        await for (final entity in d.list(recursive: false)) {
          if (entity.path.endsWith('.vst3')) {
            results.add(entity.path);
          }
        }
      } catch (_) {}
    }
    return results;
  }

  /// Default OS search paths for VST3 plugins.
  static List<String> get defaultSearchPaths {
    if (Platform.isLinux) {
      return [
        '${Platform.environment['HOME']}/.vst3',
        '/usr/lib/vst3',
        '/usr/local/lib/vst3',
      ];
    }
    if (Platform.isMacOS) {
      return [
        '${Platform.environment['HOME']}/Library/Audio/Plug-Ins/VST3',
        '/Library/Audio/Plug-Ins/VST3',
      ];
    }
    if (Platform.isWindows) {
      return [r'C:\Program Files\Common Files\VST3'];
    }
    return [];
  }
}

/// Describes a single VST3 parameter (ID, display name, unit string, group).
class VstParamInfo {
  final int id;
  final String title;
  final String units;
  final int unitId;

  const VstParamInfo({
    required this.id,
    required this.title,
    required this.units,
    this.unitId = -1,
  });
}

