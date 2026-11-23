// gf_convolver_smoke_test.c — Offline checks for cabinet impulse responses.
//
// What it guards:
//
//   1. **The convolver is exact.** Its output is compared with a direct
//      double-precision sum over every tap, for IR lengths on both sides of
//      each partition boundary and for random, ragged block sizes — the case
//      where a bookkeeping slip in the partition ring would hide.
//   2. **It adds no latency**: an impulse in gives the IR out from sample 0.
//   3. **Preparing an IR** drops the silence before the attack, caps its
//      length, and rejects files with nothing in them.
//   4. **Level matching**: an IR measured from the built-in 2x12 cabinet and
//      saved 20 dB too loud plays back at the 2x12's level, including after
//      a resample from 96 kHz.
//   5. **Swaps are clean**: loading a new IR while one plays, or switching
//      between the built-in cabinet and the IR, never clicks, and the old IR
//      is handed back to be freed.
//   6. **Cost and rate changes.**
//
// Build: see CMakeLists.txt — target "gf_convolver_smoke_test".
// Run  : ./scripts/run_smoke_tests.sh convolver

#include "gf_amp.h"
#include "gf_convolver.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define SR 48000

static int g_failures = 0;

static void report(const char* name, int ok, const char* detail) {
    printf("   %-58s %s\n", name, ok ? "PASS" : "FAIL");
    if (detail && detail[0]) printf("      %s\n", detail);
    if (!ok) g_failures++;
}

static float frand(void) { return 2.0f * rand() / (float)RAND_MAX - 1.0f; }

static void sine(float* buf, int n, double hz, double amp, double rate) {
    for (int i = 0; i < n; ++i) buf[i] = (float)(amp * sin(2 * M_PI * hz * i / rate));
}

static double rms(const float* x, int n) {
    double s = 0;
    for (int i = 0; i < n; ++i) s += (double)x[i] * x[i];
    return sqrt(s / n);
}

// ── 1-2. The convolver ──────────────────────────────────────────────────────

/// Largest error of the convolver against a direct sum, relative to the
/// output's peak, with blocks of random size.
static double convolver_error(int len) {
    const int n = 6000;
    float* ir = malloc(sizeof(float) * len);
    float* in = malloc(sizeof(float) * n);
    float* out = malloc(sizeof(float) * n);
    for (int i = 0; i < len; ++i) ir[i] = frand() * expf(-3.0f * i / len);
    for (int i = 0; i < n; ++i) in[i] = frand();
    gf_convolver* c = gf_convolver_create(ir, len);
    for (int done = 0; done < n;) {
        int blk = 1 + rand() % 300;
        if (blk > n - done) blk = n - done;
        gf_convolver_process(c, in + done, out + done, blk);
        done += blk;
    }
    double worst = 0, peak = 0;
    for (int i = 0; i < n; ++i) {
        double ref = 0;
        for (int k = 0; k < len && k <= i; ++k) ref += (double)ir[k] * in[i - k];
        if (fabs(ref) > peak) peak = fabs(ref);
        if (fabs(ref - out[i]) > worst) worst = fabs(ref - out[i]);
    }
    gf_convolver_destroy(c);
    free(ir);
    free(in);
    free(out);
    return worst / peak;
}

