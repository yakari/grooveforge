// gf_aec.c — Implementation of the offline echo canceller.
// See gf_aec.h for what it does, why it is offline, and what it cannot remove.
//
// Layout of this file:
//   1. Context and lifecycle.
//   2. Block processing: the partitioned frequency-domain adaptive filter.
//   3. Delay estimation by GCC-PHAT.
//   4. File driver: two passes over a take.

#include "gf_aec.h"

#include <float.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gf_fft.h"
#include "gf_wav.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/// Transform length. Overlap-save needs twice the block so that the circular
/// convolution the FFT performs matches the linear one we actually want.
#define AEC_N (GF_AEC_BLOCK * 2)

/// Floats in one complex spectrum of AEC_N bins.
#define AEC_SPEC (AEC_N * 2)

/// Keeps the normalised step finite when a bin holds no energy at all —
/// silence between takes, or a band the speaker simply cannot reproduce.
#define AEC_EPS 1e-6f

/// How far below the average bin power a bin is still believed.
///
/// Anything quieter is treated as carrying that much, which caps how large the
/// normalised step can become in a band the reference barely occupies. 1% is
/// 20 dB down: quiet enough not to blunt adaptation in bands that genuinely
/// matter, loud enough that an empty band cannot divide the step by nothing.
#define AEC_POWER_FLOOR 0.01f

/// Reference power below which a block is taken as silence and not learned
/// from. Scaled for a 512-bin spectrum of 16-bit audio.
#define AEC_SILENCE 1e-9f

/// How far below the loudest recent block the reference may be and still be
/// learned from. 0.1 is 10 dB down — measured as the best balance between
/// learning enough and learning from noise.
#define AEC_LEARN_GATE 0.1f

/// How fast the long-term reference level forgets a loud passage, per block.
/// About a minute to fall by e at 48 kHz, which outlasts any quiet bar.
#define AEC_SCALE_DECAY 0.9999f

// ─── 1. Context and lifecycle ───────────────────────────────────────────────

struct gf_aec_context {
    int sample_rate;
    int partitions;     ///< Filter length in blocks.

    gf_fft fft;         ///< Shared transform, size AEC_N.

    float* w;           ///< Filter spectra, partitions * AEC_SPEC floats.
    float* xh;          ///< Reference spectra history, same size, circular.
    int    head;        ///< Index in [0, partitions) of the newest xh entry.

    float* xpow;        ///< |X|^2 per bin per partition, partitions * AEC_N.
    float* hist;        ///< Sum of xpow across partitions, AEC_N floats.
    float* xprev;       ///< Previous block of reference, GF_AEC_BLOCK floats.

    float* spec;        ///< Scratch spectrum, AEC_SPEC floats.
    float* accum;       ///< Echo estimate spectrum, AEC_SPEC floats.

    float  mu;          ///< Step size.
    int    constrain;   ///< Which partition gets its gradient constrained next.

    /// Long-term reference level the step normalisation is anchored to.
    ///
    /// Rises at once with the signal and falls very slowly, so a quiet bar
    /// still regularises against how loud the take actually gets rather than
    /// against the silence of the moment.
    float  power_scale;

    double energy_in;   ///< Running sum of mic^2, for the reduction figure.
    double energy_out;  ///< Running sum of residual^2.
};

gf_aec_context* gf_aec_create(int sample_rate, int partitions) {
    if (partitions < 1) partitions = 1;

    gf_aec_context* ctx = (gf_aec_context*)calloc(1, sizeof(gf_aec_context));
    if (!ctx) return NULL;

    ctx->sample_rate = sample_rate > 0 ? sample_rate : 48000;
    ctx->partitions = partitions;
    ctx->mu = 0.3f;

    if (!gf_fft_init(&ctx->fft, AEC_N)) { gf_aec_destroy(ctx); return NULL; }

    ctx->w     = (float*)calloc((size_t)partitions * AEC_SPEC, sizeof(float));
    ctx->xh    = (float*)calloc((size_t)partitions * AEC_SPEC, sizeof(float));
    ctx->xpow  = (float*)calloc((size_t)partitions * AEC_N, sizeof(float));
    ctx->hist  = (float*)calloc(AEC_N, sizeof(float));
    ctx->xprev = (float*)calloc(GF_AEC_BLOCK, sizeof(float));
    ctx->spec  = (float*)calloc(AEC_SPEC, sizeof(float));
    ctx->accum = (float*)calloc(AEC_SPEC, sizeof(float));

    if (!ctx->w || !ctx->xh || !ctx->xpow || !ctx->hist || !ctx->xprev ||
        !ctx->spec || !ctx->accum) {
        gf_aec_destroy(ctx);
        return NULL;
    }
    return ctx;
}

