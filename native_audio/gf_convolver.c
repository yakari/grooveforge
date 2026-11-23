// gf_convolver.c — Zero-latency convolution. See gf_convolver.h.

#include "gf_convolver.h"

#include "gf_fft.h"

#include <stdlib.h>
#include <string.h>

/// Partition length: the head summed directly, and the size of each FFT
/// partition. 128 keeps the direct head cheap (128 multiply-adds a sample)
/// while the FFT work, done once per 128 samples, stays small.
#define PART 128

/// FFT size. Overlap-save needs twice the partition: a partition of the IR
/// convolved with a block of input is 2·PART - 1 samples long.
#define FFT_N (2 * PART)

/// Spectrum bins kept. The input and the IR are real, so their spectra are
/// mirror images around the middle and only the lower half (plus the middle
/// bin) needs multiplying.
#define BINS (FFT_N / 2 + 1)

struct gf_convolver {
    int len;              ///< IR length in taps.
    int parts;            ///< FFT partitions after the head (0 for a short IR).

    /// The head (taps 0..PART-1), stored reversed so the direct sum walks
    /// the input history forwards.
    float head_rev[PART];

    /// Input history: the previous block in [0, PART), the block being
    /// filled in [PART, 2·PART).
    float win[FFT_N];
    int pos;              ///< Samples received in the current block.

    /// The FFT partitions' contribution to the block being output, computed
    /// at the end of the previous block.
    float tail[PART];

    // Spectra, [parts][BINS] each, split into real and imaginary arrays so
    // the multiply-accumulate loops vectorise.
    float* h_re;          ///< IR partition k at row k-1.
    float* h_im;
    float* x_re;          ///< Ring of the last [parts] input spectra.
    float* x_im;
    int newest;           ///< Ring row of the most recent input spectrum.

    gf_fft fft;
    float frame[2 * FFT_N];   ///< FFT scratch, interleaved re/im.
    float acc_re[BINS], acc_im[BINS];
};

// ── FFT helpers ──────────────────────────────────────────────────────────────

/// Forward FFT of [n] real samples, zero-padded to the FFT size, into the
/// interleaved frame.
static void fft_real(gf_convolver* c, const float* x, int n) {
    memset(c->frame, 0, sizeof(c->frame));
    for (int i = 0; i < n; ++i) c->frame[2 * i] = x[i];
    gf_fft_execute(&c->fft, c->frame, 0);
}

/// Copies the lower half of the frame's spectrum into a spectrum row.
static void frame_to_row(const gf_convolver* c, float* re, float* im) {
    for (int b = 0; b < BINS; ++b) {
        re[b] = c->frame[2 * b];
        im[b] = c->frame[2 * b + 1];
    }
}

// ── Construction ─────────────────────────────────────────────────────────────

/// Stores the spectrum of IR partition [k] (k >= 1) in row k-1.
static void store_partition(gf_convolver* c, const float* ir, int k) {
    const int start = k * PART;
    const int n = (c->len - start < PART) ? c->len - start : PART;
    // Zero-padded to the FFT size: the padding is what lets overlap-save
    // read a clean linear convolution out of a circular one.
    fft_real(c, ir + start, n);
    frame_to_row(c, c->h_re + (size_t)(k - 1) * BINS,
                 c->h_im + (size_t)(k - 1) * BINS);
}

gf_convolver* gf_convolver_create(const float* ir, int len) {
    if (!ir || len < 1) return NULL;
    gf_convolver* c = (gf_convolver*)calloc(1, sizeof(gf_convolver));
    if (!c) return NULL;
    c->len = len;
    c->parts = (len + PART - 1) / PART - 1;
    if (!gf_fft_init(&c->fft, FFT_N)) {
        gf_convolver_destroy(c);
        return NULL;
    }
    for (int k = 0; k < PART && k < len; ++k) c->head_rev[PART - 1 - k] = ir[k];
    if (c->parts > 0) {
        const size_t n = (size_t)c->parts * BINS;
        c->h_re = (float*)calloc(n, sizeof(float));
        c->h_im = (float*)calloc(n, sizeof(float));
        c->x_re = (float*)calloc(n, sizeof(float));
        c->x_im = (float*)calloc(n, sizeof(float));
        if (!c->h_re || !c->h_im || !c->x_re || !c->x_im) {
            gf_convolver_destroy(c);
            return NULL;
        }
        for (int k = 1; k <= c->parts; ++k) store_partition(c, ir, k);
    }
    return c;
}

