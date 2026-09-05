// gf_pitch.c — Implementation of the monophonic pitch tracker.
// See gf_pitch.h for the method and why it is autocorrelation.

#include "gf_pitch.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

// ── Configuration ────────────────────────────────────────────────────────────

/// Decimation factor before correlating. Four puts a 48 kHz stream at 12 kHz,
/// whose Nyquist is still far above the highest pitch tracked here.
#define GF_PITCH_DECIM 4

/// Analysis window in decimated samples. 512 at 12 kHz is ~43 ms — long
/// enough to hold two periods of the lowest pitch tracked, which correlation
/// needs to see a period at all.
#define GF_PITCH_WINDOW 512

/// How often analysis runs, in decimated samples. Every 128 (~10 ms) keeps
/// the estimate current enough to follow a sung line without running the
/// correlation on every block.
#define GF_PITCH_HOP 128

/// Pitch range, in Hz. Covers a bass voice or a guitar's low E at the bottom
/// and a soprano at the top.
#define GF_PITCH_MIN_HZ 65.0f
#define GF_PITCH_MAX_HZ 1000.0f

/// Below this normalised correlation the estimate is discarded. Voiced
/// speech and sung notes sit well above it; noise and consonants do not.
#define GF_PITCH_MIN_CONFIDENCE 0.60f

/// The "looks like itself" threshold from the YIN paper. The first lag whose
/// normalised difference drops below this is taken as the period.
#define GF_PITCH_YIN_THRESHOLD 0.15

struct gf_pitch {
    float sample_rate;

    /// Decimating low-pass state (two cascaded one-poles, ~1.5 kHz).
    ///
    /// Without it, everything above the reduced Nyquist folds down into the
    /// correlation and invents periodicity that is not there.
    float lp1, lp2;
    float lp_coeff;

    /// Sample counter for the decimator.
    int decim_phase;

    /// Decimated analysis buffer, used as a sliding window.
    float buf[GF_PITCH_WINDOW];
    int   filled;      // decimated samples currently in buf

    /// Lag range corresponding to the pitch range, in decimated samples.
    int min_lag, max_lag;

    /// Difference function and its cumulative-mean normalisation, one entry
    /// per candidate lag. Kept in the struct so analysis never allocates.
    double diff[GF_PITCH_WINDOW / 2 + 2];
    double cmnd[GF_PITCH_WINDOW / 2 + 2];

    float midi_note;   // negative when nothing usable is heard
    float confidence;
};

gf_pitch* gf_pitch_create(float sample_rate) {
    if (sample_rate < 8000.0f || sample_rate > 192000.0f) return NULL;

    gf_pitch* p = (gf_pitch*)calloc(1, sizeof(gf_pitch));
    if (!p) return NULL;

    p->sample_rate = sample_rate;
    const float decimated = sample_rate / (float)GF_PITCH_DECIM;

    // One-pole coefficient for a ~1.5 kHz corner at the *input* rate.
    const float cutoff = 1500.0f;
    p->lp_coeff = 1.0f - expf(-2.0f * 3.14159265f * cutoff / sample_rate);

    // lag = decimated_rate / frequency, so the highest pitch gives the
    // shortest lag.
    p->min_lag = (int)(decimated / GF_PITCH_MAX_HZ);
    p->max_lag = (int)(decimated / GF_PITCH_MIN_HZ) + 1;
    if (p->min_lag < 2) p->min_lag = 2;
    if (p->max_lag > GF_PITCH_WINDOW / 2) p->max_lag = GF_PITCH_WINDOW / 2;

    p->midi_note = -1.0f;
    return p;
}

void gf_pitch_destroy(gf_pitch* p) { free(p); }

void gf_pitch_reset(gf_pitch* p) {
    if (!p) return;
    memset(p->buf, 0, sizeof(p->buf));
    p->lp1 = p->lp2 = 0.0f;
    p->decim_phase = 0;
    p->filled = 0;
    p->midi_note = -1.0f;
    p->confidence = 0.0f;
}

// ── Analysis ─────────────────────────────────────────────────────────────────

