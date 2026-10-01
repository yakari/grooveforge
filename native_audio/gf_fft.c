// gf_fft.c — Implementation of the shared radix-2 complex FFT.
// See gf_fft.h for the public API and the rationale behind the design.

#include "gf_fft.h"

#include <math.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int gf_fft_init(gf_fft* f, int n) {
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

void gf_fft_free(gf_fft* f) {
    free(f->twiddle_cos);
    free(f->twiddle_sin);
    free(f->bitrev);
    f->twiddle_cos = NULL;
    f->twiddle_sin = NULL;
    f->bitrev      = NULL;
}

// In-place complex FFT (or IFFT if [inverse] is nonzero).
// [data] is interleaved real/imag, length 2*n floats.
void gf_fft_execute(const gf_fft* f, float* data, int inverse) {
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
