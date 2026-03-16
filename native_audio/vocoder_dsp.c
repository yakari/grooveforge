/**
 * vocoder_dsp.c — Context-based vocoder DSP implementation.
 *
 * Algorithm ported from audio_input.c data_callback() into a context struct
 * so that the GrooveForge Vocoder VST3 can hold its own independent instance.
 * No miniaudio dependency — voice audio is supplied by the caller.
 *
 * Waveform modes:
 *   SAW, SQUARE, CHORAL — Classic phase-vocoder: 32-band filter bank drives a
 *     synthetic carrier oscillator.  Result is recognisably robotic.
 *
 *   NATURAL — Autotune / pitch-correction mode.  Bypasses the filter bank
 *     entirely.  Instead a PSOLA (Pitch-Synchronous Overlap-Add) pitch shifter
 *     reads from a 4096-sample ring buffer of raw mic audio and retunes it to
 *     the nearest held MIDI note.  The voice timbre and formants are preserved
 *     for small-to-moderate shifts (±6 semitones); the result sounds like
 *     classic autotune rather than a vocoder.
 *
 *     Algorithm:
 *       1. Every sample, write the (gated) mic signal into a circular ring
 *          buffer (AUTOTUNE_MIC_SIZE samples long).
 *       2. An ACF pitch estimator updates atuneDetectedLag — the source pitch
 *          period length in samples — once per ACF_WINDOW (1024 samples).
 *       3. A grain is triggered every targetPeriod = sampleRate / midiNoteHz
 *          output samples.  Each grain is TWO source pitch periods long
 *          (2 × atuneDetectedLag samples), Hann-windowed.  Using 2× the
 *          source period ensures ~50 % overlap when hop ≈ source period
 *          (no pitch shift); two 50%-overlapping Hann windows sum to 1.0
 *          at every point, giving a perfectly flat output amplitude with
 *          no grain-boundary dips or choppiness.
 *       4. Successive grains are overlap-added into a 1600-sample circular
 *          accumulation buffer (AUTOTUNE_OA_SIZE).  Each grain is written
 *          starting at the current output read position, so grains overlap
 *          by (grainLen − targetPeriod) samples — ~50 % for no shift, more
 *          for pitch-up, slightly less for moderate pitch-down.
 *       5. The accumulated sample is read, the cell cleared, and the result
 *          scaled and soft-clipped before writing to out_l / out_r.
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

/* ACF pitch estimator window and lag bounds */
#define ACF_WINDOW    1024   /* ~21 ms @ 48 kHz — one analysis frame */
#define ACF_MAX_LAG   600    /* 80 Hz lower bound @ 48 kHz            */
#define ACF_MIN_LAG   48     /* 1000 Hz upper bound @ 48 kHz          */

/* Autotune (NATURAL mode) ring buffer and OA accumulator sizes.
 * MIC: ~85 ms @ 48 kHz — always holds at least 2 source pitch periods even
 *   for the lowest detectable pitch (80 Hz → 600 samples per period).
 * OA:  must exceed 2 × max grain length (2 × 600 = 1200) to ensure write
 *   and read heads never collide on the circular accumulator. */
#define AUTOTUNE_MIC_SIZE 4096
#define AUTOTUNE_OA_SIZE  1600

typedef struct {
    bool  active;
    int   midiKey;
    float frequency;
    float phase, phase2, phase3;
    float velocity;
    float envelope;
    int   releaseSamples;
    float filterState;
} Oscillator;

struct VocoderContext {
    float       sampleRate;

    /* Filter bank */
    VocoderBand bands[VD_NUM_BANDS];

    /* Polyphonic carrier oscillators */
    Oscillator  voices[VD_MAX_POLYPHONY];

    /* Parameters */
    int   waveform;
    float noiseMix;
    float envRelease;
    float gateThreshold;
    float inputGain;
    float qFactor;      /* derived from bandwidth param */

    /* ACF pitch estimator — shared by all waveform modes for mic pitch Hz,
     * used by NATURAL mode to set the grain size. */
    float acfBuffer[ACF_WINDOW];
    int   acfCounter;
    float micPitchHz;

    /* Autotune state (NATURAL mode only) */
    float atuneMicBuf[AUTOTUNE_MIC_SIZE]; /* raw gated mic ring buffer        */
    int   atuneBufHead;                    /* write head (unmasked int)        */
    int   atuneDetectedLag;               /* source pitch period (samples)    */
    float atuneOutputTimer;               /* counts toward next grain trigger */
    float atuneOaBuf[AUTOTUNE_OA_SIZE];  /* overlap-add accumulation buffer  */
    int   atuneOaRead;                    /* OA read / grain-start position   */

