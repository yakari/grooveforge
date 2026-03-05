#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <math.h>
#include <stdio.h>
#include <stdbool.h>

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

// Global state
static ma_context context;
static ma_device device;
static bool isInitialized = false;
static float currentInputPeak = 0.0f;
static float currentOutputPeak = 0.0f;
static Oscillator voices[MAX_POLYPHONY];

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

// Data callback for full-duplex audio processing
void data_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount)
{
    float* pOut = (float*)pOutput;
    const float* pIn = (const float*)pInput;
    float inPeak = 0.0f;
    float outPeak = 0.0f;
    
    // Peak-based Squelch Gate variables
    static float squelchEnv = 0.0f;
    const float squelchThreshold = 0.003f; // Require fairly loud input to open gate
    const float squelchAttack = 0.05f;     // Open instantly
    const float squelchRelease = 0.002f;   // Snap shut in ~100ms when talking stops

    // We process sample by sample
    for (ma_uint32 i = 0; i < frameCount; ++i) {
        float micInput = pIn ? pIn[i] : 0.0f;
        
        // Track visual input peak BEFORE the gate mutes it, so the user can see their raw mic level
        float absRawMic = fabsf(micInput);
        if (absRawMic > inPeak) inPeak = absRawMic;

        float synthMix = 0.0f;

        // Render Synthesizer Carrier
        for (int v = 0; v < MAX_POLYPHONY; ++v) {
            Oscillator* osc = &voices[v];
            if (osc->active || osc->releaseSamples > 0) {
                if (!osc->active && osc->releaseSamples > 0) {
                    osc->envelope -= (1.0f / 240.0f); 
                    osc->releaseSamples--;
                    if (osc->envelope <= 0.0f) {
                        osc->envelope = 0.0f;
                        osc->releaseSamples = 0;
                    }
                }
                float rawOsc = renderOscillator(osc);
                synthMix += rawOsc * (osc->velocity / 127.0f) * osc->envelope * 0.8f; 
            }
        }

        // Add user-controlled white noise to the synth for unvoiced sounds (sibilants like S, T, P)
        if (g_vocoderNoiseMix > 0.001f) {
            float noise = ((float)rand() / (float)RAND_MAX * 2.0f - 1.0f) * g_vocoderNoiseMix;
            synthMix += noise;
        }

        // Apply DC Blocker / Highpass to microphone
        micInput = pre_filter_mic(micInput);

        // --- HARD PEAK SQUELCH GATE ---
        // Instantly kill the mic if it drops below the threshold to violently break Larsen loops
        if (absRawMic > squelchEnv) {
            squelchEnv = squelchEnv * (1.0f - squelchAttack) + absRawMic * squelchAttack; // Fast open
        } else {
            squelchEnv = squelchEnv * (1.0f - squelchRelease) + absRawMic * squelchRelease; // Fast close
        }

        if (squelchEnv < squelchThreshold) {
            micInput = 0.0f;
            squelchEnv = 0.0f; // Force crush to prevent floating point stragglers
        }

        // --- Channel Vocoder Algorithm ---
        float vocoderOutput = 0.0f;
        float totalActiveVoices = 0.0f;

        for (int v = 0; v < MAX_POLYPHONY; ++v) {
            if (voices[v].active || voices[v].releaseSamples > 0) totalActiveVoices += 1.0f;
        }

        // ALWAYS process Modulator and Envelopes so they don't freeze when silent!
        for (int b = 0; b < NUM_BANDS; ++b) {
            // 1. Modulator (Mic) Bandpass
            float modSignal = processBiquad(&bands[b].modFilter, micInput);
            
            // 2. Envelope Follower (Full wave rectify + lowpass)
            float absMod = fabsf(modSignal);
            if (absMod > bands[b].envelope) {
                bands[b].envelope = absMod; // Instant attack
            } else {
                // Use the user-controlled envelope release parameter
                bands[b].envelope = bands[b].envelope * (1.0f - g_vocoderEnvRelease) + absMod * g_vocoderEnvRelease;
            }
            // Anti-denormal / Hard zero
            if (bands[b].envelope < 1e-6f) bands[b].envelope = 0.0f;
        }

        if (totalActiveVoices > 0.0f) {
            for (int b = 0; b < NUM_BANDS; ++b) {
                // 3. Carrier (Synth) Bandpass
                float carSignal = processBiquad(&bands[b].carFilter, synthMix);

                // 4. Amplitude Modulation (Restored basic linear multiplication)
                vocoderOutput += carSignal * bands[b].envelope;
            }
            // Add dynamic makeup gain to output
            vocoderOutput *= 20.0f;
        } else {
            // Silence when no notes are playing to prevent Larsen feedback loop!
            vocoderOutput = 0.0f; 
        }

        // Apply Soft Clipper to prevent harsh digital distortion from clipping
        vocoderOutput = soft_clip(vocoderOutput) * 0.95f;
        
        float absOut = fabsf(vocoderOutput);
        if (absOut > outPeak) outPeak = absOut;

        if (pOut) {
            pOut[i] = vocoderOutput; 
        }
    }

    if (inPeak > currentInputPeak) currentInputPeak = inPeak;
    if (outPeak > currentOutputPeak) currentOutputPeak = outPeak;
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
            voices[i].phase = ((float)rand() / (float)RAND_MAX); // Randomize start phase for natural chorus
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

// Initialize and start audio duplex
EXPORT int start_audio_capture() {
    if (isInitialized) return 0;

    // Initialize Vocoder DSP Filters dynamically
    envRelease = expf(-1.0f / (SAMPLE_RATE * 0.02f)); // 20ms release
    float minFreq = 80.0f;
    float maxFreq = 12000.0f;
    for (int b = 0; b < NUM_BANDS; ++b) {
        // Logarithmic spacing
        float freq = minFreq * powf(maxFreq / minFreq, (float)b / (NUM_BANDS - 1));
        // Q factor controls overlap. Q=12.0 gives clean, distinct formants for 32 bands
        calculateBandpass(&bands[b].modFilter, freq, 12.0f);
        calculateBandpass(&bands[b].carFilter, freq, 12.0f);
        bands[b].envelope = 0.0f;
    }

    // Reset voices
    for (int i = 0; i < MAX_POLYPHONY; ++i) {
        voices[i].active = false;
        voices[i].releaseSamples = 0;
    }

    ma_result result;
    ma_device_config deviceConfig;

    result = ma_context_init(NULL, 0, NULL, &context);
    if (result != MA_SUCCESS) {
        LOGE("Failed to initialize context: %d\n", result);
        return -1;
    }

    // Initialize as FULL DUPLEX (Capture AND Playback)
    deviceConfig = ma_device_config_init(ma_device_type_duplex);
    deviceConfig.performanceProfile = ma_performance_profile_low_latency;
    
#ifdef __ANDROID__
    // Ask Android Core Audio (AAudio / OpenSL) to apply Hardware Acoustic Echo Cancellation (AEC)
    deviceConfig.aaudio.inputPreset = ma_aaudio_input_preset_voice_communication;
    deviceConfig.opensl.recordingPreset = ma_opensl_recording_preset_voice_communication;
#endif

    // Capture config
    deviceConfig.capture.pDeviceID = NULL; 
    deviceConfig.capture.format    = ma_format_f32;
    deviceConfig.capture.channels  = CHANNELS;
    
    // Playback config
    deviceConfig.playback.pDeviceID = NULL; 
    deviceConfig.playback.format    = ma_format_f32;
    deviceConfig.playback.channels  = CHANNELS;

    deviceConfig.sampleRate        = SAMPLE_RATE;
    deviceConfig.dataCallback      = data_callback;

    result = ma_device_init(&context, &deviceConfig, &device);
    if (result != MA_SUCCESS) {
        LOGE("Failed to initialize device: %d\n", result);
        ma_context_uninit(&context);
        return -2;
    }

    result = ma_device_start(&device);
    if (result != MA_SUCCESS) {
        LOGE("Failed to start device: %d\n", result);
        ma_device_uninit(&device);
        ma_context_uninit(&context);
        return -3;
    }

    LOGI("Audio duplex (Vocoder synth) started successfully!");

    isInitialized = true;
    return 0; // Success
}

EXPORT void stop_audio_capture() {
    if (!isInitialized) return;

    ma_device_stop(&device);
    ma_device_uninit(&device);
    ma_context_uninit(&context);

    isInitialized = false;
    currentInputPeak = 0.0f;
    currentOutputPeak = 0.0f;
}

EXPORT float getInputPeakLevel() {
    float peak = currentInputPeak;
    currentInputPeak = 0.0f;
    return peak;
}

EXPORT float getOutputPeakLevel() {
    float peak = currentOutputPeak;
    currentOutputPeak = 0.0f;
    return peak;
}

EXPORT void setVocoderParameters(int waveform, float noiseMix, float envRelease) {
    g_vocoderWaveform = waveform;
    g_vocoderNoiseMix = noiseMix;
    // Map a nice 0.0 - 1.0 value from the UI to the actual filter coefficient math
    // 0.0 -> very slow (0.005), 1.0 -> very fast (0.1)
    g_vocoderEnvRelease = 0.005f + (envRelease * 0.095f);
}

// Deprecated, mapped to input for backward compat if needed
EXPORT float getPeakLevel() {
    return getInputPeakLevel();
}
