#define MA_API static
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

#define PSOLA_OA_SIZE 1024

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
    float pulseTimer;  // PSOLA: samples until next grain trigger
    float oaBuffer[PSOLA_OA_SIZE]; // PSOLA: overlap-add buffer
    int   oaCursor;    // PSOLA: current sample position in OA buffer
} Oscillator;

// --- Vocoder Adjustable Parameters ---
int g_vocoderWaveform = 0;          // 0 = Sawtooth, 1 = Square, 2 = Choral (glottal ensemble), 3 = Neutral (Sine)
float g_vocoderNoiseMix = 0.05f;    // Amount of white noise added to carrier for consonant intelligibility
float g_vocoderEnvRelease = 0.02f;  // Envelope follower release time (lower = faster)
static float g_gateThreshold = 0.01f; // Mic noise gate: mic samples below this amplitude are silenced

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

// --- ACF Pitch Estimator State ---
#define ACF_WINDOW 1024
#define ACF_MAX_LAG 600  // 80Hz at 48kHz
#define ACF_MIN_LAG 48   // 1000Hz at 48kHz
static float g_micPitchHz = 150.0f;
static int   g_acfCounter   = 0;
static float g_acfBuffer[ACF_WINDOW];

// --- Natural PSOLA Grain Capture ---
// We capture 2 periods of the voice to create a smooth Hanning-windowed grain.
static float g_naturalWavetable[ACF_MAX_LAG * 2];
static int   g_naturalWavetableLen = 100; // This will be 2 * bestLag
static float g_naturalMaxCorr = 0.0f;

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

// --- PSOLA: Hanning Window Capture ---
// Captures 2 periods of the voice and applies a Hanning window to create a stable grain.
static void capture_psola_grain(const float* source, int lag) {
    if (lag < ACF_MIN_LAG || lag > ACF_MAX_LAG) return;
    
    int grainLen = lag * 2; 
    g_naturalWavetableLen = grainLen;
    
    // Calculate RMS for normalization
    float sumSq = 0.0f;
    for (int i = 0; i < grainLen; i++) sumSq += source[i] * source[i];
    float rms = sqrtf(sumSq / (float)grainLen) + 1e-9f;
    // Target a healthy internal amplitude (approx 0.4 RMS)
    float norm = 0.4f / rms;
    if (norm > 4.0f) norm = 4.0f; // Limit extreme gain on silence
    
    for (int i = 0; i < grainLen; i++) {
        // Hanning window over 2 periods
        float window = 0.5f * (1.0f - cosf(6.2831853f * (float)i / (float)(grainLen - 1)));
        g_naturalWavetable[i] = source[i] * window * norm;
    }
}

