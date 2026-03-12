/**
 * vocoder_dsp.h — Context-based vocoder DSP for the GrooveForge Vocoder VST3.
 *
 * Pure C, no miniaudio dependency. Accepts a voice audio buffer as sidechain
 * input (from the DAW) and produces stereo output. This is the same algorithm
 * used inside audio_input.c but refactored into a reusable context struct so
 * that the VST3 plugin can own an instance without relying on global state.
 */

#pragma once

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VD_MAX_POLYPHONY 16
#define VD_NUM_BANDS     32

/** Carrier oscillator waveform. Matches audio_input.c g_vocoderWaveform values. */
typedef enum {
    VD_WAVE_SAW     = 0,
    VD_WAVE_SQUARE  = 1,
    VD_WAVE_CHORAL  = 2,
    VD_WAVE_NATURAL = 3,
} VocoderWaveform;

/** Opaque context — allocate with vocoder_dsp_create(). */
typedef struct VocoderContext VocoderContext;

/** Allocate and initialise a new vocoder context at the given sample rate. */
VocoderContext* vocoder_dsp_create(float sample_rate);

/** Release all resources owned by ctx. */
void vocoder_dsp_destroy(VocoderContext* ctx);

/** Trigger a note-on event (key = MIDI pitch 0-127, velocity 0-127). */
void vocoder_dsp_note_on(VocoderContext* ctx, int key, int velocity);

/** Trigger a note-off event. */
void vocoder_dsp_note_off(VocoderContext* ctx, int key);

/** Immediately silence all active voices. */
void vocoder_dsp_all_notes_off(VocoderContext* ctx);

/** Set the carrier oscillator waveform (VocoderWaveform). */
void vocoder_dsp_set_waveform(VocoderContext* ctx, int waveform);

/** Noise mix for consonant intelligibility (0..1). */
void vocoder_dsp_set_noise_mix(VocoderContext* ctx, float v);

/** Envelope follower release time — lower = faster (0..1). */
void vocoder_dsp_set_env_release(VocoderContext* ctx, float v);

/**
 * Filter-bank Q factor (0..1 maps to 0.3..4.0).
 * Higher = narrower bands = more "robotic" sound.
 */
void vocoder_dsp_set_bandwidth(VocoderContext* ctx, float v);

/** Input noise gate threshold (0..0.1). */
void vocoder_dsp_set_gate_threshold(VocoderContext* ctx, float v);

/** Pre-amplification on the incoming voice signal (0..2). */
void vocoder_dsp_set_input_gain(VocoderContext* ctx, float v);

/**
 * Process one block of audio.
 *
 * @param ctx       Vocoder context.
 * @param voice_in  Mono voice input from the DAW sidechain bus (nframes floats).
 * @param out_l     Left output channel (nframes floats, caller-allocated).
 * @param out_r     Right output channel (nframes floats, caller-allocated).
 * @param nframes   Number of samples to process.
 */
void vocoder_dsp_process(VocoderContext* ctx,
                         const float*    voice_in,
                         float*          out_l,
                         float*          out_r,
                         int             nframes);

#ifdef __cplusplus
}
#endif
