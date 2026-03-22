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
import 'gfpa_android_bindings_native.dart';

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
      !kIsWeb &&
      (Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isAndroid);

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

    // Android uses libnative-lib.so (flutter_midi_pro) for audio — no
    // VstHost or libdart_vst_host.so needed on this platform.
    if (Platform.isAndroid) return;

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

    // On Android the VstHost is not used; propagate BPM via the FFI binding
    // which writes to the atomic float in gfpa_dsp.cpp / gfpa_audio_android.cpp.
    if (Platform.isAndroid) {
      GfpaAndroidBindings.instance.gfpaAndroidSetBpm(bpm);
    }
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
    if (!isSupported) return;

    // FluidSynth's Oboe driver starts automatically when loadSoundfont is
    // called on Android.  Mark as started so setTransport calls go through.
    if (Platform.isAndroid) {
      _audioRunning = true;
      return;
    }

    if (_audioRunning || _host == null) return;
    // Register all currently loaded plugins with the audio loop.
    _host!.clearAudioLoop();
    for (final p in _plugins.values) {
      _host!.addToAudioLoop(p);
    }

    // Register slot 0 as a baseline master-mix contributor.  Slot 0 is always
    // created by audio_engine.dart's keyboard_init() call.  Using the per-slot
    // function pointer (keyboard_render_block_0) rather than the backward-compat
    // Register render functions for all keyboard slots upfront.
    // keyboard_render_block_N outputs silence when slot N has no active synth,
    // so pre-registering both is always safe.  Slot 0 is also initialised by
    // audio_engine.dart's keyboard_init(); slot 1 is initialised here so it is
    // ready before syncAudioRouting() fires (which only runs on connection or
    // plugin changes, not on plain rack startup with no effects).
    if (Platform.isLinux || Platform.isMacOS) {
      AudioInputFFI().keyboardInitSlot(0, 48000.0);
      AudioInputFFI().keyboardInitSlot(1, 48000.0);
      _host!.addMasterRender(AudioInputFFI().keyboardRenderFnForSlot(0));
      _host!.addMasterRender(AudioInputFFI().keyboardRenderFnForSlot(1));
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
  void syncAudioRouting(
    AudioGraph graph,
    List<PluginInstance> allPlugins, {
    Map<String, int> keyboardSfIds = const {},
  }) {
    if (!isSupported) return;

    // On Android, the GFPA insert chain lives in gfpa_audio_android.cpp.
    if (Platform.isAndroid) {
      _syncAudioRoutingAndroid(graph, allPlugins, keyboardSfIds);
      return;
    }

    if (_host == null) return;

    // Build the topological processing order — VST3 slots only.
    final allSlotIds = allPlugins.map((p) => p.id).toList();
    final orderedIds = graph.topologicalOrder(allSlotIds);
    final orderedPlugins = orderedIds
        .map((id) => _plugins[id])
        .whereType<VstPlugin>()
        .toList();

    _host!.setProcessingOrder(orderedPlugins);

    // Clear all inserts and all render contributors at the start of each
    // rebuild so stale registrations from prior routing states are removed.
    // masterRenders must be cleared so that instruments no longer in the rack
    // or no longer connected (e.g. a Theremin that was cabled before) are not
    // left in the list, which would cause them to be rendered twice (once via
    // the cleared list and once via their own ALSA device) → saturation.
    _host!.clearMasterInserts();
    _host!.clearMasterRenders();

    // Re-register each GF Keyboard slot as a master-mix contributor.
    if (Platform.isLinux || Platform.isMacOS) {
      for (final plugin in allPlugins.whereType<GrooveForgeKeyboardPlugin>()) {
        // MIDI channels are 1-based; map to 0-based slot index mod MAX_KB_SLOTS.
        final slotIdx = (plugin.midiChannel - 1) % 2;
        AudioInputFFI().keyboardInitSlot(slotIdx, 48000.0);
        _host!.addMasterRender(AudioInputFFI().keyboardRenderFnForSlot(slotIdx));
      }
    }

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
          // Use the per-slot render function so this VST3 effect only receives
          // audio from the keyboard slot it is cabled to.
          final slotIdx = (fromPlugin.midiChannel - 1) % 2;
          _host!.setExternalRender(to, AudioInputFFI().keyboardRenderFnForSlot(slotIdx));
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

      // Non-VST3 → GFPA: handled below via DFS traversal after this loop.
    }

    // ── GFPA insert chains (Linux/macOS): DFS from each source ───────────────
    //
    // Using DFS (same approach as the Android path) ensures that chained
    // effects such as Keyboard → WAH → Reverb are registered in the correct
    // order into the source's insert chain.  A single-hop lookup would miss
    // the second effect in the chain.
    if (Platform.isLinux || Platform.isMacOS) {
      // GF Keyboard sources.
      for (final plugin in allPlugins.whereType<GrooveForgeKeyboardPlugin>()) {
        final slotIdx = (plugin.midiChannel - 1) % 2;
        _addChainInsertsDesktop(
            plugin.id, AudioInputFFI().keyboardRenderFnForSlot(slotIdx), graph);
      }

      // Theremin and Stylophone: when wired to a GFPA effect, add them as
      // masterRender contributors and enable capture mode so their own ALSA
      // device outputs silence (the ALSA thread drives the DSP instead).
      for (final plugin in allPlugins.whereType<GFpaPluginInstance>()) {
        if (plugin.pluginId == 'com.grooveforge.theremin' &&
            _hasAnyGfpaConnection(plugin.id, graph)) {
          _host!.addMasterRender(AudioInputFFI().thereminRenderBlockPtr);
          thereminHasRoute.add(plugin.id);
          _addChainInsertsDesktop(
              plugin.id, AudioInputFFI().thereminRenderBlockPtr, graph);
        } else if (plugin.pluginId == 'com.grooveforge.stylophone' &&
            _hasAnyGfpaConnection(plugin.id, graph)) {
          _host!.addMasterRender(AudioInputFFI().styloRenderBlockPtr);
          styloHasRoute.add(plugin.id);
          _addChainInsertsDesktop(
              plugin.id, AudioInputFFI().styloRenderBlockPtr, graph);
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
    if (!isSupported) return;

    // On Android, create the DSP via the FFI binding to libnative-lib.so.
    if (Platform.isAndroid) {
      _destroyGfpaDspForSlot(slotId);
      final handle = GfpaAndroidBindings.instance.createDsp(pluginId);
      if (handle != nullptr) {
        _gfpaHandles[slotId] = handle;
        debugPrint('VstHostService: GFPA DSP created (Android) for $slotId ($pluginId)');
      }
      return;
    }

    if (_host == null) return;
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
  ///
  /// Delegates to [_destroyGfpaDspForSlot] on all platforms so the Android
  /// path correctly calls [gfpaAndroidRemoveInsert] (with its drain wait)
  /// before [gfpaDspDestroy].  The previous inline Android branch called
  /// [gfpaDspDestroy] directly, bypassing the drain and causing a
  /// use-after-free SIGSEGV in the AAudio callback.
  void unregisterGfpaDsp(String slotId) {
    if (!isSupported) return;
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

    // On Android, forward directly via the FFI binding to libnative-lib.so.
    if (Platform.isAndroid) {
      GfpaAndroidBindings.instance.gfpaDspSetParam(handle, paramId, physicalValue);
      return;
    }

    _host?.setGfpaDspParam(handle, paramId, physicalValue);
  }

  /// Synchronise the Android GFPA insert chain with the current [graph].
  ///
  /// Rebuilds all per-source chains from scratch:
  ///   1. Clear every existing insert so stale connections are removed.
  ///   2. For each GF Keyboard, trace the full downstream GFPA chain via DFS
  ///      and register every reachable effect into that keyboard's bus slot.
  ///   3. For Theremin (bus slot 5) and Stylophone (bus slot 6), do the same.
  ///
  /// Using DFS (rather than single-hop lookup) allows effect chains such as
  /// Keyboard → WAH → Reverb to work: Reverb is registered in the same slot
  /// as WAH, so both effects run in series on that keyboard's audio path.
  ///
  /// [keyboardSfIds] maps each keyboard plugin's slot ID to its soundfont ID
  /// (the 1-based integer returned by [loadSoundfont]).  The native layer uses
  /// this to route each effect to only the keyboard it is connected to, so
  /// WAH on keyboard A cannot bleed into keyboard B's audio path.
  void _syncAudioRoutingAndroid(
      AudioGraph graph,
      List<PluginInstance> allPlugins,
      Map<String, int> keyboardSfIds) {
    // Clear all per-source chains — rebuilt from scratch on each call.
    GfpaAndroidBindings.instance.gfpaAndroidClearAllInserts();

    // ── GF Keyboards: one bus slot per soundfont ID ────────────────────────
    for (final plugin in allPlugins.whereType<GrooveForgeKeyboardPlugin>()) {
      final sfId = keyboardSfIds[plugin.id] ?? -1;
      if (sfId < 1) continue; // Not yet loaded — skip.
      _addChainInserts(plugin.id, sfId, graph);
    }

    // ── Theremin (bus slot 5) and Stylophone (bus slot 6) ─────────────────
    //
    // These are GFpaPluginInstance slots with well-known plugin IDs. Their
    // audio flows through the shared AAudio bus, so the bus slot ID is the
    // key the native insert chain uses.
    for (final plugin in allPlugins.whereType<GFpaPluginInstance>()) {
      if (plugin.pluginId == 'com.grooveforge.theremin') {
        _addChainInserts(plugin.id, kBusSlotTheremin, graph);
      } else if (plugin.pluginId == 'com.grooveforge.stylophone') {
        _addChainInserts(plugin.id, kBusSlotStylophone, graph);
      }
    }
  }

  /// Depth-first traversal of [graph] starting from [sourceSlotId].
  ///
  /// Registers every reachable GFPA DSP handle into [busSlotId]'s insert
  /// chain in traversal order (source → first effect → chained effects).
  /// [visited] tracks visited slot IDs to avoid infinite loops in cycles
  /// (cycles are prevented by [AudioGraph.wouldCreateCycle] but the guard
  /// also protects against future graph changes).
  ///
  /// Only audio connections are followed — MIDI and data ports are skipped.
  void _addChainInserts(
      String sourceSlotId, int busSlotId, AudioGraph graph, [Set<String>? visited]) {
    final seen = visited ?? {sourceSlotId};

    for (final conn in graph.connections) {
      // Only follow audio cables from the current node.
      if (conn.fromSlotId != sourceSlotId) continue;
      if (conn.fromPort.isDataPort || conn.toPort.isDataPort) continue;
      if (conn.fromPort == AudioPortId.midiOut ||
          conn.toPort == AudioPortId.midiIn) {
        continue;
      }

      // Guard against cycles.
      if (seen.contains(conn.toSlotId)) continue;
      seen.add(conn.toSlotId);

      // Register the downstream GFPA effect handle if available.
      final handle = _gfpaHandles[conn.toSlotId];
      if (handle != null && handle != nullptr) {
        GfpaAndroidBindings.instance.gfpaAndroidAddInsertForSf(busSlotId, handle);
      }

      // Recurse to pick up chained effects (e.g. WAH → Reverb).
      _addChainInserts(conn.toSlotId, busSlotId, graph, seen);
    }
  }

  /// Depth-first traversal of [graph] starting from [sourceSlotId] for the
  /// desktop (Linux/macOS) GFPA insert chain.
  ///
  /// Registers every reachable GFPA DSP handle into [renderFn]'s masterInsert
  /// chain in DFS traversal order, enabling series chains such as
  /// Keyboard → WAH → Reverb.  Only audio connections are followed.
  void _addChainInsertsDesktop(
      String sourceSlotId,
      Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>> renderFn,
      AudioGraph graph, [Set<String>? visited]) {
    final seen = visited ?? {sourceSlotId};
    for (final conn in graph.connections) {
      if (conn.fromSlotId != sourceSlotId) continue;
      if (conn.fromPort.isDataPort || conn.toPort.isDataPort) continue;
      if (conn.fromPort == AudioPortId.midiOut ||
          conn.toPort == AudioPortId.midiIn) {
        continue;
      }
      if (seen.contains(conn.toSlotId)) continue;
      seen.add(conn.toSlotId);
      final handle = _gfpaHandles[conn.toSlotId];
      if (handle != null && handle != nullptr) {
        _host!.addMasterInsert(renderFn, handle);
      }
      _addChainInsertsDesktop(conn.toSlotId, renderFn, graph, seen);
    }
  }

  /// Returns true if [slotId] has at least one audio connection to a slot
  /// that has an active GFPA DSP handle.  Used to decide whether to add a
  /// Theremin/Stylophone as a masterRender contributor.
  bool _hasAnyGfpaConnection(String slotId, AudioGraph graph) {
    for (final conn in graph.connections) {
      if (conn.fromSlotId != slotId) continue;
      if (conn.fromPort.isDataPort || conn.toPort.isDataPort) continue;
      if (conn.fromPort == AudioPortId.midiOut ||
          conn.toPort == AudioPortId.midiIn) {
        continue;
      }
      final handle = _gfpaHandles[conn.toSlotId];
      if (handle != null && handle != nullptr) return true;
    }
    return false;
  }

  /// Internal: destroy and remove the DSP handle for [slotId] if present.
  ///
  /// On Android [_host] is null; destruction goes through [GfpaAndroidBindings].
  ///
  /// **Ordering guarantee**: `gfpaAndroidRemoveInsert` must be called BEFORE
  /// `gfpaDspDestroy`. The remove call contains a spin-wait that drains any
  /// in-flight AAudio callback snapshot that still holds a raw pointer to the
  /// DSP object. Destroying first leaves a dangling pointer in the chain and
  /// causes an immediate use-after-free SIGSEGV on the audio thread.
  void _destroyGfpaDspForSlot(String slotId) {
    final old = _gfpaHandles.remove(slotId);
    if (old == null || old == nullptr) return;
    if (Platform.isAndroid) {
      // Remove from the insert chain and wait for the audio thread to drain
      // any in-flight callback that still references this handle.
      GfpaAndroidBindings.instance.gfpaAndroidRemoveInsert(old);
      GfpaAndroidBindings.instance.gfpaDspDestroy(old);
    } else {
      // Remove from all source chains and drain before destroying.
      // The drain spin-waits for the ALSA/CoreAudio callback to finish at
      // least one full block after removal, ensuring no in-flight raw pointer
      // to this DSP remains before gfpa_dsp_destroy frees the memory.
      _host?.removeMasterInsertByHandle(old);
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