void gf_aec_destroy(gf_aec_context* ctx) {
    if (!ctx) return;
    gf_fft_free(&ctx->fft);
    free(ctx->w);
    free(ctx->xh);
    free(ctx->xpow);
    free(ctx->hist);
    free(ctx->xprev);
    free(ctx->spec);
    free(ctx->accum);
    free(ctx);
}

void gf_aec_reset(gf_aec_context* ctx) {
    if (!ctx) return;
    memset(ctx->w, 0, (size_t)ctx->partitions * AEC_SPEC * sizeof(float));
    gf_aec_rewind_keep_filter(ctx);
}

void gf_aec_rewind_keep_filter(gf_aec_context* ctx) {
    if (!ctx) return;
    memset(ctx->xh, 0, (size_t)ctx->partitions * AEC_SPEC * sizeof(float));
    memset(ctx->xpow, 0, (size_t)ctx->partitions * AEC_N * sizeof(float));
    memset(ctx->hist, 0, AEC_N * sizeof(float));
    memset(ctx->xprev, 0, GF_AEC_BLOCK * sizeof(float));
    ctx->power_scale = 0.0f;
    ctx->head = 0;
    ctx->constrain = 0;
    ctx->energy_in = 0.0;
    ctx->energy_out = 0.0;
}

void gf_aec_set_step(gf_aec_context* ctx, float mu) {
    if (!ctx) return;
    if (mu < 0.0f) mu = 0.0f;
    if (mu > 1.0f) mu = 1.0f;
    ctx->mu = mu;
}

// ─── 2. Block processing ────────────────────────────────────────────────────

/// Spectrum of partition [p] counted back from the newest, i.e. the reference
/// block from [p] blocks ago.
static float* xh_at(gf_aec_context* ctx, int p) {
    int idx = ctx->head - p;
    while (idx < 0) idx += ctx->partitions;
    return ctx->xh + (size_t)idx * AEC_SPEC;
}

/// Projects partition [p] back onto filters that are at most one block long.
///
/// The frequency-domain update produces a gradient that, read back as time
/// samples, spills past the block it is allowed to occupy. Left alone that
/// wrap-around makes the filter model echoes that arrive before the sound
/// causing them, and the whole thing slowly goes unstable. Zeroing the back
/// half each time is the standard fix.
///
/// Only one partition is corrected per block, cycling through them. Doing all
/// of them would cost two extra transforms per partition per block — the
/// dominant cost of the whole canceller — for a convergence difference that
/// does not survive being listened to.
static void constrain_partition(gf_aec_context* ctx, int p) {
    float* wp = ctx->w + (size_t)p * AEC_SPEC;
    memcpy(ctx->spec, wp, AEC_SPEC * sizeof(float));
    gf_fft_execute(&ctx->fft, ctx->spec, 1);
    for (int i = GF_AEC_BLOCK; i < AEC_N; i++) {
        ctx->spec[2 * i] = 0.0f;
        ctx->spec[2 * i + 1] = 0.0f;
    }
    gf_fft_execute(&ctx->fft, ctx->spec, 0);
    memcpy(wp, ctx->spec, AEC_SPEC * sizeof(float));
}

