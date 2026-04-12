// oboe_stream_android.cpp — Shared AAudio output stream (universal audio bus).
//
// Architecture overview:
//   One AAudioStream runs for the lifetime of the app's audio session.
//   Any sound source (GF Keyboard, Theremin, Stylophone, Vocoder, …) registers
//   itself as an AudioSource with a render callback and a bus slot ID.
//   Each audio block:
//     1. The AAudio callback snapshots the registered source list under a brief
//        mutex, then calls each source's renderFn() into a pre-allocated buffer.
//     2. The GFPA per-source insert chain (WAH, reverb, delay, EQ, …) is applied
//        in-place via gfpa_android_apply_chain_for_sf(), using the source's
//        busSlotId as the chain key.  This ensures an effect wired to the
//        Theremin cannot bleed into Keyboard or Vocoder audio.
//     3. All per-source outputs are summed into shared mix buffers.
//     4. The non-interleaved L/R mix is interleaved into AAudio's output buffer.
//
// Thread safety:
//   The source list (g_sources, g_sourceCount) is guarded by g_sourcesMtx.
//   The callback takes a brief snapshot copy and releases the lock immediately.
//   oboe_stream_remove_source() waits for an "all-clear" atomic counter that
//   the callback increments at the END of each invocation, guaranteeing that no
//   in-flight callback is still using a removed source before the caller proceeds
//   to free any associated resources.
//
// Audio thread rules:
//   - No heap allocation inside audioCallback.
//   - No logging on the hot path.
//   - Parameter changes reach the DSP via std::atomic<float> (gfpa_dsp.cpp).
//
// Bus slot ID assignment (must match gfpa_audio_android.cpp kMaxBusSlot):
//   1–4  : GF Keyboard slots (sfId returned by flutter_midi_pro loadSoundfont)
//   5    : Theremin
//   6    : Stylophone
//   7    : Vocoder
//   (additional slots reserved for future sources up to kMaxSources)

#include "oboe_stream_android.h"
#include "gfpa_audio_android.h"
#include "audio_looper.h"

#include <aaudio/AAudio.h>
#include <android/log.h>
#include <fluidsynth.h>

#include <atomic>
#include <cstring>
#include <mutex>
#include <thread>
#include <chrono>

// ── Android logging macros ────────────────────────────────────────────────────

#define LOG_TAG "OboeStreamAndroid"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// ── Constants ─────────────────────────────────────────────────────────────────

/// Maximum number of simultaneously active audio sources (keyboards + instruments).
/// 4 keyboard slots + Theremin + Stylophone + Vocoder = 7; 8 leaves headroom.
static constexpr int kMaxSources = 8;

/// Maximum block size (frames) that AAudio will deliver per callback.
/// Pre-allocated render and mix buffers are sized to this ceiling so the
/// callback never allocates on the heap.
/// 4096 frames @ 48 kHz ≈ 85 ms; actual Oboe bursts are typically 96–256.
static constexpr int kMaxFrames = 4096;

// ── Audio source registry ─────────────────────────────────────────────────────

/// One registered audio source.
///
/// Any sound generator (FluidSynth keyboard, Theremin, Stylophone, Vocoder)
/// registers as an AudioSource.  The callback calls renderFn() each block,
/// then applies that source's GFPA insert chain identified by busSlotId.
struct AudioSource {
    /// Render callback — writes [frames] non-interleaved float samples into
    /// outL and outR.  Called on the AAudio real-time thread; must be
    /// allocation-free.  The buffers are pre-zeroed before this call, so the
    /// function can either replace or accumulate into them.
    AudioSourceRenderFn renderFn;

    /// Opaque context forwarded to renderFn — e.g. fluid_synth_t* for keyboards,
    /// nullptr for singleton instruments (Theremin, Stylophone, Vocoder).
    void* userdata;

    /// Bus slot identifier used to look up the GFPA insert chain for this source.
    /// Must be unique across all registered sources and match the slot IDs
    /// documented at the top of this file.
    int busSlotId;
};

/// All registered audio sources.
/// Modified from the Dart/JNI thread; read (via snapshot) by the AAudio callback.
static AudioSource g_sources[kMaxSources] = {};

/// Number of valid entries in g_sources.
static int g_sourceCount = 0;

/// Protects g_sources / g_sourceCount between the Dart/JNI thread and the callback.
static std::mutex g_sourcesMtx;

// ── Drain synchronisation ─────────────────────────────────────────────────────

