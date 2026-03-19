// gfpa_dsp.h — Native GFPA DSP effect nodes for the dart_vst_host ALSA chain.
//
// Each GfpaDspHandle encapsulates the full signal graph of one .gfpd
// descriptor plugin (reverb, delay, wah, EQ, compressor, chorus).
// Instances run entirely on the ALSA audio thread — all internal buffers
// are pre-allocated at construction; no heap allocation occurs in process().
//
// Thread safety: gfpa_dsp_set_param() uses std::atomic<float> internally and
// is safe to call from the Dart isolate while the ALSA thread runs.
#pragma once
#include "dart_vst_host.h"

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a native GFPA DSP effect instance.
typedef void* GfpaDspHandle;

/// Insert-effect callback — called on the ALSA audio thread (allocation-free).
///
/// Reads [frames] samples from inL/inR (the source's dry signal), writes the
/// processed stereo result to outL/outR.  All pointers are guaranteed non-null
/// and point to pre-allocated buffers of at least [frames] floats.
typedef void (*GfpaInsertFn)(const float* inL, const float* inR,
                              float* outL, float* outR,
                              int32_t frames, void* userdata);

/// Create a native GFPA DSP instance for the given pluginId.
///
/// [pluginId] must be one of:
///   "com.grooveforge.reverb", "com.grooveforge.delay", "com.grooveforge.wah",
///   "com.grooveforge.eq", "com.grooveforge.compressor", "com.grooveforge.chorus"
///
/// Returns NULL for unrecognised IDs.
/// [sampleRate] and [blockSize] are used to pre-size internal delay buffers.
DVH_API GfpaDspHandle gfpa_dsp_create(const char* pluginId,
                                       int32_t sampleRate,
                                       int32_t blockSize);

/// Set a parameter using its string id and PHYSICAL (denormalized) value.
///
/// Thread-safe: may be called from the Dart isolate while the ALSA thread runs.
/// The Dart side must convert normalised [0,1] → physical using
///   physical = min + norm * (max - min)
/// before calling this function.
DVH_API void gfpa_dsp_set_param(GfpaDspHandle handle,
                                 const char* paramId,
                                 double physicalValue);

/// Return the insert callback for this DSP instance.
///
/// The returned function pointer is static and valid for the entire lifetime
/// of the process — it does not change between calls.
DVH_API GfpaInsertFn gfpa_dsp_insert_fn(GfpaDspHandle handle);

/// Return the userdata pointer to pass alongside [gfpa_dsp_insert_fn].
///
/// The handle itself is used as userdata; this function simply casts and
/// returns it for clarity at the call site.
DVH_API void* gfpa_dsp_userdata(GfpaDspHandle handle);

/// Destroy the DSP instance and free all associated resources.
///
/// The caller must unregister the insert from the chain via
/// dvh_remove_master_insert() before calling this function to ensure the
/// audio thread no longer holds a dangling function pointer.
DVH_API void gfpa_dsp_destroy(GfpaDspHandle handle);

/// Set the current BPM for BPM-synced effects (delay, wah, chorus).
///
/// Called from Dart whenever the transport tempo changes.  The value is stored
/// in a global atomic float shared across all instances.
DVH_API void gfpa_set_bpm(double bpm);

// ── Insert chain API ─────────────────────────────────────────────────────────

/// Register a GFPA insert on a master-mix source render function.
///
/// Instead of [source] audio going directly to the master mix, it passes
/// through [insertFn(inL,inR,outL,outR,frames,userdata)] first.
/// Only one insert per source is supported; calling again replaces the
/// existing registration.
DVH_API void dvh_add_master_insert(DVH_Host host, DvhRenderFn source,
                                    GfpaInsertFn insertFn, void* userdata);

/// Remove the GFPA insert for [source].
///
/// After this call, audio from [source] flows directly to the master mix.
DVH_API void dvh_remove_master_insert(DVH_Host host, DvhRenderFn source);

/// Remove all master inserts.
///
/// Called from syncAudioRouting() at the start of a full routing rebuild so
/// that stale insert registrations from previous configurations are cleared.
DVH_API void dvh_clear_master_inserts(DVH_Host host);

#ifdef __cplusplus
}
#endif
