// gf_aec_smoke_test.c — Offline smoke test for the echo canceller.
//
// Builds a rehearsal take from parts whose truth is known, so the result can
// be measured rather than listened to:
//
//   - a REFERENCE, standing in for the click and backing track the phone
//     plays out of its speaker;
//   - a ROOM, a short impulse response with a few early reflections and a
//     decaying tail, standing in for the trip from speaker to microphone;
//   - a NEAR signal, standing in for the musician, which must survive;
//   - the MIC, which is the reference through the room, delayed, plus the
//     musician.
//
// Because the near signal is known exactly, the echo left in the output can be
// isolated (output minus near) and compared with the echo that went in (mic
// minus near). That ratio is the number that matters, and no amount of
// damaging the musician's sound can flatter it.
//
// Six checks:
//
//   1. DELAY — the estimator finds a known lag to within a block.
//   2. CANCELLATION — a take with speaker bleed loses most of it.
//   3. THE MUSICIAN SURVIVES — with no echo to cancel, the near signal comes
//      back essentially untouched. This is the check that fails if the filter
//      starts subtracting the performance instead of the echo.
//   4. TWO PASSES EARN THEIR KEEP — the opening of the take is cancelled as
//      well as the end, which a single adapting pass cannot manage.
//   5. NOTHING TO DO — an unrelated reference (headphones, no bleed) leaves
//      the take alone instead of mangling it.
//
// Build: see CMakeLists.txt — target "gf_aec_smoke_test".
// Run  : ./build/gf_aec_smoke_test

#include "gf_aec.h"
#include "gf_wav.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define SR        48000
#define SECONDS   12
#define FRAMES    (SR * SECONDS)
#define DELAY     2400      ///< 50 ms, a plausible phone round trip.
#define ROOM_LEN  3000      ///< ~62 ms of room.

// ─── Signal construction ────────────────────────────────────────────────────

static unsigned g_seed = 20260101u;

static float noise(void) {
    g_seed = g_seed * 1664525u + 1013904223u;
    return (float)((int)(g_seed >> 16) % 2000 - 1000) / 1000.0f;
}

/// A backing track's worth of sound: a few partials plus a click on every
/// beat, which is what actually comes out of the phone in a rehearsal.
static void make_reference(float* x, int n) {
    const double beat = 60.0 / 116.0 * SR;   // 116 BPM
    for (int i = 0; i < n; i++) {
        const double t = (double)i / SR;
        double v = 0.22 * sin(2.0 * M_PI * 110.0 * t)
                 + 0.16 * sin(2.0 * M_PI * 247.0 * t)
                 + 0.10 * sin(2.0 * M_PI * 659.0 * t);
        const double phase = fmod((double)i, beat);
        if (phase < 180.0) {
            // Short percussive click, broadband enough to excite the filter.
            v += 0.45 * exp(-phase / 40.0) * sin(2.0 * M_PI * 1800.0 * t);
        }
        x[i] = (float)(v * 0.6);
    }
}

/// The musician: a different, slower signal that must come through intact.
static void make_near(float* x, int n) {
    for (int i = 0; i < n; i++) {
        const double t = (double)i / SR;
        double v = 0.30 * sin(2.0 * M_PI * 196.0 * t + 0.4 * sin(2.0 * M_PI * 3.0 * t))
                 + 0.18 * sin(2.0 * M_PI * 392.0 * t);
        x[i] = (float)(v * 0.5);
    }
}

/// A plausible small room: direct sound, a handful of early reflections, and
/// an exponential tail with the high end rolling off.
static void make_room(float* h, int n) {
    for (int i = 0; i < n; i++) h[i] = 0.0f;
    h[0] = 0.80f;
    h[131] = -0.38f;
    h[277] = 0.26f;
    h[523] = -0.17f;
    h[881] = 0.12f;
    float lp = 0.0f;
    for (int i = 0; i < n; i++) {
        const float tail = 0.25f * expf(-(float)i / 600.0f) * noise();
        lp = 0.7f * lp + 0.3f * tail;      // dull the tail, as a room does
        h[i] += lp;
    }
}

/// out[i] = sum_j in[i-j] * h[j], with the whole thing pushed back by [delay].
static void convolve_delayed(const float* in, int n, const float* h, int hn,
                             int delay, float* out) {
    for (int i = 0; i < n; i++) out[i] = 0.0f;
    for (int i = 0; i < n; i++) {
        const float xi = in[i];
        if (xi == 0.0f) continue;
        const int base = i + delay;
        const int last = (base + hn < n) ? hn : (n - base);
        for (int j = 0; j < last; j++) out[base + j] += xi * h[j];
    }
}

// ─── Measurement ────────────────────────────────────────────────────────────

