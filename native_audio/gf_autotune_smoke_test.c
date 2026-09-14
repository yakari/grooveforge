// gf_autotune_smoke_test.c — Offline checks for the Autotune effect.
//
// Renders synthetic voices through the real GFPA DSP and measures the result
// with an estimator that shares no code with the effect (zero crossings), so
// a tracker bug cannot mark its own homework. What it guards:
//
//   1. **It tunes.** A note sung 30 cents sharp comes out on the note; at
//      50 % strength it comes out halfway.
//   2. **Key and scale.** A pitch between two notes of C major lands on the
//      nearer one — not on the chromatic neighbour that is not in the scale —
//      and a patched scale overrides the panel's.
//   3. **Retune Speed.** 0 ms has fully corrected within a fraction of a
//      second; 400 ms has not.
//   4. **Transpose** moves the pitch by exactly the number of semitones.
//   5. **No clicks.** A voice sliding across a whole octave under a hard
//      retune jumps note after note; none of those jumps may put a step in
//      the waveform, at any block size.
//   6. **Level.** Splices crossfade two copies of the signal; if they are
//      not in phase the level dips and wobbles.
//   7. **Silence stays silent**, and noise does not blow up.
//   8. **The stream's real rate.** An effect is created before the audio
//      stream opens, so it is told 48 kHz whatever the device runs at. On a
//      44.1 kHz stream every note it names is a semitone and a half high and
//      the voice lands between notes. The backend's published rate must win,
//      whether it arrives before the effect is created or after.
//
// Build: see CMakeLists.txt — target "gf_autotune_smoke_test".
// Run  : ./scripts/run_smoke_tests.sh autotune

#include "gfpa_dsp.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define SR 48000

/// The rate the synthetic audio is generated and measured at. The rate the
/// effect *believes* it runs at is a separate thing, set through
/// gfpa_dsp_create and gfpa_set_sample_rate — test 8 pulls the two apart.
static int g_rate = SR;

static int g_failures = 0;

static void report(const char* name, int ok, const char* detail) {
    printf("   %-58s %s\n", name, ok ? "PASS" : "FAIL");
    if (detail && detail[0]) printf("      %s\n", detail);
    if (!ok) g_failures++;
}

static double midiToHz(double note) { return 440.0 * pow(2.0, (note - 69.0) / 12.0); }
static double hzToMidi(double hz) { return 69.0 + 12.0 * log2(hz / 440.0); }

/// An Autotune at the given settings; everything else at its default.
static GfpaDspHandle makeTuner(double strength, double retuneMs) {
    GfpaDspHandle h = gfpa_dsp_create("com.grooveforge.autotune", SR, 4096);
    if (!h) return NULL;
    gfpa_dsp_set_param(h, "key", 0);
    gfpa_dsp_set_param(h, "scale", 0);          // chromatic
    gfpa_dsp_set_param(h, "strength", strength);
    gfpa_dsp_set_param(h, "retune", retuneMs);
    gfpa_dsp_set_param(h, "humanize", 0);
    gfpa_dsp_set_param(h, "flex_tune", 0);
    gfpa_dsp_set_param(h, "transpose", 0);
    gfpa_dsp_set_param(h, "mix", 100);
    return h;
}

/// A voice-like tone: a fundamental with falling harmonics. [phase] is
/// advanced in cycles so the pitch may glide without discontinuities.
static float voiceSample(double* phase, double hz) {
    const double p = 2.0 * M_PI * *phase;
    *phase += hz / g_rate;
    if (*phase > 1e6) *phase -= floor(*phase);
    return (float)(0.5 * sin(p) + 0.15 * sin(2 * p) + 0.08 * sin(3 * p));
}

