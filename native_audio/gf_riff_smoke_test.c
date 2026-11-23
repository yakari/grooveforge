// gf_riff_smoke_test.c — Offline checks for Riff, the modelled guitar.
//
// What it guards:
//
//   1. **Tuning.** Every note of a piano's range, A0 to C8 (the low string
//      takes what lies below the low E, the high one what lies past the
//      24th fret), plays in tune at 44.1, 48 and 96 kHz. Pitch is measured from the
//      audio, not read back from the engine.
//   2. **Decay.** Strings ring for the time the Sustain control sets, high
//      notes shorter than low ones; palm mute shortens them a lot.
//   3. **Bends** reach the set range, and bending or muting a ringing
//      string never clicks.
//   4. **Strings.** Notes go to the strings a guitarist would use: a C chord
//      lands in open position, one note per string; a seventh note steals a
//      string; the same note picked again reuses its string without piling
//      up energy.
//   5. **Release and sustain pedal.**
//   6. **Pickups** play at about the same loudness.
//   7. **Robustness and cost**: random playing with every control at its
//      extremes stays finite and bounded; six ringing strings are cheap.
//
// Build: see CMakeLists.txt — target "gf_riff_smoke_test".
// Run  : ./scripts/run_smoke_tests.sh riff

#include "gf_riff.h"

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

static double note_hz(double n) { return 440.0 * pow(2.0, (n - 69.0) / 12.0); }

static double rms(const float* x, int n) {
    double s = 0;
    for (int i = 0; i < n; ++i) s += (double)x[i] * x[i];
    return sqrt(s / (n > 0 ? n : 1));
}

static double db(double x) { return 20.0 * log10(x + 1e-30); }

static float* render(gf_riff* r, int n) {
    float* out = malloc(sizeof(float) * (size_t)n);
    for (int done = 0; done < n; done += 256) {
        const int len = n - done < 256 ? n - done : 256;
        gf_riff_process(r, out + done, len);
    }
    return out;
}

/// Period of [x] near [expect] samples, by autocorrelation: the peak at a
/// multiple of the period long enough for sub-cent precision, refined by a
/// parabola through its three points.
static double measure_period(const float* x, int n, double expect) {
    const int mult = (int)ceil(1200.0 / expect);
    const double lag0 = expect * mult;
    // Search ±3% but never as far as the neighbouring multiple.
    const double span = fmin(0.03 * lag0, 0.4 * expect);
    const int lo = (int)(lag0 - span), hi = (int)(lag0 + span) + 1;
    const int win = n - hi - 1;
    double best = -1e30;
    int at = lo;
    double c[3];
    for (int lag = lo; lag <= hi; ++lag) {
        double s = 0;
        for (int i = 0; i < win; ++i) s += (double)x[i] * x[i + lag];
        if (s > best) { best = s; at = lag; }
    }
    for (int k = -1; k <= 1; ++k) {
        double s = 0;
        for (int i = 0; i < win; ++i) s += (double)x[i] * x[i + at + k];
        c[k + 1] = s;
    }
    const double den = c[0] - 2 * c[1] + c[2];
    const double off = den != 0 ? 0.5 * (c[0] - c[2]) / den : 0.0;
    return (at + off) / mult;
}

/// Power of [x] at [hz], through a Hann window. The phasor is advanced by
/// multiplication, so a scan costs no trigonometry per sample.
static double dft_power(const float* x, const double* win, int n, double hz, double rate) {
    const double w = 2 * M_PI * hz / rate, cw = cos(w), sw = sin(w);
    double re = 0, im = 0, pc = 1, ps = 0;
    for (int i = 0; i < n; ++i) {
        const double v = x[i] * win[i];
        re += v * pc;
        im += v * ps;
        const double t = pc * cw - ps * sw;
        ps = pc * sw + ps * cw;
        pc = t;
    }
    return re * re + im * im;
}

/// Where, in cents from [hz], the fundamental of [x] sits: the peak of a
/// windowed DFT scanned 1 cent at a time over ±30 cents, then a twentieth of
/// a cent around the best. A DFT at the note, rather than a period count,
/// because a stiff string's upper harmonics run sharp and would pull any
/// method that looks at the whole waveform.
static double fundamental_cents(const float* x, int n, double hz, double rate) {
    double* win = malloc(sizeof(double) * (size_t)n);
    for (int i = 0; i < n; ++i) win[i] = 0.5 - 0.5 * cos(2 * M_PI * i / n);
    double best = -1, at = 0;
    for (double c = -30.0; c <= 30.0; c += 1.0) {
        const double pw = dft_power(x, win, n, hz * pow(2.0, c / 1200.0), rate);
        if (pw > best) { best = pw; at = c; }
    }
    const double coarse = at;
    for (double c = coarse - 1.0; c <= coarse + 1.0; c += 0.05) {
        const double pw = dft_power(x, win, n, hz * pow(2.0, c / 1200.0), rate);
        if (pw > best) { best = pw; at = c; }
    }
    free(win);
    return at;
}

