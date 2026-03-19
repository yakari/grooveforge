// ALSA audio loop for dart_vst_host (Linux only).
//
// Provides dvh_start_alsa_thread / dvh_stop_alsa_thread which drive all
// registered VST3 plugins in a real-time ALSA output thread. Plugins are
// mixed and written to the ALSA PCM device as interleaved int16.
//
// Phase 5.4 — audio graph execution:
//   dvh_set_processing_order  — override plugin processing order (topological)
//   dvh_route_audio            — route one plugin's output to another's input
//   dvh_clear_routes           — restore direct-to-master-mix routing

#ifdef __linux__

#include "dart_vst_host.h"
#include "dart_vst_host_internal.h"
#include "../include/gfpa_dsp.h"

#include <alsa/asoundlib.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

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
    /// When registered, the ALSA loop calls the function instead of using
    /// silence or an upstream VST3 output as the plugin's audio input.
    /// Used to route non-VST3 generators (Theremin, Stylophone) into effects.
    std::unordered_map<void*, DvhRenderFn> externalRenders;
    /// Master-mix contributors: render functions whose output is mixed directly
    /// into the ALSA master output alongside VST3 plugin outputs. Used for
    /// GF Keyboard (libfluidsynth) when it is not routed into a VST3 effect.
    std::vector<DvhRenderFn> masterRenders;
    /// GFPA insert chain: for each master render source, an optional insert
    /// effect that intercepts audio before it reaches the master mix bus.
    /// Key = source DvhRenderFn, Value = {insertFn, userdata}.
    std::unordered_map<DvhRenderFn, std::pair<GfpaInsertFn, void*>> masterInserts;
    /// Pre-allocated stereo buffer for external render calls — no heap
    /// allocation on the audio thread.
    std::vector<float> extBufL;
    std::vector<float> extBufR;
    /// Pre-allocated intermediate buffers for insert chain processing.
    /// The insert reads from extBuf and writes here, then we accumulate to mix.
    std::vector<float> insertBufL;
    std::vector<float> insertBufR;
    std::mutex          pluginsMtx;

    std::thread         thread;
    std::atomic<bool>   running{false};

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

// Process [ordered] plugins using [routes] for signal routing.
//
// Each plugin is given:
//   - As input: the output of the upstream plugin in [routes], or silence.
//   - Its output accumulates into [mixL]/[mixR] only when no downstream
//     route consumes it (i.e. the plugin is a "leaf" in the signal graph).
//
// This allows simple send-return chains, e.g.:
//   Synth → Effect: Effect output → master mix; Synth output → Effect input.
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

