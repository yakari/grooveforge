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
//     4. The non-interleaved L/R mix is interleaved into AAudio's output buffer,
//        with an inaudible keep-alive offset so the stream is never digitally
//        silent (see kKeepAliveAmplitude).
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
#include <dlfcn.h>
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

/// Amplitude of the keep-alive signal that rides along with the output mix,
/// as a linear gain (-50 dBFS).
///
/// Why it exists: USB-C DAC dongles routinely power their headphone amp down
/// after about a second of *digitally silent* input, and bring it back with a
/// soft-start anti-pop ramp. The audible result is that a note played after a
/// pause arrives without its attack. GrooveForge walked into this because the
/// stream stays open and simply writes zeros between notes, which is precisely
/// the pattern those chips watch for. The phone's own speaker has no such
/// logic and neither does the Linux backend, which is why the symptom only
/// ever showed up through a dongle.
///
/// Why this waveform and this level -- both established by measurement on a
/// Galaxy Z Fold 6 with a USB-C-to-jack dongle, not by guesswork:
///
///   - The detector reads the incoming samples, not the analogue output. So all
///     of the energy is placed at Nyquist (24 kHz at 48 kHz): full scale as far
///     as the detector is concerned, outside the audible band, and crushed
///     further by the DAC's reconstruction filter. Confirmed inaudible.
///
///   - It is a level threshold, not a zero-detector. Broadband noise woke the
///     dongle at -40 dBFS and failed at -90 dBFS; a Nyquist square at -90 dBFS
///     failed too, which is what ruled the level in and the waveform out as the
///     reason. -50 dBFS clears the threshold with 40 dB of margin, which gives
///     it a fair chance on dongles with a higher threshold. If one is ever
///     found that still sleeps through this, raising this constant is the knob
///     to turn -- there is a lot of headroom before anything becomes audible.
///
/// Added only to AAudio's output buffer, never to g_mixL/g_mixR: the audio
/// looper records from g_srcCaptureL/R upstream of this, so recordings stay
/// bit-identical.
static constexpr float kKeepAliveAmplitude = 3.1622777e-03f;

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
/// Used ONLY by the audio-looper fill pass: per-source post-chain (wet)
/// snapshot. Holds the audio that comes out of a source AFTER its GFPA
/// insert chain has been applied, so a clip cabled to e.g. Live Input →
/// Audio Harmonizer → Audio Looper records the harmonized output rather
/// than the dry mic. Mirrors the Linux JACK semantic where the post-
/// chain extBuf is written into renderCaptureL/R[m] for each chain
/// source.
///
/// Kept separate from g_srcL/R so the looper read doesn't race with
/// further mutation of the master accumulation buffers.
static float g_srcCaptureL[kMaxSources][kMaxFrames];
static float g_srcCaptureR[kMaxSources][kMaxFrames];

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

/// Sign of the keep-alive sample, flipped every frame so the signal is a
/// Nyquist-rate square wave: DC-free, and above the audible band at any
/// supported sample rate. Audio-thread only, so a plain int is sufficient.
static int g_keepAliveSign = 1;

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
// ── Adaptive buffer size ─────────────────────────────────────────────────────
//
// The stream opens at two bursts, the tightest setting that can work, and on
// this device that is 4 ms of slack. Anything that briefly steals the CPU —
// Flutter's raster thread, another app, a frequency governor step — costs a
// whole callback and the stream underruns, which is heard as a click.
//
// Growing the buffer is the remedy Oboe documents for exactly this ("if
// glitches occur, increasing the Buffer Size is recommended"). It is applied
// only in response to underruns that actually happened, one burst at a time,
// so a device that never glitches keeps the lowest possible latency and one
// that does trades a couple of milliseconds for silence.
//
// Growth only, never shrinkage: a device that glitched once under load will
// do it again, and oscillating the buffer around the threshold would glitch
// on every step down. The ceiling bounds what that can cost.

/// Frames per burst, cached from the stream at open time.
static int32_t g_burstFrames = 0;

/// Buffer size currently requested, in frames.
static int32_t g_bufferFrames = 0;

/// Ceiling for [g_bufferFrames] — eight bursts, about 16 ms on a phone.
static int32_t g_maxBufferFrames = 0;

