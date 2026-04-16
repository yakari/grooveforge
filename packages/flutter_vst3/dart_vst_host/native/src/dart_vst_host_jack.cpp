// JACK audio client for dart_vst_host (Linux only).
//
// Architecture: triple-buffered routing snapshots.
//
// The Dart thread (via dvh_add_master_render, dvh_add_master_insert, etc.)
// mutates the "authoritative" routing state under pluginsMtx, then calls
// _publishSnapshot() which copies the state into a flat RoutingSnapshot and
// atomically publishes its index.  The JACK RT callback reads the latest
// published snapshot via an atomic load — zero mutex, zero allocation.
//
// This replaces the former design where the callback copied std::vectors and
// std::unordered_maps under a mutex on every audio frame, which caused heap
// fragmentation, latency spikes, and eventual std::length_error crashes.

#ifdef __linux__

#include "dart_vst_host.h"
#include "dart_vst_host_internal.h"
#include "../include/gfpa_dsp.h"
#include "../include/gf_insert_chain.h"
#include "../include/audio_looper.h"

#include <jack/jack.h>
#include <algorithm>
#include <cmath>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// ── Capacity limits ────────────────────────────────────────────────────────
// These are hard ceilings for pre-allocated flat arrays.  Exceeding them
// silently drops the excess entries (safe, just silent) rather than crashing.

/// Maximum VST3 plugins in the process order.
static constexpr int kMaxPlugins = 32;
/// Maximum audio routes (plugin → plugin).
static constexpr int kMaxRoutes = 32;
/// Maximum external render sources (Theremin, Stylophone, …).
static constexpr int kMaxExtRenders = 16;
/// Maximum master-mix render contributors.
static constexpr int kMaxMasterRenders = 16;
/// Maximum fan-in insert chains.
static constexpr int kMaxInsertChains = 16;
/// Maximum sources per insert chain (fan-in).
static constexpr int kMaxChainSources = 8;
/// Maximum effects per insert chain (series).
static constexpr int kMaxChainEffects = 8;

// ── Flat insert chain (no heap allocation) ─────────────────────────────────

/// Fixed-capacity insert chain stored in the routing snapshot.
/// All arrays are stack-resident — no std::vector, no heap.
struct FlatInsertChain {
    DvhRenderFn sources[kMaxChainSources];
    int sourceCount = 0;
    struct Effect { GfpaInsertFn fn; void* userdata; };
    Effect effects[kMaxChainEffects];
    int effectCount = 0;
};

// ── Routing snapshot (read by JACK callback, written by Dart thread) ───────

/// Complete routing state consumed by the JACK process callback.
/// Every field is fixed-size — no heap allocation, no std::vector, no map.
/// The Dart thread fills this via _publishSnapshot() under pluginsMtx.
struct RoutingSnapshot {
    void* ordered[kMaxPlugins];
    int   orderedCount = 0;

    struct Route { void* from; void* to; };
    Route routes[kMaxRoutes];
    int   routeCount = 0;

    struct ExtRender { void* plugin; DvhRenderFn fn; };
    ExtRender extRenders[kMaxExtRenders];
    int       extRenderCount = 0;

    DvhRenderFn masterRenders[kMaxMasterRenders];
    int         masterRenderCount = 0;

    FlatInsertChain insertChains[kMaxInsertChains];
    int             insertChainCount = 0;
};

// ── Heap-allocated insert chain (used by Dart-side authoritative state) ────

/// Heap-allocated version used on the Dart thread where allocation is fine.
/// Converted to FlatInsertChain when publishing a snapshot.
struct InsertChain {
    std::vector<DvhRenderFn> sources;
    std::vector<std::pair<GfpaInsertFn, void*>> effects;
};

// ── AudioState ─────────────────────────────────────────────────────────────

struct AudioState {
    // ── Authoritative routing state (Dart thread, under pluginsMtx) ────────
    std::vector<void*> plugins;
    std::vector<void*> processOrder;
    std::vector<std::pair<void*, void*>> routes;
    std::vector<std::pair<void*, DvhRenderFn>> externalRenders;
    std::vector<DvhRenderFn> masterRenders;
    std::vector<InsertChain> masterInsertChains;
    std::mutex pluginsMtx;

    // ── Triple-buffered snapshots ──────────────────────────────────────────
    // Index 0, 1, 2: the Dart thread writes to snapshots[writeIdx],
    // then publishes via activeIdx.store().  The callback reads
    // snapshots[activeIdx.load()].  The third buffer is spare.
    RoutingSnapshot snapshots[3];
    std::atomic<int> activeIdx{0};
    int writeIdx = 1;

    // ── Pre-allocated audio scratch buffers ────────────────────────────────
    // All sized to blockSize; resized in _resizeBuffers (non-RT).
    std::vector<float> extBufL, extBufR;
    std::vector<float> insertBufL, insertBufR;
    std::vector<float> tmpBufL, tmpBufR;
    std::vector<float> mixL, mixR;
    std::vector<float> zeroL, zeroR;

    /// Per-clip audio looper source buffers.  Filled by the JACK callback
    /// before dvh_alooper_process: copied from the master render capture
    /// or from pluginBuf (VST3 source).  NULL-initialized each block.
    std::vector<float> alooperSrcL[ALOOPER_MAX_CLIPS];
    std::vector<float> alooperSrcR[ALOOPER_MAX_CLIPS];

