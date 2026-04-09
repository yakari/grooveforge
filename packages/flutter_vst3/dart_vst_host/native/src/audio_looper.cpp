// audio_looper.cpp — PCM audio looper implementation.
//
// All clip buffers are pre-allocated. The process function
// (dvh_alooper_process) is called from the JACK/AAudio RT callback
// and performs zero allocation.
//
// Bar-sync: the process function maintains a running beat position
// computed from a sample counter and the current BPM. When an armed
// clip detects a downbeat crossing within the current block, recording
// starts at the exact sample where the downbeat falls.

#include "../include/audio_looper.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>

// ── Clip data structure ────────────────────────────────────────────────────

/// Internal representation of one audio looper clip.
/// All atomic fields are accessed from the RT thread; all others are set
/// from the Dart thread before arming.
struct ALooperClip {
    /// Pre-allocated stereo PCM buffers.  Allocated in dvh_alooper_create,
    /// freed in dvh_alooper_destroy.  The RT callback reads/writes these
    /// directly — no copy, no lock.
    float* dataL = nullptr;
    float* dataR = nullptr;

    /// Maximum capacity in frames (set at creation, immutable).
    int32_t capacity = 0;

    /// How many frames have been recorded.  Grows during recording,
    /// immutable during playback.  The RT callback writes this atomically
    /// so Dart can poll it for progress display.
    std::atomic<int32_t> length{0};

    /// Current read/write head position in frames.
    std::atomic<int32_t> head{0};

    /// Clip state machine.  Written by Dart (arm, stop) and by the RT
    /// callback (armed→recording, recording→playing on loop boundary).
    std::atomic<int32_t> state{ALOOPER_IDLE};

    /// Playback volume multiplier (0.0–1.0).
    std::atomic<float> volume{1.0f};

    /// When true, playback runs backwards.
    std::atomic<int32_t> reversed{0};

    /// Recording source configuration.
    std::atomic<int32_t> sourceType{ALOOPER_SOURCE_MASTER};
    std::atomic<int32_t> sourcePluginIdx{0};

    /// Target loop length in beats.  0 = free-form (record until stopped).
    /// The callback uses this with BPM to compute the frame count.
    std::atomic<double> targetLengthBeats{0.0};

    /// Sample rate used for beat→frame conversion.
    int32_t sampleRate = 48000;

    /// Beat position when recording started (set by the RT callback at the
    /// exact downbeat sample).  Used to compute when targetLengthBeats is
    /// reached.
    double recordStartBeat = 0.0;

    /// Whether this slot is allocated (has buffers).
    bool active = false;
};

// ── Global clip pool ───────────────────────────────────────────────────────

/// Fixed-size pool of clips.  Indexed by the clip index returned to Dart.
/// Protected by g_looperMtx for create/destroy (non-RT).  The RT callback
/// reads clips without locking — it only accesses atomic fields and raw
/// buffer pointers that are stable between create and destroy.
static ALooperClip g_clips[ALOOPER_MAX_CLIPS];
static std::mutex  g_looperMtx;

// ── Internal helpers ───────────────────────────────────────────────────────

/// Returns a pointer to clip [idx] if it is active, or nullptr.
static ALooperClip* _getClip(int32_t idx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS) return nullptr;
    if (!g_clips[idx].active) return nullptr;
    return &g_clips[idx];
}

// ── RT-callable process function ───────────────────────────────────────────
//
// Called from the JACK/AAudio callback AFTER the master mix is accumulated
// but BEFORE soft-clipping.  The [preMixL/R] buffers contain the master
// mix signal that the looper can record from (pre-looper-playback, so
// overdub does not create feedback).  The [mixL/R] buffers are the final
// output that the looper's playback is added to.
//
// This function is NOT part of the C API — it is called directly from the
// JACK callback in dart_vst_host_jack.cpp.