/// Underrun count at the previous check, to spot a *rise* rather than a
/// non-zero total (every stream underruns a little at startup).
static int32_t g_prevXRuns = 0;

/// Callbacks remaining before the next check. Reading the underrun counter is
/// cheap but not free, and underruns do not need reacting to within 2 ms.
static int32_t g_tuneCountdown = 0;

/// One burst is checked out of every this many.
static constexpr int32_t kTuneInterval = 64;

/// Grows the buffer by one burst if the stream has underrun since the last
/// check. Audio-thread only; allocation-free and non-blocking.
static void tuneBufferSize()
{
    if (g_stream == nullptr || g_burstFrames <= 0) return;
    if (--g_tuneCountdown > 0) return;
    g_tuneCountdown = kTuneInterval;

    const int32_t xruns = AAudioStream_getXRunCount(g_stream);
    if (xruns <= g_prevXRuns) return;   // no new underruns since last check
    g_prevXRuns = xruns;

    if (g_bufferFrames >= g_maxBufferFrames) return;   // already at the ceiling
    g_bufferFrames += g_burstFrames;
    AAudioStream_setBufferSizeInFrames(g_stream, g_bufferFrames);
}

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

        // Apply this source's GFPA insert chain (WAH, EQ, reverb, delay, …)
        // in-place before accumulating into the master mix.
        // This ensures an effect wired to the Theremin cannot reach keyboard or
        // vocoder audio, and vice versa.  No-op when the chain is empty.
        gfpa_android_apply_chain_for_sf(snapshot[s].busSlotId,
                                        g_srcL[s], g_srcR[s], frames);

        // Snapshot the POST-chain (wet) signal so the audio looper can
        // record the effect-processed output. Cabling Live Input → Audio
        // Harmonizer → Audio Looper records the harmonized audio, not
        // the dry mic. Linux does the equivalent via `renderCapture[m]`
        // in dart_vst_host_jack.cpp.
        // Cheap: one 8-byte-per-frame copy per source per block.
        std::memcpy(g_srcCaptureL[s], g_srcL[s],
                    sizeof(float) * static_cast<size_t>(frames));
        std::memcpy(g_srcCaptureR[s], g_srcR[s],
                    sizeof(float) * static_cast<size_t>(frames));

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
                        g_alooperSrcL[c][i] += g_srcCaptureL[s][i];
                        g_alooperSrcR[c][i] += g_srcCaptureR[s][i];
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
    //
    // The keep-alive offset is added here, on the way out, so that the stream
    // is never digitally silent -- see kKeepAliveAmplitude for why.
    for (int i = 0; i < frames; ++i) {
        g_keepAliveSign = -g_keepAliveSign;
        const float keepAlive =
                kKeepAliveAmplitude * static_cast<float>(g_keepAliveSign);

        output[i * 2]     = g_mixL[i] + keepAlive;
        output[i * 2 + 1] = g_mixR[i] + keepAlive;
    }

    // Silence any frames beyond the kMaxFrames cap (should never happen in practice).
    if (numFrames > kMaxFrames) {
        std::memset(output + kMaxFrames * 2, 0,
                    sizeof(float) * static_cast<size_t>(numFrames - kMaxFrames) * 2);
    }

    // ── 5. Adapt the buffer size to what this device can actually keep up
    //       with. Throttled internally; see tuneBufferSize.
    tuneBufferSize();

    // ── 6. Signal drain waiters ───────────────────────────────────────────
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

// ── Stream attributes (API 28 symbols, resolved at runtime) ──────────────────