    /// Per-master-render capture buffers.  During the bare render pass, each
    /// render function's output is saved here so the audio looper can read it
    /// without calling the function a second time (which would double-render
    /// FluidSynth and cause saturation).
    /// Index matches the masterRenders[] ordinal in the routing snapshot.
    std::vector<float> renderCaptureL[kMaxMasterRenders];
    std::vector<float> renderCaptureR[kMaxMasterRenders];

    /// Per-plugin stereo output buffers: pluginBuf[i*2] = L, [i*2+1] = R.
    std::vector<float> pluginBuf[kMaxPlugins * 2];

    // ── Transport state for audio looper bar-sync ──────────────────────────
    // Updated from dvh_set_transport(); read by dvh_alooper_process().
    std::atomic<double> transportBpm{120.0};
    std::atomic<int32_t> transportTimeSigNum{4};
    std::atomic<int32_t> transportIsPlaying{0};
    std::atomic<double> transportPositionBeats{0.0};

    // ── Output limiter state ───────────────────────────────────────────────
    // Brickwall limiter with smooth gain reduction to prevent speaker damage.
    // Threshold: 0.95 (leaves headroom for DAC reconstruction).
    // Attack: instant (brickwall). Release: ~50ms exponential decay.
    float limiterGain = 1.0f;

    // ── Callback drain counter ─────────────────────────────────────────────
    std::atomic<uint64_t> callbackSeq{0};

    // ── JACK handles ───────────────────────────────────────────────────────
    jack_client_t* jackClient = nullptr;
    jack_port_t* portOutL = nullptr;
    jack_port_t* portOutR = nullptr;
    std::atomic<bool> running{false};
    std::atomic<int32_t> xrunCount{0};
    int32_t sampleRate = 44100;
    int32_t blockSize = 256;
};

// ── Global state map ───────────────────────────────────────────────────────

static std::mutex g_mapMtx;
static std::vector<std::pair<void*, AudioState*>> g_states;

static AudioState* getOrCreate(DVH_Host host) {
    std::lock_guard<std::mutex> lk(g_mapMtx);
    for (auto& kv : g_states)
        if (kv.first == host) return kv.second;
    auto* s = new AudioState();
    g_states.push_back({host, s});
    return s;
}

static AudioState* get(DVH_Host host) {
    std::lock_guard<std::mutex> lk(g_mapMtx);
    for (auto& kv : g_states)
        if (kv.first == host) return kv.second;
    return nullptr;
}

static void removeState(DVH_Host host) {
    std::lock_guard<std::mutex> lk(g_mapMtx);
    for (auto it = g_states.begin(); it != g_states.end(); ++it) {
        if (it->first == host) {
            delete it->second;
            g_states.erase(it);
            return;
        }
    }
}

// ── Snapshot publishing (Dart thread, under pluginsMtx) ────────────────────

/// Copies the authoritative routing state into a flat RoutingSnapshot and
/// atomically publishes it for the JACK callback.  Must be called under
/// pluginsMtx after every routing mutation.
static void _publishSnapshot(AudioState* s) {
    auto& snap = s->snapshots[s->writeIdx];

    // Ordered plugins.
    const auto& src = s->processOrder.empty() ? s->plugins : s->processOrder;
    snap.orderedCount = std::min(static_cast<int>(src.size()), kMaxPlugins);
    for (int i = 0; i < snap.orderedCount; ++i) snap.ordered[i] = src[i];

    // Routes.
    snap.routeCount = std::min(static_cast<int>(s->routes.size()), kMaxRoutes);
    for (int i = 0; i < snap.routeCount; ++i) {
        snap.routes[i] = {s->routes[i].first, s->routes[i].second};
    }

    // External renders.
    snap.extRenderCount = std::min(static_cast<int>(s->externalRenders.size()), kMaxExtRenders);
    for (int i = 0; i < snap.extRenderCount; ++i) {
        snap.extRenders[i] = {s->externalRenders[i].first, s->externalRenders[i].second};
    }

    // Master renders.
    snap.masterRenderCount = std::min(static_cast<int>(s->masterRenders.size()), kMaxMasterRenders);
    for (int i = 0; i < snap.masterRenderCount; ++i) {
        snap.masterRenders[i] = s->masterRenders[i];
    }

    // Insert chains.
    snap.insertChainCount = std::min(static_cast<int>(s->masterInsertChains.size()), kMaxInsertChains);
    for (int i = 0; i < snap.insertChainCount; ++i) {
        auto& dst = snap.insertChains[i];
        const auto& chain = s->masterInsertChains[i];
        dst.sourceCount = std::min(static_cast<int>(chain.sources.size()), kMaxChainSources);
        for (int j = 0; j < dst.sourceCount; ++j) dst.sources[j] = chain.sources[j];
        dst.effectCount = std::min(static_cast<int>(chain.effects.size()), kMaxChainEffects);
        for (int j = 0; j < dst.effectCount; ++j) {
            dst.effects[j] = {chain.effects[j].first, chain.effects[j].second};
        }
    }

    // Atomically publish: the callback will pick this up on the next frame.
    // Memory order: release ensures all writes above are visible before the
    // index becomes visible to the callback's acquire load.
    int published = s->writeIdx;
    // Pick a new writeIdx that is neither the old writeIdx nor the current activeIdx.
    int current = s->activeIdx.load(std::memory_order_relaxed);
    s->activeIdx.store(published, std::memory_order_release);
    // The spare buffer is whichever index is not published and not the old active.
    for (int i = 0; i < 3; ++i) {
        if (i != published && i != current) { s->writeIdx = i; break; }
    }
}