/// Renders [seconds] of a steady tone at MIDI [note] through [h] in bursts of
/// [burst], writing the output from [skip] seconds onward into [out].
/// Returns the number of samples written.
static int renderTone(GfpaDspHandle h, double note, double seconds, double skip,
                      int burst, float* out, int capacity) {
    GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
    void* ud = gfpa_dsp_userdata(h);
    float in[4096], outL[4096], outR[4096];
    double phase = 0;
    const double hz = midiToHz(note);
    const int total = (int)(seconds * g_rate);
    const int from = (int)(skip * g_rate);
    int written = 0;
    for (int done = 0; done < total; done += burst) {
        for (int i = 0; i < burst; i++) in[i] = voiceSample(&phase, hz);
        fn(in, in, outL, outR, burst, ud);
        for (int i = 0; i < burst && written < capacity; i++) {
            if (done + i >= from) out[written++] = outL[i];
        }
    }
    return written;
}

/// Frequency of [x] from its rising zero crossings, interpolated to a
/// fraction of a sample. Independent of the tracker inside the effect.
static double zeroCrossingHz(const float* x, int n) {
    double first = -1, last = -1;
    int crossings = 0;
    for (int i = 1; i < n; i++) {
        if (x[i - 1] < 0 && x[i] >= 0) {
            const double t = (i - 1) + (-x[i - 1]) / (x[i] - x[i - 1]);
            if (first < 0) first = t;
            last = t;
            crossings++;
        }
    }
    if (crossings < 3) return 0;
    return (crossings - 1) * (double)g_rate / (last - first);
}

/// Output pitch, as a MIDI note, for a steady input note.
static double tunedNote(GfpaDspHandle h, double inNote) {
    static float buf[SR * 2];
    const int n = renderTone(h, inNote, 2.5, 1.0, 256, buf, SR * 2);
    const double hz = zeroCrossingHz(buf, n);
    return hz > 0 ? hzToMidi(hz) : -1;
}

// ── 1. It tunes ──────────────────────────────────────────────────────────────

static void testCorrects(void) {
    printf("── Test 1: a sharp note is pulled onto pitch\n");
    char detail[160];
    const double notes[3] = {48.3, 57.3, 69.3};   // C3, A3, A4, all +30 cents
    for (int k = 0; k < 3; k++) {
        GfpaDspHandle h = makeTuner(100, 0);
        const double out = tunedNote(h, notes[k]);
        gfpa_dsp_destroy(h);
        const double target = floor(notes[k] + 0.5);
        snprintf(detail, sizeof detail, "in %.2f -> out %.3f (want %.0f)",
                 notes[k], out, target);
        report("full strength lands within 5 cents", fabs(out - target) < 0.05, detail);
    }

    GfpaDspHandle h = makeTuner(50, 0);
    const double out = tunedNote(h, 57.3);
    gfpa_dsp_destroy(h);
    snprintf(detail, sizeof detail, "in 57.30 -> out %.3f (want 57.15)", out);
    report("half strength corrects half the distance", fabs(out - 57.15) < 0.05, detail);

    h = makeTuner(0, 0);
    const double untouched = tunedNote(h, 57.3);
    gfpa_dsp_destroy(h);
    snprintf(detail, sizeof detail, "in 57.30 -> out %.3f", untouched);
    report("zero strength leaves the pitch alone", fabs(untouched - 57.3) < 0.05, detail);
}

// ── 2. Key and scale ─────────────────────────────────────────────────────────

