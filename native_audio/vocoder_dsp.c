/**
 * vocoder_dsp.c — Context-based vocoder DSP implementation.
 *
 * Algorithm ported from audio_input.c data_callback() into a context struct
 * so that the GrooveForge Vocoder VST3 can hold its own independent instance.
 * No miniaudio dependency — voice audio is supplied by the caller.
 */

#include "vocoder_dsp.h"

#include <math.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* ── Internal types ──────────────────────────────────────────────────────── */

typedef struct {
    float a0, a1, a2, b1, b2;
    float z1, z2;
} Biquad;

typedef struct {
    Biquad modFilter;
    Biquad carFilter;
    float  envelope;
} VocoderBand;

#define PSOLA_OA_SIZE 1024
#define ACF_WINDOW    1024
#define ACF_MAX_LAG   600   /* 80 Hz at 48 kHz  */
#define ACF_MIN_LAG   48    /* 1000 Hz at 48 kHz */

typedef struct {
    bool  active;
    int   midiKey;
    float frequency;
    float phase, phase2, phase3;
    float velocity;
    float envelope;
    int   releaseSamples;
    float filterState;
    float pulseTimer;
    float oaBuffer[PSOLA_OA_SIZE];
    int   oaCursor;
} Oscillator;

struct VocoderContext {
    float        sampleRate;

    /* Filter bank */
    VocoderBand  bands[VD_NUM_BANDS];

    /* Polyphonic carrier oscillators */
    Oscillator   voices[VD_MAX_POLYPHONY];

    /* Parameters */
    int   waveform;
    float noiseMix;
    float envRelease;
    float gateThreshold;
    float inputGain;
    float qFactor;      /* derived from bandwidth param */

    /* ACF pitch estimator (Natural waveform only) */
    float acfBuffer[ACF_WINDOW];
    int   acfCounter;
    float micPitchHz;
    float naturalWavetable[ACF_MAX_LAG * 2];
    int   naturalWavetableLen;
    float naturalMaxCorr;

    /* Per-block filter state */
    float sibilanceZ1, sibilanceZ2;
    float squelchEnv;
};

/* ── Static DSP helpers (mirrored from audio_input.c) ───────────────────── */

static float note_to_freq(int midiNote) {
    return 440.0f * powf(2.0f, (float)(midiNote - 69) / 12.0f);
}

static void calc_bandpass(Biquad* f, float freq, float q, float sampleRate) {
    float w0    = 2.0f * (float)M_PI * freq / sampleRate;
    float cosW0 = cosf(w0);
    float sinW0 = sinf(w0);
    float alpha = sinW0 / (2.0f * q);
    float b0    = alpha;
    float b1t   = 0.0f;
    float b2    = -alpha;
    float a0i   = 1.0f / (1.0f + alpha);
    f->a0 = b0   * a0i;
    f->a1 = b1t  * a0i;
    f->a2 = b2   * a0i;
    f->b1 = -2.0f * cosW0 * a0i;
    f->b2 = (1.0f - alpha) * a0i;
    f->z1 = f->z2 = 0.0f;
}

static float process_biquad(Biquad* f, float in) {
    float out = f->a0 * in + f->z1;
    f->z1     = f->a1 * in - f->b1 * out + f->z2;
    f->z2     = f->a2 * in - f->b2 * out;
    return out;
}

static void init_bands(VocoderContext* ctx) {
    float minFreq = 80.0f, maxFreq = 12000.0f;
    float q = 0.3f + ctx->qFactor * 3.7f;   /* map 0..1 → 0.3..4.0 */
    for (int b = 0; b < VD_NUM_BANDS; ++b) {
        float freq = minFreq * powf(maxFreq / minFreq, (float)b / (VD_NUM_BANDS - 1));
        calc_bandpass(&ctx->bands[b].modFilter, freq, q, ctx->sampleRate);
        calc_bandpass(&ctx->bands[b].carFilter, freq, q, ctx->sampleRate);
    }
}

static float soft_clip(float x) {
    return x / (1.0f + fabsf(x));
}

static float pre_filter_mic(float in) {
    /* Simple 1-pole high-pass to remove DC/rumble */
    static float z = 0.0f;
    float out = in - z;
    z = in * 0.995f;
    return out;
}

