// audio_looper.cpp — PCM audio looper implementation.
//
// Per-clip audio sources: each clip reads from its own source buffer
// (filled by the JACK callback from a render function or plugin output).
// No source = silence (the user must cable an instrument into the looper).

#include "../include/audio_looper.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>

// ── Clip data structure ────────────────────────────────────────────────────

struct ALooperClip {
    float* dataL = nullptr;
    float* dataR = nullptr;
    int32_t capacity = 0;

    std::atomic<int32_t> length{0};
    std::atomic<int32_t> head{0};
    std::atomic<int32_t> state{ALOOPER_IDLE};
    std::atomic<float>   volume{1.0f};
    std::atomic<int32_t> reversed{0};
    std::atomic<double>  targetLengthBeats{0.0};

    /// Per-clip audio sources (multiple allowed, mixed/summed).
    /// Protected by g_looperMtx for add/clear (non-RT).
    /// The JACK callback reads these under a simple count + array scan.
    DvhRenderFn renderSources[ALOOPER_MAX_SOURCES] = {};
    int32_t     renderSourceCount = 0;
    int32_t     pluginSources[ALOOPER_MAX_SOURCES] = {};  // ordinal indices, -1 = unused
    int32_t     pluginSourceCount = 0;

    /// Bar-sync mode: 1 = wait for downbeat, 0 = start immediately.
    std::atomic<int32_t> barSync{1};

    int32_t sampleRate = 48000;
    double recordStartBeat = 0.0;
    bool active = false;
};

// ── Global clip pool ───────────────────────────────────────────────────────

static ALooperClip g_clips[ALOOPER_MAX_CLIPS];
static std::mutex  g_looperMtx;

static ALooperClip* _getClip(int32_t idx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS) return nullptr;
    if (!g_clips[idx].active) return nullptr;
    return &g_clips[idx];
}

// ── Helper: record one sample from source into clip ────────────────────────

/// Writes one frame from [srcL/R] at position [srcIdx] into the clip at
/// position [h].  Returns the new head position (h+1).
static inline int32_t _recordSample(
    ALooperClip& clip, int32_t h,
    const float* srcL, const float* srcR, int i)
{
    clip.dataL[h] = srcL ? srcL[i] : 0.0f;
    clip.dataR[h] = srcR ? srcR[i] : 0.0f;
    return h + 1;
}

// ── RT process function ────────────────────────────────────────────────────