void gf_aec_process_block(gf_aec_context* ctx, const float* mic,
                          const float* ref, float* out, int adapt) {
    if (!ctx || !mic || !ref || !out) return;

    const int B = GF_AEC_BLOCK;

    // ── Reference into the history ──────────────────────────────────────────
    //
    // Overlap-save: the transform sees the previous block followed by this
    // one, so that the useful half of the result is a true linear convolution.
    ctx->head = (ctx->head + 1) % ctx->partitions;
    float* xnow = ctx->xh + (size_t)ctx->head * AEC_SPEC;
    for (int i = 0; i < B; i++) {
        xnow[2 * i] = ctx->xprev[i];
        xnow[2 * i + 1] = 0.0f;
        xnow[2 * (i + B)] = ref[i];
        xnow[2 * (i + B) + 1] = 0.0f;
    }
    memcpy(ctx->xprev, ref, (size_t)B * sizeof(float));

    // The slot just claimed still holds the power of the block falling out of
    // the filter's reach, so take that off the running sum before overwriting.
    float* pnow = ctx->xpow + (size_t)ctx->head * AEC_N;
    for (int k = 0; k < AEC_N; k++) {
        ctx->hist[k] -= pnow[k];
        if (ctx->hist[k] < 0.0f) ctx->hist[k] = 0.0f;  // drift from repeated sums
    }

    gf_fft_execute(&ctx->fft, xnow, 0);

    for (int k = 0; k < AEC_N; k++) {
        const float xr = xnow[2 * k], xi = xnow[2 * k + 1];
        pnow[k] = xr * xr + xi * xi;
        ctx->hist[k] += pnow[k];
    }

    // ── Estimate the echo ───────────────────────────────────────────────────
    //
    // Each partition holds one block's worth of the room's response, applied
    // to the reference from that many blocks ago. Summing them applies a
    // filter partitions*BLOCK samples long without ever transforming anything
    // that long.
    memset(ctx->accum, 0, AEC_SPEC * sizeof(float));
    for (int p = 0; p < ctx->partitions; p++) {
        const float* wp = ctx->w + (size_t)p * AEC_SPEC;
        const float* xp = xh_at(ctx, p);
        for (int k = 0; k < AEC_N; k++) {
            const float ar = wp[2 * k],     ai = wp[2 * k + 1];
            const float br = xp[2 * k],     bi = xp[2 * k + 1];
            ctx->accum[2 * k]     += ar * br - ai * bi;
            ctx->accum[2 * k + 1] += ar * bi + ai * br;
        }
    }

    memcpy(ctx->spec, ctx->accum, AEC_SPEC * sizeof(float));
    gf_fft_execute(&ctx->fft, ctx->spec, 1);

    // ── Subtract ────────────────────────────────────────────────────────────
    //
    // Overlap-save discards the first half: only the back block of the inverse
    // transform is free of wrap-around.
    for (int i = 0; i < B; i++) {
        const float echo = ctx->spec[2 * (i + B)];
        const float e = mic[i] - echo;
        ctx->energy_in  += (double)mic[i] * (double)mic[i];
        ctx->energy_out += (double)e * (double)e;
        out[i] = e;
    }

    if (!adapt) return;

    // ── Learn ───────────────────────────────────────────────────────────────
    //
    // The error goes back into the transform zero-padded at the front, the
    // mirror of how the reference was padded at the back.
    for (int i = 0; i < B; i++) {
        ctx->spec[2 * i] = 0.0f;
        ctx->spec[2 * i + 1] = 0.0f;
        ctx->spec[2 * (i + B)] = out[i];
        ctx->spec[2 * (i + B) + 1] = 0.0f;
    }
    gf_fft_execute(&ctx->fft, ctx->spec, 0);

    // Normalising each bin by how much reference energy it carries is what
    // makes this converge at the same rate for a loud backing track and a
    // quiet click, instead of crawling for one and going unstable on the other.
    double psum = 0.0;
    for (int k = 0; k < AEC_N; k++) psum += (double)ctx->hist[k];

    // The speaker was silent through this whole block, so it left nothing in
    // the microphone and there is nothing here to learn from. Adapting anyway
    // would be asking the filter to explain the performance with a signal that
    // was not playing.
    if (psum <= (double)AEC_SILENCE) return;

    // Floor every bin against a fraction of how loud the reference gets,
    // rather than against a fixed small number or against this instant.
    //
    // A real reference is not noise. A metronome over an empty bar is literal
    // digital silence, and the takes playing alongside it leave whole bands
    // with almost nothing in them. A bin at zero power divides the step by
    // nothing at all, and the microphone still holds the performer, so the
    // error in that bin is *not* zero — the update goes to infinity and takes
    // the output with it. The first real take off a phone came back as NaN
    // where the synthetic fixture, continuous noise that was never silent, had
    // been fine.
    //
    // Anchoring to a long-term level rather than to this block is what makes
    // that safe: through a silent bar the filter keeps regularising against
    // the loud passage it has already heard, instead of against nothing.
    const float pmean = (float)(psum / (double)AEC_N);
    ctx->power_scale = (pmean > ctx->power_scale)
                           ? pmean
                           : AEC_SCALE_DECAY * ctx->power_scale;

    // Learn only where the speaker is actually loud.
    //
    // A metronome is a click and then a long gap. In the gap the microphone
    // holds room noise, which is not echo and cannot be predicted from the
    // reference — measured on a real take, the echo path is coherent to 0.998
    // while the speaker is producing something and to barely 0.3 in between.
    // Adapting through the gaps therefore feeds the room's noise into the
    // filter and drags it off the path it had found. Skipping them is worth
    // about 3 dB on the parts of the take that actually carry bleed.
    if (pmean < AEC_LEARN_GATE * ctx->power_scale) return;

    const float floor_k = AEC_POWER_FLOOR * ctx->power_scale;

    for (int p = 0; p < ctx->partitions; p++) {
        float* wp = ctx->w + (size_t)p * AEC_SPEC;
        const float* xp = xh_at(ctx, p);
        for (int k = 0; k < AEC_N; k++) {
            const float pk = ctx->hist[k] > floor_k ? ctx->hist[k] : floor_k;
            const float denom = pk + AEC_EPS;
            const float g = ctx->mu / denom;
            // conj(X) * E, the direction that reduces this block's error.
            const float xr = xp[2 * k], xi = -xp[2 * k + 1];
            const float er = ctx->spec[2 * k], ei = ctx->spec[2 * k + 1];
            wp[2 * k]     += g * (xr * er - xi * ei);
            wp[2 * k + 1] += g * (xr * ei + xi * er);
        }
    }

    constrain_partition(ctx, ctx->constrain);
    ctx->constrain = (ctx->constrain + 1) % ctx->partitions;
}