static float render_oscillator(Oscillator* osc, float sampleRate, int waveform,
                               float micPitchHz, const float* wavetable,
                               int wavetableLen) {
    float out = 0.0f;
    switch (waveform) {
        case VD_WAVE_SAW:
            osc->phase  = fmodf(osc->phase  + osc->frequency / sampleRate, 1.0f);
            osc->phase2 = fmodf(osc->phase2 + osc->frequency * 1.003f / sampleRate, 1.0f);
            osc->phase3 = fmodf(osc->phase3 + osc->frequency * 0.997f / sampleRate, 1.0f);
            out = ((osc->phase  * 2.0f - 1.0f) +
                   (osc->phase2 * 2.0f - 1.0f) * 0.5f +
                   (osc->phase3 * 2.0f - 1.0f) * 0.5f) / 2.0f;
            break;
        case VD_WAVE_SQUARE:
            osc->phase = fmodf(osc->phase + osc->frequency / sampleRate, 1.0f);
            out = (osc->phase < 0.5f) ? 0.7f : -0.7f;
            break;
        case VD_WAVE_CHORAL: {
            osc->phase  = fmodf(osc->phase  + osc->frequency / sampleRate, 1.0f);
            osc->phase2 = fmodf(osc->phase2 + osc->frequency * 1.007f / sampleRate, 1.0f);
            osc->phase3 = fmodf(osc->phase3 + osc->frequency * 0.993f / sampleRate, 1.0f);
            /* Glottal pulse: half-wave rectified + filtered */
            float p1 = (osc->phase  < 0.6f) ? sinf(osc->phase  * (float)M_PI / 0.6f) : 0.0f;
            float p2 = (osc->phase2 < 0.6f) ? sinf(osc->phase2 * (float)M_PI / 0.6f) : 0.0f;
            float p3 = (osc->phase3 < 0.6f) ? sinf(osc->phase3 * (float)M_PI / 0.6f) : 0.0f;
            float raw = (p1 + p2 * 0.7f + p3 * 0.7f) / 2.4f;
            osc->filterState = osc->filterState * 0.6f + raw * 0.4f;
            out = osc->filterState;
            break;
        }
        case VD_WAVE_NATURAL:
            if (wavetableLen > 0) {
                /* PSOLA-style grain playback */
                float grainRate = osc->frequency / fmaxf(micPitchHz, 40.0f);
                osc->pulseTimer += grainRate;
                if (osc->pulseTimer >= 1.0f) {
                    osc->pulseTimer -= 1.0f;
                    osc->oaCursor = 0;
                }
                if (osc->oaCursor < wavetableLen) {
                    float pos   = (float)osc->oaCursor / (float)wavetableLen;
                    float hann  = 0.5f - 0.5f * cosf(2.0f * (float)M_PI * pos);
                    out = wavetable[osc->oaCursor] * hann;
                    osc->oaBuffer[osc->oaCursor % PSOLA_OA_SIZE] = out;
                    osc->oaCursor++;
                }
            } else {
                /* Fallback: sine */
                osc->phase = fmodf(osc->phase + osc->frequency / sampleRate, 1.0f);
                out = sinf(osc->phase * 2.0f * (float)M_PI);
            }
            break;
    }
    return out;
}

/* ── Public API ──────────────────────────────────────────────────────────── */

VocoderContext* vocoder_dsp_create(float sample_rate) {
    VocoderContext* ctx = (VocoderContext*)calloc(1, sizeof(VocoderContext));
    if (!ctx) return NULL;

    ctx->sampleRate          = sample_rate;
    ctx->waveform            = VD_WAVE_SAW;
    ctx->noiseMix            = 0.05f;
    ctx->envRelease          = 0.02f;
    ctx->gateThreshold       = 0.01f;
    ctx->inputGain           = 1.0f;
    ctx->qFactor             = 0.15f;   /* default: moderate bandwidth */
    ctx->micPitchHz          = 150.0f;
    ctx->naturalWavetableLen = 0;
    ctx->naturalMaxCorr      = 0.0f;

    init_bands(ctx);
    return ctx;
}

void vocoder_dsp_destroy(VocoderContext* ctx) {
    free(ctx);
}