// ── Buffer sizing (non-RT, under pluginsMtx) ──────────────────────────────
//
// The audio callback uses `bs = nframes` as its iteration count, never
// `vector.size()`, so the only correctness requirement is that every
// state vector is at least [bs] floats long.
//
// **Grow only, never shrink.** Past implementations called `.assign(n,
// 0.f)` on every vector every time the JACK buffer size changed. That
// introduced a race: libstdc++'s `assign` goes through an intermediate
// state where `size()` briefly returns the old size, zero, or the new
// size depending on whether the allocator reused the existing storage.
// When the process callback races with `_jackBufferSizeCallback` during
// PipeWire startup (which bounces the block size between 1024 and
// 2048), the callback can observe `size() == 0` and trip the libstdc++
// debug assertion in `operator[]`. Since we never want to reduce the
// vector capacity anyway (the startup path is the only time bs changes
// and it only goes up), growing is the only operation we ever need.
//
// To further eliminate the cold-start window, every state vector is
// pre-sized to [kStartupBuffer] floats in [_ensureBufferFloor] the
// first time this function is called, so a process callback that fires
// before JACK reports the final block size still sees a usable vector.
static constexpr int32_t kStartupBuffer = 8192;

static void _growVector(std::vector<float>& v, int32_t newSize) {
    if (static_cast<int32_t>(v.size()) >= newSize) return;
    v.resize(static_cast<size_t>(newSize), 0.f);
}

static void _resizeBuffers(AudioState* s, int32_t newSize) {
    // Record the logical block size the callback should iterate over.
    // Vectors may be larger than this — that's fine.
    s->blockSize = newSize;

    // Floor at kStartupBuffer so JACK can bump the block size up to
    // 8192 without re-entering this code path. Below that floor we
    // never shrink, so a transient callback overlap cannot observe a
    // shorter-than-expected vector.
    const int32_t target =
        newSize > kStartupBuffer ? newSize : kStartupBuffer;

    _growVector(s->extBufL, target);
    _growVector(s->extBufR, target);
    _growVector(s->insertBufL, target);
    _growVector(s->insertBufR, target);
    _growVector(s->tmpBufL, target);
    _growVector(s->tmpBufR, target);
    _growVector(s->mixL, target);
    _growVector(s->mixR, target);
    _growVector(s->zeroL, target);
    _growVector(s->zeroR, target);
    for (int i = 0; i < ALOOPER_MAX_CLIPS; ++i) {
        _growVector(s->alooperSrcL[i], target);
        _growVector(s->alooperSrcR[i], target);
    }
    for (int i = 0; i < kMaxMasterRenders; ++i) {
        _growVector(s->renderCaptureL[i], target);
        _growVector(s->renderCaptureR[i], target);
    }
    for (int i = 0; i < kMaxPlugins * 2; ++i) {
        _growVector(s->pluginBuf[i], target);
    }
}

// ── JACK process callback (RT thread — zero allocation) ────────────────────

/// Finds the ordinal index of [plugin] in the snapshot's ordered list.
/// Returns -1 if not found.  Linear scan is fine for N < 32.
static int _findPluginIdx(const RoutingSnapshot& snap, void* plugin) {
    for (int i = 0; i < snap.orderedCount; ++i)
        if (snap.ordered[i] == plugin) return i;
    return -1;
}

/// Returns true if [fn] appears as a source in any insert chain.
static bool _isInChain(const RoutingSnapshot& snap, DvhRenderFn fn) {
    for (int c = 0; c < snap.insertChainCount; ++c) {
        const auto& chain = snap.insertChains[c];
        for (int s = 0; s < chain.sourceCount; ++s)
            if (chain.sources[s] == fn) return true;
    }
    return false;
}