float gf_aec_reduction_db(const gf_aec_context* ctx) {
    if (!ctx || ctx->energy_in <= 0.0 || ctx->energy_out <= 0.0) return 0.0f;
    return (float)(10.0 * log10(ctx->energy_in / ctx->energy_out));
}

// ─── 3. Delay estimation ────────────────────────────────────────────────────

/// Largest transform the estimator will build: 2^19 frames, about 11 seconds
/// at 48 kHz. Long enough that a real correlation stands well clear of chance,
/// small enough that the two scratch buffers stay a few megabytes.
#define AEC_DELAY_MAX_FFT (1 << 19)

/// How tall the correlation peak itself must be before it is believed.
///
/// Because the cross-spectrum is normalised to unit magnitude per bin before
/// being transformed back, this number does not depend on how loud anything
/// was: it is near 1 when the microphone heard exactly what the speaker
/// played, and near 0 when the two have nothing in common.
///
/// Measured on the smoke test's fixtures, with the lag window above holding
/// the search to plausible delays:
///
///   bleed as loud as the performance   0.44
///   bleed 9 dB below it                0.26
///   bleed 18 dB below it               0.12   <- still the right delay
///   bleed 29 dB below it               0.06   <- indistinguishable from noise
///   the most convincing false match    0.06
///
/// So the decision has to land between 0.06 and 0.12, and where in that gap
/// it sits trades one failure for the other. Erring high is the safer side —
/// refusing to clean a take leaves it exactly as recorded, while cleaning one
/// with no bleed in it means subtracting the performance from itself — but
/// erring too high makes the feature decline on exactly the quiet bleed it
/// would most help with.
#define AEC_PEAK_ABS 0.10f

/// How far that peak must also stand above the average, which catches a broad
/// smear that happens to be tall without being an alignment.
#define AEC_PEAK_RATIO 8.0

static int next_pow2_at_most(int n, int cap) {
    int p = 1;
    while (p * 2 <= n && p * 2 <= cap) p *= 2;
    return p;
}

static int estimate_one(const float* mic, const float* ref, int n,
                        int sample_rate) {
    if (!mic || !ref || n < 1024) return 0;
    if (sample_rate <= 0) sample_rate = 48000;

    const int fftn = next_pow2_at_most(n, AEC_DELAY_MAX_FFT);
    if (fftn < 1024) return 0;

    gf_fft f;
    if (!gf_fft_init(&f, fftn)) return 0;

    float* A = (float*)calloc((size_t)fftn * 2, sizeof(float));
    float* Bb = (float*)calloc((size_t)fftn * 2, sizeof(float));
    if (!A || !Bb) { free(A); free(Bb); gf_fft_free(&f); return 0; }

    for (int i = 0; i < fftn; i++) {
        A[2 * i] = mic[i];
        Bb[2 * i] = ref[i];
    }
    gf_fft_execute(&f, A, 0);
    gf_fft_execute(&f, Bb, 0);

    // Cross-spectrum MIC * conj(REF), divided by its own magnitude. Dropping
    // the magnitude is the "phase transform": it stops a loud bass-heavy
    // backing track from dominating the correlation and smearing the peak,
    // which is exactly what a phone speaker's response would otherwise do.
    for (int k = 0; k < fftn; k++) {
        const float ar = A[2 * k],  ai = A[2 * k + 1];
        const float br = Bb[2 * k], bi = -Bb[2 * k + 1];
        float cr = ar * br - ai * bi;
        float ci = ar * bi + ai * br;
        const float m = sqrtf(cr * cr + ci * ci);
        if (m > 1e-12f) { cr /= m; ci /= m; } else { cr = 0.0f; ci = 0.0f; }
        A[2 * k] = cr;
        A[2 * k + 1] = ci;
    }
    gf_fft_execute(&f, A, 1);

    // A positive lag means the microphone heard it later than the speaker
    // played it, which is the only physically sensible direction.
    int max_lag = (int)(GF_AEC_MAX_DELAY_SEC * (float)sample_rate);
    if (max_lag > fftn / 2) max_lag = fftn / 2;

    int best = 0;
    float best_val = 0.0f;
    double sum = 0.0;
    for (int lag = 0; lag < max_lag; lag++) {
        const float v = A[2 * lag];
        sum += fabs((double)v);
        if (v > best_val) { best_val = v; best = lag; }
    }

    // A real alignment produces a peak standing far above the background. If
    // nothing does, the two signals are unrelated — an empty reference, or a
    // take recorded on headphones with no bleed to cancel — and saying so is
    // the whole point: an adaptive filter given an unrelated reference does
    // not sit still, it gradually learns to subtract part of the performance.
    const double mean = (max_lag > 0) ? sum / (double)max_lag : 0.0;
    if (best_val < AEC_PEAK_ABS) best = -1;
    else if (mean <= 0.0 || (double)best_val < AEC_PEAK_RATIO * mean) best = -1;

    free(A); free(Bb); gf_fft_free(&f);
    return best;
}