void vocoder_dsp_note_on(VocoderContext* ctx, int key, int velocity) {
    for (int i = 0; i < VD_MAX_POLYPHONY; ++i) {
        if (!ctx->voices[i].active && ctx->voices[i].releaseSamples == 0) {
            ctx->voices[i].active        = true;
            ctx->voices[i].midiKey       = key;
            ctx->voices[i].frequency     = note_to_freq(key);
            ctx->voices[i].velocity      = (float)velocity;
            ctx->voices[i].phase         = (float)rand() / (float)RAND_MAX;
            ctx->voices[i].phase2        = (float)rand() / (float)RAND_MAX;
            ctx->voices[i].phase3        = (float)rand() / (float)RAND_MAX;
            ctx->voices[i].envelope      = 1.0f;
            ctx->voices[i].releaseSamples = 0;
            ctx->voices[i].filterState   = 0.0f;
            ctx->voices[i].pulseTimer    = 0.0f;
            return;
        }
    }
    /* Voice-steal: kill the quietest active voice */
    int   victim = 0;
    float minEnv = ctx->voices[0].envelope;
    for (int i = 1; i < VD_MAX_POLYPHONY; ++i) {
        if (ctx->voices[i].envelope < minEnv) { minEnv = ctx->voices[i].envelope; victim = i; }
    }
    ctx->voices[victim].active         = true;
    ctx->voices[victim].midiKey        = key;
    ctx->voices[victim].frequency      = note_to_freq(key);
    ctx->voices[victim].velocity       = (float)velocity;
    ctx->voices[victim].envelope       = 1.0f;
    ctx->voices[victim].releaseSamples = 0;
}

void vocoder_dsp_note_off(VocoderContext* ctx, int key) {
    for (int i = 0; i < VD_MAX_POLYPHONY; ++i) {
        if (ctx->voices[i].active && ctx->voices[i].midiKey == key) {
            ctx->voices[i].active         = false;
            ctx->voices[i].releaseSamples = 240;
        }
    }
}

void vocoder_dsp_all_notes_off(VocoderContext* ctx) {
    memset(ctx->voices, 0, sizeof(ctx->voices));
}

void vocoder_dsp_set_waveform(VocoderContext* ctx, int waveform) {
    ctx->waveform = waveform;
}

void vocoder_dsp_set_noise_mix(VocoderContext* ctx, float v) {
    ctx->noiseMix = v;
}

void vocoder_dsp_set_env_release(VocoderContext* ctx, float v) {
    ctx->envRelease = v;
}

void vocoder_dsp_set_bandwidth(VocoderContext* ctx, float v) {
    ctx->qFactor = v;
    init_bands(ctx);   /* recompute filter coefficients */
}

void vocoder_dsp_set_gate_threshold(VocoderContext* ctx, float v) {
    ctx->gateThreshold = v;
}

void vocoder_dsp_set_input_gain(VocoderContext* ctx, float v) {
    ctx->inputGain = v;
}

