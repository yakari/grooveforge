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
//
// FluidSynth assigns sfIds sequentially from 1 for every loadSoundfont() call.
// With per-keyboard dedicated synths (createKeyboardSlotSynth), each of the
// 4 keyboard slots can generate 2 sfId allocations (initial load + dedicated
// load), meaning sfIds can reach 8 or higher in practice.
//
// Instrument bus slots are therefore placed at 100+ to guarantee they never
// collide with any FluidSynth sfId, regardless of how many soundfonts are
// loaded.  The gfpa_audio_android chains array (kMaxBusSlot) must be at
// least as large as the highest slot ID used here.

/// Fixed bus slot ID for the Theremin instrument.
/// Placed at 100 to avoid collisions with FluidSynth sfIds (1-based,
/// sequentially assigned — may reach double digits with multiple keyboard slots).
#define OBOE_BUS_SLOT_THEREMIN   100

/// Fixed bus slot ID for the Stylophone instrument.
#define OBOE_BUS_SLOT_STYLOPHONE 101

/// Fixed bus slot ID for the Vocoder instrument.
#define OBOE_BUS_SLOT_VOCODER    102

/// Fixed bus slot ID for the Live Input source (mic / line-in passthrough).
/// Not an "instrument" — it is a hardware capture passthrough that the
/// rack can cable into any GFPA effect or the audio looper.
#define OBOE_BUS_SLOT_LIVE_INPUT 103

// Slots 104 and 105 once belonged to the latency probe and the rehearsal
// engine. Neither is a rack source: they are heard, never cabled, and must
// never be recorded. Both moved to the monitor source below.

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

// ── Rack output tap ──────────────────────────────────────────────────────────

/// Receives the rack's mixed output, one block at a time.
///
/// Called from the AAudio real-time thread. Must be allocation-free and
/// non-blocking, exactly like a render callback.
///
/// [mono]   — the rack's output summed to mono, [frames] samples long.
/// [frames] — number of sample frames in the block.
typedef void (*AudioTapFn)(const float* mono, int frames);

/// Sends the rack's output to [fn] every block, or stops sending when NULL.
///
/// "The rack's output" is everything the rack itself produces — keyboards, the
/// Theremin, live input, the audio looper — because that is what the player
/// hears and what they mean by "the rack". It is read before the monitor
/// source is added, so a rehearsal take fed from here cannot swallow the
/// metronome, the imported recording and the rest of the band along with the
/// part being played.
///
/// The tap is what makes a rehearsal take recordable straight from the rack
/// rather than through the room. It costs nothing while no tap is set.
void oboe_stream_set_rack_tap(AudioTapFn fn);

/// Render [fn] on the monitor source: heard on the bus, but never part of
/// what the tap reports or the audio looper records. Pass NULL to clear.
///
/// One slot, not a list. The rehearsal engine and the latency probe are the
/// only things that belong here and they share a single render, so a probe
/// started from Preferences cannot switch the engine off on its way out.
void oboe_stream_set_monitor_source(AudioSourceRenderFn fn);

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

// ── Output device routing ────────────────────────────────────────────────────

/// Sets the Android output device ID for the AAudio stream.
///
/// [deviceId] — Android AudioDeviceInfo.id from AudioManager.getDevices().
///              Pass 0 (AAUDIO_UNSPECIFIED) to revert to the system default.
///
/// If the stream is already running, it is stopped and restarted so the new
/// device takes effect (AAudio does not support hot-swapping).
void oboe_stream_set_output_device(int deviceId);

/// Returns the currently configured output device ID (0 = system default).
int oboe_stream_get_output_device(void);

// ── Stream diagnostics ───────────────────────────────────────────────────────

/// Returns the sample rate the AAudio stream is actually running at.
///
/// Sound sources must be created at this rate — any mismatch means
/// AudioFlinger resamples every block, which costs latency and disqualifies
/// the low-latency fast path.  Returns the 48000 default before the stream
/// has ever been opened.
int32_t oboe_stream_get_sample_rate(void);

/// Returns the stream's accumulated underrun (xrun) count, or -1 if not open.
///
/// Climbing = the render callback misses its deadline (too much DSP for the
/// buffer size).  Flat but laggy = the buffer is simply too large.
int32_t oboe_stream_get_xrun_count(void);

// ── Drain synchronisation (shared with other translation units) ──────────────

/// Returns the current value of the per-callback sequence counter.
///
/// Incremented once at the end of every AAudio callback invocation.
/// Used by gfpa_audio_android and other consumers to drain any in-flight
/// snapshot before freeing resources referenced by the audio thread.
uint64_t oboe_stream_callback_done_seq(void);

#ifdef __cplusplus
}
#endif
