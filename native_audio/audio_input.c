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
// Pitch bend multiplier for the vocoder carrier oscillator.
// 1.0 = no bend. Derived from the raw MIDI pitch-bend value (0-16383, center 8192)
// using a ±2 semitone range (standard VST convention).
static volatile float g_pitchBendFactor = 1.0f;

// Vibrato (CC#1 / mod wheel) LFO state for the vocoder carrier oscillator.
// g_vibratoDepth is the normalised depth (0..1, where 1 = CC#1 at 127).
// g_lfoPhase advances once per sample; g_effectivePitchFactor is recomputed
// at the start of each sample in data_callback so renderOscillator can read it.
static float g_vibratoDepth  = 0.0f; // 0..1 controlled by CC#1
static float g_lfoPhase      = 0.0f; // 0..1 sawtooth counter
static float g_effectivePitchFactor = 1.0f; // = g_pitchBendFactor × vibrato LFO

static float g_inputPeak = 0.0f;
static float g_outputPeak = 0.0f;
static float g_inputGain = 1.0f;

/// Vocoder capture mode flag.
/// 0 = normal playback via miniaudio (default).
/// 1 = routed through JACK audio thread — data_callback outputs silence and
///     does NOT advance DSP state.  vocoder_render_block() drives the DSP.
static volatile int g_vocoderCaptureMode = 0;
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

        float bentFreq0 = osc->frequency * g_effectivePitchFactor;
        osc->phase  += (bentFreq0 / SAMPLE_RATE);
        osc->phase2 += (bentFreq0 * 0.9971f / SAMPLE_RATE);   // -5 cents: 2^(-5/1200)
        osc->phase3 += (bentFreq0 * 1.0029f / SAMPLE_RATE);   // +5 cents: 2^(+5/1200)
        if (osc->phase  >= 1.0f) osc->phase  -= 1.0f;
        if (osc->phase2 >= 1.0f) osc->phase2 -= 1.0f;
        if (osc->phase3 >= 1.0f) osc->phase3 -= 1.0f;

    } else if (g_vocoderWaveform == 1) {
        // --- Square: 3 detuned unison copies (-8, 0, +8 cents) for richness & intelligibility ---
        float s1 = (osc->phase  < 0.5f) ? 1.0f : -1.0f;
        float s2 = (osc->phase2 < 0.5f) ? 1.0f : -1.0f;  // -8 cents
        float s3 = (osc->phase3 < 0.5f) ? 1.0f : -1.0f;  // +8 cents
        sample   = (s1 + s2 * 0.6f + s3 * 0.6f) * (1.0f / 2.2f);

        float bentFreq1 = osc->frequency * g_effectivePitchFactor;
        osc->phase  += (bentFreq1 / SAMPLE_RATE);
        osc->phase2 += (bentFreq1 * 0.9954f / SAMPLE_RATE);   // -8 cents
        osc->phase3 += (bentFreq1 * 1.0046f / SAMPLE_RATE);   // +8 cents
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
        float bentFreq2 = osc->frequency * g_effectivePitchFactor;
        osc->phase  += (bentFreq2 / SAMPLE_RATE);
        osc->phase2 += (bentFreq2 * 0.994f  / SAMPLE_RATE);  // -10 cents (original)
        osc->phase3 += (bentFreq2 * 1.006f  / SAMPLE_RATE);  // +10 cents (original)
        if (osc->phase  >= 1.0f) osc->phase  -= 1.0f;
        if (osc->phase2 >= 1.0f) osc->phase2 -= 1.0f;
        if (osc->phase3 >= 1.0f) osc->phase3 -= 1.0f;
    } else if (g_vocoderWaveform == 3) {
        // --- Natural (PSOLA) Mode: Pulse-Train Grain Synthesis ---
        // This triggers a fixed-duration vocal pulse at the target MIDI frequency.
        // It's superior to wavetable looping because it doesn't stretch formants.
        osc->pulseTimer -= 1.0f;
        if (osc->pulseTimer <= 0.0f) {
            float targetPeriod = (float)SAMPLE_RATE / (osc->frequency * g_effectivePitchFactor);
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
    // When capture mode is active, the JACK thread owns the DSP.
    // Output silence so we don't double-render.
    if (g_vocoderCaptureMode) {
        if (pOutput) memset(pOutput, 0, frameCount * sizeof(float));
        return;
    }

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
        // Advance the vibrato LFO once per sample (5.5 Hz sine, standard keyboard rate).
        // Combine with the raw pitch-bend multiplier so renderOscillator needs only one factor.
        // Depth: ±1 semitone at CC#1 = 127 (factor ≈ 0.05946 = 2^(1/12) - 1).
        g_lfoPhase += 5.5f / (float)SAMPLE_RATE;
        if (g_lfoPhase >= 1.0f) g_lfoPhase -= 1.0f;
        float lfoSin = sinf(g_lfoPhase * 6.2831853f); // 2π
        g_effectivePitchFactor = g_pitchBendFactor * (1.0f + lfoSin * g_vibratoDepth * 0.05946f);

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

// ── Vocoder capture mode + render block ──────────────────────────────────────
//
// When capture mode is enabled, the miniaudio playback device outputs silence
// and vocoder_render_block() produces the vocoder audio.  This allows the JACK
// audio thread (and the audio looper) to capture the vocoder's output.
//
// Same pattern as theremin_render_block / theremin_set_capture_mode.

/// Renders [frames] samples of vocoder DSP into [outL] and [outR] (stereo f32).
///
/// Must ONLY be called when capture mode is enabled (vocoder_set_capture_mode(1)).
/// Reads from the mic ring buffer (filled by the capture device) and runs the
/// full vocoder pipeline: filter bank analysis, carrier synthesis, sibilance.
///
/// This function is allocation-free and safe on the audio thread.
static void _vocoder_render_block_impl(float* outL, float* outR, int frames) {
    ma_uint32 writePos = __atomic_load_n(&g_micWriteCursor, __ATOMIC_ACQUIRE);
    ma_uint32 readStart = (writePos - (ma_uint32)frames) & MIC_RING_MASK;

    static float squelchEnv = 0.0f;
    const float squelchThreshold = 0.003f;
    const float squelchAttack = 0.05f;
    const float squelchRelease = 0.002f;

    static float sibilanceZ1 = 0.0f;
    static float sibilanceZ2 = 0.0f;
    const float hp_b0 = 0.65f, hp_b1 = -1.3f, hp_b2 = 0.65f, hp_a1 = -0.8f, hp_a2 = 0.2f;

    int activeVoiceCount = 0;
    for (int v = 0; v < MAX_POLYPHONY; ++v) {
        if (voices[v].active || voices[v].releaseSamples > 0) activeVoiceCount++;
    }

    // ACF pitch detection (NATURAL mode only).
    if (g_vocoderWaveform == 3 && activeVoiceCount > 0) {
        for (int i = 0; i < frames; i++) {
            g_acfBuffer[g_acfCounter++] = g_micRing[(readStart + (ma_uint32)i) & MIC_RING_MASK];
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
                    if (maxCorr > g_naturalMaxCorr * 0.8f || maxCorr > 0.5f) {
                        g_naturalMaxCorr = maxCorr;
                        capture_psola_grain(&g_acfBuffer[0], bestLag);
                    }
                }
                g_acfCounter = 0;
            }
        }
    }

    for (int i = 0; i < frames; ++i) {
        g_lfoPhase += 5.5f / (float)SAMPLE_RATE;
        if (g_lfoPhase >= 1.0f) g_lfoPhase -= 1.0f;
        float lfoSin = sinf(g_lfoPhase * 6.2831853f);
        g_effectivePitchFactor = g_pitchBendFactor * (1.0f + lfoSin * g_vibratoDepth * 0.05946f);

        float micInput = g_micRing[(readStart + (ma_uint32)i) & MIC_RING_MASK] * g_inputGain;

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
        if (fabsf(micInput) < g_gateThreshold) micInput = 0.0f;

        if (activeVoiceCount == 0) {
            float absRawMic = fabsf(micInput);
            if (absRawMic > squelchEnv) squelchEnv = squelchEnv * (1.0f - squelchAttack) + absRawMic * squelchAttack;
            else squelchEnv = squelchEnv * (1.0f - squelchRelease) + absRawMic * squelchRelease;
            if (squelchEnv < squelchThreshold) { micInput = 0.0f; squelchEnv = 0.0f; }
        } else {
            squelchEnv = fabsf(micInput);
        }

        float vocoderOutput = 0.0f;

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
            float modeScale = (g_vocoderWaveform == 0) ? 18.0f :
                              (g_vocoderWaveform == 1) ? 15.0f :
                              (g_vocoderWaveform == 2) ? 20.0f : 15.0f;
            vocoderOutput *= modeScale;

            float sibilance = micInput * hp_b0 + sibilanceZ1;
            sibilanceZ1 = micInput * hp_b1 - sibilance * hp_a1 + sibilanceZ2;
            sibilanceZ2 = micInput * hp_b2 - sibilance * hp_a2;
            float sibScale = (g_vocoderWaveform <= 1) ? 4.5f :
                             (g_vocoderWaveform == 2) ? 2.5f : 1.5f;
            vocoderOutput += sibilance * g_vocoderNoiseMix * sibScale;
        } else {
            float sibilance = micInput * hp_b0 + sibilanceZ1;
            sibilanceZ1 = micInput * hp_b1 - sibilance * hp_a1 + sibilanceZ2;
            sibilanceZ2 = micInput * hp_b2 - sibilance * hp_a2;
        }

        vocoderOutput = soft_clip(vocoderOutput) * 0.95f;
        // Mono → stereo.
        outL[i] = vocoderOutput;
        outR[i] = vocoderOutput;
    }
}

