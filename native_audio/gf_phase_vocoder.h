// gf_phase_vocoder.h — Shared phase vocoder DSP library for GrooveForge.
//
// A phase vocoder analyses audio into short-time Fourier frames, modifies
// their magnitudes and phases, then resynthesises via inverse FFT and
// overlap-add. This file exposes the public C API; the implementation lives
// in gf_phase_vocoder.c.
//
// Two independent operations are supported:
//
//   1. Time stretching  — change the playback duration of audio without
//      altering its pitch. Needed by the audio looper for tempo-synced
//      playback (e.g. a 120 BPM loop played back at 140 BPM).
//
//   2. Pitch shifting   — change the pitch of audio without altering its
//      duration. Needed by the harmonizer effect (N pitch-shifted voices)
//      and by the vocoder's NATURAL mode (replacing the choppy PSOLA grain
//      engine). Implemented as resample + time-stretch.
//
// Real-time safety
// ----------------
// The context owns all working buffers. Once gf_pv_create has returned,
// gf_pv_process_block must be allocation-free and lock-free, suitable for
// calling from an audio callback thread.
//
// Algorithm
// ---------
// Phase-locked vocoder (Laroche & Dolson, 1999): spectral peaks are detected
// in each analysis frame, their phase advance is computed from the measured
// instantaneous frequency, and the phases of bins around each peak are
// locked rigidly to the peak's phase. This preserves vertical phase
// coherence across partials and yields markedly better transient handling
// than the classic phase vocoder — important for drum loops.

#ifndef GF_PHASE_VOCODER_H
#define GF_PHASE_VOCODER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle. All state is owned by this struct; callers never
/// dereference it. Allocated by gf_pv_create, released by gf_pv_destroy.
typedef struct gf_pv_context gf_pv_context;

/// Creates a new phase vocoder context.
///
/// - [fft_size]      FFT length in samples. Must be a power of two in
///                   [256, 8192]. Typical values: 2048 for music, 1024 for
///                   percussive material, 4096 for sustained tones.
/// - [hop_size]      Analysis hop in samples. Must divide fft_size evenly
///                   and give an overlap factor of at least 4
///                   (i.e. hop_size <= fft_size / 4). Typical: fft_size/4.
/// - [channels]      Number of audio channels (1 = mono, 2 = stereo). Each
///                   channel runs an independent analysis/synthesis pass
///                   but shares the same stretch ratio so they stay phase
///                   aligned.
///
/// Returns NULL on invalid parameters or out-of-memory.
gf_pv_context* gf_pv_create(int fft_size, int hop_size, int channels);

/// Destroys a context and frees all its buffers. Safe to pass NULL.
void gf_pv_destroy(gf_pv_context* ctx);

/// Resets all internal state (ring buffers, phase accumulators, overlap-add
/// tail). Call after a seek or when starting a new audio stream. Does not
/// allocate. Safe to call from the audio thread.
void gf_pv_reset(gf_pv_context* ctx);

/// Sets the time-stretch ratio. 1.0 = no change; 2.0 = twice as long
/// (slower); 0.5 = half as long (faster). Clamped to [0.25, 4.0]. Safe to
/// call between process blocks; changes take effect on the next analysis
/// frame boundary so there are no clicks.
void gf_pv_set_stretch(gf_pv_context* ctx, float ratio);

/// Sets the pitch shift in semitones. 0 = no change; +12 = one octave up;
/// -12 = one octave down. Clamped to [-24, +24]. Implemented as
/// time-stretch by 2^(-semitones/12) followed by resampling by the inverse
/// factor, so duration is preserved.
void gf_pv_set_pitch_semitones(gf_pv_context* ctx, float semitones);

/// Pushes [num_samples] input samples (interleaved, [channels] channels) into
/// the vocoder. Any output the vocoder can produce given the current input
/// backlog is written into [out] as interleaved samples. Returns the number
/// of output sample *frames* written (not samples).
///
/// Because time-stretching changes the rate at which output frames are
/// produced relative to input frames, callers cannot assume output size
/// equals input size. The caller must provide an output buffer large
/// enough for the worst case: ceil(num_samples * max_stretch) + fft_size.
///
/// Must be called from a single thread. Allocation-free and lock-free.
int gf_pv_process_block(gf_pv_context* ctx,
                        const float* input_interleaved,
                        int num_frames,
                        float* output_interleaved,
                        int output_capacity_frames);

/// Convenience: processes an entire mono buffer offline. Writes
/// time-stretched output to [out] (caller-sized). Returns frames written.
/// Intended for smoke tests and offline rendering, not the audio thread.
int gf_pv_time_stretch_offline(const float* input,
                               int num_frames,
                               int channels,
                               int sample_rate,
                               float stretch_ratio,
                               int fft_size,
                               float* output,
                               int output_capacity);

/// Convenience: offline pitch shift by [semitones]. Same duration as the
/// input (no stretching). Shift is clamped to ±24 semitones. Intended for
/// smoke tests and offline rendering.
int gf_pv_pitch_shift_offline(const float* input,
                              int num_frames,
                              int channels,
                              int sample_rate,
                              float semitones,
                              int fft_size,
                              float* output,
                              int output_capacity);

#ifdef __cplusplus
}
#endif

#endif // GF_PHASE_VOCODER_H
