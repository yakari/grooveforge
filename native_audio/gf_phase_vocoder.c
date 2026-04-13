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
//   - phase accumulator for every FFT bin (synthesis phase)
//   - last analysis phase (for computing phase advance)
//   - synthesis overlap-add tail
//   - in/out ring buffers
//
// fft_work and mag/phase scratch are shared across channels since we
// process channels serially.

typedef struct {
    // Phase state (length fft_size/2 + 1).
    float* last_phase;   // analysis phase from the previous frame
    float* sum_phase;    // running synthesis phase

    // Overlap-add tail of length fft_size. Newly synthesised frames are
    // added on top of this buffer and shifted out by hop_out samples.
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

    // Fractional accumulator for output shifting. When the synthesis hop
    // is not an integer (stretch_ratio * hop_in), we keep the fractional
    // residue across frames and step the output cursor by an integer
    // count each time.
    float  out_hop_accum;

    // Fractional read position within the output ring, used only when
    // pitch shifting is active (pitch_ratio != 1). Each output frame we
    // emit consumes `pitch_ratio` samples from the ring — less than 1 for
    // downshifts, more than 1 for upshifts — implemented via linear
    // interpolation between adjacent ring samples. Zero when pitch_ratio
    // is 1 so the fast path degenerates into the old integer drain.
    float  out_frac_pos;
} gf_pv_channel;

// -------------------------------------------------------------------------
// 3. Context
// -------------------------------------------------------------------------

struct gf_pv_context {
    int   fft_size;
    int   hop_in;        // analysis hop (input stride)
    int   channels;
    int   bins;          // fft_size/2 + 1

    float stretch;       // current stretch ratio
    float pitch_ratio;   // 2^(semitones/12). 1.0 = no shift.

    gf_fft fft;

    // Pre-allocated Hann analysis/synthesis window.
    float* window;

    // Scratch buffers shared across channels. Real-time safe because
    // channels are processed serially on the same thread.
    float* fft_work;     // length 2*fft_size (interleaved complex)
    float* mag;          // length bins
    float* phase;        // length bins
    float  ola_norm;     // OLA compensation: 1 / sum_k(w_a * w_s at overlap)

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
    free(ctx->mag);
    free(ctx->phase);
    for (int c = 0; c < GF_PV_MAX_CHANNELS; c++) {
        free(ctx->ch[c].last_phase);
        free(ctx->ch[c].sum_phase);
        free(ctx->ch[c].ola);
    }
    free(ctx);
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
    ctx->hop_in      = hop_size;
    ctx->channels    = channels;
    ctx->bins        = fft_size / 2 + 1;
    ctx->stretch     = 1.0f;
    ctx->pitch_ratio = 1.0f;

    if (!gf_fft_init(&ctx->fft, fft_size)) { gf_pv_free_internal(ctx); return NULL; }

    ctx->window   = (float*)calloc((size_t)fft_size,     sizeof(float));
    ctx->fft_work = (float*)calloc((size_t)fft_size * 2, sizeof(float));
    ctx->mag      = (float*)calloc((size_t)ctx->bins,    sizeof(float));
    ctx->phase    = (float*)calloc((size_t)ctx->bins,    sizeof(float));
    if (!ctx->window || !ctx->fft_work || !ctx->mag || !ctx->phase) {
        gf_pv_free_internal(ctx);
        return NULL;
    }

    // Hann window. Used for both analysis and synthesis.
    for (int i = 0; i < fft_size; i++) {
        ctx->window[i] = 0.5f * (1.0f - (float)cos(2.0 * M_PI * (double)i / (double)(fft_size - 1)));
    }

    // Compute OLA compensation. For a given sample position, the number
    // of analysis/synthesis frames overlapping it is fft_size / hop_size.
    // The sum of w_a[i]*w_s[i] evaluated at those overlapping frame
    // offsets is approximately constant across the frame interior; we
    // measure it at position N/2 (guaranteed to be fully overlapped) by
    // summing the squared window at every hop_in offset.
    double overlap_sum = 0.0;
    for (int i = 0; i < fft_size; i += hop_size) {
        // Contribution of the frame centred such that sample N/2 lands
        // at offset i in the window.
        double w = ctx->window[i];
        overlap_sum += w * w;
    }
    ctx->ola_norm = (overlap_sum > 1e-6) ? (float)(1.0 / overlap_sum) : 1.0f;

