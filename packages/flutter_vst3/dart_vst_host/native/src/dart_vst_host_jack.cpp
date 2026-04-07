// JACK audio client for dart_vst_host (Linux only).
//
// Provides dvh_start_jack_client / dvh_stop_jack_client which drive all
// registered VST3 plugins inside a JACK process callback.  Plugins are
// mixed and written to JACK output ports as native float (no int16
// conversion — JACK uses 32-bit float natively).
//
// Replaces the former ALSA backend (dart_vst_host_alsa.cpp) to gain:
//   - Sub-10 ms latency (vs ~50 ms with ALSA dmix)
//   - Inter-application audio routing via PipeWire / JACK
//   - Proper port naming and session management
//   - Compatibility with both PipeWire (JACK shim) and native JACK2
//
// Phase 5.4 — audio graph execution:
//   dvh_set_processing_order  — override plugin processing order (topological)
//   dvh_route_audio            — route one plugin's output to another's input
//   dvh_clear_routes           — restore direct-to-master-mix routing

#ifdef __linux__

#include "dart_vst_host.h"
#include "dart_vst_host_internal.h"
#include "../include/gfpa_dsp.h"

#include <jack/jack.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

/// One fan-in effect chain: one or more source render functions whose audio
/// is mixed together and then passed through a series of GFPA DSP inserts.
///
/// Example topology — KB2 → WAH → Reverb, Theremin → WAH → Reverb:
///   sources = [kb2RenderFn, thereminRenderFn]
///   effects = [(wahInsertFn, wahPtr), (reverbInsertFn, reverbPtr)]
///
/// The audio callback mixes all sources first (fan-in), then runs effects in
/// series on the combined signal.  Each DSP is therefore called exactly once
/// per block regardless of how many sources feed into it.
struct InsertChain {
    /// Render functions whose audio is mixed (fan-in) before the effect chain.
    std::vector<DvhRenderFn> sources;
    /// Effects in processing order: sources → [0] → [1] → … → master mix.
    std::vector<std::pair<GfpaInsertFn, void*>> effects;
};

struct AudioState {
    std::vector<void*> plugins;
    /// Topological processing order set by dvh_set_processing_order().
    /// Empty means "use plugins insertion order".
    std::vector<void*> processOrder;
    /// Audio routing table: fromPlugin → toPlugin.
    /// When a route exists for plugin P, P's output feeds into the
    /// destination plugin's input rather than the master mix bus.
    std::unordered_map<void*, void*> routes;
    /// External audio sources: destPlugin → render function.
    /// When registered, the JACK callback calls the function instead of using
    /// silence or an upstream VST3 output as the plugin's audio input.
    /// Used to route non-VST3 generators (Theremin, Stylophone) into effects.
    std::unordered_map<void*, DvhRenderFn> externalRenders;
    /// Master-mix contributors: ALL active non-VST3 render functions.
    /// Sources that belong to an InsertChain are skipped in the bare-render
    /// loop — the chain's own fan-in loop renders them instead.
    std::vector<DvhRenderFn> masterRenders;
    /// Fan-in insert chains.  Multiple sources feeding the same first effect
    /// are merged into one chain so each DSP runs exactly once per block.
    std::vector<InsertChain> masterInsertChains;
    /// Pre-allocated stereo buffer for external render calls — no heap
    /// allocation on the audio thread.
    std::vector<float> extBufL;
    std::vector<float> extBufR;
    /// Pre-allocated intermediate buffers for insert chain processing.
    /// The insert reads from extBuf and writes here, then we accumulate to mix.
    std::vector<float> insertBufL;
    std::vector<float> insertBufR;
    /// Pre-allocated temporary buffer for fan-in source mixing — each source
    /// renders into tmpBuf and it is accumulated into extBuf before the chain.
    std::vector<float> tmpBufL;
    std::vector<float> tmpBufR;
    /// Pre-allocated mix bus buffers used inside the JACK process callback.
    /// Sized to blockSize; resized in the buffer-size callback.
    std::vector<float> mixL;
    std::vector<float> mixR;
    /// Zero buffer (silence) used as default input for plugins with no source.
    std::vector<float> zeroL;
    std::vector<float> zeroR;
    std::mutex          pluginsMtx;
    /// Monotonically increasing counter incremented at the end of every audio
    /// block, after all DSP processing is complete.  dvh_remove_master_insert_by_handle
    /// spin-waits on this to drain any in-flight callback snapshot before the
    /// caller destroys the DSP object, preventing use-after-free crashes.
    std::atomic<uint64_t> callbackSeq{0};

