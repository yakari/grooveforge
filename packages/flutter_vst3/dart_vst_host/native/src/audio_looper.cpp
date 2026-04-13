// audio_looper.cpp — PCM audio looper implementation.
//
// Transport-synced design:
//   - Recording starts on exact bar boundary (bar-sync mode).
//   - When the user stops recording, silence is padded to the next bar
//     boundary (STOPPING state) so the loop is always whole-bar aligned.
//   - Playback head is computed from the transport beat position, not a
//     sample counter. This keeps the loop in sync with tempo changes.
//   - Overdub records one full loop pass and auto-returns to playing.

#include "../include/audio_looper.h"
#include "gf_phase_vocoder.h"

#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>

// ── Phase vocoder config ───────────────────────────────────────────────────
//
// A per-clip phase vocoder is used when the current transport BPM differs
// from the BPM at which the loop was recorded. This lets a 120-BPM loop
// play back at 140 BPM without pitch change. When the BPMs match (within a
// small epsilon) the vocoder is bypassed entirely and the classic sample-
// per-sample fast path runs.
//
// FFT_SIZE = 2048 gives good spectral resolution for music without excessive
// latency; HOP = FFT_SIZE/4 yields a 4x overlap which is the sweet spot for
// Hann-window analysis/synthesis reconstruction.
//
// The ring-in transient (first ~N output samples after a reset) is a known
// limitation — tracked as session 2b latency compensation in the roadmap.
static constexpr int kPvFftSize = 2048;
static constexpr int kPvHopSize = 512;
// Max single-block output drained from the vocoder into the scratch buffer.
// Sized to comfortably exceed any plausible audio callback blockSize.
static constexpr int kPvOutScratchFrames = 4096;

// Stretch epsilon: if |1 - ratio| is below this, bypass the vocoder and
// take the original zero-cost fast path. 0.005 corresponds to ~0.6 BPM at
// 120, well below human detection of tempo drift.
static constexpr float kPvBypassEpsilon = 0.005f;

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
    ///
    /// Three kinds in parallel — see [audio_looper.h] for the rationale.
    /// On Linux/macOS only [renderSources] and [pluginSources] are populated;
    /// on Android only [busSources] is populated. The audio callback reads
    /// whichever list applies to its platform.
    DvhRenderFn renderSources[ALOOPER_MAX_SOURCES] = {};
    int32_t     renderSourceCount = 0;
    int32_t     pluginSources[ALOOPER_MAX_SOURCES] = {};
    int32_t     pluginSourceCount = 0;
    int32_t     busSources[ALOOPER_MAX_SOURCES] = {};
    int32_t     busSourceCount = 0;

    /// Bar-sync mode: 1 = wait for downbeat, 0 = start immediately.
    std::atomic<int32_t> barSync{1};

    /// Number of bar downbeats to skip before starting recording.
    /// 0 = record on the very next downbeat.  1 = skip 1 bar (count-in).
    std::atomic<int32_t> skipBars{0};

    /// Counter for downbeats seen since arming (used with skipBars).
    int32_t downbeatsSeen = 0;

    // ── Transport-sync fields ──────────────────────────────────────────
    /// Beat position where the loop starts (exact bar boundary).
    double loopStartBeat = 0.0;
    /// Loop length in beats (set when recording→playing, always whole bars).
    double loopLengthBeats = 0.0;
    /// Authoritative frame count (may include silence padding to bar boundary).
    int32_t loopLengthFrames = 0;
    /// Head position when overdub started — auto-stop after one full pass.
    int32_t overdubStartHead = -1;
    /// BPM at which the loop was recorded (for frame↔beat conversion).
    double recordBpm = 120.0;

    int32_t sampleRate = 48000;
    double recordStartBeat = 0.0;
    bool active = false;

    // ── Phase vocoder (tempo-synced playback) ──────────────────────────
    /// Per-clip phase vocoder context. Allocated in dvh_alooper_create,
    /// freed in dvh_alooper_destroy — never touched from the audio thread.
    /// Always non-null between create/destroy so the RT path never branches
    /// on allocation.
    gf_pv_context* pv = nullptr;
    /// Interleaved stereo scratch for feeding one analysis hop into the
    /// vocoder. Size: kPvHopSize frames × 2 channels.
    float* pvScratchIn = nullptr;
    /// Interleaved stereo scratch for draining output from the vocoder.
    /// Size: kPvOutScratchFrames frames × 2 channels.
    float* pvScratchOut = nullptr;
    /// Set to 1 by any state transition that should flush the vocoder's
    /// internal phase accumulators and OLA tail (entering PLAYING fresh,
    /// clearing clip data, etc.). The RT path reads + clears this with an
    /// exchange so the reset happens at most once per transition.
    std::atomic<int32_t> pvNeedsReset{0};
};