/// Segments the estimate takes a vote across, and the shortest useful one.
#define AEC_DELAY_SEGMENTS 6
#define AEC_DELAY_MIN_SEG  (1 << 15)   /* ~0.68 s at 48 kHz */

static int cmp_float(const void* a, const void* b) {
    const float x = *(const float*)a, y = *(const float*)b;
    return (x > y) - (x < y);
}

static int cmp_int(const void* a, const void* b) {
    const int x = *(const int*)a, y = *(const int*)b;
    return (x > y) - (x < y);
}

/// Turns per-window answers into one, or -1 if they do not agree.
///
/// [count] of [total] windows were confident enough to answer at all. A real
/// delay shows up as most of them naming the same number; windows that locked
/// onto something else scatter, and scattered confidence is not a delay.
static int consensus_of(int* found, int count, int total) {
    if (count * 2 <= total) return -1;

    qsort(found, (size_t)count, sizeof(int), cmp_int);
    const int median = found[count / 2];

    int near = 0;
    for (int i = 0; i < count; i++) {
        if (abs(found[i] - median) <= GF_AEC_BLOCK) near++;
    }
    if (near * 2 <= count) return -1;
    return median;
}

int gf_aec_estimate_delay(const float* mic, const float* ref, int n,
                          int sample_rate) {
    if (!mic || !ref || n < 1024) return 0;
    if (sample_rate <= 0) sample_rate = 48000;

    // One window is not enough to trust.
    //
    // Measured on a real take off a phone: for the first three seconds the
    // microphone correlates with the speaker far more strongly at a lag of one
    // frame than at the true acoustic delay — the speaker amplifier couples
    // into the microphone preamp electrically, which arrives instantly and
    // inverted, while the sound through the air takes 25 ms. A single window
    // taken from the start of the file locks onto that and reports a delay of
    // 1, and the whole cancellation then has nothing to subtract.
    //
    // Several windows across the recording, and the middle answer wins. The
    // electrical peak dominates only where the room is quiet, so it loses the
    // vote; so would a passage where one player drowns out the bleed, or the
    // count-in before anyone starts.
    int seg = n / AEC_DELAY_SEGMENTS;
    if (seg > AEC_DELAY_MAX_FFT) seg = AEC_DELAY_MAX_FFT;
    if (seg < AEC_DELAY_MIN_SEG) {
        // Too short to divide up; one window is all there is.
        return estimate_one(mic, ref, n, sample_rate);
    }

    int found[AEC_DELAY_SEGMENTS];
    int count = 0;
    for (int i = 0; i < AEC_DELAY_SEGMENTS; i++) {
        const int off = (int)((long long)i * (n - seg) / (AEC_DELAY_SEGMENTS - 1));
        const int d = estimate_one(mic + off, ref + off, seg, sample_rate);
        if (d >= 0) found[count++] = d;
    }

    return consensus_of(found, count, AEC_DELAY_SEGMENTS);
}

// ─── 4. File driver ─────────────────────────────────────────────────────────

/// How far a measured delay may sit from the one the device reported and still
/// be believed as a refinement of it rather than a different thing entirely.
/// 50 ms is far more than a route's round trip varies between takes.
#define AEC_EXPECTED_TOLERANCE_SEC 0.05f

/// Frames of slack kept in front of the measured delay.
///
/// The adaptive filter can only model echo arriving at or after the point the
/// reference is aligned to, so an overestimate puts part of the room's
/// response out of reach. Starting slightly early costs two blocks of the
/// filter's length and nothing else.
#define AEC_DELAY_MARGIN (GF_AEC_BLOCK * 2)

/// Frames in each window the delay is measured over. About 2.7 s at 48 kHz —
/// long enough for a confident correlation, short enough that six of them fit
/// inside a take without overlapping.
#define AEC_DELAY_SEG_FRAMES (1 << 17)

/// Step size while learning the room, and while merely holding onto it.
///
/// The second pass keeps adapting, slowly. Freezing would be tidier, but the
/// capture and playback clocks are not the same crystal and drift apart by a
/// few milliseconds over a long take — enough to pull the filter out of
/// alignment with the room it just learned.
#define AEC_STEP_LEARN 0.30f

