/// High level wrappers over the native VST host bindings. These
/// classes manage resources using RAII and provide idiomatic Dart
/// APIs for loading plug‑ins, controlling parameters and processing
/// audio.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'bindings.dart';

/// Represents a running host context. A host owns its VST plug‑ins
/// and must be disposed when no longer needed.
class VstHost {
  final NativeBindings _b;
  final Pointer<Void> handle;

  VstHost._(this._b, this.handle);

  /// Create a new host at the given sample rate and maximum block
  /// size. Optionally specify [dylibPath] to load the native
  /// library from a custom location. Throws StateError on failure.
  static VstHost create({required double sampleRate, required int maxBlock, String? dylibPath}) {
    final b = NativeBindings(loadDvh(path: dylibPath));
    final h = b.dvhCreateHost(sampleRate, maxBlock);
    if (h == nullptr) {
      throw StateError('Failed to create host');
    }
    final host = VstHost._(b, h);
    debugPrint('VstHost: version ${host.getVersion()}');
    return host;
  }

  /// Get the version string of the native VST host library.
  String getVersion() => _b.dvhGetVersion().toDartString();

  /// Release resources associated with this host. After calling
  /// dispose(), the host handle is invalid and should not be used.
  void dispose() {
    _b.dvhDestroyHost(handle);
  }

  /// Set the global transport state for all plugins.
  void setTransport({
    required double bpm,
    required int timeSigNum,
    required int timeSigDen,
    required bool isPlaying,
    required double positionInBeats,
    required int positionInSamples,
  }) {
    _b.dvhSetTransport(bpm, timeSigNum, timeSigDen, isPlaying ? 1 : 0, positionInBeats, positionInSamples);
  }

  // ─── JACK audio client helpers ──────────────────────────────────────────────

  /// Register [plugin] with the host's JACK audio callback.
  void addToAudioLoop(VstPlugin plugin) =>
      _b.dvhAudioAddPlugin(handle, plugin.handle);

  /// Remove [plugin] from the host's JACK audio callback.
  void removeFromAudioLoop(VstPlugin plugin) =>
      _b.dvhAudioRemovePlugin(handle, plugin.handle);

  /// Clear all plugins from the host's JACK audio callback.
  void clearAudioLoop() => _b.dvhAudioClearPlugins(handle);

  /// Start a JACK client and activate it.  Registers stereo output ports
  /// ("out_L", "out_R") and auto-connects to system playback.
  /// [clientName] defaults to "GrooveForge".
  bool startJackClient({String clientName = 'GrooveForge'}) {
    final n = clientName.toNativeUtf8();
    final r = _b.dvhStartJackClient(handle, n);
    malloc.free(n);
    return r == 1;
  }

  /// Stop the JACK client.  Deactivates and closes it.
  void stopJackClient() => _b.dvhStopJackClient(handle);

  /// Return the cumulative XRUN count since the JACK client was started.
  /// Useful for surfacing latency warnings in the UI.
  int getXrunCount() => _b.dvhJackGetXrunCount(handle);

  /// Start the desktop miniaudio playback thread (macOS CoreAudio,
  /// Windows WASAPI). miniaudio picks the OS backend automatically.
  /// Linux uses [startJackClient] instead.
  bool startDesktopAudio() => _b.dvhStartDesktopAudio(handle) == 1;

  /// Stop the desktop miniaudio playback thread (macOS + Windows).
  void stopDesktopAudio() => _b.dvhStopDesktopAudio(handle);

  // ─── Audio graph routing (Phase 5.4) ──────────────────────────────────────

  /// Set the topological processing order for the audio callback.
  ///
  /// [ordered] must list ALL plugins that should be processed, in the order
  /// sources come before the effects that consume their output.
  /// Pass an empty list to restore the default insertion order.
  void setProcessingOrder(List<VstPlugin> ordered) {
    if (ordered.isEmpty) {
      _b.dvhSetProcessingOrder(handle, nullptr, 0);
      return;
    }
    final arr = calloc<Pointer<Void>>(ordered.length);
    for (int i = 0; i < ordered.length; i++) {
      arr[i] = ordered[i].handle;
    }
    _b.dvhSetProcessingOrder(handle, arr, ordered.length);
    calloc.free(arr);
  }

