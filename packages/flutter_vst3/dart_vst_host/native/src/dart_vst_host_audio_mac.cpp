// macOS Audio backend for dart_vst_host using miniaudio.
// Drives VST3 plugins in a real-time CoreAudio playback thread via miniaudio.
//
// Phase 5.4 — audio graph execution:
//   dvh_set_processing_order, dvh_route_audio, dvh_clear_routes
//   (same semantics as the ALSA backend — see dart_vst_host_alsa.cpp).

#ifdef __APPLE__

#define MA_API static
#define MINIAUDIO_IMPLEMENTATION
#include "dart_vst_host.h"
#include "../include/gfpa_dsp.h"
#include "../include/audio_looper.h"
#include "miniaudio.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <vector>

/// One fan-in effect chain: one or more source render functions whose audio
/// is mixed together and then passed through a series of GFPA DSP inserts.
/// See dart_vst_host_alsa.cpp for full documentation.
struct InsertChain {
    std::vector<DvhRenderFn> sources;
    std::vector<std::pair<GfpaInsertFn, void*>> effects;
};

/// Maximum master render contributors.
static constexpr int kMaxMasterRenders = 16;

struct AudioState {
    std::vector<void*> plugins;
    std::vector<void*> processOrder;
    std::unordered_map<void*, void*> routes;
    std::vector<DvhRenderFn> masterRenders;
    std::vector<InsertChain> masterInsertChains;
    std::mutex          pluginsMtx;
    std::atomic<uint64_t> callbackSeq{0};

    ma_device           device;
    std::atomic<bool>   running{false};

    int32_t sampleRate{48000};
    int32_t blockSize{256};

    // Pre-allocated scratch buffers (no heap allocation in callback).
    std::vector<float> extBufL, extBufR;
    std::vector<float> insertBufL, insertBufR;
    std::vector<float> tmpBufL, tmpBufR;
    std::vector<float> mixL, mixR;
    std::vector<float> zeroL, zeroR;

    // Per-master-render capture buffers for audio looper source matching.
    std::vector<float> renderCaptureL[kMaxMasterRenders];
    std::vector<float> renderCaptureR[kMaxMasterRenders];

    // Per-clip audio looper source buffers.
    std::vector<float> alooperSrcL[ALOOPER_MAX_CLIPS];
    std::vector<float> alooperSrcR[ALOOPER_MAX_CLIPS];

    // Transport state for audio looper bar-sync.
    std::atomic<double> transportBpm{120.0};
    std::atomic<int32_t> transportTimeSigNum{4};
    std::atomic<int32_t> transportIsPlaying{0};
    std::atomic<double> transportPositionBeats{0.0};