/// Passes spent learning before the one that writes the output.
///
/// One. A second was swept and bought nothing on a real take that the first
/// had not already found, at twice the time.
#define AEC_LEARN_PASSES 1

/// How far above the typical block the microphone may be, relative to what the
/// speaker was playing, before that block is refused as near-end.
///
/// The ratio of microphone energy to reference energy sits at a floor while
/// only the speaker is sounding, and jumps when the player comes in. Those
/// jumps are where an adaptive filter destroys itself trying to explain a
/// guitar with a metronome.
///
/// Expressed as a multiple of the median rather than as a percentile. A
/// percentile always throws away half the take, and with nobody playing the
/// half it keeps is the half where the coupling happened to be weakest —
/// which biases the filter into under-estimating the echo. Measured: keeping
/// the quietest half cost an empty-room take 12.0 dB -> 5.5 dB, while
/// excluding only the outliers leaves it untouched and still rescues a take
/// with a player.
#define AEC_NEAR_END_RATIO 4.0f
#define AEC_STEP_TRACK 0.05f

/// Reads one block of reference, delayed by [delay] frames.
///
/// Before the delay has elapsed the speaker had not yet played anything the
/// microphone could hear, so the reference reads as silence.
///
/// Must be called with [pos] advancing one whole block at a time from zero,
/// on a reader rewound to its first sample. The silence at the front is
/// produced without touching the file, which is what keeps the reader's own
/// position equal to [pos] - [delay] for every later call; calling this out of
/// order would read the right number of samples from the wrong place.
static int read_ref_delayed(gf_wav_reader* ref, float* dst, int count,
                            int64_t pos, int delay) {
    const int64_t start = pos - (int64_t)delay;
    int done = 0;
    while (done < count) {
        const int64_t at = start + done;
        if (at < 0) {
            const int64_t zeros = (-at < (int64_t)(count - done))
                                      ? -at
                                      : (int64_t)(count - done);
            memset(dst + done, 0, (size_t)zeros * sizeof(float));
            done += (int)zeros;
            continue;
        }
        const int got = gf_wav_read(ref, dst + done, count - done);
        if (got <= 0) {
            memset(dst + done, 0, (size_t)(count - done) * sizeof(float));
            done = count;
            break;
        }
        done += got;
    }
    return done;
}

/// Writes [mic] out verbatim, for takes with no bleed to remove.
///
/// Still produces the output file rather than reporting "nothing to do", so
/// callers have one path to play from whichever answer the canceller reached.
static int copy_take(gf_wav_reader* mic, const char* out_path) {
    gf_wav_rewind(mic);
    FILE* out = gf_wav_open_write(out_path, mic->sample_rate);
    if (!out) return GF_AEC_ERR_OPEN_OUTPUT;

    float buf[GF_AEC_BLOCK];
    int64_t written = 0;
    int ok = 1;
    while (written < mic->frames && ok) {
        const int got = gf_wav_read(mic, buf, GF_AEC_BLOCK);
        if (got <= 0) break;
        ok = gf_wav_write(out, buf, got);
        written += got;
    }
    gf_wav_finish(out, written);
    fclose(out);
    if (!ok) { remove(out_path); return GF_AEC_ERR_WRITE; }
    return GF_AEC_OK;
}