  /// Route [from]'s stereo output to [to]'s audio input.
  ///
  /// [from]'s output will no longer be mixed directly into the master
  /// output — it feeds exclusively into [to]'s input instead. [from] must
  /// precede [to] in the processing order set via [setProcessingOrder].
  void routeAudio(VstPlugin from, VstPlugin to) =>
      _b.dvhRouteAudio(handle, from.handle, to.handle);

  /// Remove all audio routing rules. Every plugin's output returns to the
  /// default behaviour of mixing directly into the master output.
  void clearRoutes() => _b.dvhClearRoutes(handle);

  /// Register a non-VST3 render function as the audio source for [plugin]'s
  /// input. The JACK audio thread will call [renderFn] each block to fill the
  /// plugin's stereo input buffer, bypassing silence or upstream VST3 output.
  ///
  /// [renderFn] is a raw pointer to a C function with signature:
  ///   `void render(float* outL, float* outR, int32_t frames)`
  /// Obtain it via `DynamicLibrary.lookup<NativeFunction<...>>('symbol')`.
  ///
  /// Typical use: route Theremin or Stylophone audio into a VST3 effect.
  void setExternalRender(
    VstPlugin plugin,
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>> renderFn,
  ) => _b.dvhSetExternalRender(handle, plugin.handle, renderFn);

  /// Remove the external render registration for [plugin].
  /// The plugin's input reverts to silence or its routed upstream VST3 output.
  void clearExternalRender(VstPlugin plugin) =>
      _b.dvhClearExternalRender(handle, plugin.handle);

  /// Register [renderFn] as a master-mix audio contributor.
  ///
  /// The JACK audio thread calls [renderFn] every block and mixes its stereo output
  /// directly into the master bus alongside VST3 plugin outputs. Used for
  /// GF Keyboard (libfluidsynth) when it is not routed through a VST3 effect.
  ///
  /// Adding the same pointer twice is a no-op (deduplicated in C).
  void addMasterRender(
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>> renderFn,
  ) => _b.dvhAddMasterRender(handle, renderFn);

  /// Remove a previously registered master-mix contributor.
  ///
  /// No-op if [renderFn] was not registered. Call before switching to an
  /// external-render VST3 route.
  void removeMasterRender(
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>> renderFn,
  ) => _b.dvhRemoveMasterRender(handle, renderFn);

  // ─── GFPA native DSP effects ───────────────────────────────────────────────

  /// Create a native GFPA DSP instance for [pluginId].
  ///
  /// [pluginId] must be a recognised built-in effect ID such as
  /// `"com.grooveforge.reverb"`. Returns a non-null [Pointer<Void>] on success
  /// or [nullptr] for unrecognised IDs.
  ///
  /// [sampleRate] and [blockSize] must match the values used to start the
  /// JACK client so that delay-line buffers are sized correctly.
  Pointer<Void> createGfpaDsp(String pluginId, int sampleRate, int blockSize) {
    final id = pluginId.toNativeUtf8();
    final result = _b.gfpaDspCreate(id, sampleRate, blockSize);
    malloc.free(id);
    return result;
  }

  /// Destroy a GFPA DSP instance previously created with [createGfpaDsp].
  ///
  /// The caller must remove the insert from the chain via
  /// [removeMasterInsert] before calling this to avoid dangling callbacks.
  void destroyGfpaDsp(Pointer<Void> dspHandle) =>
      _b.gfpaDspDestroy(dspHandle);