static void test_convolver(void) {
    printf("\n1. Exact convolution\n");
    static const int lens[] = {1, 77, 127, 128, 129, 255, 256, 257, 1000, 4800};
    double worst = 0;
    int worst_len = 0;
    for (size_t i = 0; i < sizeof lens / sizeof lens[0]; ++i) {
        const double e = convolver_error(lens[i]);
        if (e > worst) { worst = e; worst_len = lens[i]; }
    }
    char d[128];
    snprintf(d, sizeof d, "worst error %.2e of the peak (IR of %d taps)", worst, worst_len);
    report("matches a direct sum for every length and block size", worst < 1e-5, d);

    printf("\n2. Latency\n");
    float ir[500], in[600] = {0}, out[600];
    for (int i = 0; i < 500; ++i) ir[i] = frand();
    in[0] = 1.0f;
    gf_convolver* c = gf_convolver_create(ir, 500);
    gf_convolver_process(c, in, out, 600);
    double e = 0;
    for (int i = 0; i < 500; ++i) e = fmax(e, fabs(out[i] - ir[i]));
    snprintf(d, sizeof d, "out[0] = %.4f for ir[0] = %.4f, worst %.1e", out[0], ir[0], e);
    report("an impulse in gives the IR out from the first sample", e < 1e-5, d);

    for (int i = 0; i < 600; ++i) in[i] = frand();
    gf_convolver_process(c, in, out, 600);
    gf_convolver_reset(c);
    memset(in, 0, sizeof in);
    gf_convolver_process(c, in, out, 600);
    report("reset forgets everything heard before", rms(out, 600) == 0.0, "");
    gf_convolver_destroy(c);
    report("refuses an empty IR", gf_convolver_create(ir, 0) == NULL, "");
}

// ── Helpers: the amp's own cabinets, measured as IRs ────────────────────────

/// An amp with only the cabinet on, set to [cab].
static gf_amp* cab_amp(int cab, double rate) {
    gf_amp* a = gf_amp_create((float)rate);
    gf_amp_params p;
    gf_amp_default_params(&p);
    p.drive_on = 0;
    p.amp_on = 0;
    p.cab_on = 1;
    p.cab_type = cab;
    gf_amp_set_params(a, &p);
    gf_amp_reset(a);
    return a;
}

/// The built-in cabinet [cab]'s impulse response at [rate], scaled by
/// [gain]: what someone recording that cabinet would have saved.
static float* measure_cab(int cab, double rate, float gain, int* len) {
    const int n = (int)(0.1 * rate);
    float* x = calloc((size_t)n, sizeof(float));
    x[0] = 1.0f;
    gf_amp* a = cab_amp(cab, rate);
    gf_amp_process(a, x, x, n);
    gf_amp_destroy(a);
    for (int i = 0; i < n; ++i) x[i] *= gain;
    *len = n;
    return x;
}

/// Level in dB of a [hz] sine through [a], after it settles.
static double sine_level_db(gf_amp* a, double hz) {
    const int n = SR / 2;
    float* in = malloc(sizeof(float) * n);
    float* out = malloc(sizeof(float) * n);
    sine(in, n, hz, 0.1, SR);
    gf_amp_process(a, in, out, n);
    const double db = 20 * log10(rms(out + n / 2, n / 2) / rms(in + n / 2, n / 2));
    free(in);
    free(out);
    return db;
}

// ── 3. Preparation ──────────────────────────────────────────────────────────

static void test_preparation(void) {
    printf("\n3. Preparing an IR\n");
    float* x = calloc(SR, sizeof(float));
    report("rejects a silent IR", gf_amp_ir_create(x, SR, SR, 0) == NULL, "");
    report("rejects an unusable rate", gf_amp_ir_create(x, SR, 1000, 0) == NULL, "");

    x[700] = 1.0f;  // a click after 700 samples of silence
    gf_amp_ir* ir = gf_amp_ir_create(x, SR, SR, 0);
    char d[128];
    snprintf(d, sizeof d, "%d taps kept", gf_amp_ir_length(ir, SR));
    report("drops the silence before the attack", ir && gf_amp_ir_length(ir, SR) == 1, d);
    gf_amp_ir_destroy(ir);

    // A full second of slowly decaying noise: a room, not a cabinet.
    for (int i = 0; i < SR; ++i) x[i] = frand() * expf(-1.0f * i / SR);
    ir = gf_amp_ir_create(x, SR, SR, 0);
    const int cap = (int)ceil(GF_AMP_IR_MAX_SEC * SR);
    snprintf(d, sizeof d, "%d taps kept, cap %d", gf_amp_ir_length(ir, SR), cap);
    report("cuts a long IR at the cap", ir && gf_amp_ir_length(ir, SR) == cap, d);
    const int l44 = gf_amp_ir_length(ir, 44100);
    snprintf(d, sizeof d, "%d taps at 44.1 kHz", l44);
    report("prepares a resampled version for 44.1 kHz", abs(l44 - 4410) < 4, d);
    gf_amp_ir_destroy(ir);

    x[0] = NAN;
    ir = gf_amp_ir_create(x, SR, SR, 0);
    report("survives a corrupt sample", ir != NULL, "");
    gf_amp_ir_destroy(ir);
    free(x);
}

