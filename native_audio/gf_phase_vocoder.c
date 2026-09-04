// gf_phase_vocoder.c — Implementation of the shared phase vocoder DSP
// library. See gf_phase_vocoder.h for the public API and algorithm rationale.
//
// Layout of this file:
//   1. Minimal iterative radix-2 complex FFT (Cooley-Tukey).
//   2. Per-channel analysis/synthesis state.
//   3. gf_pv_context and its allocator/destructor.
//   4. STFT analysis -> phase-locking -> STFT synthesis.
//   5. Streaming front-end (gf_pv_process_block) with input/output ring buffers.
//   6. Offline convenience helper.
//
// Real-time safety: after gf_pv_create, nothing on the hot path calls malloc
// or any blocking operation. All buffers are sized once from the configured
// fft_size/hop_size/channels and never grow.

#include "gf_phase_vocoder.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define GF_PV_MAX_FFT      8192
#define GF_PV_MIN_FFT      256
#define GF_PV_MAX_CHANNELS 2

// Output ring buffer must hold a worst-case produced chunk plus one extra
// synthesis frame of slack. Sized at the largest supported fft_size * 4
// (matches max stretch ratio) + one fft.
#define GF_PV_OUT_RING_CAP (GF_PV_MAX_FFT * 8)
// Input ring: we need at least fft_size samples available before the first
// analysis frame. Sized generously.
#define GF_PV_IN_RING_CAP  (GF_PV_MAX_FFT * 4)

// -------------------------------------------------------------------------
// 1. Iterative radix-2 complex FFT
// -------------------------------------------------------------------------
//
// Operates in place on a tightly-packed complex array: re[0], im[0],
// re[1], im[1], ... Twiddles are precomputed once per context.
//
// Bit-reversal permutation + butterfly layers is the textbook Cooley-Tukey
// formulation. Chosen over recursion for cache locality and zero stack
// growth on the audio thread.

typedef struct {
    int   n;             // FFT size, power of two
    int   log2n;         // log2(n)
    float* twiddle_cos;  // length n/2
    float* twiddle_sin;  // length n/2
    int*   bitrev;       // length n, precomputed bit-reversal indices
} gf_fft;

static int gf_fft_init(gf_fft* f, int n) {
    f->n = n;
    f->log2n = 0;
    while ((1 << f->log2n) < n) f->log2n++;
    f->twiddle_cos = (float*)calloc((size_t)(n / 2), sizeof(float));
    f->twiddle_sin = (float*)calloc((size_t)(n / 2), sizeof(float));
    f->bitrev      = (int*)  calloc((size_t)n, sizeof(int));
    if (!f->twiddle_cos || !f->twiddle_sin || !f->bitrev) return 0;

    // Twiddle factors for forward FFT: W_n^k = exp(-j * 2*pi*k/n).
    // Inverse is obtained by negating the sign of the sine.
    for (int k = 0; k < n / 2; k++) {
        double a = -2.0 * M_PI * (double)k / (double)n;
        f->twiddle_cos[k] = (float)cos(a);
        f->twiddle_sin[k] = (float)sin(a);
    }
    // Precompute bit-reversal permutation indices.
    for (int i = 0; i < n; i++) {
        int j = 0;
        int x = i;
        for (int b = 0; b < f->log2n; b++) { j = (j << 1) | (x & 1); x >>= 1; }
        f->bitrev[i] = j;
    }
    return 1;
}

static void gf_fft_free(gf_fft* f) {
    free(f->twiddle_cos);
    free(f->twiddle_sin);
    free(f->bitrev);
    f->twiddle_cos = NULL;
    f->twiddle_sin = NULL;
    f->bitrev      = NULL;
}

// In-place complex FFT (or IFFT if [inverse] is nonzero).
// [data] is interleaved real/imag, length 2*n floats.
static void gf_fft_execute(const gf_fft* f, float* data, int inverse) {
    const int n = f->n;

    // Step 1: bit-reversal reorder. Swap data[i] with data[bitrev[i]] once.
    for (int i = 0; i < n; i++) {
        int j = f->bitrev[i];
        if (j > i) {
            float tr = data[2*i];     float ti = data[2*i + 1];
            data[2*i]     = data[2*j];
            data[2*i + 1] = data[2*j + 1];
            data[2*j]     = tr;
            data[2*j + 1] = ti;
        }
    }

    // Step 2: butterfly layers, size 2, 4, 8, ..., n.
    for (int size = 2; size <= n; size <<= 1) {
        int half = size >> 1;
        int step = n / size; // stride into the twiddle tables
        for (int i = 0; i < n; i += size) {
            for (int k = 0; k < half; k++) {
                int tw = k * step;
                float wr = f->twiddle_cos[tw];
                float wi = f->twiddle_sin[tw];
                if (inverse) wi = -wi;

                int i0 = 2 * (i + k);
                int i1 = 2 * (i + k + half);

                float xr = data[i1];
                float xi = data[i1 + 1];
                // t = W * x[i1]
                float tr = wr * xr - wi * xi;
                float ti = wr * xi + wi * xr;
                // x[i1] = x[i0] - t ;  x[i0] = x[i0] + t
                data[i1]     = data[i0]     - tr;
                data[i1 + 1] = data[i0 + 1] - ti;
                data[i0]     = data[i0]     + tr;
                data[i0 + 1] = data[i0 + 1] + ti;
            }
        }
    }

    // Step 3: on inverse, divide by n to normalise.
    if (inverse) {
        float inv = 1.0f / (float)n;
        for (int i = 0; i < 2 * n; i++) data[i] *= inv;
    }
}