static int _jackProcessCallback(jack_nframes_t nframes, void* arg) {
    auto* state = static_cast<AudioState*>(arg);

    auto* outL = static_cast<float*>(jack_port_get_buffer(state->portOutL, nframes));
    auto* outR = static_cast<float*>(jack_port_get_buffer(state->portOutR, nframes));
    const int32_t bs = static_cast<int32_t>(nframes);

    // Guard: if ANY buffer isn't sized for [bs] yet, output silence.
    // The non-RT `_resizeBuffers` path mutates every state buffer under
    // `pluginsMtx`, but JACK/PipeWire can invoke this callback in
    // parallel with the buffer-size callback, so we cannot assume the
    // resize has finished when we enter here. Checking every buffer
    // the chain-processing path actually reads gives us a belt-and-
    // braces safety net that costs ~6 integer comparisons per block —
    // invisible in RT cost, invaluable for the bounds-checked libstdc++
    // build that asserts on `operator[]` out of range.
    const size_t mn = static_cast<size_t>(bs);
    if (state->mixL.size() < mn ||
        state->mixR.size() < mn ||
        state->extBufL.size() < mn ||
        state->extBufR.size() < mn ||
        state->insertBufL.size() < mn ||
        state->insertBufR.size() < mn ||
        state->tmpBufL.size() < mn ||
        state->tmpBufR.size() < mn ||
        state->zeroL.size() < mn ||
        state->zeroR.size() < mn) {
        std::memset(outL, 0, nframes * sizeof(float));
        std::memset(outR, 0, nframes * sizeof(float));
        return 0;
    }

    // Read the latest routing snapshot — single atomic load, no mutex.
    const auto& snap = state->snapshots[state->activeIdx.load(std::memory_order_acquire)];

    // Zero the master mix bus.
    std::fill_n(state->mixL.data(), bs, 0.f);
    std::fill_n(state->mixR.data(), bs, 0.f);

    // ── Process VST3 plugins ───────────────────────────────────────────────
    for (int idx = 0; idx < snap.orderedCount; ++idx) {
        void* p = snap.ordered[idx];

        // Zero per-plugin output buffer.
        float* pOutL = state->pluginBuf[idx * 2].data();
        float* pOutR = state->pluginBuf[idx * 2 + 1].data();
        std::fill_n(pOutL, bs, 0.f);
        std::fill_n(pOutR, bs, 0.f);

        // Determine input: external render > upstream plugin > silence.
        const float* inL = state->zeroL.data();
        const float* inR = state->zeroR.data();

        // Check external render sources.
        for (int e = 0; e < snap.extRenderCount; ++e) {
            if (snap.extRenders[e].plugin == p) {
                snap.extRenders[e].fn(state->extBufL.data(), state->extBufR.data(), bs);
                inL = state->extBufL.data();
                inR = state->extBufR.data();
                break;
            }
        }

        // If no external source, check for upstream VST3 plugin route.
        if (inL == state->zeroL.data()) {
            for (int r = 0; r < snap.routeCount; ++r) {
                if (snap.routes[r].to == p) {
                    int upIdx = _findPluginIdx(snap, snap.routes[r].from);
                    if (upIdx >= 0) {
                        inL = state->pluginBuf[upIdx * 2].data();
                        inR = state->pluginBuf[upIdx * 2 + 1].data();
                    }
                    break;
                }
            }
        }

        dvh_process_stereo_f32(p, inL, inR, pOutL, pOutR, bs);

        // Accumulate to master mix only if no downstream route exists.
        bool hasDownstream = false;
        for (int r = 0; r < snap.routeCount; ++r) {
            if (snap.routes[r].from == p) { hasDownstream = true; break; }
        }
        if (!hasDownstream) {
            for (int i = 0; i < bs; ++i) {
                state->mixL[i] += pOutL[i];
                state->mixR[i] += pOutR[i];
            }
        }
    }

    // ── Fan-in insert chains ───────────────────────────────────────────────
    // Each chain: mix sources (fan-in) → apply effects in series → master mix.
    for (int c = 0; c < snap.insertChainCount; ++c) {
        const auto& chain = snap.insertChains[c];

        // Zero the fan-in accumulation buffer.
        std::fill_n(state->extBufL.data(), bs, 0.f);
        std::fill_n(state->extBufR.data(), bs, 0.f);

        // Render each source into tmpBuf and accumulate.
        for (int s = 0; s < chain.sourceCount; ++s) {
            chain.sources[s](state->tmpBufL.data(), state->tmpBufR.data(), bs);
            for (int i = 0; i < bs; ++i) {
                state->extBufL[i] += state->tmpBufL[i];
                state->extBufR[i] += state->tmpBufR[i];
            }
        }

        // Apply effects in series via the shared helper. The helper uses
        // insertBuf as the ping-pong partner and leaves the final wet
        // signal in extBuf, so the post-chain capture below can read it
        // from the same place unconditionally. See `gf_insert_chain.h`
        // for the contract.
        gf_ic_effect_t chainEffects[kMaxChainEffects];
        for (int e = 0; e < chain.effectCount; ++e) {
            chainEffects[e].fn       = chain.effects[e].fn;
            chainEffects[e].userdata = chain.effects[e].userdata;
        }
        gf_ic_run_effects(
            state->extBufL.data(), state->extBufR.data(),
            state->insertBufL.data(), state->insertBufR.data(),
            chainEffects, chain.effectCount, bs);

        // Save the post-chain (wet) output into renderCapture for every
        // source feeding this chain. The audio looper later pulls from
        // renderCapture[m] keyed by the source render fn — by writing the
        // post-effects buffer here we make the looper record the effect-
        // processed signal (e.g. mic → Harmonizer → Looper records the
        // harmonized audio, not the dry mic).
        //
        // For multi-source fan-in chains, every contributing source ends
        // up pointing at the same mixed wet buffer, which is also the
        // intuitive "what you'd hear on this chain" semantic.
        for (int s = 0; s < chain.sourceCount; ++s) {
            for (int m = 0; m < snap.masterRenderCount && m < kMaxMasterRenders; ++m) {
                if (snap.masterRenders[m] == chain.sources[s]) {
                    std::copy_n(state->extBufL.data(), bs, state->renderCaptureL[m].data());
                    std::copy_n(state->extBufR.data(), bs, state->renderCaptureR[m].data());
                    break;
                }
            }
        }

        // Accumulate to master mix.
        for (int i = 0; i < bs; ++i) {
            state->mixL[i] += state->extBufL[i];
            state->mixR[i] += state->extBufR[i];
        }
    }

    // ── Bare master renders (not in any chain) ─────────────────────────────
    // Each render's output is also saved into renderCapture[m] so the audio
    // looper can read it without re-calling the function (which would double-
    // render FluidSynth and cause saturation).
    for (int m = 0; m < snap.masterRenderCount; ++m) {
        DvhRenderFn fn = snap.masterRenders[m];
        if (_isInChain(snap, fn)) continue;

        fn(state->extBufL.data(), state->extBufR.data(), bs);
        // Save a copy for the audio looper.
        if (m < kMaxMasterRenders) {
            std::copy_n(state->extBufL.data(), bs, state->renderCaptureL[m].data());
            std::copy_n(state->extBufR.data(), bs, state->renderCaptureR[m].data());
        }
        for (int i = 0; i < bs; ++i) {
            state->mixL[i] += state->extBufL[i];
            state->mixR[i] += state->extBufR[i];
        }
    }

    // ── Audio Looper — fill per-clip source buffers ─────────────────────────
    // Each clip may have MULTIPLE sources (keyboards, drums, VST3 plugins all
    // cabled to the same looper).  We mix (sum) all connected sources into the
    // per-clip source buffer.
    //
    // For render function sources (keyboard, theremin, etc.): we read from
    // renderCapture[m] which was already filled during the master render /
    // insert chain passes above — never re-call the function (double-render).
    //
    // For VST3 plugin sources: read from pluginBuf[ordinal].
    const float* aloopSrcL[ALOOPER_MAX_CLIPS] = {};
    const float* aloopSrcR[ALOOPER_MAX_CLIPS] = {};
    for (int c = 0; c < ALOOPER_MAX_CLIPS; ++c) {
        if (!dvh_alooper_is_active(c)) continue;

        const int nRender = dvh_alooper_get_render_source_count(c);
        const int nPlugin = dvh_alooper_get_plugin_source_count(c);
        if (nRender == 0 && nPlugin == 0) continue; // no sources → silence

        // Zero the per-clip accumulation buffer.
        std::fill_n(state->alooperSrcL[c].data(), bs, 0.f);
        std::fill_n(state->alooperSrcR[c].data(), bs, 0.f);

        // Sum all render function sources from their pre-captured buffers.
        for (int s = 0; s < nRender; ++s) {
            DvhRenderFn fn = dvh_alooper_get_render_source(c, s);
            if (!fn) continue;
            // Find the matching renderCapture buffer.
            for (int m = 0; m < snap.masterRenderCount && m < kMaxMasterRenders; ++m) {
                if (snap.masterRenders[m] == fn) {
                    for (int i = 0; i < bs; ++i) {
                        state->alooperSrcL[c][i] += state->renderCaptureL[m][i];
                        state->alooperSrcR[c][i] += state->renderCaptureR[m][i];
                    }
                    break;
                }
            }
        }

        // Sum all VST3 plugin sources from their per-plugin output buffers.
        for (int s = 0; s < nPlugin; ++s) {
            const int plugIdx = dvh_alooper_get_plugin_source(c, s);
            if (plugIdx < 0 || plugIdx >= snap.orderedCount) continue;
            const float* pL = state->pluginBuf[plugIdx * 2].data();
            const float* pR = state->pluginBuf[plugIdx * 2 + 1].data();
            for (int i = 0; i < bs; ++i) {
                state->alooperSrcL[c][i] += pL[i];
                state->alooperSrcR[c][i] += pR[i];
            }
        }

        aloopSrcL[c] = state->alooperSrcL[c].data();
        aloopSrcR[c] = state->alooperSrcR[c].data();
    }

    // Process all active looper clips.
    dvh_alooper_process(
        aloopSrcL, aloopSrcR,
        state->mixL.data(), state->mixR.data(),
        bs,
        state->transportBpm.load(std::memory_order_relaxed),
        state->transportTimeSigNum.load(std::memory_order_relaxed),
        state->sampleRate,
        state->transportIsPlaying.load(std::memory_order_relaxed) != 0,
        state->transportPositionBeats.load(std::memory_order_relaxed));

    // Signal block completion for drain synchronization.
    state->callbackSeq.fetch_add(1, std::memory_order_release);

    // ── Output limiter — speaker protection ────────────────────────────────
    // Brickwall limiter that smoothly reduces gain when peaks exceed the
    // threshold.  Prevents the hard-clipped square waves that destroy
    // laptop speakers.
    //
    // - Threshold: 0.95 (leaves headroom for DAC inter-sample peaks).
    // - Attack: instant — gain is reduced within the same sample.
    // - Release: ~50ms exponential decay back to unity (1.0).
    //
    // This runs per-sample after all mixing is complete, just before the
    // JACK output.  The limiter gain state persists across blocks.
    {
        constexpr float threshold = 0.95f;
        // Release coefficient: at 48kHz, 0.9999 ≈ 50ms to recover from
        // -6dB reduction.  Slower release = smoother but more audible pumping.
        const float releaseCoeff = 1.0f - (1.0f / (0.050f * state->sampleRate));
        float g = state->limiterGain;

        for (int i = 0; i < bs; ++i) {
            const float l = state->mixL[i];
            const float r = state->mixR[i];
            // Find the peak of this sample (stereo).
            const float peak = std::max(std::abs(l), std::abs(r));

            if (peak * g > threshold) {
                // Instant attack: set gain so peak * g == threshold.
                g = threshold / peak;
            } else {
                // Exponential release back towards 1.0.
                g = g * releaseCoeff + (1.0f - releaseCoeff);
                if (g > 1.0f) g = 1.0f;
            }

            outL[i] = l * g;
            outR[i] = r * g;
        }
        state->limiterGain = g;
    }

    return 0;
}