    /// JACK client handle — owned by this AudioState.
    jack_client_t*      jackClient{nullptr};
    /// Registered JACK output ports (stereo pair).
    jack_port_t*        portOutL{nullptr};
    jack_port_t*        portOutR{nullptr};

    std::atomic<bool>   running{false};
    /// Cumulative XRUN count reported by the JACK server.
    std::atomic<int32_t> xrunCount{0};

    int32_t sampleRate{44100};
    int32_t blockSize{256};
};

static std::mutex           g_mapMtx;
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

// ── VST3 plugin processing with audio graph routing ─────────────────────────
//
// Process [ordered] plugins using [routes] for VST3→VST3 routing and
// [extRenders] for non-VST3 → VST3 injection (e.g. Theremin → Reverb).
//
// Input priority for each plugin:
//   1. External render function (non-VST3 source, e.g. Theremin DSP)
//   2. Upstream VST3 plugin output (dvh_route_audio connection)
//   3. Silence (zero buffer) — default when no source is wired
static void _processPlugins(
    const std::vector<void*>& ordered,
    const std::unordered_map<void*, void*>& routes,
    const std::unordered_map<void*, DvhRenderFn>& extRenders,
    std::unordered_map<void*, std::pair<std::vector<float>, std::vector<float>>>& bufs,
    int32_t blockSize,
    const std::vector<float>& zeroL,
    const std::vector<float>& zeroR,
    std::vector<float>& mixL,
    std::vector<float>& mixR,
    std::vector<float>& extBufL,
    std::vector<float>& extBufR)
{
    for (void* p : ordered) {
        const float* inL;
        const float* inR;

        auto extIt = extRenders.find(p);
        if (extIt != extRenders.end()) {
            // External non-VST3 source (Theremin, Stylophone, …).
            // Call the registered render fn to fill the pre-allocated buffers.
            extIt->second(extBufL.data(), extBufR.data(), blockSize);
            inL = extBufL.data();
            inR = extBufR.data();
        } else {
            // Reverse-lookup: find the upstream VST3 plugin that feeds into p.
            void* upstream = nullptr;
            for (const auto& r : routes)
                if (r.second == p) { upstream = r.first; break; }

            inL = upstream ? bufs.at(upstream).first.data()  : zeroL.data();
            inR = upstream ? bufs.at(upstream).second.data() : zeroR.data();
        }

        auto& out = bufs[p];
        dvh_process_stereo_f32(p, inL, inR, out.first.data(), out.second.data(), blockSize);

        // Accumulate to master mix only when no downstream plugin consumes this output.
        if (routes.count(p) == 0) {
            for (int i = 0; i < blockSize; ++i) {
                mixL[i] += out.first[i];
                mixR[i] += out.second[i];
            }
        }
    }
}

/// Resize all pre-allocated scratch buffers to match [newSize].
/// Called from the JACK buffer-size callback (non-RT thread) and during
/// initial setup.
static void _resizeBuffers(AudioState* s, int32_t newSize) {
    s->blockSize = newSize;
    s->extBufL.assign(newSize, 0.f);
    s->extBufR.assign(newSize, 0.f);
    s->insertBufL.assign(newSize, 0.f);
    s->insertBufR.assign(newSize, 0.f);
    s->tmpBufL.assign(newSize, 0.f);
    s->tmpBufR.assign(newSize, 0.f);
    s->mixL.assign(newSize, 0.f);
    s->mixR.assign(newSize, 0.f);
    s->zeroL.assign(newSize, 0.f);
    s->zeroR.assign(newSize, 0.f);
}

