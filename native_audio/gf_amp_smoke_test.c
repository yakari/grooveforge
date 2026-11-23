// gf_amp_smoke_test.c — Offline checks for the guitar amp simulator.
//
// What it guards:
//
//   1. **The tone stack is the circuit.** The closed-form transfer function
//      (transcribed from Yeh & Smith) is compared with an independent nodal
//      analysis of the passive circuit, solved numerically from Kirchhoff's
//      current law. A typo in any of the dozens of terms shows up here.
//   2. **The digital tone stack matches the analog one** below 3 kHz, where
//      the bilinear transform's frequency warping is negligible.
//   3. **The knobs do what they say.** Bass raises the lows, Treble the highs,
//      and the Fender stack has its famous mid scoop at noon.
//   4. **The resampler is transparent**: flat across the audible band.
//   5. **Antialiasing works**: a high note through full distortion produces
//      far less inharmonic (folded) energy with it than without it.
//   6. **Sections switch without clicks**, and everything off is a bypass.
//   7. **Silence stays silent**, loud noise stays finite, and the cost is a
//      small fraction of real time.
//
// Build: see CMakeLists.txt — target "gf_amp_smoke_test".
// Run  : ./scripts/run_smoke_tests.sh amp

#include "gf_amp.h"

#include <complex.h>
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

// ── Nodal analysis of the tone stack ────────────────────────────────────────
//
// The circuit, driven by an ideal source Vin:
//
//   Vin ─C1─ A ─[treble pot, top part]─ W(out) ─[treble pot, rest]─ C
//   Vin ─R4─ B ;  B ─C2─ C ;  B ─C3─ E
//   C ─[bass pot, l·R2]─ D ─[(1-m)·R3]─ E ─[m·R3]─ ground
//
// The mid pot's whole track sits between the bass pot and ground, and C3
// lands on its wiper E. (Wiring C3 to the top of the track instead gives a
// response a few dB off the paper's: the test told those two apart.)
//
// Unknowns A, W, C, D, E, B; one KCL equation per node, solved by Gaussian
// elimination. [t_is_top] picks which end of the treble pot t measures from.

typedef double complex cplx;

#define NODES 6

static void solve(cplx m[NODES][NODES + 1], cplx x[NODES]) {
    for (int c = 0; c < NODES; ++c) {
        int piv = c;
        for (int r = c + 1; r < NODES; ++r)
            if (cabs(m[r][c]) > cabs(m[piv][c])) piv = r;
        for (int k = 0; k <= NODES; ++k) {
            cplx t = m[c][k]; m[c][k] = m[piv][k]; m[piv][k] = t;
        }
        for (int r = 0; r < NODES; ++r) {
            if (r == c) continue;
            const cplx f = m[r][c] / m[c][c];
            for (int k = c; k <= NODES; ++k) m[r][k] -= f * m[c][k];
        }
    }
    for (int r = 0; r < NODES; ++r) x[r] = m[r][NODES] / m[r][r];
}

/// Adds admittance [y] between unknowns [i] and [j] (-1 = the source node,
/// -2 = ground) to the system, with Vin = 1.
static void stamp(cplx m[NODES][NODES + 1], int i, int j, cplx y) {
    if (i >= 0) {
        m[i][i] += y;
        if (j >= 0) m[i][j] -= y; else if (j == -1) m[i][NODES] += y;
    }
    if (j >= 0) {
        m[j][j] += y;
        if (i >= 0) m[j][i] -= y; else if (i == -1) m[j][NODES] += y;
    }
}