static void testScale(void) {
    printf("── Test 2: key, scale, and a patched scale\n");
    char detail[160];

    // 61.2 is C# + 20 cents. Chromatic keeps C#; C major has no C#, and D
    // (0.8 away) is nearer than C (1.2 away).
    GfpaDspHandle h = makeTuner(100, 0);
    gfpa_dsp_set_param(h, "scale", 1);          // major
    gfpa_dsp_set_param(h, "key", 0);            // C
    double out = tunedNote(h, 61.2);
    gfpa_dsp_destroy(h);
    snprintf(detail, sizeof detail, "in 61.20 -> out %.3f (want 62)", out);
    report("C major skips C# for the nearer D", fabs(out - 62.0) < 0.05, detail);

    // The same pitch in D major: C# is in the scale.
    h = makeTuner(100, 0);
    gfpa_dsp_set_param(h, "scale", 1);
    gfpa_dsp_set_param(h, "key", 2);            // D
    out = tunedNote(h, 61.2);
    gfpa_dsp_destroy(h);
    snprintf(detail, sizeof detail, "in 61.20 -> out %.3f (want 61)", out);
    report("D major keeps C#", fabs(out - 61.0) < 0.05, detail);

    // A patched scale holding only A overrides the panel's C major.
    h = makeTuner(100, 0);
    gfpa_dsp_set_param(h, "scale", 1);
    gfpa_dsp_set_param(h, "scale_mask", 1 << 9);
    out = tunedNote(h, 58.3);
    gfpa_dsp_destroy(h);
    snprintf(detail, sizeof detail, "in 58.30 -> out %.3f (want 57)", out);
    report("a patched scale wins over the panel", fabs(out - 57.0) < 0.05, detail);
}

// ── 3. Retune Speed ──────────────────────────────────────────────────────────

/// The applied correction [afterSeconds] into a note 40 cents flat.
static double correctionAfter(double retuneMs, double afterSeconds) {
    GfpaDspHandle h = makeTuner(100, retuneMs);
    static float buf[SR];
    renderTone(h, 56.6, afterSeconds, afterSeconds, 256, buf, SR);
    const double c = gfpa_dsp_get_readout(h, "correction");
    gfpa_dsp_destroy(h);
    return c;
}

static void testRetuneSpeed(void) {
    printf("── Test 3: retune speed\n");
    char detail[160];
    // The tracker needs ~50 ms of signal before it names a note at all.
    const double fast = correctionAfter(0, 0.15);
    const double slow = correctionAfter(400, 0.15);
    const double slowLater = correctionAfter(400, 2.5);
    snprintf(detail, sizeof detail,
             "0 ms: %+.3f st, 400 ms: %+.3f st at 150 ms and %+.3f st at 2.5 s (want +0.4)",
             fast, slow, slowLater);
    report("0 ms is fully corrected at 150 ms", fabs(fast - 0.4) < 0.03, detail);
    report("400 ms is still under half way at 150 ms", slow > 0 && slow < 0.2, NULL);
    report("400 ms gets there eventually", fabs(slowLater - 0.4) < 0.03, NULL);
}

/// Flex-Tune: a pitch far from any scale note is left alone, one close to a
/// note is still corrected.
static void testFlexTune(void) {
    printf("── Test 3b: flex-tune spares notes far from the scale\n");
    char detail[160];
    GfpaDspHandle h = makeTuner(100, 0);
    gfpa_dsp_set_param(h, "flex_tune", 60);     // zone reaches 0.4 st
    const double near = tunedNote(h, 57.1);
    gfpa_dsp_destroy(h);

    h = makeTuner(100, 0);
    gfpa_dsp_set_param(h, "flex_tune", 60);
    const double far = tunedNote(h, 57.45);
    gfpa_dsp_destroy(h);

    snprintf(detail, sizeof detail, "57.10 -> %.3f, 57.45 -> %.3f", near, far);
    report("10 cents off is still corrected", fabs(near - 57.0) < 0.05, detail);
    report("45 cents off is left alone", fabs(far - 57.45) < 0.05, NULL);
}

// ── 4. Transpose ─────────────────────────────────────────────────────────────

static void testTranspose(void) {
    printf("── Test 4: transpose\n");
    const double shifts[3] = {12, -12, 7};
    char detail[160];
    for (int k = 0; k < 3; k++) {
        GfpaDspHandle h = makeTuner(0, 0);
        gfpa_dsp_set_param(h, "transpose", shifts[k]);
        const double out = tunedNote(h, 57.0);
        gfpa_dsp_destroy(h);
        snprintf(detail, sizeof detail, "57 %+g st -> %.3f", shifts[k], out);
        report("output moves by the transpose", fabs(out - (57.0 + shifts[k])) < 0.05, detail);
    }
}

