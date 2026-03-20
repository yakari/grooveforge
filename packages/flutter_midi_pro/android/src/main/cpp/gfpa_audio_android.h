// gfpa_audio_android.h — Android audio callback for GFPA DSP insert chain.
//
// Declares the FluidSynth audio callback used with new_fluid_audio_driver2.
// The callback intercepts Oboe's audio thread, renders FluidSynth audio, then
// applies the GFPA insert chain (reverb, delay, wah, EQ, compressor, chorus)
// before handing samples to the Oboe output buffer.
//
// All processing is done on the Oboe real-time thread — no allocation, no
// logging, no locks on the hot path.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// FluidSynth audio callback matching the fluid_audio_func_t signature.
///
/// Called by FluidSynth's Oboe driver each block.  Renders [len] frames from
/// [data] (a fluid_synth_t*), applies the active GFPA insert chain in-place,
/// and writes the result into [out].
///
/// [data]  — opaque pointer; cast to fluid_synth_t* inside the implementation.
/// [len]   — number of sample frames to render.
/// [nfx]   — number of effect (reverb/chorus) output pairs in [fx].
/// [fx]    — array of FluidSynth effect buffers (may be NULL when nfx == 0).
/// [nout]  — number of dry output pairs in [out].
/// [out]   — array of output buffers; [0] = left, [1] = right channel.
///
/// Returns 0 (FLUID_OK) on success.
int gfpa_audio_callback(void* data, int len,
                        int nfx, float* fx[],
                        int nout, float* out[]);

#ifdef __cplusplus
}
#endif
