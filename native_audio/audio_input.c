#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <math.h>
#include <stdio.h>
#include <stdbool.h>
#include <time.h>

#ifdef __ANDROID__
#include <android/log.h>
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "GrooveForgeAudio", __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "GrooveForgeAudio", __VA_ARGS__)
#else
#define LOGE(...) printf(__VA_ARGS__)
#define LOGI(...) printf(__VA_ARGS__)
#endif

#define MAX_POLYPHONY 16
#define SAMPLE_RATE 48000
#define CHANNELS 1
#define NUM_BANDS 32

// --- Vocoder DSP State ---
typedef struct {
    float a0, a1, a2, b1, b2;
    float z1, z2;
} Biquad;

typedef struct {
    Biquad modFilter;
    Biquad carFilter;
    float envelope;
} VocoderBand;

static VocoderBand bands[NUM_BANDS];

// Envelope follower release coefficient (approx 20ms)
static float envRelease = 0.0f;

// --- Oscillator State ---
typedef struct {
    bool active;
    int midiKey;
    float frequency;
    float phase;
    float phase2; // Unison detune 1
    float phase3; // Unison detune 2
    float velocity;
    float envelope;
    int releaseSamples;
    float filterState; // Used for glottal pulse low-pass
} Oscillator;

// --- Vocoder Adjustable Parameters ---
int g_vocoderWaveform = 0;          // 0 = Sawtooth, 1 = Square/PWM, 2 = Sine (Neutral)
float g_vocoderNoiseMix = 0.05f;    // Amount of white noise added to carrier for consonant intelligibility
float g_vocoderEnvRelease = 0.02f;  // Envelope follower release time (lower = faster)
static float g_inputPeak = 0.0f;
static float g_outputPeak = 0.0f;
static float g_inputGain = 1.0f;
static int g_selectedCaptureDeviceIndex = -1; // -1 means default
static int g_androidDeviceId = -1; // Specific Android Device ID for AAudio
static int g_androidOutputDeviceId = -1; // Specific Android Output Device ID for AAudio

// --- Latency Debug State ---
static volatile int g_latencyDebugEnabled = 0;
// Monotonic timestamp (ns) of the start of the most recent callback
static volatile int64_t g_lastCallbackStartNs = 0;
// Most-recent measured period between consecutive callbacks (ns)
static volatile int64_t g_lastCallbackPeriodNs = 0;
// Accumulator for rolling average over ~1s
static int64_t g_periodAccumNs = 0;
static int g_periodCount = 0;
// Approximate number of callbacks per second (updated on each measurement)
static int g_callbacksPerSec = 1;
static int g_glitchCounter = 0;
static int g_engineUnhealthy = 0;

static int64_t _get_monotonic_ns(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000000LL + ts.tv_nsec;
}

// Global state
static ma_context context;
static ma_device device;          // Playback-only (was duplex)
static bool isInitialized = false;
static Oscillator voices[MAX_POLYPHONY];

// --- Dedicated Mic Capture Ring Buffer ---
// A separate capture device feeds a ring buffer that the playback callback
// reads from. This decouples capture from the duplex clock-alignment overhead
// that was adding 300-400ms of delay on this Samsung device.
#define MIC_RING_FRAMES 8192   // ~170ms of headroom at 48kHz (power-of-2 for fast modulo)
#define MIC_RING_MASK   (MIC_RING_FRAMES - 1)
static float          g_micRing[MIC_RING_FRAMES];
// Written by mic capture callback, read by playback callback.
// Accessed from two threads — plain volatile is sufficient for a single-producer
// single-consumer ring on ARM (store-release / load-acquire semantics).
static volatile ma_uint32 g_micWriteCursor = 0;

static ma_device g_micDevice;     // Dedicated capture device
static bool g_micDeviceRunning = false;

// --- Latency Click Test ---
// When latency debug is on and a note is pressed, inject a short click
// directly into pOutput so we can measure RAW OUTPUT latency independently
// of the mic path. If click is also delayed the output hardware path is slow.
static volatile int g_clickCounter = 0;  // > 0 → mix click pulse for this many samples

// --- DSP Helpers ---