/// Incremented by the callback at the END of every invocation.
/// oboe_stream_remove_source() reads this before removing a source, then waits
/// until it advances — ensuring any in-flight callback that captured a snapshot
/// containing that source has fully completed before the caller may free resources.
static std::atomic<uint64_t> g_callbackDoneSeq{0};

// ── Pre-allocated audio buffers ───────────────────────────────────────────────
//
// Global (not stack-allocated) because the AAudio callback runs on a single
// dedicated thread — there is no concurrent access to these arrays.
// Pre-allocation avoids heap usage and stack pressure in the callback.

/// Per-source non-interleaved left-channel render buffers.
/// Zeroed before each renderFn() call to prevent any accumulation artifact.
/// These hold the **post-FX** signal after the source's GFPA insert chain
/// has been applied in place — i.e. what reaches the master mix.
static float g_srcL[kMaxSources][kMaxFrames];

/// Per-source non-interleaved right-channel render buffers (post-FX).
static float g_srcR[kMaxSources][kMaxFrames];

/// Dry (pre-GFPA-chain) copies of g_srcL/R, captured right after the source's
/// renderFn() returns and before `gfpa_android_apply_chain_for_sf` runs.
///
/// Used ONLY by the audio-looper fill pass: a clip cabled to a source records
/// its dry signal so that the looper captures the instrument, not the
/// instrument-plus-insert-effects.  This matches the Linux JACK semantic
/// where `renderCaptureL/R[m]` snapshots the dry render output.
///
/// Kept separate from g_srcL/R to avoid a second `memcpy` back after the
/// chain is applied — a single copy before the chain is cheapest.
static float g_srcDryL[kMaxSources][kMaxFrames];
static float g_srcDryR[kMaxSources][kMaxFrames];

/// Sink buffers for FluidSynth's built-in reverb/chorus wet signal.
/// Kept separate from g_srcL/g_srcR so that FX output cannot corrupt the
/// dry render buffers, even if fluid_synth_reverb_on() was not honoured.
static float g_fxL[kMaxFrames];
static float g_fxR[kMaxFrames];

/// Final summed left-channel master mix.
static float g_mixL[kMaxFrames];

/// Final summed right-channel master mix.
static float g_mixR[kMaxFrames];

// ── Audio looper pre-allocated buffers ───────────────────────────────────────

/// Per-clip source buffers for the audio looper.
static float g_alooperSrcL[ALOOPER_MAX_CLIPS][kMaxFrames];
static float g_alooperSrcR[ALOOPER_MAX_CLIPS][kMaxFrames];

// ── Transport state for audio looper bar-sync ────────────────────────────────

static std::atomic<double>  g_transportBpm{120.0};
static std::atomic<int32_t> g_transportTimeSigNum{4};
static std::atomic<int32_t> g_transportIsPlaying{0};
static std::atomic<double>  g_transportPositionBeats{0.0};
static int32_t g_sampleRate = 48000;

// ── AAudio stream handle ──────────────────────────────────────────────────────

static AAudioStream* g_stream = nullptr;

// ── Output device routing ────────────────────────────────────────────────────
//
// Android AudioDeviceInfo.id to pass to AAudioStreamBuilder_setDeviceId().
// A value of 0 (AAUDIO_UNSPECIFIED) means "use the system default device".
// Set from the Dart/JNI thread; read when (re-)opening the stream.
// Not accessed from the audio callback, so a plain int is sufficient.

static int g_outputDeviceId = 0;

// ── FluidSynth render trampoline ──────────────────────────────────────────────

/// Render trampoline for FluidSynth keyboard sources.
///
/// Adapts the generic AudioSourceRenderFn signature to fluid_synth_process().
/// FluidSynth's reverb/chorus wet signal is routed into the dedicated g_fxL/g_fxR
/// sink buffers and discarded — this prevents any residual FX output from
/// overwriting the dry render buffers even if the built-in effects are not
/// fully disabled on the bundled pre-built FluidSynth.
///
/// [userdata] — fluid_synth_t* cast to void*.
static void fluidSynthRenderFn(float* outL, float* outR, int frames, void* userdata)
{
    auto* synth = static_cast<fluid_synth_t*>(userdata);

    float* outPtrs[2] = { outL, outR };
    float* fxPtrs[4]  = {
        g_fxL, g_fxR,   // reverb L/R — written but discarded
        g_fxL, g_fxR    // chorus L/R — written but discarded
    };

    fluid_synth_process(synth, frames, 4, fxPtrs, 2, outPtrs);
}