// ── JACK non-RT callbacks ──────────────────────────────────────────────────

static int _jackBufferSizeCallback(jack_nframes_t nframes, void* arg) {
    auto* state = static_cast<AudioState*>(arg);
    fprintf(stderr, "[dart_vst_host] JACK buffer size changed to %u\n",
            (unsigned)nframes);
    std::lock_guard<std::mutex> lk(state->pluginsMtx);
    _resizeBuffers(state, static_cast<int32_t>(nframes));
    return 0;
}

static int _jackXrunCallback(void* arg) {
    auto* state = static_cast<AudioState*>(arg);
    state->xrunCount.fetch_add(1, std::memory_order_relaxed);
    return 0;
}

static void _jackShutdownCallback(void* arg) {
    auto* state = static_cast<AudioState*>(arg);
    fprintf(stderr, "[dart_vst_host] JACK server shut down\n");
    state->running.store(false);
}

// ── Transport broadcast (called from dart_vst_host.cpp) ─────────────────────

void dvh_jack_update_transport(double bpm, int32_t timeSigNum,
                                int32_t isPlaying, double positionInBeats) {
    std::lock_guard<std::mutex> lk(g_mapMtx);
    for (auto& kv : g_states) {
        auto* s = kv.second;
        s->transportBpm.store(bpm, std::memory_order_relaxed);
        s->transportTimeSigNum.store(timeSigNum, std::memory_order_relaxed);
        s->transportIsPlaying.store(isPlaying, std::memory_order_relaxed);
        s->transportPositionBeats.store(positionInBeats, std::memory_order_relaxed);
    }
}