// -------------------------------------------------------------------------
// 2. Per-channel state
// -------------------------------------------------------------------------
//
// Each channel keeps its own:
//   - the previous analysis frame's complex spectrum (for phase advance)
//   - the previous synthesis frame's complex spectrum (for phase continuity)
//   - a synthesis overlap-add tail
//   - in/out ring buffers
//   - the anti-alias low-pass state used when pitching up
//
// fft_work and the magnitude scratch are shared across channels since we
// process channels serially on the same thread.
//
// Why complex spectra instead of phase arrays: the phase-locking step
// rotates every bin of a peak's region by the *same* angle, which is a
// single complex multiply per bin. Storing the spectra lets us compute
// that angle from a handful of `atan2f` calls per *peak* instead of one
// `atan2f` + one `sqrtf` + a `cosf`/`sinf` pair per *bin*. On a 2048-point
// FFT that removes ~4000 transcendental calls per frame per voice, which
// is what made a 4-voice harmonizer miss its deadline on phone-class CPUs.

/// Coefficients of one biquad section, normalised so a0 == 1.
typedef struct {
    float b0, b1, b2, a1, a2;
} gf_biquad;

typedef struct {
    // Previous analysis frame's spectrum (length bins each). The phase
    // advance between two frames is arg(X_now * conj(X_prev)), so we never
    // need the raw phases themselves.
    float* prev_re;
    float* prev_im;

    // Previous synthesis frame's spectrum (length bins each). Its argument
    // is the running synthesis phase that the vocoder must continue from.
    float* syn_re;
    float* syn_im;

    // Overlap-add tail of length fft_size. Newly synthesised frames are
    // added on top of this buffer and shifted out by hop_syn samples.
    float* ola;

    // Input ring buffer. Samples flow in here; we pull fft_size at a time
    // at analysis hop intervals.
    float  in_ring[GF_PV_IN_RING_CAP];
    int    in_write;    // write cursor
    int    in_read;     // read cursor for next analysis frame
    int    in_count;    // samples currently buffered

    // Output ring buffer. Synthesis frames overlap-added here; drained by
    // the caller via the out_* cursors.
    float  out_ring[GF_PV_OUT_RING_CAP];
    int    out_write;
    int    out_read;
    int    out_count;

    // Fractional accumulator for the *analysis* hop. The synthesis hop is
    // held constant (see gf_pv_process_block) and the stretch ratio is
    // realised by moving the analysis cursor faster or slower; that ratio
    // is rarely an exact integer number of samples, so the residue is
    // carried across frames to avoid long-run drift.
    float  in_hop_accum;

    // Fractional read position within the output ring, used only when
    // pitch shifting is active (pitch_ratio != 1). Each output frame we
    // emit consumes `pitch_ratio` samples from the ring — less than 1 for
    // downshifts, more than 1 for upshifts — implemented via linear
    // interpolation between adjacent ring samples. Zero when pitch_ratio
    // is 1 so the fast path degenerates into the plain integer drain.
    float  out_frac_pos;

    // Anti-alias low-pass state — two cascaded biquads in transposed
    // direct form II. Only engaged when pitching up; see
    // gf_pv_update_antialias.
    float  lp_z1[2];
    float  lp_z2[2];
} gf_pv_channel;

// -------------------------------------------------------------------------
// 3. Context
// -------------------------------------------------------------------------

struct gf_pv_context {
    int   fft_size;
    int   hop_nominal;   // configured hop — used as the synthesis hop
    int   channels;
    int   bins;          // fft_size/2 + 1

    float stretch;       // current stretch ratio
    float pitch_ratio;   // 2^(semitones/12). 1.0 = no shift.
    float pitch_semis;   // last value passed to gf_pv_set_pitch_semitones

    gf_fft fft;

    // Pre-allocated Hann analysis/synthesis window.
    float* window;

    // Scratch buffers shared across channels. Real-time safe because
    // channels are processed serially on the same thread.
    float* fft_work;     // length 2*fft_size (interleaved complex)
    float* mag2;         // length bins — squared magnitude, peak picking only

    // Synthesis hop the last processed block used. Published through
    // gf_pv_output_quantum so a caller can size the buffer it needs to
    // absorb the vocoder's production granularity.
    int    hop_syn_current;

    // Overlap-add gain compensation, cached for the synthesis hop it was
    // computed at. Recomputed only when that hop changes (rare).
    float  ola_norm;
    int    ola_norm_hop;

    // Anti-alias low-pass: a 4th-order Butterworth as two cascaded
    // biquads. `lp_active` is 0 when no filtering is needed
    // (pitch_ratio <= 1).
    int      lp_active;
    gf_biquad lp[2];

    gf_pv_channel ch[GF_PV_MAX_CHANNELS];
};

// -------------------------------------------------------------------------
// 3b. Create / destroy / reset
// -------------------------------------------------------------------------

static void gf_pv_free_internal(gf_pv_context* ctx) {
    if (!ctx) return;
    gf_fft_free(&ctx->fft);
    free(ctx->window);
    free(ctx->fft_work);
    free(ctx->mag2);
    for (int c = 0; c < GF_PV_MAX_CHANNELS; c++) {
        free(ctx->ch[c].prev_re);
        free(ctx->ch[c].prev_im);
        free(ctx->ch[c].syn_re);
        free(ctx->ch[c].syn_im);
        free(ctx->ch[c].ola);
    }
    free(ctx);
}

