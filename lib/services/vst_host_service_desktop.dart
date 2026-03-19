import 'dart:ffi';
import 'dart:io';

import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:flutter/foundation.dart';

import '../models/audio_port_id.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/plugin_instance.dart';
import '../models/vst3_plugin_instance.dart';
// Vst3PluginType used in loadPlugin signature.
export '../models/vst3_plugin_instance.dart' show Vst3PluginType;
import 'audio_graph.dart';
import 'audio_input_ffi_native.dart';

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

  // Map from rack slot ID → native GFPA DSP handle (Pointer<Void>).
  // Populated by registerGfpaDsp() when a descriptor effect slot becomes active.
  final Map<String, Pointer<Void>> _gfpaHandles = {};

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
    // Destroy all GFPA DSP instances before tearing down the host.
    for (final h in _gfpaHandles.values) {
      _host?.destroyGfpaDsp(h);
    }
    _gfpaHandles.clear();
    _host?.dispose();
    _host = null;
  }

  // ─── Plugin loading ────────────────────────────────────────────────────────

  /// Load a .vst3 plugin from [path] and associate it with [slotId].
  ///
  /// [pluginType] must be supplied by the caller (user intent from
  /// [AddPluginSheet]). Effect slots receive [midiChannel] == 0 because they
  /// process audio, not MIDI note streams.
  ///
  /// Returns a populated [Vst3PluginInstance] on success, null on failure.
  Future<Vst3PluginInstance?> loadPlugin(
    String path,
    String slotId, {
    Vst3PluginType pluginType = Vst3PluginType.instrument,
  }) async {
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

      // Effect and analyzer slots have no MIDI channel — set to 0.
      final midiCh = pluginType == Vst3PluginType.instrument ? 1 : 0;

      return Vst3PluginInstance(
        id: slotId,
        midiChannel: midiCh,
        path: path,
        pluginName: name,
        pluginType: pluginType,
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
    // Propagate BPM to GFPA BPM-synced effects (delay, wah, chorus).
    _host?.setGfpaBpm(bpm);
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

    // Register GF Keyboard (libfluidsynth) as a master-mix contributor so its
    // audio plays through the ALSA thread alongside VST3 plugins. On Linux the
    // keyboard synth is always initialised before startAudio() is called.
    if (Platform.isLinux) {
      _host!.addMasterRender(AudioInputFFI().keyboardRenderBlockPtr);
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

    // Clear all master inserts at the start of each rebuild so stale
    // registrations from prior configurations are removed before we re-add.
    _host!.clearMasterInserts();

    // Track which built-in instruments now have audio routes so we can
    // enable/disable capture mode on the native synth side.
    final thereminHasRoute = <String>{};
    final styloHasRoute    = <String>{};

    // Rebuild routing table from audio connections.
    _host!.clearRoutes();
    // Clear all previous external renders before re-registering them.
    for (final plugin in _plugins.values) {
      _host!.clearExternalRender(plugin);
    }

    for (final conn in graph.connections) {
      // Only audio-family ports — skip MIDI and data cables.
      if (conn.fromPort.isDataPort || conn.toPort.isDataPort) continue;
      if (conn.fromPort == AudioPortId.midiOut ||
          conn.toPort == AudioPortId.midiIn) {
        continue;
      }

      final from = _plugins[conn.fromSlotId];
      final to   = _plugins[conn.toSlotId];

      if (from != null && to != null) {
        // VST3 → VST3: standard dart_vst_host routing.
        _host!.routeAudio(from, to);
        continue;
      }

      if (from == null && to != null) {
        // Non-VST3 → VST3: identify the source plugin by slot ID.
        final fromPlugin = allPlugins.firstWhere(
          (p) => p.id == conn.fromSlotId,
          orElse: () => allPlugins.first,
        );

        // GF Keyboard uses GrooveForgeKeyboardPlugin (not GFpaPluginInstance),
        // so it must be handled before the GFpaPluginInstance type guard.
        if (fromPlugin is GrooveForgeKeyboardPlugin) {
          // libfluidsynth renders a full stereo mix of all MIDI channels.
          // Route it into the VST3 effect's input.
          _host!.setExternalRender(to, AudioInputFFI().keyboardRenderBlockPtr);
          continue;
        }

        // Theremin and Stylophone are GFpaPluginInstance subclasses.
        if (fromPlugin is! GFpaPluginInstance) continue;

        if (fromPlugin.pluginId == 'com.grooveforge.theremin') {
          _host!.setExternalRender(to, AudioInputFFI().thereminRenderBlockPtr);
          thereminHasRoute.add(fromPlugin.id);
        } else if (fromPlugin.pluginId == 'com.grooveforge.stylophone') {
          _host!.setExternalRender(to, AudioInputFFI().styloRenderBlockPtr);
          styloHasRoute.add(fromPlugin.id);
        }
        // Other built-in instruments (Vocoder, JamMode) are not routable
        // through the VST3 chain — they use separate audio paths.
        continue;
      }

      // Non-VST3 → GFPA descriptor effect (no VST3 plugin in the destination).
      // The destination slot has a native DSP handle in _gfpaHandles.
      if (from == null && to == null) {
        final toHandle = _gfpaHandles[conn.toSlotId];
        if (toHandle == null || toHandle == nullptr) continue;

        final fromPlugin = allPlugins.firstWhere(
          (p) => p.id == conn.fromSlotId,
          orElse: () => allPlugins.first,
        );

        // GF Keyboard → GFPA effect: wire via master-insert on the keyboard
        // render function so the keyboard audio passes through native DSP.
        // The keyboard stays in masterRenders; the insert chain replaces
        // direct accumulation with the DSP-processed output.
        if (fromPlugin is GrooveForgeKeyboardPlugin && Platform.isLinux) {
          _host!.addMasterInsert(
            AudioInputFFI().keyboardRenderBlockPtr,
            toHandle,
          );
        }
      }
    }

    // Enable capture mode on native synths that are routed through VST3,
    // and disable it for those that are no longer connected.
    // Capture mode ON  → miniaudio outputs silence; ALSA thread drives DSP.
    // Capture mode OFF → normal direct ALSA playback.
    //
    // For GF Keyboard: when routed into an effect, remove it from the
    // master-mix list (output now goes to the effect's input exclusively).
    // When not routed, add it back as a master-mix contributor.
    final thereminActive = thereminHasRoute.isNotEmpty;
    final styloActive    = styloHasRoute.isNotEmpty;
    try {
      AudioInputFFI().thereminSetCaptureMode(enabled: thereminActive);
      AudioInputFFI().styloSetCaptureMode(enabled: styloActive);

      if (Platform.isLinux) {
        // Always keep the keyboard in masterRenders.
        // The insert chain handles routing: when an insert is registered for
        // the keyboard render fn (keyboard → GFPA effect), the ALSA loop
        // passes audio through the DSP before accumulating to master.
        // When no insert exists, audio goes directly to master.
        // Removing the keyboard from masterRenders would silence it even when
        // an insert is wired (inserts only run for fns IN masterRenders).
        _host!.addMasterRender(AudioInputFFI().keyboardRenderBlockPtr);
      }
    } catch (_) {
      // AudioInputFFI may not be initialised on non-Linux builds (web, macOS
      // without the native lib). Silently ignore — routing is no-op there.
    }
  }

  // ─── GFPA native DSP effects ────────────────────────────────────────────────

  /// Create a native GFPA DSP instance for [pluginId] and store it under
  /// [slotId].  The DSP runs on the ALSA audio thread once wired via
  /// [syncAudioRouting].
  ///
  /// Calling again for the same [slotId] first destroys the old instance
  /// (safe because syncAudioRouting clears inserts before re-registering).
  void registerGfpaDsp(String slotId, String pluginId) {
    if (!isSupported || _host == null) return;
    _destroyGfpaDspForSlot(slotId);
    final handle = _host!.createGfpaDsp(pluginId, 48000, 256);
    if (handle == nullptr) {
      debugPrint('VstHostService: gfpa_dsp_create returned null for $pluginId');
      return;
    }
    _gfpaHandles[slotId] = handle;
    debugPrint('VstHostService: GFPA DSP created for $slotId ($pluginId)');
  }

  /// Destroy the native DSP instance for [slotId] and remove it from the map.
  void unregisterGfpaDsp(String slotId) {
    if (!isSupported || _host == null) return;
    _destroyGfpaDspForSlot(slotId);
    debugPrint('VstHostService: GFPA DSP destroyed for $slotId');
  }

  /// Send a physical parameter value to the native DSP for [slotId].
  ///
  /// [physicalValue] must already be in the parameter's declared range
  /// (i.e. the caller converts from normalised [0,1] using min + norm*(max-min)).
  void setGfpaDspParam(String slotId, String paramId, double physicalValue) {
    final handle = _gfpaHandles[slotId];
    if (handle == null || handle == nullptr) return;
    _host?.setGfpaDspParam(handle, paramId, physicalValue);
  }

  /// Internal: destroy and remove the DSP handle for [slotId] if present.
  void _destroyGfpaDspForSlot(String slotId) {
    final old = _gfpaHandles.remove(slotId);
    if (old != null && old != nullptr) {
      _host?.destroyGfpaDsp(old);
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

