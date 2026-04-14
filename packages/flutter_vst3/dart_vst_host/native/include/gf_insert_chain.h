// ============================================================================
// gf_insert_chain.h — Shared GFPA insert-chain runner used by every native
// audio backend in GrooveForge.
//
// Phase C of the audio routing redesign
// (`docs/dev/AUDIO_ROUTING_REDESIGN.md`). Before this header, every backend
// (JACK on Linux, CoreAudio on macOS, Oboe/AAudio on Android) had its own
// copy of the "run N effects in series over a stereo buffer" loop, each
// using slightly different variable names and scratch-buffer ownership
// conventions. The audio-looper recording regression in v2.13.0 cost us a
// full debugging session because the three copies had drifted: one
// captured the pre-chain signal, the other two captured the post-chain
// signal, and there was no test covering the contract.
//
// This header replaces all three copies with one allocation-free, lock-free,
// inlineable helper that is guaranteed by construction to produce identical
// output on every platform. The callback just fills two scratch buffers and
// calls `gf_ic_run_effects` — everything downstream (insert ping-pong,
// post-chain signal location, bypass handling from the effect itself) is
// centralised.
//
// ## Contract
//
// - **Allocation-free**: no `malloc`, no `std::vector` resize, no RAII
//   destructor surprises.
// - **Lock-free**: the helper never takes a mutex. Callers are responsible
//   for snapshotting the effect list before calling.
// - **Single-threaded entry**: callers must guarantee that no concurrent
//   call touches the same effect handles. Every backend today calls this
//   helper from a single audio thread per backend, and the effects
//   themselves own their own atomics for parameter reads.
// - **Scratch buffer ownership**: the caller allocates `scratchL`/`scratchR`
//   (on the stack or in a pre-sized service buffer) and passes them in.
//   The helper uses them as the ping-pong partner for `liveL`/`liveR`.
// - **Final wet signal location**: after the call returns, the post-chain
//   output lives in `liveL`/`liveR` — **always**, regardless of whether
//   `effectCount` is even or odd. This is the invariant the looper,
//   master-mix, and post-chain capture all rely on.
//
// ## Non-goals
//
// - No cable routing logic. The helper does not know about sources,
//   looper sinks, or master renders. It only runs an ordered list of
//   effects through a single stereo stream.
// - No multi-source fan-in. Callers that want fan-in must sum their
//   sources into `liveL`/`liveR` before calling this helper.
// - No bypass handling at the helper level — individual effect functions
//   are expected to handle their own `atomic<bool> bypassed` flag
//   internally (see `GfpaDspInstance::insertCb` for the canonical
//   implementation). Letting each effect own its bypass avoids a second
//   branch on the hot path.
// ============================================================================

#pragma once

#include <stdint.h>
#include <string.h>  // memcpy

#include "gfpa_dsp.h"  // GfpaInsertFn

#ifdef __cplusplus
extern "C" {
#endif

// ── Data shape ───────────────────────────────────────────────────────────────

/// One entry in a GFPA insert chain, as seen by the shared runner.
/// Bit-identical to the `FlatInsertChain::Effect` struct in
/// `dart_vst_host_jack.cpp` and to the `GfpaInsert` struct in
/// `gfpa_audio_android.cpp` — both callers convert their private shape
/// into this type by copying the two fields before invoking the runner.
typedef struct {
    GfpaInsertFn fn;
    void*        userdata;
} gf_ic_effect_t;

// ── Runner ───────────────────────────────────────────────────────────────────

/// Runs [effectCount] GFPA effects in series over the stereo signal held
/// in [liveL]/[liveR]. After the call returns, the fully-processed wet
/// signal lives in [liveL]/[liveR] unconditionally — the helper uses
/// [scratchL]/[scratchR] as the ping-pong partner and always copies back
/// into the live buffer after each effect.
///
/// Parameters:
///   liveL, liveR       in/out — stereo signal to be processed in place.
///                      On entry: dry (or fan-in-summed) source audio.
///                      On exit : fully processed wet audio, which the
///                      caller then accumulates into the master mix or
///                      copies into a post-chain capture buffer.
///   scratchL, scratchR in/out — caller-owned scratch buffers, at least
///                      [frames] floats long. Contents undefined on
///                      entry and on exit — do not read from them after
///                      the call returns.
///   effects            pointer to an on-stack (or snapshot) array of
///                      [effectCount] entries.
///   effectCount        number of effects to apply. 0 is a valid no-op.
///   frames             number of sample frames in each buffer.
///
/// Contract:
///   * All four buffer pointers must be distinct, non-overlapping
///     memory regions of at least [frames] floats each.
///   * The caller must have snapshotted [effects] off the audio thread
///     if the authoritative chain can be mutated concurrently.
///   * Each effect's `fn` is called exactly once per invocation (no
///     retries, no short-circuit on bypass — that's the effect's job).
///   * Allocation-free: no heap touches anywhere in the call graph of
///     this function. memcpy is the only stdlib call.
///
/// Performance: the cost is `effectCount` DSP calls plus
/// `2 * effectCount` stereo memcpys. At 512 frames per block the memcpy
/// cost is ~4 µs per effect on modern hardware — dwarfed by the DSP
/// itself.
static inline void gf_ic_run_effects(float* liveL, float* liveR,
                                     float* scratchL, float* scratchR,
                                     const gf_ic_effect_t* effects,
                                     int effectCount,
                                     int frames)
{
    if (effectCount <= 0) return;
    const size_t bytes = (size_t)frames * sizeof(float);
    for (int i = 0; i < effectCount; ++i) {
        // Effect reads live, writes scratch, then we copy back into live
        // so the next iteration (and the final wet signal) always lives
        // in liveL/liveR.
        effects[i].fn(liveL, liveR, scratchL, scratchR,
                      (int32_t)frames, effects[i].userdata);
        memcpy(liveL, scratchL, bytes);
        memcpy(liveR, scratchR, bytes);
    }
}

#ifdef __cplusplus
}  // extern "C"
#endif