// ── Global clip pool ───────────────────────────────────────────────────────

static ALooperClip g_clips[ALOOPER_MAX_CLIPS];
static std::mutex  g_looperMtx;

static ALooperClip* _getClip(int32_t idx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS) return nullptr;
    if (!g_clips[idx].active) return nullptr;
    return &g_clips[idx];
}

// ── Helper: read one stereo frame from a clip's recorded buffer ────────────
//
// Honors the reverse-playback flag by mirroring the index against the loop
// length. Pure function of inputs; used by both the fast playback path and
// the phase vocoder feed loop.
static inline void _readClipFrame(
    const ALooperClip& clip, int32_t h, int32_t len, bool reversed,
    float* outL, float* outR)
{
    const int32_t ri = reversed ? (len - 1 - h) : h;
    *outL = clip.dataL[ri];
    *outR = clip.dataR[ri];
}

// ── Helper: drain already-queued PV output into the mix bus ────────────────
//
// Pulls up to [wanted] stereo frames out of the phase vocoder's output ring
// via a single gf_pv_process_block call (no input fed), deinterleaves them,
// and sums them into mixL/mixR with the clip volume applied. Returns the
// number of frames actually emitted (may be less than [wanted] if the PV
// output ring is currently empty).
static inline int _drainPvInto(
    ALooperClip& clip, float vol,
    float* mixL, float* mixR, int startIdx, int wanted)
{
    const int cap = wanted;
    const int got = gf_pv_process_block(
        clip.pv, /*input*/nullptr, /*num_frames*/0,
        clip.pvScratchOut, cap);
    for (int i = 0; i < got; ++i) {
        mixL[startIdx + i] += clip.pvScratchOut[i * 2]     * vol;
        mixR[startIdx + i] += clip.pvScratchOut[i * 2 + 1] * vol;
    }
    return got;
}

// ── Helper: feed one analysis hop of clip audio into the PV ────────────────
//
// Reads kPvHopSize stereo frames starting at [h] (wrapping at loop length,
// honoring reverse), interleaves them into pvScratchIn, and pushes them to
// the vocoder with zero output drained. Advances and returns the updated
// playback head.
static inline int32_t _feedPvOneHop(
    ALooperClip& clip, int32_t h, int32_t len, bool reversed)
{
    for (int i = 0; i < kPvHopSize; ++i) {
        float l, r;
        _readClipFrame(clip, h, len, reversed, &l, &r);
        clip.pvScratchIn[i * 2]     = l;
        clip.pvScratchIn[i * 2 + 1] = r;
        h = (h + 1) % len;
    }
    gf_pv_process_block(
        clip.pv, clip.pvScratchIn, kPvHopSize,
        /*output*/nullptr, /*capacity*/0);
    return h;
}

