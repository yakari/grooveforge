// macOS Audio backend for dart_vst_host using miniaudio.
// Drives VST3 plugins in a real-time CoreAudio playback thread via miniaudio.

#ifdef __APPLE__

#define MA_API static
#define MINIAUDIO_IMPLEMENTATION
#include "dart_vst_host.h"
#include "miniaudio.h"

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <mutex>
#include <vector>

struct AudioState {
    std::vector<void*> plugins; // DVH_Plugin (PluginState*)
    std::mutex          pluginsMtx;

    ma_device           device;
    std::atomic<bool>   running{false};

    int32_t sampleRate{48000}; // Aligned with native_audio
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

// ─── miniaudio Callback ──────────────────────────────────────────────────────

static void dataCallback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    auto* state = (AudioState*)pDevice->pUserData;
    if (!state || !state->running.load()) return;

    float* out = (float*)pOutput;
    
    std::vector<float> inputZero(frameCount, 0.f);
    std::vector<float> outL(frameCount, 0.f);
    std::vector<float> outR(frameCount, 0.f);
    
    // Clear output buffer
    std::fill(out, out + frameCount * 2, 0.f);

    std::vector<void*> snapshot;
    {
        std::lock_guard<std::mutex> lk(state->pluginsMtx);
        snapshot = state->plugins;
    }

    for (void* p : snapshot) {
        std::fill(outL.begin(), outL.end(), 0.f);
        std::fill(outR.begin(), outR.end(), 0.f);
        
        dvh_process_stereo_f32(p,
            inputZero.data(), inputZero.data(),
            outL.data(), outR.data(),
            (int32_t)frameCount);

        for (ma_uint32 i = 0; i < frameCount; ++i) {
            out[i * 2 + 0] += outL[i];
            out[i * 2 + 1] += outR[i];
        }
    }

    // Clip
    for (ma_uint32 i = 0; i < frameCount * 2; ++i) {
        if (out[i] > 1.f) out[i] = 1.f;
        else if (out[i] < -1.f) out[i] = -1.f;
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
}

DVH_API void dvh_audio_clear_plugins(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.clear();
}

DVH_API int32_t dvh_mac_start_audio(DVH_Host host) {
    if (!host) return 0;
    auto* s = getOrCreate(host);
    if (s->running.load()) return 1;

    fprintf(stderr, "[dart_vst_host] dvh_mac_start_audio(host=%p) called\n", host);
    fflush(stderr);

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format   = ma_format_f32;
    config.playback.channels = 2;
    config.sampleRate        = s->sampleRate;
    config.dataCallback      = dataCallback;
    config.pUserData         = s;
    config.performanceProfile = ma_performance_profile_low_latency;

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

// Keep old names as stubs for compatibility if needed, but they should be unused now
DVH_API int32_t dvh_start_alsa_thread(DVH_Host host, const char* /*device*/) {
    fprintf(stderr, "[dart_vst_host] dvh_start_alsa_thread called on macOS (IGNORING: use dvh_mac_start_audio)\n");
    fflush(stderr);
    return 0;
}
DVH_API void dvh_stop_alsa_thread(DVH_Host host) {
    (void)host;
}

} // extern "C"

#endif // __APPLE__