// ── JACK callbacks ──────────────────────────────────────────────────────────

/// JACK process callback — called from the real-time audio thread.
///
/// This function must be allocation-free, lock-free (except the snapshot
/// mutex which is held very briefly), and must not perform any I/O or
/// syscalls.  JACK enforces real-time safety by contract.
static int _jackProcessCallback(jack_nframes_t nframes, void* arg) {
    auto* state = static_cast<AudioState*>(arg);

    // Get the JACK port output buffers — these are float arrays of nframes.
    auto* outL = static_cast<float*>(jack_port_get_buffer(state->portOutL, nframes));
    auto* outR = static_cast<float*>(jack_port_get_buffer(state->portOutR, nframes));

    const int32_t blockSize = static_cast<int32_t>(nframes);

    // If the buffer size changed between the buffer-size callback and this
    // process call, output silence to avoid buffer overruns.
    if (blockSize > static_cast<int32_t>(state->mixL.size())) {
        std::memset(outL, 0, nframes * sizeof(float));
        std::memset(outR, 0, nframes * sizeof(float));
        return 0;
    }

    // Zero the mix bus for this block.
    std::fill(state->mixL.begin(), state->mixL.begin() + blockSize, 0.f);
    std::fill(state->mixR.begin(), state->mixR.begin() + blockSize, 0.f);

    // Snapshot plugins, order, routes, external renders, and master-mix
    // contributors under the lock so the JACK thread never races with
    // Dart-side mutations.
    std::vector<void*> ordered;
    std::unordered_map<void*, void*> routes;
    std::unordered_map<void*, DvhRenderFn> extRenders;
    std::vector<DvhRenderFn> masterRenders;
    std::vector<InsertChain> masterInsertChains;
    {
        std::lock_guard<std::mutex> lk(state->pluginsMtx);
        ordered             = state->processOrder.empty() ? state->plugins : state->processOrder;
        routes              = state->routes;
        extRenders          = state->externalRenders;
        masterRenders       = state->masterRenders;
        masterInsertChains  = state->masterInsertChains;
    }

    // Allocate per-plugin output buffers for routing.
    std::unordered_map<void*, std::pair<std::vector<float>, std::vector<float>>> bufs;
    for (void* p : ordered)
        bufs[p] = {std::vector<float>(blockSize, 0.f), std::vector<float>(blockSize, 0.f)};

    _processPlugins(ordered, routes, extRenders, bufs, blockSize,
                    state->zeroL, state->zeroR, state->mixL, state->mixR,
                    state->extBufL, state->extBufR);

    // ── Fan-in insert chains ────────────────────────────────────────────────
    // For each chain: mix all sources into extBuf (fan-in), apply effects
    // in series, then accumulate to the master bus.  Sources listed in any
    // chain are skipped in the bare-render loop below so they are never
    // rendered twice.
    for (const auto& chain : masterInsertChains) {
        // Zero the accumulation buffer for this chain's fan-in mix.
        std::fill(state->extBufL.begin(), state->extBufL.begin() + blockSize, 0.f);
        std::fill(state->extBufR.begin(), state->extBufR.begin() + blockSize, 0.f);
        // Render each source into tmpBuf and accumulate into extBuf.
        for (DvhRenderFn fn : chain.sources) {
            fn(state->tmpBufL.data(), state->tmpBufR.data(), blockSize);
            for (int i = 0; i < blockSize; ++i) {
                state->extBufL[i] += state->tmpBufL[i];
                state->extBufR[i] += state->tmpBufR[i];
            }
        }
        // Apply effects in series: extBuf → insertBuf → extBuf.
        for (const auto& ins : chain.effects) {
            ins.first(state->extBufL.data(), state->extBufR.data(),
                      state->insertBufL.data(), state->insertBufR.data(),
                      blockSize, ins.second);
            std::copy(state->insertBufL.begin(), state->insertBufL.begin() + blockSize,
                      state->extBufL.begin());
            std::copy(state->insertBufR.begin(), state->insertBufR.begin() + blockSize,
                      state->extBufR.begin());
        }
        // Accumulate processed signal to the master mix.
        for (int i = 0; i < blockSize; ++i) {
            state->mixL[i] += state->extBufL[i];
            state->mixR[i] += state->extBufR[i];
        }
    }

    // ── Bare master renders (no chain) ──────────────────────────────────────
    // Render sources that are NOT part of any insert chain directly.
    // This handles instruments with no downstream effects (e.g. KB1 bare).
    for (DvhRenderFn fn : masterRenders) {
        // Skip if this source is already handled by a chain above.
        bool inChain = false;
        for (const auto& chain : masterInsertChains) {
            for (DvhRenderFn src : chain.sources) {
                if (src == fn) { inChain = true; break; }
            }
            if (inChain) break;
        }
        if (inChain) continue;

        fn(state->extBufL.data(), state->extBufR.data(), blockSize);
        for (int i = 0; i < blockSize; ++i) {
            state->mixL[i] += state->extBufL[i];
            state->mixR[i] += state->extBufR[i];
        }
    }

    // Signal that this block's DSP processing is complete.
    // dvh_remove_master_insert_by_handle spin-waits on this counter to
    // ensure any in-flight snapshot that still held a raw DSP pointer has
    // retired before the caller destroys the DSP object.
    state->callbackSeq.fetch_add(1, std::memory_order_release);

    // Soft-clip to [-1, 1] and copy directly to JACK port buffers (float).
    // No int16 conversion needed — JACK uses native 32-bit float.
    for (int i = 0; i < blockSize; ++i) {
        float l = state->mixL[i];
        float r = state->mixR[i];
        if (l >  1.f) l =  1.f; if (l < -1.f) l = -1.f;
        if (r >  1.f) r =  1.f; if (r < -1.f) r = -1.f;
        outL[i] = l;
        outR[i] = r;
    }

    return 0;
}

