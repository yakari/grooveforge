// audio_looper.h — PCM audio looper for GrooveForge.
//
// Records and plays back raw stereo PCM audio in sync with the transport.
// All buffer access happens on the JACK/AAudio audio thread (RT-safe).
// State changes (arm, play, stop) are communicated via atomic fields.
//
// Architecture:
//   - Clip buffers are pre-allocated on the Dart thread via dvh_alooper_create.
//   - The audio callback reads/writes clip data with zero allocation.
//   - Bar-sync: the callback detects downbeat crossings using a running
//     sample counter and transitions armed → recording at sample precision.
//   - Overdub: reads old buffer to output, sums new input, writes back.
//     Recording taps the mix BEFORE looper playback is injected, preventing
//     feedback loops.

#pragma once
#include <stdint.h>

#ifdef _WIN32
  #ifdef DART_VST_HOST_EXPORTS
    #define DVH_API __declspec(dllexport)
  #else
    #define DVH_API __declspec(dllimport)
  #endif
#else
  #define DVH_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/// Maximum simultaneous audio looper clips.
#define ALOOPER_MAX_CLIPS 8

/// Clip state machine (values stored in std::atomic<int32_t>).
///
/// ```
///   idle ──arm──→ armed ──(downbeat)──→ recording
///                                          │
///     ┌──────── playing ←──(boundary)──────┘
///     │            │
///     │         overdub ←──(user action)
///     │            │
///     └────────────┘──stop──→ idle
/// ```
enum ALooperState {
    ALOOPER_IDLE       = 0,
    ALOOPER_ARMED      = 1,
    ALOOPER_RECORDING  = 2,
    ALOOPER_PLAYING    = 3,
    ALOOPER_OVERDUBBING = 4,
};

/// Source to record from.
enum ALooperSource {
    /// Record from the master mix bus (post all instruments, pre looper playback).
    ALOOPER_SOURCE_MASTER = 0,
    /// Record from a specific plugin's per-plugin output buffer.
    ALOOPER_SOURCE_PLUGIN = 1,
};

/// Opaque handle to the host's audio looper subsystem.
typedef void* DVH_Host;

// ── Clip lifecycle ─────────────────────────────────────────────────────────

/// Create a new audio looper clip with [maxSeconds] of pre-allocated stereo
/// buffer at [sampleRate].  Returns the clip index (0 .. ALOOPER_MAX_CLIPS-1)
/// or -1 if the pool is full.
///
/// Must be called from the Dart thread (allocates memory).
DVH_API int32_t dvh_alooper_create(DVH_Host host, float maxSeconds, int32_t sampleRate);

/// Destroy clip [idx] and free its buffers.  No-op if idx is invalid or
/// the slot is already empty.  Must NOT be called while the clip is
/// recording or playing — set state to idle first and drain one callback.
DVH_API void dvh_alooper_destroy(DVH_Host host, int32_t idx);

// ── State control ──────────────────────────────────────────────────────────

/// Set the state of clip [idx].  The callback reads this atomically.
///
/// Valid transitions:
///   idle → armed (Dart arms for recording)
///   armed → recording (callback detects downbeat — do NOT call from Dart)
///   recording → playing (callback detects loop boundary — or Dart stops early)
///   playing → overdubbing (Dart starts overdub)
///   overdubbing → playing (Dart stops overdub)
///   any → idle (Dart stops/clears)
DVH_API void dvh_alooper_set_state(DVH_Host host, int32_t idx, int32_t state);

/// Read the current state of clip [idx].  Useful for Dart to detect when
/// the callback transitions armed → recording or recording → playing.
DVH_API int32_t dvh_alooper_get_state(DVH_Host host, int32_t idx);

// ── Parameters ─────────────────────────────────────────────────────────────

/// Set the playback volume for clip [idx].  [volume] is 0.0–1.0.
DVH_API void dvh_alooper_set_volume(DVH_Host host, int32_t idx, float volume);

/// Toggle reverse playback for clip [idx].
DVH_API void dvh_alooper_set_reversed(DVH_Host host, int32_t idx, int32_t reversed);

/// Set the recording source type for clip [idx].
/// [sourceType] is ALOOPER_SOURCE_MASTER or ALOOPER_SOURCE_PLUGIN.
/// [sourcePluginIdx] is the plugin's ordinal index in the routing snapshot
/// (only used when sourceType == ALOOPER_SOURCE_PLUGIN).
DVH_API void dvh_alooper_set_source(DVH_Host host, int32_t idx,
                                     int32_t sourceType, int32_t sourcePluginIdx);

/// Set the loop length in beats for clip [idx].  When > 0, the callback
/// auto-transitions recording → playing after this many beats.
/// Set to 0 for "record until manually stopped" (free-form mode).
DVH_API void dvh_alooper_set_length_beats(DVH_Host host, int32_t idx, double lengthBeats);

// ── Buffer access (for Dart-side waveform preview and WAV export) ──────────

/// Returns a pointer to the left channel PCM data of clip [idx].
/// The returned pointer is valid until dvh_alooper_destroy is called.
/// Dart may read [0 .. dvh_alooper_get_length()) safely on a non-RT thread.
DVH_API const float* dvh_alooper_get_data_l(DVH_Host host, int32_t idx);

/// Returns a pointer to the right channel PCM data of clip [idx].
DVH_API const float* dvh_alooper_get_data_r(DVH_Host host, int32_t idx);

/// Returns the current length in frames (how much has been recorded).
DVH_API int32_t dvh_alooper_get_length(DVH_Host host, int32_t idx);

/// Returns the pre-allocated capacity in frames.
DVH_API int32_t dvh_alooper_get_capacity(DVH_Host host, int32_t idx);

/// Returns the current playback/record head position in frames.
DVH_API int32_t dvh_alooper_get_head(DVH_Host host, int32_t idx);

/// Returns total memory used by all clips in bytes.
DVH_API int64_t dvh_alooper_memory_used(DVH_Host host);

// ── RT process function (called from JACK/AAudio callback) ─────────────────
// NOT part of the Dart-facing C API. Called directly from the audio callback
// after the master mix is accumulated but before soft-clipping.

/// Process all active audio looper clips for one audio block.
///
/// [preMixL/R]: master mix before looper playback (record source — no feedback).
/// [mixL/R]: final output buffer (looper playback is ADDED here).
/// [blockSize]: frames in this block.
/// [bpm]: current transport tempo.
/// [timeSigNum]: beats per bar (e.g. 4 for 4/4).
/// [sampleRate]: audio sample rate.
/// [isPlaying]: whether the transport is running.
/// [positionInBeats]: current transport position in beats.
void dvh_alooper_process(
    const float* preMixL, const float* preMixR,
    float* mixL, float* mixR,
    int32_t blockSize,
    double bpm, int32_t timeSigNum, int32_t sampleRate,
    bool isPlaying, double positionInBeats);

#ifdef __cplusplus
}
#endif
