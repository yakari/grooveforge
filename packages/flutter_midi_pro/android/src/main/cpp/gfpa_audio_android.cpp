// gfpa_audio_android.cpp — Android GFPA DSP per-keyboard insert chains.
//
// Stores up to kMaxBusSlot independent insert chains, one per loaded soundfont
// slot (keyboard).  The chains are keyed by sfId (integer, 1-based) — the
// same integer that flutter_midi_pro's loadSoundfont() JNI call returns to
// Dart and that Dart passes back via gfpa_android_add_insert_for_sf().
//
// Architecture within one audio block (called by oboe_stream_android.cpp):
//   1. FluidSynth renders keyboard A's audio into synthL[0]/synthR[0].
//   2. gfpa_android_apply_chain_for_sf(sfIdA, synthL[0], synthR[0], frames)
//      applies keyboard A's effect chain (e.g. WAH) in-place.
//   3. FluidSynth renders keyboard B's audio into synthL[1]/synthR[1].
//   4. gfpa_android_apply_chain_for_sf(sfIdB, ...) — no effects for B, no-op.
//   5. Both contributions are summed into the master mix by oboe_stream.
//
// This ensures WAH on keyboard A never reaches keyboard B's audio path.
//
// Thread safety:
//   All chain mutations (add/remove/clear) hold g_chainsMtx.
//   gfpa_android_apply_chain_for_sf() snapshots the chain under the same
//   mutex and releases the lock before any DSP processing, so Dart-side
//   mutations never block the audio thread for more than a pointer copy.
//
//   Scratch buffers are stack-allocated in gfpa_android_apply_chain_for_sf
//   so concurrent calls from different audio threads are safe.

#include "gfpa_audio_android.h"
#include "gfpa_dsp.h"

#include <android/log.h>
#include <cstring>
#include <mutex>

// ── Logging macros ────────────────────────────────────────────────────────────

#define LOG_TAG "GfpaAudioAndroid"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── Constants ─────────────────────────────────────────────────────────────────

/// Maximum number of GFPA effect inserts per keyboard slot.
static constexpr int kMaxInserts = 8;

/// Maximum block size (frames) processed per call.
/// Scratch buffers are sized to this ceiling.
static constexpr int kMaxFrames = 4096;

/// Maximum bus slot ID supported.
/// g_sfChains is indexed 0..kMaxBusSlot; index 0 is unused (slot IDs start at 1).
/// Slots 1–4: GF Keyboard (FluidSynth sfId).
/// Slot 5: Theremin.  Slot 6: Stylophone.  Slot 7: Vocoder.
static constexpr int kMaxBusSlot = 8; // leave slot 8 as headroom

// ── Per-keyboard insert chain storage ─────────────────────────────────────────

/// One DSP insert: a processing function pointer and its opaque context.
struct GfpaInsert {
    /// DSP processing callback — never null for an active slot.
    GfpaInsertFn fn;
    /// Opaque pointer passed back to fn; equals the GfpaDspHandle.
    void* userdata;
};

/// One keyboard's complete insert chain.
struct SfInsertChain {
    GfpaInsert inserts[kMaxInserts];
    int count = 0;
};

/// Per-sfId insert chains.  Index 0 is unused; valid sfIds are 1..kMaxBusSlot.
static SfInsertChain g_sfChains[kMaxBusSlot + 1];

/// Protects all of g_sfChains.  Held briefly to copy a chain snapshot.
static std::mutex g_chainsMtx;

// ── Internal helpers ──────────────────────────────────────────────────────────

/// Apply [count] inserts to the stereo signal in [outL]/[outR].
///
/// [tmpL]/[tmpR] are caller-owned scratch buffers (stack-allocated) used for
/// the ping-pong between successive effects.  No heap allocation occurs here.
///
/// [outL], [outR] — in/out stereo buffers (overwritten with final result).
/// [tmpL], [tmpR] — scratch buffers, each at least [frames] floats.
/// [inserts]      — on-stack snapshot of the active chain.
/// [count]        — number of valid entries in [inserts].
/// [frames]       — number of sample frames to process.
static void applyInsertChain(float* outL, float* outR,
                              float* tmpL, float* tmpR,
                              const GfpaInsert* inserts, int count,
                              int frames)
{
    // Start with the raw synth audio as the source for the first effect.
    const float* srcL = outL;
    const float* srcR = outR;

    for (int i = 0; i < count; ++i) {
        // Effect reads from srcL/srcR and writes into tmpL/tmpR.
        // We copy back into outL/outR so the final processed signal always
        // lives there, ready for the caller to accumulate into the master mix.
        inserts[i].fn(srcL, srcR, tmpL, tmpR,
                      static_cast<int32_t>(frames), inserts[i].userdata);

        std::memcpy(outL, tmpL, sizeof(float) * static_cast<size_t>(frames));
        std::memcpy(outR, tmpR, sizeof(float) * static_cast<size_t>(frames));

        srcL = outL;
        srcR = outR;
    }
}