/// Cents between the pitch heard and [note], after the attack settles.
/// [humanize] 0 measures the engine's own tuning, without the deliberate
/// spread between strings.
static double tuning_error_h(double rate, int note, gf_riff_params* p, int humanize) {
    gf_riff* r = gf_riff_create((float)rate);
    gf_riff_debug_set_humanize(r, humanize);
    if (p) gf_riff_set_params(r, p);
    gf_riff_note_on(r, note, 50);
    // Measured once the pick's glide has settled but while the note still
    // rings: the top of a piano's range dies within a third of a second,
    // so the window follows the note's own decay time.
    const double t60 = 2.0 * pow(10.0, 0.7) * pow(note_hz(40) / note_hz(note), 0.9);
    const double start = fmin(0.35, 0.2 * t60);
    // At least 40 periods: below the low E a third of a second holds barely
    // ten, too few for a sub-cent reading.
    const double span = fmax(0.35, 40.0 / note_hz(note));
    const int n = (int)((start + span) * rate);
    float* out = render(r, n);
    const int from = (int)(start * rate);
    const double cents = fundamental_cents(out + from, n - from, note_hz(note), rate);
    free(out);
    gf_riff_destroy(r);
    return cents;
}

static double tuning_error(double rate, int note, gf_riff_params* p) {
    return tuning_error_h(rate, note, p, 0);
}

// ── 1. Tuning ───────────────────────────────────────────────────────────────

static void test_tuning(void) {
    printf("\n1. Tuning\n");
    static const double rates[] = {44100, 48000, 96000};
    for (int k = 0; k < 3; ++k) {
        double worst = 0;
        int worst_note = 0;
        for (int note = GF_RIFF_NOTE_MIN; note <= GF_RIFF_NOTE_MAX; ++note) {
            const double e = fabs(tuning_error(rates[k], note, NULL));
            if (e > worst) { worst = e; worst_note = note; }
        }
        char name[64], d[96];
        snprintf(name, sizeof name, "every note in tune at %.1f kHz", rates[k] / 1000);
        snprintf(d, sizeof d, "worst %.2f cents (MIDI %d)", worst, worst_note);
        // 2.5 cents, half of what the ear notices and about how close a
        // real guitar stays in tune. Measured over seconds the engine is
        // within a quarter of a cent; at the two ends of a piano's range the
        // glide a pick leaves has not settled inside the window. A missing
        // delay compensation, the failure this guards, is tens of cents.
        report(name, worst < 2.5, d);
    }
    // As played, the strings sit a hair apart, as on a real guitar, but no
    // further than a careful player would tolerate.
    double lo = 1e9, hi = -1e9;
    for (int s = 0; s < GF_RIFF_STRINGS; ++s) {
        static const int open[] = {40, 45, 50, 55, 59, 64};
        const double e = tuning_error_h(SR, open[s] + 5, NULL, 1);
        lo = fmin(lo, e);
        hi = fmax(hi, e);
    }
    char d2[96];
    snprintf(d2, sizeof d2, "fifth fret of each string: %.2f to %.2f cents", lo, hi);
    report("as played, strings sit a hair apart, within 2 cents", hi - lo > 0.2 && lo > -2.0 && hi < 2.0, d2);
    // A stiff wound string's 10th harmonic runs sharp: about 9.5 cents on
    // the low E (B = 1.1e-4). Found from the audio by scanning a DFT, one
    // tenth of a cent at a time, around ten times the fundamental.
    {
        gf_riff* r = gf_riff_create(SR);
        gf_riff_debug_set_humanize(r, 0);
        gf_riff_params p;
        gf_riff_default_params(&p);
        p.pickup = GF_RIFF_PICKUP_NECK;   // hears the 10th well
        gf_riff_set_params(r, &p);
        gf_riff_note_on(r, 40, 60);
        const int n = (int)(1.2 * SR), from = SR / 5;
        float* out = render(r, n);
        const double h10 = 10.0 * note_hz(40);
        double best = -1, at = 0;
        for (double c = -40.0; c <= 40.0; c += 0.1) {
            const double w = 2 * M_PI * h10 * pow(2.0, c / 1200.0) / SR;
            double re = 0, im = 0;
            for (int i = from; i < n; ++i) {
                const double win = 0.5 - 0.5 * cos(2 * M_PI * (i - from) / (n - from));
                re += out[i] * win * cos(w * i);
                im += out[i] * win * sin(w * i);
            }
            if (re * re + im * im > best) { best = re * re + im * im; at = c; }
        }
        free(out);
        gf_riff_destroy(r);
        char d[80];
        snprintf(d, sizeof d, "10th harmonic of the low E %.1f cents sharp (real strings: ~9.5)", at);
        report("wound strings are stiff: upper harmonics run sharp", at > 6.0 && at < 13.0, d);
    }

    // A keyboard's whole range plays at pitch: below the low E on the low
    // string, past the 24th fret on the high one. No octave jumps inside a
    // piano's range; only beyond it does a note fold back.
    gf_riff* r = gf_riff_create(SR);
    gf_riff_note_on(r, 39, 80);   // D#2, just below the low E
    gf_riff_note_on(r, 89, 80);   // F6, just past the 24th fret
    int low = 0, high = 0;
    low = gf_riff_string_note(r, 0) == 39;
    high = gf_riff_string_note(r, GF_RIFF_STRINGS - 1) == 89;
    report("notes past the guitar's range play at pitch, no octave jump", low && high, "");
    gf_riff_destroy(r);
    r = gf_riff_create(SR);
    gf_riff_note_on(r, 12, 80);   // C0, below a piano
    gf_riff_note_on(r, 120, 80);  // C9, above a piano
    int folded_low = 0, folded_high = 0;
    for (int s = 0; s < GF_RIFF_STRINGS; ++s) {
        folded_low |= gf_riff_string_note(r, s) == 24;
        folded_high |= gf_riff_string_note(r, s) == 108;
    }
    report("only notes past a piano's range fold by octaves", folded_low && folded_high, "");
    gf_riff_destroy(r);
}

// ── 2. Decay ────────────────────────────────────────────────────────────────