static double energy(const float* x, int n) {
    double e = 0.0;
    for (int i = 0; i < n; i++) e += (double)x[i] * (double)x[i];
    return e;
}

/// Energy of (a - b), i.e. how much of [a] is not explained by [b].
static double diff_energy(const float* a, const float* b, int n) {
    double e = 0.0;
    for (int i = 0; i < n; i++) {
        const double d = (double)a[i] - (double)b[i];
        e += d * d;
    }
    return e;
}

static double to_db(double ratio) {
    if (ratio <= 0.0) return -999.0;
    return 10.0 * log10(ratio);
}

/// Rotating pool, so that several paths can be live in one call's arguments.
///
/// A single static buffer would make every argument of a three-path call
/// point at the same string — which silently turns "read this, write that"
/// into "truncate the input and read the hole".
static const char* tmp_path(const char* name) {
    static char pool[4][512];
    static int next = 0;
    char* buf = pool[next];
    next = (next + 1) % 4;
    const char* dir = getenv("TMPDIR");
    if (!dir || !*dir) dir = "/tmp";
    snprintf(buf, 512, "%s/%s", dir, name);
    return buf;
}

static int write_wav(const char* path, const float* x, int n) {
    FILE* f = gf_wav_open_write(path, SR);
    if (!f) { printf("      cannot write %s\n", path); return 0; }
    const int ok = gf_wav_write(f, x, n);
    gf_wav_finish(f, n);
    fclose(f);
    if (!ok) printf("      short write to %s\n", path);
    return ok;
}

static int read_wav(const char* path, float* x, int n) {
    gf_wav_reader r = gf_wav_open_read(path);
    if (!r.file) return 0;
    const int got = gf_wav_read(&r, x, n);
    gf_wav_close(&r);
    return got;
}

// ─── Shared fixtures ────────────────────────────────────────────────────────

static float *g_ref, *g_near, *g_echo, *g_mic, *g_out, *g_room;

static int alloc_all(void) {
    g_ref  = (float*)malloc(sizeof(float) * FRAMES);
    g_near = (float*)malloc(sizeof(float) * FRAMES);
    g_echo = (float*)malloc(sizeof(float) * FRAMES);
    g_mic  = (float*)malloc(sizeof(float) * FRAMES);
    g_out  = (float*)malloc(sizeof(float) * FRAMES);
    g_room = (float*)malloc(sizeof(float) * ROOM_LEN);
    return g_ref && g_near && g_echo && g_mic && g_out && g_room;
}

static void build_take(void) {
    make_reference(g_ref, FRAMES);
    make_near(g_near, FRAMES);
    make_room(g_room, ROOM_LEN);
    convolve_delayed(g_ref, FRAMES, g_room, ROOM_LEN, DELAY, g_echo);
    for (int i = 0; i < FRAMES; i++) g_mic[i] = g_echo[i] + g_near[i];
}

// ─── 1. Delay ───────────────────────────────────────────────────────────────

static int test_delay(void) {
    build_take();
    printf("1. the estimator finds the delay\n");
    const int got = gf_aec_estimate_delay(g_mic, g_ref, FRAMES, SR);
    const int err = abs(got - DELAY);
    const int ok = err <= GF_AEC_BLOCK;
    printf("      true %d frames, found %d, error %d (%.1f ms)\n",
           DELAY, got, err, (double)err * 1000.0 / SR);
    printf(ok ? "   PASS\n" : "   FAIL\n");
    return ok;
}

// ─── 2. Cancellation ────────────────────────────────────────────────────────

/// How much of the speaker bleed survived, in dB. Higher is better.
static double run_and_measure(const char* tag, double* out_near_damage) {
    write_wav(tmp_path("gf_aec_mic.wav"), g_mic, FRAMES);
    write_wav(tmp_path("gf_aec_ref.wav"), g_ref, FRAMES);

    float reduction = 0.0f;
    const int rc = gf_aec_render_file(tmp_path("gf_aec_mic.wav"),
                                      tmp_path("gf_aec_ref.wav"),
                                      tmp_path("gf_aec_out.wav"), -1, &reduction);
    if (rc != GF_AEC_OK) {
        printf("      %s: render failed (%d)\n", tag, rc);
        return -999.0;
    }
    const int got = read_wav(tmp_path("gf_aec_out.wav"), g_out, FRAMES);
    if (got != FRAMES) {
        printf("      %s: wrote %d frames, wanted %d\n", tag, got, FRAMES);
        return -999.0;
    }

    // Skip the first 200 ms: that is the filter's startup and the WAV's own
    // 16-bit quantisation settling, neither of which is what is being tested.
    const int skip = SR / 5;
    const int n = FRAMES - skip;
    const double echo_in  = energy(g_echo + skip, n);
    const double echo_out = diff_energy(g_out + skip, g_near + skip, n);
    if (out_near_damage) *out_near_damage = echo_out;
    return to_db(echo_in / echo_out);
}