/// Tags the stream as game audio rather than the default MEDIA usage.
///
/// Why it matters: MEDIA-usage output is routed through the vendor's media
/// post-processing chain on many devices (Samsung/Dolby Atmos, Xiaomi,
/// OnePlus, ...).  That block is a fixed-latency effect stage that can add
/// 100-200 ms on its own and is invisible to AAudio's latency accounting.
/// GAME usage opts out of it, which is what the desktop miniaudio path always
/// did via `playConfig.aaudio.usage = ma_aaudio_usage_game`.
///
/// Why dlsym: AAudioStreamBuilder_setUsage/setContentType were introduced in
/// API 28 while GrooveForge's minSdk is 26.  The NDK marks them hard
/// "unavailable" at API 26 and `__builtin_available` only lifts that when the
/// build enables weak symbol references, which the Gradle/CMake setup here
/// does not.  Looking the symbols up at runtime keeps the API-26 floor intact:
/// on 26/27 both lookups return null and the stream simply keeps the default
/// MEDIA usage.
///
/// [builder] - stream builder to tag; must not be null.
static void applyLowLatencyAttributes(AAudioStreamBuilder* builder)
{
    using SetUsageFn       = void (*)(AAudioStreamBuilder*, aaudio_usage_t);
    using SetContentTypeFn = void (*)(AAudioStreamBuilder*, aaudio_content_type_t);

    // RTLD_DEFAULT searches the already-linked libaaudio.so.  Cached in
    // statics so the lookup cost is paid once per process, not per stream open.
    static auto setUsage = reinterpret_cast<SetUsageFn>(
            dlsym(RTLD_DEFAULT, "AAudioStreamBuilder_setUsage"));
    static auto setContentType = reinterpret_cast<SetContentTypeFn>(
            dlsym(RTLD_DEFAULT, "AAudioStreamBuilder_setContentType"));

    if (setUsage != nullptr)       setUsage(builder, AAUDIO_USAGE_GAME);
    if (setContentType != nullptr) setContentType(builder, AAUDIO_CONTENT_TYPE_MUSIC);
}

// ── Stream diagnostics ────────────────────────────────────────────────────────

/// Logs the configuration AAudio actually granted, alongside what was asked for.
///
/// AAudio downgrades silently. A LOW_LATENCY/EXCLUSIVE request the device cannot
/// satisfy comes back as a NONE/SHARED legacy stream with AAUDIO_OK and no
/// warning, and the difference between the two is the difference between a
/// playable instrument and an unplayable one. Whenever Android "feels laggy",
/// these two lines are the first thing to read:
///
///     adb logcat -s OboeStreamAndroid
///
/// Healthy output on a modern phone looks like burst=96..240,
/// bufferSize = 2 x burst (4-10 ms), performance=LOW_LATENCY, sharing=EXCLUSIVE.
///
/// [requestedSampleRate] — the rate the sources render at, for mismatch checking.
static void logStreamConfig(int requestedSampleRate)
{
    const int32_t rate     = AAudioStream_getSampleRate(g_stream);
    const int32_t burst    = AAudioStream_getFramesPerBurst(g_stream);
    const int32_t bufSize  = AAudioStream_getBufferSizeInFrames(g_stream);
    const int32_t capacity = AAudioStream_getBufferCapacityInFrames(g_stream);

    const aaudio_performance_mode_t perf = AAudioStream_getPerformanceMode(g_stream);
    const aaudio_sharing_mode_t sharing  = AAudioStream_getSharingMode(g_stream);

    // Buffer latency: how much audio sits queued ahead of the device at steady
    // state. This is the part of end-to-end latency this file controls; the
    // device/HAL adds its own on top.
    const double bufferMs = (rate > 0)
            ? 1000.0 * static_cast<double>(bufSize) / static_cast<double>(rate)
            : 0.0;

    const char* perfText =
            (perf == AAUDIO_PERFORMANCE_MODE_LOW_LATENCY) ? "LOW_LATENCY"
          : (perf == AAUDIO_PERFORMANCE_MODE_POWER_SAVING) ? "POWER_SAVING"
          : "NONE";
    const char* sharingText =
            (sharing == AAUDIO_SHARING_MODE_EXCLUSIVE) ? "EXCLUSIVE(MMAP)" : "SHARED";

    LOGI("[Latency] AAudio granted: rate=%d (sources render at %d) burst=%d "
         "bufferSize=%d (%.1f ms) capacity=%d",
         rate, requestedSampleRate, burst, bufSize, bufferMs, capacity);
    LOGI("[Latency] AAudio mode: performance=%s sharing=%s", perfText, sharingText);

    // Each downgrade below is worth tens to hundreds of milliseconds, so they
    // are reported individually rather than as one generic warning.
    if (perf != AAUDIO_PERFORMANCE_MODE_LOW_LATENCY) {
        LOGW("[Latency] LOW_LATENCY was DENIED: the stream is on the normal "
             "mixer path and will feel laggy no matter how small the buffer is.");
    }
    if (sharing != AAUDIO_SHARING_MODE_EXCLUSIVE) {
        LOGW("[Latency] EXCLUSIVE (MMAP) was DENIED: running on a shared "
             "AudioTrack stream, which adds the AudioFlinger mixer and HAL "
             "buffers on top of the %.1f ms above.", bufferMs);
    }
    if (rate != requestedSampleRate) {
        LOGW("[Latency] Sample-rate mismatch: device runs at %d Hz but sources "
             "render at %d Hz, so AudioFlinger is resampling every block "
             "(costs latency and disqualifies the fast path).",
             rate, requestedSampleRate);
    }
}