    // Output limiter state.
    float limiterGain = 1.0f;
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

// Process [ordered] plugins using [routes] for signal routing.
// See dart_vst_host_alsa.cpp for full documentation.
static void _processPlugins(
    const std::vector<void*>& ordered,
    const std::unordered_map<void*, void*>& routes,
    std::unordered_map<void*, std::pair<std::vector<float>, std::vector<float>>>& bufs,
    ma_uint32 frameCount,
    const std::vector<float>& zeroL,
    const std::vector<float>& zeroR,
    float* out)
{
    for (void* p : ordered) {
        void* upstream = nullptr;
        for (const auto& r : routes)
            if (r.second == p) { upstream = r.first; break; }

        const float* inL = upstream ? bufs.at(upstream).first.data()  : zeroL.data();
        const float* inR = upstream ? bufs.at(upstream).second.data() : zeroR.data();
        auto& outBuf = bufs[p];
        dvh_process_stereo_f32(p, inL, inR, outBuf.first.data(), outBuf.second.data(), (int32_t)frameCount);

        // Accumulate to master only when no downstream plugin consumes this output.
        if (routes.count(p) == 0) {
            for (ma_uint32 i = 0; i < frameCount; ++i) {
                out[i * 2 + 0] += outBuf.first[i];
                out[i * 2 + 1] += outBuf.second[i];
            }
        }
    }
}

// ─── miniaudio Callback ──────────────────────────────────────────────────────

/// Returns true if [fn] appears as a source in any insert chain.
static bool _isInChain(const std::vector<InsertChain>& chains, DvhRenderFn fn) {
    for (const auto& chain : chains) {
        for (DvhRenderFn src : chain.sources)
            if (src == fn) return true;
    }
    return false;
}

static void dataCallback(ma_device* pDevice, void* pOutput, const void* /*pInput*/, ma_uint32 frameCount) {
    auto* state = (AudioState*)pDevice->pUserData;
    if (!state || !state->running.load()) return;

    const int32_t bs = static_cast<int32_t>(frameCount);

    // Guard: if buffers not yet allocated, output silence.
    if (bs > static_cast<int32_t>(state->mixL.size())) {
        std::memset(pOutput, 0, frameCount * 2 * sizeof(float));
        return;
    }

    // Zero the master mix bus.
    std::fill_n(state->mixL.data(), bs, 0.f);
    std::fill_n(state->mixR.data(), bs, 0.f);

    // Snapshot plugins, order, routes, and chains under the lock.
    // NOTE: these copies still allocate on the heap. A full triple-buffer
    // refactor (like the Linux JACK backend) is a future optimisation.
    std::vector<void*> ordered;
    std::unordered_map<void*, void*> routes;
    std::vector<DvhRenderFn> masterRenders;
    std::vector<InsertChain> masterInsertChains;
    {
        std::lock_guard<std::mutex> lk(state->pluginsMtx);
        ordered            = state->processOrder.empty() ? state->plugins : state->processOrder;
        routes             = state->routes;
        masterRenders      = state->masterRenders;
        masterInsertChains = state->masterInsertChains;
    }

    // ── VST3 plugins (output goes into interleaved out via _processPlugins) ──
    // TODO: pre-allocate per-plugin buffers like the Linux backend.
    float* out = (float*)pOutput;
    std::fill(out, out + frameCount * 2, 0.f);
    std::unordered_map<void*, std::pair<std::vector<float>, std::vector<float>>> bufs;
    for (void* p : ordered)
        bufs[p] = {std::vector<float>(frameCount, 0.f), std::vector<float>(frameCount, 0.f)};
    _processPlugins(ordered, routes, bufs, frameCount, state->zeroL, state->zeroR, out);
    // Deinterleave VST3 output into the mix bus.
    for (int32_t i = 0; i < bs; ++i) {
        state->mixL[i] += out[i * 2 + 0];
        state->mixR[i] += out[i * 2 + 1];
    }

    // ── Fan-in insert chains ─────────────────────────────────────────────
    for (const auto& chain : masterInsertChains) {
        std::fill_n(state->extBufL.data(), bs, 0.f);
        std::fill_n(state->extBufR.data(), bs, 0.f);
        for (DvhRenderFn fn : chain.sources) {
            fn(state->tmpBufL.data(), state->tmpBufR.data(), bs);
            // Save render capture for audio looper source matching.
            for (int m = 0; m < static_cast<int>(masterRenders.size()) && m < kMaxMasterRenders; ++m) {
                if (masterRenders[m] == fn) {
                    std::copy_n(state->tmpBufL.data(), bs, state->renderCaptureL[m].data());
                    std::copy_n(state->tmpBufR.data(), bs, state->renderCaptureR[m].data());
                    break;
                }
            }
            for (int32_t i = 0; i < bs; ++i) {
                state->extBufL[i] += state->tmpBufL[i];
                state->extBufR[i] += state->tmpBufR[i];
            }
        }
        for (const auto& ins : chain.effects) {
            ins.first(state->extBufL.data(), state->extBufR.data(),
                      state->insertBufL.data(), state->insertBufR.data(),
                      bs, ins.second);
            std::copy_n(state->insertBufL.data(), bs, state->extBufL.data());
            std::copy_n(state->insertBufR.data(), bs, state->extBufR.data());
        }
        for (int32_t i = 0; i < bs; ++i) {
            state->mixL[i] += state->extBufL[i];
            state->mixR[i] += state->extBufR[i];
        }
    }

    // ── Bare master renders ──────────────────────────────────────────────
    for (int m = 0; m < static_cast<int>(masterRenders.size()); ++m) {
        DvhRenderFn fn = masterRenders[m];
        if (_isInChain(masterInsertChains, fn)) continue;

        fn(state->extBufL.data(), state->extBufR.data(), bs);
        if (m < kMaxMasterRenders) {
            std::copy_n(state->extBufL.data(), bs, state->renderCaptureL[m].data());
            std::copy_n(state->extBufR.data(), bs, state->renderCaptureR[m].data());
        }
        for (int32_t i = 0; i < bs; ++i) {
            state->mixL[i] += state->extBufL[i];
            state->mixR[i] += state->extBufR[i];
        }
    }

    // ── Audio Looper — fill per-clip source buffers ──────────────────────
    const float* aloopSrcL[ALOOPER_MAX_CLIPS] = {};
    const float* aloopSrcR[ALOOPER_MAX_CLIPS] = {};
    for (int c = 0; c < ALOOPER_MAX_CLIPS; ++c) {
        if (!dvh_alooper_is_active(c)) continue;
        const int nRender = dvh_alooper_get_render_source_count(c);
        const int nPlugin = dvh_alooper_get_plugin_source_count(c);
        if (nRender == 0 && nPlugin == 0) continue;

        std::fill_n(state->alooperSrcL[c].data(), bs, 0.f);
        std::fill_n(state->alooperSrcR[c].data(), bs, 0.f);

        for (int s = 0; s < nRender; ++s) {
            DvhRenderFn fn = dvh_alooper_get_render_source(c, s);
            if (!fn) continue;
            for (int m2 = 0; m2 < static_cast<int>(masterRenders.size()) && m2 < kMaxMasterRenders; ++m2) {
                if (masterRenders[m2] == fn) {
                    for (int32_t i = 0; i < bs; ++i) {
                        state->alooperSrcL[c][i] += state->renderCaptureL[m2][i];
                        state->alooperSrcR[c][i] += state->renderCaptureR[m2][i];
                    }
                    break;
                }
            }
        }
        aloopSrcL[c] = state->alooperSrcL[c].data();
        aloopSrcR[c] = state->alooperSrcR[c].data();
    }

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

    // ── Output limiter — speaker protection ─────────────────────────────
    {
        constexpr float threshold = 0.95f;
        const float releaseCoeff = 1.0f - (1.0f / (0.050f * state->sampleRate));
        float g = state->limiterGain;

        for (int32_t i = 0; i < bs; ++i) {
            const float l = state->mixL[i];
            const float r = state->mixR[i];
            const float peak = std::max(std::abs(l), std::abs(r));

            if (peak * g > threshold) {
                g = threshold / peak;
            } else {
                g = g * releaseCoeff + (1.0f - releaseCoeff);
                if (g > 1.0f) g = 1.0f;
            }

            out[i * 2 + 0] = l * g;
            out[i * 2 + 1] = r * g;
        }
        state->limiterGain = g;
    }
}

extern "C" {

DVH_API void dvh_audio_add_plugin(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.push_back(plugin);
    fprintf(stderr, "[dart_vst_host] Plugin added to macOS audio loop: host=%p plugin=%p\n", host, plugin);
    fflush(stderr);
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
}

DVH_API void dvh_audio_clear_plugins(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.clear();
    s->processOrder.clear();
    s->routes.clear();
}

DVH_API void dvh_set_processing_order(DVH_Host host, const DVH_Plugin* order, int32_t count) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    if (!order || count <= 0) { s->processOrder.clear(); return; }
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

DVH_API int32_t dvh_mac_start_audio(DVH_Host host) {
    if (!host) return 0;
    auto* s = getOrCreate(host);
    if (s->running.load()) return 1;

    fprintf(stderr, "[dart_vst_host] dvh_mac_start_audio(host=%p) called\n", host);
    fflush(stderr);

    // Pre-allocate all audio scratch buffers so the CoreAudio callback never
    // allocates heap memory on the real-time audio thread.
    // tmpBuf is used for fan-in source mixing in insert chains.
    s->extBufL.assign(s->blockSize, 0.f);
    s->extBufR.assign(s->blockSize, 0.f);
    s->insertBufL.assign(s->blockSize, 0.f);
    s->insertBufR.assign(s->blockSize, 0.f);
    s->tmpBufL.assign(s->blockSize, 0.f);
    s->tmpBufR.assign(s->blockSize, 0.f);
    s->mixL.assign(s->blockSize, 0.f);
    s->mixR.assign(s->blockSize, 0.f);
    s->zeroL.assign(s->blockSize, 0.f);
    s->zeroR.assign(s->blockSize, 0.f);
    for (int i = 0; i < kMaxMasterRenders; ++i) {
        s->renderCaptureL[i].assign(s->blockSize, 0.f);
        s->renderCaptureR[i].assign(s->blockSize, 0.f);
    }
    for (int i = 0; i < ALOOPER_MAX_CLIPS; ++i) {
        s->alooperSrcL[i].assign(s->blockSize, 0.f);
        s->alooperSrcR[i].assign(s->blockSize, 0.f);
    }

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format      = ma_format_f32;
    config.playback.channels    = 2;
    config.sampleRate           = (ma_uint32)s->sampleRate;
    config.dataCallback         = dataCallback;
    config.pUserData            = s;
    config.performanceProfile   = ma_performance_profile_low_latency;
    // Lock the period size to match our pre-allocated scratch buffers and the
    // FluidSynth/VST3 block size.  Without this miniaudio lets CoreAudio choose
    // its own period (typically 512 on macOS), which causes keyboard_render_block
    // to write 512 floats into the 256-float extBufL/R → buffer overflow → corrupt
    // audio that sounds like random effects / echo / distortion.
    config.periodSizeInFrames   = (ma_uint32)s->blockSize;

    fprintf(stderr, "[dart_vst_host] Initializing ma_device at %d Hz...\n", s->sampleRate);
    fflush(stderr);

    ma_result res = ma_device_init(NULL, &config, &s->device);
    if (res != MA_SUCCESS) {
        fprintf(stderr, "[dart_vst_host] ma_device_init failed with error %d\n", (int)res);
        fflush(stderr);
        return 0;
    }

    res = ma_device_start(&s->device);
    if (res != MA_SUCCESS) {
        fprintf(stderr, "[dart_vst_host] ma_device_start failed with error %d\n", (int)res);
        fflush(stderr);
        ma_device_uninit(&s->device);
        return 0;
    }

    s->running.store(true);
    fprintf(stderr, "[dart_vst_host] macOS CoreAudio device started OK\n");
    fflush(stderr);
    return 1;
}

DVH_API void dvh_mac_stop_audio(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    s->running.store(false);
    ma_device_stop(&s->device);
    ma_device_uninit(&s->device);
    removeState(host);
    fprintf(stderr, "[dart_vst_host] dvh_mac_stop_audio(host=%p) done\n", host);
    fflush(stderr);
}

// ─── External-render routing (Theremin/Stylophone → VST3 input) ─────────────
// Not yet implemented for CoreAudio — macOS instruments output audio through
// their own paths.  Stubs satisfy the FFI symbol lookup from syncAudioRouting.

DVH_API void dvh_set_external_render(DVH_Host /*host*/, DVH_Plugin /*plugin*/, DvhRenderFn /*fn*/) {}
DVH_API void dvh_clear_external_render(DVH_Host /*host*/, DVH_Plugin /*plugin*/) {}

// Keep ALSA stubs for compatibility — ALSA is not used on macOS.
DVH_API int32_t dvh_start_alsa_thread(DVH_Host /*host*/, const char* /*device*/) {
    fprintf(stderr, "[dart_vst_host] dvh_start_alsa_thread called on macOS (IGNORING: use dvh_mac_start_audio)\n");
    fflush(stderr);
    return 0;
}
DVH_API void dvh_stop_alsa_thread(DVH_Host /*host*/) {}

// ─── Master-render contributors (e.g. GF Keyboard) ──────────────────────────

/// Register [fn] as a master-mix contributor.  On each CoreAudio block its
/// stereo output is added to the master bus (possibly via an insert effect).
DVH_API void dvh_add_master_render(DVH_Host host, DvhRenderFn fn) {
    if (!host || !fn) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    // Deduplicate.
    for (auto existing : s->masterRenders)
        if (existing == fn) return;
    s->masterRenders.push_back(fn);
    fprintf(stderr, "[dart_vst_host] Master render added (total=%zu)\n", s->masterRenders.size());
}

/// Remove [fn] from the master-render list.
DVH_API void dvh_remove_master_render(DVH_Host host, DvhRenderFn fn) {
    if (!host || !fn) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterRenders.erase(
        std::remove(s->masterRenders.begin(), s->masterRenders.end(), fn),
        s->masterRenders.end());
    fprintf(stderr, "[dart_vst_host] Master render removed (total=%zu)\n", s->masterRenders.size());
}

// ─── GFPA insert chain ───────────────────────────────────────────────────────

/// Register a GFPA DSP insert on [source]'s master-render path.
/// Fan-in merging: if [userdata] is already in an existing chain, [source]
/// is added to that chain's sources instead of creating a duplicate.
/// See dart_vst_host_alsa.cpp for full documentation.
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
            for (DvhRenderFn src : chain.sources)
                if (src == source) return;  // already registered
            chain.sources.push_back(source);
            fprintf(stderr, "[dart_vst_host] Fan-in: source=%p merged into chain "
                    "containing dsp=%p (sources=%zu)\n",
                    (void*)source, userdata, chain.sources.size());
            return;
        }
    }

    // No chain contains this DSP yet.  Find a chain for [source] and append.
    for (auto& chain : s->masterInsertChains) {
        for (DvhRenderFn src : chain.sources) {
            if (src != source) continue;
            for (const auto& ins : chain.effects)
                if (ins.second == userdata) return;  // already there
            chain.effects.push_back({insertFn, userdata});
            fprintf(stderr, "[dart_vst_host] Chain append: source=%p dsp=%p "
                    "effects=%zu\n",
                    (void*)source, userdata, chain.effects.size());
            return;
        }
    }

    // Create a new chain.
    s->masterInsertChains.push_back({{source}, {{insertFn, userdata}}});
    fprintf(stderr, "[dart_vst_host] New chain: source=%p dsp=%p\n",
            (void*)source, userdata);
}