/// Decay time of [note], seconds: a straight line fitted to the level, in
/// dB, over 50 ms windows late enough that the fundamental dominates. A
/// fit rather than two points, because the two planes of the string beat
/// slowly and two windows could land anywhere in that swell.
static double measure_t60(gf_riff_params* p, int note, double expect) {
    gf_riff* r = gf_riff_create(SR);
    gf_riff_set_params(r, p);
    gf_riff_note_on(r, note, 90);
    const double t1 = fmax(0.1, 0.2 * expect), t2 = t1 + 0.5 * expect;
    const int n = (int)((t2 + 0.1) * SR);
    float* out = render(r, n);
    const int w = SR / 20;
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    int m = 0;
    for (double t = t1; t < t2; t += 0.05, ++m) {
        const double y = db(rms(out + (int)(t * SR), w));
        sx += t; sy += y; sxx += t * t; sxy += t * y;
    }
    const double slope = (m * sxy - sx * sy) / (m * sxx - sx * sx);   // dB/s
    free(out);
    gf_riff_destroy(r);
    return -60.0 / slope;
}

static double expected_t60(double sustain, int note) {
    return 2.0 * pow(10.0, sustain) * pow(note_hz(40) / note_hz(note), 0.9);
}

static void test_decay(void) {
    printf("\n2. Decay\n");
    gf_riff_params p;
    gf_riff_default_params(&p);
    static const int notes[] = {40, 52, 64, 76};
    double worst = 0;
    char d[160] = "";
    for (int i = 0; i < 4; ++i) {
        const double want = expected_t60(p.sustain, notes[i]);
        const double got = measure_t60(&p, notes[i], want);
        const double ratio = got / want;
        worst = fmax(worst, fabs(log(ratio)));
        char part[40];
        snprintf(part, sizeof part, "%d: %.1f/%.1f s  ", notes[i], got, want);
        strncat(d, part, sizeof d - strlen(d) - 1);
    }
    report("strings ring for the time Sustain sets (within 25%)", worst < log(1.25), d);

    const double open = measure_t60(&p, 45, expected_t60(p.sustain, 45));
    p.palm_mute = 1.0f;
    const double muted = measure_t60(&p, 45, 0.12);
    p.palm_mute = 1.0f;
    p.sustain = 1.0f;
    const double muted_long = measure_t60(&p, 45, 0.12);
    snprintf(d, sizeof d, "A string: %.2f s open, %.2f s palm-muted, %.2f s at full sustain",
             open, muted, muted_long);
    report("full palm mute cuts the ring to ~0.12 s, whatever the sustain",
           muted > 0.08 && muted < 0.18 && muted_long > 0.08 && muted_long < 0.18, d);
}

// ── 3. Bends and live controls ──────────────────────────────────────────────

/// Largest sample-to-sample step in [x].
static double worst_step(const float* x, int n) {
    double w = 0;
    for (int i = 1; i < n; ++i) w = fmax(w, fabs(x[i] - x[i - 1]));
    return w;
}

/// Plays a ringing A, runs [event] each block from block 40 to 80, and
/// returns the largest step after the event starts relative to the largest
/// before it. A clean change stays near or below 1.
static double click_ratio(void (*event)(gf_riff*, int block)) {
    gf_riff* r = gf_riff_create(SR);
    gf_riff_note_on(r, 57, 100);
    const int blk = 256, blocks = 120;
    float* out = malloc(sizeof(float) * blk * blocks);
    for (int b = 0; b < blocks; ++b) {
        if (b >= 40 && b < 80) event(r, b - 40);
        gf_riff_process(r, out + b * blk, blk);
    }
    const double before = worst_step(out + 20 * blk, 20 * blk);
    const double after = worst_step(out + 40 * blk, 80 * blk);
    free(out);
    gf_riff_destroy(r);
    return after / before;
}

/// The bend jumps straight to the top, as a coarse pitch wheel or a ribbon
/// tapped at its end sends it: the engine has to glide, not leap.
static void bend_up(gf_riff* r, int k) { if (k == 0) gf_riff_pitch_bend(r, 1.0f); }

static void palm_on(gf_riff* r, int k) {
    gf_riff_params p;
    gf_riff_default_params(&p);
    p.palm_mute = k == 0 ? 1.0f : 1.0f;
    gf_riff_set_params(r, &p);
}

static void sweep_controls(gf_riff* r, int k) {
    gf_riff_params p;
    gf_riff_default_params(&p);
    p.pickup = k / 10;          // every pickup in turn
    p.humbucker = k % 2;
    p.tone = (float)(k % 7) / 6.0f;
    gf_riff_set_params(r, &p);
}

static void test_bends(void) {
    printf("\n3. Bends and live controls\n");
    gf_riff_params p;
    gf_riff_default_params(&p);
    char d[96];
    for (int range = 2; range <= 12; range += 10) {
        p.bend_range = (float)range;
        gf_riff* r = gf_riff_create(SR);
        gf_riff_set_params(r, &p);
        gf_riff_pitch_bend(r, 1.0f);
        gf_riff_note_on(r, 57, 50);
        const int n = (int)(0.7 * SR);
        float* out = render(r, n);
        const double expect = SR / note_hz(57);
        const double per = measure_period(out + SR / 3, n - SR / 3, expect / pow(2.0, range / 12.0));
        const double cents = 1200.0 * log2(expect / per);
        snprintf(d, sizeof d, "%.1f cents for a full bend (range %d semitones)", cents, range);
        char name[64];
        snprintf(name, sizeof name, "a full bend reaches the range (%d semitones)", range);
        report(name, fabs(cents - 100.0 * range) < 3.0, d);
        free(out);
        gf_riff_destroy(r);
    }
    double c = click_ratio(bend_up);
    snprintf(d, sizeof d, "largest step %.2fx the steady state", c);
    report("bending a ringing string does not click", c < 1.2, d);
    c = click_ratio(palm_on);
    snprintf(d, sizeof d, "largest step %.2fx the steady state", c);
    report("palm-muting a ringing string does not click", c < 1.2, d);
    c = click_ratio(sweep_controls);
    snprintf(d, sizeof d, "largest step %.2fx the steady state", c);
    report("switching pickups and tone while it rings does not click", c < 1.5, d);
}