    /* Per-block filter state */
    float sibilanceZ1, sibilanceZ2;
    float squelchEnv;
};

/* ── Static DSP helpers ──────────────────────────────────────────────────── */

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
    float q = 0.3f + ctx->qFactor * 3.7f;   /* 0..1 → 0.3..4.0 */
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
    /* 1-pole high-pass to remove DC and low-frequency rumble. */
    static float z = 0.0f;
    float out = in - z;
    z = in * 0.995f;
    return out;
}

/* ── Carrier oscillator (SAW / SQUARE / CHORAL only) ────────────────────── */

/**
 * Synthesises one sample of the carrier waveform for vocoder modes.
 *
 * NATURAL mode is handled separately in the main process loop (PSOLA path)
 * and never reaches this function.
 */
static float render_oscillator(Oscillator* osc, float sampleRate, int waveform) {
    float out = 0.0f;
    switch (waveform) {
        case VD_WAVE_SAW:
            /* Three detuned sawtooth waves (±0.3 %) for a richer carrier. */
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
            /* Glottal-pulse model: three detuned half-wave rectified sinusoids.
             * The 0.6-cycle open phase and decay-filtered output approximate
             * the spectral envelope of a human singing voice. */
            osc->phase  = fmodf(osc->phase  + osc->frequency / sampleRate, 1.0f);
            osc->phase2 = fmodf(osc->phase2 + osc->frequency * 1.007f / sampleRate, 1.0f);
            osc->phase3 = fmodf(osc->phase3 + osc->frequency * 0.993f / sampleRate, 1.0f);
            float p1 = (osc->phase  < 0.6f) ? sinf(osc->phase  * (float)M_PI / 0.6f) : 0.0f;
            float p2 = (osc->phase2 < 0.6f) ? sinf(osc->phase2 * (float)M_PI / 0.6f) : 0.0f;
            float p3 = (osc->phase3 < 0.6f) ? sinf(osc->phase3 * (float)M_PI / 0.6f) : 0.0f;
            float raw = (p1 + p2 * 0.7f + p3 * 0.7f) / 2.4f;
            osc->filterState = osc->filterState * 0.6f + raw * 0.4f;
            out = osc->filterState;
            break;
        }

        default:
            /* Fallback: silence.  NATURAL is handled before this is called. */
            break;
    }
    return out;
}

/* ── Public API ──────────────────────────────────────────────────────────── */

VocoderContext* vocoder_dsp_create(float sample_rate) {
    VocoderContext* ctx = (VocoderContext*)calloc(1, sizeof(VocoderContext));
    if (!ctx) return NULL;

    ctx->sampleRate         = sample_rate;
    ctx->waveform           = VD_WAVE_SAW;
    ctx->noiseMix           = 0.05f;
    ctx->envRelease         = 0.02f;
    ctx->gateThreshold      = 0.01f;
    ctx->inputGain          = 1.0f;
    ctx->qFactor            = 0.15f;
    ctx->micPitchHz         = 150.0f;   /* reasonable seed until ACF converges */
    ctx->atuneDetectedLag   = 0;        /* 0 = not yet detected — stay silent  */

    init_bands(ctx);
    return ctx;
}

void vocoder_dsp_destroy(VocoderContext* ctx) {
    free(ctx);
}