  /// Set a physical (denormalized) parameter value on a live DSP instance.
  ///
  /// [paramId] is the string key from the .gfpd file (e.g. `"room_size"`).
  /// [physicalValue] is the raw value in the parameter's declared range
  /// (e.g. 1200.0 Hz for the wah center frequency).
  void setGfpaDspParam(Pointer<Void> dspHandle, String paramId, double physicalValue) {
    final id = paramId.toNativeUtf8();
    _b.gfpaDspSetParam(dspHandle, id, physicalValue);
    malloc.free(id);
  }

  /// Set the bypass state of a GFPA DSP instance.
  ///
  /// When [bypassed] is true, the effect's insert callback copies input to
  /// output unchanged — zero CPU cost, zero latency.
  /// Thread-safe: the native side uses std::atomic<bool>.
  void setGfpaDspBypass(Pointer<Void> dspHandle, bool bypassed) =>
      _b.gfpaDspSetBypass(dspHandle, bypassed);

  /// Set the global BPM for all BPM-synced GFPA effects (delay, wah, chorus).
  void setGfpaBpm(double bpm) => _b.gfpaSetBpm(bpm);

  /// Phase H — atomically install ONE complete master insert chain.
  ///
  /// This is the routing adapter's preferred entry point. Unlike
  /// [addMasterInsert] which relies on a per-call merge heuristic
  /// that can produce wrong chains when the same DSP is reachable
  /// from divergent upstream sources (the v2.13.0 "grésillement"
  /// bug), this method commits the whole `(sources[], effects[])`
  /// pair in a single native call with no merge logic.
  ///
  /// Contract: each [dspHandles] entry MUST be unique across every
  /// chain committed to this host between `clearMasterInserts()`
  /// calls. The plan builder dedups shared DSPs upstream of this
  /// wrapper; the native side does not re-check.
  ///
  /// Allocates native scratch arrays, calls into the host, and frees
  /// the arrays before returning. Safe to call from the Dart isolate.
  void setMasterInsertChain({
    required List<
            Pointer<
                NativeFunction<
                    Void Function(Pointer<Float>, Pointer<Float>, Int32)>>>
        sourceFns,
    required List<Pointer<Void>> dspHandles,
  }) {
    if (sourceFns.isEmpty) return;

    // Allocate temporary native arrays for sources, effect fns, and
    // effect userdatas. All three are typed as `Pointer<Pointer<Void>>`
    // to match the FFI binding, which keeps the function pointers
    // weakly typed so that `gfpaDspInsertFn` (which returns
    // `Pointer<Void>`) can be stored without per-entry casts.
    //
    // The three arrays are freed in the `finally` block so a failure
    // during effect-fn lookup cannot leak native memory.
    final srcArr = calloc<Pointer<Void>>(sourceFns.length);
    final fxArr = dspHandles.isEmpty
        ? nullptr.cast<Pointer<Void>>()
        : calloc<Pointer<Void>>(dspHandles.length);
    final udArr = dspHandles.isEmpty
        ? nullptr.cast<Pointer<Void>>()
        : calloc<Pointer<Void>>(dspHandles.length);

    try {
      for (var i = 0; i < sourceFns.length; i++) {
        // A function pointer and a `Pointer<Void>` share the same ABI,
        // so a cast is enough — no conversion happens at runtime.
        srcArr[i] = sourceFns[i].cast<Void>();
      }
      for (var i = 0; i < dspHandles.length; i++) {
        fxArr[i] = _b.gfpaDspInsertFn(dspHandles[i]);
        udArr[i] = _b.gfpaDspUserdata(dspHandles[i]);
      }
      _b.dvhSetMasterInsertChain(
        handle,
        srcArr,
        sourceFns.length,
        fxArr,
        udArr,
        dspHandles.length,
      );
    } finally {
      calloc.free(srcArr);
      if (dspHandles.isNotEmpty) {
        calloc.free(fxArr);
        calloc.free(udArr);
      }
    }
  }

  /// Remove all inserts for [sourceFn] from the chain.
  void removeMasterInsert(
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>> sourceFn,
  ) => _b.dvhRemoveMasterInsert(handle, sourceFn);