// Simple DC Blocker / High-pass at approx 80Hz to remove rumble
static float pre_filter_mic(float in) {
    static float prev_in = 0.0f;
    static float prev_out = 0.0f;
    // R characterizes the cutoff frequency. 0.99 is roughly good for ignoring DC offset.
    float out = in - prev_in + 0.95f * prev_out;
    prev_in = in;
    prev_out = out;
    return out;
}

// Simple soft clipper approximation for tanh 
static float soft_clip(float x) {
    if (x <= -1.0f) return -1.0f;
    if (x >= 1.0f) return 1.0f;
    return x - (x * x * x) / 3.0f;
}

// Compute Biquad Bandpass coefficients (constant skirt gain, peak gain = Q)
static void calculateBandpass(Biquad* filter, float f0, float q) {
    float w0 = 2.0f * M_PI * f0 / SAMPLE_RATE;
    float alpha = sinf(w0) / (2.0f * q);
    
    // Constant peak gain variant:
    float a0 = alpha; 
    float a1 = 0.0f;
    float a2 = -alpha;
    float b0 = 1.0f + alpha;
    float b1 = -2.0f * cosf(w0);
    float b2 = 1.0f - alpha;

    filter->a0 = a0 / b0;
    filter->a1 = a1 / b0;
    filter->a2 = a2 / b0;
    filter->b1 = b1 / b0;
    filter->b2 = b2 / b0;
    filter->z1 = 0.0f;
    filter->z2 = 0.0f;
}

static float processBiquad(Biquad* filter, float in) {
    in += 1e-15f; // Anti-denormal
    float out = in * filter->a0 + filter->z1;
    filter->z1 = in * filter->a1 - out * filter->b1 + filter->z2;
    filter->z2 = in * filter->a2 - out * filter->b2;
    return out;
}

static float noteToFreq(int midiNote) {
    return 440.0f * powf(2.0f, (midiNote - 69) / 12.0f);
}

// Generates a simple band-limited-ish sawtooth
static float renderSawtooth(Oscillator* osc) {
    float sample = (2.0f * osc->phase) - 1.0f;
    osc->phase += (osc->frequency / SAMPLE_RATE);
    if (osc->phase >= 1.0f) {
        osc->phase -= 1.0f;
    }
    return sample;
}

// Render Oscillator (Polyphonic Carrier)
static float renderOscillator(Oscillator* osc) {
    float sample = 0.0f;
    
    if (g_vocoderWaveform == 0) {
        // Sawtooth
        sample = osc->phase * 2.0f - 1.0f; 
        osc->phase += (osc->frequency / SAMPLE_RATE);
        if (osc->phase >= 1.0f) osc->phase -= 1.0f;
    } else if (g_vocoderWaveform == 1) {
        // Square
        sample = (osc->phase < 0.5f) ? 1.0f : -1.0f;
        osc->phase += (osc->frequency / SAMPLE_RATE);
        if (osc->phase >= 1.0f) osc->phase -= 1.0f;
    } else {
        // Neutral (Choral Super-Vocal Ensemble)
        // 3 detuned glottal pulses layered together with natural pitch spread.
        float raw1 = (osc->phase < 0.08f) ? 2.0f : -0.2f;
        float raw2 = (osc->phase2 < 0.08f) ? 2.0f : -0.2f;
        float raw3 = (osc->phase3 < 0.08f) ? 2.0f : -0.2f;
        
        float mix = (raw1 + raw2 + raw3) * 0.33f;
        
        // Gentle lowpass filter for body warmth
        osc->filterState += 0.3f * (mix - osc->filterState);
        sample = osc->filterState; 
        
        // Advance phases with slight natural detuning (-10 cents and +10 cents)
        osc->phase += (osc->frequency / SAMPLE_RATE);
        osc->phase2 += ((osc->frequency * 0.994f) / SAMPLE_RATE);
        osc->phase3 += ((osc->frequency * 1.006f) / SAMPLE_RATE);
        
        if (osc->phase >= 1.0f) osc->phase -= 1.0f;
        if (osc->phase2 >= 1.0f) osc->phase2 -= 1.0f;
        if (osc->phase3 >= 1.0f) osc->phase3 -= 1.0f;
    }
    
    return sample;
}