/// Sum of the squared Hann window sampled at every [hop] offset.
///
/// This is the gain the overlap-add stage applies to a fully-overlapped
/// sample: each synthesis frame contributes `w * w` (analysis window times
/// synthesis window) and consecutive frames sit `hop` samples apart. The
/// reciprocal is the normalisation that brings the analysis/synthesis chain
/// back to unity gain.
static float gf_pv_window_overlap_gain(const float* window, int fft_size, int hop) {
    double sum = 0.0;
    for (int i = 0; i < fft_size; i += hop) {
        double w = window[i];
        sum += w * w;
    }
    return (sum > 1e-6) ? (float)(1.0 / sum) : 1.0f;
}

gf_pv_context* gf_pv_create(int fft_size, int hop_size, int channels) {
    // Validate: fft_size power of two in range, hop divides evenly, 4x overlap.
    if (fft_size < GF_PV_MIN_FFT || fft_size > GF_PV_MAX_FFT) return NULL;
    if ((fft_size & (fft_size - 1)) != 0) return NULL;
    if (hop_size <= 0 || hop_size > fft_size / 4) return NULL;
    if ((fft_size % hop_size) != 0) return NULL;
    if (channels < 1 || channels > GF_PV_MAX_CHANNELS) return NULL;

    gf_pv_context* ctx = (gf_pv_context*)calloc(1, sizeof(gf_pv_context));
    if (!ctx) return NULL;

    ctx->fft_size    = fft_size;
    ctx->hop_nominal = hop_size;
    ctx->channels    = channels;
    ctx->bins        = fft_size / 2 + 1;
    ctx->stretch     = 1.0f;
    ctx->pitch_ratio = 1.0f;
    ctx->pitch_semis = 0.0f;

    if (!gf_fft_init(&ctx->fft, fft_size)) { gf_pv_free_internal(ctx); return NULL; }

    ctx->window   = (float*)calloc((size_t)fft_size,     sizeof(float));
    ctx->fft_work = (float*)calloc((size_t)fft_size * 2, sizeof(float));
    ctx->mag2     = (float*)calloc((size_t)ctx->bins,    sizeof(float));
    if (!ctx->window || !ctx->fft_work || !ctx->mag2) {
        gf_pv_free_internal(ctx);
        return NULL;
    }

    // Hann window. Used for both analysis and synthesis.
    for (int i = 0; i < fft_size; i++) {
        ctx->window[i] = 0.5f * (1.0f - (float)cos(2.0 * M_PI * (double)i / (double)(fft_size - 1)));
    }

    // Overlap-add compensation for the nominal synthesis hop. The synthesis
    // hop only ever leaves this value for extreme downward pitch shifts
    // (see gf_pv_process_block), where it is recomputed on the fly.
    ctx->ola_norm        = gf_pv_window_overlap_gain(ctx->window, fft_size, hop_size);
    ctx->ola_norm_hop    = hop_size;
    ctx->hop_syn_current = hop_size;

    for (int c = 0; c < channels; c++) {
        ctx->ch[c].prev_re = (float*)calloc((size_t)ctx->bins, sizeof(float));
        ctx->ch[c].prev_im = (float*)calloc((size_t)ctx->bins, sizeof(float));
        ctx->ch[c].syn_re  = (float*)calloc((size_t)ctx->bins, sizeof(float));
        ctx->ch[c].syn_im  = (float*)calloc((size_t)ctx->bins, sizeof(float));
        ctx->ch[c].ola     = (float*)calloc((size_t)fft_size,  sizeof(float));
        if (!ctx->ch[c].prev_re || !ctx->ch[c].prev_im ||
            !ctx->ch[c].syn_re  || !ctx->ch[c].syn_im  || !ctx->ch[c].ola) {
            gf_pv_free_internal(ctx);
            return NULL;
        }
    }
    return ctx;
}

void gf_pv_destroy(gf_pv_context* ctx) { gf_pv_free_internal(ctx); }

void gf_pv_reset(gf_pv_context* ctx) {
    if (!ctx) return;
    for (int c = 0; c < ctx->channels; c++) {
        gf_pv_channel* ch = &ctx->ch[c];
        memset(ch->prev_re, 0, sizeof(float) * (size_t)ctx->bins);
        memset(ch->prev_im, 0, sizeof(float) * (size_t)ctx->bins);
        memset(ch->syn_re,  0, sizeof(float) * (size_t)ctx->bins);
        memset(ch->syn_im,  0, sizeof(float) * (size_t)ctx->bins);
        memset(ch->ola,     0, sizeof(float) * (size_t)ctx->fft_size);
        ch->in_write = ch->in_read = ch->in_count = 0;
        ch->out_write = ch->out_read = ch->out_count = 0;
        ch->in_hop_accum = 0.0f;
        ch->out_frac_pos = 0.0f;
        ch->lp_z1[0] = ch->lp_z1[1] = 0.0f;
        ch->lp_z2[0] = ch->lp_z2[1] = 0.0f;
    }
}

void gf_pv_set_stretch(gf_pv_context* ctx, float ratio) {
    if (!ctx) return;
    if (ratio < 0.25f) ratio = 0.25f;
    if (ratio > 4.0f)  ratio = 4.0f;
    ctx->stretch = ratio;
}