// ── 4. Level matching ───────────────────────────────────────────────────────

/// An amp playing the IR made from [x] (recorded at [rate]) as its cabinet.
/// The amp owns the IR.
static gf_amp* ir_amp(const float* x, int n, double rate) {
    gf_amp* a = cab_amp(GF_AMP_CAB_IR, SR);
    gf_amp_set_ir(a, gf_amp_ir_create(x, n, rate, 0));
    gf_amp_params p;
    gf_amp_default_params(&p);
    p.drive_on = p.amp_on = 0;
    p.cab_type = GF_AMP_CAB_IR;
    gf_amp_set_params(a, &p);
    gf_amp_reset(a);
    return a;
}

/// Largest level difference, in dB, between the IR made from [x] and the
/// built-in 2x12, over a guitar's range.
static double worst_band_diff(const float* x, int n, double rate) {
    static const double hz[] = {150, 400, 1000, 2500};
    double worst = 0;
    for (int i = 0; i < 4; ++i) {
        gf_amp* ref = cab_amp(GF_AMP_CAB_2X12, SR);
        gf_amp* a = ir_amp(x, n, rate);
        const double d = fabs(sine_level_db(a, hz[i]) - sine_level_db(ref, hz[i]));
        if (d > worst) worst = d;
        gf_amp_destroy(ref);
        gf_amp_destroy(a);
    }
    return worst;
}

static void test_level(void) {
    printf("\n4. Level matching\n");
    int n = 0;
    float* x = measure_cab(GF_AMP_CAB_2X12, SR, 10.0f, &n);
    char d[128];
    double w = worst_band_diff(x, n, SR);
    snprintf(d, sizeof d, "worst difference %.2f dB at 150-2500 Hz", w);
    report("the 2x12, measured 20 dB hot, plays at the 2x12's level", w < 0.5, d);
    free(x);

    // Same cabinet recorded at 96 kHz: exercises the resampler.
    x = measure_cab(GF_AMP_CAB_2X12, 96000, 0.05f, &n);
    w = worst_band_diff(x, n, 96000);
    snprintf(d, sizeof d, "worst difference %.2f dB at 150-2500 Hz", w);
    report("same from a 96 kHz recording, resampled", w < 0.5, d);
    free(x);

    gf_amp* a = cab_amp(GF_AMP_CAB_IR, SR);
    gf_amp* ref = cab_amp(GF_AMP_CAB_2X12, SR);
    const double diff = fabs(sine_level_db(a, 1000) - sine_level_db(ref, 1000));
    snprintf(d, sizeof d, "difference %.3f dB", diff);
    report("\"IR\" with no IR loaded is the 2x12", diff < 0.01, d);
    gf_amp_destroy(a);
    gf_amp_destroy(ref);
}

// ── 5. Swaps ────────────────────────────────────────────────────────────────

/// Largest sample-to-sample step in [out] after block [from].
static double worst_step(const float* out, int n) {
    double worst = 0;
    for (int i = 1; i < n; ++i) worst = fmax(worst, fabs(out[i] - out[i - 1]));
    return worst;
}