// Audio thread body. Takes ownership of the already-opened, configured [pcm].
static void audioThreadFn(AudioState* state, snd_pcm_t* pcm) {
    const int32_t blockSize = state->blockSize;

    std::vector<float> zeroL(blockSize, 0.f);
    std::vector<float> zeroR(blockSize, 0.f);
    std::vector<float> mixL(blockSize, 0.f);
    std::vector<float> mixR(blockSize, 0.f);
    std::vector<int16_t> pcmBuf(blockSize * 2);

    while (state->running.load()) {
        std::fill(mixL.begin(), mixL.end(), 0.f);
        std::fill(mixR.begin(), mixR.end(), 0.f);

        // Snapshot plugins, order, routes, external renders, and master-mix
        // contributors under the lock so the audio thread never races with
        // Dart-side mutations.
        std::vector<void*> ordered;
        std::unordered_map<void*, void*> routes;
        std::unordered_map<void*, DvhRenderFn> extRenders;
        std::vector<DvhRenderFn> masterRenders;
        std::unordered_map<DvhRenderFn, std::pair<GfpaInsertFn, void*>> masterInserts;
        {
            std::lock_guard<std::mutex> lk(state->pluginsMtx);
            ordered       = state->processOrder.empty() ? state->plugins : state->processOrder;
            routes        = state->routes;
            extRenders    = state->externalRenders;
            masterRenders = state->masterRenders;
            masterInserts = state->masterInserts;
        }

        // Allocate per-plugin output buffers for routing.
        std::unordered_map<void*, std::pair<std::vector<float>, std::vector<float>>> bufs;
        for (void* p : ordered)
            bufs[p] = {std::vector<float>(blockSize, 0.f), std::vector<float>(blockSize, 0.f)};

        _processPlugins(ordered, routes, extRenders, bufs, blockSize,
                        zeroL, zeroR, mixL, mixR,
                        state->extBufL, state->extBufR);

        // Mix master-render contributors (e.g. GF Keyboard via libfluidsynth)
        // into the master bus, applying any registered GFPA insert effects.
        for (DvhRenderFn fn : masterRenders) {
            // Render the source into the pre-allocated ext buffer.
            fn(state->extBufL.data(), state->extBufR.data(), blockSize);

            auto it = masterInserts.find(fn);
            if (it != masterInserts.end()) {
                // An insert is registered: route source through the DSP effect
                // into the insert intermediate buffer, then accumulate that.
                it->second.first(state->extBufL.data(), state->extBufR.data(),
                                 state->insertBufL.data(), state->insertBufR.data(),
                                 blockSize, it->second.second);
                for (int i = 0; i < blockSize; ++i) {
                    mixL[i] += state->insertBufL[i];
                    mixR[i] += state->insertBufR[i];
                }
            } else {
                // No insert — accumulate source directly to master mix.
                for (int i = 0; i < blockSize; ++i) {
                    mixL[i] += state->extBufL[i];
                    mixR[i] += state->extBufR[i];
                }
            }
        }

        // Soft-clip to [-1, 1] and convert to int16 interleaved.
        for (int i = 0; i < blockSize; ++i) {
            float l = mixL[i]; if (l >  1.f) l =  1.f; if (l < -1.f) l = -1.f;
            float r = mixR[i]; if (r >  1.f) r =  1.f; if (r < -1.f) r = -1.f;
            pcmBuf[i * 2 + 0] = (int16_t)(l * 32767.f);
            pcmBuf[i * 2 + 1] = (int16_t)(r * 32767.f);
        }

        snd_pcm_sframes_t written = snd_pcm_writei(pcm, pcmBuf.data(), blockSize);
        if (written < 0) {
            int err = snd_pcm_recover(pcm, (int)written, /*silent=*/0);
            if (err < 0) {
                fprintf(stderr, "[dart_vst_host] ALSA unrecoverable error: %s — stopping\n",
                        snd_strerror(err));
                break;
            }
        }
    }

    snd_pcm_drain(pcm);
    snd_pcm_close(pcm);
    fprintf(stderr, "[dart_vst_host] ALSA audio thread exited\n");
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
/// On each ALSA block, [source]'s output passes through [insertFn] before
/// being mixed into the master bus.  Replaces any previously registered
/// insert for the same [source].
DVH_API void dvh_add_master_insert(DVH_Host host, DvhRenderFn source,
                                    GfpaInsertFn insertFn, void* userdata) {
    if (!host || !source || !insertFn) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterInserts[source] = {insertFn, userdata};
    fprintf(stderr, "[dart_vst_host] Master insert added (total=%zu)\n",
            s->masterInserts.size());
}

/// Remove the GFPA insert registered for [source]. No-op if none registered.
DVH_API void dvh_remove_master_insert(DVH_Host host, DvhRenderFn source) {
    if (!host || !source) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterInserts.erase(source);
    fprintf(stderr, "[dart_vst_host] Master insert removed (total=%zu)\n",
            s->masterInserts.size());
}

/// Remove all registered master inserts.  Called from syncAudioRouting at the
/// start of a full routing rebuild to clear stale registrations.
DVH_API void dvh_clear_master_inserts(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->masterInserts.clear();
    fprintf(stderr, "[dart_vst_host] Master inserts cleared\n");
}

// Open and configure ALSA synchronously so failures are immediately visible.
// Returns 1 on success, 0 if ALSA cannot be opened/configured.
DVH_API int32_t dvh_start_alsa_thread(DVH_Host host, const char* alsa_device) {
    if (!host) return 0;
    auto* s = getOrCreate(host);
    if (s->running.load()) {
        fprintf(stderr, "[dart_vst_host] ALSA thread already running\n");
        return 1;
    }

    // Sync sample rate and block size from the host so ALSA opens at the
    // same rate that plug-ins were resumed with. The AudioState defaults to
    // 44100 Hz which would cause a ~1.4-semitone pitch shift vs VSTs running
    // at 48000 Hz.
    auto* hs = static_cast<DVH_HostState*>(host);
    s->sampleRate = static_cast<int32_t>(hs->sr);
    s->blockSize  = static_cast<int32_t>(hs->maxBlock);

    // Pre-allocate external render and insert intermediate buffers
    // (avoids heap allocation on the audio thread).
    s->extBufL.assign(s->blockSize, 0.f);
    s->extBufR.assign(s->blockSize, 0.f);
    s->insertBufL.assign(s->blockSize, 0.f);
    s->insertBufR.assign(s->blockSize, 0.f);

    const char* dev = (alsa_device && alsa_device[0]) ? alsa_device : "default";
    fprintf(stderr, "[dart_vst_host] Opening ALSA device: %s\n", dev);

    snd_pcm_t* pcm = nullptr;
    int err = snd_pcm_open(&pcm, dev, SND_PCM_STREAM_PLAYBACK, 0);
    if (err < 0) {
        fprintf(stderr, "[dart_vst_host] ALSA open failed: %s\n", snd_strerror(err));
        return 0;
    }

    err = snd_pcm_set_params(pcm,
        SND_PCM_FORMAT_S16_LE,
        SND_PCM_ACCESS_RW_INTERLEAVED,
        /*channels=*/2,
        (unsigned int)s->sampleRate,
        /*allow_resampling=*/1,
        /*latency_us=*/50000); // 50 ms — more forgiving for PipeWire/dmix
    if (err < 0) {
        fprintf(stderr, "[dart_vst_host] ALSA set_params failed: %s\n", snd_strerror(err));
        snd_pcm_close(pcm);
        return 0;
    }

    fprintf(stderr, "[dart_vst_host] ALSA opened OK — starting audio thread (sr=%d bs=%d)\n",
            s->sampleRate, s->blockSize);

    s->running.store(true);
    s->thread = std::thread(audioThreadFn, s, pcm);
    return 1;
}

DVH_API void dvh_stop_alsa_thread(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    fprintf(stderr, "[dart_vst_host] Stopping ALSA thread…\n");
    s->running.store(false);
    if (s->thread.joinable()) s->thread.join();
    removeState(host);
}

} // extern "C"

#else // !__linux__

#include "dart_vst_host.h"
#include "../include/gfpa_dsp.h"
extern "C" {
    void    dvh_audio_add_plugin(DVH_Host, DVH_Plugin) {}
    void    dvh_audio_remove_plugin(DVH_Host, DVH_Plugin) {}
    void    dvh_audio_clear_plugins(DVH_Host) {}
    int32_t dvh_start_alsa_thread(DVH_Host, const char*) { return 0; }
    void    dvh_stop_alsa_thread(DVH_Host) {}
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
    void    dvh_clear_master_inserts(DVH_Host) {}
    // GFPA DSP stubs — return safe no-op values.
    void*   gfpa_dsp_create(const char*, int32_t, int32_t) { return nullptr; }
    void    gfpa_dsp_set_param(void*, const char*, double) {}
    GfpaInsertFn gfpa_dsp_insert_fn(void*) { return nullptr; }
    void*   gfpa_dsp_userdata(void*) { return nullptr; }
    void    gfpa_dsp_destroy(void*) {}
    void    gfpa_set_bpm(double) {}
}
#endif