static double nodal_db(int model, double bass, double mid, double treble,
                       double hz, int t_is_top) {
    double p[7], l, m, t;
    gf_amp_tonestack_parts(model, p);
    gf_amp_tonestack_tapers(bass, mid, treble, &l, &m, &t);
    const double eps = 1e-9;  // a pot at its end stop is a wire, not 0 ohm
    const double top = t_is_top ? t : 1.0 - t;
    const cplx s = I * 2.0 * M_PI * hz;
    enum { A, W, C, D, E, B };
    cplx mat[NODES][NODES + 1];
    memset(mat, 0, sizeof(mat));
    stamp(mat, -1, A, s * p[0]);
    stamp(mat, A, W, 1.0 / (p[3] * (top + eps)));
    stamp(mat, W, C, 1.0 / (p[3] * (1.0 - top + eps)));
    stamp(mat, -1, B, 1.0 / p[6]);
    stamp(mat, B, C, s * p[1]);
    stamp(mat, B, E, s * p[2]);
    stamp(mat, C, D, 1.0 / (p[4] * (l + eps)));
    stamp(mat, D, E, 1.0 / (p[5] * (1.0 - m + eps)));
    stamp(mat, E, -2, 1.0 / (p[5] * (m + eps)));
    cplx v[NODES];
    solve(mat, v);
    return 20.0 * log10(cabs(v[W]));
}

/// Largest gap in dB between the closed form and the nodal solution over a
/// grid of knob settings and frequencies.
static double tonestack_formula_error(int model, int t_is_top) {
    static const double knobs[] = {0.05, 0.3, 0.5, 0.7, 0.95};
    static const double freqs[] = {40, 100, 250, 500, 1000, 2000, 5000, 10000};
    double worst = 0.0;
    for (int bi = 0; bi < 5; ++bi)
    for (int mi = 0; mi < 5; ++mi)
    for (int ti = 0; ti < 5; ++ti)
    for (int fi = 0; fi < 8; ++fi) {
        const double a = gf_amp_tonestack_analog_db(
            model, knobs[bi], knobs[mi], knobs[ti], freqs[fi]);
        const double n = nodal_db(model, knobs[bi], knobs[mi], knobs[ti],
                                  freqs[fi], t_is_top);
        if (fabs(a - n) > worst) worst = fabs(a - n);
    }
    return worst;
}

static void test_tonestack_formula(void) {
    printf("\n1. Tone stack closed form vs nodal analysis\n");
    static const char* names[] = {"Fender", "Marshall", "Vox"};
    for (int model = 0; model < GF_AMP_MODEL_COUNT; ++model) {
        // Which end of the treble pot "t" measures from is a convention of
        // the paper; the circuit must match under exactly one of them.
        const double e_top = tonestack_formula_error(model, 1);
        const double e_bot = tonestack_formula_error(model, 0);
        const double e = e_top < e_bot ? e_top : e_bot;
        char d[160], name[80];
        snprintf(d, sizeof d, "max error %.4f dB (t from top: %.3f, from bottom: %.3f)",
                 e, e_top, e_bot);
        snprintf(name, sizeof name, "%s: formula matches the circuit", names[model]);
        report(name, e < 0.05, d);
    }
}

static void test_tonestack_digital(void) {
    printf("\n2. Digital tone stack vs analog\n");
    static const double freqs[] = {50, 100, 300, 700, 1500, 3000};
    double worst = 0.0;
    for (int model = 0; model < GF_AMP_MODEL_COUNT; ++model)
    for (double k = 0.1; k < 1.0; k += 0.4)
    for (int fi = 0; fi < 6; ++fi) {
        const double a = gf_amp_tonestack_analog_db(model, k, k, k, freqs[fi]);
        const double d = gf_amp_tonestack_digital_db(model, k, k, k, SR, freqs[fi]);
        if (fabs(a - d) > worst) worst = fabs(a - d);
    }
    char det[96];
    snprintf(det, sizeof det, "max error below 3 kHz: %.3f dB", worst);
    report("bilinear transform keeps the response", worst < 0.3, det);
}

