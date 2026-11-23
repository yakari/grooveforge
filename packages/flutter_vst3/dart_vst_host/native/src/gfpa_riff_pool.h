// gfpa_riff_pool.h — Internal: the pool of Riff guitars behind the GFPA C API.
//
// Riff (native_audio/gf_riff.h) is an instrument, not an effect: it produces
// sound from MIDI rather than processing an input. It still goes through the
// GFPA DSP handle (gfpa_dsp_create("com.grooveforge.riff")) so its knobs,
// saved state and CC mappings use the same path as every descriptor effect.
//
// Why a pool. The audio backends pull an instrument through a bare function
// pointer — on the desktop DvhRenderFn has no user-data argument at all — and
// nothing guarantees a render already under way has finished when a source
// is removed. So the guitars live in a fixed array of slots that are never
// freed: each slot has its own render trampoline, a removed rack slot only
// marks its pool slot free, and a render that races the removal finds it free
// and writes silence instead of touching freed memory.
//
// Threads. acquire/release/set_param/the event pushes run on the Dart isolate;
// the render functions run on the audio thread. MIDI events cross through a
// single-producer, single-consumer ring per slot; parameters through atomics.

#ifndef GFPA_RIFF_POOL_H
#define GFPA_RIFF_POOL_H

#include <cstdint>

/// Number of Riff guitars that can play at once.
constexpr int kRiffSlots = 4;

/// Takes a free pool slot and readies its guitar at [sampleRate] (used only
/// when no stream is open yet). Returns the slot, or -1 when all are taken or
/// memory ran out. Dart isolate only.
int gfpa_riff_acquire(float sampleRate);

/// Gives pool slot [slot] back. Its render goes silent at once. Dart isolate.
void gfpa_riff_release(int slot);

/// Sets a knob by its descriptor id (physical value, as the host sends it).
void gfpa_riff_slot_set_param(int slot, const char* id, float value);

/// Silences slot [slot]'s output while [muted] (the slot's bypass switch).
void gfpa_riff_slot_set_muted(int slot, bool muted);

// MIDI, queued for the audio thread. Dart isolate only.
void gfpa_riff_slot_note_on(int slot, int note, int velocity);
void gfpa_riff_slot_note_off(int slot, int note);
void gfpa_riff_slot_pitch_bend(int slot, float bend);   // -1..1
void gfpa_riff_slot_control_change(int slot, int cc, int value);

/// Render function for the desktop hosts: void (float* L, float* R, int32_t n).
void* gfpa_riff_slot_render_fn(int slot);

/// Render function for the Android bus: void (float* L, float* R, int n, void*).
void* gfpa_riff_slot_bus_render_fn(int slot);

/// The stream's live sample rate, 0 before one opens (gfpa_dsp.cpp).
float gfpa_stream_sample_rate();

#endif // GFPA_RIFF_POOL_H