#ifdef _WIN32
  #define EXPORT __declspec(dllexport)
#else
  #define EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

/// Enable or disable vocoder capture mode.
/// When enabled, the miniaudio playback device outputs silence and
/// vocoder_render_block() drives the DSP (called by the JACK thread).
EXPORT void vocoder_set_capture_mode(int enabled) {
    g_vocoderCaptureMode = enabled ? 1 : 0;
    fprintf(stderr, "[vocoder] capture mode %s\n", enabled ? "ON" : "OFF");
}

/// Renders vocoder audio for the JACK audio thread / audio looper.
/// Only valid when capture mode is enabled.
EXPORT void vocoder_render_block(float* outL, float* outR, int frames) {
    _vocoder_render_block_impl(outL, outR, frames);
}

/// AAudio-bus render wrapper for the Vocoder.
///
/// Matches the AudioSourceRenderFn signature expected by oboe_stream_add_source()
/// in libnative-lib.so.  The [userdata] parameter is unused — the Vocoder uses
/// singleton DSP state.
///
/// Must be called with capture mode enabled (vocoder_set_capture_mode(1)) so
/// that the miniaudio playback device outputs silence and this function owns
/// the DSP state exclusively. The mic capture device keeps filling the ring
/// buffer independently of capture mode — `_vocoder_render_block_impl` reads
/// from that ring to drive the carrier oscillator.
EXPORT void vocoder_bus_render(float* outL, float* outR, int frames, void* userdata) {
    (void)userdata;
    _vocoder_render_block_impl(outL, outR, frames);
}