// ── Helper: stretched playback via phase vocoder ───────────────────────────
//
// Fills [blockSize] stereo output samples by alternately draining the
// vocoder and feeding it new input from the clip buffer. Stretch ratio is
// recordBpm/currentBpm so a loop captured at 120 BPM and played at 140 BPM
// comes out shorter (0.857×) without pitch change.
//
// Loop safety bound: each feed adds one synthesis frame to the output ring,
// and each iteration either emits frames or feeds more. A single callback
// never needs more than ~16 iterations even under the coldest-start +
// extreme-stretch case (blockSize=2048, stretch=0.25). The safety counter
// exists so any future bug cannot hang the audio thread.
static void _processPlayingStretched(
    ALooperClip& clip, double currentBpm,
    float* mixL, float* mixR, int blockSize)
{
    const int32_t len = clip.loopLengthFrames;
    if (len == 0) return;
    const float vol = clip.volume.load(std::memory_order_relaxed);
    const bool  rev = clip.reversed.load(std::memory_order_relaxed) != 0;
    int32_t h = clip.head.load(std::memory_order_relaxed);

    // Flush phase accumulators + OLA tail if we just entered PLAYING.
    if (clip.pvNeedsReset.exchange(0, std::memory_order_relaxed) != 0) {
        gf_pv_reset(clip.pv);
    }
    const float ratio = static_cast<float>(clip.recordBpm / currentBpm);
    gf_pv_set_stretch(clip.pv, ratio);

    int emitted = 0;
    int safety  = 64;
    while (emitted < blockSize && safety-- > 0) {
        const int wanted = blockSize - emitted;
        emitted += _drainPvInto(clip, vol, mixL, mixR, emitted, wanted);
        if (emitted >= blockSize) break;
        h = _feedPvOneHop(clip, h, len, rev);
    }
    clip.head.store(h, std::memory_order_relaxed);
}

// ── Helper: record one sample ──────────────────────────────────────────────

static inline int32_t _recordSample(
    ALooperClip& clip, int32_t h,
    const float* srcL, const float* srcR, int i)
{
    clip.dataL[h] = srcL ? srcL[i] : 0.0f;
    clip.dataR[h] = srcR ? srcR[i] : 0.0f;
    return h + 1;
}