static void test_tonestack_knobs(void) {
    printf("\n3. Tone stack knobs\n");
    char d[160];
    for (int model = 0; model < GF_AMP_MODEL_COUNT; ++model) {
        // Full knob travel, 0 to 10.
        const double lo0 = gf_amp_tonestack_digital_db(model, 0.0, 0.5, 0.5, SR, 80);
        const double lo1 = gf_amp_tonestack_digital_db(model, 1.0, 0.5, 0.5, SR, 80);
        const double hi0 = gf_amp_tonestack_digital_db(model, 0.5, 0.5, 0.0, SR, 5000);
        const double hi1 = gf_amp_tonestack_digital_db(model, 0.5, 0.5, 1.0, SR, 5000);
        snprintf(d, sizeof d, "model %d: bass 80 Hz %+.1f -> %+.1f dB, treble 5 kHz %+.1f -> %+.1f dB",
                 model, lo0, lo1, hi0, hi1);
        report("bass and treble move their own end", lo1 - lo0 > 6 && hi1 - hi0 > 6, d);
    }
    const double f100 = gf_amp_tonestack_digital_db(0, 0.5, 0.5, 0.5, SR, 100);
    const double f500 = gf_amp_tonestack_digital_db(0, 0.5, 0.5, 0.5, SR, 500);
    const double f3k = gf_amp_tonestack_digital_db(0, 0.5, 0.5, 0.5, SR, 3000);
    snprintf(d, sizeof d, "100 Hz %+.1f, 500 Hz %+.1f, 3 kHz %+.1f dB", f100, f500, f3k);
    report("Fender at noon scoops the mids", f500 < f100 && f500 < f3k, d);
    // The Bassman's mid control is famously subtle: ~6 dB end to end.
    const double m0 = gf_amp_tonestack_digital_db(0, 0.5, 0.0, 0.5, SR, 500);
    const double m1 = gf_amp_tonestack_digital_db(0, 0.5, 1.0, 0.5, SR, 500);
    snprintf(d, sizeof d, "500 Hz: %+.1f -> %+.1f dB", m0, m1);
    report("Middle raises the mids", m1 - m0 > 3, d);
}

// ── Signal measurement ──────────────────────────────────────────────────────

static void sine(float* buf, int n, double hz, double amp) {
    for (int i = 0; i < n; ++i) buf[i] = (float)(amp * sin(2 * M_PI * hz * i / SR));
}

/// Power of the [hz] component of [x] (n samples at [rate], exact-bin
/// frequencies).
static double goertzel_power_at(const float* x, int n, double hz, double rate) {
    const double w = 2 * M_PI * hz / rate, c = 2 * cos(w);
    double s1 = 0, s2 = 0;
    for (int i = 0; i < n; ++i) {
        const double s0 = x[i] + c * s1 - s2;
        s2 = s1;
        s1 = s0;
    }
    const double p = s1 * s1 + s2 * s2 - c * s1 * s2;
    return 2.0 * p / ((double)n * n);  // mean-square of that sinusoid
}

static double goertzel_power(const float* x, int n, double hz) {
    return goertzel_power_at(x, n, hz, SR);
}

static double mean_square(const float* x, int n) {
    double acc = 0;
    for (int i = 0; i < n; ++i) acc += (double)x[i] * x[i];
    return acc / n;
}

static void test_resampler(void) {
    printf("\n4. 2x resampler\n");
    const int n = SR;
    float* in = malloc(sizeof(float) * n);
    float* out = malloc(sizeof(float) * n);
    static const double freqs[] = {50, 1000, 5000, 10000, 15000, 18000, 20000};
    double worst = 0;
    for (int k = 0; k < 7; ++k) {
        sine(in, n, freqs[k], 0.5);
        gf_amp_debug_resample_roundtrip(in, out, n);
        const double db = 10 * log10(mean_square(out + n / 2, n / 2)
                                     / mean_square(in + n / 2, n / 2));
        if (fabs(db) > worst) worst = fabs(db);
    }
    char d[96];
    snprintf(d, sizeof d, "max deviation 50 Hz - 20 kHz: %.3f dB", worst);
    report("flat across the audible band", worst < 0.1, d);

    // Upsampling leaves a mirror image of every tone at 48 kHz - f; whatever
    // survives the filter is what the clippers would turn into noise.
    float* up = malloc(sizeof(float) * 2 * n);
    double weakest = -1e9;
    static const double probes[] = {1000, 10000, 20000, 21000};
    for (int k = 0; k < 4; ++k) {
        sine(in, n, probes[k], 0.5);
        gf_amp_debug_upsample(in, up, n);
        const float* tail = up + n;  // second half: the filter has settled
        const double sig = goertzel_power_at(tail, n, probes[k], 2.0 * SR);
        const double img = goertzel_power_at(tail, n, SR - probes[k], 2.0 * SR);
        const double rej = 10 * log10(img / sig + 1e-30);
        if (rej > weakest) weakest = rej;
    }
    snprintf(d, sizeof d, "weakest image rejection up to 21 kHz: %.1f dB", weakest);
    report("upsampling images are removed", weakest < -90, d);
    free(up);
    free(in);
    free(out);
}