// ── 5. No clicks ─────────────────────────────────────────────────────────────

/// Largest sample-to-sample step in the output of an octave-long glide under
/// a hard retune, relative to the largest step a clean tone at the highest
/// output pitch could make.
static double worstStepRatio(int burst, double transpose) {
    GfpaDspHandle h = makeTuner(100, 0);
    gfpa_dsp_set_param(h, "transpose", transpose);
    GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
    void* ud = gfpa_dsp_userdata(h);

    float in[4096], outL[4096], outR[4096];
    double phase = 0;
    const int total = SR * 4;
    float prev = 0;
    double worst = 0;
    for (int done = 0; done < total; done += burst) {
        for (int i = 0; i < burst; i++) {
            // Glide from A2 to A3 and back over four seconds.
            const double t = (double)(done + i) / total;
            const double note = 45.0 + 12.0 * (t < 0.5 ? 2 * t : 2 - 2 * t);
            in[i] = voiceSample(&phase, midiToHz(note));
        }
        fn(in, in, outL, outR, burst, ud);
        for (int i = 0; i < burst; i++) {
            const double step = fabs(outL[i] - prev);
            if (done > SR / 4 && step > worst) worst = step;
            prev = outL[i];
        }
    }
    gfpa_dsp_destroy(h);

    // The steepest a clean voiceSample can be: sum of each harmonic's peak
    // slope, at the top of the glide after correction and transpose.
    const double topHz = midiToHz(57.5 + transpose);
    const double w = 2.0 * M_PI * topHz / SR;
    const double cleanStep = w * (0.5 + 0.15 * 2 + 0.08 * 3);
    return worst / cleanStep;
}

static void testContinuity(void) {
    printf("── Test 5: hard retune across an octave never clicks\n");
    const int bursts[4] = {64, 192, 256, 1024};
    char detail[160];
    for (int k = 0; k < 4; k++) {
        const double ratio = worstStepRatio(bursts[k], 0);
        snprintf(detail, sizeof detail, "burst %d: worst step %.2fx a clean tone's", bursts[k], ratio);
        report("no step beyond a clean tone's slope", ratio < 1.5, detail);
    }
    const double up = worstStepRatio(256, 12);
    snprintf(detail, sizeof detail, "+12 st: worst step %.2fx", up);
    report("no step with transpose up an octave", up < 1.5, detail);
}

// ── 6. Level ─────────────────────────────────────────────────────────────────

static void testLevel(void) {
    printf("── Test 6: the corrected voice keeps its level\n");
    static float buf[SR * 2];
    char detail[160];
    const double notes[3] = {45.3, 57.3, 69.3};
    for (int k = 0; k < 3; k++) {
        GfpaDspHandle h = makeTuner(100, 0);
        const int n = renderTone(h, notes[k], 2.5, 1.0, 256, buf, SR * 2);
        gfpa_dsp_destroy(h);

        // RMS over 20 ms windows: the mean says whether the level is right,
        // the spread says whether the splices make it wobble.
        const int win = SR / 50;
        double lo = 1e9, hi = 0, sum = 0;
        int windows = 0;
        for (int w = 0; w + win <= n; w += win) {
            double e = 0;
            for (int i = 0; i < win; i++) e += (double)buf[w + i] * buf[w + i];
            const double rms = sqrt(e / win);
            if (rms < lo) lo = rms;
            if (rms > hi) hi = rms;
            sum += rms;
            windows++;
        }
        // The clean tone's RMS: sqrt of half the summed squared amplitudes.
        const double expected = sqrt((0.25 + 0.0225 + 0.0064) / 2.0);
        const double meanDb = 20 * log10((sum / windows) / expected);
        const double wobbleDb = 20 * log10(hi / lo);
        snprintf(detail, sizeof detail, "note %.1f: mean %+.2f dB, wobble %.2f dB",
                 notes[k], meanDb, wobbleDb);
        report("level within 1 dB, wobble under 1.5 dB",
               fabs(meanDb) < 1.0 && wobbleDb < 1.5, detail);
    }
}

