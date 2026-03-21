// gfpa_audio_android.h — Android GFPA DSP per-source insert chains.
//
// Each sound source on the audio bus has its own insert chain keyed by its
// bus slot ID.  Effects are applied per-source BEFORE audio is summed into
// the master mix, so WAH on the Theremin cannot bleed into Keyboard or
// Vocoder audio, and vice versa.
//
// Bus slot ID assignment (must match oboe_stream_android.h):
//   1–4  : GF Keyboard slots (sfId from flutter_midi_pro loadSoundfont)
//   5    : Theremin
//   6    : Stylophone
//   7    : Vocoder
//
// The Dart layer (gfpa_android_bindings.dart / vst_host_service_desktop.dart)
// calls gfpa_android_add_insert_for_sf() once per routing sync, passing the
// correct bus slot ID for each source → GFPA cable.
#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/// Register [dspHandle] as the next insert in the chain for [sfId].
///
/// [sfId] is the integer returned by flutter_midi_pro's loadSoundfont (1-based,
/// max kMaxSfId).  Idempotent: registering the same handle twice is a no-op.
void gfpa_android_add_insert_for_sf(int sfId, void* dspHandle);

/// Remove [dspHandle] from whichever per-keyboard chain it belongs to.
///
/// Searches all chains.  No-op if the handle is not registered anywhere.
void gfpa_android_remove_insert(void* dspHandle);

/// Clear every insert from every per-keyboard chain.
///
/// Called at the start of each syncAudioRouting rebuild so that stale
/// connections from the previous graph configuration are removed.
void gfpa_android_clear_all_inserts(void);

/// Apply the insert chain for [sfId] to the stereo signal in [outL]/[outR].
///
/// Called by oboe_stream_android.cpp once per synth block, before the
/// synth's contribution is accumulated into the master mix.
/// No-op when the chain for [sfId] is empty.
///
/// [outL], [outR] — non-interleaved in/out stereo buffers.
/// [frames]       — number of sample frames to process.
void gfpa_android_apply_chain_for_sf(int sfId,
                                      float* outL, float* outR,
                                      int frames);

/// Forward the transport BPM to all BPM-synced GFPA effects (delay, wah, chorus).
void gfpa_android_set_bpm(double bpm);

#ifdef __cplusplus
}
#endif