/// Remove [source] from all chains.  Chains with no sources left are deleted.
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
    fprintf(stderr, "[dart_vst_host] Master insert removed for source %p\n", (void*)source);
}

/// Remove the insert matching [dspHandle] from all chains, then drain.
/// Must be called BEFORE gfpa_dsp_destroy to prevent use-after-free crashes.
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
    } // ← pluginsMtx released BEFORE drain to avoid deadlock with CoreAudio callback
    if (!removed) {
        fprintf(stderr, "[dart_vst_host] dvh_remove_master_insert_by_handle: "
                "handle %p not found\n", dspHandle);
        return;
    }
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

/// Clear all insert chains (called at the start of every syncAudioRouting rebuild).
DVH_API void dvh_clear_master_inserts(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterInsertChains.clear();
}

/// Clear all master render contributors.
/// Called from syncAudioRouting before re-registering active sources.
DVH_API void dvh_clear_master_renders(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterRenders.clear();
    fprintf(stderr, "[dart_vst_host] Master renders cleared\n");
}

} // extern "C"

// ── Transport broadcast (called from dart_vst_host.cpp) ─────────────────────

void dvh_mac_update_transport(double bpm, int32_t timeSigNum,
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

#else // !__APPLE__
// Stub when not compiling for macOS.
void dvh_mac_update_transport(double, int32_t, int32_t, double) {}
#endif // __APPLE__
