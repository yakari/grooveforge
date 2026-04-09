// audio_looper.h — PCM audio looper for GrooveForge.
//
// Architecture:
//   - Each clip has a per-clip audio source: either a DvhRenderFn (for
//     non-VST3 sources like GF Keyboard, Theremin) or a VST3 plugin index
//     (copied from pluginBuf[] by the JACK callback).  No source = silence.
//   - Clip buffers are pre-allocated on the Dart thread via dvh_alooper_create.
//   - The audio callback reads/writes clip data with zero allocation.
//   - Bar-sync (optional): the callback detects downbeat crossings using a
//     running sample counter.  Free-form mode starts recording immediately.
//   - Overdub: reads old buffer to output, sums new input, writes back.

#pragma once
#include <stdint.h>
#include "dart_vst_host.h"  // for DvhRenderFn typedef

#ifdef __cplusplus
extern "C" {
#endif

/// Maximum simultaneous audio looper clips.
#define ALOOPER_MAX_CLIPS 8

/// Clip state machine (values stored in std::atomic<int32_t>).
///
/// Single-button flow:
///   idle (empty) ──press──→ armed ──(downbeat or immediate)──→ recording
///   idle (has content) ──press──→ playing
///   recording ──press──→ playing (auto-set length)
///   playing ──press──→ overdubbing
///   overdubbing ──press──→ playing
///   any ──stop──→ idle
enum ALooperState {
    ALOOPER_IDLE       = 0,
    ALOOPER_ARMED      = 1,
    ALOOPER_RECORDING  = 2,
    ALOOPER_PLAYING    = 3,
    ALOOPER_OVERDUBBING = 4,
};

/// Opaque handle (unused — looper uses a global clip pool).
typedef void* DVH_Host;

// ── Clip lifecycle ─────────────────────────────────────────────────────────

DVH_API int32_t dvh_alooper_create(DVH_Host host, float maxSeconds, int32_t sampleRate);
DVH_API void    dvh_alooper_destroy(DVH_Host host, int32_t idx);

// ── State control ──────────────────────────────────────────────────────────

DVH_API void    dvh_alooper_set_state(DVH_Host host, int32_t idx, int32_t state);
DVH_API int32_t dvh_alooper_get_state(DVH_Host host, int32_t idx);

// ── Parameters ─────────────────────────────────────────────────────────────

DVH_API void dvh_alooper_set_volume(DVH_Host host, int32_t idx, float volume);
DVH_API void dvh_alooper_set_reversed(DVH_Host host, int32_t idx, int32_t reversed);
DVH_API void dvh_alooper_set_length_beats(DVH_Host host, int32_t idx, double lengthBeats);

// ── Audio source routing (multiple sources per clip) ──────────────────────
//
// A clip can have multiple audio sources (e.g. two keyboards + a drum
// generator all cabled to the same looper).  The JACK callback mixes all
// connected sources into the clip's source buffer each block.

/// Maximum audio sources per clip (render functions + plugin indices combined).
#define ALOOPER_MAX_SOURCES 8

/// Remove all audio sources from clip [idx].
DVH_API void dvh_alooper_clear_sources(int32_t idx);

/// Add a render function as an audio source for clip [idx].
/// Multiple render sources can be added — they are mixed (summed) each block.
DVH_API void dvh_alooper_add_render_source(int32_t idx, DvhRenderFn fn);

/// Add a VST3 plugin output as an audio source for clip [idx].
/// [pluginOrdinalIdx] is the plugin's ordinal in the routing snapshot.
DVH_API void dvh_alooper_add_source_plugin(int32_t idx, int32_t pluginOrdinalIdx);

/// Enable or disable bar-sync for clip [idx].
/// When enabled (default), armed→recording waits for the next downbeat.
/// When disabled, armed→recording starts immediately.
DVH_API void dvh_alooper_set_bar_sync(int32_t idx, int32_t enabled);

// ── Buffer access ──────────────────────────────────────────────────────────

DVH_API const float* dvh_alooper_get_data_l(DVH_Host host, int32_t idx);
DVH_API const float* dvh_alooper_get_data_r(DVH_Host host, int32_t idx);
DVH_API int32_t      dvh_alooper_get_length(DVH_Host host, int32_t idx);
DVH_API int32_t      dvh_alooper_get_capacity(DVH_Host host, int32_t idx);
DVH_API int32_t      dvh_alooper_get_head(DVH_Host host, int32_t idx);
DVH_API int64_t      dvh_alooper_memory_used(DVH_Host host);
DVH_API int32_t      dvh_alooper_load_data(DVH_Host host, int32_t idx,
                                            const float* srcL, const float* srcR,
                                            int32_t lengthFrames);

// ── RT-callable source query (used by JACK callback to fill source bufs) ──

/// Returns the number of render function sources for clip [idx].
int32_t dvh_alooper_get_render_source_count(int32_t idx);

/// Returns the [srcIdx]-th render function source for clip [idx].
DvhRenderFn dvh_alooper_get_render_source(int32_t idx, int32_t srcIdx);

/// Returns the number of plugin sources for clip [idx].
int32_t dvh_alooper_get_plugin_source_count(int32_t idx);

/// Returns the [srcIdx]-th plugin ordinal index for clip [idx].
int32_t dvh_alooper_get_plugin_source(int32_t idx, int32_t srcIdx);

/// Returns 1 if clip [idx] is active (has allocated buffers), 0 otherwise.
int32_t dvh_alooper_is_active(int32_t idx);

// ── RT process function ────────────────────────────────────────────────────

/// Process all active audio looper clips for one audio block.
///
/// [clipSrcL/R]: array of ALOOPER_MAX_CLIPS pointers to per-clip source
///   buffers (filled by the JACK callback before this call).  NULL entries
///   mean "no source connected" — the clip records silence.
/// [mixL/R]: final output buffer (looper playback is ADDED here).
/// [blockSize]: frames in this block.
/// [bpm], [timeSigNum], [sampleRate], [isPlaying], [positionInBeats]:
///   transport state for bar-sync detection.
void dvh_alooper_process(
    const float* const* clipSrcL, const float* const* clipSrcR,
    float* mixL, float* mixR,
    int32_t blockSize,
    double bpm, int32_t timeSigNum, int32_t sampleRate,
    bool isPlaying, double positionInBeats);

#ifdef __cplusplus
}
#endif
