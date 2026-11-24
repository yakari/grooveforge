// gf_limiter_smoke_test.c - Checks the master-bus output limiter.
//
// 1. A signal under the ceiling passes through bit for bit.
// 2. Nothing ever leaves the ceiling, whatever the overload.
// 3. A sustained, overloaded low note comes out undistorted once the
//    limiter has settled (and much cleaner than the previous design, whose
//    gain wobbled between crests).
// 4. The gain returns to unity after a loud burst.
// 5. A NaN silences one block, and the next block plays normally.
// 6. Interleaved and planar variants agree exactly.
#include "gf_limiter.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#define SR 48000
#define PI 3.14159265358979323846

static int failures = 0;

static void check(int ok, const char* what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok) failures++;
}

/// The limiter that shipped before gf_limiter: instant attack, 50 ms release
/// and no hold. Kept here only to show what the hold buys.
static void old_limiter(float* x, int n, float* gain) {
    const float thr = 0.95f;
    const float rel = 1.0f - 1.0f / (0.050f * SR);
    float g = *gain;
    for (int i = 0; i < n; ++i) {
        const float p = fabsf(x[i]);
        if (p * g > thr) g = thr / p;
        else { g = g * rel + (1.0f - rel); if (g > 1.0f) g = 1.0f; }
        x[i] *= g;
    }
    *gain = g;
}

/// Total harmonic distortion of [x] (a [f0] Hz tone, [n] samples), in dB:
/// the energy left after removing the best-fit fundamental, relative to it.
static double thd_db(const float* x, int n, double f0) {
    double c = 0, s = 0;
    for (int i = 0; i < n; ++i) {
        c += x[i] * cos(2 * PI * f0 * i / SR);
        s += x[i] * sin(2 * PI * f0 * i / SR);
    }
    c *= 2.0 / n; s *= 2.0 / n;
    double fund = 0, rest = 0;
    for (int i = 0; i < n; ++i) {
        const double f = c * cos(2 * PI * f0 * i / SR) + s * sin(2 * PI * f0 * i / SR);
        fund += f * f;
        rest += (x[i] - f) * (x[i] - f);
    }
    return 10 * log10(rest / fund);
}

/// Feeds [x] through the limiter in 64-frame blocks, mono on both sides.
static void run(gf_limiter* lim, float* x, int n) {
    float r[64];
    for (int p = 0; p < n; p += 64) {
        const int k = n - p < 64 ? n - p : 64;
        for (int i = 0; i < k; ++i) r[i] = x[p + i];
        gf_limiter_process(lim, x + p, r, k);
    }
}

int main(void) {
    gf_limiter lim;
    const int n = SR * 2;
    float* x = malloc(sizeof(float) * n);
    float* y = malloc(sizeof(float) * n);

    // 1. Transparent below the ceiling.
    gf_limiter_init(&lim, SR);
    int same = 1;
    for (int i = 0; i < n; ++i) x[i] = y[i] = 0.85f * (float)sin(2 * PI * 220 * i / SR);
    run(&lim, x, n);
    for (int i = 0; i < n; ++i) if (x[i] != y[i]) same = 0;
    check(same, "signal at -1.4 dBFS passes bit-exact");

    // 2. Ceiling holds against noise bursts up to +40 dB.
    gf_limiter_init(&lim, SR);
    srand(7);
    float worst = 0;
    for (int b = 0; b < 200; ++b) {
        const float amp = powf(10.0f, ((float)(rand() % 41)) / 20.0f);
        for (int i = 0; i < 960; ++i) x[i] = amp * ((float)rand() / RAND_MAX * 2 - 1);
        run(&lim, x, 960);
        for (int i = 0; i < 960; ++i) if (fabsf(x[i]) > worst) worst = fabsf(x[i]);
    }
    printf("     worst output %.6f (ceiling %.6f)\n", worst, GF_LIMITER_THRESHOLD);
    check(worst <= GF_LIMITER_THRESHOLD * 1.000001f, "no sample above the ceiling");

    // 3. A 41 Hz low E (41.0 Hz, a whole number of cycles per second so the fit is exact) at +12 dB over full scale, held for 2 s.
    gf_limiter_init(&lim, SR);
    for (int i = 0; i < n; ++i) x[i] = y[i] = 4.0f * (float)sin(2 * PI * 41.0 * i / SR);
    run(&lim, x, n);
    float og = 1.0f;
    for (int p = 0; p < n; p += 64) old_limiter(y + p, 64, &og);
    const double t_new = thd_db(x + SR, SR, 41.0);
    const double t_old = thd_db(y + SR, SR, 41.0);
    printf("     THD after settling: new %.1f dB, old %.1f dB\n", t_new, t_old);
    check(t_new < -60.0, "sustained overload is not distorted (THD < -60 dB)");
    check(t_new < t_old - 20.0, "at least 20 dB cleaner than the previous limiter");

    // 4. Recovery: a 100 ms burst at +20 dB, then a quiet tone.
    gf_limiter_init(&lim, SR);
    for (int i = 0; i < n; ++i) {
        const float a = i < SR / 10 ? 10.0f : 0.1f;
        x[i] = a * (float)sin(2 * PI * 440 * i / SR);
    }
    run(&lim, x, n);
    printf("     gain 1.9 s after the burst: %.4f\n", lim.gain);
    check(lim.gain > 0.99f, "gain back to unity within 2 s");

    // 5. NaN in one block.
    gf_limiter_init(&lim, SR);
    float l[64], r[64];
    for (int i = 0; i < 64; ++i) l[i] = r[i] = 0.5f;
    l[10] = NAN;
    gf_limiter_process(&lim, l, r, 64);
    int silent = 1;
    for (int i = 0; i < 64; ++i) if (l[i] != 0 || r[i] != 0) silent = 0;
    for (int i = 0; i < 64; ++i) l[i] = r[i] = 0.5f;
    gf_limiter_process(&lim, l, r, 64);
    check(silent && l[0] == 0.5f && isfinite(lim.gain), "NaN block silenced, next one plays");

    // 6. Interleaved variant matches the planar one.
    gf_limiter a, b;
    gf_limiter_init(&a, SR);
    gf_limiter_init(&b, SR);
    int match = 1;
    for (int blk = 0; blk < 100; ++blk) {
        float pl[64], pr[64], il[64], ir[64], out[128];
        for (int i = 0; i < 64; ++i) {
            pl[i] = il[i] = 3.0f * (float)sin(0.01 * (blk * 64 + i));
            pr[i] = ir[i] = 2.0f * (float)cos(0.013 * (blk * 64 + i));
        }
        gf_limiter_process(&a, pl, pr, 64);
        gf_limiter_process_interleave(&b, il, ir, out, 64);
        for (int i = 0; i < 64; ++i)
            if (out[2 * i] != pl[i] || out[2 * i + 1] != pr[i]) match = 0;
    }
    check(match, "interleaved output identical to planar");

    free(x);
    free(y);
    printf(failures ? "\n%d FAILED\n" : "\nALL PASS\n", failures);
    return failures ? 1 : 0;
}
