#ifdef __APPLE__

#define MA_API static
#define MINIAUDIO_IMPLEMENTATION
#include "../include/dart_vst_host.h"
#include "../include/gfpa_dsp.h"
#include "../include/miniaudio.h"

#include <atomic>
#include <vector>
#include <mutex>
#include <algorithm>
#include <thread>
#include <chrono>

#define MAX_VST_PLUGINS 64
#define MAX_BUFFER_SIZE 4096

/// Represents a single plugin slot in the processing chain.
struct RackRow {
    void*           plugin{nullptr};
    int32_t         bufferIdx{-1};
    int32_t         upstreamBufferIdx{-1};
    DvhRenderFn      extRenderFn{nullptr};
    bool            isOutput{false};
};

/// Constant view of the rack for the audio thread.
struct RackState {
    RackRow rows[MAX_VST_PLUGINS];
    int     count{0};

    // ── Master Renders (Double Buffered) ───────────────────────────────────
    DvhRenderFn renders[32];
    int         renderCount{0};

    // ── Master Inserts (Double Buffered) ───────────────────────────────────
    struct RenderInsert {
        DvhRenderFn source;
        struct Effect {
            GfpaInsertFn fn;
            void*        userdata;
        } effects[8];
        int effectCount;
    } inserts[32];
    int insertCount{0};
};

struct AudioState {
    // ── Rack State (Double Buffered) ─────────────────────────────────────────
    RackState           racks[2];
    std::atomic<int>    activeRackIdx{0};
    std::mutex          rackMtx; // Protects the background rack while building

    // ── Pre-allocated Buffers ────────────────────────────────────────────────
    float* bufferPoolL[MAX_VST_PLUGINS];
    float* bufferPoolR[MAX_VST_PLUGINS];
    float* scratchL;
    float* scratchR;
    float* insertL;
    float* insertR;
    float* zeroBuf;

    // ── Pre-allocated Plugin List (Original Source) ──────────────────────────
    std::vector<void*> plugins;
    std::vector<void*> processOrder;
    struct Route { void* from; void* to; };
    std::vector<Route> routes;
    struct ExtRender { void* plugin; DvhRenderFn fn; };
    std::vector<ExtRender> extRenders;

    // ── Master Mix Configuration (Source for Triple Buffering) ───────────────
    DvhRenderFn masterRenders[32];
    struct MasterInsertConfig {
        DvhRenderFn source;
        struct Effect {
            GfpaInsertFn fn;
            void*        userdata;
        } effects[8];
    } masterInserts[32];

    // ── Synchronization ──────────────────────────────────────────────────────
    std::atomic<uint64_t> cycleCount{0};

    // ── Device State ─────────────────────────────────────────────────────────
    ma_device           device;
    std::atomic<bool>   running{false};
    int32_t             sampleRate{48000};
    int32_t             blockSize{MAX_BUFFER_SIZE};

    AudioState() {
        for (int i = 0; i < MAX_VST_PLUGINS; ++i) {
            bufferPoolL[i] = new float[MAX_BUFFER_SIZE];
            bufferPoolR[i] = new float[MAX_BUFFER_SIZE];
        }
        scratchL = new float[MAX_BUFFER_SIZE];
        scratchR = new float[MAX_BUFFER_SIZE];
        insertL = new float[MAX_BUFFER_SIZE];
        insertR = new float[MAX_BUFFER_SIZE];
        zeroBuf = new float[MAX_BUFFER_SIZE];
        std::fill(zeroBuf, zeroBuf + MAX_BUFFER_SIZE, 0.f);

        for (int i = 0; i < 32; ++i) {
            masterRenders[i] = nullptr;
            masterInserts[i].source = nullptr;
            for (int j = 0; j < 8; ++j) {
                masterInserts[i].effects[j].fn = nullptr;
                masterInserts[i].effects[j].userdata = nullptr;
            }
        }
    }

    ~AudioState() {
        for (int i = 0; i < MAX_VST_PLUGINS; ++i) {
            delete[] bufferPoolL[i];
            delete[] bufferPoolR[i];
        }
        delete[] scratchL;
        delete[] scratchR;
        delete[] insertL;
        delete[] insertR;
        delete[] zeroBuf;
    }
    