  /// Remove the insert matching [dspHandle] from all source chains, then
  /// drain — waits for the audio callback to complete at least one full block
  /// so that any in-flight raw pointer to this DSP has retired.
  ///
  /// **Must be called BEFORE [destroyGfpaDsp]** to prevent use-after-free
  /// crashes on the JACK / CoreAudio audio thread.
  void removeMasterInsertByHandle(Pointer<Void> dspHandle) =>
      _b.dvhRemoveMasterInsertByHandle(handle, dspHandle);

  /// Remove all registered master inserts (all fan-in chains).
  ///
  /// Call at the beginning of each syncAudioRouting rebuild.
  void clearMasterInserts() => _b.dvhClearMasterInserts(handle);

  /// Remove all registered master render contributors.
  ///
  /// Call at the beginning of each syncAudioRouting rebuild so that stale
  /// entries from previous routing states (e.g. a Theremin that was connected
  /// before but now has no cables) are not left in the list.
  void clearMasterRenders() => _b.dvhClearMasterRenders(handle);

  // ── Audio Looper ────────────────────────────────────────────────────────

  /// Create a new audio looper clip with [maxSeconds] of pre-allocated buffer.
  /// Returns the clip index (0–7) or -1 if the pool is full.
  int createAudioLooperClip(double maxSeconds, {int sampleRate = 48000}) =>
      _b.alooperCreate(handle, maxSeconds, sampleRate);

  /// Destroy clip [idx] and free its buffers.
  void destroyAudioLooperClip(int idx) => _b.alooperDestroy(handle, idx);

  /// Set the state of clip [idx] (see ALooperState enum in audio_looper.h).
  void setAudioLooperState(int idx, int state) =>
      _b.alooperSetState(handle, idx, state);

  /// Read the current state of clip [idx].
  int getAudioLooperState(int idx) => _b.alooperGetState(handle, idx);

  /// Erases the recorded PCM data for clip [idx] without changing its
  /// state. Used by Dart's [AudioLooperEngine.clear] to wipe the audio
  /// while keeping the clip slot alive — separate from `setState(IDLE)`
  /// so that pausing playback does not discard recorded content.
  void clearAudioLooperData(int idx) => _b.alooperClearData(idx);

  /// Set playback volume (0.0–1.0) for clip [idx].
  void setAudioLooperVolume(int idx, double volume) =>
      _b.alooperSetVolume(handle, idx, volume);

  /// Toggle reverse playback for clip [idx].
  void setAudioLooperReversed(int idx, bool reversed) =>
      _b.alooperSetReversed(handle, idx, reversed ? 1 : 0);

  /// Remove all audio sources from clip [idx].
  void clearAudioLooperSources(int idx) => _b.alooperClearSources(idx);

  /// Add a render function as an audio source for clip [idx].
  /// Multiple sources are mixed (summed) by the JACK callback.
  void addAudioLooperRenderSource(int idx,
      Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>> fn) =>
      _b.alooperAddRenderSource(idx, fn);

  /// Add a VST3 plugin output as an audio source for clip [idx].
  void addAudioLooperSourcePlugin(int idx, int pluginOrdinalIdx) =>
      _b.alooperAddSourcePlugin(idx, pluginOrdinalIdx);

  /// Enable or disable bar-sync for clip [idx].
  void setAudioLooperBarSync(int idx, bool enabled) =>
      _b.alooperSetBarSync(idx, enabled ? 1 : 0);

  /// Set the number of bars to skip before recording starts (count-in).
  void setAudioLooperSkipBars(int idx, int bars) =>
      _b.alooperSetSkipBars(idx, bars);

  /// Set target loop length in beats.  0 = record until manually stopped.
  void setAudioLooperLengthBeats(int idx, double lengthBeats) =>
      _b.alooperSetLengthBeats(handle, idx, lengthBeats);

  /// Raw pointer to the left channel PCM data (for WAV export).
  Pointer<Float> getAudioLooperDataL(int idx) => _b.alooperGetDataL(handle, idx);