/// Process all active audio looper clips for one audio block.
///
/// [preMixL/R]: the master mix before looper playback injection (record source).
/// [mixL/R]: the final output buffer (looper playback is ADDED here).
/// [blockSize]: number of frames in this block.
/// [bpm]: current transport tempo.
/// [timeSigNum]: beats per bar (e.g. 4 for 4/4 time).
/// [sampleRate]: audio sample rate.
/// [isPlaying]: whether the transport is running.
/// [positionInBeats]: current transport position in beats (from dvh_set_transport).
void dvh_alooper_process(
    const float* preMixL, const float* preMixR,
    float* mixL, float* mixR,
    int32_t blockSize,
    double bpm, int32_t timeSigNum, int32_t sampleRate,
    bool isPlaying, double positionInBeats)
{
    if (bpm <= 0.0 || !isPlaying) {
        // Transport not running — still play back existing clips but don't
        // advance armed/recording state.
        for (int c = 0; c < ALOOPER_MAX_CLIPS; ++c) {
            auto& clip = g_clips[c];
            if (!clip.active) continue;
            const int32_t st = clip.state.load(std::memory_order_relaxed);
            if (st != ALOOPER_PLAYING && st != ALOOPER_OVERDUBBING) continue;

            const int32_t len = clip.length.load(std::memory_order_relaxed);
            if (len == 0) continue;
            const float vol = clip.volume.load(std::memory_order_relaxed);
            const bool rev = clip.reversed.load(std::memory_order_relaxed) != 0;
            int32_t h = clip.head.load(std::memory_order_relaxed);

            for (int i = 0; i < blockSize; ++i) {
                const int32_t readIdx = rev ? (len - 1 - h) : h;
                mixL[i] += clip.dataL[readIdx] * vol;
                mixR[i] += clip.dataR[readIdx] * vol;
                h = (h + 1) % len;
            }
            clip.head.store(h, std::memory_order_relaxed);
        }
        return;
    }

    // Compute beats-per-sample for downbeat detection.
    const double beatsPerSample = bpm / (60.0 * sampleRate);

    for (int c = 0; c < ALOOPER_MAX_CLIPS; ++c) {
        auto& clip = g_clips[c];
        if (!clip.active) continue;

        const int32_t st = clip.state.load(std::memory_order_relaxed);
        if (st == ALOOPER_IDLE) continue;

        // ── Armed: wait for next downbeat ──────────────────────────────
        if (st == ALOOPER_ARMED) {
            // Find the exact sample in this block where a bar boundary falls.
            for (int i = 0; i < blockSize; ++i) {
                const double beatAtSample = positionInBeats + i * beatsPerSample;
                const double barBeat = std::fmod(beatAtSample, static_cast<double>(timeSigNum));
                // Downbeat: bar-relative beat is within one sample of 0.
                if (barBeat < beatsPerSample || barBeat > (timeSigNum - beatsPerSample)) {
                    // Transition to recording at this exact sample.
                    clip.state.store(ALOOPER_RECORDING, std::memory_order_relaxed);
                    clip.head.store(0, std::memory_order_relaxed);
                    clip.length.store(0, std::memory_order_relaxed);
                    clip.recordStartBeat = beatAtSample;

                    // Record the remaining samples in this block.
                    for (int j = i; j < blockSize; ++j) {
                        const int32_t h = clip.head.load(std::memory_order_relaxed);
                        if (h >= clip.capacity) {
                            // Buffer full — auto-stop.
                            clip.state.store(ALOOPER_PLAYING, std::memory_order_relaxed);
                            clip.head.store(0, std::memory_order_relaxed);
                            break;
                        }
                        clip.dataL[h] = preMixL[j];
                        clip.dataR[h] = preMixR[j];
                        clip.head.store(h + 1, std::memory_order_relaxed);
                        clip.length.store(h + 1, std::memory_order_relaxed);
                    }
                    break; // done with this clip for this block
                }
            }
            continue; // still armed — no playback yet
        }

        // ── Recording ──────────────────────────────────────────────────
        if (st == ALOOPER_RECORDING) {
            int32_t h = clip.head.load(std::memory_order_relaxed);

            // Check if target length reached (bar-synced stop).
            const double targetBeats = clip.targetLengthBeats.load(std::memory_order_relaxed);
            int32_t targetFrames = 0;
            if (targetBeats > 0.0) {
                targetFrames = static_cast<int32_t>(
                    targetBeats * 60.0 / bpm * sampleRate + 0.5);
            }

            for (int i = 0; i < blockSize; ++i) {
                if (h >= clip.capacity ||
                    (targetFrames > 0 && h >= targetFrames)) {
                    // Stop recording → start playing.
                    clip.length.store(h, std::memory_order_relaxed);
                    clip.state.store(ALOOPER_PLAYING, std::memory_order_relaxed);
                    clip.head.store(0, std::memory_order_relaxed);

                    // Play back the remaining samples in this block.
                    const int32_t len = h;
                    if (len > 0) {
                        const float vol = clip.volume.load(std::memory_order_relaxed);
                        const bool rev = clip.reversed.load(std::memory_order_relaxed) != 0;
                        int32_t ph = 0;
                        for (int j = i; j < blockSize; ++j) {
                            const int32_t readIdx = rev ? (len - 1 - ph) : ph;
                            mixL[j] += clip.dataL[readIdx] * vol;
                            mixR[j] += clip.dataR[readIdx] * vol;
                            ph = (ph + 1) % len;
                        }
                        clip.head.store(ph, std::memory_order_relaxed);
                    }
                    goto next_clip;
                }
                clip.dataL[h] = preMixL[i];
                clip.dataR[h] = preMixR[i];
                ++h;
            }
            clip.head.store(h, std::memory_order_relaxed);
            clip.length.store(h, std::memory_order_relaxed);
            continue;
        }

        // ── Playing ────────────────────────────────────────────────────
        if (st == ALOOPER_PLAYING) {
            const int32_t len = clip.length.load(std::memory_order_relaxed);
            if (len == 0) continue;
            const float vol = clip.volume.load(std::memory_order_relaxed);
            const bool rev = clip.reversed.load(std::memory_order_relaxed) != 0;
            int32_t h = clip.head.load(std::memory_order_relaxed);

            for (int i = 0; i < blockSize; ++i) {
                const int32_t readIdx = rev ? (len - 1 - h) : h;
                mixL[i] += clip.dataL[readIdx] * vol;
                mixR[i] += clip.dataR[readIdx] * vol;
                h = (h + 1) % len;
            }
            clip.head.store(h, std::memory_order_relaxed);
            continue;
        }

        // ── Overdubbing ────────────────────────────────────────────────
        // Read old buffer → output, sum new input → write back.
        if (st == ALOOPER_OVERDUBBING) {
            const int32_t len = clip.length.load(std::memory_order_relaxed);
            if (len == 0) continue;
            const float vol = clip.volume.load(std::memory_order_relaxed);
            const bool rev = clip.reversed.load(std::memory_order_relaxed) != 0;
            int32_t h = clip.head.load(std::memory_order_relaxed);

            for (int i = 0; i < blockSize; ++i) {
                const int32_t idx = rev ? (len - 1 - h) : h;
                // Play the existing audio.
                const float oldL = clip.dataL[idx];
                const float oldR = clip.dataR[idx];
                mixL[i] += oldL * vol;
                mixR[i] += oldR * vol;
                // Sum new input on top of existing audio.
                clip.dataL[idx] = oldL + preMixL[i];
                clip.dataR[idx] = oldR + preMixR[i];
                h = (h + 1) % len;
            }
            clip.head.store(h, std::memory_order_relaxed);
            continue;
        }

        next_clip:;
    }
}