int gf_aec_render_file(const char* mic_path, const char* ref_path,
                       const char* out_path, int expected_delay,
                       float* reduction_db) {
    if (reduction_db) *reduction_db = 0.0f;
    if (!mic_path || !ref_path || !out_path) return GF_AEC_ERR_OPEN_MIC;

    gf_wav_reader mic = gf_wav_open_read(mic_path);
    if (!mic.file) return GF_AEC_ERR_OPEN_MIC;

    gf_wav_reader ref = gf_wav_open_read(ref_path);
    if (!ref.file) { gf_wav_close(&mic); return GF_AEC_ERR_OPEN_REF; }

    if (mic.sample_rate != ref.sample_rate) {
        gf_wav_close(&mic); gf_wav_close(&ref);
        return GF_AEC_ERR_RATE_MISMATCH;
    }

    // ── Measure the delay ───────────────────────────────────────────────────
    // Sampled from windows spread across the whole recording rather than from
    // a chunk off the front. A prefix is not representative: the opening of a
    // take is a count-in with nobody playing, and on real hardware the quiet
    // there lets a spurious correlation win that the rest of the take would
    // have outvoted. Reading a window at a time also keeps a five-minute take
    // from having to be held in memory to be measured.
    int seg = (int)(mic.frames / AEC_DELAY_SEGMENTS);
    if (seg > AEC_DELAY_SEG_FRAMES) seg = AEC_DELAY_SEG_FRAMES;

    int delay = -1;
    if (seg >= 1024) {
        float* mbuf = (float*)malloc((size_t)seg * sizeof(float));
        float* rbuf = (float*)malloc((size_t)seg * sizeof(float));
        if (mbuf && rbuf) {
            int found[AEC_DELAY_SEGMENTS];
            int count = 0;
            for (int i = 0; i < AEC_DELAY_SEGMENTS; i++) {
                const int64_t off = (int64_t)i * (mic.frames - seg) /
                                    (AEC_DELAY_SEGMENTS - 1);
                gf_wav_seek(&mic, off);
                gf_wav_seek(&ref, off);
                const int mg = gf_wav_read(&mic, mbuf, seg);
                const int rg = gf_wav_read(&ref, rbuf, seg);
                const int usable = (mg < rg) ? mg : rg;
                if (usable < 1024) continue;
                const int d = estimate_one(mbuf, rbuf, usable, mic.sample_rate);
                if (d >= 0) found[count++] = d;
            }
            delay = consensus_of(found, count, AEC_DELAY_SEGMENTS);
        }
        free(mbuf); free(rbuf);
    }

    // Reconcile what was measured with what the device already knew.
    //
    // Correlation alone needs the bleed to stand clear of everything else in
    // the take, and a player barely above it is enough to bury it. The round
    // trip, though, is a property of the route and not of the take — the
    // engine measures it for every output path in order to align takes at all.
    // So when it is offered, a correlation that lands near it refines it, and
    // one that found nothing defers to it rather than giving up.
    if (expected_delay >= 0) {
        const int window = (int)(AEC_EXPECTED_TOLERANCE_SEC * mic.sample_rate);
        if (delay < 0 || abs(delay - expected_delay) > window) {
            delay = expected_delay;
        }
    } else if (delay < 0) {
        // Nothing measured and nothing known: the band was on headphones or
        // the USB output and no bleed ever reached the microphone. Copy the
        // take through rather than set an adaptive filter loose on a signal it
        // cannot explain — given long enough it would learn to subtract part
        // of the performance instead.
        const int rc = copy_take(&mic, out_path);
        gf_wav_close(&mic);
        gf_wav_close(&ref);
        return rc;
    }

    delay -= AEC_DELAY_MARGIN;
    if (delay < 0) delay = 0;

    gf_aec_context* ctx = gf_aec_create(mic.sample_rate, GF_AEC_PARTITIONS);
    float* mblk = (float*)malloc(GF_AEC_BLOCK * sizeof(float));
    float* rblk = (float*)malloc(GF_AEC_BLOCK * sizeof(float));
    float* oblk = (float*)malloc(GF_AEC_BLOCK * sizeof(float));
    if (!ctx || !mblk || !rblk || !oblk) {
        gf_aec_destroy(ctx); free(mblk); free(rblk); free(oblk);
        gf_wav_close(&mic); gf_wav_close(&ref);
        return GF_AEC_ERR_MEMORY;
    }

    // ── Choose what to learn from ───────────────────────────────────────────
    //
    // One cheap pass over both files to rank the blocks by how quiet the
    // microphone was relative to what the speaker was playing. Only the
    // quietest half is learned from; see AEC_LEARN_PERCENT.
    const int64_t nblocks = mic.frames / GF_AEC_BLOCK;
    float* ratio = (nblocks > 0)
                       ? (float*)malloc((size_t)nblocks * sizeof(float))
                       : NULL;
    float limit = 0.0f;
    if (ratio) {
        gf_wav_rewind(&mic);
        gf_wav_rewind(&ref);
        for (int64_t b = 0; b < nblocks; b++) {
            const int got = gf_wav_read(&mic, mblk, GF_AEC_BLOCK);
            read_ref_delayed(&ref, rblk, GF_AEC_BLOCK, b * GF_AEC_BLOCK, delay);
            double me = 0.0, re = 0.0;
            for (int i = 0; i < got; i++) {
                me += (double)mblk[i] * mblk[i];
                re += (double)rblk[i] * rblk[i];
            }
            // A block the speaker was silent through says nothing about the
            // near-end, so it is never a candidate.
            ratio[b] = (re > 1e-7) ? (float)(me / re) : FLT_MAX;
        }

        float* sorted = (float*)malloc((size_t)nblocks * sizeof(float));
        int usable = 0;
        if (sorted) {
            for (int64_t b = 0; b < nblocks; b++) {
                if (ratio[b] < FLT_MAX) sorted[usable++] = ratio[b];
            }
            qsort(sorted, (size_t)usable, sizeof(float), cmp_float);
            limit = (usable > 0) ? sorted[usable / 2] * AEC_NEAR_END_RATIO : 0.0f;
            free(sorted);
        }
        // Nothing usable: fall back to learning from everything, which is what
        // this did before and is no worse than not running at all.
        if (usable == 0) {
            for (int64_t b = 0; b < nblocks; b++) ratio[b] = 0.0f;
            limit = 1.0f;
        }
    }

    // ── Learning passes ─────────────────────────────────────────────────────
    //
    // The output is thrown away; only what the filter learns survives. Two of
    // them rather than one: the filter spends the first pass finding the room
    // from nothing, and a second pass over the same audio starting from what
    // it found lands measurably closer. A third adds almost nothing.
    gf_aec_set_step(ctx, AEC_STEP_LEARN);
    for (int pass = 0; pass < AEC_LEARN_PASSES; pass++) {
        gf_aec_rewind_keep_filter(ctx);
        gf_wav_rewind(&mic);
        gf_wav_rewind(&ref);
        int64_t pos = 0;
        while (pos < mic.frames) {
            const int got = gf_wav_read(&mic, mblk, GF_AEC_BLOCK);
            if (got <= 0) break;
            if (got < GF_AEC_BLOCK) {
                memset(mblk + got, 0,
                       (size_t)(GF_AEC_BLOCK - got) * sizeof(float));
            }
            read_ref_delayed(&ref, rblk, GF_AEC_BLOCK, pos, delay);
            const int64_t b = pos / GF_AEC_BLOCK;
            const int clean = !ratio || (b < nblocks && ratio[b] <= limit);
            gf_aec_process_block(ctx, mblk, rblk, oblk, clean);
            pos += GF_AEC_BLOCK;
        }
    }
    int64_t pos = 0;

    // ── Pass 2: apply it from the first sample ──────────────────────────────
    gf_aec_set_step(ctx, AEC_STEP_TRACK);
    gf_aec_rewind_keep_filter(ctx);
    gf_wav_rewind(&mic);
    gf_wav_rewind(&ref);

    FILE* out = gf_wav_open_write(out_path, mic.sample_rate);
    if (!out) {
        gf_aec_destroy(ctx); free(mblk); free(rblk); free(oblk);
        gf_wav_close(&mic); gf_wav_close(&ref);
        return GF_AEC_ERR_OPEN_OUTPUT;
    }

    int64_t written = 0;
    int ok = 1;
    double scored_in = 0.0, scored_out = 0.0;
    pos = 0;
    while (pos < mic.frames && ok) {
        const int got = gf_wav_read(&mic, mblk, GF_AEC_BLOCK);
        if (got <= 0) break;
        if (got < GF_AEC_BLOCK) {
            memset(mblk + got, 0,
                   (size_t)(GF_AEC_BLOCK - got) * sizeof(float));
        }
        read_ref_delayed(&ref, rblk, GF_AEC_BLOCK, pos, delay);
        // Still tracking, but only where the player is not covering the
        // speaker. Freezing outright measured worse on a take with nobody
        // playing, and adapting everywhere measured worse on one with a
        // player: the clean blocks are what both want.
        const int64_t ob_ = pos / GF_AEC_BLOCK;
        const int clean_out = !ratio || (ob_ < nblocks && ratio[ob_] <= limit);
        gf_aec_process_block(ctx, mblk, rblk, oblk, clean_out);

        // Score only the blocks where the speaker was sounding and the player
        // was not. Over the whole take the figure is meaningless: a performer
        // 10 dB above the bleed dominates the energy, so removing every last
        // bit of echo would still read as a fraction of a dB and the result
        // would be thrown away as useless.
        if (clean_out) {
            for (int i = 0; i < GF_AEC_BLOCK; i++) {
                scored_in += (double)mblk[i] * mblk[i];
                scored_out += (double)oblk[i] * oblk[i];
            }
        }

        // The take decides the length: a block was padded to a whole block to
        // be processed, but the extra samples are not part of the recording.
        int usable = GF_AEC_BLOCK;
        if (written + usable > mic.frames) usable = (int)(mic.frames - written);
        if (usable > 0) {
            ok = gf_wav_write(out, oblk, usable);
            written += usable;
        }
        pos += GF_AEC_BLOCK;
    }

    const float removed = (scored_in > 0.0 && scored_out > 0.0)
                              ? (float)(10.0 * log10(scored_in / scored_out))
                              : gf_aec_reduction_db(ctx);
    gf_wav_finish(out, written);
    fclose(out);

    if (reduction_db) *reduction_db = removed;
    gf_aec_destroy(ctx);
    free(mblk); free(rblk); free(oblk); free(ratio);
    gf_wav_close(&mic);
    gf_wav_close(&ref);

    if (!ok) { remove(out_path); return GF_AEC_ERR_WRITE; }
    return GF_AEC_OK;
}
