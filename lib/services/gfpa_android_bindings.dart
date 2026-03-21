import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ── Native function type definitions ─────────────────────────────────────────

/// Native signature for gfpa_dsp_create.
typedef _GfpaDspCreateNative = Pointer<Void> Function(
    Pointer<Utf8> pluginId, Int32 sampleRate, Int32 blockSize);

/// Dart binding for gfpa_dsp_create.
typedef _GfpaDspCreate = Pointer<Void> Function(
    Pointer<Utf8> pluginId, int sampleRate, int blockSize);

/// Native signature for gfpa_dsp_set_param.
typedef _GfpaDspSetParamNative = Void Function(
    Pointer<Void> handle, Pointer<Utf8> paramId, Double value);

/// Dart binding for gfpa_dsp_set_param.
typedef _GfpaDspSetParam = void Function(
    Pointer<Void> handle, Pointer<Utf8> paramId, double value);

/// Native signature for gfpa_dsp_destroy.
typedef _GfpaDspDestroyNative = Void Function(Pointer<Void> handle);

/// Dart binding for gfpa_dsp_destroy.
typedef _GfpaDspDestroy = void Function(Pointer<Void> handle);

/// Native signature for gfpa_android_add_insert_for_sf.
///
/// [sfId] is the 1-based soundfont ID returned by loadSoundfont.
/// [handle] is the opaque GFPA DSP handle to insert into that keyboard's chain.
typedef _GfpaAndroidAddInsertForSfNative = Void Function(
    Int32 sfId, Pointer<Void> handle);

/// Dart binding for gfpa_android_add_insert_for_sf.
typedef _GfpaAndroidAddInsertForSf = void Function(
    int sfId, Pointer<Void> handle);

/// Native signature for gfpa_android_remove_insert.
typedef _GfpaAndroidRemoveInsertNative = Void Function(Pointer<Void> handle);

/// Dart binding for gfpa_android_remove_insert.
typedef _GfpaAndroidRemoveInsert = void Function(Pointer<Void> handle);

/// Native signature for gfpa_android_clear_all_inserts.
typedef _GfpaAndroidClearAllInsertsNative = Void Function();

/// Dart binding for gfpa_android_clear_all_inserts.
typedef _GfpaAndroidClearAllInserts = void Function();

/// Native signature for gfpa_android_set_bpm.
typedef _GfpaAndroidSetBpmNative = Void Function(Double bpm);

/// Dart binding for gfpa_android_set_bpm.
typedef _GfpaAndroidSetBpm = void Function(double bpm);

// ── GfpaAndroidBindings ───────────────────────────────────────────────────────

/// FFI bindings for the GFPA Android DSP functions exported from
/// `libnative-lib.so` (the `flutter_midi_pro` native library).
///
/// On Android, `libnative-lib.so` bundles both FluidSynth audio and the
/// GFPA DSP insert chain (reverb, delay, wah, EQ, compressor, chorus).
/// This class provides Dart access to the insert-chain management API and
/// to the core DSP create/set-param/destroy lifecycle.
///
/// Usage:
/// ```dart
/// final h = GfpaAndroidBindings.instance.createDsp('com.grooveforge.reverb');
/// GfpaAndroidBindings.instance.gfpaDspSetParam(h, 'mix', 0.4);
/// GfpaAndroidBindings.instance.gfpaAndroidAddInsertForSf(sfId, h);
/// // … later …
/// GfpaAndroidBindings.instance.gfpaAndroidRemoveInsert(h);
/// GfpaAndroidBindings.instance.gfpaDspDestroy(h);
/// ```
class GfpaAndroidBindings {
  /// Singleton accessor.  Initialised once on first access.
  static final GfpaAndroidBindings instance = GfpaAndroidBindings._();

  GfpaAndroidBindings._() {
    // Open the shared library that contains both the Flutter MIDI Pro JNI
    // entry points and the GFPA DSP insert-chain symbols.
    _lib = DynamicLibrary.open('libnative-lib.so');
  }

  late final DynamicLibrary _lib;

  // ── Lazy FFI bindings ────────────────────────────────────────────────────

  /// Create a native GFPA DSP instance for [pluginId].
  ///
  /// Returns nullptr for unrecognised plugin IDs.
  late final _GfpaDspCreate _gfpaDspCreate =
      _lib.lookupFunction<_GfpaDspCreateNative, _GfpaDspCreate>(
          'gfpa_dsp_create');

  /// Set a DSP parameter using its string ID and physical (denormalised) value.
  ///
  /// Thread-safe: may be called from the Dart isolate while the Oboe thread
  /// runs — the native implementation uses std::atomic internally.
  late final _GfpaDspSetParam _gfpaDspSetParam =
      _lib.lookupFunction<_GfpaDspSetParamNative, _GfpaDspSetParam>(
          'gfpa_dsp_set_param');