// --- Dedicated Mic Capture Callback ---
// This fires on a dedicated high-priority capture thread (short period = 256 frames
// = 5.3ms). Samples are pushed to g_micRing so the playback callback always
// has access to the freshest mic data without duplex clock-alignment lag.
void mic_capture_callback(ma_device* pDevice, void* pOutput, const void* pInput,
                          ma_uint32 frameCount)
{
    const float* pIn = (const float*)pInput;
    if (!pIn || frameCount == 0) return;

    ma_uint32 writePos = g_micWriteCursor;  // snapshot
    for (ma_uint32 i = 0; i < frameCount; i++) {
        g_micRing[(writePos + i) & MIC_RING_MASK] = pIn[i];
    }
    // Publish the new write position (store-release on ARM)
    __atomic_store_n(&g_micWriteCursor, (writePos + frameCount) & MIC_RING_MASK,
                     __ATOMIC_RELEASE);

    // Update raw VU peak from dedicated capture thread
    for (ma_uint32 i = 0; i < frameCount; i++) {
        float a = fabsf(pIn[i]) * g_inputGain;
        if (a > g_inputPeak) g_inputPeak = a;
    }
}

// Data callback for full-duplex audio processing
// Main audio loop.
// Optimization: move voice counting OUT of the sample loop for speed.
void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    if (g_latencyDebugEnabled) {
        int64_t now = _get_monotonic_ns();
        if (g_lastCallbackStartNs != 0) {
            int64_t period = now - g_lastCallbackStartNs;
            g_lastCallbackPeriodNs = period;
            g_periodAccumNs += period;
            g_periodCount++;

            // --- Jitter/Glitch Detection ---
            double expectedMs = (double)frameCount / SAMPLE_RATE * 1000.0;
            double actualMs = (double)period / 1e6;
            if (actualMs > expectedMs * 1.5) {
                g_glitchCounter++;
                if (g_glitchCounter > 10) g_engineUnhealthy = 1;
            } else if (g_glitchCounter > 0) {
                g_glitchCounter--;
                if (g_glitchCounter == 0) g_engineUnhealthy = 0;
            }

            double periodSec = (double)frameCount / SAMPLE_RATE;
            int cbPerSec = (int)(1.0 / periodSec + 0.5);
            if (cbPerSec < 1) cbPerSec = 1;
            g_callbacksPerSec = cbPerSec;

            if (g_periodCount >= cbPerSec) {
                double avgPeriodMs = (double)(g_periodAccumNs / g_periodCount) / 1e6;
                double bufferMs = (double)frameCount / SAMPLE_RATE * 1000.0;
                LOGI("[Latency] avg_callback_period=%.2fms  buffer=%.2fms  glitches=%d status=%s",
                     avgPeriodMs, bufferMs, g_glitchCounter, g_engineUnhealthy ? "UNHEALTHY" : "OK");
                g_periodAccumNs = 0;
                g_periodCount = 0;
            }
        }
        g_lastCallbackStartNs = now;
    }

    ma_uint32 writePos = __atomic_load_n(&g_micWriteCursor, __ATOMIC_ACQUIRE);
    ma_uint32 readStart = (writePos - frameCount) & MIC_RING_MASK;
    float* pOut = (float*)pOutput;
    float inPeak = 0.0f;
    float outPeak = 0.0f;

    static float squelchEnv = 0.0f;
    const float squelchThreshold = 0.003f;
    const float squelchAttack = 0.05f;
    const float squelchRelease = 0.002f;

    static float sibilanceZ1 = 0.0f;
    static float sibilanceZ2 = 0.0f;
    const float hp_b0 = 0.65f, hp_b1 = -1.3f, hp_b2 = 0.65f, hp_a1 = -0.8f, hp_a2 = 0.2f;

    // PRE-LOOP: Count active voices once per callback
    int activeVoiceCount = 0;
    for (int v = 0; v < MAX_POLYPHONY; ++v) {
        if (voices[v].active || voices[v].releaseSamples > 0) activeVoiceCount++;
    }

    for (ma_uint32 i = 0; i < frameCount; ++i) {
        float micInput = g_micRing[(readStart + i) & MIC_RING_MASK] * g_inputGain;
        float absRawMic = fabsf(micInput);
        if (absRawMic > inPeak) inPeak = absRawMic;

        float synthMix = 0.0f;
        if (activeVoiceCount > 0) {
            for (int v = 0; v < MAX_POLYPHONY; ++v) {
                Oscillator* osc = &voices[v];
                if (osc->active || osc->releaseSamples > 0) {
                    if (!osc->active && osc->releaseSamples > 0) {
                        osc->envelope -= (1.0f / 240.0f);
                        osc->releaseSamples--;
                        if (osc->envelope <= 0.0f) { osc->envelope = 0.0f; osc->releaseSamples = 0; }
                    }
                    synthMix += renderOscillator(osc) * (osc->velocity / 127.0f) * osc->envelope * 0.8f;
                }
            }
        }

        micInput = pre_filter_mic(micInput);

        if (activeVoiceCount == 0) {
            if (absRawMic > squelchEnv) squelchEnv = squelchEnv * (1.0f - squelchAttack) + absRawMic * squelchAttack;
            else squelchEnv = squelchEnv * (1.0f - squelchRelease) + absRawMic * squelchRelease;
            if (squelchEnv < squelchThreshold) { micInput = 0.0f; squelchEnv = 0.0f; }
        } else {
            squelchEnv = absRawMic;
        }

        for (int b = 0; b < NUM_BANDS; ++b) {
            float modSignal = processBiquad(&bands[b].modFilter, micInput);
            float absMod = fabsf(modSignal);
            if (absMod > bands[b].envelope) bands[b].envelope = bands[b].envelope * (1.0f - 0.01f) + absMod * 0.01f;
            else bands[b].envelope = bands[b].envelope * (1.0f - g_vocoderEnvRelease) + absMod * g_vocoderEnvRelease;
            if (bands[b].envelope < 1e-6f) bands[b].envelope = 0.0f;
        }

        float vocoderOutput = 0.0f;
        if (activeVoiceCount > 0) {
            for (int b = 0; b < NUM_BANDS; ++b) {
                vocoderOutput += processBiquad(&bands[b].carFilter, synthMix) * bands[b].envelope;
            }
            vocoderOutput *= 20.0f;
            float sibilance = micInput * hp_b0 + sibilanceZ1;
            sibilanceZ1 = micInput * hp_b1 - sibilance * hp_a1 + sibilanceZ2;
            sibilanceZ2 = micInput * hp_b2 - sibilance * hp_a2;
            vocoderOutput += sibilance * g_vocoderNoiseMix * 2.5f;
        } else {
            float sibilance = micInput * hp_b0 + sibilanceZ1;
            sibilanceZ1 = micInput * hp_b1 - sibilance * hp_a1 + sibilanceZ2;
            sibilanceZ2 = micInput * hp_b2 - sibilance * hp_a2;
        }

        vocoderOutput = soft_clip(vocoderOutput) * 0.95f;

        if (g_latencyDebugEnabled && g_clickCounter > 0) {
            vocoderOutput += 0.6f * (1.0f - (float)(240 - g_clickCounter) / 240.0f);
            g_clickCounter--;
        }

        float absOut = fabsf(vocoderOutput);
        if (absOut > outPeak) outPeak = absOut;
        if (pOut) pOut[i] = vocoderOutput;
    }

    if (inPeak > g_inputPeak) g_inputPeak = inPeak;
    if (outPeak > g_outputPeak) g_outputPeak = outPeak;
}

