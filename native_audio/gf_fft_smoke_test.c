// gf_fft_smoke_test.c — Offline smoke test for the shared radix-2 FFT.
//
// The FFT spent its life inside gf_phase_vocoder.c, where it was only ever
// exercised through the vocoder: a transform bug and a phase-locking bug look
// the same from the outside. Now that other effects share it, it needs checks
// that fail for one reason only.
//
// Six checks, each pinning a property something downstream relies on:
//
//   1. ROUND TRIP — forward then inverse returns the original samples. This is
//      the normalisation check: the 1/n belongs on exactly one of the two
//      directions, and getting it wrong is a silent gain error, not a crash.
//
//   2. KNOWN SPECTRA — an impulse transforms to a flat spectrum, and a
//      sinusoid at an exact bin centre transforms to that one bin and nothing
//      else. Catches a botched bit-reversal, which round-tripping alone would
//      hide because the two directions cancel.
//
//   2b. SIGN CONVENTION — a one-sample-delayed impulse must give bin k a
//      phase of -2*pi*k/n, i.e. the forward transform uses exp(-j...). None of
//      the other checks can see this: negating the twiddles merely swaps the
//      forward and inverse conventions, which cancels on a round trip and is
//      invisible in the magnitude spectrum of a real signal. It still matters,
//      because it sets which way round a cross-correlation reports a delay —
//      get it wrong and an echo canceller looks for the echo before the sound.
//
//   3. LINEARITY — the transform of a sum equals the sum of the transforms.
//
//   4. CONVOLUTION THEOREM — multiplying two spectra equals circularly
//      convolving the two signals. This is the property an echo canceller
//      rests on: it is how a filter gets applied to a whole block at once
//      instead of sample by sample, and how a delay is found by correlation.
//
//   5. SIZES — every power of two the callers use, from the vocoder's
//      smallest to its largest, transforms correctly.
//
// Build: see CMakeLists.txt — target "gf_fft_smoke_test".
// Run  : ./build/gf_fft_smoke_test

#include "gf_fft.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/// Tolerance for a float round trip through a few thousand butterflies.
/// Generous enough to absorb ordinary rounding, tight enough that a sign
/// error or a missing normalisation cannot slip through.
#define EPS 1e-4f

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Fills [data] with a complex signal whose real parts are pseudo-random and
/// whose imaginary parts are zero, the shape every caller actually feeds in.
///
/// Deliberately a fixed sequence rather than rand(): a failure must reproduce.
static void fill_real_noise(float* data, int n, unsigned seed) {
    unsigned s = seed;
    for (int i = 0; i < n; i++) {
        s = s * 1664525u + 1013904223u;          // Numerical Recipes LCG
        data[2*i]     = (float)((int)(s >> 16) % 2000 - 1000) / 1000.0f;
        data[2*i + 1] = 0.0f;
    }
}

/// Largest absolute difference between two complex arrays of length [n].
static float max_diff(const float* a, const float* b, int n) {
    float worst = 0.0f;
    for (int i = 0; i < 2 * n; i++) {
        const float d = fabsf(a[i] - b[i]);
        if (d > worst) worst = d;
    }
    return worst;
}

/// Magnitude of bin [k].
static float mag(const float* data, int k) {
    return sqrtf(data[2*k] * data[2*k] + data[2*k + 1] * data[2*k + 1]);
}

// ── 1. Round trip ────────────────────────────────────────────────────────────

static int test_round_trip(void) {
    const int n = 1024;
    printf("1. forward then inverse returns the original\n");

    gf_fft f;
    if (!gf_fft_init(&f, n)) { printf("   FAIL — init\n"); return 0; }

    float* work = (float*)malloc(sizeof(float) * 2 * n);
    float* orig = (float*)malloc(sizeof(float) * 2 * n);
    fill_real_noise(work, n, 12345u);
    memcpy(orig, work, sizeof(float) * 2 * n);

    gf_fft_execute(&f, work, 0);
    gf_fft_execute(&f, work, 1);

    const float worst = max_diff(work, orig, n);
    const int ok = worst < EPS;
    printf("      worst sample error %.3g%s\n", (double)worst,
           ok ? "" : "  (normalisation or twiddle sign)");
    printf(ok ? "   PASS\n" : "   FAIL\n");

    free(work); free(orig); gf_fft_free(&f);
    return ok;
}

// ── 2. Known spectra ─────────────────────────────────────────────────────────

