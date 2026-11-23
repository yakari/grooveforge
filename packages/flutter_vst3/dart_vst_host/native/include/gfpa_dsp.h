// gfpa_dsp.h — Native GFPA DSP effect nodes for the dart_vst_host audio chain.
//
// Each GfpaDspHandle encapsulates the full signal graph of one .gfpd
// descriptor plugin (reverb, delay, wah, EQ, compressor, chorus).
// Instances run entirely on the JACK audio thread — all internal buffers
// are pre-allocated at construction; no heap allocation occurs in process().
//
// Thread safety: gfpa_dsp_set_param() uses std::atomic<float> internally and
// is safe to call from the Dart isolate while the JACK audio thread runs.
#pragma once
#include "dart_vst_host.h"

// `bool` in the declarations below is a keyword in C++ but a library type in
// C. Without this, any C translation unit including this header fails to
// compile — which the C smoke test found.
#ifndef __cplusplus
#include <stdbool.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to a native GFPA DSP effect instance.
typedef void* GfpaDspHandle;

/// Insert-effect callback — called on the JACK audio thread (allocation-free).
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
///   "com.grooveforge.eq", "com.grooveforge.compressor", "com.grooveforge.chorus",
///   "com.grooveforge.audio_harmonizer", "com.grooveforge.autotune",
///   "com.grooveforge.amp"
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

/// Read a value the effect publishes for its panel.
///
/// Currently only the Autotune publishes anything: `input_note` (the pitch
/// heard, fractional MIDI, negative when unpitched), `target_note` (the note
/// it corrects towards, -1 for none) and `correction` (semitones). Returns NaN
/// for any other effect or id. Lock-free; safe from the Dart isolate.
DVH_API double gfpa_dsp_get_readout(GfpaDspHandle handle,
                                     const char* readoutId);

/// Load a speaker-cabinet impulse response into an Amp instance.
///
/// [samples] holds [n] mono samples recorded at [sampleRate] Hz; they are
/// copied, so the caller may free them as soon as this returns. The IR is
/// trimmed, resampled and levelled on the calling thread (a few tens of ms
/// for a long file), then picked up by the audio thread at its next block
/// and crossfaded in. It is heard when the Amp's cabinet selector is on
/// "IR". Must not be called from the audio thread.
///
/// Returns 0 on success, -1 when [handle] is not an Amp or the IR is unusable
/// (empty, silent, unsupported rate) or memory ran out.
DVH_API int32_t gfpa_dsp_load_ir(GfpaDspHandle handle, const float* samples,
                                  int32_t n, double sampleRate);

/// Remove the cabinet impulse response loaded into an Amp DSP instance.
///
/// The audio thread fades the IR out over ~10 ms at its next block, then the
/// cabinet selector's "IR" option falls back to the built-in 2x12. Must not
/// be called from the audio thread.
///
/// Returns 0 on success, -1 when [handle] is not an Amp.
DVH_API int32_t gfpa_dsp_clear_ir(GfpaDspHandle handle);

// ── Riff guitar ──────────────────────────────────────────────────────────────
//
// gfpa_dsp_create("com.grooveforge.riff") returns a handle to a Riff guitar
// (native_audio/gf_riff.h) — an instrument, not an effect. Its knobs go
// through gfpa_dsp_set_param like any effect's, and gfpa_dsp_set_bypass
// mutes it; its sound comes from the render functions below, which the host
// registers as a source. At most four guitars exist at once: a fifth create
// returns NULL. The MIDI calls queue the event for the audio thread's next
// block and return at once; call them from the Dart isolate, never the
// audio thread. All are no-ops on a handle that is not a Riff.

/// Pick [note] (MIDI 0-127) at [velocity] (1-127; 0 is a note-off).
DVH_API void gfpa_riff_note_on(GfpaDspHandle handle, int32_t note, int32_t velocity);

/// Let go of [note].
DVH_API void gfpa_riff_note_off(GfpaDspHandle handle, int32_t note);

/// Pitch bend in [-1, 1], scaled by the guitar's bend range.
DVH_API void gfpa_riff_pitch_bend(GfpaDspHandle handle, double bend);

/// Controller: 1 = vibrato depth, 64 = sustain pedal, 120/123 = all notes off.
DVH_API void gfpa_riff_control_change(GfpaDspHandle handle, int32_t cc, int32_t value);

/// The guitar's render function for the desktop hosts, as a DvhRenderFn
/// address (dvh_add_master_render / dvh_set_master_insert_chain); 0 when
/// [handle] is not a Riff. Stays valid for the life of the process.
DVH_API intptr_t gfpa_riff_render_fn(GfpaDspHandle handle);

/// The same for the Android AAudio bus, as an AudioSourceRenderFn address
/// (oboe_stream_add_source); 0 when [handle] is not a Riff.
DVH_API intptr_t gfpa_riff_bus_render_fn(GfpaDspHandle handle);

/// Set the bypass state of a DSP instance.
///
/// When bypassed, the insert callback copies input to output unchanged
/// (zero CPU cost, zero latency).  Thread-safe: uses std::atomic<bool>
/// internally; safe to call from the Dart isolate while the audio thread runs.
DVH_API void gfpa_dsp_set_bypass(GfpaDspHandle handle, bool bypassed);

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

/// Publish the rate the audio stream is actually running at.
///
/// Called by each audio backend when its stream opens (JACK, miniaudio,
/// AAudio). New effects are built at this rate whatever their creator asked
/// for, and existing ones re-derive their rate-dependent maths before their
/// next block — allocation-free, on the audio thread. 0 or never called means
/// effects keep the rate they were created with.
DVH_API void gfpa_set_sample_rate(double sampleRate);

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