// ── 4. Strings ──────────────────────────────────────────────────────────────

static void test_strings(void) {
    printf("\n4. Strings\n");
    gf_riff* r = gf_riff_create(SR);
    static const int chord[] = {48, 52, 55, 60, 64};   // C major, open position
    for (int i = 0; i < 5; ++i) gf_riff_note_on(r, chord[i], 90);
    float buf[256];
    gf_riff_process(r, buf, 256);
    int found = 0, max_fret = 0, used = 0;
    char d[128] = "";
    for (int s = 0; s < GF_RIFF_STRINGS; ++s) {
        const int note = gf_riff_string_note(r, s);
        if (note < 0) continue;
        used++;
        for (int i = 0; i < 5; ++i) found += note == chord[i];
        if (gf_riff_string_fret(r, s) > max_fret) max_fret = gf_riff_string_fret(r, s);
        char part[24];
        snprintf(part, sizeof part, "s%d:fret %d  ", s + 1, gf_riff_string_fret(r, s));
        strncat(d, part, sizeof d - strlen(d) - 1);
    }
    report("a C chord takes five strings, in open position",
           used == 5 && found == 5 && max_fret <= 3, d);

    // Same note again: same string, no build-up of energy.
    gf_riff_destroy(r);
    r = gf_riff_create(SR);
    const int blk = SR / 10;
    float* out = malloc(sizeof(float) * blk * 20);
    for (int k = 0; k < 20; ++k) {
        gf_riff_note_on(r, 50, 100);
        gf_riff_process(r, out + k * blk, blk);
    }
    int strings_used = 0;
    for (int s = 0; s < GF_RIFF_STRINGS; ++s) strings_used += gf_riff_string_note(r, s) >= 0;
    const double first = worst_step(out, blk) > 0 ? rms(out, blk) : 0;
    const double last = rms(out + 19 * blk, blk);
    snprintf(d, sizeof d, "level of the 20th pick %.1f dB from the first, %d string(s)",
             db(last) - db(first), strings_used);
    report("re-picking a note reuses its string without piling up",
           strings_used == 1 && last < 1.3 * first, d);
    free(out);
    gf_riff_destroy(r);

    // Seven held notes on six strings: the first picked is stolen.
    r = gf_riff_create(SR);
    static const int seven[] = {40, 45, 50, 55, 59, 64, 69};
    for (int i = 0; i < 7; ++i) {
        gf_riff_note_on(r, seven[i], 90);
        gf_riff_process(r, buf, 256);
    }
    int has69 = 0, has40 = 0, active = 0;
    for (int s = 0; s < GF_RIFF_STRINGS; ++s) {
        const int note = gf_riff_string_note(r, s);
        active += note >= 0;
        has69 |= note == 69;
        has40 |= note == 40;
    }
    report("a seventh held note takes a string, six still sound",
           has69 && has40 && active == 6, "");
    gf_riff_destroy(r);
}

// ── 4b. Close notes and legato ──────────────────────────────────────────────

/// Number of strings sounding, and whether one of them plays [note].
static int strings_playing(const gf_riff* r, int note, int* has) {
    int n = 0;
    *has = 0;
    for (int s = 0; s < GF_RIFF_STRINGS; ++s) {
        const int v = gf_riff_string_note(r, s);
        n += v >= 0;
        *has |= v == note;
    }
    return n;
}

/// Level of [note]'s fundamental in [x], dB (arbitrary reference).
static double note_db(const float* x, int n, int note) {
    double* win = malloc(sizeof(double) * (size_t)n);
    for (int i = 0; i < n; ++i) win[i] = 0.5 - 0.5 * cos(2 * M_PI * i / n);
    const double pw = dft_power(x, win, n, note_hz(note), SR);
    free(win);
    return 10.0 * log10(pw + 1e-30);
}

/// Strikes [a] and [b] together and returns how far apart, in dB, their
/// fundamentals sound half a second later; 99 when they share a string.
static double pair_gap(int a, int b) {
    gf_riff* r = gf_riff_create(SR);
    gf_riff_debug_set_humanize(r, 0);
    gf_riff_note_on(r, a, 100);
    gf_riff_note_on(r, b, 100);
    float* out = render(r, SR);
    int has;
    const int used = strings_playing(r, a, &has);
    const double gap = fabs(note_db(out + SR / 2, SR / 2, a) - note_db(out + SR / 2, SR / 2, b));
    free(out);
    gf_riff_destroy(r);
    return used == 2 ? gap : 99.0;
}

/// A guitar with legato on, [first] held and ringing for a fifth of a second.
static gf_riff* legato_guitar(int first, int by_pedal) {
    gf_riff* r = gf_riff_create(SR);
    gf_riff_debug_set_humanize(r, 0);
    gf_riff_params p;
    gf_riff_default_params(&p);
    p.legato = by_pedal ? 0 : 1;
    gf_riff_set_params(r, &p);
    if (by_pedal) gf_riff_legato_pedal(r, 1);
    gf_riff_note_on(r, first, 100);
    free(render(r, SR / 5));
    return r;
}

