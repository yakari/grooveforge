import 'dart:ffi';

import 'package:ffi/ffi.dart';

// ── AAudio bus slot ID constants ──────────────────────────────────────────────
//
// These mirror the OBOE_BUS_SLOT_* #defines in oboe_stream_android.h.
// GF Keyboard slots use FluidSynth sfIds (assigned sequentially from 1) as
// their bus slot IDs.  Instrument slots are placed at 100+ to guarantee they
// never collide with any sfId regardless of how many soundfonts are loaded.

/// AAudio bus slot ID for the Theremin.  Matches OBOE_BUS_SLOT_THEREMIN (100).
const int kBusSlotTheremin = 100;

/// AAudio bus slot ID for the Stylophone.  Matches OBOE_BUS_SLOT_STYLOPHONE (101).
const int kBusSlotStylophone = 101;

/// AAudio bus slot ID for the Vocoder.  Matches OBOE_BUS_SLOT_VOCODER (102).
const int kBusSlotVocoder = 102;

/// AAudio bus slot ID for the Live Input source.  Unique integer above the
/// other instrument slots so it never collides with a FluidSynth sfId.
const int kBusSlotLiveInput = 103;

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

/// Native signature for gfpa_dsp_set_bypass.
typedef _GfpaDspSetBypassNative = Void Function(
    Pointer<Void> handle, Bool bypassed);

/// Dart binding for gfpa_dsp_set_bypass.
typedef _GfpaDspSetBypass = void Function(
    Pointer<Void> handle, bool bypassed);

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

// ── oboe_stream_android bindings ──────────────────────────────────────────────

/// AudioSourceRenderFn native type: void (*)(float*, float*, int32, void*).
///
/// This is the render callback signature for all bus sources (keyboards,
/// Theremin, Stylophone, Vocoder).  The function pointer value comes from
/// audio_input.so via [thereminBusRenderFnAddr()].
typedef _AudioSourceRenderFnNative =
    Void Function(Pointer<Float>, Pointer<Float>, Int32, Pointer<Void>);

/// Native signature for oboe_stream_add_source.
typedef _OboeStreamAddSourceNative = Void Function(
    Pointer<NativeFunction<_AudioSourceRenderFnNative>>, // renderFn
    Pointer<Void>,                                       // userdata
    Int32);                                              // busSlotId

/// Dart binding for oboe_stream_add_source.
typedef _OboeStreamAddSource = void Function(
    Pointer<NativeFunction<_AudioSourceRenderFnNative>>,
    Pointer<Void>,
    int);

/// Native signature for oboe_stream_remove_source.
typedef _OboeStreamRemoveSourceNative = Void Function(Int32 busSlotId);

/// Dart binding for oboe_stream_remove_source.
typedef _OboeStreamRemoveSource = void Function(int busSlotId);

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

  /// Set the bypass state of a native GFPA DSP instance.
  ///
  /// Thread-safe: uses `std::atomic<bool>` internally. When bypassed, the
  /// insert callback copies input to output unchanged (zero CPU cost on
  /// the audio thread — single relaxed atomic bool load).
  late final _GfpaDspSetBypass _gfpaDspSetBypass =
      _lib.lookupFunction<_GfpaDspSetBypassNative, _GfpaDspSetBypass>(
          'gfpa_dsp_set_bypass');

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

  /// Register a generic audio source on the shared AAudio bus.
  ///
  /// [renderFnAddr] — raw address of an AudioSourceRenderFn-compatible C
  ///   function (e.g. from [thereminBusRenderFnAddr()]).
  /// [busSlotId]    — unique slot identifier (see OBOE_BUS_SLOT_* constants).
  ///   The same ID is used to look up the GFPA insert chain for this source.
  late final _OboeStreamAddSource _oboeStreamAddSource =
      _lib.lookupFunction<_OboeStreamAddSourceNative, _OboeStreamAddSource>(
          'oboe_stream_add_source');

  /// Unregister an audio source from the AAudio bus.
  ///
  /// Blocks until any in-flight audio callback snapshot that captured this
  /// source has fully completed before returning.
  late final _OboeStreamRemoveSource _oboeStreamRemoveSource =
      _lib.lookupFunction<_OboeStreamRemoveSourceNative, _OboeStreamRemoveSource>(
          'oboe_stream_remove_source');

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

  /// Set the bypass state of a native DSP instance.
  ///
  /// Zero CPU cost on the audio thread when bypassed — single relaxed
  /// atomic bool load, then memcpy of input to output.
  void gfpaDspSetBypass(Pointer<Void> handle, bool bypassed) =>
      _gfpaDspSetBypass(handle, bypassed);

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

  /// Register an audio source on the shared AAudio bus.
  ///
  /// [renderFnAddr] — address of the C render callback (AudioSourceRenderFn).
  ///   Typically obtained via `theremin_bus_render_fn_addr()` from
  ///   libaudio_input.so.
  /// [busSlotId]    — unique integer slot identifier; also the GFPA chain key.
  ///   Use [kBusSlotTheremin], [kBusSlotStylophone], or [kBusSlotVocoder]
  ///   for non-keyboard sources.  These are placed at 100+ to avoid collisions
  ///   with FluidSynth sfIds, which are assigned sequentially from 1.
  void oboeStreamAddSource(int renderFnAddr, int busSlotId) {
    final fnPtr =
        Pointer<NativeFunction<_AudioSourceRenderFnNative>>.fromAddress(
            renderFnAddr);
    _oboeStreamAddSource(fnPtr, nullptr, busSlotId);
  }

  /// Unregister an audio source from the AAudio bus by its [busSlotId].
  ///
  /// Blocks until any in-flight audio callback snapshot has finished, so the
  /// caller may safely free any resources associated with this source.
  void oboeStreamRemoveSource(int busSlotId) =>
      _oboeStreamRemoveSource(busSlotId);
}
