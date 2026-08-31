// gf_tuning_smoke_test.c — Offline smoke test for microtonal key tuning.
//
// Verifies that `keyboard_set_key_tuning` / `keyboard_clear_tuning` in
// keyboard_synth.c really change the pitch FluidSynth produces. The Xen module
// is built entirely on this mechanism, so a silent regression here — a
// FluidSynth version that drops MIDI Tuning Standard support, a build linked
// against a synth without it — would make every microtonal scale in the app
// play back as plain equal temperament with no visible error anywhere.
//
// Two checks, matching the two claims the module rests on:
//
//   1. MONOPHONIC — a −50 cent table on the E key makes E4 sound a
//      quarter-tone flat, and clearing the tuning restores it exactly.
//      Measured by autocorrelation with parabolic peak interpolation
//      (integer lags alone quantise to ~12 cents at this pitch, the same
//      order as the effect, so the interpolation is not optional).
//
//   2. POLYPHONIC — with a maqam Rast table active on ONE MIDI channel, a
//      held C-E-G chord comes out with a flat third over an untouched root
//      and fifth. This is what rules out the pitch-bend approach used by the
//      older Microtone plugin: bend is per channel and would drag all three
//      notes together. Measured with Goertzel filters, because
//      autocorrelation cannot separate concurrent pitches.
//
// Build: see CMakeLists.txt — target "gf_tuning_smoke_test".
// Run  : ./build/gf_tuning_smoke_test [soundfont.sf2]
//        Defaults to ../assets/soundfonts/default.sf2.

#include <math.h>
#include <stdio.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ── Functions under test (keyboard_synth.c) ──────────────────────────────────

extern int  keyboard_init(float sr);
extern int  keyboard_load_sf(const char* path);
extern void keyboard_program_select(int ch, int sf, int bank, int prog);
extern void keyboard_note_on(int ch, int key, int vel);
extern void keyboard_note_off(int ch, int key);
extern void keyboard_render_block(float* l, float* r, int frames);
extern void keyboard_set_key_tuning(int ch, const double* cents);
extern void keyboard_clear_tuning(int ch);

// ── Constants ────────────────────────────────────────────────────────────────

#define SR          48000
#define FRAMES      48000   ///< 1 s analysis window.
#define SETTLE      12000   ///< 0.25 s discarded so the attack transient is gone.
#define MIN_HZ      80
#define MAX_HZ      800
#define MAX_LAG     (SR / MIN_HZ)
#define MIN_LAG     (SR / MAX_HZ)

/** Tolerance in cents for every pitch assertion. */
#define TOL_CENTS   1.5

/** The quarter-tone the Arabic 24-tone convention notates as a half-flat. */
#define QUARTER_FLAT (-50.0)

static float L[FRAMES], R[FRAMES];
static double g_corr[MAX_LAG + 2];

// ── Pitch measurement ────────────────────────────────────────────────────────

/**
 * Estimate the fundamental of a monophonic buffer by autocorrelation.
 *
 * The raw peak lands on an integer lag, which at 330 Hz quantises the result
 * to roughly 12 cents — too coarse to confirm a 50 cent shift with any
 * confidence. Fitting a parabola through the peak and its two neighbours
 * recovers a fractional lag and brings the error under a tenth of a cent.
 */
static double estimate_hz(const float* x, int n) {
    double best = -1e30;
    int best_lag = MIN_LAG;
    for (int lag = MIN_LAG; lag <= MAX_LAG; ++lag) {
        double acc = 0.0;
        for (int i = 0; i + lag < n; ++i) acc += (double)x[i] * (double)x[i + lag];
        g_corr[lag] = acc;
        if (acc > best) { best = acc; best_lag = lag; }
    }
    double refined = (double)best_lag;
    if (best_lag > MIN_LAG && best_lag < MAX_LAG) {
        double a = g_corr[best_lag - 1], b = g_corr[best_lag], c = g_corr[best_lag + 1];
        double denom = a - 2.0 * b + c;
        if (fabs(denom) > 1e-12) refined = best_lag + 0.5 * (a - c) / denom;
    }
    return (double)SR / refined;
}

/**
 * Energy at a single frequency, via the Goertzel recurrence.
 *
 * A Hann window is applied because the two frequencies that must be told
 * apart — the equal-tempered E4 and its quarter-flat neighbour — are only
 * 9 Hz apart, and an unwindowed bin leaks far more than that.
 */
static double goertzel(const float* x, int n, double hz) {
    double w = 2.0 * M_PI * hz / (double)SR;
    double coeff = 2.0 * cos(w);
    double s0, s1 = 0.0, s2 = 0.0;
    for (int i = 0; i < n; ++i) {
        double win = 0.5 * (1.0 - cos(2.0 * M_PI * i / (n - 1)));
        s0 = coeff * s1 - s2 + (double)x[i] * win;
        s2 = s1;
        s1 = s0;
    }
    return sqrt(s1 * s1 + s2 * s2 - coeff * s1 * s2);
}

/** Interval between two frequencies, in cents. */
static double cents_between(double from_hz, double to_hz) {
    return 1200.0 * log2(to_hz / from_hz);
}

// ── Test helpers ─────────────────────────────────────────────────────────────