// ── C API — Dart-side routing mutations ────────────────────────────────────
//
// Every mutation acquires pluginsMtx, modifies the authoritative state,
// then calls _publishSnapshot() to make the change visible to the callback.

extern "C" {

DVH_API void dvh_audio_add_plugin(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.push_back(plugin);
    _publishSnapshot(s);
    fprintf(stderr, "[dart_vst_host] Plugin added to audio loop (total=%zu)\n", s->plugins.size());
}

DVH_API void dvh_audio_remove_plugin(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.erase(std::remove(s->plugins.begin(), s->plugins.end(), plugin), s->plugins.end());
    s->processOrder.erase(std::remove(s->processOrder.begin(), s->processOrder.end(), plugin), s->processOrder.end());
    // Remove routes involving this plugin.
    s->routes.erase(
        std::remove_if(s->routes.begin(), s->routes.end(),
            [plugin](const auto& r) { return r.first == plugin || r.second == plugin; }),
        s->routes.end());
    _publishSnapshot(s);
    fprintf(stderr, "[dart_vst_host] Plugin removed from audio loop (total=%zu)\n", s->plugins.size());
}

DVH_API void dvh_audio_clear_plugins(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.clear();
    s->processOrder.clear();
    s->routes.clear();
    _publishSnapshot(s);
    fprintf(stderr, "[dart_vst_host] Audio loop cleared\n");
}

DVH_API void dvh_set_processing_order(DVH_Host host, const DVH_Plugin* order, int32_t count) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    if (!order || count <= 0) {
        s->processOrder.clear();
    } else {
        s->processOrder.assign(order, order + count);
    }
    _publishSnapshot(s);
}

DVH_API void dvh_route_audio(DVH_Host host, DVH_Plugin from, DVH_Plugin to) {
    if (!host || !from || !to) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    // Update or add.
    for (auto& r : s->routes) {
        if (r.first == from) { r.second = to; _publishSnapshot(s); return; }
    }
    s->routes.push_back({from, to});
    _publishSnapshot(s);
}

DVH_API void dvh_clear_routes(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->routes.clear();
    _publishSnapshot(s);
}

DVH_API void dvh_set_external_render(DVH_Host host, DVH_Plugin plugin, DvhRenderFn fn) {
    if (!host || !plugin || !fn) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    for (auto& er : s->externalRenders) {
        if (er.first == plugin) { er.second = fn; _publishSnapshot(s); return; }
    }
    s->externalRenders.push_back({plugin, fn});
    _publishSnapshot(s);
}

DVH_API void dvh_clear_external_render(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->externalRenders.erase(
        std::remove_if(s->externalRenders.begin(), s->externalRenders.end(),
            [plugin](const auto& er) { return er.first == plugin; }),
        s->externalRenders.end());
    _publishSnapshot(s);
}