  /// Raw pointer to the right channel PCM data (for WAV export).
  Pointer<Float> getAudioLooperDataR(int idx) => _b.alooperGetDataR(handle, idx);

  /// Returns the left channel PCM data as a Dart Float32List view.
  /// Returns null if the clip has no data.
  Float32List? getAudioLooperDataAsListL(int idx, int length) {
    if (length <= 0) return null;
    final ptr = _b.alooperGetDataL(handle, idx);
    if (ptr == nullptr) return null;
    return ptr.asTypedList(length);
  }

  /// Returns the right channel PCM data as a Dart Float32List view.
  Float32List? getAudioLooperDataAsListR(int idx, int length) {
    if (length <= 0) return null;
    final ptr = _b.alooperGetDataR(handle, idx);
    if (ptr == nullptr) return null;
    return ptr.asTypedList(length);
  }

  /// Current recorded length in frames.
  int getAudioLooperLength(int idx) => _b.alooperGetLength(handle, idx);

  /// Pre-allocated capacity in frames.
  int getAudioLooperCapacity(int idx) => _b.alooperGetCapacity(handle, idx);

  /// Current playback/record head position in frames.
  int getAudioLooperHead(int idx) => _b.alooperGetHead(handle, idx);

  /// Total memory used by all audio looper clips (bytes).
  int getAudioLooperMemoryUsed() => _b.alooperMemoryUsed(handle);

  /// Load PCM data into clip [idx] from Dart-side Float32Lists.
  /// Returns true on success.
  bool loadAudioLooperData(int idx, Pointer<Float> srcL, Pointer<Float> srcR,
          int lengthFrames) =>
      _b.alooperLoadData(handle, idx, srcL, srcR, lengthFrames) == 1;