#ifdef _WIN32
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// --- FFI Interface ---

EXPORT void VocoderNoteOn(int key, int velocity) {
    // Find an empty voice or steal the oldest
    for (int i = 0; i < MAX_POLYPHONY; ++i) {
        if (!voices[i].active && voices[i].releaseSamples == 0) {
            voices[i].active = true;
            voices[i].midiKey = key;
            voices[i].frequency = noteToFreq(key);
            voices[i].velocity = velocity;
            voices[i].phase = ((float)rand() / (float)RAND_MAX);
            voices[i].phase2 = ((float)rand() / (float)RAND_MAX);
            voices[i].phase3 = ((float)rand() / (float)RAND_MAX);
            voices[i].envelope = 1.0f;
            voices[i].releaseSamples = 0;
            voices[i].filterState = 0.0f;
            // Latency click test: inject a brief 5ms click into the output so the
            // user can hear when this note-on reaches the audio thread.
            // Helps distinguish output-path latency from mic-path latency.
            if (g_latencyDebugEnabled) g_clickCounter = 240;
            return;
        }
    }
}

EXPORT void VocoderNoteOff(int key) {
    for (int i = 0; i < MAX_POLYPHONY; ++i) {
        if (voices[i].active && voices[i].midiKey == key) {
            voices[i].active = false;
            voices[i].releaseSamples = 240; // ~5ms release tail
        }
    }
}