/// Fills one RBJ-cookbook low-pass biquad section.
///
/// [fc] is the cutoff expressed in cycles per sample (0.5 == Nyquist), so
/// the vocoder never needs to be told the sample rate. [q] selects the
/// section's resonance — the two values used below are the pole Qs of a
/// 4th-order Butterworth.
static void gf_pv_make_lowpass(gf_biquad* bq, float fc, double q) {
    const double w0    = 2.0 * M_PI * (double)fc;
    const double cosw0 = cos(w0);
    const double alpha = sin(w0) / (2.0 * q);

    const double b0 = (1.0 - cosw0) * 0.5;
    const double b1 =  1.0 - cosw0;
    const double b2 = (1.0 - cosw0) * 0.5;
    const double a0 =  1.0 + alpha;
    const double a1 = -2.0 * cosw0;
    const double a2 =  1.0 - alpha;

    bq->b0 = (float)(b0 / a0);
    bq->b1 = (float)(b1 / a0);
    bq->b2 = (float)(b2 / a0);
    bq->a1 = (float)(a1 / a0);
    bq->a2 = (float)(a2 / a0);
}

/// Recomputes the anti-alias low-pass for the current pitch ratio.
///
/// Pitching *up* means reading the vocoder's material back faster — a
/// decimation by `pitch_ratio`. Any content above `Nyquist / pitch_ratio`
/// folds back into the audible band as inharmonic hash, which is exactly
/// the metallic edge people describe as a bad pitch shifter: transpose a
/// voice up an octave and its sibilance reappears an octave *down* as a
/// whistle. Band-limiting ahead of the decimation removes it.
///
/// The filter sits on the vocoder's input. Time-stretching does not change
/// the spectrum, so filtering there is equivalent to filtering immediately
/// before the decimation, and it costs two biquads per sample instead of a
/// filter over the whole output ring.
///
/// Downward shifts read the material back *slower* (interpolation), which
/// cannot alias, so the filter is switched off for pitch_ratio <= 1.
///
/// 4th order rather than 2nd: the cutoff has to sit right at
/// Nyquist/pitch_ratio to keep the treble that survives the shift, so
/// everything that aliases lives just above the corner. A 12 dB/octave
/// slope leaves the worst folds only ~9 dB down; 24 dB/octave puts them
/// around 19 dB down for the cost of one extra biquad.
static void gf_pv_update_antialias(gf_pv_context* ctx) {
    const float r = ctx->pitch_ratio;
    if (r <= 1.0f) {          // downshift or unity — nothing can alias
        ctx->lp_active = 0;
        return;
    }

    // Normalised cutoff, capped just under Nyquist so the sections stay
    // well conditioned for tiny upward shifts (r barely above 1).
    float fc = 0.5f / r;
    if (fc > 0.45f) fc = 0.45f;

    // Pole Qs of a 4th-order Butterworth: 1 / (2 cos(pi/8)) and
    // 1 / (2 cos(3 pi/8)).
    gf_pv_make_lowpass(&ctx->lp[0], fc, 0.541196100);
    gf_pv_make_lowpass(&ctx->lp[1], fc, 1.306562965);
    ctx->lp_active = 1;
}

void gf_pv_set_pitch_semitones(gf_pv_context* ctx, float semitones) {
    if (!ctx) return;
    if (semitones < -24.0f) semitones = -24.0f;
    if (semitones >  24.0f) semitones =  24.0f;
    // Callers (the harmonizer) re-assert the same value on every audio
    // block; skipping the `pow` and the filter redesign when nothing moved
    // keeps the hot path free of transcendental maths.
    if (semitones == ctx->pitch_semis) return;
    ctx->pitch_semis = semitones;
    ctx->pitch_ratio = (float)pow(2.0, (double)semitones / 12.0);
    gf_pv_update_antialias(ctx);
}

// -------------------------------------------------------------------------
// 4. Frame processing: analysis, phase-locking, synthesis
// -------------------------------------------------------------------------

// Wraps a phase value into [-pi, pi]. Called per-peak per-frame so we keep
// it branch-light.
static inline float gf_pv_wrap_phase(float x) {
    const float twopi = 6.28318530717958647692f;
    // fmodf on some libc implementations is slow; use a manual approach.
    x += (float)M_PI;
    x -= twopi * floorf(x / twopi);
    return x - (float)M_PI;
}