// Render Oscillator (Polyphonic Carrier) — used by modes 0, 1, 2.
// Mode 3 (Neutral) bypasses this entirely, pitch-shifting the raw mic signal.
static float renderOscillator(Oscillator* osc) {
    float sample = 0.0f;

    if (g_vocoderWaveform == 0) {
        // --- Saw: 3 detuned unison copies (0, -5 cents, +5 cents) for body & intelligibility ---
        float s1 = osc->phase  * 2.0f - 1.0f;
        float s2 = osc->phase2 * 2.0f - 1.0f;  // -5 cents
        float s3 = osc->phase3 * 2.0f - 1.0f;  // +5 cents
        sample   = (s1 + s2 * 0.7f + s3 * 0.7f) * (1.0f / 2.4f);

        osc->phase  += (osc->frequency / SAMPLE_RATE);
        osc->phase2 += (osc->frequency * 0.9971f / SAMPLE_RATE);   // -5 cents: 2^(-5/1200)
        osc->phase3 += (osc->frequency * 1.0029f / SAMPLE_RATE);   // +5 cents: 2^(+5/1200)
        if (osc->phase  >= 1.0f) osc->phase  -= 1.0f;
        if (osc->phase2 >= 1.0f) osc->phase2 -= 1.0f;
        if (osc->phase3 >= 1.0f) osc->phase3 -= 1.0f;

    } else if (g_vocoderWaveform == 1) {
        // --- Square: 3 detuned unison copies (-8, 0, +8 cents) for richness & intelligibility ---
        float s1 = (osc->phase  < 0.5f) ? 1.0f : -1.0f;
        float s2 = (osc->phase2 < 0.5f) ? 1.0f : -1.0f;  // -8 cents
        float s3 = (osc->phase3 < 0.5f) ? 1.0f : -1.0f;  // +8 cents
        sample   = (s1 + s2 * 0.6f + s3 * 0.6f) * (1.0f / 2.2f);

        osc->phase  += (osc->frequency / SAMPLE_RATE);
        osc->phase2 += (osc->frequency * 0.9954f / SAMPLE_RATE);   // -8 cents
        osc->phase3 += (osc->frequency * 1.0046f / SAMPLE_RATE);   // +8 cents
        if (osc->phase  >= 1.0f) osc->phase  -= 1.0f;
        if (osc->phase2 >= 1.0f) osc->phase2 -= 1.0f;
        if (osc->phase3 >= 1.0f) osc->phase3 -= 1.0f;

    } else if (g_vocoderWaveform == 2) {
        // --- Choral: 3 detuned glottal pulses — warm, robotic, ensemble-like ---
        float raw1 = (osc->phase  < 0.08f) ? 2.0f : -0.2f;
        float raw2 = (osc->phase2 < 0.08f) ? 2.0f : -0.2f;
        float raw3 = (osc->phase3 < 0.08f) ? 2.0f : -0.2f;

        float mix = (raw1 + raw2 + raw3) * 0.33f;

        // Gentle lowpass for body warmth
        osc->filterState += 0.3f * (mix - osc->filterState);
        sample = osc->filterState;

        // Advance phases with slight natural detuning (-10 and +10 cents)
        osc->phase  += (osc->frequency / SAMPLE_RATE);
        osc->phase2 += (osc->frequency * 0.994f  / SAMPLE_RATE);  // -10 cents (original)
        osc->phase3 += (osc->frequency * 1.006f  / SAMPLE_RATE);  // +10 cents (original)
        if (osc->phase  >= 1.0f) osc->phase  -= 1.0f;
        if (osc->phase2 >= 1.0f) osc->phase2 -= 1.0f;
        if (osc->phase3 >= 1.0f) osc->phase3 -= 1.0f;
    } else if (g_vocoderWaveform == 3) {
        // --- Natural (PSOLA) Mode: Pulse-Train Grain Synthesis ---
        // This triggers a fixed-duration vocal pulse at the target MIDI frequency.
        // It's superior to wavetable looping because it doesn't stretch formants.
        osc->pulseTimer -= 1.0f;
        if (osc->pulseTimer <= 0.0f) {
            float targetPeriod = (float)SAMPLE_RATE / osc->frequency;
            if (targetPeriod < 10.0f) targetPeriod = 10.0f; // Limit to 4.8kHz (ultrasound)
            
            // Trigger a new grain: add g_naturalWavetable into the circular oaBuffer
            int grainLen = g_naturalWavetableLen;
            if (grainLen > ACF_MAX_LAG * 2) grainLen = ACF_MAX_LAG * 2;
            
            for (int j = 0; j < grainLen; j++) {
                int oaIdx = (osc->oaCursor + j) % PSOLA_OA_SIZE;
                osc->oaBuffer[oaIdx] += g_naturalWavetable[j];
            }
            osc->pulseTimer += targetPeriod;
        }

        sample = osc->oaBuffer[osc->oaCursor];
        osc->oaBuffer[osc->oaCursor] = 0.0f; // Consume and clear
        osc->oaCursor = (osc->oaCursor + 1) % PSOLA_OA_SIZE;
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

    // Sibilance high-pass filter state (shared across modes)
    static float sibilanceZ1 = 0.0f;
    static float sibilanceZ2 = 0.0f;
    const float hp_b0 = 0.65f, hp_b1 = -1.3f, hp_b2 = 0.65f, hp_a1 = -0.8f, hp_a2 = 0.2f;

    // PRE-LOOP: Count active voices once per callback
    int activeVoiceCount = 0;
    for (int v = 0; v < MAX_POLYPHONY; ++v) {
        if (voices[v].active || voices[v].releaseSamples > 0) activeVoiceCount++;
    }

    // PRE-LOOP: Pitch Detection (ACF)
    if (g_vocoderWaveform == 3 && activeVoiceCount > 0) {
        for (ma_uint32 i = 0; i < frameCount; i++) {
            g_acfBuffer[g_acfCounter++] = g_micRing[(readStart + i) & MIC_RING_MASK];
            if (g_acfCounter >= ACF_WINDOW) {
                float maxCorr = -1.0f;
                int bestLag = -1;
                for (int lag = ACF_MIN_LAG; lag < ACF_MAX_LAG; lag++) {
                    float corr = 0.0f;
                    for (int j = 0; j < ACF_WINDOW - lag; j++) {
                        corr += g_acfBuffer[j] * g_acfBuffer[j + lag];
                    }
                    if (corr > maxCorr) { maxCorr = corr; bestLag = lag; }
                }

                if (bestLag > 0) {
                    float detectedHz = (float)SAMPLE_RATE / (float)bestLag;
                    g_micPitchHz = g_micPitchHz * 0.9f + detectedHz * 0.1f;
                    
                    // Capture dynamic wavetable snapshot if correlation is healthy
                    // Normalize by energy to keep volume consistent
                    float energy = 0.0f;
                    for (int j = 0; j < bestLag; j++) energy += g_acfBuffer[j] * g_acfBuffer[j];
                    float norm = (energy > 1e-6f) ? (1.0f / sqrtf(energy / bestLag)) * 0.5f : 0.0f;

                    if (maxCorr > g_naturalMaxCorr * 0.8f || maxCorr > 0.5f) {
                        g_naturalMaxCorr = maxCorr;
                        // Capture PSOLA grain (2 periods, Hanning windowed)
                        capture_psola_grain(&g_acfBuffer[0], bestLag);
                    }
                }
                g_acfCounter = 0;
            }
        }
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
                    float voiceGain = (g_vocoderWaveform == 3) ? 1.2f : 0.8f;
                    synthMix += renderOscillator(osc) * (osc->velocity / 127.0f) * osc->envelope * voiceGain;
                }
            }
        }

        micInput = pre_filter_mic(micInput);

        // Noise gate: silence mic input below threshold at all times.
        if (fabsf(micInput) < g_gateThreshold) micInput = 0.0f;

        if (activeVoiceCount == 0) {
            if (absRawMic > squelchEnv) squelchEnv = squelchEnv * (1.0f - squelchAttack) + absRawMic * squelchAttack;
            else squelchEnv = squelchEnv * (1.0f - squelchRelease) + absRawMic * squelchRelease;
            if (squelchEnv < squelchThreshold) { micInput = 0.0f; squelchEnv = 0.0f; }
        } else {
            squelchEnv = absRawMic;
        }

        float vocoderOutput = 0.0f;

        // ----------------------------------------------------------------
        // FILTER-BANK MODES: Saw (0), Square (1), Choral (2), Neutral (3)
        // ----------------------------------------------------------------
        for (int b = 0; b < NUM_BANDS; ++b) {
            float modSignal = processBiquad(&bands[b].modFilter, micInput);
            float absMod = fabsf(modSignal);
            if (absMod > bands[b].envelope) bands[b].envelope = bands[b].envelope * (1.0f - 0.01f) + absMod * 0.01f;
            else bands[b].envelope = bands[b].envelope * (1.0f - g_vocoderEnvRelease) + absMod * g_vocoderEnvRelease;
            if (bands[b].envelope < 1e-6f) bands[b].envelope = 0.0f;
        }

        if (activeVoiceCount > 0) {
            for (int b = 0; b < NUM_BANDS; ++b) {
                vocoderOutput += processBiquad(&bands[b].carFilter, synthMix) * bands[b].envelope;
            }
            // Per-mode output scaling
            float modeScale = (g_vocoderWaveform == 0) ? 18.0f :
                              (g_vocoderWaveform == 1) ? 15.0f :
                              (g_vocoderWaveform == 2) ? 20.0f : 15.0f; // Mode 3: Sine
            vocoderOutput *= modeScale;

            // Sibilance injection — boosted for Saw/Square for intelligibility
            float sibilance = micInput * hp_b0 + sibilanceZ1;
            sibilanceZ1 = micInput * hp_b1 - sibilance * hp_a1 + sibilanceZ2;
            sibilanceZ2 = micInput * hp_b2 - sibilance * hp_a2;
            float sibScale = (g_vocoderWaveform <= 1) ? 4.5f : 
                             (g_vocoderWaveform == 2) ? 2.5f : 1.5f; // Mode 3: Sine
            vocoderOutput += sibilance * g_vocoderNoiseMix * sibScale;
        } else {
            float sibilance = micInput * hp_b0 + sibilanceZ1;
            sibilanceZ1 = micInput * hp_b1 - sibilance * hp_a1 + sibilanceZ2;
            sibilanceZ2 = micInput * hp_b2 - sibilance * hp_a2;
        }

        vocoderOutput = soft_clip(vocoderOutput) * 0.95f;

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
    if (g_androidDeviceId >= 0) {
        customDeviceId.aaudio = g_androidDeviceId;
        customDeviceId.opensl = (ma_uint32)g_androidDeviceId;
        useCustomId = true;
        LOGI("GrooveForge: Android Capture Device ID %d set to customDeviceId", g_androidDeviceId);
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
    if (g_androidOutputDeviceId >= 0) {
        customOutputDeviceId.aaudio = g_androidOutputDeviceId;
        customOutputDeviceId.opensl = (ma_uint32)g_androidOutputDeviceId;
        useCustomOutputId = true;
        LOGI("GrooveForge: Android Playback Device ID %d set to customOutputDeviceId", g_androidOutputDeviceId);
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

    // Reset health counters immediately so that the next start_audio_capture begins
    // with a clean slate. Without this, a crash cycle (e.g. bad neutral mode) sets
    // g_engineUnhealthy = 1 and the Dart health-watcher triggers an infinite restart
    // loop that kills every note played and disrupts the whole Android audio stack.
    g_engineUnhealthy = 0;
    g_glitchCounter   = 0;

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

// waveform: 0=Saw, 1=Square, 2=Choral(glottal ensemble), 3=Natural(pitch-locked live wavetable)
EXPORT void setVocoderParameters(int waveform, float noiseMix, float envRelease, float bandwidth) {
    g_vocoderWaveform = waveform;
    g_vocoderNoiseMix = noiseMix * 10.0f; // Scale 0.0-1.0 up to 0.0-10.0 for audible noise presence
    // Map a nice 0.0 - 1.0 value from the UI to the actual filter coefficient math
    // 0.0 -> very slow (0.0001), 1.0 -> very fast (0.05)
    g_vocoderEnvRelease = 0.0001f + (envRelease * 0.0499f);

    // Map bandwidth 0.0 to 1.0 to Q factor 2.0 (blurry) to 30.0 (sharp robotic)
    // (Only affects filter-bank modes 0, 1, 2; mode 3 bypasses the filter bank)
    float qFactor = 2.0f + (bandwidth * 28.0f);
    init_vocoder_bands(qFactor);
}

EXPORT void set_gate_threshold(float threshold) {
    // Clamp to a safe range: 0.0 (gate off) to 0.5 (extreme gate)
    if (threshold < 0.0f) threshold = 0.0f;
    if (threshold > 0.5f) threshold = 0.5f;
    g_gateThreshold = threshold;
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