// ── C API implementation ───────────────────────────────────────────────────

extern "C" {

int32_t dvh_alooper_create(DVH_Host /*host*/, float maxSeconds, int32_t sampleRate) {
    std::lock_guard<std::mutex> lk(g_looperMtx);

    // Find a free slot.
    int32_t idx = -1;
    for (int i = 0; i < ALOOPER_MAX_CLIPS; ++i) {
        if (!g_clips[i].active) { idx = i; break; }
    }
    if (idx < 0) return -1;

    auto& clip = g_clips[idx];
    clip.capacity = static_cast<int32_t>(maxSeconds * sampleRate + 0.5f);
    if (clip.capacity <= 0) return -1;

    clip.dataL = new float[clip.capacity]();
    clip.dataR = new float[clip.capacity]();
    clip.sampleRate = sampleRate;
    clip.length.store(0, std::memory_order_relaxed);
    clip.head.store(0, std::memory_order_relaxed);
    clip.state.store(ALOOPER_IDLE, std::memory_order_relaxed);
    clip.volume.store(1.0f, std::memory_order_relaxed);
    clip.reversed.store(0, std::memory_order_relaxed);
    clip.sourceType.store(ALOOPER_SOURCE_MASTER, std::memory_order_relaxed);
    clip.sourcePluginIdx.store(0, std::memory_order_relaxed);
    clip.targetLengthBeats.store(0.0, std::memory_order_relaxed);
    clip.recordStartBeat = 0.0;
    clip.active = true;

    fprintf(stderr, "[audio_looper] Created clip %d (%.1fs, %d frames, sr=%d)\n",
            idx, maxSeconds, clip.capacity, sampleRate);
    return idx;
}

void dvh_alooper_destroy(DVH_Host /*host*/, int32_t idx) {
    std::lock_guard<std::mutex> lk(g_looperMtx);
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS) return;
    auto& clip = g_clips[idx];
    if (!clip.active) return;

    clip.active = false;
    clip.state.store(ALOOPER_IDLE, std::memory_order_relaxed);
    delete[] clip.dataL;
    delete[] clip.dataR;
    clip.dataL = nullptr;
    clip.dataR = nullptr;
    clip.capacity = 0;
    clip.length.store(0, std::memory_order_relaxed);
    clip.head.store(0, std::memory_order_relaxed);

    fprintf(stderr, "[audio_looper] Destroyed clip %d\n", idx);
}

