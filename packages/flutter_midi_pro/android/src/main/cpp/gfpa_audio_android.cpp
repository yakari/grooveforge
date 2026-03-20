// gfpa_audio_android.cpp — Android GFPA DSP insert chain and FluidSynth callback.
//
// This file wires the GFPA DSP effect chain (reverb, delay, wah, EQ,
// compressor, chorus) into FluidSynth's Oboe audio thread on Android.
//
// Architecture overview:
//   1. FluidSynth creates an Oboe stream with new_fluid_audio_driver2(),
//      passing gfpa_audio_callback as the real-time audio callback.
//   2. Each block: FluidSynth renders its synth mix into out[0] / out[1].
//   3. The callback snapshots the active insert chain under a mutex (outside
//      the tight per-frame loop) and applies each effect in sequence.
//   4. Parameter writes from Dart use std::atomic<float> inside gfpa_dsp.cpp
//      so they never block the Oboe thread.
//
// All processing on the hot path is allocation-free and lock-free (after the
// one-shot snapshot of the insert chain pointer array).

#include "gfpa_audio_android.h"
#include "gfpa_dsp.h"

#include <fluidsynth.h>
#include <android/log.h>

#include <cstring>
#include <mutex>

// ── Android logging macros ────────────────────────────────────────────────────

#define LOG_TAG "GfpaAudioAndroid"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── Constants ─────────────────────────────────────────────────────────────────

/// Maximum number of GFPA effect inserts active simultaneously.
static constexpr int kMaxInserts = 8;

/// Maximum block size (frames) this callback will ever receive from Oboe.
/// Pre-allocated so the audio callback is always allocation-free.
static constexpr int kMaxFrames = 4096;

// ── Insert chain storage ──────────────────────────────────────────────────────

/// One entry in the insert chain: the DSP callback and its opaque userdata.
struct GfpaInsert {
    /// The DSP processing function (never null for active slots).
    GfpaInsertFn fn;
    /// Opaque userdata passed back to fn — equals the GfpaDspHandle.
    void* userdata;
};

/// Active insert chain.  Modified only from the Dart isolate thread via
/// gfpa_android_add/remove_insert.  Read under g_insertsMtx each block.
static GfpaInsert g_inserts[kMaxInserts] = {};

/// Number of valid entries in g_inserts.
static int g_insertCount = 0;

/// Protects g_inserts and g_insertCount.
/// Taken briefly at the top of gfpa_audio_callback to copy the chain,
/// then released before any DSP processing begins.
static std::mutex g_insertsMtx;

// ── Pre-allocated intermediate DSP buffers ────────────────────────────────────

/// Temporary left-channel buffer used to ping-pong between effects.
/// Size matches the Oboe-side Oboe block size ceiling.
static float g_tmpL[kMaxFrames];

/// Temporary right-channel buffer used to ping-pong between effects.
static float g_tmpR[kMaxFrames];

// ── Internal helpers ──────────────────────────────────────────────────────────

/// Apply the snapshot of [count] inserts to the stereo signal in [outL]/[outR].
///
/// Processes the insert chain in sequence.  Uses g_tmpL/g_tmpR as ping-pong
/// scratch buffers so each effect reads from one pair and writes to another,
/// with no intermediate heap allocation.
///
/// [outL], [outR] — in/out stereo buffers (overwritten with processed audio).
/// [inserts]      — snapshot of the active chain (on the stack, not the global).
/// [count]        — number of valid entries in [inserts].
/// [frames]       — number of sample frames to process.
static void applyInsertChain(float* outL, float* outR,
                              const GfpaInsert* inserts, int count,
                              int frames)
{
    // Source buffers for the first effect: the raw FluidSynth output.
    const float* srcL = outL;
    const float* srcR = outR;

    for (int i = 0; i < count; ++i) {
        // Each effect writes into g_tmpL/g_tmpR, reading from srcL/srcR.
        inserts[i].fn(srcL, srcR, g_tmpL, g_tmpR,
                      static_cast<int32_t>(frames), inserts[i].userdata);

        // After the first effect the dry signal in outL/outR has been
        // consumed; subsequent effects read from g_tmpL/g_tmpR.
        // We copy back into outL/outR so the final result always lives there,
        // ready for Oboe to consume.
        std::memcpy(outL, g_tmpL, sizeof(float) * static_cast<size_t>(frames));
        std::memcpy(outR, g_tmpR, sizeof(float) * static_cast<size_t>(frames));

        // Next effect reads from outL/outR (which now holds the previous
        // effect's output).
        srcL = outL;
        srcR = outR;
    }
}

// ── FluidSynth audio callback ─────────────────────────────────────────────────