  /// Load a VST plug‑in from [modulePath]. Optionally specify
  /// [classUid] to select a specific class from a multi‑class module.
  /// Returns a VstPlugin on success; throws StateError on failure.
  VstPlugin load(String modulePath, {String? classUid}) {
    debugPrint('🔍 DIAGNOSTIC: Attempting to load VST plugin from: $modulePath');
    debugPrint('🔍 DIAGNOSTIC: classUid: ${classUid ?? "null"}');
    
    // Check if path exists (could be file or directory for VST3 bundles)
    final fileEntity = FileSystemEntity.typeSync(modulePath);
    if (fileEntity == FileSystemEntityType.notFound) {
      debugPrint('❌ DIAGNOSTIC: Path does not exist: $modulePath');
      throw StateError('VST plugin not found: $modulePath');
    }
    debugPrint('🔍 DIAGNOSTIC: Path exists, type: $fileEntity');
    
    // For .vst3 bundles, check for the actual shared library
    if (modulePath.endsWith('.vst3')) {
      debugPrint('🔍 DIAGNOSTIC: VST3 bundle detected, checking for shared library...');
      final vst3Dir = Directory(modulePath);
      if (!vst3Dir.existsSync()) {
        debugPrint('❌ DIAGNOSTIC: VST3 bundle directory does not exist');
        throw StateError('VST3 bundle not found: $modulePath');
      }
      
      // Check for architecture-specific libraries
      final archPaths = [
        '$modulePath/Contents/aarch64-linux',
        '$modulePath/Contents/arm64-linux', 
        '$modulePath/Contents/x86_64-linux',
        '$modulePath/Contents/Linux',
        '$modulePath/Contents/linux'
      ];
      
      debugPrint('🔍 DIAGNOSTIC: Searching for shared libraries in VST3 bundle...');
      for (final archPath in archPaths) {
        if (Directory(archPath).existsSync()) {
          debugPrint('📁 DIAGNOSTIC: Found architecture directory: $archPath');
          final files = Directory(archPath).listSync();
          for (final f in files) {
            if (f.path.endsWith('.so')) {
              debugPrint('📄 DIAGNOSTIC: Found .so file: ${f.path}');
              
              // Check architecture of the .so file using readelf
              try {
                final result = Process.runSync('readelf', ['-h', f.path]);
                if (result.exitCode == 0) {
                  final output = result.stdout.toString();
                  debugPrint('🔍 DIAGNOSTIC: Library architecture info:');
                  final lines = output.split('\n');
                  for (final line in lines) {
                    if (line.contains('Machine:') || line.contains('Class:')) {
                      debugPrint('  $line');
                    }
                  }
                }
              } catch (e) {
                debugPrint('⚠️ DIAGNOSTIC: Could not run readelf: $e');
              }
              
              // Try to detect if it's x86_64 or ARM
              final isX86 = archPath.contains('x86_64');
              final isArm = archPath.contains('aarch64') || archPath.contains('arm64');
              
              if (isX86) {
                debugPrint('⚠️ DIAGNOSTIC: This appears to be an x86_64 binary');
                debugPrint('⚠️ DIAGNOSTIC: Current system architecture: ${Platform.version.contains('arm') ? 'ARM' : 'Unknown'}');
              } else if (isArm) {
                debugPrint('✅ DIAGNOSTIC: This appears to be an ARM binary');
              }
            }
          }
        }
      }
    }
    
    debugPrint('🔍 DIAGNOSTIC: Calling native dvhLoadPlugin...');
    final p = modulePath.toNativeUtf8();
    final uid = classUid == null ? nullptr : classUid.toNativeUtf8();
    final h = _b.dvhLoadPlugin(handle, p, uid);
    malloc.free(p);
    if (uid != nullptr) malloc.free(uid);
    
    if (h == nullptr) {
      debugPrint('❌ DIAGNOSTIC: dvhLoadPlugin returned nullptr');
      debugPrint('❌ DIAGNOSTIC: Possible causes:');
      debugPrint('  1. VST plugin architecture mismatch (x86_64 plugin on ARM system)');
      debugPrint('  2. Missing dependencies (VST3 SDK not properly linked)');
      debugPrint('  3. Invalid VST3 bundle structure');
      debugPrint('  4. Plugin requires specific host features not implemented');
      throw StateError('Failed to load plugin from $modulePath - check diagnostics above');
    }
    
    debugPrint('✅ DIAGNOSTIC: Plugin loaded successfully, handle: $h');
    return VstPlugin._(_b, h);
  }
}

/// Information about a plug‑in parameter. The [id] can be passed
/// to getParamNormalized() and setParamNormalized().
/// [unitId] groups this parameter with related parameters (see IUnitInfo).
class ParamInfo {
  final int id;
  final String title;
  final String units;
  final int unitId;
  ParamInfo(this.id, this.title, this.units, [this.unitId = -1]);
}

/// Represents a loaded VST plug‑in. Provides methods for
/// starting/stopping processing, handling MIDI events and
/// manipulating parameters. Instances must be unloaded when no
/// longer needed.
class VstPlugin {
  final NativeBindings _b;
  final Pointer<Void> handle;
  VstPlugin._(this._b, this.handle);

  /// Activate the plug‑in with the given sample rate and block size.
  bool resume({required double sampleRate, required int maxBlock}) =>
      _b.dvhResume(handle, sampleRate, maxBlock) == 1;

  /// Deactivate processing. Returns true on success.
  bool suspend() => _b.dvhSuspend(handle) == 1;

  /// Release this plug‑in from the host. After calling unload() the
  /// handle is invalid. Further calls on this instance will throw.
  void unload() => _b.dvhUnloadPlugin(handle);

  /// Number of parameters exposed by this plug‑in.
  int paramCount() => _b.dvhParamCount(handle);

  /// Get information about a parameter by index, including its unit group ID.
  /// Throws StateError if index is out of range or retrieval fails.
  ParamInfo paramInfoAt(int index) {
    final id = malloc<Int32>();
    final title = malloc.allocate<Utf8>(256);
    final units = malloc.allocate<Utf8>(64);
    try {
      final ok = _b.dvhParamInfo(handle, index, id, title, 256, units, 64) == 1;
      if (!ok) throw StateError('param info failed');
      final unitId = _b.dvhParamUnitId(handle, index);
      return ParamInfo(id.value, title.toDartString(), units.toDartString(), unitId);
    } finally {
      malloc.free(id);
      malloc.free(title);
      malloc.free(units);
    }
  }