/// JACK buffer-size callback — called from a non-RT thread when the server
/// changes the buffer size (e.g. user adjusts latency in JACK settings).
/// Allocation is permitted here.
static int _jackBufferSizeCallback(jack_nframes_t nframes, void* arg) {
    auto* state = static_cast<AudioState*>(arg);
    fprintf(stderr, "[dart_vst_host] JACK buffer size changed to %u\n",
            (unsigned)nframes);
    std::lock_guard<std::mutex> lk(state->pluginsMtx);
    _resizeBuffers(state, static_cast<int32_t>(nframes));
    return 0;
}

/// JACK XRUN callback — called from a notification thread when the server
/// detects a buffer underrun or overrun.  Keep the body trivial.
static int _jackXrunCallback(void* arg) {
    auto* state = static_cast<AudioState*>(arg);
    state->xrunCount.fetch_add(1, std::memory_order_relaxed);
    return 0;
}

/// JACK shutdown callback — called from a non-RT thread when the JACK server
/// shuts down (e.g. PipeWire restart, JACK server killed).
/// Cannot call jack_client_close inside this callback — just set a flag.
static void _jackShutdownCallback(void* arg) {
    auto* state = static_cast<AudioState*>(arg);
    fprintf(stderr, "[dart_vst_host] JACK server shut down\n");
    state->running.store(false);
}