// Processes one analysis frame from channel [c] starting at its current
// in_read cursor, produces one synthesis frame, and overlap-adds it into
// the channel's output ring buffer.
//
// [hop_ana] is how far the analysis cursor advances through the input after
// this frame; [hop_syn] is how many output samples the frame emits. Their
// ratio is the time-stretch factor realised by this frame.
static void gf_pv_process_frame(gf_pv_context* ctx, int c,
                                int hop_ana, int hop_syn) {
    gf_pv_channel* ch = &ctx->ch[c];
    const int N = ctx->fft_size;
    const int bins = ctx->bins;

    // Copy windowed input into the FFT work buffer (real part only).
    for (int i = 0; i < N; i++) {
        int idx = (ch->in_read + i) & (GF_PV_IN_RING_CAP - 1);
        float s = ch->in_ring[idx] * ctx->window[i];
        ctx->fft_work[2*i]     = s;
        ctx->fft_work[2*i + 1] = 0.0f;
    }

    // Forward FFT.
    gf_fft_execute(&ctx->fft, ctx->fft_work, 0);

    // Squared magnitude for the positive-frequency half (DC..Nyquist).
    // Squared is enough: peak picking only ever compares magnitudes, and
    // squaring is monotonic — so the `sqrtf` per bin is pure waste.
    for (int k = 0; k < bins; k++) {
        float re = ctx->fft_work[2*k];
        float im = ctx->fft_work[2*k + 1];
        ctx->mag2[k] = re*re + im*im;
    }

    // --- Phase-locked vocoder ---
    //
    // Step A: detect spectral peaks. A bin k is a peak if its magnitude
    // exceeds its 4 nearest neighbours.
    //
    // Step B: for each peak, compute the expected phase advance from the
    // previous analysis hop, measure the deviation, and derive the
    // synthesis phase by stepping forward by that true advance times the
    // hop ratio (= hop_syn / hop_ana = the stretch of this frame).
    //
    // Step C: each peak's region of influence is [mid_prev..mid_next], and
    // every bin in that region is rotated by the peak's phase correction.
    // This is the "phase locking" that keeps partials vertically coherent
    // and preserves transient shape. Because every bin in the region takes
    // the *same* rotation, the whole region is one complex multiply per
    // bin — no per-bin trigonometry.

    const float hop_ratio     = (float)hop_syn / (float)hop_ana;
    const float twopi         = 6.28318530717958647692f;
    const float expected_base = twopi * (float)hop_ana / (float)N;

    // Peak collection: stack array is fine since max bins ~= 4097 and
    // worst-case peaks ~= bins/2, so 2048 ints = 8KB.
    int peaks[GF_PV_MAX_FFT / 2 + 2];
    int num_peaks = 0;
    for (int k = 2; k < bins - 2; k++) {
        if (ctx->mag2[k] > ctx->mag2[k-1] && ctx->mag2[k] > ctx->mag2[k-2] &&
            ctx->mag2[k] > ctx->mag2[k+1] && ctx->mag2[k] > ctx->mag2[k+2]) {
            peaks[num_peaks++] = k;
        }
    }

    // Keep the analysis spectrum before it is overwritten by the synthesis
    // one — the phase advance of the *next* frame is measured against it.
    // prev_re/prev_im are still the frame-before-last at this point, which
    // is exactly what the loop below needs.
    if (num_peaks == 0) {
        // Digitally silent frame: nothing to resynthesise, and there is no
        // meaningful phase to continue from. Clearing the stored spectra
        // makes the next sounding frame start from phase zero, which is the
        // right behaviour at a note onset.
        for (int b = 0; b < bins; b++) {
            ch->prev_re[b] = ctx->fft_work[2*b];
            ch->prev_im[b] = ctx->fft_work[2*b + 1];
            ch->syn_re[b]  = 0.0f;
            ch->syn_im[b]  = 0.0f;
            ctx->fft_work[2*b]     = 0.0f;
            ctx->fft_work[2*b + 1] = 0.0f;
        }
    } else {
        for (int p = 0; p < num_peaks; p++) {
            const int k = peaks[p];

            const float xr = ctx->fft_work[2*k];
            const float xi = ctx->fft_work[2*k + 1];

            // Phase advance since the previous analysis frame, obtained
            // from X_now * conj(X_prev) — one atan2 instead of two.
            const float pr = ch->prev_re[k];
            const float pi_ = ch->prev_im[k];
            const float cross_re = xr * pr + xi * pi_;
            const float cross_im = xi * pr - xr * pi_;
            const float measured = atan2f(cross_im, cross_re);

            // Deviation from the advance a bin-centre frequency would have
            // produced tells us the partial's true instantaneous frequency.
            const float deviation    = gf_pv_wrap_phase(
                measured - expected_base * (float)k);
            const float true_advance = expected_base * (float)k + deviation;

            // Continue the synthesis phase from where the previous output
            // frame left this bin, advancing by the true frequency scaled
            // by the stretch factor.
            const float prev_syn_phase =
                atan2f(ch->syn_im[k], ch->syn_re[k]);
            const float new_phase = prev_syn_phase + true_advance * hop_ratio;

            // The rotation that turns the analysed bin into the synthesis
            // bin. Applied as a complex multiply to the peak's whole region.
            const float rot = new_phase - atan2f(xi, xr);
            const float cr  = cosf(rot);
            const float ci  = sinf(rot);

            const int lo = (p == 0) ? 0 : (peaks[p-1] + k) / 2 + 1;
            const int hi = (p == num_peaks - 1) ? (bins - 1)
                                                : (k + peaks[p+1]) / 2;
            for (int b = lo; b <= hi; b++) {
                const float br = ctx->fft_work[2*b];
                const float bi = ctx->fft_work[2*b + 1];
                ch->prev_re[b] = br;   // stash analysis bin for the next frame
                ch->prev_im[b] = bi;
                const float yr = br * cr - bi * ci;
                const float yi = br * ci + bi * cr;
                ctx->fft_work[2*b]     = yr;
                ctx->fft_work[2*b + 1] = yi;
                ch->syn_re[b] = yr;    // running synthesis phase carrier
                ch->syn_im[b] = yi;
            }
        }
    }

    // Reconstruct the negative-frequency half as conjugate of the positive
    // half (Hermitian symmetry of real-input FFTs).
    for (int k = 1; k < bins - 1; k++) {
        ctx->fft_work[2*(N - k)]     =  ctx->fft_work[2*k];
        ctx->fft_work[2*(N - k) + 1] = -ctx->fft_work[2*k + 1];
    }

    // Inverse FFT.
    gf_fft_execute(&ctx->fft, ctx->fft_work, 1);

    // Overlap-add the windowed time-domain frame into the channel's OLA.
    // ola_norm compensates for the sum of w_a*w_s at the *synthesis* hop
    // so the analysis/synthesis chain has unity gain. Caching it against
    // the hop it was computed for keeps the common case free.
    if (ctx->ola_norm_hop != hop_syn) {
        ctx->ola_norm     = gf_pv_window_overlap_gain(ctx->window, N, hop_syn);
        ctx->ola_norm_hop = hop_syn;
    }
    const float ola_norm = ctx->ola_norm;
    for (int i = 0; i < N; i++) {
        ch->ola[i] += ctx->fft_work[2*i] * ctx->window[i] * ola_norm;
    }

    // Shift out the leading hop_syn samples of ola[] into the output ring,
    // and left-shift the OLA buffer to make room for the next frame.
    for (int i = 0; i < hop_syn; i++) {
        int idx = (ch->out_write + i) & (GF_PV_OUT_RING_CAP - 1);
        ch->out_ring[idx] = ch->ola[i];
    }
    ch->out_write = (ch->out_write + hop_syn) & (GF_PV_OUT_RING_CAP - 1);
    ch->out_count += hop_syn;

    // Shift OLA left by hop_syn, zero-filling the tail.
    memmove(ch->ola, ch->ola + hop_syn, sizeof(float) * (size_t)(N - hop_syn));
    memset(ch->ola + (N - hop_syn), 0, sizeof(float) * (size_t)hop_syn);

    // Advance the analysis read cursor by one analysis hop.
    ch->in_read = (ch->in_read + hop_ana) & (GF_PV_IN_RING_CAP - 1);
    ch->in_count -= hop_ana;
}