DVH_API void dvh_add_master_render(DVH_Host host, DvhRenderFn fn) {
    if (!host || !fn) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    for (auto existing : s->masterRenders)
        if (existing == fn) return;
    s->masterRenders.push_back(fn);
    _publishSnapshot(s);
    fprintf(stderr, "[dart_vst_host] Master render added (total=%zu)\n",
            s->masterRenders.size());
}

DVH_API void dvh_remove_master_render(DVH_Host host, DvhRenderFn fn) {
    if (!host || !fn) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterRenders.erase(
        std::remove(s->masterRenders.begin(), s->masterRenders.end(), fn),
        s->masterRenders.end());
    _publishSnapshot(s);
    fprintf(stderr, "[dart_vst_host] Master render removed (total=%zu)\n",
            s->masterRenders.size());
}

// ── Phase H — atomic chain commit (dvh_set_master_insert_chain) ────────────
//
// Appends a single complete chain to `masterInsertChains` in one shot.
// No merge heuristic runs: the caller (the Dart plan builder) has
// already guaranteed that each `effectUserdatas[i]` is unique across
// chains, so there is nothing to merge. Callers use this in the usual
// `clear + rebuild` pattern:
//
//     dvh_clear_master_inserts(host);
//     for each chain:
//         dvh_set_master_insert_chain(host, ...);
//
// Any attempt to commit a chain that would overflow the snapshot's
// fixed-capacity arrays is truncated to the allowed count and logged
// once per call.
DVH_API void dvh_set_master_insert_chain(
    DVH_Host host,
    const DvhRenderFn* sources, int32_t sourceCount,
    const GfpaInsertFn_fwd* effects,
    void* const* effectUserdatas,
    int32_t effectCount)
{
    if (!host || !sources || sourceCount <= 0) return;
    if (effectCount < 0) effectCount = 0;
    if (effectCount > 0 && (!effects || !effectUserdatas)) return;

    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);

    InsertChain chain;
    const int32_t srcLimit = std::min<int32_t>(sourceCount, kMaxChainSources);
    if (srcLimit < sourceCount) {
        fprintf(stderr,
                "[dart_vst_host] dvh_set_master_insert_chain: truncated "
                "sources %d→%d (kMaxChainSources)\n",
                sourceCount, srcLimit);
    }
    for (int32_t i = 0; i < srcLimit; ++i) {
        if (!sources[i]) continue;
        chain.sources.push_back(sources[i]);
    }
    if (chain.sources.empty()) return;

    const int32_t fxLimit = std::min<int32_t>(effectCount, kMaxChainEffects);
    if (fxLimit < effectCount) {
        fprintf(stderr,
                "[dart_vst_host] dvh_set_master_insert_chain: truncated "
                "effects %d→%d (kMaxChainEffects)\n",
                effectCount, fxLimit);
    }
    for (int32_t i = 0; i < fxLimit; ++i) {
        if (!effects[i]) continue;
        chain.effects.emplace_back(
            reinterpret_cast<GfpaInsertFn>(effects[i]),
            effectUserdatas[i]);
    }

    // Snapshot counts BEFORE moving the chain in, since we can't read
    // from the moved-from object after push_back.
    const size_t committedSources = chain.sources.size();
    const size_t committedEffects = chain.effects.size();
    s->masterInsertChains.push_back(std::move(chain));
    fprintf(stderr,
            "[dart_vst_host] set_master_insert_chain: sources=%zu effects=%zu "
            "(total chains=%zu)\n",
            committedSources, committedEffects,
            s->masterInsertChains.size());
    _publishSnapshot(s);
}

DVH_API void dvh_remove_master_insert(DVH_Host host, DvhRenderFn source) {
    if (!host || !source) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    for (auto& chain : s->masterInsertChains) {
        chain.sources.erase(
            std::remove(chain.sources.begin(), chain.sources.end(), source),
            chain.sources.end());
    }
    s->masterInsertChains.erase(
        std::remove_if(s->masterInsertChains.begin(), s->masterInsertChains.end(),
            [](const InsertChain& c) { return c.sources.empty(); }),
        s->masterInsertChains.end());
    _publishSnapshot(s);
    fprintf(stderr, "[dart_vst_host] Master insert removed for source %p\n", (void*)source);
}