static int test_known_spectra(void) {
    const int n = 256;
    printf("2. impulse is flat, bin-centred sinusoid is one bin\n");

    gf_fft f;
    if (!gf_fft_init(&f, n)) { printf("   FAIL — init\n"); return 0; }
    float* work = (float*)malloc(sizeof(float) * 2 * n);
    int ok = 1;

    // An impulse at sample 0 contains every frequency in equal measure, so
    // every bin must come back with magnitude 1.
    memset(work, 0, sizeof(float) * 2 * n);
    work[0] = 1.0f;
    gf_fft_execute(&f, work, 0);
    float worst_flat = 0.0f;
    for (int k = 0; k < n; k++) {
        const float d = fabsf(mag(work, k) - 1.0f);
        if (d > worst_flat) worst_flat = d;
    }
    if (worst_flat > EPS) ok = 0;
    printf("      impulse: worst bin deviation from flat %.3g\n", (double)worst_flat);

    // A cosine sitting exactly on bin 8 must put all its energy in bins 8 and
    // n-8 (the negative-frequency mirror of a real signal) and nowhere else.
    const int bin = 8;
    for (int i = 0; i < n; i++) {
        work[2*i]     = cosf(2.0f * (float)M_PI * (float)bin * (float)i / (float)n);
        work[2*i + 1] = 0.0f;
    }
    gf_fft_execute(&f, work, 0);
    const float on  = mag(work, bin);
    const float mir = mag(work, n - bin);
    float leak = 0.0f;
    for (int k = 0; k < n; k++) {
        if (k == bin || k == n - bin) continue;
        if (mag(work, k) > leak) leak = mag(work, k);
    }
    // Each half carries n/2 of the energy for a unit-amplitude cosine.
    if (fabsf(on - (float)n / 2.0f) > 0.01f * (float)n) ok = 0;
    if (fabsf(mir - (float)n / 2.0f) > 0.01f * (float)n) ok = 0;
    if (leak > 0.001f * (float)n) ok = 0;
    printf("      cosine on bin %d: |X(%d)|=%.1f mirror=%.1f worst leak=%.3g\n",
           bin, bin, (double)on, (double)mir, (double)leak);

    printf(ok ? "   PASS\n" : "   FAIL\n");
    free(work); gf_fft_free(&f);
    return ok;
}

// ── 2b. Sign convention ──────────────────────────────────────────────────────

static int test_sign_convention(void) {
    const int n = 256;
    printf("2b. forward transform uses exp(-j...), not exp(+j...)\n");

    gf_fft f;
    if (!gf_fft_init(&f, n)) { printf("   FAIL — init\n"); return 0; }
    float* work = (float*)malloc(sizeof(float) * 2 * n);

    // An impulse delayed by one sample has X[k] = exp(-j*2*pi*k/n), so bin k
    // must come back with a NEGATIVE imaginary part for small k. Negated
    // twiddles would give the conjugate — same magnitudes, mirrored phase.
    memset(work, 0, sizeof(float) * 2 * n);
    work[2 * 1] = 1.0f;                       // delta at sample 1
    gf_fft_execute(&f, work, 0);

    const int k = 1;
    const float want_re = cosf(2.0f * (float)M_PI * (float)k / (float)n);
    const float want_im = -sinf(2.0f * (float)M_PI * (float)k / (float)n);
    const float got_re = work[2*k];
    const float got_im = work[2*k + 1];

    const int ok = fabsf(got_re - want_re) < EPS
                && fabsf(got_im - want_im) < EPS;
    printf("      bin %d: want (%+.4f, %+.4f)  got (%+.4f, %+.4f)\n",
           k, (double)want_re, (double)want_im, (double)got_re, (double)got_im);
    if (!ok && fabsf(got_im + want_im) < EPS) {
        printf("      phase is mirrored — twiddle sign is flipped\n");
    }
    printf(ok ? "   PASS\n" : "   FAIL\n");

    free(work); gf_fft_free(&f);
    return ok;
}

// ── 3. Linearity ─────────────────────────────────────────────────────────────

static int test_linearity(void) {
    const int n = 512;
    printf("3. transform of a sum is the sum of the transforms\n");

    gf_fft f;
    if (!gf_fft_init(&f, n)) { printf("   FAIL — init\n"); return 0; }

    float* a   = (float*)malloc(sizeof(float) * 2 * n);
    float* b   = (float*)malloc(sizeof(float) * 2 * n);
    float* sum = (float*)malloc(sizeof(float) * 2 * n);
    fill_real_noise(a, n, 777u);
    fill_real_noise(b, n, 31337u);
    for (int i = 0; i < 2 * n; i++) sum[i] = a[i] + b[i];

    gf_fft_execute(&f, a, 0);
    gf_fft_execute(&f, b, 0);
    gf_fft_execute(&f, sum, 0);

    float worst = 0.0f;
    for (int i = 0; i < 2 * n; i++) {
        const float d = fabsf(sum[i] - (a[i] + b[i]));
        if (d > worst) worst = d;
    }
    // Scaled against n because spectral magnitudes grow with the transform size.
    const int ok = worst < EPS * (float)n;
    printf("      worst deviation %.3g\n", (double)worst);
    printf(ok ? "   PASS\n" : "   FAIL\n");

    free(a); free(b); free(sum); gf_fft_free(&f);
    return ok;
}