void gf_convolver_destroy(gf_convolver* c) {
    if (!c) return;
    gf_fft_free(&c->fft);
    free(c->h_re);
    free(c->h_im);
    free(c->x_re);
    free(c->x_im);
    free(c);
}

void gf_convolver_reset(gf_convolver* c) {
    if (!c) return;
    memset(c->win, 0, sizeof(c->win));
    memset(c->tail, 0, sizeof(c->tail));
    c->pos = 0;
    c->newest = 0;
    if (c->parts > 0) {
        const size_t n = (size_t)c->parts * BINS * sizeof(float);
        memset(c->x_re, 0, n);
        memset(c->x_im, 0, n);
    }
}

int gf_convolver_length(const gf_convolver* c) { return c ? c->len : 0; }

// ── Processing ───────────────────────────────────────────────────────────────

/// Sums every partition against the input spectrum it lines up with:
/// partition k meets the input from k-1 blocks ago.
static void accumulate(gf_convolver* c) {
    memset(c->acc_re, 0, sizeof(c->acc_re));
    memset(c->acc_im, 0, sizeof(c->acc_im));
    for (int k = 1; k <= c->parts; ++k) {
        int row = c->newest - (k - 1);
        if (row < 0) row += c->parts;
        const float* hr = c->h_re + (size_t)(k - 1) * BINS;
        const float* hi = c->h_im + (size_t)(k - 1) * BINS;
        const float* xr = c->x_re + (size_t)row * BINS;
        const float* xi = c->x_im + (size_t)row * BINS;
        // Complex multiply-accumulate: multiplying spectra is convolving
        // the signals.
        for (int b = 0; b < BINS; ++b) {
            c->acc_re[b] += hr[b] * xr[b] - hi[b] * xi[b];
            c->acc_im[b] += hr[b] * xi[b] + hi[b] * xr[b];
        }
    }
}

/// End of an input block: work out what the FFT partitions add to the next
/// output block, then slide the history along.
static void finish_block(gf_convolver* c) {
    if (c->parts > 0) {
        // Spectrum of the last two blocks of input, into the ring.
        fft_real(c, c->win, FFT_N);
        c->newest = (c->newest + 1) % c->parts;
        frame_to_row(c, c->x_re + (size_t)c->newest * BINS,
                     c->x_im + (size_t)c->newest * BINS);

        accumulate(c);
        // Rebuild the full spectrum from its lower half (mirror image,
        // conjugated) and transform back.
        float* f = c->frame;
        for (int b = 0; b < BINS; ++b) {
            f[2 * b] = c->acc_re[b];
            f[2 * b + 1] = c->acc_im[b];
        }
        for (int b = 1; b < FFT_N / 2; ++b) {
            f[2 * (FFT_N - b)] = c->acc_re[b];
            f[2 * (FFT_N - b) + 1] = -c->acc_im[b];
        }
        gf_fft_execute(&c->fft, f, 1);
        // Overlap-save: only the second half is the true linear convolution;
        // the first half is wrapped-around garbage and is dropped.
        for (int i = 0; i < PART; ++i) c->tail[i] = f[2 * (PART + i)];
    }
    memmove(c->win, c->win + PART, PART * sizeof(float));
    c->pos = 0;
}

/// The head, summed directly over the last PART inputs.
static float head_sum(const gf_convolver* c) {
    // win[pos + 1 + j] lines up with head_rev[j]: the newest input
    // (win[PART + pos]) meets tap 0, the oldest meets tap PART-1.
    const float* w = c->win + c->pos + 1;
    float y = 0.0f;
    for (int j = 0; j < PART; ++j) y += c->head_rev[j] * w[j];
    return y;
}

void gf_convolver_process(gf_convolver* c, const float* in, float* out, int n) {
    if (!c || !in || !out) return;
    for (int i = 0; i < n; ++i) {
        c->win[PART + c->pos] = in[i];
        const float y = head_sum(c) + c->tail[c->pos];
        out[i] = y;
        if (++c->pos == PART) finish_block(c);
    }
}