extern "C" int gfpa_audio_callback(void* data, int len,
                                    int nfx, float* fx[],
                                    int nout, float* out[])
{
    auto* synth = static_cast<fluid_synth_t*>(data);

    // ── 1. Render FluidSynth audio ─────────────────────────────────────────
    //
    // When nfx == 0 FluidSynth has no dedicated FX buffers.  We alias the dry
    // output buffers as FX buffers so that FluidSynth's built-in reverb/chorus
    // mix in alongside the dry signal rather than being discarded.
    if (nfx == 0) {
        // Four FX channels (chorus L/R + reverb L/R) all aliased to the stereo
        // output pair so their output accumulates into the final mix.
        float* fxb[4] = { out[0], out[1], out[0], out[1] };
        fluid_synth_process(synth, len, 4, fxb, nout, out);
    } else {
        fluid_synth_process(synth, len, nfx, fx, nout, out);
    }

    // Guard: we need at least stereo output to apply effects.
    if (nout < 2 || out[0] == nullptr || out[1] == nullptr) return 0;

    // ── 2. Snapshot the insert chain ──────────────────────────────────────
    //
    // We copy the chain under the mutex and release the lock immediately so
    // the DSP processing loop (which may last several milliseconds) never
    // holds it.  Dart-side modifications to g_inserts happen outside the
    // audio callback so this critical section is very short.
    GfpaInsert snapshot[kMaxInserts];
    int snapshotCount = 0;
    {
        std::lock_guard<std::mutex> lock(g_insertsMtx);
        snapshotCount = g_insertCount;
        std::memcpy(snapshot, g_inserts,
                    sizeof(GfpaInsert) * static_cast<size_t>(snapshotCount));
    }

    // ── 3. Apply effects ───────────────────────────────────────────────────
    if (snapshotCount > 0) {
        applyInsertChain(out[0], out[1], snapshot, snapshotCount, len);
    }

    // FLUID_OK — tells FluidSynth the callback consumed the data successfully.
    return 0;
}

// ── Public insert-chain management (called from Dart via FFI) ─────────────────

extern "C" void gfpa_android_add_insert(void* dspHandle)
{
    GfpaInsertFn fn = gfpa_dsp_insert_fn(dspHandle);
    void* ud       = gfpa_dsp_userdata(dspHandle);

    if (fn == nullptr) {
        LOGE("gfpa_android_add_insert: gfpa_dsp_insert_fn returned null");
        return;
    }

    std::lock_guard<std::mutex> lock(g_insertsMtx);

    // Idempotency guard: skip if this userdata is already in the chain.
    for (int i = 0; i < g_insertCount; ++i) {
        if (g_inserts[i].userdata == ud) return;
    }

    if (g_insertCount >= kMaxInserts) {
        LOGE("gfpa_android_add_insert: insert chain full (%d slots)", kMaxInserts);
        return;
    }

    g_inserts[g_insertCount] = { fn, ud };
    ++g_insertCount;
    LOGI("gfpa_android_add_insert: added insert %d", g_insertCount);
}

/// Remove the insert whose userdata matches [dspHandle]'s userdata.
///
/// Shifts remaining entries left so the chain stays contiguous.
/// No-op if the handle is not found.
extern "C" void gfpa_android_remove_insert(void* dspHandle)
{
    void* ud = gfpa_dsp_userdata(dspHandle);

    std::lock_guard<std::mutex> lock(g_insertsMtx);

    int found = -1;
    for (int i = 0; i < g_insertCount; ++i) {
        if (g_inserts[i].userdata == ud) { found = i; break; }
    }

    if (found < 0) return; // not present — no-op

    // Shift later entries left to fill the gap.
    for (int i = found; i < g_insertCount - 1; ++i) {
        g_inserts[i] = g_inserts[i + 1];
    }
    --g_insertCount;
    LOGI("gfpa_android_remove_insert: removed, %d remaining", g_insertCount);
}

/// Remove all active inserts from the chain.
///
/// Called at the start of each syncAudioRouting() rebuild on the Dart side so
/// that stale registrations from the previous configuration are cleared before
/// the new routing connections are applied.
extern "C" void gfpa_android_clear_inserts()
{
    std::lock_guard<std::mutex> lock(g_insertsMtx);
    g_insertCount = 0;
    LOGI("gfpa_android_clear_inserts: chain cleared");
}

/// Forward the current transport BPM to all BPM-synced GFPA effects.
///
/// Wraps gfpa_set_bpm() which stores the value in a global std::atomic<float>
/// shared by the delay, wah, and chorus DSP instances.
extern "C" void gfpa_android_set_bpm(double bpm)
{
    gfpa_set_bpm(bpm);
}
