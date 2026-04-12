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
    ALOOPER_STOPPING   = 5,  // padding silence to next bar boundary
};

/// Opaque handle (unused — looper uses a global clip pool).
typedef void* DVH_Host;

// ── Clip lifecycle ─────────────────────────────────────────────────────────

DVH_API int32_t dvh_alooper_create(DVH_Host host, float maxSeconds, int32_t sampleRate);
DVH_API void    dvh_alooper_destroy(DVH_Host host, int32_t idx);

// ── State control ──────────────────────────────────────────────────────────

DVH_API void    dvh_alooper_set_state(DVH_Host host, int32_t idx, int32_t state);
DVH_API int32_t dvh_alooper_get_state(DVH_Host host, int32_t idx);

/// Erases the recorded PCM data for clip [idx] without changing its state.
///
/// Dart's clear() calls this after a set_state(IDLE) transition to wipe
/// the clip's audio while keeping the slot alive. Separate from set_state
/// so that pausing playback (IDLE) does not discard recorded content —
/// required for autosave round-trip to work across stop → relaunch.
DVH_API void    dvh_alooper_clear_data(int32_t idx);

// ── Parameters ─────────────────────────────────────────────────────────────

DVH_API void dvh_alooper_set_volume(DVH_Host host, int32_t idx, float volume);
DVH_API void dvh_alooper_set_reversed(DVH_Host host, int32_t idx, int32_t reversed);
DVH_API void dvh_alooper_set_length_beats(DVH_Host host, int32_t idx, double lengthBeats);

// ── Audio source routing (multiple sources per clip) ──────────────────────
//
// A clip can have multiple audio sources (e.g. two keyboards + a drum
// generator all cabled to the same looper).  The audio callback mixes all
// connected sources into the clip's source buffer each block.
//
// Three source kinds exist:
//   1. Render function sources (DvhRenderFn pointers) — used on Linux/macOS,
//      where each slot has a distinct exported C symbol.
//   2. Plugin ordinal sources — used on Linux/macOS for VST3 plugin outputs.
//   3. Bus slot sources (int IDs) — used on Android, where the Oboe bus keeps
//      one slot per source and a single shared render function cannot
//      disambiguate two instances of the same instrument class.

/// Maximum audio sources per clip, per kind (render / plugin / bus).
#define ALOOPER_MAX_SOURCES 8

/// Remove all audio sources from clip [idx] — clears render, plugin AND bus
/// source lists.  Called at the start of every routing sync so the clip
/// always reflects the current cable topology exactly.
DVH_API void dvh_alooper_clear_sources(int32_t idx);

/// Add a render function as an audio source for clip [idx].
/// Multiple render sources can be added — they are mixed (summed) each block.
DVH_API void dvh_alooper_add_render_source(int32_t idx, DvhRenderFn fn);

/// Add a VST3 plugin output as an audio source for clip [idx].
/// [pluginOrdinalIdx] is the plugin's ordinal in the routing snapshot.
DVH_API void dvh_alooper_add_source_plugin(int32_t idx, int32_t pluginOrdinalIdx);

/// Add an Android Oboe bus slot as an audio source for clip [idx].
///
/// [busSlotId] matches the ID passed to `oboe_stream_add_source`:
///   - Keyboards: the dynamic FluidSynth `sfId` assigned at load time.
///   - Theremin:  `OBOE_BUS_SLOT_THEREMIN` (100).
///   - (Stylophone and vocoder are not bus-routed on Android and cannot be
///      cabled to the audio looper — their audio lives on separate miniaudio
///      devices that never reach the shared AAudio render pipeline.)
DVH_API void dvh_alooper_add_bus_source(int32_t idx, int32_t busSlotId);

/// Enable or disable bar-sync for clip [idx].
/// When enabled (default), armed→recording waits for the next downbeat.
/// When disabled, armed→recording starts immediately.
DVH_API void dvh_alooper_set_bar_sync(int32_t idx, int32_t enabled);

/// Set the number of bars to skip after arming before recording starts.
/// When > 0, the ARMED state counts downbeat crossings and only transitions
/// to RECORDING after [bars] downbeats have passed.  Used for count-in:
/// the drum generator plays 4 stick hits in bar 1, so skipBars=1 waits
/// for bar 2 before recording.  Set to 0 to start on the next downbeat.
DVH_API void dvh_alooper_set_skip_bars(int32_t idx, int32_t bars);

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

/// Returns the number of bus slot sources for clip [idx] (Android only).
int32_t dvh_alooper_get_bus_source_count(int32_t idx);

/// Returns the [srcIdx]-th bus slot ID for clip [idx], or -1 if out of range.
int32_t dvh_alooper_get_bus_source(int32_t idx, int32_t srcIdx);

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