static void test_legato(void) {
    printf("\n4b. Close notes and legato\n");
    char d[128];
    // Notes only one string reaches on a real guitar: a free string plays
    // the second one out of its range instead of cutting the first off.
    static const int pairs[][2] = {{40, 41}, {33, 35}, {86, 88}, {59, 60}};
    double worst = 0;
    for (int k = 0; k < 4; ++k) worst = fmax(worst, pair_gap(pairs[k][0], pairs[k][1]));
    snprintf(d, sizeof d, "fundamentals at most %.1f dB apart (E2+F2, A1+B1, D6+E6, B3+C4)", worst);
    report("two close notes both sound, even where one string reaches both", worst < 10.0, d);

    // Hammer-on: the string moves to the new note without a second string.
    for (int by_pedal = 0; by_pedal <= 1; ++by_pedal) {
        gf_riff* r = legato_guitar(60, by_pedal);
        gf_riff_note_on(r, 62, 100);
        float* out = render(r, SR / 2);
        int has62;
        const int used = strings_playing(r, 62, &has62);
        const double cents = fundamental_cents(out + SR / 10, SR / 2 - SR / 10, note_hz(62), SR);
        snprintf(d, sizeof d, "%d string(s), the hammered note %.1f cents off", used, cents);
        report(by_pedal ? "the legato pedal (CC 68) hammers on as well"
                        : "legato: a close note hammers on, on the same string",
               used == 1 && has62 && fabs(cents) < 3.0, d);
        free(out);

        if (by_pedal) { gf_riff_destroy(r); break; }
        // Pull-off: letting go of the top key falls back to the held one.
        gf_riff_note_off(r, 62);
        out = render(r, SR / 2);
        int has60;
        const int used2 = strings_playing(r, 60, &has60);
        const double c2 = fundamental_cents(out + SR / 10, SR / 2 - SR / 10, note_hz(60), SR);
        const double ring = rms(out + SR / 4, SR / 4);
        snprintf(d, sizeof d, "%d string(s), %.1f cents off, still ringing at %.1f dB",
                 used2, c2, db(ring));
        report("releasing the hammered key pulls off to the one held",
               used2 == 1 && has60 && fabs(c2) < 3.0 && db(ring) > -60.0, d);
        free(out);
        gf_riff_destroy(r);
    }

    // The hammer does not click: its first 5 ms take no larger steps than
    // the hammered note once it has settled. The tap and the energy put back
    // into the string (see SLUR_SUSTAIN) are part of the note, not a spike.
    {
        // Two seconds in, so the string has decayed and the slur has a
        // good deal of energy to put back.
        gf_riff* r = legato_guitar(57, 0);
        free(render(r, 2 * SR));
        gf_riff_note_on(r, 59, 100);
        float* after = render(r, SR / 10);
        const int onset = SR / 200, settled = SR / 50;
        const double c = worst_step(after, onset) / worst_step(after + settled, SR / 10 - settled);
        snprintf(d, sizeof d, "largest step in the first 5 ms %.2fx the settled note's", c);
        report("a hammer-on does not click", c < 1.0, d);
        free(after);
        gf_riff_destroy(r);
    }

    // Lifting the lower finger under a hammered note changes nothing heard,
    // and the top key's release then damps the string: nothing to pull to.
    {
        gf_riff* r = legato_guitar(60, 0);
        gf_riff_note_on(r, 62, 100);
        free(render(r, SR / 10));
        gf_riff_note_off(r, 60);
        free(render(r, SR / 10));
        int has62;
        const int still = strings_playing(r, 62, &has62) == 1 && has62;
        gf_riff_note_off(r, 62);
        float* out = render(r, SR / 2);
        const double tail = rms(out + SR / 4, SR / 4);
        report("lifting the lower finger first leaves the hammered note",
               still && db(tail) < -60.0, "");
        free(out);
        gf_riff_destroy(r);
    }

    // A long legato run keeps its level: the open B string pedalled under
    // hammer-ons and pull-offs from the 12th, 10th and 9th frets, four notes
    // a second, each key let go as the next goes down, for six seconds. The
    // open B at the end must sound about as loud as just after the pick;
    // without the slurs' energy it ended 9 dB down.
    {
        gf_riff* r = legato_guitar(59, 0);
        static const int run[] = {71, 59, 69, 59, 68, 59, 69, 59};
        const int step = SR / 4, steps = 24;
        float* out = malloc(sizeof(float) * (size_t)step);
        double last_b = 0.0;
        int prev = 59;
        for (int k = 0; k < steps; ++k) {
            const int next = run[k % 8];
            gf_riff_note_off(r, prev);
            gf_riff_note_on(r, next, 100);
            prev = next;
            for (int done = 0; done < step; done += 256) {
                const int len = step - done < 256 ? step - done : 256;
                gf_riff_process(r, out + done, len);
            }
            if (next == 59) last_b = rms(out, step);
        }
        free(out);
        gf_riff_destroy(r);
        // The same open B just after its pick, for reference.
        r = gf_riff_create(SR);
        gf_riff_debug_set_humanize(r, 0);
        gf_riff_note_on(r, 59, 100);
        float* pick = render(r, step);
        const double first_b = rms(pick, step);
        free(pick);
        gf_riff_destroy(r);
        snprintf(d, sizeof d, "open B after six seconds of slurs %.1f dB from its pick",
                 db(last_b) - db(first_b));
        report("a long hammer-on / pull-off run keeps its level",
               db(last_b) - db(first_b) > -5.0, d);
    }

    // The same riff moved to C4, as a keyboard player plays it: the pedal is
    // now fretted (1st fret of the B string), not open, and the run climbs
    // to its 13th fret. Every note stays on the pedal's string.
    {
        gf_riff* r = legato_guitar(60, 0);
        static const int run[] = {64, 60, 67, 60, 68, 60, 72, 60, 70, 60, 69, 60};
        int prev = 60, worst = 1;
        for (int k = 0; k < 12; ++k) {
            gf_riff_note_off(r, prev);
            gf_riff_note_on(r, run[k], 100);
            prev = run[k];
            free(render(r, SR / 10));
            int has;
            const int used = strings_playing(r, run[k], &has);
            if (!has || used > worst) worst = has ? used : 99;
        }
        snprintf(d, sizeof d, "at most %d string(s) sounding during the run", worst);
        report("legato: Thunderstruck from C4 stays on one string", worst == 1, d);
        gf_riff_destroy(r);
    }

    // Overlap legato: slurs only a key pressed while the previous one, alone,
    // is still down.
    {
        static const char* names[] = {
            "overlap: a note pressed over the held one hammers on",
            "overlap: a detached note is picked on its own string",
            "overlap: a melody over a held chord keeps every chord note",
        };
        for (int k = 0; k < 3; ++k) {
            gf_riff* r = gf_riff_create(SR);
            gf_riff_params p;
            gf_riff_default_params(&p);
            p.legato_overlap = 1;
            gf_riff_set_params(r, &p);
            if (k == 2) {
                gf_riff_note_on(r, 48, 100);
                gf_riff_note_on(r, 52, 100);
                gf_riff_note_on(r, 55, 100);
            } else {
                gf_riff_note_on(r, 60, 100);
            }
            free(render(r, SR / 5));
            if (k == 1) gf_riff_note_off(r, 60);
            gf_riff_note_on(r, k == 2 ? 57 : 65, 100);
            free(render(r, SR / 50));
            int has;
            const int used = strings_playing(r, k == 2 ? 57 : 65, &has);
            const int want = k == 0 ? 1 : (k == 1 ? 2 : 4);
            snprintf(d, sizeof d, "%d string(s) sounding, %d expected", used, want);
            report(names[k], used == want && has, d);
            gf_riff_destroy(r);
        }
    }

    // What legato leaves alone: a chord, a wide jump, and legato off.
    static const char* names[] = {
        "legato: notes struck together still form a chord",
        "legato: a jump past an octave is picked on another string",
        "without legato a close note is picked on its own string",
    };
    for (int k = 0; k < 3; ++k) {
        gf_riff* r = gf_riff_create(SR);
        gf_riff_params p;
        gf_riff_default_params(&p);
        p.legato = k < 2;
        gf_riff_set_params(r, &p);
        gf_riff_note_on(r, 60, 100);
        if (k != 0) free(render(r, SR / 5));
        float buf[128];
        gf_riff_process(r, buf, 128);   // under 3 ms: a hand's chord
        gf_riff_note_on(r, k == 1 ? 74 : 62, 100);
        gf_riff_process(r, buf, 128);
        int has;
        report(names[k], strings_playing(r, 60, &has) == 2 && has, "");
        gf_riff_destroy(r);
    }
}