// ── 7. Silence and noise ─────────────────────────────────────────────────────

static void testSilenceAndNoise(void) {
    printf("── Test 7: silence and noise\n");
    GfpaDspHandle h = makeTuner(100, 0);
    GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
    void* ud = gfpa_dsp_userdata(h);
    float in[256], outL[256], outR[256];

    double peak = 0;
    memset(in, 0, sizeof in);
    for (int b = 0; b < 200; b++) {
        fn(in, in, outL, outR, 256, ud);
        for (int i = 0; i < 256; i++) if (fabs(outL[i]) > peak) peak = fabs(outL[i]);
    }
    report("silence in, silence out", peak == 0, NULL);
    report("no note is reported for silence",
           gfpa_dsp_get_readout(h, "input_note") < 0, NULL);

    unsigned seed = 1;
    int finite = 1;
    peak = 0;
    for (int b = 0; b < 400; b++) {
        for (int i = 0; i < 256; i++) {
            seed = seed * 1664525u + 1013904223u;
            in[i] = (float)((seed >> 8) / 16777216.0 - 0.5);
        }
        fn(in, in, outL, outR, 256, ud);
        for (int i = 0; i < 256; i++) {
            if (!isfinite(outL[i])) finite = 0;
            if (fabs(outL[i]) > peak) peak = fabs(outL[i]);
        }
    }
    char detail[80];
    snprintf(detail, sizeof detail, "peak %.3f for noise peaking at 0.5", peak);
    report("noise stays finite and bounded", finite && peak < 1.0, detail);
    report("unknown readouts are NaN", isnan(gfpa_dsp_get_readout(h, "nope")), NULL);
    gfpa_dsp_destroy(h);
}

// ── 8. Sample rate ───────────────────────────────────────────────────────────

/// Output pitch for a note 30 cents sharp, generated at 44.1 kHz, through an
/// Autotune created with a 48 kHz guess. [publish] is what the backend
/// reports: before creation, after it, or never (0).
static double tunedAt44k(double publishBefore, double publishAfter) {
    gfpa_set_sample_rate(publishBefore);
    GfpaDspHandle h = makeTuner(100, 0);        // asks for SR = 48000
    gfpa_set_sample_rate(publishAfter);
    g_rate = 44100;
    const double out = tunedNote(h, 57.3);
    g_rate = SR;
    gfpa_dsp_destroy(h);
    gfpa_set_sample_rate(0);
    return out;
}

static void testStreamSampleRate(void) {
    printf("── Test 8: effects follow the stream's real sample rate\n");
    char detail[160];

    const double unaware = tunedAt44k(0, 0);
    snprintf(detail, sizeof detail, "never told: 57.30 -> %.3f", unaware);
    report("control: a 48 kHz effect on 44.1 kHz audio misses the note",
           fabs(unaware - 57.0) > 0.2, detail);

    const double before = tunedAt44k(44100, 44100);
    snprintf(detail, sizeof detail, "stream open first: 57.30 -> %.3f", before);
    report("built at the stream's rate when it is already open",
           fabs(before - 57.0) < 0.05, detail);

    const double after = tunedAt44k(0, 44100);
    snprintf(detail, sizeof detail, "stream opens later: 57.30 -> %.3f", after);
    report("follows a rate published after it was created",
           fabs(after - 57.0) < 0.05, detail);
}

int main(void) {
    printf("Autotune smoke test\n");
    testCorrects();
    testScale();
    testRetuneSpeed();
    testFlexTune();
    testTranspose();
    testContinuity();
    testLevel();
    testSilenceAndNoise();
    testStreamSampleRate();
    printf("\n%s (%d failure%s)\n", g_failures ? "FAILED" : "OK",
           g_failures, g_failures == 1 ? "" : "s");
    return g_failures ? 1 : 0;
}