    /// Rebuild the background [RackState] and toggle the atomic index.
    void commitRack() {
        std::lock_guard<std::mutex> lk(rackMtx);
        int nextIdx = 1 - activeRackIdx.load();
        RackState& nr = racks[nextIdx];
        
        const std::vector<void*>& order = processOrder.empty() ? plugins : processOrder;
        nr.count = (int)std::min((size_t)order.size(), (size_t)MAX_VST_PLUGINS);
        
        for (int i = 0; i < nr.count; ++i) {
            void* p = order[i];
            nr.rows[i].plugin = p;
            nr.rows[i].bufferIdx = i; // simple 1:1 mapping to pool
            
            // Check for external render driver (high priority)
            nr.rows[i].extRenderFn = nullptr;
            for (const auto& er : extRenders) {
                if (er.plugin == p) { nr.rows[i].extRenderFn = er.fn; break; }
            }
            
            // Check for upstream dependency
            nr.rows[i].upstreamBufferIdx = -1;
            if (!nr.rows[i].extRenderFn) {
                void* upstream = nullptr;
                for (const auto& r : routes) {
                    if (r.to == p) { upstream = r.from; break; }
                }
                if (upstream) {
                    for (int j = 0; j < i; ++j) {
                        if (nr.rows[j].plugin == upstream) {
                            nr.rows[i].upstreamBufferIdx = nr.rows[j].bufferIdx;
                            break;
                        }
                    }
                }
            }
            
            // Is this a leaf node that should mix into the master out?
            bool hasDownstream = false;
            for (const auto& r : routes) {
                if (r.from == p) { hasDownstream = true; break; }
            }
            nr.rows[i].isOutput = !hasDownstream;
        }
        
        // 3. Snapshot master renders and inserts
        nr.renderCount = 0;
        for (int i = 0; i < 32; ++i) {
            if (masterRenders[i]) {
                nr.renders[nr.renderCount++] = masterRenders[i];
            }
        }

        nr.insertCount = 0;
        for (int i = 0; i < 32; ++i) {
            if (masterInserts[i].source) {
                nr.inserts[nr.insertCount].source = masterInserts[i].source;
                int ec = 0;
                for (int j = 0; j < 8; ++j) {
                    if (masterInserts[i].effects[j].fn) {
                        nr.inserts[nr.insertCount].effects[ec].fn = masterInserts[i].effects[j].fn;
                        nr.inserts[nr.insertCount].effects[ec].userdata = masterInserts[i].effects[j].userdata;
                        ec++;
                    }
                }
                nr.inserts[nr.insertCount].effectCount = ec;
                nr.insertCount++;
            }
        }
        
        activeRackIdx.store(nextIdx, std::memory_order_release);
    }
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

// ─── miniaudio Callback (STRICTLY REAL-TIME SAFE) ───────────────────────────

static void dataCallback(ma_device* pDevice, void* pOutput, const void* /*pInput*/, ma_uint32 frameCount) {
    auto* s = (AudioState*)pDevice->pUserData;
    if (!s || !s->running.load(std::memory_order_acquire)) return;

    float* out = (float*)pOutput;
    std::fill(out, out + frameCount * 2, 0.f);
    if (frameCount > MAX_BUFFER_SIZE) return;

    // 1. Snapshot the rack (LOCK-FREE)
    int rackIdx = s->activeRackIdx.load(std::memory_order_acquire);
    const RackState& rack = s->racks[rackIdx];

    // 2. Process VST3 chain (LOCK-FREE, ALLOCATION-FREE)
    for (int i = 0; i < rack.count; ++i) {
        const RackRow& row = rack.rows[i];
        const float* inL = s->zeroBuf;
        const float* inR = s->zeroBuf;

        if (row.extRenderFn) {
            row.extRenderFn(s->scratchL, s->scratchR, (int32_t)frameCount);
            inL = s->scratchL;
            inR = s->scratchR;
        } else if (row.upstreamBufferIdx >= 0) {
            inL = s->bufferPoolL[row.upstreamBufferIdx];
            inR = s->bufferPoolR[row.upstreamBufferIdx];
        }

        dvh_process_stereo_f32(row.plugin, inL, inR, s->bufferPoolL[row.bufferIdx], s->bufferPoolR[row.bufferIdx], (int32_t)frameCount);

        if (row.isOutput) {
            for (ma_uint32 f = 0; f < frameCount; ++f) {
                out[f * 2 + 0] += s->bufferPoolL[row.bufferIdx][f];
                out[f * 2 + 1] += s->bufferPoolR[row.bufferIdx][f];
            }
        }
    }

    // 3. Mix master-render contributors + GFPA insert chains (LOCK-FREE SNAPSHOT)
    for (int m = 0; m < rack.renderCount; ++m) {
        DvhRenderFn mFn = rack.renders[m];
        mFn(s->scratchL, s->scratchR, (int32_t)frameCount);

        // Find associated insert chain in the SNAPSHOT.
        const RackState::RenderInsert* pSlot = nullptr;
        for (int i = 0; i < rack.insertCount; ++i) {
            if (rack.inserts[i].source == mFn) {
                pSlot = &rack.inserts[i];
                break;
            }
        }

        if (pSlot && pSlot->effectCount > 0) {
            float* curInL = s->scratchL;
            float* curInR = s->scratchR;
            float* curOutL = s->insertL;
            float* curOutR = s->insertR;
            bool processed = false;

            for (int e = 0; e < pSlot->effectCount; ++e) {
                GfpaInsertFn iFn = pSlot->effects[e].fn;
                void* ud = pSlot->effects[e].userdata;

                iFn(curInL, curInR, curOutL, curOutR, (int32_t)frameCount, ud);
                
                curInL = curOutL;
                curInR = curOutR;
                curOutL = (curInL == s->insertL) ? s->scratchL : s->insertL;
                curOutR = (curInR == s->insertR) ? s->scratchR : s->insertR;
                processed = true;
            }

            const float* finalSourceL = processed ? curInL : s->scratchL;
            const float* finalSourceR = processed ? curInR : s->scratchR;
            for (ma_uint32 f = 0; f < frameCount; ++f) {
                out[f * 2 + 0] += finalSourceL[f];
                out[f * 2 + 1] += finalSourceR[f];
            }
        } else {
            for (ma_uint32 f = 0; f < frameCount; ++f) {
                out[f * 2 + 0] += s->scratchL[f];
                out[f * 2 + 1] += s->scratchR[f];
            }
        }
    }

    // 4. Clipping
    for (ma_uint32 i = 0; i < frameCount * 2; ++i) {
        if (out[i] > 1.0f) out[i] = 1.0f;
        else if (out[i] < -1.0f) out[i] = -1.0f;
    }

    // 5. Signal block completion for synchronization.
    s->cycleCount.fetch_add(1, std::memory_order_release);
}

extern "C" {

DVH_API void dvh_audio_add_plugin(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->rackMtx);
    s->plugins.push_back(plugin);
    s->commitRack();
}

DVH_API void dvh_audio_remove_plugin(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    s->plugins.erase(std::remove(s->plugins.begin(), s->plugins.end(), plugin), s->plugins.end());
    s->processOrder.erase(std::remove(s->processOrder.begin(), s->processOrder.end(), plugin), s->processOrder.end());
    
    for (auto it = s->routes.begin(); it != s->routes.end();) {
        if (it->from == plugin || it->to == plugin) it = s->routes.erase(it); else ++it;
    }
    for (auto it = s->extRenders.begin(); it != s->extRenders.end();) {
        if (it->plugin == plugin) it = s->extRenders.erase(it); else ++it;
    }
    s->commitRack();
}

DVH_API void dvh_audio_clear_plugins(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    s->plugins.clear();
    s->processOrder.clear();
    s->routes.clear();
    s->extRenders.clear();
    s->commitRack();
}

DVH_API void dvh_set_processing_order(DVH_Host host, const DVH_Plugin* order, int32_t count) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    if (!order || count <= 0) s->processOrder.clear();
    else s->processOrder.assign(order, order + count);
    s->commitRack();
}