// ── 4c. Pedal sustain and feedback ──────────────────────────────────────────

/// Level of [hz] in [x] (n samples), dB, searched ±1% so a string that
/// settles a few cents sharp is still found.
static double peak_near_db(const float* x, int n, double hz) {
    double* win = malloc(sizeof(double) * (size_t)n);
    for (int i = 0; i < n; ++i) win[i] = 0.5 - 0.5 * cos(2 * M_PI * i / n);
    double best = 0.0;
    for (double f = hz * 0.99; f <= hz * 1.01; f += hz * 0.0005) {
        best = fmax(best, dft_power(x, win, n, f, SR));
    }
    free(win);
    return 10.0 * log10(best / ((double)n * n) + 1e-30);
}

/// Holds [note] with [feedback] on harmonic selection [harm] (and the
/// pedal down when [pedal]) for [secs] seconds and returns the level, dB,
/// of frequency [hz] in the last quarter second; the output's peak goes in
/// [peak].
static double hold_level(int note, float feedback, int harm, int pedal, double secs,
                         double hz, float* peak) {
    gf_riff* r = gf_riff_create(SR);
    gf_riff_debug_set_humanize(r, 0);
    gf_riff_params p;
    gf_riff_default_params(&p);
    p.feedback = feedback;
    p.fb_harmonic = harm;
    gf_riff_set_params(r, &p);
    if (pedal) gf_riff_sustain_pedal(r, 1);
    gf_riff_note_on(r, note, 100);
    const int n = (int)(secs * SR);
    float* out = render(r, n);
    *peak = 0.0f;
    for (int i = 0; i < n; ++i) *peak = fmaxf(*peak, fabsf(out[i]));
    const double lvl = peak_near_db(out + n - SR / 4, SR / 4, hz);
    free(out);
    gf_riff_destroy(r);
    return lvl;
}

