import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:flutter/foundation.dart';

import '../models/grooveforge_keyboard_plugin.dart';
import '../models/plugin_instance.dart';
import 'audio_looper_engine.dart';
import 'wav_utils.dart';
import '../models/vst3_plugin_instance.dart';
// Vst3PluginType used in loadPlugin signature.
export '../models/vst3_plugin_instance.dart' show Vst3PluginType;
import '../audio/audio_source_descriptor.dart';
import '../audio/routing_plan.dart';
import '../audio/routing_plan_builder.dart';
import 'audio_graph.dart';
import 'audio_input_ffi_native.dart';
import 'gfpa_android_bindings_native.dart';
import 'native_instrument_controller.dart';

/// Desktop VST3 host service.
///
/// Wraps [VstHost] from `dart_vst_host` to provide plugin loading, MIDI
/// routing, parameter control, and JACK audio output (Linux only).
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

  /// Public read-only access to the native host handle.
  ///
  /// Used by [AudioLooperEngine] to call audio looper C API functions.
  /// Returns null before [initialize] is called or on unsupported platforms.
  VstHost? get host => _host;

  /// Reference to the audio looper engine, set by splash_screen.dart.
  /// Used by [syncAudioRouting] to wire audio cable sources to looper clips.
  AudioLooperEngine? audioLooperEngine;

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

  /// Exports every audio-looper clip as a 32-bit float stereo WAV sidecar
  /// file inside `.gf.audio/` next to the project's `.gf` JSON.
  ///
  /// Called as the [AudioLooperEngine.wavExporter] callback on native
  /// platforms.  Web falls through to the stub and silently no-ops.
  ///
  /// Reads native clip buffers through two different libraries depending on
  /// platform: `libdart_vst_host.so` on Linux/macOS (via [VstHost]) and
  /// `libnative-lib.so` on Android (via [AudioInputFFI]).  Both compile the
  /// identical `audio_looper.cpp` source file, so the `dvh_alooper_*`
  /// symbols behave the same way — the only difference is which handle
  /// returns the raw `Pointer<Float>`.
  ///
  /// The pointers are wrapped as zero-copy [Float32List] views via
  /// `ptr.asTypedList(length)` **before** being handed to [writeWavFile],
  /// because `writeWavFile` takes its buffers as `dynamic` to keep
  /// `dart:ffi` out of `wav_utils.dart` for web compatibility — and
  /// indexing a raw `Pointer<Float>` through a `dynamic` receiver fails at
  /// runtime (see v2.12.3 fix).
  Future<void> exportAudioLooperWavs(
      String gfPath, Map<String, AudioLooperClip> clips) async {
    if (clips.isEmpty) return;
    final isAndroid = Platform.isAndroid;
    if (_host == null && !isAndroid) return;

    final dir = Directory('$gfPath.audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    final writtenFiles = <String>{};

    for (final entry in clips.entries) {
      final slotId = entry.key;
      final clip = entry.value;
      final int length;
      final Float32List dataL;
      final Float32List dataR;
      if (isAndroid) {
        length = AudioInputFFI().alooperGetLength(clip.nativeIdx);
        if (length <= 0) continue;
        final ptrL = AudioInputFFI().alooperGetDataL(clip.nativeIdx);
        final ptrR = AudioInputFFI().alooperGetDataR(clip.nativeIdx);
        if (ptrL == nullptr || ptrR == nullptr) {
          debugPrint('VstHostService: skip loop_$slotId — native buffer null');
          continue;
        }
        dataL = ptrL.asTypedList(length);
        dataR = ptrR.asTypedList(length);
      } else {
        length = _host!.getAudioLooperLength(clip.nativeIdx);
        if (length <= 0) continue;
        final ptrL = _host!.getAudioLooperDataL(clip.nativeIdx);
        final ptrR = _host!.getAudioLooperDataR(clip.nativeIdx);
        if (ptrL == nullptr || ptrR == nullptr) {
          debugPrint('VstHostService: skip loop_$slotId — native buffer null');
          continue;
        }
        dataL = ptrL.asTypedList(length);
        dataR = ptrR.asTypedList(length);
      }

      final filename = 'loop_$slotId.wav';
      final wavPath = '${dir.path}/$filename';
      try {
        writeWavFile(
          dataL: dataL,
          dataR: dataR,
          lengthFrames: length,
          sampleRate: clip.sampleRate,
          path: wavPath,
        );
        writtenFiles.add(filename);
        debugPrint('VstHostService: exported $filename ($length frames)');
      } catch (e) {
        debugPrint('VstHostService: failed to export $filename: $e');
      }
    }

    // Clean up orphan WAVs from deleted clips.
    try {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.wav')) {
          final name = entity.uri.pathSegments.last;
          if (!writtenFiles.contains(name)) {
            await entity.delete();
            debugPrint('VstHostService: cleaned up orphan $name');
          }
        }
      }
    } catch (e) {
      debugPrint('VstHostService: orphan cleanup failed: $e');
    }
  }

  /// Imports sidecar WAV files into native audio looper clip buffers.
  ///
  /// Called as the [AudioLooperEngine.wavImporter] callback on all native
  /// platforms. Uses `dart:ffi` (`Pointer`, `malloc`) for the bulk PCM copy,
  /// which is only available off-web — the stub export of this class
  /// returns a no-op.
  ///
  /// On Linux/macOS, the native buffers are owned by `libdart_vst_host.so`
  /// and accessed through [VstHost.loadAudioLooperData].  On Android the
  /// same C symbols live in `libnative-lib.so` and are reached directly
  /// through [AudioInputFFI] since `VstHost` is null there.
  Future<void> importAudioLooperWavs(
      String gfPath, Map<String, AudioLooperClip> clips) async {
    // Bail on platforms where no sidecar directory is expected.
    final dir = Directory('$gfPath.audio');
    final dirExists = await dir.exists();
    debugPrint('VstHostService: importAudioLooperWavs '
        'gfPath=$gfPath, dir=${dir.path}, exists=$dirExists, '
        'clipCount=${clips.length}');
    if (!dirExists) return;

    final isAndroid = !kIsWeb && Platform.isAndroid;
    if (_host == null && !isAndroid) {
      debugPrint('VstHostService: importAudioLooperWavs — host null on '
          'non-Android, skipping');
      return;
    }

    for (final entry in clips.entries) {
      final slotId = entry.key;
      final clip = entry.value;
      final wavPath = '${dir.path}/loop_$slotId.wav';
      final wavExists = await File(wavPath).exists();
      debugPrint('VstHostService: importAudioLooperWavs — check $wavPath '
          'exists=$wavExists nativeIdx=${clip.nativeIdx}');
      if (!wavExists) continue;
      try {
        final wav = readWavFile(wavPath);
        // Allocate a native scratch pair, fill it with the WAV PCM, hand it
        // to the native loader, and free immediately. The loader copies the
        // data into the clip's pre-allocated internal buffer so lifetime
        // is bounded to this call.
        final srcL = malloc<Float>(wav.lengthFrames);
        final srcR = malloc<Float>(wav.lengthFrames);
        srcL.asTypedList(wav.lengthFrames).setAll(0, wav.left);
        srcR.asTypedList(wav.lengthFrames).setAll(0, wav.right);
        bool ok;
        if (isAndroid) {
          // Android path: FFI straight into libnative-lib.so.
          final rc = AudioInputFFI()
              .alooperLoadData(clip.nativeIdx, srcL, srcR, wav.lengthFrames);
          ok = rc != 0;
          debugPrint('VstHostService: alooperLoadData($slotId, ${wav.lengthFrames}'
              ' frames) → rc=$rc');
        } else {
          // Desktop path: through the VstHost-owned DVH C API.
          ok = _host!.loadAudioLooperData(
              clip.nativeIdx, srcL, srcR, wav.lengthFrames);
        }
        malloc.free(srcL);
        malloc.free(srcR);
        if (ok) {
          clip.lengthFrames = wav.lengthFrames;
          debugPrint(
              'VstHostService: imported loop $slotId (${wav.lengthFrames} frames)');
        } else {
          debugPrint('VstHostService: load FAILED for $slotId — native '
              'loader returned 0');
        }
      } catch (e) {
        debugPrint('VstHostService: failed to import loop $slotId: $e');
      }
    }
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

  // ─── Audio output (Linux JACK / macOS CoreAudio) ───────────────────────────

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
    // All three desktop platforms use the same FluidSynth keyboard slot
    // render functions — the miniaudio path on mac/Windows and the JACK
    // path on Linux both pull from these master-render contributors.
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      AudioInputFFI().keyboardInitSlot(0, 48000.0);
      AudioInputFFI().keyboardInitSlot(1, 48000.0);
      AudioInputFFI().keyboardInitSlot(2, 48000.0); // percussion (channel 9)
      _host!.addMasterRender(AudioInputFFI().keyboardRenderFnForSlot(0));
      _host!.addMasterRender(AudioInputFFI().keyboardRenderFnForSlot(1));
      _host!.addMasterRender(AudioInputFFI().keyboardRenderFnForSlot(2));
    }

    // macOS and Windows share the miniaudio desktop backend (CoreAudio
    // and WASAPI respectively); Linux uses JACK. See the native
    // `dart_vst_host_audio_desktop.cpp` vs `dart_vst_host_jack.cpp`
    // split for the rationale.
    bool ok = false;
    if (Platform.isMacOS || Platform.isWindows) {
      ok = _host!.startDesktopAudio();
    } else {
      ok = _host!.startJackClient();
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

    if (Platform.isMacOS || Platform.isWindows) {
      _host!.stopDesktopAudio();
    } else {
      _host!.stopJackClient();
    }

    _audioRunning = false;
    debugPrint('VstHostService: Audio thread stopped');
  }

  // ─── Audio graph routing (Phase 5.4) ──────────────────────────────────────

  /// Synchronises the native JACK processing order and audio routing table
  /// with the current state of the Dart [AudioGraph].
  ///
  /// Should be called whenever:
  ///   - An [AudioGraph] connection is added or removed.
  ///   - A VST3 plugin slot is added or removed from the rack.
  ///
  /// Only VST3 slots (those present in [_plugins]) participate in native
  /// routing. Built-in GFPA slots (FluidSynth, vocoder, Jam Mode) use their
  /// own audio paths and are not routed through the JACK audio loop.
  void syncAudioRouting(
    AudioGraph graph,
    List<PluginInstance> allPlugins, {
    Map<String, int> keyboardSfIds = const {},
  }) {
    if (!isSupported) return;

    // On Android, the GFPA insert chain lives in gfpa_audio_android.cpp.
    if (Platform.isAndroid) {
      // Defensive check: an empty `keyboardSfIds` when keyboards exist in
      // the rack is almost always a call-site bug — it silently breaks
      // GFPA effect routing AND audio looper cabled input routing. Log
      // loudly so it gets noticed in development, and avoids the "record
      // produces silence" mystery from v2.12.x.
      if (keyboardSfIds.isEmpty &&
          allPlugins.whereType<GrooveForgeKeyboardPlugin>().isNotEmpty) {
        debugPrint(
            'VstHostService: syncAudioRouting called with empty keyboardSfIds '
            'but ${allPlugins.whereType<GrooveForgeKeyboardPlugin>().length} '
            'keyboard(s) in rack — call site must pass RackState.buildKeyboardSfIds()');
      }
      _syncAudioRoutingAndroid(graph, allPlugins, keyboardSfIds);
      return;
    }

    if (_host == null) return;

    // ── Desktop (Linux / macOS) routing — plan-driven since v2.13.x ───────
    //
    // The routing sync now flows through a single `RoutingPlan` built by
    // `buildRoutingPlan(…)` in `lib/audio/`. The plan is a platform-
    // agnostic POD that is unit-tested in isolation and shared with the
    // future macOS / Windows / iOS adapters. All the per-source dispatch
    // that used to live here (GF keyboard / theremin / stylophone /
    // vocoder / live input / VST3) is now expressed as a few fields on
    // `ResolvedSource`, and `_applyPlanDesktop` is a dumb translator from
    // plan entries to `_host` FFI calls.
    //
    // The behaviour should be **exactly** what the previous ~270 lines of
    // hand-written branches did, because the plan was designed by reading
    // that code. If you see a routing regression after this change, diff
    // the FFI call sequence between old and new paths — not the Dart
    // logic.
    final plan = _buildDesktopPlan(graph, allPlugins);
    _applyPlanDesktop(plan: plan, graph: graph, allPlugins: allPlugins);
  }

  // ── Desktop plan builder + apply helpers ────────────────────────────────

  /// Turns the current rack state into a [RoutingPlan] for the desktop
  /// backend. Thin wrapper around [buildRoutingPlan] that supplies the
  /// production handle resolvers (which touch `AudioInputFFI` and
  /// `_gfpaHandles`) and picks the JACK capability profile.
  ///
  /// The `DrumGeneratorPluginInstance` is a virtual source that shares
  /// percussion slot 2 with the rack metronome; its resolver hands back
  /// the slot-2 render function so the plan sees it as a normal source.
  RoutingPlan _buildDesktopPlan(
    AudioGraph graph,
    List<PluginInstance> allPlugins,
  ) {
    return buildRoutingPlan(
      plugins: allPlugins,
      graph: graph,
      caps: BackendCapabilities.jack,
      resolveSource: _resolveDesktopSource,
      resolveEffect: _resolveDesktopEffect,
    );
  }

  /// Resolves a rack slot to the pointer address of its native render
  /// function (or a VST3 ordinal marker), along with the mix-strategy
  /// and capture-group metadata the adapter needs.
  ///
  /// Phase B structure: the plugin class itself declares its audio
  /// role via [AudioSourcePlugin.describeAudioSource]. We switch on
  /// the returned [AudioSourceKind], which is exhaustiveness-checked
  /// by the Dart 3 analyser — adding a new enum value without a case
  /// here produces a static error rather than a silent null return.
  ResolvedSource? _resolveDesktopSource(PluginInstance plugin) {
    if (plugin is! AudioSourcePlugin) return null;
    final descriptor =
        (plugin as AudioSourcePlugin).describeAudioSource();
    if (descriptor == null) return null;

    final ffi = AudioInputFFI();
    switch (descriptor.kind) {
      case AudioSourceKind.gfKeyboard:
        final slotIdx = (descriptor.midiChannel - 1) % 2;
        ffi.keyboardInitSlot(slotIdx, 48000.0);
        return ResolvedSource(
          kind: SourceKind.renderFunction,
          handle: ffi.keyboardRenderFnForSlot(slotIdx).address,
          masterMixStrategy: MasterMixStrategy.alwaysRender,
        );
      case AudioSourceKind.drumGenerator:
        // Percussion slot 2 is shared with the metronome and is
        // always primed; its handle is the same slot-2 render function.
        ffi.keyboardInitSlot(2, 48000.0);
        return ResolvedSource(
          kind: SourceKind.renderFunction,
          handle: ffi.keyboardRenderFnForSlot(2).address,
          masterMixStrategy: MasterMixStrategy.alwaysRender,
        );
      case AudioSourceKind.theremin:
        return ResolvedSource(
          kind: SourceKind.renderFunction,
          handle: ffi.thereminRenderBlockPtr.address,
          captureGroup: CaptureModeGroup.theremin,
        );
      case AudioSourceKind.stylophone:
        return ResolvedSource(
          kind: SourceKind.renderFunction,
          handle: ffi.styloRenderBlockPtr.address,
          captureGroup: CaptureModeGroup.stylophone,
        );
      case AudioSourceKind.vocoder:
        return ResolvedSource(
          kind: SourceKind.renderFunction,
          handle: ffi.vocoderRenderBlockPtr.address,
          captureGroup: CaptureModeGroup.vocoder,
        );
      case AudioSourceKind.liveInput:
        return ResolvedSource(
          kind: SourceKind.renderFunction,
          handle: ffi.liveInputRenderBlockPtr.address,
        );
      case AudioSourceKind.vst3Instrument:
        // VST3 instruments are addressed by ordinal, not function
        // pointer. The ordinal is not stable across calls, so we
        // store `-1` here and let the adapter resolve it from
        // `_plugins` + topological order at apply time.
        return const ResolvedSource(
          kind: SourceKind.vst3Plugin,
          handle: -1,
        );
    }
  }

  /// Looks up the native GFPA DSP handle for an effect slot, as an
  /// integer address for the plan's opaque field. Returns `null` if the
  /// slot has no registered DSP yet (the next sync will pick it up).
  int? _resolveDesktopEffect(PluginInstance plugin) {
    final handle = _gfpaHandles[plugin.id];
    if (handle == null || handle == nullptr) return null;
    return handle.address;
  }

  /// Translates a [RoutingPlan] into `_host` FFI calls for the desktop
  /// backend. Mirrors the behaviour of the previous hand-written routing
  /// code one-to-one:
  ///
  ///   1. `clearMasterInserts` / `clearMasterRenders` / `clearRoutes`
  ///      wipe stale native state before we re-register anything.
  ///   2. Percussion slot 2 is always added to the master mix, even when
  ///      no keyboard exists, so the metronome is audible.
  ///   3. For every source in the plan: if its strategy is
  ///      `alwaysRender` OR it participates in any chain / looper sink,
  ///      register it as a master render contributor.
  ///   4. For every chain with GFPA effects: add each effect to each
  ///      participating source's master insert chain.
  ///   5. For every empty chain (source → VST3 direct cable): register
  ///      an external render so the VST3 plugin sees the source on its
  ///      audio input.
  ///   6. For every VST3 → VST3 route in `plan.vstRoutes`: route audio.
  ///   7. For every looper sink: register the root source against the
  ///      clip's native index (or a VST3 ordinal for VST3 sources).
  ///   8. Aggregate capture-group usage and push one `setCaptureMode`
  ///      call per group.
  void _applyPlanDesktop({
    required RoutingPlan plan,
    required AudioGraph graph,
    required List<PluginInstance> allPlugins,
  }) {
    final host = _host;
    if (host == null) return;

    // Phase H diagnostics: log every dropped shared-effect cable so
    // the user can see in the debug console why part of their cable
    // graph is not producing the expected audio. A future UI pass
    // will surface these as a patch-view overlay.
    for (final diag in plan.diagnostics) {
      debugPrint('[routing] $diag');
    }

    // Topological order of all slot IDs — needed for VST3 processing
    // order and for resolving VST3 ordinals in looper sinks.
    final allSlotIds = allPlugins.map((p) => p.id).toList();
    final orderedIds = graph.topologicalOrder(allSlotIds);
    final orderedVst3Plugins = orderedIds
        .map((id) => _plugins[id])
        .whereType<VstPlugin>()
        .toList();
    host.setProcessingOrder(orderedVst3Plugins);
    final vst3SlotOrder =
        orderedIds.where((id) => _plugins.containsKey(id)).toList();

    // Clear every per-sync registry so stale state from a previous
    // topology cannot linger.
    host.clearMasterInserts();
    host.clearMasterRenders();
    host.clearRoutes();
    for (final plugin in _plugins.values) {
      host.clearExternalRender(plugin);
    }

    // Percussion slot 2 — unconditional master render so the metronome
    // and drum generator are always heard. Matches the pre-plan code.
    final ffi = AudioInputFFI();
    ffi.keyboardInitSlot(2, 48000.0);
    host.addMasterRender(ffi.keyboardRenderFnForSlot(2));

    // Determine which sources are referenced by a chain or looper sink.
    // `onlyWhenConnected` strategies only get a master render when they
    // actually feed something; `alwaysRender` strategies are registered
    // unconditionally so the raw source remains audible.
    final referencedSourceIndices = <int>{};
    for (final chain in plan.insertChains) {
      referencedSourceIndices.addAll(chain.sourceIndices);
    }
    for (final sink in plan.looperSinks) {
      referencedSourceIndices.add(sink.sourceIndex);
    }

    // Master renders. Keyboards and the percussion slot come through as
    // `alwaysRender`; theremin / stylo / vocoder / live input only when
    // they are wired into something.
    for (var i = 0; i < plan.sources.length; i++) {
      final source = plan.sources[i];
      if (source.kind != SourceKind.renderFunction) continue;
      final isReferenced = referencedSourceIndices.contains(i);
      final shouldRender =
          source.masterMixStrategy == MasterMixStrategy.alwaysRender ||
              isReferenced;
      if (!shouldRender) continue;
      host.addMasterRender(_renderFnFromHandle(source.renderFnHandle));
    }

    // Insert chains and their destinations. A chain with no effects and
    // a VST3 destination becomes a `setExternalRender`. A chain with
    // effects and any destination becomes per-source `addMasterInsert`
    // calls (matching the old `_addChainInsertsDesktop` walk).
    for (final chain in plan.insertChains) {
      _applyChainDesktop(
        host: host,
        chain: chain,
        plan: plan,
      );
    }

    // VST3 → VST3 direct audio routes.
    for (final route in plan.vstRoutes) {
      final from = _plugins[route.fromSlotId];
      final to = _plugins[route.toSlotId];
      if (from == null || to == null) continue;
      host.routeAudio(from, to);
    }

    // Audio looper sources. The plan's looper sinks already point at the
    // root source (post-upstream-walk), so we just translate the source
    // kind to the matching `addAudioLooperRenderSource` /
    // `addAudioLooperSourcePlugin` call.
    final alooperEngine = audioLooperEngine;
    if (alooperEngine != null) {
      for (final clip in alooperEngine.clips.values) {
        host.clearAudioLooperSources(clip.nativeIdx);
      }
      for (final sink in plan.looperSinks) {
        final clip = alooperEngine.clips[sink.clipSlotId];
        if (clip == null) continue;
        final source = plan.sources[sink.sourceIndex];
        if (source.kind == SourceKind.renderFunction) {
          host.addAudioLooperRenderSource(
            clip.nativeIdx,
            _renderFnFromHandle(source.renderFnHandle),
          );
        } else if (source.kind == SourceKind.vst3Plugin) {
          final ordIdx = vst3SlotOrder.indexOf(source.slotId);
          if (ordIdx >= 0) {
            host.addAudioLooperSourcePlugin(clip.nativeIdx, ordIdx);
          }
        }
      }
    }

    // Capture-mode toggles. Enabled when any source of the given group
    // is referenced by a chain or looper sink — matches the previous
    // `thereminHasRoute.isNotEmpty` / `vocoderHasRoute.isNotEmpty`
    // aggregates.
    bool captureActiveFor(CaptureModeGroup group) {
      for (var i = 0; i < plan.sources.length; i++) {
        if (plan.sources[i].captureGroup != group) continue;
        if (referencedSourceIndices.contains(i)) return true;
      }
      return false;
    }

    try {
      ffi.thereminSetCaptureMode(
          enabled: captureActiveFor(CaptureModeGroup.theremin));
      ffi.styloSetCaptureMode(
          enabled: captureActiveFor(CaptureModeGroup.stylophone));
      ffi.vocoderSetCaptureMode(
          enabled: captureActiveFor(CaptureModeGroup.vocoder));
    } catch (_) {
      // AudioInputFFI may not be initialised on web / minimal builds.
      // Silently ignore — routing is a no-op there anyway.
    }
  }

  /// Applies a single [InsertChainEntry] to the desktop host using the
  /// Phase H atomic chain-commit API.
  ///
  /// Three destination cases:
  ///   1. Empty chain + VST3 destination: register an external render
  ///      for each source, so the VST3 plugin receives the source's
  ///      dry audio on its audio input.
  ///   2. Non-empty chain (any destination): issue ONE
  ///      [VstHost.setMasterInsertChain] call with all source fns and
  ///      all effect handles in order. The Phase H native entry point
  ///      commits the chain atomically with no merge logic, so the
  ///      v2.13.0 "grésillement" topology (where the old merge
  ///      heuristic reordered chains and double-called source render
  ///      functions) cannot recur.
  ///   3. Empty chain + master mix: no call needed. The bare master-
  ///      render registration earlier in [_applyPlanDesktop] already
  ///      routes the source directly into the mix.
  void _applyChainDesktop({
    required VstHost host,
    required InsertChainEntry chain,
    required RoutingPlan plan,
  }) {
    // Case 1 — direct source → VST3 external render (no effects).
    if (chain.effects.isEmpty &&
        chain.destination.kind == ChainDestinationKind.vst3Plugin) {
      final vst3 = _plugins[chain.destination.slotId];
      if (vst3 == null) return;
      for (final sourceIndex in chain.sourceIndices) {
        final source = plan.sources[sourceIndex];
        if (source.kind != SourceKind.renderFunction) continue;
        host.setExternalRender(
          vst3,
          _renderFnFromHandle(source.renderFnHandle),
        );
      }
      return;
    }

    // Case 3 — no effects, no VST3 destination: nothing to do here.
    if (chain.effects.isEmpty) return;

    // Case 2 — atomic chain commit. Collect source render fns and
    // effect DSP handles into flat Dart lists, then hand the whole
    // chain to the native layer in one shot.
    final sourceFns = <
        Pointer<
            NativeFunction<
                Void Function(Pointer<Float>, Pointer<Float>, Int32)>>>[];
    for (final sourceIndex in chain.sourceIndices) {
      final source = plan.sources[sourceIndex];
      if (source.kind != SourceKind.renderFunction) continue;
      sourceFns.add(_renderFnFromHandle(source.renderFnHandle));
    }
    if (sourceFns.isEmpty) return;

    final dspHandles = [
      for (final effect in chain.effects)
        Pointer<Void>.fromAddress(effect.dspHandle),
    ];

    host.setMasterInsertChain(sourceFns: sourceFns, dspHandles: dspHandles);
  }

  /// Rehydrates a render function pointer from its opaque integer
  /// handle. The plan carries `int` addresses so it can be serialised
  /// and unit-tested without a `dart:ffi` dependency on the test side.
  Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>
      _renderFnFromHandle(int address) {
    return Pointer<
        NativeFunction<
            Void Function(Pointer<Float>, Pointer<Float>,
                Int32)>>.fromAddress(address);
  }

  // ─── GFPA native DSP effects ────────────────────────────────────────────────

  /// Create a native GFPA DSP instance for [pluginId] and store it under
  /// [slotId].  The DSP runs on the JACK audio thread once wired via
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
    // Size the DSP's internal scratch buffers for the largest block
    // JACK will ever deliver. PipeWire commonly uses 1024 or 2048 and
    // can bump up to 4096 on some systems; 8192 matches the native
    // host's `kStartupBuffer` floor for state vectors so every effect
    // can process a full JACK block without re-allocating. The old
    // hardcoded `256` was left over from a miniaudio-era assumption
    // and triggered a libstdc++ `operator[]` bounds assertion at
    // startup when JACK delivered 2048-frame blocks.
    final handle = _host!.createGfpaDsp(pluginId, 48000, 8192);
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

  /// Sets the bypass state of a GFPA DSP effect identified by [slotId].
  ///
  /// When [bypassed] is true, the native insert callback copies input to output
  /// unchanged — zero CPU cost on the audio thread (single atomic bool load).
  void setGfpaDspBypass(String slotId, bool bypassed) {
    final handle = _gfpaHandles[slotId];
    if (handle == null || handle == nullptr) return;

    if (Platform.isAndroid) {
      GfpaAndroidBindings.instance.gfpaDspSetBypass(handle, bypassed);
      return;
    }

    _host?.setGfpaDspBypass(handle, bypassed);
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
  /// Android routing sync — plan-driven since v2.13.x.
  ///
  /// Behaviour-identical to the previous hand-rolled Android branch, but
  /// delegated to a single [RoutingPlan] produced by the shared builder
  /// and applied by [_applyPlanAndroid]. The Android plan uses the
  /// [BackendCapabilities.oboe] profile, so VST3 routes are never
  /// emitted and sources are keyed by their Oboe bus slot ID rather
  /// than by function pointer.
  void _syncAudioRoutingAndroid(
      AudioGraph graph,
      List<PluginInstance> allPlugins,
      Map<String, int> keyboardSfIds) {
    final plan = _buildAndroidPlan(graph, allPlugins, keyboardSfIds);
    _applyPlanAndroid(plan: plan, allPlugins: allPlugins);
  }

  // ── Android plan builder + apply ─────────────────────────────────────────

  /// Produces a [RoutingPlan] for the Android Oboe backend. Keyboards and
  /// drum generators resolve via [keyboardSfIds] (the 1-based FluidSynth
  /// sfId is also the Oboe bus slot ID). Theremin / stylophone / vocoder /
  /// live input resolve to their fixed `kBusSlot*` constants. VST3
  /// instances are rejected — Android does not host VST3 at all.
  RoutingPlan _buildAndroidPlan(
    AudioGraph graph,
    List<PluginInstance> allPlugins,
    Map<String, int> keyboardSfIds,
  ) {
    // Defensive: capture the map at closure creation time so the resolver
    // callback sees the value the caller intended, even if the caller
    // mutates its local map later.
    final sfIds = Map<String, int>.of(keyboardSfIds);
    return buildRoutingPlan(
      plugins: allPlugins,
      graph: graph,
      caps: BackendCapabilities.oboe,
      resolveSource: (plugin) => _resolveAndroidSource(plugin, sfIds),
      resolveEffect: _resolveAndroidEffect,
    );
  }

  /// Android resolver: turns a plugin into an `oboeBusSlot` source entry
  /// with its bus slot ID in [ResolvedSource.busSlotId]. Returns `null`
  /// for VST3 plugins and for keyboards whose soundfont has not yet been
  /// loaded (the next routing sync will pick them up once they are).
  ///
  /// Phase B structure: same as [_resolveDesktopSource], the resolver
  /// switches on [AudioSourceKind] rather than runtime plugin types, so
  /// adding a new source kind without an Android case becomes a static
  /// analyser error rather than silent drop.
  ResolvedSource? _resolveAndroidSource(
    PluginInstance plugin,
    Map<String, int> keyboardSfIds,
  ) {
    if (plugin is! AudioSourcePlugin) return null;
    final descriptor =
        (plugin as AudioSourcePlugin).describeAudioSource();
    if (descriptor == null) return null;

    switch (descriptor.kind) {
      case AudioSourceKind.gfKeyboard:
      case AudioSourceKind.drumGenerator:
        // Keyboards and drum generator share the per-soundfont bus slot
        // ID. The drum generator plays MIDI on its declared channel and
        // relies on the keyboard FluidSynth on that channel — the same
        // bus slot owns its audio path.
        final sfId = keyboardSfIds[plugin.id] ?? -1;
        if (sfId < 1) return null; // not yet loaded — try again next sync.
        return ResolvedSource(
          kind: SourceKind.oboeBusSlot,
          handle: 0,
          busSlotId: sfId,
        );
      case AudioSourceKind.theremin:
        return const ResolvedSource(
          kind: SourceKind.oboeBusSlot,
          handle: 0,
          busSlotId: kBusSlotTheremin,
        );
      case AudioSourceKind.stylophone:
        return const ResolvedSource(
          kind: SourceKind.oboeBusSlot,
          handle: 0,
          busSlotId: kBusSlotStylophone,
        );
      case AudioSourceKind.vocoder:
        return const ResolvedSource(
          kind: SourceKind.oboeBusSlot,
          handle: 0,
          busSlotId: kBusSlotVocoder,
        );
      case AudioSourceKind.liveInput:
        return const ResolvedSource(
          kind: SourceKind.oboeBusSlot,
          handle: 0,
          busSlotId: kBusSlotLiveInput,
        );
      case AudioSourceKind.vst3Instrument:
        // VST3 is not hosted on Android — silently drop so downstream
        // cable resolution fails cleanly in the plan builder.
        return null;
    }
  }

  /// Android effect resolver: returns the native GFPA DSP handle for the
  /// slot as an `int` address, or `null` if no handle is registered yet.
  /// Identical shape to [_resolveDesktopEffect] — both platforms share
  /// the same `_gfpaHandles` map because `registerGfpaDsp` already
  /// branches on `Platform.isAndroid` internally.
  int? _resolveAndroidEffect(PluginInstance plugin) {
    final handle = _gfpaHandles[plugin.id];
    if (handle == null || handle == nullptr) return null;
    return handle.address;
  }

  /// Translates a [RoutingPlan] into Android Oboe-bus FFI calls.
  ///
  /// Mirrors the previous hand-rolled Android branch:
  ///
  ///   1. `gfpa_android_clear_all_inserts` wipes every per-bus insert chain.
  ///   2. For every insert chain in the plan whose destination is NOT the
  ///      audio looper: push each effect handle into *each* participating
  ///      source's bus slot via `gfpa_android_add_insert_for_sf`.
  ///   3. The Live Input Source bus slot is registered with Oboe only when
  ///      a Live Input appears in any chain or looper sink — matches the
  ///      "no raw mic in master when uncabled" rule from v2.13.0.
  ///   4. For every looper sink: call `alooperAddBusSource` with the root
  ///      source's bus slot ID (already walked past the effect chain by
  ///      the builder in Pass 3).
  ///
  /// The Android path does NOT need:
  ///   - `setExternalRender` — there is no external-render concept here.
  ///   - `routeAudio` — no VST3 → VST3 routes exist.
  ///   - Capture-mode toggles — theremin / stylo / vocoder are already
  ///     routed through the Oboe bus instead of their miniaudio playback
  ///     devices. The native-instrument lifecycle controller owns that
  ///     state on Android.
  void _applyPlanAndroid({
    required RoutingPlan plan,
    required List<PluginInstance> allPlugins,
  }) {
    // Phase H diagnostics: log every dropped shared-effect cable so
    // the user can see in logcat why part of their cable graph is
    // not producing the expected audio.
    for (final diag in plan.diagnostics) {
      debugPrint('[routing] $diag');
    }

    // Clear every per-source insert chain before rebuilding. The
    // Phase H atomic commit (`setChainForSlot`) replaces slots
    // individually, so wiping first guarantees stale effects from
    // last sync are gone.
    GfpaAndroidBindings.instance.gfpaAndroidClearAllInserts();

    // Determine which sources actually feed something downstream.
    // Used by both the Live Input bus-source toggle and as a belt to
    // filter out chains whose sources could not be resolved by the
    // builder (e.g. a VST3 source that returned null on Android).
    final referencedSourceIndices = <int>{};
    for (final chain in plan.insertChains) {
      referencedSourceIndices.addAll(chain.sourceIndices);
    }
    for (final sink in plan.looperSinks) {
      referencedSourceIndices.add(sink.sourceIndex);
    }

    // Phase H — atomic chain commit per bus slot.
    //
    // Android's native chain store is keyed by bus slot ID, one
    // chain per slot. Multi-source fan-in (e.g. two keyboards → one
    // reverb) cannot be represented as a shared chain because the
    // Oboe callback iterates bus slots independently, applying each
    // slot's chain to that slot's audio output alone. Sharing a
    // stateful DSP handle across two bus-slot chains would trigger
    // the v2.13.0 double-call bug again.
    //
    // Strategy: for each plan chain, commit its effect list to the
    // FIRST source's bus slot only. Subsequent sources of the same
    // chain output dry — a degraded but honest result. The plan
    // builder has already dedup'd across chains, so no DSP handle
    // is written into more than one bus slot by this loop.
    //
    // Users who actually want fan-in-with-effect on Android must
    // create one effect slot per source. A future Phase F.5 will
    // surface this as a patch-view warning.
    for (final chain in plan.insertChains) {
      if (chain.effects.isEmpty) continue;
      if (chain.sourceIndices.isEmpty) continue;

      // Pick the first resolvable source's bus slot. Skip any sources
      // that did not resolve to a bus slot (e.g. VST3 rejected on
      // Android — should not happen after the plan builder's own
      // capability filtering, but cheap to guard against).
      int? targetBusSlot;
      for (final sourceIndex in chain.sourceIndices) {
        final source = plan.sources[sourceIndex];
        if (source.kind != SourceKind.oboeBusSlot) continue;
        if (source.busSlotId < 0) continue;
        targetBusSlot = source.busSlotId;
        break;
      }
      if (targetBusSlot == null) continue;

      final dspHandles = [
        for (final effect in chain.effects)
          Pointer<Void>.fromAddress(effect.dspHandle),
      ];
      GfpaAndroidBindings.instance
          .gfpaAndroidSetChainForSlot(targetBusSlot, dspHandles);

      // Diagnostic for any additional sources that were dropped by
      // this one-slot strategy — helps the user realise why kb2's
      // reverb is missing when they cabled both keyboards into the
      // same effect.
      if (chain.sourceIndices.length > 1) {
        debugPrint(
          '[routing] Android: multi-source chain with effects '
          '${chain.effects.map((e) => e.slotId).toList()} committed '
          'to bus slot $targetBusSlot only. Additional sources in '
          'this chain will output dry — duplicate the effect slot '
          'to apply it to each source independently.',
        );
      }
    }

    // Live Input bus-source lifecycle. The Oboe bus mixer always sums
    // registered sources into the master output, so we only register
    // the live input when at least one Live Input Source slot is
    // referenced by a chain or a looper sink — matches the 2.13.0
    // "don't leak raw mic" rule.
    var liveInputActive = false;
    for (var i = 0; i < plan.sources.length; i++) {
      final source = plan.sources[i];
      if (source.kind != SourceKind.oboeBusSlot) continue;
      if (source.busSlotId != kBusSlotLiveInput) continue;
      if (!referencedSourceIndices.contains(i)) continue;
      liveInputActive = true;
      break;
    }
    NativeInstrumentController.instance
        .syncLiveInputBusSource(shouldBeActive: liveInputActive);

    // Audio looper cabled-input routing. Plan already walked upstream
    // past any effect chain, so each sink points at a root source's
    // index. Translate to `alooperAddBusSource` calls keyed by bus slot.
    final alooperEngine = audioLooperEngine;
    if (alooperEngine == null) return;

    // Clear all clip source lists up-front (mirrors the old behaviour).
    for (final clip in alooperEngine.clips.values) {
      AudioInputFFI().alooperClearSources(clip.nativeIdx);
    }
    for (final sink in plan.looperSinks) {
      final clip = alooperEngine.clips[sink.clipSlotId];
      if (clip == null) continue;
      final source = plan.sources[sink.sourceIndex];
      if (source.kind != SourceKind.oboeBusSlot) continue;
      if (source.busSlotId < 0) continue;
      AudioInputFFI().alooperAddBusSource(clip.nativeIdx, source.busSlotId);
    }
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
      // The drain spin-waits for the JACK/CoreAudio callback to finish at
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