/// Estimates the period with the YIN difference function.
///
/// Plain autocorrelation cannot be used here. For a periodic signal the
/// correlation at twice the period is just as high as at the period itself,
/// and rounding decides which one wins — so a sung A3 comes out as A2 and
/// the whole harmony lands an octave low. Measured on synthetic voices,
/// half the test pitches came back an octave or two down.
///
/// YIN replaces "where is correlation highest" with "where does the signal
/// first look like itself", via the cumulative mean normalised difference:
/// each lag's difference is divided by the running mean of all shorter lags,
/// which pushes multiples of the true period *up* rather than leaving them
/// tied. Taking the first lag under an absolute threshold, rather than the
/// global best, then picks the fundamental instead of a multiple of it.
static void gf_pitch_analyse(gf_pitch* p) {
    const float* x = p->buf;
    const int span = GF_PITCH_WINDOW / 2;   // samples compared at each lag

    // Silence has no pitch, and normalising it would yield a very confident
    // answer about nothing.
    double energy = 0.0;
    for (int i = 0; i < GF_PITCH_WINDOW; i++) energy += (double)x[i] * x[i];
    if (energy < 1e-7) {
        p->midi_note = -1.0f;
        p->confidence = 0.0f;
        return;
    }

    // Squared difference between the window and itself delayed by tau.
    for (int tau = 0; tau <= p->max_lag; tau++) {
        double sum = 0.0;
        for (int i = 0; i < span; i++) {
            const double d = (double)x[i] - (double)x[i + tau];
            sum += d * d;
        }
        p->diff[tau] = sum;
    }

    // Cumulative mean normalisation. Dividing by the running mean of every
    // shorter lag is what stops a multiple of the period scoring as well as
    // the period.
    p->cmnd[0] = 1.0;
    double running = 0.0;
    for (int tau = 1; tau <= p->max_lag; tau++) {
        running += p->diff[tau];
        p->cmnd[tau] = (running > 1e-12)
                ? p->diff[tau] * (double)tau / running
                : 1.0;
    }

    // First lag under the threshold, walked down to its local minimum —
    // deliberately not the global minimum, which is frequently a multiple.
    int best = -1;
    for (int tau = p->min_lag; tau <= p->max_lag; tau++) {
        if (p->cmnd[tau] < GF_PITCH_YIN_THRESHOLD) {
            while (tau + 1 <= p->max_lag && p->cmnd[tau + 1] < p->cmnd[tau]) tau++;
            best = tau;
            break;
        }
    }
    if (best < 0) {
        // Nothing crossed the threshold: fall back to the best candidate and
        // let the confidence check below decide whether to trust it.
        double lowest = 1e18;
        for (int tau = p->min_lag; tau <= p->max_lag; tau++) {
            if (p->cmnd[tau] < lowest) { lowest = p->cmnd[tau]; best = tau; }
        }
    }
    if (best < 0) {
        p->midi_note = -1.0f;
        p->confidence = 0.0f;
        return;
    }

    const float confidence = 1.0f - (float)p->cmnd[best];
    if (confidence < GF_PITCH_MIN_CONFIDENCE) {
        p->midi_note = -1.0f;
        p->confidence = (confidence > 0.0f) ? confidence : 0.0f;
        return;
    }

    // Parabolic interpolation around the dip: the true period rarely lands
    // on a whole sample, and without this the estimate quantises audibly at
    // high pitches where one lag step is a large fraction of a semitone.
    float refined = (float)best;
    if (best > p->min_lag && best < p->max_lag) {
        const double cm = p->cmnd[best - 1];
        const double c0 = p->cmnd[best];
        const double cp = p->cmnd[best + 1];
        const double d  = 2.0 * (2.0 * c0 - cm - cp);
        if (fabs(d) > 1e-12) refined += (float)((cp - cm) / d);
    }

    const float decimated = p->sample_rate / (float)GF_PITCH_DECIM;
    const float hz = decimated / refined;
    if (hz < GF_PITCH_MIN_HZ || hz > GF_PITCH_MAX_HZ) {
        p->midi_note = -1.0f;
        p->confidence = confidence;
        return;
    }

    // MIDI note 69 is A4 = 440 Hz.
    p->midi_note  = 69.0f + 12.0f * log2f(hz / 440.0f);
    p->confidence = confidence;
}

void gf_pitch_process(gf_pitch* p, const float* in, int n) {
    if (!p || !in || n <= 0) return;

    for (int i = 0; i < n; i++) {
        // Anti-alias before decimating.
        p->lp1 += (in[i] - p->lp1) * p->lp_coeff;
        p->lp2 += (p->lp1 - p->lp2) * p->lp_coeff;

        if (++p->decim_phase < GF_PITCH_DECIM) continue;
        p->decim_phase = 0;

        // Append; the window is compacted by a whole hop after each
        // analysis rather than shifted by one every sample, which would cost
        // a window-length move per sample on the audio thread.
        p->buf[p->filled++] = p->lp2;

        if (p->filled >= GF_PITCH_WINDOW) {
            gf_pitch_analyse(p);
            memmove(p->buf, p->buf + GF_PITCH_HOP,
                    sizeof(float) * (GF_PITCH_WINDOW - GF_PITCH_HOP));
            p->filled = GF_PITCH_WINDOW - GF_PITCH_HOP;
        }
    }
}

float gf_pitch_midi_note(const gf_pitch* p) { return p ? p->midi_note : -1.0f; }
float gf_pitch_confidence(const gf_pitch* p) { return p ? p->confidence : 0.0f; }