static void test_feedback(void) {
    printf("\n4c. Pedal sustain and feedback\n");
    char d[128];
    float peak;
    // The pedal makes a held note ring longer than holding it alone.
    const double held = hold_level(52, 0.0f, 1, 0, 3.0, note_hz(52), &peak);
    const double pedalled = hold_level(52, 0.0f, 1, 1, 3.0, note_hz(52), &peak);
    snprintf(d, sizeof d, "after 3 s: %.1f dB with the pedal, %.1f dB held alone",
             pedalled, held);
    report("the pedal makes a note ring longer than holding it", pedalled - held > 15.0, d);

    // Feedback: the octave of a held E3 blooms and holds, while the same
    // note without feedback has died away; the output stays bounded.
    const double fb_on = hold_level(52, 1.0f, 1, 0, 8.0, 2 * note_hz(52), &peak);
    const float fb_peak = peak;
    const double fb_off = hold_level(52, 0.0f, 1, 0, 8.0, 2 * note_hz(52), &peak);
    snprintf(d, sizeof d, "octave after 8 s: %.1f dB with feedback, %.1f dB without; peak %.2f",
             fb_on, fb_off, fb_peak);
    report("feedback: a held note's octave blooms and holds",
           fb_on - fb_off > 60.0 && fb_peak < 0.5f, d);

    // Every harmonic choice holds, from the low E to the top of the neck.
    static const int notes[] = {40, 52, 64, 76, 88};
    double worst = 1e9;
    int worst_note = 0, worst_harm = 0;
    for (int k = 0; k < 5; ++k) {
        for (int harm = 0; harm < 4; ++harm) {
            int n = harm + 1;
            while (n > 1 && n * note_hz(notes[k]) > 3000.0) n--;
            const double lvl = hold_level(notes[k], 1.0f, harm, 0, 6.0, n * note_hz(notes[k]), &peak);
            if (lvl < worst) { worst = lvl; worst_note = notes[k]; worst_harm = harm; }
        }
    }
    snprintf(d, sizeof d, "weakest after 6 s: %.1f dB (note %d, harmonic choice %d)",
             worst, worst_note, worst_harm);
    report("feedback holds on every string and harmonic choice", worst > -45.0, d);

    // Letting go, or the palm, stops the feedback: the string dies as usual.
    {
        gf_riff* r = gf_riff_create(SR);
        gf_riff_params p;
        gf_riff_default_params(&p);
        p.feedback = 1.0f;
        gf_riff_set_params(r, &p);
        gf_riff_note_on(r, 52, 100);
        free(render(r, 2 * SR));
        gf_riff_note_off(r, 52);
        float* out = render(r, SR);
        const double tail = rms(out + SR / 2, SR / 2);
        free(out);
        p.palm_mute = 1.0f;
        gf_riff_set_params(r, &p);
        gf_riff_note_on(r, 52, 100);
        out = render(r, 2 * SR);
        const double muted = rms(out + SR, SR);
        free(out);
        gf_riff_destroy(r);
        snprintf(d, sizeof d, "%.1f dB after letting go, %.1f dB palm-muted", db(tail), db(muted));
        report("letting go or the palm mute stops the feedback",
               db(tail) < -70.0 && db(muted) < -70.0, d);
    }
}

// ── 5. Release and sustain pedal ────────────────────────────────────────────

/// Level 0.3 s after letting go of the key, in dB relative to the same note
/// still held at that moment. [release] 0 keeps the key down throughout.
static double level_after(int pedal, int release) {
    gf_riff* r = gf_riff_create(SR);
    gf_riff_sustain_pedal(r, pedal);
    gf_riff_note_on(r, 52, 100);
    float* a = render(r, SR / 2);
    if (release) gf_riff_note_off(r, 52);
    float* b = render(r, SR / 2);
    const double after = rms(b + (int)(0.3 * SR), SR / 10);
    free(a);
    free(b);
    gf_riff_destroy(r);
    return db(after);
}

static double level_after_release(int pedal) {
    return level_after(pedal, 1) - level_after(pedal, 0);
}

static void test_release(void) {
    printf("\n5. Release and sustain pedal\n");
    char d[64];
    double l = level_after_release(0);
    snprintf(d, sizeof d, "%.0f dB 0.3 s after the key is let go", l);
    report("letting go of a key damps the string", l < -40.0, d);
    l = level_after_release(1);
    snprintf(d, sizeof d, "%.1f dB from a held note, 0.3 s after the key is let go", l);
    report("with the sustain pedal down it keeps ringing", fabs(l) < 0.5, d);
}

// ── 6. Pickups ──────────────────────────────────────────────────────────────

static double strum_level(int pickup, int humbucker) {
    gf_riff_params p;
    gf_riff_default_params(&p);
    p.pickup = pickup;
    p.humbucker = humbucker;
    gf_riff* r = gf_riff_create(SR);
    gf_riff_set_params(r, &p);
    static const int open_chord[] = {40, 47, 52, 56, 59, 64};   // E major
    for (int i = 0; i < 6; ++i) gf_riff_note_on(r, open_chord[i], 90);
    float* out = render(r, SR);
    const double l = db(rms(out, SR));
    free(out);
    gf_riff_destroy(r);
    return l;
}

static void test_pickups(void) {
    printf("\n6. Pickups\n");
    double lo = 1e9, hi = -1e9;
    char d[160] = "";
    static const char* names[] = {"neck", "middle", "bridge", "neck+bridge"};
    for (int hb = 0; hb <= 1; ++hb) {
        for (int k = 0; k < GF_RIFF_PICKUP_COUNT; ++k) {
            const double l = strum_level(k, hb);
            lo = fmin(lo, l);
            hi = fmax(hi, l);
            if (hb) continue;
            char part[32];
            snprintf(part, sizeof part, "%s %.1f  ", names[k], l);
            strncat(d, part, sizeof d - strlen(d) - 1);
        }
    }
    char d2[200];
    snprintf(d2, sizeof d2, "%sdB; spread %.1f dB incl. humbuckers", d, hi - lo);
    report("every pickup plays at about the same level (within 6 dB)", hi - lo < 6.0, d2);
}