/** Fill a 128-key table that flattens the E and B keys — maqam Rast on C. */
static void build_rast_table(double* table) {
    for (int k = 0; k < 128; ++k) {
        int pc = k % 12;
        table[k] = (pc == 4 || pc == 11) ? QUARTER_FLAT : 0.0;
    }
}

/** Play one key with [tuning] applied (NULL = equal temperament) and measure it. */
static double render_single_note(int key, const double* tuning) {
    if (tuning) keyboard_set_key_tuning(0, tuning);
    else        keyboard_clear_tuning(0);

    keyboard_note_on(0, key, 110);
    keyboard_render_block(L, R, SETTLE);
    keyboard_render_block(L, R, FRAMES);
    double hz = estimate_hz(L, FRAMES);

    keyboard_note_off(0, key);
    keyboard_render_block(L, R, SETTLE);
    return hz;
}

// ── Test 1 — monophonic shift and restore ────────────────────────────────────

static int test_monophonic(void) {
    printf("── Test 1: a single key bends by exactly the requested amount\n");

    const int key_e4 = 64;
    double table[128];
    build_rast_table(table);

    double plain    = render_single_note(key_e4, NULL);
    double tuned    = render_single_note(key_e4, table);
    double restored = render_single_note(key_e4, NULL);

    double shift   = cents_between(plain, tuned);
    double residue = cents_between(plain, restored);

    printf("   plain    : %8.3f Hz\n", plain);
    printf("   tuned    : %8.3f Hz  (%+.2f cents, expected %+.2f)\n",
           tuned, shift, QUARTER_FLAT);
    printf("   restored : %8.3f Hz  (%+.2f cents from plain)\n", restored, residue);

    int ok = 1;
    if (fabs(shift - QUARTER_FLAT) > TOL_CENTS) {
        printf("   FAIL: tuning table was not applied\n");
        ok = 0;
    }
    if (fabs(residue) > TOL_CENTS) {
        printf("   FAIL: keyboard_clear_tuning did not restore 12-TET\n");
        ok = 0;
    }
    printf(ok ? "   PASS\n" : "   FAIL\n");
    return ok;
}

// ── Test 2 — polyphonic, per-key independence ────────────────────────────────

static int test_polyphonic(void) {
    printf("── Test 2: one channel, three notes, only the third moves\n");

    double table[128];
    build_rast_table(table);
    keyboard_set_key_tuning(0, table);

    keyboard_note_on(0, 60, 110);   // C4 — root, must not move
    keyboard_note_on(0, 64, 110);   // E4 — the only retuned key
    keyboard_note_on(0, 67, 110);   // G4 — fifth, must not move
    keyboard_render_block(L, R, SETTLE);
    keyboard_render_block(L, R, FRAMES);

    const double c4      = 261.626;
    const double e4_tet  = 329.628;
    const double e4_rast = 329.628 * pow(2.0, QUARTER_FLAT / 1200.0);
    const double g4      = 391.995;

    double energy_c    = goertzel(L, FRAMES, c4);
    double energy_tet  = goertzel(L, FRAMES, e4_tet);
    double energy_rast = goertzel(L, FRAMES, e4_rast);
    double energy_g    = goertzel(L, FRAMES, g4);
    double reference   = (energy_c + energy_g) / 2.0;

    printf("   C4  %7.2f Hz : %8.1f  (root, must stay)\n", c4, energy_c);
    printf("   E4  %7.2f Hz : %8.1f  (12-TET third, must vanish)\n", e4_tet, energy_tet);
    printf("   E4  %7.2f Hz : %8.1f  (Rast third, must appear)\n", e4_rast, energy_rast);
    printf("   G4  %7.2f Hz : %8.1f  (fifth, must stay)\n", g4, energy_g);

    // Thresholds are deliberately loose — the point is which bins carry the
    // energy, not their exact level, which depends on the SoundFont.
    int ok = 1;
    if (energy_rast < 0.30 * reference) {
        printf("   FAIL: the quarter-flat third never sounded\n");
        ok = 0;
    }
    if (energy_tet > 0.30 * energy_rast) {
        printf("   FAIL: the third is still at its equal-tempered pitch\n");
        ok = 0;
    }
    if (energy_c < 0.30 * energy_rast || energy_g < 0.30 * energy_rast) {
        printf("   FAIL: root or fifth was dragged along — not per-key tuning\n");
        ok = 0;
    }
    printf(ok ? "   PASS\n" : "   FAIL\n");

    keyboard_note_off(0, 60);
    keyboard_note_off(0, 64);
    keyboard_note_off(0, 67);
    keyboard_clear_tuning(0);
    return ok;
}

// ── Entry point ──────────────────────────────────────────────────────────────

int main(int argc, char** argv) {
    const char* sf_path = (argc > 1)
        ? argv[1]
        : "../assets/soundfonts/default.sf2";

    if (!keyboard_init(SR)) {
        fprintf(stderr, "gf_tuning_smoke_test: keyboard_init failed\n");
        return 1;
    }
    int sf = keyboard_load_sf(sf_path);
    if (sf < 0) {
        fprintf(stderr, "gf_tuning_smoke_test: could not load '%s'\n", sf_path);
        return 1;
    }
    keyboard_program_select(0, sf, 0, 0);

    int ok = 1;
    ok &= test_monophonic();
    ok &= test_polyphonic();

    printf(ok ? "\nALL TESTS PASSED\n" : "\nTESTS FAILED\n");
    return ok ? 0 : 1;
}