/// Plays a low sine through [a] in 256-frame blocks, calling [event] at block
/// 40, and returns the largest step around the event relative to the larger
/// of the two steady states, before and after. (The cabinets differ in level
/// at 110 Hz, so the louder one sets what a normal step is.)
static double click_ratio(gf_amp* a, void (*event)(gf_amp*)) {
    const int n = SR, blk = 256;
    float* in = malloc(sizeof(float) * n);
    float* out = malloc(sizeof(float) * n);
    sine(in, n, 110, 0.4, SR);
    for (int b = 0; b < n / blk; ++b) {
        if (b == 40) event(a);
        gf_amp_process(a, in + b * blk, out + b * blk, blk);
    }
    const double steady = fmax(worst_step(out + 20 * blk, 20 * blk),
                               worst_step(out + 120 * blk, 20 * blk));
    const double around = worst_step(out + 38 * blk, 20 * blk);
    free(in);
    free(out);
    return around / steady;
}

static float* g_ir_b;
static int g_ir_b_len;
static int g_swap_taken;

static void swap_to_b(gf_amp* a) {
    g_swap_taken = gf_amp_set_ir(a, gf_amp_ir_create(g_ir_b, g_ir_b_len, SR, 0));
}

static void select_cab(gf_amp* a, int cab) {
    gf_amp_params p;
    gf_amp_default_params(&p);
    p.drive_on = p.amp_on = 0;
    p.cab_type = cab;
    gf_amp_set_params(a, &p);
}

static void select_4x12(gf_amp* a) { select_cab(a, GF_AMP_CAB_4X12); }
static void select_ir(gf_amp* a) { select_cab(a, GF_AMP_CAB_IR); }
static void clear_ir(gf_amp* a) { gf_amp_clear_ir(a); }

/// Removing the IR while it plays: fades out, then hands the IR back, and
/// "IR" is the 2x12 again. A load during the fade cancels the removal.
static void test_removal(const float* ir_a, int na) {
    char d[128];
    gf_amp* a = ir_amp(ir_a, na, SR);
    const double r = click_ratio(a, clear_ir);
    snprintf(d, sizeof d, "largest step %.2fx the steady state", r);
    report("removing the IR while it plays does not click", r < 1.5, d);
    gf_amp_ir* old = gf_amp_take_retired_ir(a);
    report("the removed IR is handed back", old != NULL && !gf_amp_has_ir(a), "");
    gf_amp_ir_destroy(old);
    gf_amp_reset(a);
    gf_amp* ref = cab_amp(GF_AMP_CAB_2X12, SR);
    const double diff = fabs(sine_level_db(a, 1000) - sine_level_db(ref, 1000));
    snprintf(d, sizeof d, "difference %.3f dB", diff);
    report("after removal, \"IR\" is the 2x12 again", diff < 0.01, d);
    gf_amp_destroy(ref);
    gf_amp_clear_ir(a);   // nothing loaded: must be harmless
    gf_amp_destroy(a);

    a = ir_amp(ir_a, na, SR);
    float tmp[256] = {0};
    gf_amp_clear_ir(a);
    gf_amp_process(a, tmp, tmp, 256);
    gf_amp_set_ir(a, gf_amp_ir_create(ir_a, na, SR, 0));
    for (int i = 0; i < 400; ++i) gf_amp_process(a, tmp, tmp, 256);
    gf_amp_ir_destroy(gf_amp_take_retired_ir(a));
    report("a load during the fade-out cancels the removal", gf_amp_has_ir(a), "");
    gf_amp_destroy(a);
}