extern "C" {

DVH_API void dvh_audio_add_plugin(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.push_back(plugin);
    fprintf(stderr, "[dart_vst_host] Plugin added to audio loop (total=%zu)\n", s->plugins.size());
}

DVH_API void dvh_audio_remove_plugin(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.erase(std::remove(s->plugins.begin(), s->plugins.end(), plugin), s->plugins.end());
    s->processOrder.erase(std::remove(s->processOrder.begin(), s->processOrder.end(), plugin), s->processOrder.end());
    s->routes.erase(plugin);
    for (auto it = s->routes.begin(); it != s->routes.end(); )
        it = (it->second == plugin) ? s->routes.erase(it) : std::next(it);
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
    fprintf(stderr, "[dart_vst_host] Audio loop cleared\n");
}

DVH_API void dvh_set_processing_order(DVH_Host host, const DVH_Plugin* order, int32_t count) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    if (!order || count <= 0) {
        s->processOrder.clear();
        return;
    }
    s->processOrder.assign(order, order + count);
}

DVH_API void dvh_route_audio(DVH_Host host, DVH_Plugin from, DVH_Plugin to) {
    if (!host || !from || !to) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->routes[from] = to;
}

DVH_API void dvh_clear_routes(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->routes.clear();
}

DVH_API void dvh_set_external_render(DVH_Host host, DVH_Plugin plugin, DvhRenderFn fn) {
    if (!host || !plugin || !fn) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->externalRenders[plugin] = fn;
}

DVH_API void dvh_clear_external_render(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->externalRenders.erase(plugin);
}

DVH_API void dvh_add_master_render(DVH_Host host, DvhRenderFn fn) {
    if (!host || !fn) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    // Deduplicate: only add if not already present.
    for (auto existing : s->masterRenders)
        if (existing == fn) return;
    s->masterRenders.push_back(fn);
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
    fprintf(stderr, "[dart_vst_host] Master render removed (total=%zu)\n",
            s->masterRenders.size());
}

/// Register a GFPA insert on [source]'s master-render audio path.
///
/// On each audio block, [source]'s output passes through the insert chain
/// in registration order.  Multiple inserts for the same [source] form a
/// series chain (source → insert[0] → insert[1] → … → master mix).
///
/// Fan-in merging: if [userdata] is already registered in an existing chain,
/// [source] is added to that chain's sources (fan-in).  This allows multiple
/// render sources (e.g. KB2 + Theremin) to share the same WAH → Reverb chain:
/// all sources are mixed first, then the effect runs once on the combined
/// signal, preventing double-processing and the associated distortion.
DVH_API void dvh_add_master_insert(DVH_Host host, DvhRenderFn source,
                                    GfpaInsertFn insertFn, void* userdata) {
    if (!host || !source || !insertFn) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);

    // Search all chains for one that already contains this DSP.
    // If found: merge [source] into that chain (fan-in).
    for (auto& chain : s->masterInsertChains) {
        for (const auto& ins : chain.effects) {
            if (ins.second != userdata) continue;
            // Chain already has this DSP — add source if not already there.
            for (DvhRenderFn src : chain.sources)
                if (src == source) return;  // already registered
            chain.sources.push_back(source);
            fprintf(stderr, "[dart_vst_host] Fan-in: source=%p merged into chain "
                    "containing dsp=%p (sources=%zu)\n",
                    (void*)source, userdata, chain.sources.size());
            return;
        }
    }

    // No chain contains this DSP yet.  Find an existing chain for [source]
    // and append the effect to it.
    for (auto& chain : s->masterInsertChains) {
        for (DvhRenderFn src : chain.sources) {
            if (src != source) continue;
            // This source already has a chain — append the new effect.
            for (const auto& ins : chain.effects)
                if (ins.second == userdata) return;  // already there
            chain.effects.push_back({insertFn, userdata});
            fprintf(stderr, "[dart_vst_host] Chain append: source=%p dsp=%p "
                    "effects=%zu\n",
                    (void*)source, userdata, chain.effects.size());
            return;
        }
    }

    // Neither this DSP nor this source has a chain yet — create one.
    s->masterInsertChains.push_back({{source}, {{insertFn, userdata}}});
    fprintf(stderr, "[dart_vst_host] New chain: source=%p dsp=%p\n",
            (void*)source, userdata);
}

