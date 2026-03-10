// ALSA audio loop for dart_vst_host (Linux only).
//
// Provides dvh_start_alsa_thread / dvh_stop_alsa_thread which drive all
// registered VST3 plugins in a real-time ALSA output thread. Plugins are
// mixed and written to the ALSA PCM device as interleaved int16.

#ifdef __linux__

#include "dart_vst_host.h"

#include <alsa/asoundlib.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct AudioState {
    std::vector<void*> plugins;
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

// Audio thread body. Takes ownership of the already-opened, configured [pcm].
static void audioThreadFn(AudioState* state, snd_pcm_t* pcm) {
    const int32_t blockSize = state->blockSize;

    std::vector<float> zeroL(blockSize, 0.f);
    std::vector<float> zeroR(blockSize, 0.f);
    std::vector<float> outL(blockSize, 0.f);
    std::vector<float> outR(blockSize, 0.f);
    std::vector<float> mixL(blockSize, 0.f);
    std::vector<float> mixR(blockSize, 0.f);
    std::vector<int16_t> pcmBuf(blockSize * 2);

    while (state->running.load()) {
        std::fill(mixL.begin(), mixL.end(), 0.f);
        std::fill(mixR.begin(), mixR.end(), 0.f);

        std::vector<void*> snapshot;
        {
            std::lock_guard<std::mutex> lk(state->pluginsMtx);
            snapshot = state->plugins;
        }

        for (void* p : snapshot) {
            std::fill(outL.begin(), outL.end(), 0.f);
            std::fill(outR.begin(), outR.end(), 0.f);
            dvh_process_stereo_f32(p,
                zeroL.data(), zeroR.data(),
                outL.data(), outR.data(),
                blockSize);
            for (int i = 0; i < blockSize; ++i) {
                mixL[i] += outL[i];
                mixR[i] += outR[i];
            }
        }

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
    fprintf(stderr, "[dart_vst_host] Plugin removed from audio loop (total=%zu)\n", s->plugins.size());
}

DVH_API void dvh_audio_clear_plugins(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->pluginsMtx);
    s->plugins.clear();
    fprintf(stderr, "[dart_vst_host] Audio loop cleared\n");
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
extern "C" {
    void    dvh_audio_add_plugin(DVH_Host, DVH_Plugin) {}
    void    dvh_audio_remove_plugin(DVH_Host, DVH_Plugin) {}
    void    dvh_audio_clear_plugins(DVH_Host) {}
    int32_t dvh_start_alsa_thread(DVH_Host, const char*) { return 0; }
    void    dvh_stop_alsa_thread(DVH_Host) {}
}
#endif