DVH_API void dvh_route_audio(DVH_Host host, DVH_Plugin from, DVH_Plugin to) {
    if (!host || !from || !to) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    bool found = false;
    for (auto& r : s->routes) { if (r.from == from) { r.to = to; found = true; break; } }
    if (!found) s->routes.push_back({from, to});
    s->commitRack();
}

DVH_API void dvh_clear_routes(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    s->routes.clear();
    s->commitRack();
}

DVH_API int32_t dvh_mac_start_audio(DVH_Host host) {
    if (!host) return 0;
    auto* s = getOrCreate(host);
    if (s->running.load()) return 1;

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format   = ma_format_f32;
    config.playback.channels = 2;
    config.sampleRate        = (ma_uint32)s->sampleRate;
    config.dataCallback      = dataCallback;
    config.pUserData         = s;
    config.performanceProfile = ma_performance_profile_low_latency;

    ma_result res = ma_device_init(NULL, &config, &s->device);
    if (res != MA_SUCCESS) return 0;

    res = ma_device_start(&s->device);
    if (res != MA_SUCCESS) { ma_device_uninit(&s->device); return 0; }

    s->running.store(true);
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
}

DVH_API void dvh_set_external_render(DVH_Host host, DVH_Plugin plugin, DvhRenderFn fn) {
    if (!host || !plugin) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->rackMtx);
    bool found = false;
    for (auto& er : s->extRenders) { if (er.plugin == plugin) { er.fn = fn; found = true; break; } }
    if (!found) s->extRenders.push_back({plugin, fn});
    s->commitRack();
}