/// Remove [source] from all chains.  If a chain has no sources left after
/// removal it is deleted entirely.  No-op if [source] is not in any chain.
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
    // Remove chains that no longer have any sources.
    s->masterInsertChains.erase(
        std::remove_if(s->masterInsertChains.begin(), s->masterInsertChains.end(),
            [](const InsertChain& c) { return c.sources.empty(); }),
        s->masterInsertChains.end());
    fprintf(stderr, "[dart_vst_host] Master insert removed for source %p\n", (void*)source);
}

/// Remove the insert matching [dspHandle] from every source chain, then drain.
///
/// Searches all chains for an entry whose userdata equals
/// gfpa_dsp_userdata(dspHandle) and removes it.  After removing, this
/// function spin-waits for the audio callback to complete at least one full
/// block, guaranteeing that any in-flight snapshot that still held a raw
/// pointer to this DSP object has retired.  The caller may then safely
/// destroy the DSP.
///
/// **Must be called BEFORE gfpa_dsp_destroy** to prevent use-after-free
/// crashes on the JACK audio thread.
DVH_API void dvh_remove_master_insert_by_handle(DVH_Host host, void* dspHandle) {
    if (!host || !dspHandle) return;
    auto* s = get(host);
    if (!s) return;
    // Resolve the userdata pointer stored in the chain entry.
    void* const ud = gfpa_dsp_userdata(dspHandle);
    bool removed = false;
    {
        std::lock_guard<std::mutex> lk(s->pluginsMtx);
        // Remove matching effects from all chains.
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
        // Remove chains that have no effects left (sources become bare renders).
        s->masterInsertChains.erase(
            std::remove_if(s->masterInsertChains.begin(), s->masterInsertChains.end(),
                [](const InsertChain& c) { return c.effects.empty(); }),
            s->masterInsertChains.end());
    } // ← pluginsMtx released BEFORE drain to avoid deadlock with audio callback
    if (!removed) {
        // Expected when dvh_clear_master_inserts has already removed all chains
        // (e.g. syncAudioRouting rebuilt the graph before the widget disposed).
        // Not an error — skip the drain wait.
        return;
    }
    // Drain: spin-wait for the audio callback to complete at least one block
    // after the removal.  The callbackSeq counter is incremented at the END of
    // each block's DSP processing, so a strictly greater value means any
    // in-flight raw pointer reference has been retired.
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

/// Remove all registered master inserts (all chains).
/// Called from syncAudioRouting at the start of a full routing rebuild.
DVH_API void dvh_clear_master_inserts(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterInsertChains.clear();
    fprintf(stderr, "[dart_vst_host] Master inserts cleared\n");
}

/// Remove all master render contributors.
/// Called from syncAudioRouting before re-registering active sources so that
/// stale entries from previous routing states are not left in the list.
DVH_API void dvh_clear_master_renders(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterRenders.clear();
    fprintf(stderr, "[dart_vst_host] Master renders cleared\n");
}

/// Open a JACK client, register stereo output ports, set up callbacks, and
/// activate.  Auto-connects to system:playback_1 / system:playback_2.
///
/// Returns 1 on success, 0 if the JACK server is not available or port
/// registration fails.
DVH_API int32_t dvh_start_jack_client(DVH_Host host, const char* client_name) {
    if (!host) return 0;
    auto* s = getOrCreate(host);
    if (s->running.load()) {
        fprintf(stderr, "[dart_vst_host] JACK client already running\n");
        return 1;
    }

    const char* name = (client_name && client_name[0]) ? client_name : "GrooveForge";
    fprintf(stderr, "[dart_vst_host] Opening JACK client: %s\n", name);

    // Open the JACK client.  JackNoStartServer prevents auto-launching a
    // JACK server if none is running — we want to fail fast with a clear
    // error rather than spawning an unexpected daemon.
    jack_status_t status;
    s->jackClient = jack_client_open(name, JackNoStartServer, &status);
    if (!s->jackClient) {
        fprintf(stderr, "[dart_vst_host] JACK client_open failed (status=0x%x). "
                "Is a JACK server (PipeWire or JACK2) running?\n", status);
        return 0;
    }

    // Read the server's sample rate and buffer size — these are authoritative.
    // The host's sample rate may differ if it was created before the JACK
    // server was started; we update the AudioState to match.
    s->sampleRate = static_cast<int32_t>(jack_get_sample_rate(s->jackClient));
    s->blockSize  = static_cast<int32_t>(jack_get_buffer_size(s->jackClient));

    fprintf(stderr, "[dart_vst_host] JACK server: sr=%d bs=%d\n",
            s->sampleRate, s->blockSize);

    // Pre-allocate all audio scratch buffers at the server's current block
    // size.  The buffer-size callback will resize them if the server changes.
    _resizeBuffers(s, s->blockSize);

    // Register callbacks before activation so no events are missed.
    jack_set_process_callback(s->jackClient, _jackProcessCallback, s);
    jack_set_buffer_size_callback(s->jackClient, _jackBufferSizeCallback, s);
    jack_set_xrun_callback(s->jackClient, _jackXrunCallback, s);
    jack_on_shutdown(s->jackClient, _jackShutdownCallback, s);

    // Register stereo output ports.  JACK_DEFAULT_AUDIO_TYPE is "32 bit float
    // mono audio" — one port per channel.
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

    // Activate the client — the process callback starts firing immediately.
    if (jack_activate(s->jackClient) != 0) {
        fprintf(stderr, "[dart_vst_host] JACK activate failed\n");
        jack_client_close(s->jackClient);
        s->jackClient = nullptr;
        return 0;
    }

    s->running.store(true);
    s->xrunCount.store(0);

    // Auto-connect to the system playback ports (speakers / default sink).
    // PipeWire maps these to the default audio output device.  Failure is
    // non-fatal — the user can connect manually via Helvum / qjackctl.
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

#else // !__linux__

#include "dart_vst_host.h"
#include "../include/gfpa_dsp.h"
extern "C" {
    void    dvh_audio_add_plugin(DVH_Host, DVH_Plugin) {}
    void    dvh_audio_remove_plugin(DVH_Host, DVH_Plugin) {}
    void    dvh_audio_clear_plugins(DVH_Host) {}
    int32_t dvh_start_jack_client(DVH_Host, const char*) { return 0; }
    void    dvh_stop_jack_client(DVH_Host) {}
    int32_t dvh_jack_get_xrun_count(DVH_Host) { return 0; }
    void    dvh_set_processing_order(DVH_Host, const DVH_Plugin*, int32_t) {}
    void    dvh_route_audio(DVH_Host, DVH_Plugin, DVH_Plugin) {}
    void    dvh_clear_routes(DVH_Host) {}
    void    dvh_set_external_render(DVH_Host, DVH_Plugin, DvhRenderFn) {}
    void    dvh_clear_external_render(DVH_Host, DVH_Plugin) {}
    void    dvh_add_master_render(DVH_Host, DvhRenderFn) {}
    void    dvh_remove_master_render(DVH_Host, DvhRenderFn) {}
    // GFPA insert chain stubs — no-ops on non-Linux platforms.
    void    dvh_add_master_insert(DVH_Host, DvhRenderFn, GfpaInsertFn, void*) {}
    void    dvh_remove_master_insert(DVH_Host, DvhRenderFn) {}
    void    dvh_remove_master_insert_by_handle(DVH_Host, void*) {}
    void    dvh_clear_master_inserts(DVH_Host) {}
    void    dvh_clear_master_renders(DVH_Host) {}
    // GFPA DSP stubs — return safe no-op values.
    void*   gfpa_dsp_create(const char*, int32_t, int32_t) { return nullptr; }
    void    gfpa_dsp_set_param(void*, const char*, double) {}
    GfpaInsertFn gfpa_dsp_insert_fn(void*) { return nullptr; }
    void*   gfpa_dsp_userdata(void*) { return nullptr; }
    void    gfpa_dsp_destroy(void*) {}
    void    gfpa_set_bpm(double) {}
}
#endif