// -------------------------------------------------------------------------
// 5. Streaming front-end
// -------------------------------------------------------------------------

/// Number of output frames the vocoder could hand over right now.
///
/// Fast path: one output frame per buffered ring sample. Downshift path:
/// roughly out_count / pitch_ratio, but the last sample of a fractional
/// read needs its successor to interpolate against, so the budget is
/// (out_count - 1 - out_frac_pos) / pitch_ratio. Stereo takes the minimum
/// across channels, since both must advance together.
static int gf_pv_drainable(const gf_pv_context* ctx) {
    const int C = ctx->channels;
    const float pitch_ratio = (ctx->pitch_ratio > 0.0f) ? ctx->pitch_ratio : 1.0f;
    const int frac_drain = (pitch_ratio != 1.0f);

    if (!frac_drain) {
        int avail = ctx->ch[0].out_count;
        for (int c = 1; c < C; c++) {
            if (ctx->ch[c].out_count < avail) avail = ctx->ch[c].out_count;
        }
        return avail;
    }

    int avail = 0;
    if (ctx->ch[0].out_count >= 2) {
        float budget =
            ((float)ctx->ch[0].out_count - 1.0f - ctx->ch[0].out_frac_pos)
            / pitch_ratio;
        avail = (int)floorf(budget);
        if (avail < 0) avail = 0;
        for (int c = 1; c < C; c++) {
            if (ctx->ch[c].out_count < 2) return 0;
            float cb =
                ((float)ctx->ch[c].out_count - 1.0f - ctx->ch[c].out_frac_pos)
                / pitch_ratio;
            int ca = (int)floorf(cb);
            if (ca < avail) avail = ca;
        }
    }
    return avail;
}

int gf_pv_available(const gf_pv_context* ctx) {
    return ctx ? gf_pv_drainable(ctx) : 0;
}

int gf_pv_output_quantum(const gf_pv_context* ctx) {
    if (!ctx) return 0;
    // One synthesis frame writes hop_syn samples into the output ring, and
    // the drain consumes pitch_ratio ring samples per output frame, so a
    // production event moves gf_pv_available by hop_syn / pitch_ratio.
    const float pitch_ratio = (ctx->pitch_ratio > 0.0f) ? ctx->pitch_ratio : 1.0f;
    const int q = (int)((float)ctx->hop_syn_current / pitch_ratio);
    return (q < 1) ? 1 : q;
}