// Initialize Vocoder DSP Filters dynamically
static void init_vocoder_bands(float qFactor) {
    float minFreq = 80.0f;
    float maxFreq = 12000.0f;
    for (int b = 0; b < NUM_BANDS; ++b) {
        // Logarithmic spacing
        float freq = minFreq * powf(maxFreq / minFreq, (float)b / (NUM_BANDS - 1));
        // Q factor controls overlap.
        calculateBandpass(&bands[b].modFilter, freq, qFactor);
        calculateBandpass(&bands[b].carFilter, freq, qFactor);
        // Do not reset envelope here to prevent audio pops if changed while playing
    }
}

// Initialize and start audio — separate capture + playback devices.
// This decouples the capture clock from the playback clock, eliminating the
// TimeSeries sync overhead that was adding 300-400ms of mic onset delay on Android.
EXPORT int start_audio_capture() {
    if (isInitialized) return 0;

    // Initialize Vocoder DSP
    envRelease = expf(-1.0f / (SAMPLE_RATE * 0.02f));
    init_vocoder_bands(8.0f);
    for (int b = 0; b < NUM_BANDS; ++b) bands[b].envelope = 0.0f;
    for (int i = 0; i < MAX_POLYPHONY; ++i) { voices[i].active = false; voices[i].releaseSamples = 0; }

    // Clear the mic ring buffer
    for (int i = 0; i < MIC_RING_FRAMES; i++) g_micRing[i] = 0.0f;
    g_micWriteCursor = 0;

    ma_result result;
    ma_context_config ctxConfig = ma_context_config_init();
    result = ma_context_init(NULL, 0, &ctxConfig, &context);
    if (result != MA_SUCCESS) {
        LOGE("Failed to initialize context: %d\n", result);
        return -1;
    }

    // ---- 1. Dedicated Capture Device (256 frames = 5.3ms per callback) ----
    // Runs independently from playback. Mic samples go to the ring buffer.
    ma_device_config capConfig = ma_device_config_init(ma_device_type_capture);
    capConfig.performanceProfile = ma_performance_profile_low_latency;
    capConfig.capture.format     = ma_format_f32;
    capConfig.capture.channels   = CHANNELS;
    capConfig.sampleRate         = SAMPLE_RATE;
    capConfig.dataCallback       = mic_capture_callback;
    capConfig.periodSizeInFrames = 256;   // 5.3ms — smallest practical buffer
    capConfig.periods            = 2;

#ifdef __ANDROID__
    capConfig.aaudio.inputPreset    = ma_aaudio_input_preset_voice_performance;
    capConfig.opensl.recordingPreset = ma_opensl_recording_preset_voice_unprocessed;
#endif

    // Device selection: use the same logic as before
    ma_device_info* pCaptureDeviceInfos;
    ma_uint32 captureDeviceCount;
    ma_result devResult = ma_context_get_devices(&context, NULL, NULL, &pCaptureDeviceInfos, &captureDeviceCount);

    static ma_device_id customDeviceId;
    bool useCustomId = false;
#ifdef __ANDROID__
    if (g_androidDeviceId > 0) {
        customDeviceId.aaudio = g_androidDeviceId;
        customDeviceId.opensl = (ma_uint32)g_androidDeviceId;
        useCustomId = true;
    }
#endif
    if (useCustomId) {
        capConfig.capture.pDeviceID = &customDeviceId;
        LOGI("GrooveForge: Opening Capture Device with specific ID: %d", g_androidDeviceId);
    } else if (devResult == MA_SUCCESS && g_selectedCaptureDeviceIndex >= 0 &&
               (ma_uint32)g_selectedCaptureDeviceIndex < captureDeviceCount) {
        capConfig.capture.pDeviceID = &pCaptureDeviceInfos[g_selectedCaptureDeviceIndex].id;
        LOGI("GrooveForge: Opening Capture Device by index: %d", g_selectedCaptureDeviceIndex);
    } else {
        capConfig.capture.pDeviceID = NULL;
        LOGI("GrooveForge: Opening Default Capture Device");
    }

    result = ma_device_init(&context, &capConfig, &g_micDevice);
    if (result != MA_SUCCESS) {
        LOGE("Failed to init capture device: %d", result);
        ma_context_uninit(&context);
        return -2;
    }
    result = ma_device_start(&g_micDevice);
    if (result != MA_SUCCESS) {
        LOGE("Failed to start capture device: %d", result);
        ma_device_uninit(&g_micDevice);
        ma_context_uninit(&context);
        return -3;
    }
    g_micDeviceRunning = true;

    ma_uint32 capFrames  = g_micDevice.capture.internalPeriodSizeInFrames;
    ma_uint32 capPeriods = g_micDevice.capture.internalPeriods;
    double capLatencyMs  = (double)(capFrames * capPeriods) / SAMPLE_RATE * 1000.0;
    LOGI("[Latency] CAPTURE device: %u frames x %u periods = %.1fms (requested 256)",
         capFrames, capPeriods, capLatencyMs);

    // ---- 2. Playback-Only Device (512 frames = 10.7ms per callback) ----
    ma_device_config playConfig = ma_device_config_init(ma_device_type_playback);
    playConfig.performanceProfile        = ma_performance_profile_low_latency;
    playConfig.playback.format           = ma_format_f32;
    playConfig.playback.channels         = CHANNELS;
    playConfig.sampleRate                = SAMPLE_RATE;
    playConfig.dataCallback              = data_callback;
    playConfig.periodSizeInFrames        = 512;
    playConfig.periods                   = 3;
    playConfig.noPreSilencedOutputBuffer = MA_TRUE;
    playConfig.noClip                    = MA_TRUE;

#ifdef __ANDROID__
    static ma_device_id customOutputDeviceId;
    bool useCustomOutputId = false;
    if (g_androidOutputDeviceId > 0) {
        customOutputDeviceId.aaudio = g_androidOutputDeviceId;
        customOutputDeviceId.opensl = (ma_uint32)g_androidOutputDeviceId;
        useCustomOutputId = true;
    }
    if (useCustomOutputId) {
        playConfig.playback.pDeviceID = &customOutputDeviceId;
        LOGI("GrooveForge: Opening Playback Device with specific ID: %d", g_androidOutputDeviceId);
    } else {
        playConfig.playback.pDeviceID = NULL;
        LOGI("GrooveForge: Opening Default Playback Device");
    }
#else
    playConfig.playback.pDeviceID = NULL;
#endif

    result = ma_device_init(&context, &playConfig, &device);
    if (result != MA_SUCCESS) {
        LOGE("Failed to init playback device: %d", result);
        ma_device_stop(&g_micDevice); ma_device_uninit(&g_micDevice);
        ma_context_uninit(&context);
        return -4;
    }
    result = ma_device_start(&device);
    if (result != MA_SUCCESS) {
        LOGE("Failed to start playback device: %d", result);
        ma_device_uninit(&device);
        ma_device_stop(&g_micDevice); ma_device_uninit(&g_micDevice);
        ma_context_uninit(&context);
        return -5;
    }

    ma_uint32 playFrames  = device.playback.internalPeriodSizeInFrames;
    ma_uint32 playPeriods = device.playback.internalPeriods;
    double playLatencyMs  = (double)(playFrames * playPeriods) / SAMPLE_RATE * 1000.0;
    LOGI("[Latency] PLAYBACK device: %u frames x %u periods = %.1fms",
         playFrames, playPeriods, playLatencyMs);
    LOGI("[Latency] Est. capture overhead: %.1fms — playback overhead: %.1fms — total budget: ~%.0fms",
         capLatencyMs, playLatencyMs, capLatencyMs + playLatencyMs);
    LOGI("[Latency] TIP: enable latency debug then press a key to hear the click test (output-only check)");

    isInitialized = true;
    return 0; // Success
}