void vocoder_dsp_process(VocoderContext* ctx,
                         const float*    voice_in,
                         float*          out_l,
                         float*          out_r,
                         int             nframes) {
    /* Count active voices once per block */
    int activeVoices = 0;
    for (int v = 0; v < VD_MAX_POLYPHONY; ++v) {
        if (ctx->voices[v].active || ctx->voices[v].releaseSamples > 0) activeVoices++;
    }

    /* ACF pitch detection for Natural waveform */
    if (ctx->waveform == VD_WAVE_NATURAL && activeVoices > 0) {
        for (int i = 0; i < nframes; ++i) {
            ctx->acfBuffer[ctx->acfCounter++] = voice_in[i];
            if (ctx->acfCounter >= ACF_WINDOW) {
                float maxCorr = -1.0f;
                int   bestLag = -1;
                for (int lag = ACF_MIN_LAG; lag < ACF_MAX_LAG; lag++) {
                    float corr = 0.0f;
                    for (int j = 0; j < ACF_WINDOW - lag; j++)
                        corr += ctx->acfBuffer[j] * ctx->acfBuffer[j + lag];
                    if (corr > maxCorr) { maxCorr = corr; bestLag = lag; }
                }
                if (bestLag > 0) {
                    float hz = ctx->sampleRate / (float)bestLag;
                    ctx->micPitchHz = ctx->micPitchHz * 0.9f + hz * 0.1f;
                    float energy = 0.0f;
                    for (int j = 0; j < bestLag; j++)
                        energy += ctx->acfBuffer[j] * ctx->acfBuffer[j];
                    float norm = (energy > 1e-6f)
                        ? (1.0f / sqrtf(energy / (float)bestLag)) * 0.5f : 0.0f;
                    if (maxCorr > ctx->naturalMaxCorr * 0.8f || maxCorr > 0.5f) {
                        ctx->naturalMaxCorr = maxCorr;
                        int len = bestLag * 2;
                        if (len > ACF_MAX_LAG * 2) len = ACF_MAX_LAG * 2;
                        for (int j = 0; j < len; j++) {
                            int src = j % ACF_WINDOW;
                            ctx->naturalWavetable[j] = ctx->acfBuffer[src] * norm;
                        }
                        ctx->naturalWavetableLen = len;
                    }
                }
                ctx->acfCounter = 0;
            }
        }
    }

    /* Sibilance HP filter coefficients (fixed — same as audio_input.c) */
    const float hp_b0 = 0.65f, hp_b1 = -1.3f, hp_b2 = 0.65f;
    const float hp_a1 = -0.8f, hp_a2 = 0.2f;

    for (int i = 0; i < nframes; ++i) {
        float micRaw  = voice_in[i] * ctx->inputGain;
        float absMic  = fabsf(micRaw);

        /* Noise gate */
        float micIn = (absMic < ctx->gateThreshold) ? 0.0f : pre_filter_mic(micRaw);

        /* Squelch when no keys held */
        if (activeVoices == 0) {
            const float sqAtk = 0.05f, sqRel = 0.002f, sqThr = 0.003f;
            ctx->squelchEnv = (absMic > ctx->squelchEnv)
                ? ctx->squelchEnv * (1.0f - sqAtk) + absMic * sqAtk
                : ctx->squelchEnv * (1.0f - sqRel) + absMic * sqRel;
            if (ctx->squelchEnv < sqThr) { micIn = 0.0f; ctx->squelchEnv = 0.0f; }
        } else {
            ctx->squelchEnv = absMic;
        }

        /* Carrier oscillator sum */
        float synthMix = 0.0f;
        if (activeVoices > 0) {
            for (int v = 0; v < VD_MAX_POLYPHONY; ++v) {
                Oscillator* osc = &ctx->voices[v];
                if (osc->active || osc->releaseSamples > 0) {
                    if (!osc->active && osc->releaseSamples > 0) {
                        osc->envelope -= (1.0f / 240.0f);
                        osc->releaseSamples--;
                        if (osc->envelope <= 0.0f) { osc->envelope = 0.0f; osc->releaseSamples = 0; }
                    }
                    float gain = (ctx->waveform == VD_WAVE_NATURAL) ? 1.2f : 0.8f;
                    synthMix += render_oscillator(osc, ctx->sampleRate, ctx->waveform,
                                                  ctx->micPitchHz,
                                                  ctx->naturalWavetable,
                                                  ctx->naturalWavetableLen)
                                * (osc->velocity / 127.0f) * osc->envelope * gain;
                }
            }
        }

        /* Analysis filter bank: modulator (voice) */
        for (int b = 0; b < VD_NUM_BANDS; ++b) {
            float mod  = process_biquad(&ctx->bands[b].modFilter, micIn);
            float abm  = fabsf(mod);
            ctx->bands[b].envelope = (abm > ctx->bands[b].envelope)
                ? ctx->bands[b].envelope * (1.0f - 0.01f) + abm * 0.01f
                : ctx->bands[b].envelope * (1.0f - ctx->envRelease) + abm * ctx->envRelease;
            if (ctx->bands[b].envelope < 1e-6f) ctx->bands[b].envelope = 0.0f;
        }

        /* Synthesis filter bank: carrier shaped by envelope */
        float vocoderOut = 0.0f;
        if (activeVoices > 0) {
            for (int b = 0; b < VD_NUM_BANDS; ++b)
                vocoderOut += process_biquad(&ctx->bands[b].carFilter, synthMix)
                              * ctx->bands[b].envelope;

            float scale = (ctx->waveform == VD_WAVE_SAW)    ? 18.0f :
                          (ctx->waveform == VD_WAVE_SQUARE)  ? 15.0f :
                          (ctx->waveform == VD_WAVE_CHORAL)  ? 20.0f : 15.0f;
            vocoderOut *= scale;

            /* Sibilance injection */
            float sib  = micIn * hp_b0 + ctx->sibilanceZ1;
            ctx->sibilanceZ1 = micIn * hp_b1 - sib * hp_a1 + ctx->sibilanceZ2;
            ctx->sibilanceZ2 = micIn * hp_b2 - sib * hp_a2;
            float sibScale = (ctx->waveform <= VD_WAVE_SQUARE) ? 4.5f :
                             (ctx->waveform == VD_WAVE_CHORAL)  ? 2.5f : 1.5f;
            vocoderOut += sib * ctx->noiseMix * sibScale;
        } else {
            /* Keep HP filter state current even when silent */
            float sib        = micIn * hp_b0 + ctx->sibilanceZ1;
            ctx->sibilanceZ1 = micIn * hp_b1 - sib * hp_a1 + ctx->sibilanceZ2;
            ctx->sibilanceZ2 = micIn * hp_b2 - sib * hp_a2;
        }

        float sample = soft_clip(vocoderOut) * 0.95f;
        out_l[i] = sample;
        out_r[i] = sample;   /* mono → stereo */
    }
}
