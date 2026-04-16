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
#include "gf_insert_chain.h"
#include "oboe_stream_android.h"

#include <android/log.h>
#include <chrono>
#include <cstring>
#include <mutex>
#include <thread>

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
/// Slots 1–N: GF Keyboard (FluidSynth sfId, dynamically assigned).
/// Slots 100–103: Theremin, Stylophone, Vocoder, Live Input
/// (see OBOE_BUS_SLOT_* in oboe_stream_android.h).
///
/// Array size: (kMaxBusSlot + 1) * sizeof(SfInsertChain) ≈ 104 * 140 bytes ≈ 15 KB.
static constexpr int kMaxBusSlot = 103;

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

// ── Shared insert-chain runner ─────────────────────────────────────────────
//
// Phase C of the audio routing redesign unified every backend's
// effect-chain loop into `gf_ic_run_effects` (see
// `dart_vst_host/native/include/gf_insert_chain.h`). The Android
// `applyInsertChain` helper used to live here; it has been deleted in
// favour of a one-line call-site copy from `GfpaInsert[]` into
// `gf_ic_effect_t[]` before invoking the shared runner. All three
// backends (JACK, CoreAudio, Oboe) now use the same helper, which
// guarantees bit-identical effect semantics across platforms.

// ── Public API ────────────────────────────────────────────────────────────────

extern "C" void gfpa_android_remove_insert(void* dspHandle)
{
    void* ud = gfpa_dsp_userdata(dspHandle);

    // ── Step 1: Remove from chains (lock held only for the mutation) ───────
    //
    // IMPORTANT: the lock must be released BEFORE the drain wait below.
    // gfpa_android_apply_chain_for_sf() acquires g_chainsMtx to take its own
    // chain snapshot.  If we kept the lock across the drain wait, the audio
    // callback would deadlock trying to acquire g_chainsMtx, the seq counter
    // would never advance, the 50 ms timeout would fire, we would call
    // gfpa_dsp_destroy while the callback eventually acquires the lock and
    // runs DSP on the freed object → SIGSEGV.
    {
        std::lock_guard<std::mutex> lock(g_chainsMtx);

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
    } // ← g_chainsMtx released here, BEFORE the drain wait

    // ── Step 2: Drain — wait for any in-flight snapshot to retire ─────────
    //
    // After releasing the lock above, any new call to
    // gfpa_android_apply_chain_for_sf() will acquire g_chainsMtx, take a
    // chain snapshot that no longer contains this handle, and proceed safely.
    //
    // A callback that acquired g_chainsMtx BEFORE our removal above may have
    // already snapshotted the old chain (including our handle) and released
    // the lock.  That callback is now running DSP on the snapshot.
    //
    // We wait until g_callbackDoneSeq advances.  The counter increments AFTER
    // all per-source chains are applied (end of audioCallback), so when it
    // advances by at least 1 from our baseline, any such in-flight snapshot
    // has fully retired and the raw DSP pointer is no longer live.
    //
    // With the lock released above the audio thread is never blocked, so this
    // wait completes within one audio burst (typically ~5 ms at 256 frames /
    // 48 kHz) rather than hitting the timeout.  The timeout guards the edge
    // case where the stream is stopped or severely stalled.
    {
        const uint64_t seqBefore = oboe_stream_callback_done_seq();
        const auto deadline =
            std::chrono::steady_clock::now() + std::chrono::milliseconds(500);
        while (oboe_stream_callback_done_seq() <= seqBefore) {
            if (std::chrono::steady_clock::now() >= deadline) {
                LOGI("gfpa_android_remove_insert: drain timeout — proceeding");
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
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

// ── Phase H — atomic chain commit for one bus slot ──────────────────────────
//
// Replaces the entire insert chain for [busSlotId] with a new ordered
// list of DSP handles. Matches the semantics of the desktop
// `dvh_set_master_insert_chain` API: single atomic mutation, no merge
// heuristic, caller guarantees that each DSP handle appears in at
// most one chain across the whole host.
//
// Pattern used by the routing adapter:
//
//     gfpa_android_clear_all_inserts();
//     for each chain in plan.insertChains:
//         gfpa_android_set_chain_for_slot(busSlotId, dspHandles[], count);
//
// The native `SfInsertChain` is a plain fixed-capacity array guarded
// by `g_chainsMtx`, so the commit is a single lock acquisition + copy.
// No drain-wait is needed because the caller has already wiped every
// slot via `gfpa_android_clear_all_inserts`.
extern "C" void gfpa_android_set_chain_for_slot(
    int busSlotId, void* const* dspHandles, int handleCount)
{
    if (busSlotId < 1 || busSlotId > kMaxBusSlot) {
        LOGE("gfpa_android_set_chain_for_slot: busSlotId %d out of range "
             "[1,%d]",
             busSlotId, kMaxBusSlot);
        return;
    }
    if (handleCount < 0) handleCount = 0;
    if (handleCount > 0 && dspHandles == nullptr) return;

    // Cap at the fixed-capacity array size.
    if (handleCount > kMaxInserts) {
        LOGE("gfpa_android_set_chain_for_slot: truncated chain %d→%d "
             "(kMaxInserts)",
             handleCount, kMaxInserts);
        handleCount = kMaxInserts;
    }

    // Resolve each handle to its fn + userdata OUTSIDE the lock so we
    // never call into gfpa_dsp under the chains mutex.
    GfpaInsert staged[kMaxInserts];
    int stagedCount = 0;
    for (int i = 0; i < handleCount; ++i) {
        void* h = dspHandles[i];
        if (h == nullptr) continue;
        GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
        if (fn == nullptr) {
            LOGE("gfpa_android_set_chain_for_slot: gfpa_dsp_insert_fn "
                 "returned null for handle %p",
                 h);
            continue;
        }
        staged[stagedCount++] = {fn, gfpa_dsp_userdata(h)};
    }

    std::lock_guard<std::mutex> lock(g_chainsMtx);
    SfInsertChain& chain = g_sfChains[busSlotId];
    for (int i = 0; i < stagedCount; ++i) {
        chain.inserts[i] = staged[i];
    }
    chain.count = stagedCount;
    LOGI("gfpa_android_set_chain_for_slot: busSlotId=%d, %d insert(s)",
         busSlotId, chain.count);
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
    // Convert GfpaInsert → gf_ic_effect_t (both are `{GfpaInsertFn, void*}`
    // so the copy is a plain two-field assignment per entry) and invoke
    // the shared runner. Allocation-free — the gf_ic_effect_t array lives
    // on the audio-thread stack alongside tmpL/tmpR.
    gf_ic_effect_t effects[kMaxInserts];
    for (int i = 0; i < snapshotCount; ++i) {
        effects[i].fn       = snapshot[i].fn;
        effects[i].userdata = snapshot[i].userdata;
    }
    gf_ic_run_effects(outL, outR, tmpL, tmpR, effects, snapshotCount, frames);
}

extern "C" void gfpa_android_set_bpm(double bpm)
{
    /// gfpa_set_bpm() stores the value in a std::atomic<float> shared by all
    /// DSP instances.  Safe to call from any thread at any time.
    gfpa_set_bpm(bpm);
}