EXPORT void stop_audio_capture() {
    if (!isInitialized) return;

    if (g_micDeviceRunning) {
        ma_device_stop(&g_micDevice);
        ma_device_uninit(&g_micDevice);
        g_micDeviceRunning = false;
    }

    ma_device_stop(&device);
    ma_device_uninit(&device);
    ma_context_uninit(&context);

    isInitialized = false;
    g_inputPeak = 0.0f;
    g_outputPeak = 0.0f;
}

EXPORT float getInputPeakLevel() {
    float peak = g_inputPeak;
    g_inputPeak *= 0.8f; // Decaying peak for meters
    return peak;
}

EXPORT float getOutputPeakLevel() {
    float peak = g_outputPeak;
    g_outputPeak *= 0.8f;
    return peak;
}

EXPORT void setVocoderParameters(int waveform, float noiseMix, float envRelease, float bandwidth) {
    g_vocoderWaveform = waveform;
    g_vocoderNoiseMix = noiseMix * 10.0f; // Scale 0.0-1.0 up to 0.0-10.0 for audible noise presence
    // Map a nice 0.0 - 1.0 value from the UI to the actual filter coefficient math
    // 0.0 -> very slow (0.0001), 1.0 -> very fast (0.05)
    g_vocoderEnvRelease = 0.0001f + (envRelease * 0.0499f);
    
    // Map bandwidth 0.0 to 1.0 to Q factor 2.0 (blurry) to 30.0 (sharp robotic)
    float qFactor = 2.0f + (bandwidth * 28.0f);
    init_vocoder_bands(qFactor);
}