  /// Number of parameter groups (units) declared by the plugin.
  /// Returns 0 if the plugin does not implement IUnitInfo.
  int unitCount() => _b.dvhUnitCount(handle);

  /// Name of the unit (group) with the given [unitId].
  /// Returns null if not found or IUnitInfo is not available.
  String? unitNameForId(int unitId) {
    final buf = malloc.allocate<Utf8>(128);
    try {
      final ok = _b.dvhUnitName(handle, unitId, buf, 128) == 1;
      return ok ? buf.toDartString() : null;
    } finally {
      malloc.free(buf);
    }
  }

  /// Get the normalized value of a parameter by ID.
  double getParamNormalized(int paramId) => _b.dvhGetParam(handle, paramId);

  /// Set the normalized value of a parameter by ID. Returns true on
  /// success.
  bool setParamNormalized(int paramId, double value) =>
      _b.dvhSetParam(handle, paramId, value) == 1;

  /// Send a MIDI note on event. Channel is zero‑based.
  bool noteOn(int channel, int note, double velocity) =>
      _b.dvhNoteOn(handle, channel, note, velocity) == 1;

  /// Send a MIDI note off event.
  bool noteOff(int channel, int note, double velocity) =>
      _b.dvhNoteOff(handle, channel, note, velocity) == 1;

  // ─── Plugin editor GUI ────────────────────────────────────────────────────

  /// Open the plugin's native editor in a standalone X11 window (Linux only).
  /// Returns the X11 Window ID on success, 0 if the plugin has no GUI.
  int openEditor({String title = 'Plugin Editor'}) {
    final t = title.toNativeUtf8();
    final r = _b.dvhOpenEditor(handle, t);
    malloc.free(t);
    return r;
  }

  /// Close the editor window opened by [openEditor].
  void closeEditor() => _b.dvhCloseEditor(handle);

  /// Returns true if an editor window is currently open.
  bool get isEditorOpen => _b.dvhEditorIsOpen(handle) == 1;

  /// macOS: Open the plugin's native editor in a standalone Cocoa window.
  int openMacEditor({String title = 'Plugin Editor'}) {
    final t = title.toNativeUtf8();
    final r = _b.dvhMacOpenEditor(handle, t);
    malloc.free(t);
    return r;
  }

  /// macOS: Close the editor window.
  void closeMacEditor() => _b.dvhMacCloseEditor(handle);

  /// macOS: Returns true if an editor window is currently open.
  bool get isMacEditorOpen => _b.dvhMacEditorIsOpen(handle) == 1;

  /// Process a block of stereo audio. The input and output lists must
  /// all have the same length. Returns true on success.
  bool processStereoF32(Float32List inL, Float32List inR, Float32List outL, Float32List outR) {
    if (inL.length != inR.length || inL.length != outL.length || inL.length != outR.length) {
      throw ArgumentError('All buffers must have same length');
    }
    final n = inL.length;
    final pInL = malloc<Float>(n);
    final pInR = malloc<Float>(n);
    final pOutL = malloc<Float>(n);
    final pOutR = malloc<Float>(n);
    try {
      pInL.asTypedList(n).setAll(0, inL);
      pInR.asTypedList(n).setAll(0, inR);
      final ok = _b.dvhProcessStereoF32(handle, pInL, pInR, pOutL, pOutR, n) == 1;
      if (!ok) return false;
      outL.setAll(0, pOutL.asTypedList(n));
      outR.setAll(0, pOutR.asTypedList(n));
      return true;
    } finally {
      malloc.free(pInL);
      malloc.free(pInR);
      malloc.free(pOutL);
      malloc.free(pOutR);
    }
  }
}