// ── AAudio callbacks ──────────────────────────────────────────────────────────

/// AAudio real-time data callback.  Called on a high-priority audio thread.
///
/// For each registered source:
///   1. Zeroes the per-source render buffer (prevents accumulation across blocks).
///   2. Calls source.renderFn() to fill the buffer with that source's audio.
///   3. Applies the source's GFPA insert chain in-place (WAH, EQ, reverb, …).
///   4. Accumulates the result into the master mix buffers.
/// Then interleaves the master mix into AAudio's stereo output buffer.
///
/// [stream]    — AAudio stream handle (unused; present for API signature).
/// [userData]  — unused (NULL).
/// [audioData] — interleaved stereo float32 output buffer owned by AAudio.
/// [numFrames] — number of sample frames to fill this block.
static aaudio_data_callback_result_t audioCallback(
    AAudioStream* /*stream*/, void* /*userData*/,
    void* audioData, int32_t numFrames)
{
    auto* output = static_cast<float*>(audioData);

    // Guard against unexpectedly large blocks — process up to kMaxFrames and
    // silence the remainder.  In practice Oboe bursts are well below 4096.
    const int frames = (numFrames <= kMaxFrames) ? numFrames : kMaxFrames;

    // ── 1. Snapshot the source list ───────────────────────────────────────
    //
    // Brief lock to copy the pointer/callback array.  Released before any DSP
    // work so registration/unregistration on the Dart thread is never blocked
    // by audio processing.
    AudioSource snapshot[kMaxSources];
    int sourceCount = 0;
    {
        std::lock_guard<std::mutex> lock(g_sourcesMtx);
        sourceCount = g_sourceCount;
        for (int i = 0; i < sourceCount; ++i) snapshot[i] = g_sources[i];
    }

    // ── 2. Clear master mix ───────────────────────────────────────────────
    std::memset(g_mixL, 0, sizeof(float) * static_cast<size_t>(frames));
    std::memset(g_mixR, 0, sizeof(float) * static_cast<size_t>(frames));

    // ── 3. Render each source, capture dry, apply chain, accumulate ───────
    for (int s = 0; s < sourceCount; ++s) {
        // Zero the render buffers before calling renderFn.  Some sources
        // (e.g. FluidSynth pre-built builds) accumulate rather than replace,
        // which would cause exponential signal growth across callbacks.
        std::memset(g_srcL[s], 0, sizeof(float) * static_cast<size_t>(frames));
        std::memset(g_srcR[s], 0, sizeof(float) * static_cast<size_t>(frames));

        // Render this source into its dedicated L/R buffers.
        snapshot[s].renderFn(g_srcL[s], g_srcR[s], frames, snapshot[s].userdata);

        // Snapshot the DRY signal before the GFPA chain runs, so the audio
        // looper can record the instrument's raw output rather than the
        // post-FX signal.  Linux does the equivalent via `renderCapture[m]`
        // in dart_vst_host_jack.cpp — this memcpy is the Android analog.
        // Cheap: one 8-byte-per-frame copy per source per block.
        std::memcpy(g_srcDryL[s], g_srcL[s],
                    sizeof(float) * static_cast<size_t>(frames));
        std::memcpy(g_srcDryR[s], g_srcR[s],
                    sizeof(float) * static_cast<size_t>(frames));

        // Apply this source's GFPA insert chain (WAH, EQ, reverb, delay, …)
        // in-place before accumulating into the master mix.
        // This ensures an effect wired to the Theremin cannot reach keyboard or
        // vocoder audio, and vice versa.  No-op when the chain is empty.
        gfpa_android_apply_chain_for_sf(snapshot[s].busSlotId,
                                        g_srcL[s], g_srcR[s], frames);

        // Accumulate into the master mix.
        for (int i = 0; i < frames; ++i) {
            g_mixL[i] += g_srcL[s][i];
            g_mixR[i] += g_srcR[s][i];
        }
    }

    // ── 3b. Audio Looper — cabled-input routing ──────────────────────────
    //
    // For each active clip we consult the bus-source list configured by the
    // Dart side (VstHostService._syncAudioLooperSourcesAndroid) and sum the
    // dry output of every matching source into the clip's private source
    // buffer.  A clip with no bus sources records silence (same semantic as
    // the Linux path). Then `dvh_alooper_process` mixes clip playback back
    // into the master mix.
    {
        const float* aloopSrcL[ALOOPER_MAX_CLIPS] = {};
        const float* aloopSrcR[ALOOPER_MAX_CLIPS] = {};
        for (int c = 0; c < ALOOPER_MAX_CLIPS; ++c) {
            if (!dvh_alooper_is_active(c)) continue;
            const int32_t nBus = dvh_alooper_get_bus_source_count(c);
            if (nBus <= 0) continue; // No cables → leave aloopSrc[c] = NULL.

            // Zero the clip's scratch buffer — multiple upstream sources sum
            // into it, so we must start from silence each block.
            std::memset(g_alooperSrcL[c], 0,
                        sizeof(float) * static_cast<size_t>(frames));
            std::memset(g_alooperSrcR[c], 0,
                        sizeof(float) * static_cast<size_t>(frames));

            // For every cabled bus slot, find the matching source in the
            // current snapshot and sum its dry stereo into the clip buffer.
            // `busSlotId` is the stable lookup key:
            //   - Keyboards : dynamic FluidSynth sfId assigned at load time.
            //   - Theremin  : kBusSlotTheremin (100).
            // Stylophone and vocoder are not on the shared bus and are never
            // added here — cabling them is a known Android limitation.
            for (int b = 0; b < nBus; ++b) {
                const int32_t busId = dvh_alooper_get_bus_source(c, b);
                for (int s = 0; s < sourceCount; ++s) {
                    if (snapshot[s].busSlotId != busId) continue;
                    for (int i = 0; i < frames; ++i) {
                        g_alooperSrcL[c][i] += g_srcDryL[s][i];
                        g_alooperSrcR[c][i] += g_srcDryR[s][i];
                    }
                    break; // Each busSlotId is unique in the snapshot.
                }
            }

            aloopSrcL[c] = g_alooperSrcL[c];
            aloopSrcR[c] = g_alooperSrcR[c];
        }

        dvh_alooper_process(
            aloopSrcL, aloopSrcR,
            g_mixL, g_mixR,
            frames,
            g_transportBpm.load(std::memory_order_relaxed),
            g_transportTimeSigNum.load(std::memory_order_relaxed),
            g_sampleRate,
            g_transportIsPlaying.load(std::memory_order_relaxed) != 0,
            g_transportPositionBeats.load(std::memory_order_relaxed));
    }

    // ── 4. Interleave non-interleaved L/R into AAudio's stereo buffer ─────
    //
    // AAudio expects interleaved samples: [L0, R0, L1, R1, …]
    for (int i = 0; i < frames; ++i) {
        output[i * 2]     = g_mixL[i];
        output[i * 2 + 1] = g_mixR[i];
    }

    // Silence any frames beyond the kMaxFrames cap (should never happen in practice).
    if (numFrames > kMaxFrames) {
        std::memset(output + kMaxFrames * 2, 0,
                    sizeof(float) * static_cast<size_t>(numFrames - kMaxFrames) * 2);
    }

    // ── 5. Signal drain waiters ───────────────────────────────────────────
    //
    // Increment AFTER all work is done so oboe_stream_remove_source() can
    // safely determine when an in-flight callback has finished.
    g_callbackDoneSeq.fetch_add(1, std::memory_order_release);

    return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

/// AAudio error callback.  Called on an internal AAudio thread when the stream
/// encounters an unrecoverable error (e.g. audio device disconnect).
///
/// On any error (including AAUDIO_ERROR_DISCONNECTED and the Android 11
/// AAUDIO_ERROR_TIMEOUT variant), the stream is closed and reopened on a
/// detached thread.  The device ID is reset to 0 (system default) so the
/// new stream targets whatever device Android now considers active.
static void errorCallback(AAudioStream* stream, void* /*userData*/,
                          aaudio_result_t error)
{
    LOGE("AAudio stream error: %s (%d)", AAudio_convertResultToText(error), error);

    // Capture sample rate before the stream becomes invalid.
    const int sr = AAudioStream_getSampleRate(stream);

    // Reopen on a detached thread — we must not block the error callback, and
    // oboe_stream_stop/start touch the mutex and may block briefly.
    std::thread([sr]() {
        LOGI("AAudio error recovery: reopening stream on default device "
             "(was device %d)", g_outputDeviceId);
        g_outputDeviceId = 0;  // fall back to system default
        oboe_stream_stop();
        oboe_stream_start(sr);
    }).detach();
}

// ── Public API ────────────────────────────────────────────────────────────────

extern "C" void oboe_stream_start(int sampleRate)
{
    if (g_stream != nullptr) return; // Stream already running.

    AAudioStreamBuilder* builder = nullptr;
    aaudio_result_t result = AAudio_createStreamBuilder(&builder);
    if (result != AAUDIO_OK) {
        LOGE("AAudio_createStreamBuilder: %s", AAudio_convertResultToText(result));
        return;
    }

    // Output, stereo, float32 — matches renderFn output format for all sources.
    AAudioStreamBuilder_setDirection(builder, AAUDIO_DIRECTION_OUTPUT);
    AAudioStreamBuilder_setFormat(builder, AAUDIO_FORMAT_PCM_FLOAT);
    AAudioStreamBuilder_setChannelCount(builder, 2);
    AAudioStreamBuilder_setSampleRate(builder, sampleRate);

    // Route to a specific output device when the user has selected one.
    // 0 (AAUDIO_UNSPECIFIED) = system default; any positive value is an
    // Android AudioDeviceInfo.id obtained from AudioManager.getDevices().
    if (g_outputDeviceId > 0) {
        AAudioStreamBuilder_setDeviceId(builder, g_outputDeviceId);
        LOGI("AAudio stream targeting device ID %d", g_outputDeviceId);
    }

    // Low-latency exclusive mode for minimal device output latency.
    AAudioStreamBuilder_setPerformanceMode(
            builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setSharingMode(
            builder, AAUDIO_SHARING_MODE_EXCLUSIVE);

    // Buffer capacity hint keeps the burst well inside kMaxFrames.
    AAudioStreamBuilder_setBufferCapacityInFrames(builder, kMaxFrames);

    AAudioStreamBuilder_setDataCallback(builder, audioCallback, nullptr);
    AAudioStreamBuilder_setErrorCallback(builder, errorCallback, nullptr);

    result = AAudioStreamBuilder_openStream(builder, &g_stream);
    AAudioStreamBuilder_delete(builder);

    if (result != AAUDIO_OK) {
        LOGE("AAudioStreamBuilder_openStream: %s", AAudio_convertResultToText(result));
        g_stream = nullptr;
        return;
    }

    result = AAudioStream_requestStart(g_stream);
    if (result != AAUDIO_OK) {
        LOGE("AAudioStream_requestStart: %s", AAudio_convertResultToText(result));
        AAudioStream_close(g_stream);
        g_stream = nullptr;
        return;
    }

    LOGI("AAudio stream started — sampleRate=%d actualSampleRate=%d framesPerBurst=%d",
         sampleRate,
         AAudioStream_getSampleRate(g_stream),
         AAudioStream_getFramesPerBurst(g_stream));
}

extern "C" void oboe_stream_stop(void)
{
    if (g_stream == nullptr) return;

    AAudioStream_requestStop(g_stream);
    AAudioStream_close(g_stream);
    g_stream = nullptr;
    LOGI("AAudio stream stopped");
}

extern "C" void oboe_stream_add_source(AudioSourceRenderFn renderFn,
                                        void* userdata,
                                        int busSlotId)
{
    std::lock_guard<std::mutex> lock(g_sourcesMtx);

    // Idempotency: skip if this busSlotId is already registered.
    for (int i = 0; i < g_sourceCount; ++i) {
        if (g_sources[i].busSlotId == busSlotId) {
            LOGW("oboe_stream_add_source: busSlotId=%d already registered", busSlotId);
            return;
        }
    }

    if (g_sourceCount >= kMaxSources) {
        LOGE("oboe_stream_add_source: maximum source count (%d) reached", kMaxSources);
        return;
    }

    g_sources[g_sourceCount++] = { renderFn, userdata, busSlotId };
    LOGI("oboe_stream_add_source: busSlotId=%d, %d source(s) active",
         busSlotId, g_sourceCount);
}

extern "C" void oboe_stream_remove_source(int busSlotId)
{
    // ── 1. Remove from the registered list ───────────────────────────────
    {
        std::lock_guard<std::mutex> lock(g_sourcesMtx);

        int found = -1;
        for (int i = 0; i < g_sourceCount; ++i) {
            if (g_sources[i].busSlotId == busSlotId) { found = i; break; }
        }

        if (found < 0) return; // Not registered — no-op.

        // Shift remaining entries left to keep the array contiguous.
        for (int i = found; i < g_sourceCount - 1; ++i) {
            g_sources[i] = g_sources[i + 1];
        }
        g_sources[--g_sourceCount] = {};

        LOGI("oboe_stream_remove_source: busSlotId=%d, %d source(s) remaining",
             busSlotId, g_sourceCount);
    }

    // ── 2. Wait for any in-progress callback to finish ────────────────────
    //
    // After the removal above, future callbacks will not include this source.
    // A callback that started before the removal may have already taken a
    // snapshot containing it and might still be rendering.
    // We wait until g_callbackDoneSeq advances — meaning at least one full
    // post-removal callback has run — before returning to the caller.
    //
    // Typical wait: one audio burst (~5 ms at 256 frames / 48 kHz).
    // The 50 ms timeout guards the edge case where the stream is stopped.
    if (g_stream != nullptr) {
        const uint64_t seqBefore =
                g_callbackDoneSeq.load(std::memory_order_acquire);
        const auto deadline =
                std::chrono::steady_clock::now() + std::chrono::milliseconds(50);
        while (g_callbackDoneSeq.load(std::memory_order_acquire) <= seqBefore) {
            if (std::chrono::steady_clock::now() >= deadline) {
                LOGW("oboe_stream_remove_source: drain timeout — proceeding anyway");
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }
    // Caller may now safely free any resources associated with this source.
}

// ── Output device routing ────────────────────────────────────────────────────

/// Sets the Android output device ID for the AAudio stream.
///
/// [deviceId] — Android AudioDeviceInfo.id from AudioManager.getDevices().
///              Pass 0 (AAUDIO_UNSPECIFIED) to revert to the system default.
///
/// If the stream is already running, it is stopped and restarted so the new
/// device takes effect.  AAudio does not support hot-swapping the target
/// device on a live stream.
extern "C" void oboe_stream_set_output_device(int deviceId)
{
    const int previous = g_outputDeviceId;
    if (deviceId == previous) return;  // No change — skip restart.

    g_outputDeviceId = deviceId;
    LOGI("Output device changed: %d -> %d", previous, deviceId);

    // Restart the stream if already running so the new device takes effect.
    if (g_stream != nullptr) {
        const int sr = AAudioStream_getSampleRate(g_stream);
        oboe_stream_stop();
        oboe_stream_start(sr);
    }
}

/// Returns the currently configured output device ID (0 = system default).
extern "C" int oboe_stream_get_output_device(void)
{
    return g_outputDeviceId;
}

// ── FluidSynth convenience wrappers ──────────────────────────────────────────
//
// These thin wrappers maintain API compatibility with native-lib.cpp and hide
// the FluidSynth-specific render trampoline from callers.

extern "C" void oboe_stream_add_synth(fluid_synth_t* synth, int sfId)
{
    oboe_stream_add_source(fluidSynthRenderFn,
                           static_cast<void*>(synth),
                           sfId);
}

/// Returns the current value of the callback-done sequence counter.
///
/// Other translation units (e.g. gfpa_audio_android.cpp) call this to
/// implement a drain-wait: record the value before a mutation, then spin
/// until the counter advances, guaranteeing at least one full audio callback
/// has completed after the mutation and any in-flight snapshot has been retired.
extern "C" uint64_t oboe_stream_callback_done_seq(void)
{
    return g_callbackDoneSeq.load(std::memory_order_acquire);
}

extern "C" void oboe_stream_remove_synth(fluid_synth_t* synth)
{
    // Find the busSlotId that corresponds to this synth pointer, then remove.
    int busSlotId = -1;
    {
        std::lock_guard<std::mutex> lock(g_sourcesMtx);
        for (int i = 0; i < g_sourceCount; ++i) {
            if (g_sources[i].renderFn == fluidSynthRenderFn &&
                g_sources[i].userdata == static_cast<void*>(synth)) {
                busSlotId = g_sources[i].busSlotId;
                break;
            }
        }
    }
    if (busSlotId >= 0) oboe_stream_remove_source(busSlotId);
}

// ── Audio looper transport sync ──────────────────────────────────────────────
//
// Called from Dart via FFI to push the transport state to the audio looper.
// On Linux/macOS this is handled by dvh_set_transport → dvh_jack/mac_update_transport.
// On Android, VstHostService.setTransport is a no-op, so the transport engine
// calls this function directly.

extern "C" void alooper_android_set_transport(
    double bpm, int32_t timeSigNum, int32_t isPlaying, double positionInBeats)
{
    g_transportBpm.store(bpm, std::memory_order_relaxed);
    g_transportTimeSigNum.store(timeSigNum, std::memory_order_relaxed);
    g_transportIsPlaying.store(isPlaying, std::memory_order_relaxed);
    g_transportPositionBeats.store(positionInBeats, std::memory_order_relaxed);
}