// ── 4. Convolution theorem ───────────────────────────────────────────────────

/// Circular convolution computed the slow, obviously-correct way, so the fast
/// spectral route has something independent to be checked against.
static void naive_circular_convolve(const float* x, const float* h,
                                    float* out, int n) {
    for (int i = 0; i < n; i++) {
        float acc = 0.0f;
        for (int j = 0; j < n; j++) {
            acc += x[j] * h[(i - j + n) % n];
        }
        out[i] = acc;
    }
}

static int test_convolution(void) {
    const int n = 128;
    printf("4. multiplying spectra equals convolving signals\n");

    gf_fft f;
    if (!gf_fft_init(&f, n)) { printf("   FAIL — init\n"); return 0; }

    float* xr = (float*)malloc(sizeof(float) * n);
    float* hr = (float*)malloc(sizeof(float) * n);
    float* expected = (float*)malloc(sizeof(float) * n);
    float* X = (float*)malloc(sizeof(float) * 2 * n);
    float* H = (float*)malloc(sizeof(float) * 2 * n);

    // A short decaying tail standing in for a room impulse response, and a
    // noise burst standing in for the signal that goes through it.
    unsigned s = 4242u;
    for (int i = 0; i < n; i++) {
        s = s * 1664525u + 1013904223u;
        xr[i] = (float)((int)(s >> 16) % 2000 - 1000) / 1000.0f;
        hr[i] = (i < 16) ? expf(-(float)i / 5.0f) : 0.0f;
    }
    naive_circular_convolve(xr, hr, expected, n);

    for (int i = 0; i < n; i++) {
        X[2*i] = xr[i]; X[2*i + 1] = 0.0f;
        H[2*i] = hr[i]; H[2*i + 1] = 0.0f;
    }
    gf_fft_execute(&f, X, 0);
    gf_fft_execute(&f, H, 0);

    // Complex multiply bin by bin, then come back to the time domain.
    for (int k = 0; k < n; k++) {
        const float ar = X[2*k], ai = X[2*k + 1];
        const float br = H[2*k], bi = H[2*k + 1];
        X[2*k]     = ar * br - ai * bi;
        X[2*k + 1] = ar * bi + ai * br;
    }
    gf_fft_execute(&f, X, 1);

    float worst = 0.0f;
    for (int i = 0; i < n; i++) {
        const float d = fabsf(X[2*i] - expected[i]);
        if (d > worst) worst = d;
    }
    const int ok = worst < 1e-3f;
    printf("      worst deviation from the slow convolution %.3g\n", (double)worst);
    printf(ok ? "   PASS\n" : "   FAIL\n");

    free(xr); free(hr); free(expected); free(X); free(H);
    gf_fft_free(&f);
    return ok;
}

// ── 5. Every size the callers use ────────────────────────────────────────────

static int test_sizes(void) {
    printf("5. round trip holds at every size in use\n");
    int ok = 1;
    for (int n = 256; n <= 8192; n <<= 1) {
        gf_fft f;
        if (!gf_fft_init(&f, n)) { printf("      n=%d FAIL — init\n", n); ok = 0; continue; }

        float* work = (float*)malloc(sizeof(float) * 2 * n);
        float* orig = (float*)malloc(sizeof(float) * 2 * n);
        fill_real_noise(work, n, (unsigned)n * 7919u);
        memcpy(orig, work, sizeof(float) * 2 * n);

        gf_fft_execute(&f, work, 0);
        gf_fft_execute(&f, work, 1);
        const float worst = max_diff(work, orig, n);
        if (worst >= EPS) ok = 0;
        printf("      n=%-5d worst %.3g%s\n", n, (double)worst,
               worst < EPS ? "" : "   <-- FAIL");

        free(work); free(orig); gf_fft_free(&f);
    }
    printf(ok ? "   PASS\n" : "   FAIL\n");
    return ok;
}

// ── Entry point ──────────────────────────────────────────────────────────────

int main(void) {
    printf("gf_fft_smoke_test\n\n");

    int ok = 1;
    ok &= test_round_trip();
    ok &= test_known_spectra();
    ok &= test_sign_convention();
    ok &= test_linearity();
    ok &= test_convolution();
    ok &= test_sizes();

    printf(ok ? "\nALL TESTS PASSED\n" : "\nTESTS FAILED\n");
    return ok ? 0 : 1;
}