void dvh_alooper_set_state(DVH_Host /*host*/, int32_t idx, int32_t state) {
    auto* clip = _getClip(idx);
    if (!clip) return;

    // On transition to armed, reset head and length.
    if (state == ALOOPER_ARMED) {
        clip->head.store(0, std::memory_order_relaxed);
        clip->length.store(0, std::memory_order_relaxed);
    }
    // On transition to playing from recording, ensure head resets.
    if (state == ALOOPER_PLAYING) {
        clip->head.store(0, std::memory_order_relaxed);
    }

    clip->state.store(state, std::memory_order_release);
    fprintf(stderr, "[audio_looper] Clip %d state → %d\n", idx, state);
}

int32_t dvh_alooper_get_state(DVH_Host /*host*/, int32_t idx) {
    auto* clip = _getClip(idx);
    return clip ? clip->state.load(std::memory_order_acquire) : ALOOPER_IDLE;
}

void dvh_alooper_set_volume(DVH_Host /*host*/, int32_t idx, float volume) {
    auto* clip = _getClip(idx);
    if (clip) clip->volume.store(volume, std::memory_order_relaxed);
}

void dvh_alooper_set_reversed(DVH_Host /*host*/, int32_t idx, int32_t reversed) {
    auto* clip = _getClip(idx);
    if (clip) clip->reversed.store(reversed, std::memory_order_relaxed);
}

void dvh_alooper_set_source(DVH_Host /*host*/, int32_t idx,
                             int32_t sourceType, int32_t sourcePluginIdx) {
    auto* clip = _getClip(idx);
    if (!clip) return;
    clip->sourceType.store(sourceType, std::memory_order_relaxed);
    clip->sourcePluginIdx.store(sourcePluginIdx, std::memory_order_relaxed);
}

void dvh_alooper_set_length_beats(DVH_Host /*host*/, int32_t idx, double lengthBeats) {
    auto* clip = _getClip(idx);
    if (clip) clip->targetLengthBeats.store(lengthBeats, std::memory_order_relaxed);
}

const float* dvh_alooper_get_data_l(DVH_Host /*host*/, int32_t idx) {
    auto* clip = _getClip(idx);
    return clip ? clip->dataL : nullptr;
}

const float* dvh_alooper_get_data_r(DVH_Host /*host*/, int32_t idx) {
    auto* clip = _getClip(idx);
    return clip ? clip->dataR : nullptr;
}

int32_t dvh_alooper_get_length(DVH_Host /*host*/, int32_t idx) {
    auto* clip = _getClip(idx);
    return clip ? clip->length.load(std::memory_order_relaxed) : 0;
}

int32_t dvh_alooper_get_capacity(DVH_Host /*host*/, int32_t idx) {
    auto* clip = _getClip(idx);
    return clip ? clip->capacity : 0;
}

int32_t dvh_alooper_get_head(DVH_Host /*host*/, int32_t idx) {
    auto* clip = _getClip(idx);
    return clip ? clip->head.load(std::memory_order_relaxed) : 0;
}

int64_t dvh_alooper_memory_used(DVH_Host /*host*/) {
    int64_t total = 0;
    for (int i = 0; i < ALOOPER_MAX_CLIPS; ++i) {
        if (g_clips[i].active) {
            total += static_cast<int64_t>(g_clips[i].capacity) * 2 * sizeof(float);
        }
    }
    return total;
}

} // extern "C"