static int test_cancellation(void) {
    build_take();
    printf("2. speaker bleed is removed from the take\n");
    const double erle = run_and_measure("cancel", NULL);
    const int ok = erle >= 18.0;
    printf("      echo reduced by %.1f dB (want >= 18)\n", erle);
    printf(ok ? "   PASS\n" : "   FAIL\n");
    return ok;
}

// ─── 3. The musician survives ───────────────────────────────────────────────

static int test_near_preserved(void) {
    build_take();
    printf("3. with no echo present, the performance is left alone\n");

    // A take recorded on headphones: the microphone hears only the musician,
    // but the reference file still exists and still gets fed in.
    for (int i = 0; i < FRAMES; i++) g_mic[i] = g_near[i];

    // Check the mechanism as well as the outcome. The take survives because
    // the estimator recognised there was nothing to cancel, and saying so
    // here means a later regression reports which half broke.
    const int found = gf_aec_estimate_delay(g_mic, g_ref, FRAMES, SR);
    printf("      estimator reports %d (want -1, no relation)\n", found);

    write_wav(tmp_path("gf_aec_mic.wav"), g_mic, FRAMES);
    write_wav(tmp_path("gf_aec_ref.wav"), g_ref, FRAMES);

    float reduction = 0.0f;
    const int rc = gf_aec_render_file(tmp_path("gf_aec_mic.wav"),
                                      tmp_path("gf_aec_ref.wav"),
                                      tmp_path("gf_aec_out.wav"), -1, &reduction);
    if (rc != GF_AEC_OK) { printf("      render failed (%d)\n   FAIL\n", rc); return 0; }
    read_wav(tmp_path("gf_aec_out.wav"), g_out, FRAMES);

    const int skip = SR / 5;
    const int n = FRAMES - skip;
    const double kept = energy(g_near + skip, n);
    const double lost = diff_energy(g_out + skip, g_near + skip, n);
    const double damage_db = to_db(lost / kept);

    // -30 dB of damage is inaudible against the performance itself.
    const int ok = damage_db <= -30.0 && found == -1;
    printf("      performance altered by %.1f dB relative to itself (want <= -30)\n",
           damage_db);
    printf(ok ? "   PASS\n" : "   FAIL\n");

    return ok;
}

// ─── 4. The opening is cancelled too ────────────────────────────────────────

static int test_two_pass_opening(void) {
    build_take();
    printf("4. the opening is cancelled as well as the end\n");

    write_wav(tmp_path("gf_aec_mic.wav"), g_mic, FRAMES);
    write_wav(tmp_path("gf_aec_ref.wav"), g_ref, FRAMES);
    float reduction = 0.0f;
    if (gf_aec_render_file(tmp_path("gf_aec_mic.wav"),
                           tmp_path("gf_aec_ref.wav"),
                           tmp_path("gf_aec_out.wav"), -1,
                           &reduction) != GF_AEC_OK) {
        printf("      render failed\n   FAIL\n");
        return 0;
    }
    read_wav(tmp_path("gf_aec_out.wav"), g_out, FRAMES);

    // Second 1 through 3 — the count-in and first bars, which a single
    // adapting pass would still be converging through.
    const int a0 = SR, a1 = SR * 3;
    const int b0 = FRAMES - SR * 3, b1 = FRAMES - SR;
    const double open_db = to_db(energy(g_echo + a0, a1 - a0) /
                                 diff_energy(g_out + a0, g_near + a0, a1 - a0));
    const double end_db  = to_db(energy(g_echo + b0, b1 - b0) /
                                 diff_energy(g_out + b0, g_near + b0, b1 - b0));

    // The opening need not match the end exactly, but it must not be far
    // worse — that gap is precisely what the second pass exists to close.
    const int ok = open_db >= 15.0 && (end_db - open_db) <= 8.0;
    printf("      opening %.1f dB, end %.1f dB, gap %.1f dB (want opening >= 15, gap <= 8)\n",
           open_db, end_db, end_db - open_db);
    printf(ok ? "   PASS\n" : "   FAIL\n");
    return ok;
}

// ─── 5. Nothing to cancel ───────────────────────────────────────────────────