/// Folded (inharmonic) energy relative to the total, in dB, for a [f0] sine
/// through full distortion. One second analysed: f0 is a whole number of Hz,
/// so every harmonic and every alias falls on an exact 1 Hz bin.
static double alias_db(int aa, double f0) {
    gf_amp* a = gf_amp_create(SR);
    gf_amp_params p;
    gf_amp_default_params(&p);
    p.drive_on = 1;
    p.drive_mode = GF_AMP_DRIVE_DISTORTION;
    p.drive = 1.0f;
    p.drive_tone = 1.0f;
    p.amp_on = 0;
    p.cab_on = 0;
    gf_amp_set_params(a, &p);
    gf_amp_reset(a);
    gf_amp_debug_set_antialias(a, aa);
    const int n = 2 * SR;
    float* buf = malloc(sizeof(float) * n);
    sine(buf, n, f0, 0.3);
    gf_amp_process(a, buf, buf, n);
    const float* tail = buf + SR;
    const double total = mean_square(tail, SR);
    double harm = 0;
    for (double h = f0; h < SR / 2; h += f0) harm += goertzel_power(tail, SR, h);
    free(buf);
    gf_amp_destroy(a);
    return 10 * log10((total - harm) / total + 1e-30);
}

static void test_aliasing(void) {
    printf("\n5. Aliasing under full distortion\n");
    const double f0 = 2489;  // high on the neck; not a divisor of 48 kHz
    const double off = alias_db(0, f0);
    const double on = alias_db(1, f0);
    char d[128];
    snprintf(d, sizeof d, "folded energy: %.1f dB without, %.1f dB with (%.1f dB less)",
             off, on, off - on);
    report("antialiasing removes most of the folded energy", off - on > 15, d);
    report("folded energy stays well under the tone", on < -40, "");
}

// ── Behaviour ───────────────────────────────────────────────────────────────

static gf_amp* make_amp(int drive_on, int amp_on, int cab_on) {
    gf_amp* a = gf_amp_create(SR);
    gf_amp_params p;
    gf_amp_default_params(&p);
    p.drive_on = drive_on;
    p.amp_on = amp_on;
    p.cab_on = cab_on;
    gf_amp_set_params(a, &p);
    gf_amp_reset(a);
    return a;
}