DVH_API void dvh_clear_external_render(DVH_Host host, DVH_Plugin plugin) {
    if (!host || !plugin) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    s->extRenders.erase(std::remove_if(s->extRenders.begin(), s->extRenders.end(), [&](const AudioState::ExtRender& er){
        return er.plugin == plugin;
    }), s->extRenders.end());
    s->commitRack();
}

DVH_API int32_t dvh_start_alsa_thread(DVH_Host /*host*/, const char* /*device*/) { return 0; }
DVH_API void dvh_stop_alsa_thread(DVH_Host /*host*/) {}

DVH_API void dvh_add_master_render(DVH_Host host, DvhRenderFn fn) {
    if (!host || !fn) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->rackMtx);
    for (int i=0; i<32; ++i) {
        if (s->masterRenders[i] == fn) return;
        if (s->masterRenders[i] == nullptr) {
            s->masterRenders[i] = fn;
            s->commitRack();
            return;
        }
    }
}

DVH_API void dvh_remove_master_render(DVH_Host host, DvhRenderFn fn) {
    if (!host || !fn) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    bool found = false;
    for (int i=0; i<32; ++i) {
        if (s->masterRenders[i] == fn) { 
            s->masterRenders[i] = nullptr; 
            found = true; 
        }
    }
    if (found) s->commitRack();
}

DVH_API void dvh_add_master_insert(DVH_Host host, DvhRenderFn source, GfpaInsertFn_fwd insertFn, void* userdata) {
    if (!host || !source || !insertFn) return;
    auto* s = getOrCreate(host);
    std::lock_guard<std::mutex> lk(s->rackMtx);
    
    AudioState::MasterInsertConfig* pSlot = nullptr;
    for (int i=0; i<32; ++i) {
        if (s->masterInserts[i].source == source) { pSlot = &s->masterInserts[i]; break; }
        if (s->masterInserts[i].source == nullptr && !pSlot) { pSlot = &s->masterInserts[i]; }
    }
    
    if (pSlot) {
        pSlot->source = source;
        for (int e=0; e<8; ++e) {
            if (pSlot->effects[e].fn == (GfpaInsertFn)insertFn) {
                pSlot->effects[e].userdata = userdata;
                s->commitRack();
                return;
            }
            if (pSlot->effects[e].fn == nullptr) {
                pSlot->effects[e].fn = (GfpaInsertFn)insertFn;
                pSlot->effects[e].userdata = userdata;
                s->commitRack();
                return;
            }
        }
    }
}

DVH_API void dvh_remove_master_insert(DVH_Host host, DvhRenderFn source) {
    if (!host || !source) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    bool found = false;
    for (int i=0; i<32; ++i) {
        if (s->masterInserts[i].source == source) {
            s->masterInserts[i].source = nullptr;
            for (int e=0; e<8; ++e) {
                s->masterInserts[i].effects[e].fn = nullptr;
                s->masterInserts[i].effects[e].userdata = nullptr;
            }
            found = true;
            break;
        }
    }
    if (found) s->commitRack();
}

DVH_API void dvh_clear_master_inserts(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s) return;
    std::lock_guard<std::mutex> lk(s->rackMtx);
    for (int i=0; i<32; ++i) {
        s->masterInserts[i].source = nullptr;
        for (int e=0; e<8; ++e) {
            s->masterInserts[i].effects[e].fn = nullptr;
            s->masterInserts[i].effects[e].userdata = nullptr;
        }
    }
    s->commitRack();
}

DVH_API void dvh_mac_sync_audio(DVH_Host host) {
    if (!host) return;
    auto* s = get(host);
    if (!s || !s->running.load()) return;

    // Snapshot current cycle count
    uint64_t start = s->cycleCount.load(std::memory_order_acquire);
    
    // Wait for it to increment twice (ensures at least one full buffer cycle
    // began AFTER the sync call was made).
    for (int i = 0; i < 20; ++i) { // max 20 x 5ms = 100ms timeout
        if (s->cycleCount.load(std::memory_order_acquire) >= start + 2) return;
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
        if (!s->running.load()) return;
    }
}

} // extern "C"

#endif // __APPLE__