int gf_pv_process_block(gf_pv_context* ctx,
                        const float* input_interleaved,
                        int num_frames,
                        float* output_interleaved,
                        int output_capacity_frames) {
    if (!ctx || num_frames < 0 || output_capacity_frames < 0) return 0;

    const int C = ctx->channels;
    const int N = ctx->fft_size;
    const float pitch_ratio = (ctx->pitch_ratio > 0.0f) ? ctx->pitch_ratio : 1.0f;

    // 1. Push input frames into each channel's input ring, band-limiting
    //    first when an upward pitch shift is active. See
    //    gf_pv_update_antialias: the drain stage reads the ring back faster
    //    than it was written, and anything above Nyquist/pitch_ratio would
    //    fold back into the band. Time-stretching does not move the
    //    spectrum, so filtering here is equivalent to filtering immediately
    //    before that read.
    if (ctx->lp_active) {
        const gf_biquad* bq = ctx->lp;
        for (int i = 0; i < num_frames; i++) {
            for (int c = 0; c < C; c++) {
                gf_pv_channel* ch = &ctx->ch[c];
                float y = input_interleaved[i * C + c];
                // Transposed direct form II — two state words per section,
                // no history buffer, well behaved in single precision.
                for (int k = 0; k < 2; k++) {
                    const float x = y;
                    y = bq[k].b0 * x + ch->lp_z1[k];
                    ch->lp_z1[k] = bq[k].b1 * x - bq[k].a1 * y + ch->lp_z2[k];
                    ch->lp_z2[k] = bq[k].b2 * x - bq[k].a2 * y;
                }
                ch->in_ring[ch->in_write] = y;
                ch->in_write = (ch->in_write + 1) & (GF_PV_IN_RING_CAP - 1);
                ch->in_count++;
            }
        }
    } else {
        for (int i = 0; i < num_frames; i++) {
            for (int c = 0; c < C; c++) {
                gf_pv_channel* ch = &ctx->ch[c];
                ch->in_ring[ch->in_write] = input_interleaved[i * C + c];
                ch->in_write = (ch->in_write + 1) & (GF_PV_IN_RING_CAP - 1);
                ch->in_count++;
            }
        }
    }

    // 2. As long as channel 0 has enough samples (N from the read cursor),
    //    produce one synthesis frame per channel. Channels are in lock-step
    //    — they all consume the same analysis hop and emit the same
    //    synthesis hop.
    //
    // Pitch shift is implemented by time-stretching the input internally
    // and then resampling the output ring back to the requested duration
    // in the drain stage below. The composition is:
    //
    //   stretched_length = input_length * (user_stretch * pitch_ratio)
    //   resample by pitch_ratio → output_length = stretched_length / pitch_ratio
    //                                            = input_length * user_stretch
    //
    // The pitch axis sits in the resample step: a phase-vocoder time
    // stretch preserves the input pitch, so the stretched audio still has
    // the original frequency content. Resampling by pitch_ratio plays it
    // back at pitch_ratio× the rate, multiplying every frequency by
    // pitch_ratio — exactly the desired shift.
    //
    // So internal_stretch = user_stretch * pitch_ratio.
    //
    // The resampling stays on the *output* side. Doing it on the input
    // instead would keep the analysis frame rate flat across the whole
    // pitch range, which is cheaper, but it also means the analysis window
    // fills at 1/pitch_ratio of real time — an octave up would double the
    // vocoder's latency. For a harmonizer somebody plays live, latency is
    // worth more than the CPU.
    const float user_stretch = ctx->stretch;
    float internal_stretch = user_stretch * pitch_ratio;
    // Clamp internal stretch to the PV's working range. The user setters
    // clamp the user-facing ratios, but their composition can escape the
    // safe band (e.g. user_stretch=4 × pitch_ratio=4 → internal=16).
    if (internal_stretch < 0.125f) internal_stretch = 0.125f;
    if (internal_stretch > 8.0f)   internal_stretch = 8.0f;

    // ── Hop scheduling ────────────────────────────────────────────────────
    //
    // The stretch ratio is hop_syn / hop_ana, and whichever hop carries it
    // must be the one that gets *smaller* — never the one that grows past
    // the configured hop:
    //
    //   - Synthesis overlap below 4x makes overlap-add gain ripple. Letting
    //     hop_syn follow the ratio, as this file did before, drops it to 2x
    //     at an octave up and to nothing at two octaves, stamping a loud
    //     tremolo at the frame rate onto every upward voice.
    //   - Analysis overlap below 4x leaves consecutive frames too far apart
    //     for the measured phase advance to be unambiguous, which smears
    //     the pitch estimate.
    //
    // So stretching shortens the analysis hop and compressing shortens the
    // synthesis hop. Both stay at or under the nominal hop, both overlaps
    // stay at 4x or better, and no clamping is needed at any ratio in the
    // supported range.
    int   hop_syn;
    float hop_ana_f;
    if (internal_stretch >= 1.0f) {
        hop_syn   = ctx->hop_nominal;
        hop_ana_f = (float)ctx->hop_nominal / internal_stretch;
    } else {
        hop_ana_f = (float)ctx->hop_nominal;
        hop_syn   = (int)((float)ctx->hop_nominal * internal_stretch + 0.5f);
        if (hop_syn < 1) hop_syn = 1;
    }
    if (hop_ana_f < 1.0f) hop_ana_f = 1.0f;

    // Remembered so gf_pv_output_quantum can tell a caller how big a step
    // the next production event will be.
    ctx->hop_syn_current = hop_syn;

    while (ctx->ch[0].in_count >= N) {
        // Compute this frame's integer analysis hop from the running
        // fractional accumulator, so the long-run stretch ratio stays
        // accurate even when hop_syn / stretch is non-integer.
        gf_pv_channel* ch0 = &ctx->ch[0];
        float want = hop_ana_f + ch0->in_hop_accum;
        int   hop_ana = (int)floorf(want);
        if (hop_ana < 1) hop_ana = 1;
        if (hop_ana > N) hop_ana = N;   // safety clamp
        float residue = want - (float)hop_ana;

        for (int c = 0; c < C; c++) {
            ctx->ch[c].in_hop_accum = residue;
            gf_pv_process_frame(ctx, c, hop_ana, hop_syn);
        }
    }

    // 3. Drain each channel's output ring into the interleaved output.
    //
    // Two paths:
    //
    //   Fast path (no pitch shift): integer-step drain, one ring sample per
    //   output sample. This is the plain time-stretch behaviour — the ring
    //   already holds audio at the desired rate.
    //
    //   Pitch-shift path: fractional-step drain. Each output sample reads
    //   a linearly-interpolated value at `out_frac_pos` within the ring
    //   and advances the cursor by `pitch_ratio`: more than one ring sample
    //   per output frame going up, less than one going down. Because the
    //   vocoder stretched by pitch_ratio first, the net output duration
    //   matches the user's stretch request while every frequency is scaled
    //   by pitch_ratio.
    const int frac_drain = (pitch_ratio != 1.0f);

    // How many output frames can we safely emit? See gf_pv_drainable.
    int avail = gf_pv_drainable(ctx);
    int emit = (avail < output_capacity_frames) ? avail : output_capacity_frames;

    if (!frac_drain) {
        // Fast integer drain.
        for (int i = 0; i < emit; i++) {
            for (int c = 0; c < C; c++) {
                gf_pv_channel* ch = &ctx->ch[c];
                output_interleaved[i * C + c] = ch->out_ring[ch->out_read];
                ch->out_read = (ch->out_read + 1) & (GF_PV_OUT_RING_CAP - 1);
                ch->out_count--;
            }
        }
    } else {
        // Fractional drain with linear interpolation.
        for (int i = 0; i < emit; i++) {
            for (int c = 0; c < C; c++) {
                gf_pv_channel* ch = &ctx->ch[c];
                int r0 = ch->out_read;
                int r1 = (r0 + 1) & (GF_PV_OUT_RING_CAP - 1);
                float s0 = ch->out_ring[r0];
                float s1 = ch->out_ring[r1];
                float f  = ch->out_frac_pos;
                output_interleaved[i * C + c] = s0 * (1.0f - f) + s1 * f;

                ch->out_frac_pos += pitch_ratio;
                // Advance by as many whole samples as the fractional
                // accumulator has crossed.
                while (ch->out_frac_pos >= 1.0f) {
                    ch->out_frac_pos -= 1.0f;
                    ch->out_read = (ch->out_read + 1) & (GF_PV_OUT_RING_CAP - 1);
                    ch->out_count--;
                }
            }
        }
    }
    return emit;
}

