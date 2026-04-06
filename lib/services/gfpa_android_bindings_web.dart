// Web-only stub for GfpaAndroidBindings — selected when dart.library.js_interop
// is available (i.e., Flutter web and Wasm targets).
//
// The Android AAudio/Oboe DSP pipeline is unavailable in the browser sandbox,
// so every method is a silent no-op.  Handles are represented as plain [int]
// (memory addresses) instead of dart:ffi Pointer<Void>, since dart:ffi is not
// available on web.

// ── AAudio bus slot ID constants ──────────────────────────────────────────────
//
// Mirrored here so code that imports this stub (e.g. gfpa_theremin_slot_ui)
// can reference the constants without a platform guard.

/// AAudio bus slot ID for the Theremin.  Matches OBOE_BUS_SLOT_THEREMIN (100).
const int kBusSlotTheremin = 100;

/// AAudio bus slot ID for the Stylophone.  Matches OBOE_BUS_SLOT_STYLOPHONE (101).
const int kBusSlotStylophone = 101;

/// AAudio bus slot ID for the Vocoder.  Matches OBOE_BUS_SLOT_VOCODER (102).
const int kBusSlotVocoder = 102;

/// Web stub that mirrors the [GfpaAndroidBindings] public API.
///
/// All methods are no-ops — the Android AAudio bus and GFPA DSP chain are not
/// available in the browser.  Handles are plain [int] (0 = null handle).
class GfpaAndroidBindings {
  /// Singleton accessor.
  static final GfpaAndroidBindings instance = GfpaAndroidBindings._();

  GfpaAndroidBindings._();

  /// Not supported on web — returns 0 (null handle).
  int createDsp(String pluginId, {int sampleRate = 48000, int blockSize = 512}) => 0;

  /// Not supported on web — no-op.
  void gfpaDspSetParam(int handle, String paramId, double physicalValue) {}

  /// Not supported on web — no-op.
  void gfpaDspSetBypass(int handle, bool bypassed) {}

  /// Not supported on web — no-op.
  void gfpaDspDestroy(int handle) {}

  /// Not supported on web — no-op.
  void gfpaAndroidAddInsertForSf(int sfId, int handle) {}

  /// Not supported on web — no-op.
  void gfpaAndroidRemoveInsert(int handle) {}

  /// Not supported on web — no-op.
  void gfpaAndroidClearAllInserts() {}

  /// Not supported on web — no-op.
  void gfpaAndroidSetBpm(double bpm) {}

  /// Not supported on web — no-op.
  void oboeStreamAddSource(int renderFnAddr, int busSlotId) {}

  /// Not supported on web — no-op.
  void oboeStreamRemoveSource(int busSlotId) {}
}