/// Returns the address of vocoder_bus_render as an intptr_t.
///
/// Called from Dart so the function pointer can be passed to
/// oboe_stream_add_source() in libnative-lib.so, registering the Vocoder on
/// the shared AAudio bus so GFPA effects can be applied to its audio output
/// and so the audio looper can cable directly into it.
EXPORT intptr_t vocoder_bus_render_fn_addr(void) {
    return (intptr_t)(void*)vocoder_bus_render;
}

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

/// Apply a MIDI pitch-bend value to the vocoder carrier oscillator.
///
/// rawValue is the standard 14-bit MIDI pitch-bend word (0–16383, center 8192).
/// The bend range is ±2 semitones, matching the VST3 default.
/// Updating g_pitchBendFactor here is thread-safe enough for audio use:
/// a torn float write produces at worst a brief pitch glitch, not a crash.
EXPORT void VocoderPitchBend(int rawValue) {
    // Normalise to -1..+1 then scale to ±2 semitones
    float normalised = ((float)rawValue - 8192.0f) / 8192.0f;
    float semitones  = normalised * 2.0f;
    g_pitchBendFactor = powf(2.0f, semitones / 12.0f);
}

/// Handle MIDI Control Change messages for the vocoder carrier oscillator.
///
/// Currently recognises CC#1 (modulation wheel / vibrato depth).
/// CC#1 = 0 disables vibrato; CC#1 = 127 produces ±1 semitone LFO modulation
/// at 5.5 Hz (the standard keyboard vibrato rate).
/// Other CC numbers are silently ignored.
EXPORT void VocoderControlChange(int cc, int value) {
    if (cc == 1) {
        // Map 0-127 to 0.0-1.0 vibrato depth
        g_vibratoDepth = (float)value / 127.0f;
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
    playConfig.periodSizeInFrames        = 256;  // ~5.3ms — matches capture latency
    playConfig.periods                   = 2;   // total ~10.7ms (was 512×3 = 32ms)
    playConfig.noPreSilencedOutputBuffer = MA_TRUE;
    playConfig.noClip                    = MA_TRUE;
    playConfig.performanceProfile        = ma_performance_profile_low_latency;
#ifdef __ANDROID__
    // Enable the low-latency audio path on Android.  AAUDIO_USAGE_GAME maps
    // to the "fast mixer" hardware path on most devices, reducing output
    // latency from ~30ms to ~10ms.
    playConfig.aaudio.usage = ma_aaudio_usage_game;
#endif

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

// =============================================================================
// THEREMIN SYNTH — Continuous-pitch monophonic sine oscillator
// =============================================================================
// Produces the eerie, gliding tone of a real theremin:
//   • Smooth portamento (exponential glide, τ ≈ 42 ms at 48 kHz)
//   • 6.5 Hz vibrato LFO with adjustable depth
//   • Sine wave with faint 3rd harmonic (10 %) for warmth
//   • Smooth amplitude envelope (τ ≈ 7 ms) — prevents click artefacts
// The C synth receives direct Hz + volume [0,1] commands from Dart.

// ── Theremin device state ────────────────────────────────────────────────────

/// miniaudio context dedicated to the theremin playback device.
static ma_context g_thereminCtx;

/// miniaudio playback device that runs the theremin synthesis callback.
static ma_device  g_thereminDev;

/// True while the theremin device is initialised and running.
static bool       g_thereminRunning = false;

// ── Theremin DSP parameters (written by Dart thread, read by audio callback) ─

/// Target fundamental frequency in Hz, set by Dart via theremin_set_pitch_hz.
static volatile float g_thereminTargetHz  = 440.0f;

/// Target output volume [0, 0.85], set by Dart via theremin_set_volume.
static volatile float g_thereminTargetVol = 0.0f;

/// Vibrato depth [0, 1]: 0 = no vibrato, 1 = ±0.5 semitone LFO modulation.
static volatile float g_thereminVibDepth  = 0.0f;

// ── Theremin internal DSP state (audio-thread only, never written from Dart) ─

/// Smoothed current frequency (approaches g_thereminTargetHz via THEREMIN_GLIDE).
static float g_thereminCurrentHz  = 440.0f;

/// Smoothed current volume (approaches g_thereminTargetVol via THEREMIN_VOL).
static float g_thereminCurrentVol = 0.0f;

/// Oscillator phase accumulator [0, 1).
static float g_thereminPhase      = 0.0f;

/// Vibrato LFO phase accumulator [0, 1).
static float g_thereminLfoPhase   = 0.0f;

/// Portamento coefficient: each sample closes 0.0005 of the remaining gap → τ ≈ 42 ms.
#define THEREMIN_GLIDE    0.0005f

/// Volume envelope coefficient: τ ≈ 7 ms — responsive but click-free.
#define THEREMIN_VOL      0.003f

/// Vibrato semitone coefficient: 2^(0.5/12) − 1 ≈ 0.02963 (±0.5 st at depth=1).
#define THEREMIN_VIB_COEF 0.02963f

// ── Theremin capture mode ─────────────────────────────────────────────────────
//
// When set to 1, the miniaudio callback outputs silence and does NOT advance
// the DSP state.  Instead, theremin_render_block() advances the DSP state and
// writes stereo f32 samples that dart_vst_host's ALSA loop feeds into a VST3
// effect input.
//
// Only one thread advances the DSP state at a time: miniaudio thread when 0,
// dart_vst_host ALSA thread when 1.  No mutex needed — modes are exclusive.

/// 0 = normal playback via miniaudio; 1 = routed through VST3 effect chain.
static volatile int g_thereminCaptureMode = 0;

// ── Theremin DSP inner loop (shared by callback and render_block) ─────────────

/// Computes one sample of Theremin DSP and advances all internal state.
///
/// Must only be called from the thread that currently owns the DSP state
/// (miniaudio thread when capture=0; ALSA thread when capture=1).
static inline float _theremin_dsp_tick(float sr) {
    // Portamento: exponential glide towards target Hz (τ ≈ 42 ms).
    g_thereminCurrentHz +=
        (g_thereminTargetHz - g_thereminCurrentHz) * THEREMIN_GLIDE;

    // Volume envelope: exponential approach for click-free transitions (τ ≈ 7 ms).
    g_thereminCurrentVol +=
        (g_thereminTargetVol - g_thereminCurrentVol) * THEREMIN_VOL;

    // Vibrato LFO at 6.5 Hz — advance phase and wrap to [0, 1).
    g_thereminLfoPhase += 6.5f / sr;
    if (g_thereminLfoPhase >= 1.0f) g_thereminLfoPhase -= 1.0f;
    const float lfo = sinf(g_thereminLfoPhase * 6.28318530718f);
    // Modulate instantaneous Hz by ±THEREMIN_VIB_COEF semitones at full depth.
    const float hz =
        g_thereminCurrentHz * (1.0f + lfo * g_thereminVibDepth * THEREMIN_VIB_COEF);

    // Oscillator: fundamental + 10 % 3rd harmonic, normalised to ±1.0.
    const float twoPiPhase = g_thereminPhase * 6.28318530718f;
    float s = sinf(twoPiPhase) + sinf(twoPiPhase * 3.0f) * 0.10f;
    s *= (1.0f / 1.10f);

    // Advance phase accumulator, wrap to [0, 1) to prevent float drift.
    g_thereminPhase += hz / sr;
    if (g_thereminPhase >= 1.0f) g_thereminPhase -= 1.0f;

    return s * g_thereminCurrentVol;
}

// ── Theremin audio callback ───────────────────────────────────────────────────

/// miniaudio data callback for the theremin playback device.
///
/// When capture mode is OFF (default): runs full DSP and writes to the ALSA
/// device directly — normal playback.
///
/// When capture mode is ON: outputs silence without advancing DSP state.
/// The ALSA loop in dart_vst_host calls theremin_render_block() instead,
/// which advances the DSP and feeds the result into the VST3 effect chain.
static void theremin_data_callback(
    ma_device* pDevice,
    void* pOutput,
    const void* pInput,
    ma_uint32 frameCount)
{
    (void)pInput;
    float* out = (float*)pOutput;

    if (g_thereminCaptureMode) {
        // Silence — DSP ownership transferred to dart_vst_host ALSA thread.
        for (ma_uint32 i = 0; i < frameCount; i++) out[i] = 0.0f;
        return;
    }

    const float sr = (float)pDevice->sampleRate;
    for (ma_uint32 i = 0; i < frameCount; i++)
        out[i] = _theremin_dsp_tick(sr);
}

// ── Theremin FFI exports ──────────────────────────────────────────────────────

/// Initialises the theremin miniaudio context and playback device, then starts
/// the synthesis callback.
///
/// Returns 0 on success, −1 if context init fails, −2 if device init fails,
/// −3 if device start fails.  Safe to call again after theremin_stop().
EXPORT int theremin_start(void) {
    if (g_thereminRunning) return 0; // Already running — idempotent.

    // Reset DSP state so a fresh start has no pitch or volume memory.
    g_thereminCurrentHz  = g_thereminTargetHz;
    g_thereminCurrentVol = 0.0f;
    g_thereminPhase      = 0.0f;
    g_thereminLfoPhase   = 0.0f;

    // Initialise a dedicated miniaudio context (independent from the vocoder).
    ma_result result = ma_context_init(NULL, 0, NULL, &g_thereminCtx);
    if (result != MA_SUCCESS) {
        LOGE("theremin_start: context init failed (%d)", result);
        return -1;
    }

    // Configure a low-latency mono f32 playback device.
    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format   = ma_format_f32;
    cfg.playback.channels = 1;
    cfg.sampleRate        = SAMPLE_RATE;
    cfg.dataCallback      = theremin_data_callback;
    cfg.performanceProfile = ma_performance_profile_low_latency;
    cfg.periodSizeInFrames = 256;
    cfg.periods            = 2;

    result = ma_device_init(&g_thereminCtx, &cfg, &g_thereminDev);
    if (result != MA_SUCCESS) {
        LOGE("theremin_start: device init failed (%d)", result);
        ma_context_uninit(&g_thereminCtx);
        return -2;
    }

    result = ma_device_start(&g_thereminDev);
    if (result != MA_SUCCESS) {
        LOGE("theremin_start: device start failed (%d)", result);
        ma_device_uninit(&g_thereminDev);
        ma_context_uninit(&g_thereminCtx);
        return -3;
    }

    g_thereminRunning = true;
    return 0;
}

/// Stops and uninitialises the theremin audio device and context.
///
/// Immediately silences output by zeroing the current volume before stopping
/// the device, preventing a click artefact on shutdown.
EXPORT void theremin_stop(void) {
    if (!g_thereminRunning) return;
    // Zero volume first to fade out any ongoing sound before stopping device.
    g_thereminCurrentVol = 0.0f;
    ma_device_stop(&g_thereminDev);
    ma_device_uninit(&g_thereminDev);
    ma_context_uninit(&g_thereminCtx);
    g_thereminRunning = false;
}

/// Sets the theremin target pitch frequency in Hz.
///
/// The audio callback glides to this frequency exponentially (τ ≈ 42 ms)
/// so pitch changes are smooth and theremin-like.
/// [hz] is clamped to the audible range [20, 20000].
EXPORT void theremin_set_pitch_hz(float hz) {
    if (hz < 20.0f)     hz = 20.0f;
    if (hz > 20000.0f)  hz = 20000.0f;
    g_thereminTargetHz = hz;
}

/// Sets the theremin output volume.
///
/// [volume] is normalised [0, 1]; internally scaled by 0.85 to leave headroom
/// for the vibrato modulation.  The audio callback smooths changes (τ ≈ 7 ms).
EXPORT void theremin_set_volume(float volume) {
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;
    g_thereminTargetVol = volume * 0.85f;
}

/// Sets the vibrato depth applied by the 6.5 Hz LFO.
///
/// [depth] ∈ [0, 1]: 0 = no vibrato, 1 = ±0.5 semitone modulation.
/// Changes take effect on the very next audio callback frame.
EXPORT void theremin_set_vibrato(float depth) {
    if (depth < 0.0f) depth = 0.0f;
    if (depth > 1.0f) depth = 1.0f;
    g_thereminVibDepth = depth;
}

/// Enables or disables VST3 capture routing for the Theremin.
///
/// When [enabled] == 1:
///   - The miniaudio callback outputs silence (DSP ownership released).
///   - The dart_vst_host ALSA thread drives the DSP via theremin_render_block().
///   - The Theremin's audio is fed into the VST3 effect chain instead of the
///     ALSA hardware directly.
///
/// When [enabled] == 0 (default):
///   - Normal playback: the miniaudio callback advances the DSP and outputs
///     directly to the hardware ALSA device.
///
/// Call this before calling dvh_set_external_render on the Dart side.
EXPORT void theremin_set_capture_mode(int enabled) {
    g_thereminCaptureMode = enabled ? 1 : 0;
}

/// Renders [frames] samples of Theremin DSP into [outL] and [outR] (stereo f32).
///
/// Must ONLY be called when capture mode is enabled (theremin_set_capture_mode(1)).
/// Called by dart_vst_host's ALSA thread — advances the DSP state and writes
/// mono-duplicated stereo output that is then fed to the connected VST3 effect.
///
/// This function is allocation-free and safe on the audio thread.
EXPORT void theremin_render_block(float* outL, float* outR, int frames) {
    const float sr = (float)SAMPLE_RATE;
    for (int i = 0; i < frames; i++) {
        const float s = _theremin_dsp_tick(sr);
        // Mono source → duplicate to both stereo channels.
        outL[i] = s;
        outR[i] = s;
    }
}

/// AAudio-bus render wrapper for the Theremin.
///
/// Matches the AudioSourceRenderFn signature expected by oboe_stream_add_source()
/// in libnative-lib.so.  The [userdata] parameter is unused — the Theremin
/// uses singleton DSP state.
///
/// Must be called with capture mode enabled (theremin_set_capture_mode(1))
/// so that the miniaudio device outputs silence and this function owns the
/// DSP state exclusively.
EXPORT void theremin_bus_render(float* outL, float* outR, int frames, void* userdata) {
    (void)userdata;
    theremin_render_block(outL, outR, frames);
}

/// Returns the address of theremin_bus_render as an intptr_t.
///
/// Called from Dart so the function pointer can be passed to
/// oboe_stream_add_source() in libnative-lib.so, registering the Theremin
/// on the shared AAudio bus so GFPA effects apply to its audio output.
EXPORT intptr_t theremin_bus_render_fn_addr(void) {
    return (intptr_t)(void*)theremin_bus_render;
}

// =============================================================================
// STYLOPHONE SYNTH — Monophonic waveform oscillator
// =============================================================================
// Emulates the Dubreq Stylophone: buzzy, monophonic, waveform-selectable.
// Waveforms: 0=Square (default), 1=Sawtooth, 2=Sine, 3=Triangle.
// Phase is NOT reset between keys so sliding sounds click-free.
// Short release envelope (τ ≈ 100 ms) prevents click on note-off.

// ── Stylophone device state ───────────────────────────────────────────────────

/// miniaudio context dedicated to the stylophone playback device.
static ma_context g_styloCtx;

/// miniaudio playback device that runs the stylophone synthesis callback.
static ma_device  g_styloDev;

/// True while the stylophone device is initialised and running.
static bool       g_styloRunning = false;

// ── Stylophone DSP parameters (written by Dart thread, read by audio callback) ─

/// Current oscillator frequency in Hz, set by Dart via stylophone_note_on.
static volatile float g_styloCurrentHz   = 440.0f;

/// Active waveform: 0=Square, 1=Sawtooth, 2=Sine, 3=Triangle.
static volatile int   g_styloWaveform    = 0;

/// 1 when a note is being pressed; 0 during release.
static volatile int   g_styloNoteActive  = 0;

// ── Stylophone internal DSP state (audio-thread only) ────────────────────────

/// Oscillator phase accumulator [0, 1).  Preserved between notes for legato.
static float g_styloPhase = 0.0f;

/// Amplitude envelope [0, 1].  Rises on note-on, decays exponentially on note-off.
static float g_styloEnv   = 0.0f;

/// Vibrato LFO depth for the stylophone: 0 = off, 1 = full (±0.5 semitone).
/// Set by Dart via stylophone_set_vibrato().
static volatile float g_styloVibDepth = 0.0f;

/// Vibrato LFO phase [0, 1). Audio-thread only.
static float g_styloLfoPhase = 0.0f;

/// Attack ramp per sample: reaches 1.0 in ~2 ms at 48 kHz.
#define STYLO_ATTACK       0.004f

/// Release coefficient: applied each sample during note-off → τ ≈ 104 ms.
#define STYLO_RELEASE_COEF 0.9998f

/// Master output volume with headroom margin.
#define STYLO_MASTER_VOL   0.75f

// ── Stylophone capture mode ───────────────────────────────────────────────────
/// 0 = normal playback via miniaudio; 1 = routed through VST3 effect chain.
static volatile int g_styloCaptureMode = 0;

// ── Stylophone DSP inner loop (shared by callback and render_block) ───────────

/// Computes one sample of Stylophone DSP and advances all internal state.
///
/// Only call from the thread that currently owns the DSP state:
/// miniaudio thread when capture=0; dart_vst_host ALSA thread when capture=1.
static inline float _stylophone_dsp_tick(float sr) {
    // Envelope: linear attack on note-on, exponential decay on note-off.
    if (g_styloNoteActive) {
        g_styloEnv += STYLO_ATTACK;
        if (g_styloEnv > 1.0f) g_styloEnv = 1.0f;
    } else {
        g_styloEnv *= STYLO_RELEASE_COEF;
        if (g_styloEnv < 1e-5f) g_styloEnv = 0.0f;
    }

    // Vibrato LFO at 5.5 Hz — modulates pitch by ±0.5 semitone at full depth.
    g_styloLfoPhase += 5.5f / sr;
    if (g_styloLfoPhase >= 1.0f) g_styloLfoPhase -= 1.0f;
    const float styloLfo = sinf(g_styloLfoPhase * 6.28318530718f);
    const float styloHz  = g_styloCurrentHz * (1.0f + styloLfo * g_styloVibDepth * 0.02963f);

    const float phase = g_styloPhase;
    float s;
    switch (g_styloWaveform) {
        default:
        case 0: s = (phase < 0.5f) ? 1.0f : -1.0f;                              break; // Square
        case 1: s = phase * 2.0f - 1.0f;                                         break; // Sawtooth
        case 2: s = sinf(phase * 6.28318530718f);                                 break; // Sine
        case 3: s = (phase < 0.5f) ? (phase * 4.0f - 1.0f) : (3.0f - phase * 4.0f); break; // Triangle
    }

    g_styloPhase += styloHz / sr;
    if (g_styloPhase >= 1.0f) g_styloPhase -= 1.0f;

    return s * g_styloEnv * STYLO_MASTER_VOL;
}

// ── Stylophone audio callback ─────────────────────────────────────────────────

/// miniaudio data callback for the stylophone playback device.
///
/// When capture mode is OFF (default): runs full DSP and writes to ALSA.
/// When capture mode is ON: outputs silence; dart_vst_host calls
/// stylophone_render_block() to advance the DSP and feed VST3 effect inputs.
static void stylophone_data_callback(
    ma_device* pDevice,
    void* pOutput,
    const void* pInput,
    ma_uint32 frameCount)
{
    (void)pInput;
    float* out = (float*)pOutput;

    if (g_styloCaptureMode) {
        for (ma_uint32 i = 0; i < frameCount; i++) out[i] = 0.0f;
        return;
    }

    const float sr = (float)pDevice->sampleRate;
    for (ma_uint32 i = 0; i < frameCount; i++)
        out[i] = _stylophone_dsp_tick(sr);
}

// ── Stylophone FFI exports ────────────────────────────────────────────────────

/// Initialises the stylophone miniaudio context and playback device, then starts
/// the synthesis callback.
///
/// Returns 0 on success, −1 if context init fails, −2 if device init fails,
/// −3 if device start fails.  Safe to call again after stylophone_stop().
EXPORT int stylophone_start(void) {
    if (g_styloRunning) return 0; // Already running — idempotent.

    // Reset envelope and LFO phase; keep oscillator phase intact so a
    // quick stop/start is seamless.
    g_styloEnv      = 0.0f;
    g_styloLfoPhase = 0.0f;

    ma_result result = ma_context_init(NULL, 0, NULL, &g_styloCtx);
    if (result != MA_SUCCESS) {
        LOGE("stylophone_start: context init failed (%d)", result);
        return -1;
    }

    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format    = ma_format_f32;
    cfg.playback.channels  = 1;
    cfg.sampleRate         = SAMPLE_RATE;
    cfg.dataCallback       = stylophone_data_callback;
    cfg.performanceProfile = ma_performance_profile_low_latency;
    cfg.periodSizeInFrames = 256;
    cfg.periods            = 2;

    result = ma_device_init(&g_styloCtx, &cfg, &g_styloDev);
    if (result != MA_SUCCESS) {
        LOGE("stylophone_start: device init failed (%d)", result);
        ma_context_uninit(&g_styloCtx);
        return -2;
    }

    result = ma_device_start(&g_styloDev);
    if (result != MA_SUCCESS) {
        LOGE("stylophone_start: device start failed (%d)", result);
        ma_device_uninit(&g_styloDev);
        ma_context_uninit(&g_styloCtx);
        return -3;
    }

    g_styloRunning = true;
    return 0;
}

/// Stops and uninitialises the stylophone audio device and context.
///
/// The note-active flag is cleared so the release envelope winds down
/// naturally through the remaining callback frames before device stop.
EXPORT void stylophone_stop(void) {
    if (!g_styloRunning) return;
    g_styloNoteActive = 0;
    ma_device_stop(&g_styloDev);
    ma_device_uninit(&g_styloDev);
    ma_context_uninit(&g_styloCtx);
    g_styloRunning = false;
}

/// Starts a note at the given frequency.
///
/// [hz] is clamped to [20, 20000].  Phase is NOT reset so sliding from one
/// key to another is seamless (no click at the transition).
/// The amplitude envelope immediately starts rising from its current value.
EXPORT void stylophone_note_on(float hz) {
    if (hz < 20.0f)     hz = 20.0f;
    if (hz > 20000.0f)  hz = 20000.0f;
    g_styloCurrentHz  = hz;
    g_styloNoteActive = 1;
}

/// Releases the current note, triggering the exponential release envelope.
///
/// The oscillator continues running during the release (τ ≈ 104 ms) so the
/// sound fades gracefully rather than cutting abruptly.
EXPORT void stylophone_note_off(void) {
    g_styloNoteActive = 0;
}

/// Selects the oscillator waveform.
///
/// [waveform] is clamped to [0, 3]: 0=Square, 1=Sawtooth, 2=Sine, 3=Triangle.
/// Takes effect on the very next audio callback frame.
EXPORT void stylophone_set_waveform(int waveform) {
    if (waveform < 0) waveform = 0;
    if (waveform > 3) waveform = 3;
    g_styloWaveform = waveform;
}

/// Set the stylophone vibrato depth.
///
/// depth = 0.0 → no vibrato (clean tone).
/// depth = 1.0 → ±0.5 semitone wobble at 5.5 Hz — classic tape-wobble effect.
EXPORT void stylophone_set_vibrato(float depth) {
    if (depth < 0.0f) depth = 0.0f;
    if (depth > 1.0f) depth = 1.0f;
    g_styloVibDepth = depth;
}

/// Enables or disables VST3 capture routing for the Stylophone.
///
/// When [enabled] == 1, the miniaudio callback outputs silence and
/// stylophone_render_block() must be called by dart_vst_host's ALSA thread
/// to advance the DSP and feed audio into the connected VST3 effect.
EXPORT void stylophone_set_capture_mode(int enabled) {
    g_styloCaptureMode = enabled ? 1 : 0;
}

/// Renders [frames] samples of Stylophone DSP into [outL] and [outR] (stereo f32).
///
/// Must ONLY be called when capture mode is enabled (stylophone_set_capture_mode(1)).
/// Allocation-free; safe to call from dart_vst_host's ALSA audio thread.
EXPORT void stylophone_render_block(float* outL, float* outR, int frames) {
    const float sr = (float)SAMPLE_RATE;
    for (int i = 0; i < frames; i++) {
        const float s = _stylophone_dsp_tick(sr);
        outL[i] = s;
        outR[i] = s;
    }
}

/// AAudio-bus render wrapper for the Stylophone.
///
/// Matches the AudioSourceRenderFn signature expected by oboe_stream_add_source()
/// in libnative-lib.so.  The [userdata] parameter is unused — the Stylophone
/// uses singleton DSP state.
///
/// Must be called with capture mode enabled (stylophone_set_capture_mode(1))
/// so that the miniaudio device outputs silence and this function owns the
/// DSP state exclusively.
EXPORT void stylophone_bus_render(float* outL, float* outR, int frames, void* userdata) {
    (void)userdata;
    stylophone_render_block(outL, outR, frames);
}

/// Returns the address of stylophone_bus_render as an intptr_t.
///
/// Called from Dart so the function pointer can be passed to
/// oboe_stream_add_source() in libnative-lib.so, registering the Stylophone
/// on the shared AAudio bus so GFPA effects can be applied to its audio
/// output and so the audio looper can cable directly into it.
EXPORT intptr_t stylophone_bus_render_fn_addr(void) {
    return (intptr_t)(void*)stylophone_bus_render;
}