// -------------------------------------------------------------------------
// 6. Offline helper
// -------------------------------------------------------------------------

int gf_pv_time_stretch_offline(const float* input,
                               int num_frames,
                               int channels,
                               int sample_rate,
                               float stretch_ratio,
                               int fft_size,
                               float* output,
                               int output_capacity) {
    (void)sample_rate; // sample rate is not needed — the vocoder operates in samples
    if (channels < 1 || channels > GF_PV_MAX_CHANNELS) return 0;

    gf_pv_context* ctx = gf_pv_create(fft_size, fft_size / 4, channels);
    if (!ctx) return 0;
    gf_pv_set_stretch(ctx, stretch_ratio);

    // Feed input in chunks, collect output.
    int total_out = 0;
    int in_pos = 0;
    const int chunk = 1024;
    while (in_pos < num_frames) {
        int to_feed = (num_frames - in_pos < chunk) ? (num_frames - in_pos) : chunk;
        int produced = gf_pv_process_block(
            ctx,
            input + in_pos * channels,
            to_feed,
            output + total_out * channels,
            output_capacity - total_out);
        total_out += produced;
        in_pos    += to_feed;
        if (total_out >= output_capacity) break;
    }
    // Flush: feed zeros to drain the tail.
    int tail = fft_size * 2;
    static float zeros[GF_PV_MAX_FFT * 2 * GF_PV_MAX_CHANNELS] = {0};
    while (tail > 0 && total_out < output_capacity) {
        int to_feed = (tail < chunk) ? tail : chunk;
        int produced = gf_pv_process_block(
            ctx, zeros, to_feed,
            output + total_out * channels,
            output_capacity - total_out);
        total_out += produced;
        tail -= to_feed;
        if (produced == 0) break;
    }

    gf_pv_destroy(ctx);
    return total_out;
}

// Offline pitch shift — same shape as gf_pv_time_stretch_offline but drives
// the pitch axis instead. Shifts [input] by [semitones] and writes the
// result (same duration as input) to [output]. Host-only convenience for
// smoke tests and offline rendering.
int gf_pv_pitch_shift_offline(const float* input,
                              int num_frames,
                              int channels,
                              int sample_rate,
                              float semitones,
                              int fft_size,
                              float* output,
                              int output_capacity) {
    (void)sample_rate;
    if (channels < 1 || channels > GF_PV_MAX_CHANNELS) return 0;

    gf_pv_context* ctx = gf_pv_create(fft_size, fft_size / 4, channels);
    if (!ctx) return 0;
    gf_pv_set_stretch(ctx, 1.0f);
    gf_pv_set_pitch_semitones(ctx, semitones);

    int total_out = 0;
    int in_pos = 0;
    const int chunk = 1024;
    while (in_pos < num_frames && total_out < output_capacity) {
        int to_feed = (num_frames - in_pos < chunk) ? (num_frames - in_pos) : chunk;
        int produced = gf_pv_process_block(
            ctx,
            input + in_pos * channels,
            to_feed,
            output + total_out * channels,
            output_capacity - total_out);
        total_out += produced;
        in_pos    += to_feed;
    }
    int tail = fft_size * 2;
    static float zeros[GF_PV_MAX_FFT * 2 * GF_PV_MAX_CHANNELS] = {0};
    while (tail > 0 && total_out < output_capacity) {
        int to_feed = (tail < chunk) ? tail : chunk;
        int produced = gf_pv_process_block(
            ctx, zeros, to_feed,
            output + total_out * channels,
            output_capacity - total_out);
        total_out += produced;
        tail -= to_feed;
        if (produced == 0) break;
    }

    gf_pv_destroy(ctx);
    return total_out;
}