/// Write a silence sample at position [h].
static inline int32_t _recordSilence(ALooperClip& clip, int32_t h) {
    clip.dataL[h] = 0.0f;
    clip.dataR[h] = 0.0f;
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
    const double tsNum = static_cast<double>(timeSigNum > 0 ? timeSigNum : 4);
    // The Dart transport starts at positionInBeats = 1.0 (skips past beat 1).
    // This means Dart's bar boundaries are at positions 1, 5, 9, 13, ...
    // (i.e. offset by 1 from the mathematical fmod(pos, timeSig) == 0).
    // We subtract 1 before the fmod check so the C++ bar detection matches
    // the Dart metronome / drum generator bar timing.
    const double barOffset = 1.0;

    for (int c = 0; c < ALOOPER_MAX_CLIPS; ++c) {
        auto& clip = g_clips[c];
        if (!clip.active) continue;

        // Acquire ensures visibility of non-atomic fields (loopLengthBeats,
        // loopLengthFrames, etc.) written before the release store in
        // dvh_alooper_set_state.
        const int32_t st = clip.state.load(std::memory_order_acquire);
        if (st == ALOOPER_IDLE) continue;

        const float* srcL = clipSrcL[c];
        const float* srcR = clipSrcR[c];

        // ── Armed: wait for the next bar downbeat ──────────────────────
        if (st == ALOOPER_ARMED) {
            const bool sync = clip.barSync.load(std::memory_order_relaxed) != 0;

            if (!sync) {
                // Free-form mode: start recording immediately.
                clip.state.store(ALOOPER_RECORDING, std::memory_order_relaxed);
                clip.head.store(0, std::memory_order_relaxed);
                clip.length.store(0, std::memory_order_relaxed);
                clip.loopStartBeat = positionInBeats;
                clip.recordBpm = bpm;
                int32_t h = 0;
                for (int j = 0; j < blockSize && h < clip.capacity; ++j)
                    h = _recordSample(clip, h, srcL, srcR, j);
                clip.head.store(h, std::memory_order_relaxed);
                clip.length.store(h, std::memory_order_relaxed);
                continue;
            }

            // Bar-synced: wait for transport AND a downbeat.
            // If transport hasn't started yet, just keep waiting.
            if (!isPlaying || beatsPerSample <= 0.0) continue;

            for (int i = 0; i < blockSize; ++i) {
                const double beatAtSample = positionInBeats + i * beatsPerSample;
                const double barBeat = std::fmod(beatAtSample - barOffset, tsNum);
                if (barBeat < beatsPerSample || barBeat > (tsNum - beatsPerSample)) {
                    clip.downbeatsSeen++;
                    const int32_t skip = clip.skipBars.load(std::memory_order_relaxed);
                    if (clip.downbeatsSeen <= skip) continue;

                    fprintf(stderr, "[ALOOPER-C] ARMED→RECORDING at beat=%.1f "
                            "(downbeats=%d, skip=%d)\n",
                            beatAtSample, clip.downbeatsSeen, skip);
                    clip.state.store(ALOOPER_RECORDING, std::memory_order_relaxed);
                    clip.head.store(0, std::memory_order_relaxed);
                    clip.length.store(0, std::memory_order_relaxed);
                    clip.loopStartBeat = std::floor((beatAtSample - barOffset) / tsNum) * tsNum + barOffset;
                    clip.recordBpm = bpm;
                    int32_t h = 0;
                    for (int j = i; j < blockSize && h < clip.capacity; ++j)
                        h = _recordSample(clip, h, srcL, srcR, j);
                    clip.head.store(h, std::memory_order_relaxed);
                    clip.length.store(h, std::memory_order_relaxed);
                    break;
                }
            }
            continue;
        }

        // ── Recording: write samples until buffer full ─────────────────
        if (st == ALOOPER_RECORDING) {
            int32_t h = clip.head.load(std::memory_order_relaxed);
            for (int i = 0; i < blockSize; ++i) {
                if (h >= clip.capacity) {
                    clip.loopLengthFrames = h;
                    clip.loopLengthBeats = (bpm > 0.0)
                        ? h / (sampleRate * 60.0 / bpm) : 0.0;
                    clip.length.store(h, std::memory_order_relaxed);
                    clip.pvNeedsReset.store(1, std::memory_order_relaxed);
                    clip.state.store(ALOOPER_PLAYING, std::memory_order_relaxed);
                    clip.head.store(0, std::memory_order_relaxed);
                    goto next_clip;
                }
                h = _recordSample(clip, h, srcL, srcR, i);
            }
            clip.head.store(h, std::memory_order_relaxed);
            clip.length.store(h, std::memory_order_relaxed);
            continue;
        }

        // ── Stopping: keep recording until the next bar downbeat ───────
        // This ensures the loop always ends exactly on a bar boundary.
        // If slightly past a downbeat, trim back. If before, pad with silence.
        if (st == ALOOPER_STOPPING) {
            int32_t h = clip.head.load(std::memory_order_relaxed);

            for (int i = 0; i < blockSize; ++i) {
                if (h >= clip.capacity) break;

                const double beatAtSample = positionInBeats + i * beatsPerSample;
                const double barBeat = std::fmod(beatAtSample - barOffset, tsNum);

                if (barBeat < beatsPerSample || barBeat > (tsNum - beatsPerSample)) {
                    // We hit a bar downbeat — finalize the loop HERE.
                    // The loop length is exactly the frames recorded up to
                    // this sample (which is a bar boundary).
                    clip.loopLengthFrames = h;
                    const double beatsFromStart = beatAtSample - clip.loopStartBeat;
                    clip.loopLengthBeats = std::round(beatsFromStart / tsNum) * tsNum;
                    if (clip.loopLengthBeats < tsNum) clip.loopLengthBeats = tsNum;
                    // Recompute frames from beats for exact alignment.
                    clip.loopLengthFrames = static_cast<int32_t>(
                        clip.loopLengthBeats * 60.0 / bpm * sampleRate + 0.5);
                    // Ensure we don't exceed what we actually recorded.
                    if (clip.loopLengthFrames > h) {
                        // Pad with silence up to the bar boundary.
                        for (int32_t j = h; j < clip.loopLengthFrames && j < clip.capacity; ++j) {
                            clip.dataL[j] = 0.0f;
                            clip.dataR[j] = 0.0f;
                        }
                    }
                    clip.length.store(clip.loopLengthFrames, std::memory_order_relaxed);
                    clip.pvNeedsReset.store(1, std::memory_order_relaxed);
                    clip.state.store(ALOOPER_PLAYING, std::memory_order_relaxed);
                    clip.head.store(0, std::memory_order_relaxed);
                    fprintf(stderr, "[ALOOPER-C] STOPPING→PLAYING at beat=%.1f, "
                            "loop=%.0f beats (%d frames)\n",
                            beatAtSample, clip.loopLengthBeats, clip.loopLengthFrames);
                    goto next_clip;
                }

                // Not at a downbeat yet — keep recording.
                h = _recordSample(clip, h, srcL, srcR, i);
            }
            clip.head.store(h, std::memory_order_relaxed);
            clip.length.store(h, std::memory_order_relaxed);
            continue;
        }

        // ── Playing (bar-aligned wrap, optional tempo-sync stretch) ────
        // Two sub-paths:
        //   1. Fast path (unchanged): loop BPM matches transport BPM, so
        //      we advance one sample per output frame. Zero overhead.
        //   2. Phase-vocoder path: transport BPM differs from recordBpm,
        //      so we run the clip through gf_phase_vocoder to stretch the
        //      playback rate without pitch change.
        if (st == ALOOPER_PLAYING) {
            const int32_t len = clip.loopLengthFrames;
            if (len == 0) continue;

            // Decide whether we need tempo-sync stretching.
            const double recBpm = clip.recordBpm;
            const bool validBpms = (recBpm > 0.0 && bpm > 0.0);
            const float stretch  = validBpms
                ? static_cast<float>(recBpm / bpm) : 1.0f;
            const bool bypass = !validBpms ||
                std::fabs(stretch - 1.0f) < kPvBypassEpsilon;

            if (!bypass && clip.pv != nullptr) {
                _processPlayingStretched(clip, bpm, mixL, mixR, blockSize);
                continue;
            }

            // Fast path: untouched sample-per-sample playback.
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

        // ── Overdubbing (sample-based, single pass) ────────────────────
        // Same sample-by-sample advance as playing.  Auto-returns to
        // PLAYING after one full loop (when head wraps past overdubStartHead).
        if (st == ALOOPER_OVERDUBBING) {
            const int32_t len = clip.loopLengthFrames;
            if (len == 0) continue;
            const float vol = clip.volume.load(std::memory_order_relaxed);
            const bool rev = clip.reversed.load(std::memory_order_relaxed) != 0;
            int32_t h = clip.head.load(std::memory_order_relaxed);
            const int32_t odStart = clip.overdubStartHead;

            for (int i = 0; i < blockSize; ++i) {
                const int32_t ri = rev ? (len - 1 - h) : h;
                const float oldL = clip.dataL[ri];
                const float oldR = clip.dataR[ri];
                mixL[i] += oldL * vol;
                mixR[i] += oldR * vol;
                clip.dataL[ri] = oldL + (srcL ? srcL[i] : 0.0f);
                clip.dataR[ri] = oldR + (srcR ? srcR[i] : 0.0f);

                int32_t prevH = h;
                h = (h + 1) % len;

                // Single-pass check: detect when head wraps past the start.
                // prevH was near the end, h wrapped to near the start.
                if (odStart >= 0 && prevH > len / 2 && h <= odStart + 1) {
                    clip.head.store(h, std::memory_order_relaxed);
                    clip.pvNeedsReset.store(1, std::memory_order_relaxed);
                    clip.state.store(ALOOPER_PLAYING, std::memory_order_relaxed);
                    // Play remaining samples.
                    for (int j = i + 1; j < blockSize; ++j) {
                        const int32_t rri = rev ? (len - 1 - h) : h;
                        mixL[j] += clip.dataL[rri] * vol;
                        mixR[j] += clip.dataR[rri] * vol;
                        h = (h + 1) % len;
                    }
                    clip.head.store(h, std::memory_order_relaxed);
                    goto next_clip;
                }
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

    // Allocate the per-clip phase vocoder and its interleaved scratch
    // buffers. All allocation happens here, on the Dart thread, never on
    // the RT audio thread. If any allocation fails we bail out of the
    // whole create — the half-constructed clip is then cleaned up below.
    clip.pv = gf_pv_create(kPvFftSize, kPvHopSize, 2);
    clip.pvScratchIn  = new float[kPvHopSize * 2]();
    clip.pvScratchOut = new float[kPvOutScratchFrames * 2]();
    clip.pvNeedsReset.store(1, std::memory_order_relaxed);
    if (!clip.pv) {
        delete[] clip.dataL;
        delete[] clip.dataR;
        delete[] clip.pvScratchIn;
        delete[] clip.pvScratchOut;
        clip.dataL = clip.dataR = nullptr;
        clip.pvScratchIn = clip.pvScratchOut = nullptr;
        fprintf(stderr, "[audio_looper] FATAL: gf_pv_create failed for clip %d\n", idx);
        return -1;
    }

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
    clip.loopStartBeat = 0.0;
    clip.loopLengthBeats = 0.0;
    clip.loopLengthFrames = 0;
    clip.overdubStartHead = -1;
    clip.recordBpm = 120.0;
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

    // Phase vocoder teardown. gf_pv_destroy tolerates nullptr.
    gf_pv_destroy(clip.pv);
    clip.pv = nullptr;
    delete[] clip.pvScratchIn;
    delete[] clip.pvScratchOut;
    clip.pvScratchIn = nullptr;
    clip.pvScratchOut = nullptr;

    clip.capacity = 0;
    clip.length.store(0, std::memory_order_relaxed);
    clip.head.store(0, std::memory_order_relaxed);
    fprintf(stderr, "[audio_looper] Destroyed clip %d\n", idx);
}

void dvh_alooper_set_state(DVH_Host /*host*/, int32_t idx, int32_t state) {
    auto* clip = _getClip(idx);
    if (!clip) return;

    // Any external transition into PLAYING resets the phase vocoder so the
    // first block doesn't inherit stale phase/OLA state from a prior session.
    // (Internal RECORDING→PLAYING / STOPPING→PLAYING transitions happen on
    // the RT thread and set this flag there too.)
    if (state == ALOOPER_PLAYING) {
        clip->pvNeedsReset.store(1, std::memory_order_relaxed);
    }

    if (state == ALOOPER_ARMED) {
        clip->head.store(0, std::memory_order_relaxed);
        clip->length.store(0, std::memory_order_relaxed);
        clip->loopLengthBeats = 0.0;
        clip->loopLengthFrames = 0;
        clip->downbeatsSeen = 0;
    }
    // Dart sets PLAYING to stop recording → we transition to STOPPING
    // so the C++ callback can pad silence to the next bar boundary.
    if (state == ALOOPER_PLAYING &&
        clip->state.load(std::memory_order_relaxed) == ALOOPER_RECORDING &&
        clip->barSync.load(std::memory_order_relaxed) != 0) {
        clip->state.store(ALOOPER_STOPPING, std::memory_order_release);
        fprintf(stderr, "[ALOOPER-C] set_state: RECORDING→STOPPING (bar-pad), "
                "head=%d frames\n", clip->head.load(std::memory_order_relaxed));
        return;
    }
    if (state == ALOOPER_PLAYING &&
        clip->state.load(std::memory_order_relaxed) == ALOOPER_RECORDING) {
        // Free-form: finalize immediately.
        int32_t h = clip->head.load(std::memory_order_relaxed);
        clip->loopLengthFrames = h;
        clip->loopLengthBeats = (clip->recordBpm > 0.0)
            ? h / (clip->sampleRate * 60.0 / clip->recordBpm) : 0.0;
        clip->length.store(h, std::memory_order_relaxed);
        clip->head.store(0, std::memory_order_relaxed);
    }
    if (state == ALOOPER_OVERDUBBING) {
        // Record the current head position for single-pass auto-stop.
        clip->overdubStartHead = clip->head.load(std::memory_order_relaxed);
    }
    if (state == ALOOPER_IDLE) {
        // IDLE means "not playing or recording right now" — it is the
        // natural pause state, and a clip with previously-recorded content
        // must survive an IDLE transition so the user can hit Play again
        // and so autosave can persist the PCM. We only reset the playback
        // cursor and the overdub-start marker; the actual audio data and
        // its length are preserved.
        //
        // See dvh_alooper_clear_data for the explicit "erase recorded
        // audio" path — Dart's clear() calls that AFTER going to IDLE.
        clip->head.store(0, std::memory_order_relaxed);
        clip->overdubStartHead = -1;
    }

    clip->state.store(state, std::memory_order_release);
    fprintf(stderr, "[audio_looper] Clip %d state → %d\n", idx, state);
}

/// Erases the recorded PCM data for clip [idx] without changing its state.
///
/// Used by Dart's [AudioLooperEngine.clear] to implement the "wipe this
/// clip but keep the slot" operation. Previously this was conflated with
/// the IDLE state transition — which broke stop/reload because IDLE is
/// also the "paused with content" state and we were zeroing the length
/// out from under an autosave.
///
/// Safe to call at any time; the RT callback reads `length` as an atomic.
DVH_API void dvh_alooper_clear_data(int32_t idx) {
    auto* clip = _getClip(idx);
    if (!clip) return;
    clip->head.store(0, std::memory_order_relaxed);
    clip->length.store(0, std::memory_order_relaxed);
    clip->loopLengthFrames = 0;
    clip->loopLengthBeats = 0.0;
    clip->overdubStartHead = -1;
    clip->pvNeedsReset.store(1, std::memory_order_relaxed);
    fprintf(stderr, "[audio_looper] Clip %d data cleared\n", idx);
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
    g_clips[idx].busSourceCount = 0;
}

void dvh_alooper_add_render_source(int32_t idx, DvhRenderFn fn) {
    if (!fn) return;
    std::lock_guard<std::mutex> lk(g_looperMtx);
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return;
    auto& clip = g_clips[idx];
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
    for (int i = 0; i < clip.pluginSourceCount; ++i)
        if (clip.pluginSources[i] == pluginOrdinalIdx) return;
    if (clip.pluginSourceCount >= ALOOPER_MAX_SOURCES) return;
    clip.pluginSources[clip.pluginSourceCount++] = pluginOrdinalIdx;
}

void dvh_alooper_add_bus_source(int32_t idx, int32_t busSlotId) {
    // Bus slot IDs are non-negative on Android (sfId is 1-based for
    // keyboards, fixed ≥100 for theremin/stylophone). Reject invalid values.
    if (busSlotId < 0) return;
    std::lock_guard<std::mutex> lk(g_looperMtx);
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return;
    auto& clip = g_clips[idx];
    // Dedupe — two cables terminating at the same bus are recorded once.
    for (int i = 0; i < clip.busSourceCount; ++i)
        if (clip.busSources[i] == busSlotId) return;
    if (clip.busSourceCount >= ALOOPER_MAX_SOURCES) return;
    clip.busSources[clip.busSourceCount++] = busSlotId;
}

void dvh_alooper_set_bar_sync(int32_t idx, int32_t enabled) {
    auto* clip = _getClip(idx);
    if (clip) clip->barSync.store(enabled, std::memory_order_relaxed);
}

void dvh_alooper_set_skip_bars(int32_t idx, int32_t bars) {
    auto* clip = _getClip(idx);
    if (clip) clip->skipBars.store(bars, std::memory_order_relaxed);
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

int32_t dvh_alooper_get_bus_source_count(int32_t idx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return 0;
    return g_clips[idx].busSourceCount;
}

int32_t dvh_alooper_get_bus_source(int32_t idx, int32_t srcIdx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS || !g_clips[idx].active) return -1;
    if (srcIdx < 0 || srcIdx >= g_clips[idx].busSourceCount) return -1;
    return g_clips[idx].busSources[srcIdx];
}

int32_t dvh_alooper_is_active(int32_t idx) {
    if (idx < 0 || idx >= ALOOPER_MAX_CLIPS) return 0;
    return g_clips[idx].active ? 1 : 0;
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
    clip->loopLengthFrames = lengthFrames;
    clip->head.store(0, std::memory_order_relaxed);
    fprintf(stderr, "[audio_looper] Loaded %d frames into clip %d\n", lengthFrames, idx);
    return 1;
}

} // extern "C"