// ── 7. Robustness and cost ──────────────────────────────────────────────────

/// Peak of [secs] seconds of random playing at [rate] from [seed]: random
/// notes, releases, bends of up to an octave, vibrato, the pedal, and every
/// switch flipped at random, Feedback full when [feedback]. 1e30 when a
/// sample is not finite.
static double random_play_peak(double rate, unsigned seed, int secs, int feedback) {
    srand(seed);
    gf_riff* r = gf_riff_create((float)rate);
    gf_riff_params p;
    float buf[256];
    double peak = 0;
    for (int b = 0; b < (int)(secs * rate / 256); ++b) {
        if (b % 8 == 0) {
            gf_riff_default_params(&p);
            p.palm_mute = (float)(rand() % 2);
            p.pick_pos = (float)(rand() % 2);
            p.pickup = rand() % 4;
            p.humbucker = rand() % 2;
            p.tone = (float)(rand() % 2);
            p.sustain = (float)(rand() % 2);
            p.attack = (float)(rand() % 2);
            p.bend_range = 12.0f;
            p.legato = rand() % 2;
            p.legato_overlap = rand() % 2;
            p.pedal_sustain = (float)(rand() % 2);
            p.feedback = feedback ? 1.0f : (float)(rand() % 2);
            p.fb_harmonic = rand() % 4;
            gf_riff_set_params(r, &p);
            gf_riff_pitch_bend(r, (float)(rand() % 3) - 1.0f);
            gf_riff_vibrato(r, (float)(rand() % 2));
            gf_riff_sustain_pedal(r, rand() % 2);
        }
        const int note = 20 + rand() % 100;
        if (rand() % 3 == 0) gf_riff_note_on(r, note, 1 + rand() % 127);
        if (rand() % 3 == 0) gf_riff_note_off(r, 20 + rand() % 100);
        if (rand() % 200 == 0) gf_riff_all_notes_off(r);
        gf_riff_process(r, buf, 256);
        for (int i = 0; i < 256; ++i) {
            if (!isfinite(buf[i])) { gf_riff_destroy(r); return 1e30; }
            peak = fmax(peak, fabs(buf[i]));
        }
    }
    gf_riff_destroy(r);
    return peak;
}

static void test_robustness(void) {
    printf("\n7. Robustness and cost\n");
    const double peak = random_play_peak(SR, 7, 20, 0);
    const int finite = peak < 1e29;
    // The same at high rates, where a re-pick's damping and a short loop
    // last more samples: quick re-picks dropping in pitch once blew up there.
    double high = 0;
    static const double rates[] = {96000, 192000};
    for (int k = 0; k < 2; ++k) {
        for (unsigned seed = 1; seed <= 4; ++seed) {
            high = fmax(high, random_play_peak(rates[k], seed, 10, 1));
        }
    }
    char dh[96];
    snprintf(dh, sizeof dh, "worst peak %.2f over 8 runs at 96 and 192 kHz, feedback full", high);
    // Normal playing peaks under 0.9 here (a full chord at velocity 127
    // reaches about 0.9); the old fold reached 2 to 35.
    report("random playing at high sample rates stays bounded", high < 1.5, dh);
    char d[96];
    snprintf(d, sizeof d, "peak %.2f over 20 s of random playing", peak);
    report("random playing at extreme settings stays finite and bounded",
           finite && peak < 4.0, d);

    // Headroom: six strings struck as hard as MIDI allows.
    gf_riff* r = gf_riff_create(SR);
    gf_riff_params p;
    float buf[256];
    static const int e_chord[] = {40, 47, 52, 56, 59, 64};
    for (int i = 0; i < 6; ++i) gf_riff_note_on(r, e_chord[i], 127);
    float* strum = render(r, SR);
    double top = 0;
    for (int i = 0; i < SR; ++i) top = fmax(top, fabs(strum[i]));
    snprintf(d, sizeof d, "peak %.2f (%.1f dBFS)", top, db(top));
    report("a full chord at maximum velocity stays below full scale",
           top < 1.0 && top > 0.25, d);
    free(strum);
    gf_riff_destroy(r);

    // Six strings ringing for ten seconds.
    r = gf_riff_create(SR);
    gf_riff_default_params(&p);
    p.sustain = 1.0f;
    gf_riff_set_params(r, &p);
    static const int open_chord[] = {40, 47, 52, 56, 59, 64};
    for (int i = 0; i < 6; ++i) gf_riff_note_on(r, open_chord[i], 100);
    const clock_t t0 = clock();
    for (int b = 0; b < 10 * SR / 256; ++b) gf_riff_process(r, buf, 256);
    const double secs = (double)(clock() - t0) / CLOCKS_PER_SEC;
    snprintf(d, sizeof d, "10 s of six ringing strings in %.3f s (%.0fx real time)",
             secs, 10.0 / secs);
    report("cheap enough for a phone", secs < 0.5, d);

    gf_riff_set_sample_rate(r, 44100.0f);
    gf_riff_process(r, buf, 256);
    report("a rate change silences the strings", rms(buf, 256) == 0.0, "");
    gf_riff_destroy(r);
}

int main(void) {
    printf("Riff guitar smoke test\n");
    test_tuning();
    test_decay();
    test_bends();
    test_strings();
    test_legato();
    test_feedback();
    test_release();
    test_pickups();
    test_robustness();
    printf("\n%s (%d failure%s)\n", g_failures ? "FAILED" : "ALL PASSED",
           g_failures, g_failures == 1 ? "" : "s");
    return g_failures ? 1 : 0;
}