static void test_bypass(void) {
    printf("\n6. Switching\n");
    const int n = SR;
    float* in = malloc(sizeof(float) * n);
    float* out = malloc(sizeof(float) * n);
    sine(in, n, 1000, 0.5);
    gf_amp* a = make_amp(0, 0, 0);
    gf_amp_process(a, in, out, n);
    const double db = 10 * log10(mean_square(out + n / 2, n / 2)
                                 / mean_square(in + n / 2, n / 2));
    char d[128];
    snprintf(d, sizeof d, "level change %.3f dB", db);
    report("everything off passes the signal unchanged", fabs(db) < 0.05, d);
    gf_amp_destroy(a);

    // Toggle each section on and off on a low sine and look for steps: the
    // largest sample-to-sample jump must stay near what the waveforms
    // themselves contain.
    sine(in, n, 110, 0.4);
    static const char* names[] = {"Drive", "Amp", "Cab"};
    for (int s = 0; s < 3; ++s) {
        gf_amp* b = make_amp(0, 0, 0);
        gf_amp* ref = make_amp(s == 0, s == 1, s == 2);
        gf_amp_params p;
        gf_amp_default_params(&p);
        p.drive_on = p.amp_on = p.cab_on = 0;
        double steady = 0, worst = 0;
        float prev = 0, prev_ref = 0;
        for (int blk = 0; blk < n / 256; ++blk) {
            if (blk == 40) {
                if (s == 0) p.drive_on = 1;
                if (s == 1) p.amp_on = 1;
                if (s == 2) p.cab_on = 1;
                gf_amp_set_params(b, &p);
            }
            float ob[256], orf[256];
            gf_amp_process(b, in + blk * 256, ob, 256);
            gf_amp_process(ref, in + blk * 256, orf, 256);
            for (int i = 0; i < 256; ++i) {
                const double j = fabs(ob[i] - prev), jr = fabs(orf[i] - prev_ref);
                if (j > worst) worst = j;
                if (jr > steady) steady = jr;
                prev = ob[i];
                prev_ref = orf[i];
            }
        }
        // The unprocessed sine's own largest step, for the "off" half.
        const double sine_step = 0.4 * 2 * M_PI * 110 / SR;
        const double bound = 1.5 * (steady > sine_step ? steady : sine_step);
        char name[64];
        snprintf(name, sizeof name, "%s switches on without a click", names[s]);
        snprintf(d, sizeof d, "largest step %.4f, steady-state largest %.4f", worst, steady);
        report(name, worst < bound, d);
        gf_amp_destroy(b);
        gf_amp_destroy(ref);
    }
    free(in);
    free(out);
}

static void test_robustness(void) {
    printf("\n7. Silence, noise and cost\n");
    const int n = 10 * SR;
    float* buf = calloc((size_t)n, sizeof(float));
    gf_amp* a = make_amp(1, 1, 1);
    gf_amp_process(a, buf, buf, n);
    float peak = 0;
    for (int i = 0; i < n; ++i) if (fabsf(buf[i]) > peak) peak = fabsf(buf[i]);
    char d[128];
    snprintf(d, sizeof d, "peak %.2e", peak);
    report("silence stays silent", peak < 1e-6f, d);

    gf_amp_params p;
    gf_amp_default_params(&p);
    p.drive_on = 1;
    p.drive_mode = GF_AMP_DRIVE_DISTORTION;
    p.drive = p.gain = p.bass = p.middle = p.treble = 1.0f;
    p.level_db = 12.0f;
    gf_amp_set_params(a, &p);
    srand(1);
    for (int i = 0; i < n; ++i) buf[i] = 2.0f * rand() / (float)RAND_MAX - 1.0f;
    const clock_t t0 = clock();
    gf_amp_process(a, buf, buf, n);
    const double secs = (double)(clock() - t0) / CLOCKS_PER_SEC;
    int finite = 1;
    peak = 0;
    for (int i = 0; i < n; ++i) {
        if (!isfinite(buf[i])) finite = 0;
        if (fabsf(buf[i]) > peak) peak = fabsf(buf[i]);
    }
    snprintf(d, sizeof d, "peak %.2f", peak);
    report("full-scale noise at every knob maxed stays finite", finite && peak < 50, d);
    snprintf(d, sizeof d, "10 s of audio in %.3f s (%.0fx real time)", secs, 10.0 / secs);
    report("cheap enough for a phone", secs < 0.5, d);

    gf_amp_set_sample_rate(a, 44100);
    gf_amp_process(a, buf, buf, SR);
    finite = 1;
    for (int i = 0; i < SR; ++i) if (!isfinite(buf[i])) finite = 0;
    report("survives a sample-rate change", finite, "");
    gf_amp_destroy(a);
    free(buf);
}

int main(void) {
    printf("gf_amp smoke test\n");
    test_tonestack_formula();
    test_tonestack_digital();
    test_tonestack_knobs();
    test_resampler();
    test_aliasing();
    test_bypass();
    test_robustness();
    printf("\n%s (%d failure%s)\n", g_failures ? "FAILED" : "ALL PASSED",
           g_failures, g_failures == 1 ? "" : "s");
    return g_failures ? 1 : 0;
}