// ── Public API ────────────────────────────────────────────────────────────────

extern "C" void gfpa_android_add_insert_for_sf(int sfId, void* dspHandle)
{
    if (sfId < 1 || sfId > kMaxBusSlot) {
        LOGE("gfpa_android_add_insert_for_sf: sfId %d out of range [1,%d]",
             sfId, kMaxBusSlot);
        return;
    }

    GfpaInsertFn fn = gfpa_dsp_insert_fn(dspHandle);
    void* ud       = gfpa_dsp_userdata(dspHandle);

    if (fn == nullptr) {
        LOGE("gfpa_android_add_insert_for_sf: gfpa_dsp_insert_fn returned null");
        return;
    }

    std::lock_guard<std::mutex> lock(g_chainsMtx);
    SfInsertChain& chain = g_sfChains[sfId];

    // Idempotency: skip if this userdata is already in this chain.
    for (int i = 0; i < chain.count; ++i) {
        if (chain.inserts[i].userdata == ud) return;
    }

    if (chain.count >= kMaxInserts) {
        LOGE("gfpa_android_add_insert_for_sf: sfId %d chain full (%d slots)",
             sfId, kMaxInserts);
        return;
    }

    chain.inserts[chain.count] = { fn, ud };
    ++chain.count;
    LOGI("gfpa_android_add_insert_for_sf: sfId=%d, %d insert(s)",
         sfId, chain.count);
}

extern "C" void gfpa_android_remove_insert(void* dspHandle)
{
    void* ud = gfpa_dsp_userdata(dspHandle);
    std::lock_guard<std::mutex> lock(g_chainsMtx);

    // Search every per-keyboard chain for this handle and remove if found.
    for (int s = 1; s <= kMaxBusSlot; ++s) {
        SfInsertChain& chain = g_sfChains[s];
        int found = -1;
        for (int i = 0; i < chain.count; ++i) {
            if (chain.inserts[i].userdata == ud) { found = i; break; }
        }
        if (found < 0) continue;

        // Shift later entries left to keep the array contiguous.
        for (int i = found; i < chain.count - 1; ++i) {
            chain.inserts[i] = chain.inserts[i + 1];
        }
        --chain.count;
        LOGI("gfpa_android_remove_insert: removed from sfId=%d, %d remaining",
             s, chain.count);
    }
}

extern "C" void gfpa_android_clear_all_inserts(void)
{
    std::lock_guard<std::mutex> lock(g_chainsMtx);
    for (int s = 0; s <= kMaxBusSlot; ++s) {
        g_sfChains[s].count = 0;
    }
    LOGI("gfpa_android_clear_all_inserts: all chains cleared");
}

extern "C" void gfpa_android_apply_chain_for_sf(int sfId,
                                                  float* outL, float* outR,
                                                  int frames)
{
    if (sfId < 1 || sfId > kMaxBusSlot) return;

    // ── Snapshot this keyboard's insert chain ─────────────────────────────
    //
    // Brief lock to copy the chain; released before any DSP work so Dart-side
    // mutations are never blocked by audio processing.
    GfpaInsert snapshot[kMaxInserts];
    int snapshotCount = 0;
    {
        std::lock_guard<std::mutex> lock(g_chainsMtx);
        const SfInsertChain& chain = g_sfChains[sfId];
        snapshotCount = chain.count;
        std::memcpy(snapshot, chain.inserts,
                    sizeof(GfpaInsert) * static_cast<size_t>(snapshotCount));
    }

    if (snapshotCount == 0) return; // No inserts for this keyboard — pass through.

    // ── Apply effects ──────────────────────────────────────────────────────
    //
    // Stack-allocated scratch buffers so concurrent calls from different
    // audio threads (one per FluidSynth/Oboe instance) are safe.
    // Stack cost: 2 × kMaxFrames × 4 bytes = 32 KB per call.
    float tmpL[kMaxFrames];
    float tmpR[kMaxFrames];
    applyInsertChain(outL, outR, tmpL, tmpR, snapshot, snapshotCount, frames);
}

extern "C" void gfpa_android_set_bpm(double bpm)
{
    /// gfpa_set_bpm() stores the value in a std::atomic<float> shared by all
    /// DSP instances.  Safe to call from any thread at any time.
    gfpa_set_bpm(bpm);
}
