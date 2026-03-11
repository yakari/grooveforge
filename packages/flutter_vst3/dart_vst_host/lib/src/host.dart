/// High level wrappers over the native VST host bindings. These
/// classes manage resources using RAII and provide idiomatic Dart
/// APIs for loading plug‑ins, controlling parameters and processing
/// audio.
library;

import 'dart:ffi';
import 'dart:io';

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

  // ─── ALSA audio loop helpers ───────────────────────────────────────────────

  /// Register [plugin] with the host's ALSA audio thread.
  void addToAudioLoop(VstPlugin plugin) =>
      _b.dvhAudioAddPlugin(handle, plugin.handle);

  /// Remove [plugin] from the host's ALSA audio thread.
  void removeFromAudioLoop(VstPlugin plugin) =>
      _b.dvhAudioRemovePlugin(handle, plugin.handle);

  /// Clear all plugins from the host's ALSA audio thread.
  void clearAudioLoop() => _b.dvhAudioClearPlugins(handle);

  /// Start the ALSA output thread. [device] defaults to "default".
  bool startAlsaThread({String device = 'default'}) {
    final d = device.toNativeUtf8();
    final r = _b.dvhStartAlsaThread(handle, d);
    malloc.free(d);
    return r == 1;
  }

  /// Stop the ALSA output thread.
  void stopAlsaThread() => _b.dvhStopAlsaThread(handle);

  /// macOS: Start the CoreAudio/miniaudio output thread.
  bool startMacAudio() => _b.dvhMacStartAudio(handle) == 1;

  /// macOS: Stop the CoreAudio/miniaudio output thread.
  void stopMacAudio() => _b.dvhMacStopAudio(handle);

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