static int test_unrelated_reference(void) {
    build_take();
    printf("5. an unrelated reference leaves the take alone\n");

    // Monitoring on headphones: the reference holds real audio, but none of it
    // ever reached the microphone. The canceller must find nothing and do
    // nothing, rather than subtract a signal that was never there.
    for (int i = 0; i < FRAMES; i++) g_mic[i] = g_near[i];
    for (int i = 0; i < FRAMES; i++) g_ref[i] = 0.5f * noise();
    write_wav(tmp_path("gf_aec_mic.wav"), g_mic, FRAMES);
    write_wav(tmp_path("gf_aec_ref.wav"), g_ref, FRAMES);

    float reduction = 0.0f;
    if (gf_aec_render_file(tmp_path("gf_aec_mic.wav"),
                           tmp_path("gf_aec_ref.wav"),
                           tmp_path("gf_aec_out.wav"), -1,
                           &reduction) != GF_AEC_OK) {
        printf("      render failed\n   FAIL\n");
        return 0;
    }
    read_wav(tmp_path("gf_aec_out.wav"), g_out, FRAMES);

    const int skip = SR / 5;
    const int n = FRAMES - skip;
    const double damage_db = to_db(diff_energy(g_out + skip, g_near + skip, n) /
                                   energy(g_near + skip, n));
    const int ok = damage_db <= -25.0;
    printf("      take altered by %.1f dB (want <= -25), reported reduction %.1f dB\n",
           damage_db, (double)reduction);
    printf(ok ? "   PASS\n" : "   FAIL\n");
    return ok;
}

// ─── 6. How quiet the bleed can get and still be found ──────────────────────

static int test_quiet_bleed(void) {
    build_take();
    printf("6. quiet bleed is still found, and still removed\n");

    // The loud case above is the easy one. In a real room the musician is
    // close to the microphone and the phone is not, so the bleed can sit well
    // below the performance — and that is exactly where a detector tuned to
    // avoid false positives risks refusing to do anything at all. Scanning
    // the range records where the floor actually is, so a future change to
    // the threshold cannot quietly turn the feature off.
    const float scales[] = {1.0f, 0.3f, 0.1f, 0.03f};
    int ok = 1;
    for (int k = 0; k < 4; k++) {
        const float sc = scales[k];
        for (int i = 0; i < FRAMES; i++) g_mic[i] = sc * g_echo[i] + g_near[i];

        double scaled_echo = 0.0;
        for (int i = 0; i < FRAMES; i++) {
            const double v = (double)sc * g_echo[i];
            scaled_echo += v * v;
        }
        const double level = to_db(scaled_echo / energy(g_near, FRAMES));

        write_wav(tmp_path("gf_aec_mic.wav"), g_mic, FRAMES);
        write_wav(tmp_path("gf_aec_ref.wav"), g_ref, FRAMES);
        float reduction = 0.0f;
        if (gf_aec_render_file(tmp_path("gf_aec_mic.wav"),
                               tmp_path("gf_aec_ref.wav"),
                               tmp_path("gf_aec_out.wav"), -1,
                               &reduction) != GF_AEC_OK) {
            printf("      render failed\n");
            ok = 0;
            continue;
        }
        read_wav(tmp_path("gf_aec_out.wav"), g_out, FRAMES);

        const int skip = SR / 5;
        const int n = FRAMES - skip;
        double echo_in = 0.0;
        for (int i = skip; i < FRAMES; i++) {
            const double v = (double)sc * g_echo[i];
            echo_in += v * v;
        }
        const double erle =
            to_db(echo_in / diff_energy(g_out + skip, g_near + skip, n));

        printf("      bleed at %+6.1f dB -> removed %5.1f dB\n", level, erle);

        // Down to about 15 dB below the performance the canceller must still
        // earn its keep — that range is what the detection threshold in
        // gf_aec.c is tuned for, and a change that quietly gives it up should
        // fail here rather than on someone's recording. Quieter than that it
        // may decline, but it must never make the take worse than it found it.
        if (level >= -15.0 && erle < 12.0) ok = 0;
        if (erle < -1.0) ok = 0;
    }
    printf(ok ? "   PASS\n" : "   FAIL\n");
    return ok;
}

// ─── Entry point ────────────────────────────────────────────────────────────

int main(void) {
    printf("gf_aec_smoke_test — %d s take at %d Hz\n\n", SECONDS, SR);

    if (!alloc_all()) {
        fprintf(stderr, "gf_aec_smoke_test: out of memory\n");
        return 1;
    }
    build_take();

    printf("   echo is %.1f dB relative to the performance\n\n",
           to_db(energy(g_echo, FRAMES) / energy(g_near, FRAMES)));

    int ok = 1;
    ok &= test_delay();
    ok &= test_cancellation();
    ok &= test_near_preserved();
    ok &= test_two_pass_opening();
    ok &= test_unrelated_reference();
    ok &= test_quiet_bleed();

    printf(ok ? "\nALL TESTS PASSED\n" : "\nTESTS FAILED\n");
    return ok ? 0 : 1;
}