  /// Destroy a native GFPA DSP instance and free its resources.
  ///
  /// The caller must call [gfpaAndroidRemoveInsert] before destroying the
  /// handle to prevent a dangling function pointer on the audio thread.
  late final _GfpaDspDestroy _gfpaDspDestroy =
      _lib.lookupFunction<_GfpaDspDestroyNative, _GfpaDspDestroy>(
          'gfpa_dsp_destroy');

  /// Register a DSP handle as an insert in the per-keyboard chain for [sfId].
  ///
  /// [sfId] is the 1-based soundfont ID returned by [loadSoundfont].
  /// The effect will only be applied to the audio from that keyboard slot.
  /// Idempotent: calling again with the same handle and sfId has no effect.
  late final _GfpaAndroidAddInsertForSf _gfpaAndroidAddInsertForSf = _lib
      .lookupFunction<_GfpaAndroidAddInsertForSfNative,
          _GfpaAndroidAddInsertForSf>('gfpa_android_add_insert_for_sf');

  /// Remove a DSP handle from whichever per-keyboard chain it belongs to.
  ///
  /// Searches all chains.  No-op if the handle is not currently registered.
  late final _GfpaAndroidRemoveInsert _gfpaAndroidRemoveInsert = _lib
      .lookupFunction<_GfpaAndroidRemoveInsertNative, _GfpaAndroidRemoveInsert>(
          'gfpa_android_remove_insert');

  /// Clear every insert from every per-keyboard chain.
  ///
  /// Should be called at the start of each [syncAudioRouting] rebuild so that
  /// stale registrations from prior configurations are cleared.
  late final _GfpaAndroidClearAllInserts _gfpaAndroidClearAllInserts = _lib
      .lookupFunction<_GfpaAndroidClearAllInsertsNative,
          _GfpaAndroidClearAllInserts>('gfpa_android_clear_all_inserts');

  /// Forward the current transport BPM to all BPM-synced GFPA effects.
  ///
  /// Stores the value atomically; the Oboe thread reads it without locking.
  late final _GfpaAndroidSetBpm _gfpaAndroidSetBpm =
      _lib.lookupFunction<_GfpaAndroidSetBpmNative, _GfpaAndroidSetBpm>(
          'gfpa_android_set_bpm');

  // ── Public API ────────────────────────────────────────────────────────────

  /// Create a native DSP instance for [pluginId].
  ///
  /// Converts [pluginId] to a native UTF-8 string, calls [gfpa_dsp_create],
  /// frees the temporary string, and returns the opaque handle.
  ///
  /// [sampleRate] — output sample rate in Hz (default 48000).
  /// [blockSize]  — maximum block size in frames (default 512).
  ///
  /// Returns [nullptr] if [pluginId] is not recognised by the native DSP.
  Pointer<Void> createDsp(String pluginId,
      {int sampleRate = 48000, int blockSize = 512}) {
    final nativeId = pluginId.toNativeUtf8();
    try {
      return _gfpaDspCreate(nativeId, sampleRate, blockSize);
    } finally {
      malloc.free(nativeId);
    }
  }

  /// Set a physical parameter value on an existing DSP handle.
  ///
  /// [handle]        — handle returned by [createDsp].
  /// [paramId]       — parameter string ID (e.g. "mix", "time", "depth").
  /// [physicalValue] — value in the parameter's declared range.
  void gfpaDspSetParam(Pointer<Void> handle, String paramId,
      double physicalValue) {
    final nativeParam = paramId.toNativeUtf8();
    try {
      _gfpaDspSetParam(handle, nativeParam, physicalValue);
    } finally {
      malloc.free(nativeParam);
    }
  }

  /// Destroy a native DSP instance.
  ///
  /// Call [gfpaAndroidRemoveInsert] first to avoid a dangling pointer on the
  /// audio thread.
  void gfpaDspDestroy(Pointer<Void> handle) => _gfpaDspDestroy(handle);

  /// Register [handle] as an insert in the per-keyboard chain for [sfId].
  ///
  /// [sfId] is the 1-based soundfont ID returned by [loadSoundfont].
  void gfpaAndroidAddInsertForSf(int sfId, Pointer<Void> handle) =>
      _gfpaAndroidAddInsertForSf(sfId, handle);

  /// Remove [handle] from whichever per-keyboard chain it belongs to.
  void gfpaAndroidRemoveInsert(Pointer<Void> handle) =>
      _gfpaAndroidRemoveInsert(handle);

  /// Clear every insert from every per-keyboard chain.
  void gfpaAndroidClearAllInserts() => _gfpaAndroidClearAllInserts();

  /// Forward [bpm] to all BPM-synced GFPA effects (delay, wah, chorus).
  void gfpaAndroidSetBpm(double bpm) => _gfpaAndroidSetBpm(bpm);
}