// ── Public API ────────────────────────────────────────────────────────────────

/// Opens, configures and starts the shared output stream in one sharing mode.
///
/// Returns AAUDIO_OK with g_stream live, or the failing result with g_stream
/// left null and any partially-opened stream already closed, so the caller can
/// simply try again with a different mode.
static aaudio_result_t openAndStartStream(int sampleRate,
                                          aaudio_sharing_mode_t sharingMode)
{
    AAudioStreamBuilder* builder = nullptr;
    aaudio_result_t result = AAudio_createStreamBuilder(&builder);
    if (result != AAUDIO_OK) {
        LOGE("AAudio_createStreamBuilder: %s", AAudio_convertResultToText(result));
        return result;
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

    // ── Low-latency request ────────────────────────────────────────────────
    //
    // LOW_LATENCY + EXCLUSIVE asks the platform for an MMAP "fast path" stream
    // that bypasses AudioFlinger's normal mixer. Neither is guaranteed, and the
    // downgrade is not always the silent one AAudio documents: when another app
    // already holds the device's single exclusive MMAP endpoint, the open
    // *succeeds* in MMAP mode and requestStart() is what then fails, with
    // AAUDIO_ERROR_DISCONNECTED. oboe_stream_start() recovers from that by
    // calling this function again in SHARED mode; each call attempts exactly
    // the one mode it was handed. logStreamConfig() reports what was actually
    // granted instead of letting us assume.
    AAudioStreamBuilder_setPerformanceMode(
            builder, AAUDIO_PERFORMANCE_MODE_LOW_LATENCY);
    AAudioStreamBuilder_setSharingMode(builder, sharingMode);

    // Declare the stream as game audio instead of the default MEDIA usage.
    //
    // MEDIA-usage output is routed through the vendor's media post-processing
    // chain on many devices (Samsung/Dolby Atmos, Xiaomi, OnePlus, ...). That
    // block is a fixed-latency effect stage worth 100-200 ms on its own, and it
    // is invisible to AAudio's own latency accounting. GAME usage opts out of
    // it. The desktop miniaudio path already did this via
    // `playConfig.aaudio.usage = ma_aaudio_usage_game`; the setting was lost
    // when Android moved onto this shared bus.
    //
    // Resolved at runtime — see applyLowLatencyAttributes().
    applyLowLatencyAttributes(builder);

    // NOTE: buffer *capacity* is deliberately left unspecified.
    //
    // It used to be pinned to kMaxFrames (4096) on the assumption that this
    // capped the callback block size. It does not — that is
    // AAudioStreamBuilder_setFramesPerDataCallback(). Requesting a capacity
    // costs latency on both AAudio paths:
    //   • MMAP   — AudioStreamInternal::open() seeds the initial buffer size to
    //     capacity/2, i.e. 2048 frames ~ 43 ms at 48 kHz.
    //   • Legacy — the requested capacity is handed straight to AudioTrack as
    //     its frameCount (4096 frames ~ 85 ms) *and* suppresses the "size the
    //     buffer as N bursts" shortcut in AudioStreamTrack::open(), which only
    //     fires when the capacity is left at 0.
    // Unspecified lets the platform choose a burst-aligned capacity; the
    // `frames` clamp in audioCallback still protects the fixed-size buffers.

    AAudioStreamBuilder_setDataCallback(builder, audioCallback, nullptr);
    AAudioStreamBuilder_setErrorCallback(builder, errorCallback, nullptr);

    result = AAudioStreamBuilder_openStream(builder, &g_stream);
    AAudioStreamBuilder_delete(builder);

    if (result != AAUDIO_OK) {
        LOGE("AAudioStreamBuilder_openStream: %s", AAudio_convertResultToText(result));
        g_stream = nullptr;
        return result;
    }

    // ── Buffer size: two bursts ──────────────────────────────────────────
    //
    // Capacity is what the buffer *can* hold; buffer size is the high-water
    // mark the stream actually keeps filled, and it alone sets output latency.
    // AAudio never picks a small default for it, so it has to be set
    // explicitly. Two bursts is the standard Oboe recommendation — one burst
    // draining to the device while the next is being rendered.
    const int32_t burst = AAudioStream_getFramesPerBurst(g_stream);
    if (burst > 0) {
        AAudioStream_setBufferSizeInFrames(g_stream, burst * 2);
    }

    // Seed the adaptive tuner. Starting from the same two bursts means a
    // device that never underruns behaves exactly as it did before.
    g_burstFrames  = burst;
    g_bufferFrames = burst * 2;
    const int32_t capacity = AAudioStream_getBufferCapacityInFrames(g_stream);
    g_maxBufferFrames = burst * 8;
    if (capacity > 0 && g_maxBufferFrames > capacity) g_maxBufferFrames = capacity;
    g_prevXRuns = 0;
    g_tuneCountdown = kTuneInterval;

    // Record the rate the device actually granted. FluidSynth's render rate and
    // the audio-looper bar-sync maths both depend on it — a stale 48000 on a
    // 44.1 kHz device detunes every voice and drifts every loop.
    const int32_t grantedRate = AAudioStream_getSampleRate(g_stream);
    if (grantedRate > 0) g_sampleRate = grantedRate;

    result = AAudioStream_requestStart(g_stream);
    if (result != AAUDIO_OK) {
        LOGE("AAudioStream_requestStart: %s", AAudio_convertResultToText(result));
        AAudioStream_close(g_stream);
        g_stream = nullptr;
        return result;
    }

    return AAUDIO_OK;
}

extern "C" void oboe_stream_start(int sampleRate)
{
    if (g_stream != nullptr) return; // Stream already running.

    // Try the MMAP fast path, then fall back to a shared stream.
    //
    // Without the fallback a single failure here is permanent and silent: the
    // stream is closed, nothing drives the audio callback, and every source
    // stops being rendered until the app restarts. FluidSynth in particular
    // keeps accepting note-ons whose events are never consumed, so its
    // ringbuffer fills and it starts logging "Failed to allocate a synthesis
    // process" — a symptom far from this cause. Any other app holding the
    // device's exclusive MMAP endpoint is enough to trigger it.
    aaudio_result_t result =
            openAndStartStream(sampleRate, AAUDIO_SHARING_MODE_EXCLUSIVE);

    if (result != AAUDIO_OK) {
        LOGW("Exclusive (MMAP) stream unavailable (%s) — retrying in SHARED "
             "mode. Higher latency, but working audio.",
             AAudio_convertResultToText(result));
        result = openAndStartStream(sampleRate, AAUDIO_SHARING_MODE_SHARED);
    }

    if (result != AAUDIO_OK) {
        LOGE("AAudio stream could not be started in any sharing mode: %s",
             AAudio_convertResultToText(result));
        return;
    }

    logStreamConfig(sampleRate);
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

/// Returns the sample rate the AAudio stream is actually running at.
///
/// Callers must create their sound sources at this rate: any mismatch means
/// AudioFlinger resamples every block. Returns the last granted rate (or the
/// 48000 default when the stream has never been opened).
extern "C" int32_t oboe_stream_get_sample_rate(void)
{
    return g_sampleRate;
}

/// Returns the number of underruns (xruns) the stream has accumulated.
///
/// A steadily climbing count means the render callback is missing its deadline
/// — too much DSP for the current buffer size. A flat count with audible lag
/// means the opposite: the buffer is simply too large. Returns -1 when the
/// stream is not open.
extern "C" int32_t oboe_stream_get_xrun_count(void)
{
    if (g_stream == nullptr) return -1;
    return AAudioStream_getXRunCount(g_stream);
}

extern "C" void alooper_android_set_transport(
    double bpm, int32_t timeSigNum, int32_t isPlaying, double positionInBeats)
{
    g_transportBpm.store(bpm, std::memory_order_relaxed);
    g_transportTimeSigNum.store(timeSigNum, std::memory_order_relaxed);
    g_transportIsPlaying.store(isPlaying, std::memory_order_relaxed);
    g_transportPositionBeats.store(positionInBeats, std::memory_order_relaxed);
}