static void test_swaps(void) {
    printf("\n5. Swaps\n");
    int na = 0;
    float* ir_a = measure_cab(GF_AMP_CAB_1X12, SR, 1.0f, &na);
    g_ir_b = measure_cab(GF_AMP_CAB_4X12, SR, 1.0f, &g_ir_b_len);
    char d[128];

    gf_amp* a = ir_amp(ir_a, na, SR);
    const double r = click_ratio(a, swap_to_b);
    snprintf(d, sizeof d, "largest step %.2fx the steady state", r);
    report("loading a new IR while one plays does not click", g_swap_taken && r < 1.5, d);
    report("the swap keeps the amp busy until the old IR is taken",
           gf_amp_ir_busy(a), "");
    gf_amp_ir* old = gf_amp_take_retired_ir(a);
    report("the old IR is handed back", old != NULL && !gf_amp_ir_busy(a), "");
    gf_amp_ir_destroy(old);

    gf_amp_ir* c = gf_amp_ir_create(ir_a, na, SR, 0);
    report("a new IR is accepted once the old one is taken back",
           gf_amp_set_ir(a, c) == 1, "");
    gf_amp_ir* d2 = gf_amp_ir_create(ir_a, na, SR, 0);
    float tmp[256] = {0};
    gf_amp_process(a, tmp, tmp, 256);
    const int refused = gf_amp_set_ir(a, d2) == 0;
    report("a second IR during the crossfade is refused", refused, "");
    if (refused) gf_amp_ir_destroy(d2);
    gf_amp_destroy(a);

    a = ir_amp(ir_a, na, SR);
    double rc = click_ratio(a, select_4x12);
    snprintf(d, sizeof d, "largest step %.2fx the steady state", rc);
    report("IR to built-in cabinet does not click", rc < 1.5, d);
    rc = click_ratio(a, select_ir);
    snprintf(d, sizeof d, "largest step %.2fx the steady state", rc);
    report("built-in cabinet to IR does not click", rc < 1.5, d);
    gf_amp_destroy(a);
    test_removal(ir_a, na);
    free(ir_a);
    free(g_ir_b);
}

// ── 6. Cost and rate changes ────────────────────────────────────────────────

static void test_cost(void) {
    printf("\n6. Cost and rate changes\n");
    const int n = 10 * SR;
    float* buf = malloc(sizeof(float) * n);
    for (int i = 0; i < n; ++i) buf[i] = frand() * expf(-6.0f * (i % SR) / SR);
    const clock_t t_prep = clock();
    gf_amp_ir* ir = gf_amp_ir_create(buf, SR, SR, 0);
    const double prep = (double)(clock() - t_prep) / CLOCKS_PER_SEC;
    char d[128];
    snprintf(d, sizeof d, "%.0f ms for a 1 s file, 4 rates", prep * 1000);
    report("preparing a long IR is quick", prep < 1.0, d);

    gf_amp* a = cab_amp(GF_AMP_CAB_IR, SR);
    gf_amp_set_ir(a, ir);
    for (int i = 0; i < n; ++i) buf[i] = frand();
    const clock_t t0 = clock();
    gf_amp_process(a, buf, buf, n);
    const double secs = (double)(clock() - t0) / CLOCKS_PER_SEC;
    snprintf(d, sizeof d, "10 s with a %d-tap IR in %.3f s (%.0fx real time)",
             gf_amp_ir_length(ir, SR), secs, 10.0 / secs);
    report("cheap enough for a phone", secs < 0.5, d);

    gf_amp_set_sample_rate(a, 44100);
    gf_amp_process(a, buf, buf, SR);
    int finite = 1;
    for (int i = 0; i < SR; ++i) if (!isfinite(buf[i])) finite = 0;
    report("follows a sample-rate change", finite && rms(buf + SR / 2, SR / 2) > 0.01, "");
    gf_amp_destroy(a);
    free(buf);
}

int main(void) {
    printf("gf_convolver smoke test\n");
    srand(7);
    test_convolver();
    test_preparation();
    test_level();
    test_swaps();
    test_cost();
    printf("\n%s (%d failure%s)\n", g_failures ? "FAILED" : "ALL PASSED",
           g_failures, g_failures == 1 ? "" : "s");
    return g_failures ? 1 : 0;
}
