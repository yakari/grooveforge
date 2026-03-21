// oboe_stream_android.h — Shared AAudio output stream (universal audio bus).
//
// All GrooveForge sound sources (GF Keyboard, Theremin, Stylophone, Vocoder)
// register themselves as AudioSource entries in this bus.  Each source has its
// own render callback and a unique bus slot ID that maps to its GFPA insert chain.
//
// Bus slot ID assignment:
//   1–4  : GF Keyboard slots (sfId returned by flutter_midi_pro loadSoundfont)
//   5    : Theremin
//   6    : Stylophone
//   7    : Vocoder
//
// Lifetime:
//   oboe_stream_start() is called once (on first sound source registration).
//   oboe_stream_stop()  is called on dispose.
//   Sources are added/removed dynamically as instruments are loaded/unloaded.
#pragma once

#include <fluidsynth.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// ── Bus slot ID constants ─────────────────────────────────────────────────────

/// Fixed bus slot ID for the Theremin instrument.
/// Must not collide with any FluidSynth sfId (which are 1-based integers
/// assigned sequentially from native-lib.cpp; max 4 keyboard slots).
#define OBOE_BUS_SLOT_THEREMIN  5

/// Fixed bus slot ID for the Stylophone instrument.
#define OBOE_BUS_SLOT_STYLOPHONE 6

/// Fixed bus slot ID for the Vocoder instrument.
#define OBOE_BUS_SLOT_VOCODER   7

// ── Generic audio source render callback ─────────────────────────────────────

/// Render callback type for a generic audio source.
///
/// Called from the AAudio real-time thread every audio block.
/// Must be allocation-free and complete well within the buffer deadline.
///
/// [outL]     — pre-zeroed non-interleaved left-channel output buffer.
/// [outR]     — pre-zeroed non-interleaved right-channel output buffer.
/// [frames]   — number of sample frames to produce.
/// [userdata] — opaque pointer registered alongside the callback.
typedef void (*AudioSourceRenderFn)(float* outL, float* outR,
                                    int frames, void* userdata);

// ── Stream lifecycle ─────────────────────────────────────────────────────────

/// Open and start the shared AAudio output stream at [sampleRate] Hz.
///
/// No-op if the stream is already running.  Should be called before registering
/// any source.  [sampleRate] should match all source render rates (48000 Hz).
void oboe_stream_start(int sampleRate);

/// Stop and destroy the shared AAudio output stream.
///
/// Should be called after all sources have been removed.
/// Safe to call when the stream is not running.
void oboe_stream_stop(void);

// ── Generic source registration ──────────────────────────────────────────────

/// Register an audio source on the bus.
///
/// [renderFn]  — callback invoked each block to fill outL/outR with audio.
/// [userdata]  — forwarded to renderFn unchanged (e.g. instrument context pointer).
/// [busSlotId] — unique slot identifier; also used as the GFPA insert chain key.
///               Use the OBOE_BUS_SLOT_* constants for non-keyboard sources.
///
/// Idempotent: registering the same busSlotId twice logs a warning and no-ops.
void oboe_stream_add_source(AudioSourceRenderFn renderFn,
                             void* userdata,
                             int busSlotId);

/// Unregister the source identified by [busSlotId] from the bus.
///
/// Blocks the calling thread until any in-progress callback that captured a
/// snapshot containing this source has fully completed (~one audio burst,
/// typically < 10 ms).  After this call returns it is safe to free any
/// resources associated with the source.
void oboe_stream_remove_source(int busSlotId);

// ── FluidSynth convenience wrappers ─────────────────────────────────────────
//
// Thin wrappers used by native-lib.cpp.  Internally they call
// oboe_stream_add_source / oboe_stream_remove_source with the FluidSynth
// render trampoline and the sfId as the busSlotId.

/// Register a FluidSynth instance as a GF Keyboard source on the bus.
///
/// [synth] — FluidSynth instance; must remain valid until remove_synth returns.
/// [sfId]  — 1-based soundfont ID returned by loadSoundfont (bus slot key).
void oboe_stream_add_synth(fluid_synth_t* synth, int sfId);

/// Unregister a FluidSynth instance from the bus.
///
/// Blocks until any in-flight callback using this synth has finished.
/// After this returns it is safe to call delete_fluid_synth(synth).
void oboe_stream_remove_synth(fluid_synth_t* synth);

#ifdef __cplusplus
}
#endif