// --- NEW PER-DEVICE AND GAIN CONTROL ---


EXPORT int get_capture_device_count() {
    if (!isInitialized) {
        // We need a context to list devices. If not started, temporarily init one?
        // Actually, start_audio_capture is usually called when vocoder is needed.
        // Let's assume we can init context if needed.
        ma_result result = ma_context_init(NULL, 0, NULL, &context);
        if (result != MA_SUCCESS) return 0;
    }

    ma_device_info* pCaptureDeviceInfos;
    ma_uint32 captureDeviceCount;
    ma_result result = ma_context_get_devices(&context, NULL, NULL, &pCaptureDeviceInfos, &captureDeviceCount);
    if (result != MA_SUCCESS) return 0;

    return (int)captureDeviceCount;
}

EXPORT const char* get_capture_device_name(int index) {
    ma_device_info* pCaptureDeviceInfos;
    ma_uint32 captureDeviceCount;
    ma_result result = ma_context_get_devices(&context, NULL, NULL, &pCaptureDeviceInfos, &captureDeviceCount);
    if (result != MA_SUCCESS || (ma_uint32)index >= captureDeviceCount) return "Unknown";

    return pCaptureDeviceInfos[index].name;
}

EXPORT void set_capture_device_config(int index, float gain, int androidDeviceId, int androidOutputDeviceId) {
    g_selectedCaptureDeviceIndex = index;
    g_inputGain = gain;
    g_androidDeviceId = androidDeviceId;
    g_androidOutputDeviceId = androidOutputDeviceId;

    LOGI("GrooveForge: Device config updated (Index: %d, InID: %d, OutID: %d). Restart from Dart if needed.\n",
         index, androidDeviceId, androidOutputDeviceId);
}


// --- Latency Debug FFI Exports ---

EXPORT void set_latency_debug(int enabled) {
    g_latencyDebugEnabled = enabled;
    if (enabled) {
        g_lastCallbackStartNs = 0;
        g_periodAccumNs = 0;
        g_periodCount = 0;
        LOGI("[Latency] debug logging ENABLED");
    } else {
        LOGI("[Latency] debug logging DISABLED");
    }
}

EXPORT float get_last_callback_period_ms(void) {
    if (g_lastCallbackPeriodNs == 0) return 0.0f;
    return (float)((double)g_lastCallbackPeriodNs / 1e6);
}

/// Returns the engine health status.
/// 0 = OK, 1 = UNHEALTHY (too many glitches detected)
EXPORT int get_engine_health(void) {
    return g_engineUnhealthy;
}

// Deprecated, mapped to input for backward compat if needed
EXPORT float getPeakLevel() {
    return getInputPeakLevel();
}
EXPORT float get_vocoder_input_peak() {
    return getInputPeakLevel();
}

EXPORT float get_vocoder_output_peak() {
    return getOutputPeakLevel();
}