DVH_API void dvh_remove_master_insert_by_handle(DVH_Host host, void* dspHandle) {
    if (!host || !dspHandle) return;
    auto* s = get(host);
    if (!s) return;
    void* const ud = gfpa_dsp_userdata(dspHandle);
    bool removed = false;
    {
        std::lock_guard<std::mutex> lk(s->pluginsMtx);
        for (auto& chain : s->masterInsertChains) {
            auto it = std::remove_if(chain.effects.begin(), chain.effects.end(),
                [ud](const std::pair<GfpaInsertFn, void*>& ins) {
                    return ins.second == ud;
                });
            if (it != chain.effects.end()) {
                chain.effects.erase(it, chain.effects.end());
                removed = true;
            }
        }
        s->masterInsertChains.erase(
            std::remove_if(s->masterInsertChains.begin(), s->masterInsertChains.end(),
                [](const InsertChain& c) { return c.effects.empty(); }),
            s->masterInsertChains.end());
        if (removed) _publishSnapshot(s);
    }
    if (!removed) return;

    // Drain: wait for the callback to complete at least one full block after
    // the snapshot was published, ensuring any in-flight reference to this DSP
    // pointer has retired.
    const uint64_t seqBefore = s->callbackSeq.load(std::memory_order_acquire);
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(500);
    while (s->callbackSeq.load(std::memory_order_acquire) <= seqBefore) {
        if (std::chrono::steady_clock::now() >= deadline) {
            fprintf(stderr, "[dart_vst_host] dvh_remove_master_insert_by_handle: "
                    "drain timeout for handle %p\n", dspHandle);
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    fprintf(stderr, "[dart_vst_host] dvh_remove_master_insert_by_handle: "
            "drained OK for handle %p\n", dspHandle);
}

DVH_API void dvh_clear_master_inserts(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterInsertChains.clear();
    _publishSnapshot(s);
    fprintf(stderr, "[dart_vst_host] Master inserts cleared\n");
}

DVH_API void dvh_clear_master_renders(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterRenders.clear();
    _publishSnapshot(s);
    fprintf(stderr, "[dart_vst_host] Master renders cleared\n");
}

// ── JACK client lifecycle ──────────────────────────────────────────────────

DVH_API int32_t dvh_start_jack_client(DVH_Host host, const char* client_name) {
    if (!host) return 0;
    auto* s = getOrCreate(host);
    if (s->running.load()) {
        fprintf(stderr, "[dart_vst_host] JACK client already running\n");
        return 1;
    }

    const char* name = (client_name && client_name[0]) ? client_name : "GrooveForge";
    fprintf(stderr, "[dart_vst_host] Opening JACK client: %s\n", name);

    jack_status_t status;
    s->jackClient = jack_client_open(name, JackNoStartServer, &status);
    if (!s->jackClient) {
        fprintf(stderr, "[dart_vst_host] JACK client_open failed (status=0x%x). "
                "Is a JACK server (PipeWire or JACK2) running?\n", status);
        return 0;
    }

    s->sampleRate = static_cast<int32_t>(jack_get_sample_rate(s->jackClient));
    s->blockSize  = static_cast<int32_t>(jack_get_buffer_size(s->jackClient));
    fprintf(stderr, "[dart_vst_host] JACK server: sr=%d bs=%d\n",
            s->sampleRate, s->blockSize);

    _resizeBuffers(s, s->blockSize);

    // Publish an initial snapshot so the callback has valid data immediately.
    {
        std::lock_guard<std::mutex> lk(s->pluginsMtx);
        _publishSnapshot(s);
    }

    jack_set_process_callback(s->jackClient, _jackProcessCallback, s);
    jack_set_buffer_size_callback(s->jackClient, _jackBufferSizeCallback, s);
    jack_set_xrun_callback(s->jackClient, _jackXrunCallback, s);
    jack_on_shutdown(s->jackClient, _jackShutdownCallback, s);

    s->portOutL = jack_port_register(s->jackClient, "out_L",
                                     JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    s->portOutR = jack_port_register(s->jackClient, "out_R",
                                     JACK_DEFAULT_AUDIO_TYPE, JackPortIsOutput, 0);
    if (!s->portOutL || !s->portOutR) {
        fprintf(stderr, "[dart_vst_host] JACK port registration failed\n");
        jack_client_close(s->jackClient);
        s->jackClient = nullptr;
        return 0;
    }

    if (jack_activate(s->jackClient) != 0) {
        fprintf(stderr, "[dart_vst_host] JACK activate failed\n");
        jack_client_close(s->jackClient);
        s->jackClient = nullptr;
        return 0;
    }

    s->running.store(true);
    s->xrunCount.store(0);

    // Auto-connect to system playback ports.
    const char* clientPort = jack_port_name(s->portOutL);
    if (jack_connect(s->jackClient, clientPort, "system:playback_1") != 0) {
        fprintf(stderr, "[dart_vst_host] Auto-connect out_L → system:playback_1 failed "
                "(non-fatal — connect manually)\n");
    }
    clientPort = jack_port_name(s->portOutR);
    if (jack_connect(s->jackClient, clientPort, "system:playback_2") != 0) {
        fprintf(stderr, "[dart_vst_host] Auto-connect out_R → system:playback_2 failed "
                "(non-fatal — connect manually)\n");
    }

    fprintf(stderr, "[dart_vst_host] JACK client activated OK (sr=%d bs=%d)\n",
            s->sampleRate, s->blockSize);
    return 1;
}

DVH_API void dvh_stop_jack_client(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    fprintf(stderr, "[dart_vst_host] Stopping JACK client…\n");
    s->running.store(false);
    if (s->jackClient) {
        jack_deactivate(s->jackClient);
        jack_client_close(s->jackClient);
        s->jackClient = nullptr;
    }
    removeState(host);
}

DVH_API int32_t dvh_jack_get_xrun_count(DVH_Host host) {
    if (!host) return 0;
    auto* s = get(host);
    if (!s) return 0;
    return s->xrunCount.load(std::memory_order_relaxed);
}

} // extern "C"

#endif // __linux__