void dvh_alooper_process(
    const float* const* clipSrcL, const float* const* clipSrcR,
    float* mixL, float* mixR,
    int32_t blockSize,
    double bpm, int32_t timeSigNum, int32_t sampleRate,
    bool isPlaying, double positionInBeats)
{
    const double beatsPerSample = (bpm > 0.0 && sampleRate > 0)
        ? bpm / (60.0 * sampleRate) : 0.0;

    for (int c = 0; c < ALOOPER_MAX_CLIPS; ++c) {
        auto& clip = g_clips[c];
        if (!clip.active) continue;

        const int32_t st = clip.state.load(std::memory_order_relaxed);
        if (st == ALOOPER_IDLE) continue;

        // Per-clip source buffers (may be NULL if no source connected).
        const float* srcL = clipSrcL[c];
        const float* srcR = clipSrcR[c];

        // ── Armed ──────────────────────────────────────────────────
        if (st == ALOOPER_ARMED) {
            const bool sync = clip.barSync.load(std::memory_order_relaxed) != 0;

            if (!sync || !isPlaying) {
                // Free-form mode or transport stopped: start immediately.
                clip.state.store(ALOOPER_RECORDING, std::memory_order_relaxed);
                clip.head.store(0, std::memory_order_relaxed);
                clip.length.store(0, std::memory_order_relaxed);
                clip.recordStartBeat = positionInBeats;
                int32_t h = 0;
                for (int j = 0; j < blockSize && h < clip.capacity; ++j) {
                    h = _recordSample(clip, h, srcL, srcR, j);
                }
                clip.head.store(h, std::memory_order_relaxed);
                clip.length.store(h, std::memory_order_relaxed);
                continue;
            }

            // Bar-synced: find exact downbeat sample in this block.
            for (int i = 0; i < blockSize; ++i) {
                const double beatAtSample = positionInBeats + i * beatsPerSample;
                const double barBeat = std::fmod(beatAtSample, static_cast<double>(timeSigNum));
                if (barBeat < beatsPerSample || barBeat > (timeSigNum - beatsPerSample)) {
                    clip.state.store(ALOOPER_RECORDING, std::memory_order_relaxed);
                    clip.head.store(0, std::memory_order_relaxed);
                    clip.length.store(0, std::memory_order_relaxed);
                    clip.recordStartBeat = beatAtSample;
                    int32_t h = 0;
                    for (int j = i; j < blockSize && h < clip.capacity; ++j) {
                        h = _recordSample(clip, h, srcL, srcR, j);
                    }
                    clip.head.store(h, std::memory_order_relaxed);
                    clip.length.store(h, std::memory_order_relaxed);
                    break;
                }
            }
            continue;
        }

        // ── Recording ──────────────────────────────────────────────
        if (st == ALOOPER_RECORDING) {
            int32_t h = clip.head.load(std::memory_order_relaxed);
            const double targetBeats = clip.targetLengthBeats.load(std::memory_order_relaxed);
            int32_t targetFrames = 0;
            if (targetBeats > 0.0 && bpm > 0.0) {
                targetFrames = static_cast<int32_t>(
                    targetBeats * 60.0 / bpm * sampleRate + 0.5);
            }

            for (int i = 0; i < blockSize; ++i) {
                if (h >= clip.capacity || (targetFrames > 0 && h >= targetFrames)) {
                    // Stop recording → start playing.
                    clip.length.store(h, std::memory_order_relaxed);
                    clip.state.store(ALOOPER_PLAYING, std::memory_order_relaxed);
                    clip.head.store(0, std::memory_order_relaxed);
                    // Play back remaining samples.
                    const int32_t len = h;
                    if (len > 0) {
                        const float vol = clip.volume.load(std::memory_order_relaxed);
                        const bool rev = clip.reversed.load(std::memory_order_relaxed) != 0;
                        int32_t ph = 0;
                        for (int j = i; j < blockSize; ++j) {
                            const int32_t ri = rev ? (len - 1 - ph) : ph;
                            mixL[j] += clip.dataL[ri] * vol;
                            mixR[j] += clip.dataR[ri] * vol;
                            ph = (ph + 1) % len;
                        }
                        clip.head.store(ph, std::memory_order_relaxed);
                    }
                    goto next_clip;
                }
                h = _recordSample(clip, h, srcL, srcR, i);
            }
            clip.head.store(h, std::memory_order_relaxed);
            clip.length.store(h, std::memory_order_relaxed);
            continue;
        }

        // ── Playing ────────────────────────────────────────────────
        if (st == ALOOPER_PLAYING) {
            const int32_t len = clip.length.load(std::memory_order_relaxed);
            if (len == 0) continue;
            const float vol = clip.volume.load(std::memory_order_relaxed);
            const bool rev = clip.reversed.load(std::memory_order_relaxed) != 0;
            int32_t h = clip.head.load(std::memory_order_relaxed);
            for (int i = 0; i < blockSize; ++i) {
                const int32_t ri = rev ? (len - 1 - h) : h;
                mixL[i] += clip.dataL[ri] * vol;
                mixR[i] += clip.dataR[ri] * vol;
                h = (h + 1) % len;
            }
            clip.head.store(h, std::memory_order_relaxed);
            continue;
        }

        // ── Overdubbing ────────────────────────────────────────────
        if (st == ALOOPER_OVERDUBBING) {
            const int32_t len = clip.length.load(std::memory_order_relaxed);
            if (len == 0) continue;
            const float vol = clip.volume.load(std::memory_order_relaxed);
            const bool rev = clip.reversed.load(std::memory_order_relaxed) != 0;
            int32_t h = clip.head.load(std::memory_order_relaxed);
            for (int i = 0; i < blockSize; ++i) {
                const int32_t ri = rev ? (len - 1 - h) : h;
                const float oldL = clip.dataL[ri];
                const float oldR = clip.dataR[ri];
                mixL[i] += oldL * vol;
                mixR[i] += oldR * vol;
                // Sum new source input on top of existing audio.
                clip.dataL[ri] = oldL + (srcL ? srcL[i] : 0.0f);
                clip.dataR[ri] = oldR + (srcR ? srcR[i] : 0.0f);
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
    clip.targetLengthBeats.store(0.0, std::memory_order_relaxed);
    clip.renderSourceCount = 0;
    clip.pluginSourceCount = 0;
    clip.barSync.store(1, std::memory_order_relaxed);
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
    clip.renderSourceCount = 0;
    clip.pluginSourceCount = 0;
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
    if (state == ALOOPER_ARMED) {
        clip->head.store(0, std::memory_order_relaxed);
        clip->length.store(0, std::memory_order_relaxed);
    }
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

void dvh_alooper_set_length_beats(DVH_Host /*host*/, int32_t idx, double lengthBeats) {
    auto* clip = _getClip(idx);
    if (clip) clip->targetLengthBeats.store(lengthBeats, std::memory_order_relaxed);
}

void dvh_alooper_clear_sources(int32_t idx) {
    std::lock_guard<std::mutex> lk(g_looperMtx);
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS) return;
    g_clips[idx].renderSourceCount = 0;
    g_clips[idx].pluginSourceCount = 0;
}

void dvh_alooper_add_render_source(int32_t idx, DvhRenderFn fn) {
    if (!fn) return;
    std::lock_guard<std::mutex> lk(g_looperMtx);
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return;
    auto& clip = g_clips[idx];
    // Dedup.
    for (int i = 0; i < clip.renderSourceCount; ++i)
        if (clip.renderSources[i] == fn) return;
    if (clip.renderSourceCount >= ALOOPER_MAX_SOURCES) return;
    clip.renderSources[clip.renderSourceCount++] = fn;
}

void dvh_alooper_add_source_plugin(int32_t idx, int32_t pluginOrdinalIdx) {
    if (pluginOrdinalIdx < 0) return;
    std::lock_guard<std::mutex> lk(g_looperMtx);
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return;
    auto& clip = g_clips[idx];
    // Dedup.
    for (int i = 0; i < clip.pluginSourceCount; ++i)
        if (clip.pluginSources[i] == pluginOrdinalIdx) return;
    if (clip.pluginSourceCount >= ALOOPER_MAX_SOURCES) return;
    clip.pluginSources[clip.pluginSourceCount++] = pluginOrdinalIdx;
}

void dvh_alooper_set_bar_sync(int32_t idx, int32_t enabled) {
    auto* clip = _getClip(idx);
    if (clip) clip->barSync.store(enabled, std::memory_order_relaxed);
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

int32_t dvh_alooper_get_render_source_count(int32_t idx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return 0;
    return g_clips[idx].renderSourceCount;
}

DvhRenderFn dvh_alooper_get_render_source(int32_t idx, int32_t srcIdx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return nullptr;
    if (srcIdx < 0 || srcIdx >= g_clips[idx].renderSourceCount) return nullptr;
    return g_clips[idx].renderSources[srcIdx];
}

int32_t dvh_alooper_get_plugin_source_count(int32_t idx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return 0;
    return g_clips[idx].pluginSourceCount;
}

int32_t dvh_alooper_get_plugin_source(int32_t idx, int32_t srcIdx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return -1;
    if (srcIdx < 0 || srcIdx >= g_clips[idx].pluginSourceCount) return -1;
    return g_clips[idx].pluginSources[srcIdx];
}

int32_t dvh_alooper_is_active(int32_t idx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS) return 0;
    return g_clips[idx].active ? 1 : 0;
}

int32_t dvh_alooper_load_data(DVH_Host /*host*/, int32_t idx,
                               const float* srcL, const float* srcR,
                               int32_t lengthFrames) {
    auto* clip = _getClip(idx);
    if (!clip || !srcL || !srcR) return 0;
    if (clip->state.load(std::memory_order_relaxed) != ALOOPER_IDLE) return 0;
    if (lengthFrames <= 0 || lengthFrames > clip->capacity) return 0;
    std::memcpy(clip->dataL, srcL, lengthFrames * sizeof(float));
    std::memcpy(clip->dataR, srcR, lengthFrames * sizeof(float));
    clip->length.store(lengthFrames, std::memory_order_relaxed);
    clip->head.store(0, std::memory_order_relaxed);
    fprintf(stderr, "[audio_looper] Loaded %d frames into clip %d\n", lengthFrames, idx);
    return 1;
}

} // extern "C"