void vocoder_dsp_note_on(VocoderContext* ctx, int key, int velocity) {
    /* Find a free slot. */
    for (int i = 0; i < VD_MAX_POLYPHONY; ++i) {
        if (!ctx->voices[i].active && ctx->voices[i].releaseSamples == 0) {
            ctx->voices[i].active         = true;
            ctx->voices[i].midiKey        = key;
            ctx->voices[i].frequency      = note_to_freq(key);
            ctx->voices[i].velocity       = (float)velocity;
            ctx->voices[i].phase          = (float)rand() / (float)RAND_MAX;
            ctx->voices[i].phase2         = (float)rand() / (float)RAND_MAX;
            ctx->voices[i].phase3         = (float)rand() / (float)RAND_MAX;
            ctx->voices[i].envelope       = 1.0f;
            ctx->voices[i].releaseSamples = 0;
            ctx->voices[i].filterState    = 0.0f;
            return;
        }
    }
    /* Voice-steal: kill the quietest active voice. */
    int   victim = 0;
    float minEnv = ctx->voices[0].envelope;
    for (int i = 1; i < VD_MAX_POLYPHONY; ++i) {
        if (ctx->voices[i].envelope < minEnv) {
            minEnv = ctx->voices[i].envelope;
            victim = i;
        }
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
    /* Clear the OA accumulator on mode change to avoid stale audio bleeding
     * into the first few grains when switching back to NATURAL. */
    memset(ctx->atuneOaBuf, 0, sizeof(ctx->atuneOaBuf));
    ctx->atuneOaRead       = 0;
    ctx->atuneOutputTimer  = 0.0f;
}

void vocoder_dsp_set_noise_mix(VocoderContext* ctx, float v) {
    ctx->noiseMix = v;
}

void vocoder_dsp_set_env_release(VocoderContext* ctx, float v) {
    ctx->envRelease = v;
}

void vocoder_dsp_set_bandwidth(VocoderContext* ctx, float v) {
    ctx->qFactor = v;
    init_bands(ctx);
}

void vocoder_dsp_set_gate_threshold(VocoderContext* ctx, float v) {
    ctx->gateThreshold = v;
}

void vocoder_dsp_set_input_gain(VocoderContext* ctx, float v) {
    ctx->inputGain = v;
}

/* ── Main process loop ───────────────────────────────────────────────────── */

void vocoder_dsp_process(VocoderContext* ctx,
                         const float*    voice_in,
                         float*          out_l,
                         float*          out_r,
                         int             nframes) {
    /* Count active voices once per block — used by both paths. */
    int activeVoices = 0;
    for (int v = 0; v < VD_MAX_POLYPHONY; ++v) {
        if (ctx->voices[v].active || ctx->voices[v].releaseSamples > 0) {
            activeVoices++;
        }
    }

    /* ── ACF pitch detector ─────────────────────────────────────────────── */
    /* Runs for all modes.  Updates micPitchHz and (for NATURAL mode)
     * atuneDetectedLag so the PSOLA grain size tracks the voice pitch. */
    for (int i = 0; i < nframes; ++i) {
        ctx->acfBuffer[ctx->acfCounter++] = voice_in[i];
        if (ctx->acfCounter >= ACF_WINDOW) {
            /* Autocorrelation: find the lag that best matches one pitch period.
             * Range: ACF_MIN_LAG (1 kHz) .. ACF_MAX_LAG (80 Hz) at 48 kHz. */
            float maxCorr = -1.0f;
            int   bestLag = -1;
            for (int lag = ACF_MIN_LAG; lag < ACF_MAX_LAG; lag++) {
                float corr = 0.0f;
                for (int j = 0; j < ACF_WINDOW - lag; j++) {
                    corr += ctx->acfBuffer[j] * ctx->acfBuffer[j + lag];
                }
                if (corr > maxCorr) { maxCorr = corr; bestLag = lag; }
            }
            if (bestLag > 0) {
                /* Smooth the Hz estimate to prevent abrupt waveform jumps. */
                float hz = ctx->sampleRate / (float)bestLag;
                ctx->micPitchHz = ctx->micPitchHz * 0.9f + hz * 0.1f;
                /* Store the raw lag for the PSOLA grain sizer — no smoothing
                 * so each grain matches exactly one source pitch period. */
                ctx->atuneDetectedLag = bestLag;
            }
            ctx->acfCounter = 0;
        }
    }

    /* Sibilance HP filter coefficients (fixed). */
    const float hp_b0 = 0.65f, hp_b1 = -1.3f, hp_b2 = 0.65f;
    const float hp_a1 = -0.8f, hp_a2 = 0.2f;

    for (int i = 0; i < nframes; ++i) {
        float micRaw = voice_in[i] * ctx->inputGain;
        float absMic = fabsf(micRaw);

        /* ── Noise gate ──────────────────────────────────────────────────── */
        float micIn = (absMic < ctx->gateThreshold) ? 0.0f
                                                     : pre_filter_mic(micRaw);

        /* ── Squelch (silence when no keys are held) ─────────────────────── */
        if (activeVoices == 0) {
            const float sqAtk = 0.05f, sqRel = 0.002f, sqThr = 0.003f;
            ctx->squelchEnv = (absMic > ctx->squelchEnv)
                ? ctx->squelchEnv * (1.0f - sqAtk) + absMic * sqAtk
                : ctx->squelchEnv * (1.0f - sqRel) + absMic * sqRel;
            if (ctx->squelchEnv < sqThr) {
                micIn = 0.0f;
                ctx->squelchEnv = 0.0f;
            }
        } else {
            ctx->squelchEnv = absMic;
        }

        /* ═══════════════════════════════════════════════════════════════════
         * NATURAL mode — PSOLA autotune pitch shifter.
         * Bypasses the carrier oscillators and filter bank entirely.
         * ═══════════════════════════════════════════════════════════════════ */
        if (ctx->waveform == VD_WAVE_NATURAL) {
            /* Step 1: push gated mic sample into ring buffer. */
            ctx->atuneMicBuf[ctx->atuneBufHead % AUTOTUNE_MIC_SIZE] = micIn;
            ctx->atuneBufHead++;

            float sample = 0.0f;

            if (activeVoices > 0 && ctx->atuneDetectedLag > 0) {
                /* Find the lowest held MIDI note — autotune snaps the voice
                 * to a single pitch (the key the player holds). */
                float targetHz = 0.0f;
                float maxVel   = 0.0f;
                for (int v = 0; v < VD_MAX_POLYPHONY; ++v) {
                    Oscillator* osc = &ctx->voices[v];
                    if (osc->active || osc->releaseSamples > 0) {
                        /* Decay the release envelope for releasing voices. */
                        if (!osc->active && osc->releaseSamples > 0) {
                            osc->envelope -= (1.0f / 240.0f);
                            osc->releaseSamples--;
                            if (osc->envelope <= 0.0f) {
                                osc->envelope       = 0.0f;
                                osc->releaseSamples = 0;
                            }
                        }
                        /* Pick the lowest active frequency (bass note). */
                        if (targetHz == 0.0f || osc->frequency < targetHz) {
                            targetHz = osc->frequency;
                        }
                        /* Track peak velocity × envelope for output scaling. */
                        float ve = (osc->velocity / 127.0f) * osc->envelope;
                        if (ve > maxVel) maxVel = ve;
                    }
                }

                if (targetHz > 20.0f) {
                    /* Step 2: compute grain trigger interval and grain length.
                     *
                     * targetPeriod = synthesis hop — one output pitch period
                     *                in samples (= sampleRate / targetHz).
                     * grainLen     = TWO source pitch periods.
                     *
                     * Using 2× the detected source period as grain length is
                     * standard PSOLA practice: when hop ≈ srcLag (no pitch
                     * shift), consecutive grains overlap by exactly 50 %.
                     * Two 50%-overlapping Hann windows sum to 1.0 everywhere,
                     * so the output amplitude is continuous and flat — no dips
                     * at grain boundaries, no choppiness. */
                    float targetPeriod = ctx->sampleRate / targetHz;
                    int   grainLen     = 2 * ctx->atuneDetectedLag;

                    /* Clamp so the grain always fits inside the OA accumulator.
                     * With OA_SIZE = 1600 this caps grainLen at 800 samples,
                     * covering source pitches down to ~60 Hz @ 48 kHz. */
                    if (grainLen > AUTOTUNE_OA_SIZE / 2) {
                        grainLen = AUTOTUNE_OA_SIZE / 2;
                    }

                    /* Step 3: advance output timer; trigger a grain whenever
                     * one full target pitch period has elapsed. */
                    ctx->atuneOutputTimer += 1.0f;
                    if (ctx->atuneOutputTimer >= targetPeriod) {
                        ctx->atuneOutputTimer -= targetPeriod;

                        /* Read the most recent grainLen samples from the mic
                         * ring buffer — two source pitch periods ending at the
                         * current write head give us continuous voice content. */
                        int readStart =
                            (ctx->atuneBufHead - grainLen + AUTOTUNE_MIC_SIZE)
                            % AUTOTUNE_MIC_SIZE;

                        /* Overlap-add a Hann-windowed grain into the OA buffer,
                         * starting at the current output read position so that
                         * successive grains overlap by (grainLen - targetPeriod)
                         * samples — ~50 % for no pitch shift, more for pitch-up,
                         * less for pitch-down. */
                        for (int j = 0; j < grainLen; j++) {
                            float pos  = (float)j / (float)(grainLen - 1);
                            float hann = 0.5f - 0.5f * cosf(
                                2.0f * (float)M_PI * pos);
                            int src = (readStart + j) % AUTOTUNE_MIC_SIZE;
                            int dst = (ctx->atuneOaRead + j) % AUTOTUNE_OA_SIZE;
                            ctx->atuneOaBuf[dst] +=
                                ctx->atuneMicBuf[src] * hann;
                        }
                    }

                    /* Step 4: read one sample from the OA buffer, clear the
                     * cell, and advance the read head. */
                    sample = ctx->atuneOaBuf[ctx->atuneOaRead];
                    ctx->atuneOaBuf[ctx->atuneOaRead] = 0.0f;
                    ctx->atuneOaRead =
                        (ctx->atuneOaRead + 1) % AUTOTUNE_OA_SIZE;

                    /* Scale by velocity / release envelope and soft-clip.
                     * With 50 % Hann-window overlap the two summed windows
                     * already equal 1.0 at every point, so a factor of ~1.2
                     * (vs. the former 2.5 for single non-overlapping grains)
                     * gives the correct output level. */
                    sample = soft_clip(sample * maxVel * 1.2f) * 0.95f;
                }
            } else if (activeVoices == 0) {
                /* Drain the OA buffer to zero to prevent stale audio when a
                 * new note is pressed after a gap. */
                ctx->atuneOaBuf[ctx->atuneOaRead] = 0.0f;
                ctx->atuneOaRead =
                    (ctx->atuneOaRead + 1) % AUTOTUNE_OA_SIZE;
            }

            out_l[i] = sample;
            out_r[i] = sample;
            continue;   /* skip filterbank / sibilance injection below */
        }

        /* ═══════════════════════════════════════════════════════════════════
         * VOCODER modes (SAW / SQUARE / CHORAL) — classic filter-bank path.
         * ═══════════════════════════════════════════════════════════════════ */

        /* Carrier oscillator mix */
        float synthMix = 0.0f;
        if (activeVoices > 0) {
            for (int v = 0; v < VD_MAX_POLYPHONY; ++v) {
                Oscillator* osc = &ctx->voices[v];
                if (osc->active || osc->releaseSamples > 0) {
                    if (!osc->active && osc->releaseSamples > 0) {
                        osc->envelope -= (1.0f / 240.0f);
                        osc->releaseSamples--;
                        if (osc->envelope <= 0.0f) {
                            osc->envelope       = 0.0f;
                            osc->releaseSamples = 0;
                        }
                    }
                    synthMix += render_oscillator(osc, ctx->sampleRate,
                                                  ctx->waveform)
                                * (osc->velocity / 127.0f)
                                * osc->envelope
                                * 0.8f;
                }
            }
        }

        /* Modulator analysis: update per-band envelope from mic signal. */
        for (int b = 0; b < VD_NUM_BANDS; ++b) {
            float mod = process_biquad(&ctx->bands[b].modFilter, micIn);
            float abm = fabsf(mod);
            ctx->bands[b].envelope =
                (abm > ctx->bands[b].envelope)
                ? ctx->bands[b].envelope * (1.0f - 0.01f) + abm * 0.01f
                : ctx->bands[b].envelope * (1.0f - ctx->envRelease)
                      + abm * ctx->envRelease;
            if (ctx->bands[b].envelope < 1e-6f) ctx->bands[b].envelope = 0.0f;
        }

        /* Synthesis: shape carrier through the envelope-gated band filters. */
        float vocoderOut = 0.0f;
        if (activeVoices > 0) {
            for (int b = 0; b < VD_NUM_BANDS; ++b) {
                vocoderOut += process_biquad(&ctx->bands[b].carFilter, synthMix)
                              * ctx->bands[b].envelope;
            }

            float scale = (ctx->waveform == VD_WAVE_SAW)    ? 18.0f :
                          (ctx->waveform == VD_WAVE_SQUARE)  ? 15.0f : 20.0f;
            vocoderOut *= scale;

            /* Sibilance injection: high-pass filtered mic mixed in to restore
             * fricative consonants that the filter bank attenuates. */
            float sib  = micIn * hp_b0 + ctx->sibilanceZ1;
            ctx->sibilanceZ1 = micIn * hp_b1 - sib * hp_a1 + ctx->sibilanceZ2;
            ctx->sibilanceZ2 = micIn * hp_b2 - sib * hp_a2;
            float sibScale = (ctx->waveform == VD_WAVE_SAW)   ? 4.5f :
                             (ctx->waveform == VD_WAVE_SQUARE) ? 4.5f : 2.5f;
            vocoderOut += sib * ctx->noiseMix * sibScale;
        } else {
            /* Keep HP filter state valid even while silent. */
            float sib        = micIn * hp_b0 + ctx->sibilanceZ1;
            ctx->sibilanceZ1 = micIn * hp_b1 - sib * hp_a1 + ctx->sibilanceZ2;
            ctx->sibilanceZ2 = micIn * hp_b2 - sib * hp_a2;
        }

        float sample = soft_clip(vocoderOut) * 0.95f;
        out_l[i] = sample;
        out_r[i] = sample;
    }
}