    for (int c = 0; c < channels; c++) {
        ctx->ch[c].last_phase = (float*)calloc((size_t)ctx->bins,    sizeof(float));
        ctx->ch[c].sum_phase  = (float*)calloc((size_t)ctx->bins,    sizeof(float));
        ctx->ch[c].ola        = (float*)calloc((size_t)fft_size,     sizeof(float));
        if (!ctx->ch[c].last_phase || !ctx->ch[c].sum_phase || !ctx->ch[c].ola) {
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
        memset(ch->last_phase, 0, sizeof(float) * (size_t)ctx->bins);
        memset(ch->sum_phase,  0, sizeof(float) * (size_t)ctx->bins);
        memset(ch->ola,        0, sizeof(float) * (size_t)ctx->fft_size);
        ch->in_write = ch->in_read = ch->in_count = 0;
        ch->out_write = ch->out_read = ch->out_count = 0;
        ch->out_hop_accum = 0.0f;
        ch->out_frac_pos  = 0.0f;
    }
}

void gf_pv_set_stretch(gf_pv_context* ctx, float ratio) {
    if (!ctx) return;
    if (ratio < 0.25f) ratio = 0.25f;
    if (ratio > 4.0f)  ratio = 4.0f;
    ctx->stretch = ratio;
}

void gf_pv_set_pitch_semitones(gf_pv_context* ctx, float semitones) {
    if (!ctx) return;
    if (semitones < -24.0f) semitones = -24.0f;
    if (semitones >  24.0f) semitones =  24.0f;
    ctx->pitch_ratio = (float)pow(2.0, (double)semitones / 12.0);
}

// -------------------------------------------------------------------------
// 4. Frame processing: analysis, phase-locking, synthesis
// -------------------------------------------------------------------------

// Wraps a phase value into [-pi, pi]. Called per-bin per-frame so we keep
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
// [hop_out_int] is the integer number of output samples this frame should
// advance the output cursor by. Computed by the caller from the (possibly
// fractional) stretch ratio, using an accumulator to avoid drift.
static void gf_pv_process_frame(gf_pv_context* ctx, int c, int hop_out_int) {
    gf_pv_channel* ch = &ctx->ch[c];
    const int N = ctx->fft_size;
    const int bins = ctx->bins;
    const int hop_in = ctx->hop_in;

    // Copy windowed input into the FFT work buffer (real part only).
    for (int i = 0; i < N; i++) {
        int idx = (ch->in_read + i) & (GF_PV_IN_RING_CAP - 1);
        float s = ch->in_ring[idx] * ctx->window[i];
        ctx->fft_work[2*i]     = s;
        ctx->fft_work[2*i + 1] = 0.0f;
    }

    // Forward FFT.
    gf_fft_execute(&ctx->fft, ctx->fft_work, 0);

    // Compute magnitude + phase for the positive-frequency half (DC..Nyquist).
    for (int k = 0; k < bins; k++) {
        float re = ctx->fft_work[2*k];
        float im = ctx->fft_work[2*k + 1];
        ctx->mag[k]   = sqrtf(re*re + im*im);
        ctx->phase[k] = atan2f(im, re);
    }

    // --- Phase-locked vocoder ---
    //
    // Step A: detect spectral peaks. A bin k is a peak if its magnitude
    // exceeds its 4 nearest neighbours.
    //
    // Step B: for each peak, compute the expected phase advance from the
    // previous analysis hop, measure the deviation, and derive the
    // synthesis phase by stepping forward by that true advance times the
    // hop ratio (= hop_out / hop_in = effective stretch of this frame).
    //
    // Step C: each peak's region of influence is [mid_prev..mid_next], and
    // every bin in that region takes the peak's phase rotation. This is
    // the "phase locking" that keeps partials vertically coherent and
    // preserves transient shape.

    const float hop_ratio = (float)hop_out_int / (float)hop_in;
    const float twopi = 6.28318530717958647692f;
    const float expected_base = twopi * (float)hop_in / (float)N;

    // Peak collection: stack array is fine since max bins ~= 4097 and
    // worst-case peaks ~= bins/2, so 2048 ints = 8KB.
    int peaks[GF_PV_MAX_FFT / 2 + 2];
    int num_peaks = 0;
    for (int k = 2; k < bins - 2; k++) {
        if (ctx->mag[k] > ctx->mag[k-1] && ctx->mag[k] > ctx->mag[k-2] &&
            ctx->mag[k] > ctx->mag[k+1] && ctx->mag[k] > ctx->mag[k+2]) {
            peaks[num_peaks++] = k;
        }
    }

    if (num_peaks == 0) {
        // Silent / flat frame: advance synth phases linearly so the next
        // non-silent frame still has a sensible starting phase.
        for (int b = 0; b < bins; b++) {
            ch->sum_phase[b] += expected_base * (float)b * hop_ratio;
            ctx->fft_work[2*b]     = 0.0f;
            ctx->fft_work[2*b + 1] = 0.0f;
        }
    } else {
        // For each peak, compute rotation, then fill its region [lo..hi].
        for (int p = 0; p < num_peaks; p++) {
            int k = peaks[p];
            float dphase = ctx->phase[k] - ch->last_phase[k] - expected_base * (float)k;
            dphase = gf_pv_wrap_phase(dphase);
            float true_advance = expected_base * (float)k + dphase;
            float new_phase = ch->sum_phase[k] + true_advance * hop_ratio;
            float rot = new_phase - ctx->phase[k];

            int lo = (p == 0) ? 0 : (peaks[p-1] + k) / 2 + 1;
            int hi = (p == num_peaks - 1) ? (bins - 1)
                                          : (k + peaks[p+1]) / 2;
            for (int b = lo; b <= hi; b++) {
                float locked = ctx->phase[b] + rot;
                ch->sum_phase[b] = locked;
                float m = ctx->mag[b];
                ctx->fft_work[2*b]     = m * cosf(locked);
                ctx->fft_work[2*b + 1] = m * sinf(locked);
            }
        }
    }

    // Save this frame's analysis phases for the next iteration.
    memcpy(ch->last_phase, ctx->phase, sizeof(float) * (size_t)bins);

    // Reconstruct the negative-frequency half as conjugate of the positive
    // half (Hermitian symmetry of real-input FFTs).
    for (int k = 1; k < bins - 1; k++) {
        ctx->fft_work[2*(N - k)]     =  ctx->fft_work[2*k];
        ctx->fft_work[2*(N - k) + 1] = -ctx->fft_work[2*k + 1];
    }

    // Inverse FFT.
    gf_fft_execute(&ctx->fft, ctx->fft_work, 1);

    // Overlap-add the windowed time-domain frame into the channel's OLA.
    // ola_norm compensates for the sum of w_a*w_s at the given overlap
    // factor so the analysis/synthesis chain has unity gain.
    const float ola_norm = ctx->ola_norm;
    for (int i = 0; i < N; i++) {
        ch->ola[i] += ctx->fft_work[2*i] * ctx->window[i] * ola_norm;
    }

    // Shift out the leading hop_out_int samples of ola[] into the output
    // ring, and left-shift the OLA buffer to make room for the next frame.
    for (int i = 0; i < hop_out_int; i++) {
        int idx = (ch->out_write + i) & (GF_PV_OUT_RING_CAP - 1);
        ch->out_ring[idx] = ch->ola[i];
    }
    ch->out_write = (ch->out_write + hop_out_int) & (GF_PV_OUT_RING_CAP - 1);
    ch->out_count += hop_out_int;

    // Shift OLA left by hop_out_int, zero-filling the tail.
    memmove(ch->ola, ch->ola + hop_out_int, sizeof(float) * (size_t)(N - hop_out_int));
    memset(ch->ola + (N - hop_out_int), 0, sizeof(float) * (size_t)hop_out_int);

    // Advance the analysis read cursor by one input hop.
    ch->in_read = (ch->in_read + hop_in) & (GF_PV_IN_RING_CAP - 1);
    ch->in_count -= hop_in;
}

// -------------------------------------------------------------------------
// 5. Streaming front-end
// -------------------------------------------------------------------------

int gf_pv_process_block(gf_pv_context* ctx,
                        const float* input_interleaved,
                        int num_frames,
                        float* output_interleaved,
                        int output_capacity_frames) {
    if (!ctx || num_frames < 0 || output_capacity_frames < 0) return 0;

    const int C = ctx->channels;
    const int N = ctx->fft_size;
    const int hop_in = ctx->hop_in;

    // 1. Push input frames into each channel's input ring.
    for (int i = 0; i < num_frames; i++) {
        for (int c = 0; c < C; c++) {
            gf_pv_channel* ch = &ctx->ch[c];
            ch->in_ring[ch->in_write] = input_interleaved[i * C + c];
            ch->in_write = (ch->in_write + 1) & (GF_PV_IN_RING_CAP - 1);
            ch->in_count++;
        }
    }

    // 2. As long as channel 0 has enough samples (N from the read cursor),
    //    produce one synthesis frame per channel. Channels are in lock-step
    //    — they all consume the same hop_in and produce the same hop_out.
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
    const float pitch_ratio = (ctx->pitch_ratio > 0.0f) ? ctx->pitch_ratio : 1.0f;
    const float user_stretch = ctx->stretch;
    float internal_stretch = user_stretch * pitch_ratio;
    // Clamp internal stretch to the PV's working range. The user setters
    // clamp the user-facing ratios, but their composition can escape the
    // safe band (e.g. user_stretch=4 × pitch_ratio=4 → internal=16).
    if (internal_stretch < 0.125f) internal_stretch = 0.125f;
    if (internal_stretch > 8.0f)   internal_stretch = 8.0f;

    while (ctx->ch[0].in_count >= N) {
        // Compute this frame's integer output hop from the running
        // fractional accumulator. This keeps the long-run stretch ratio
        // accurate even when stretch * hop_in is non-integer.
        gf_pv_channel* ch0 = &ctx->ch[0];
        float want = (float)hop_in * internal_stretch + ch0->out_hop_accum;
        int   hop_out_int = (int)floorf(want);
        if (hop_out_int < 1) hop_out_int = 1;
        if (hop_out_int > N) hop_out_int = N;  // safety clamp
        float residue = want - (float)hop_out_int;

        for (int c = 0; c < C; c++) {
            ctx->ch[c].out_hop_accum = residue;
            gf_pv_process_frame(ctx, c, hop_out_int);
        }
    }

    // 3. Drain each channel's output ring into the interleaved output.
    //
    // Two paths:
    //
    //   Fast path (pitch_ratio == 1): integer-step drain, one ring sample
    //   per output sample. This is the original time-stretch behaviour —
    //   the ring already contains audio at the desired rate.
    //
    //   Pitch-shift path: fractional-step drain. Each output sample reads
    //   a linearly-interpolated value at `out_frac_pos` within the ring
    //   and advances the cursor by `pitch_ratio`. For pitch_ratio > 1 we
    //   consume more than one ring sample per output frame (upshift); for
    //   pitch_ratio < 1 we emit multiple output frames per ring sample
    //   (downshift). Because the stretched audio has been compressed /
    //   expanded by 1/pitch_ratio, the net output duration matches the
    //   user's stretch request while the frequency content is scaled by
    //   pitch_ratio.

    // How many output frames can we safely emit? Fast path: one per ring
    // sample. Pitch path: approximately out_count / pitch_ratio, but we
    // need at least 2 ring samples to interpolate the last one, so we
    // cap at (out_count - 1) / pitch_ratio rounded down. Min across
    // channels for safety.
    int avail;
    if (pitch_ratio == 1.0f) {
        avail = ctx->ch[0].out_count;
        for (int c = 1; c < C; c++) {
            if (ctx->ch[c].out_count < avail) avail = ctx->ch[c].out_count;
        }
    } else {
        // Each channel's current cursor eats pitch_ratio ring samples per
        // output frame. We need the next sample for interpolation, so
        // effective budget is (out_count - 1 - out_frac_pos) / pitch_ratio.
        avail = 0;
        if (ctx->ch[0].out_count >= 2) {
            float budget =
                ((float)ctx->ch[0].out_count - 1.0f - ctx->ch[0].out_frac_pos)
                / pitch_ratio;
            avail = (int)floorf(budget);
            if (avail < 0) avail = 0;
            for (int c = 1; c < C; c++) {
                if (ctx->ch[c].out_count < 2) { avail = 0; break; }
                float cb =
                    ((float)ctx->ch[c].out_count - 1.0f - ctx->ch[c].out_frac_pos)
                    / pitch_ratio;
                int ca = (int)floorf(cb);
                if (ca < avail) avail = ca;
            }
        }
    }
    int emit = (avail < output_capacity_frames) ? avail : output_capacity_frames;

    if (pitch_ratio == 1.0f) {
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
