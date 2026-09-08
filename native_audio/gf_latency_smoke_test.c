// gf_latency_smoke_test.c — Offline verification of the overdub alignment path.
//
// This is P0 of the Rehearsals plan (docs/dev/REHEARSALS.md §6.1): prove the
// measure → compensate → land-on-the-grid chain is correct *before* anyone
// plugs in a phone. It proves the maths on synthetic audio; the hardware
// question — what the round trip actually is on a given device and route — is
// what tomorrow's on-device probe answers.
//
// The simulation deliberately makes life hard for the estimator:
//   - a band-limited channel, because a phone speaker reproduces nothing below
//     ~150 Hz and a phone mic rolls off at the top;
//   - a room echo, an attenuated delayed copy that gives the correlator a
//     second, wrong peak to be tempted by;
//   - broadband noise at a realistic rehearsal-room level;
//   - a capture stream that starts at a different frame from playback, which
//     is the inter-device clock offset the OS cannot report and the whole
//     reason we measure end to end rather than adding up OS numbers.
//
// Checks:
//   1. the chirp is the expected length and fades in and out
//   2. the round trip is recovered within 1 ms across wired-to-Bluetooth
//      delays, at several capture-clock offsets
//   3. pure noise is *rejected*, not answered with a confident wrong number
//   4. gf_lat_align_take shifts and pads correctly
//   5. end to end: a note played exactly in time with what the player heard
//      lands on the beat after compensation
//
// Build: see CMakeLists.txt — target "gf_latency_smoke_test".
// Run  : ./build-smoke/gf_latency_smoke_test

#include "gf_latency.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define SR 48000

static int g_fails = 0;

static void check(int cond, const char* fmt, ...) {
    (void)fmt;
    if (!cond) g_fails++;
}

// ─── A deterministic pseudo-random source ────────────────────────────────────
// Fixed seed so a failure is always reproducible; rand() would make a flaky
// test that passes on re-run and teaches nothing.

static unsigned int g_rng = 12345u;
static float noise_sample(void) {
    g_rng = g_rng * 1103515245u + 12345u;
    return ((float)((g_rng >> 16) & 0x7FFF) / 16383.5f) - 1.0f;
}

// ─── A crude model of "speaker → air → microphone" ───────────────────────────

/// Two-pole bandpass, applied in series to approximate the passband a phone
/// speaker and microphone leave behind. Not accurate — just narrow enough that
/// an estimator relying on the chirp's full bandwidth would fail here.
typedef struct { float z1, z2; } OnePole;

static float highpass(OnePole* s, float x, float cutoff) {
    const float a = expf(-2.0f * (float)M_PI * cutoff / (float)SR);
    s->z1 = a * s->z1 + (1.0f - a) * x;   // low-passed copy
    return x - s->z1;                      // original minus lows = highs
}

static float lowpass(OnePole* s, float x, float cutoff) {
    const float a = expf(-2.0f * (float)M_PI * cutoff / (float)SR);
    s->z2 = a * s->z2 + (1.0f - a) * x;
    return s->z2;
}

/// Reads [play] at a fractional position by linear interpolation, so a delay
/// that is not a whole number of frames can be simulated. Real latency has no
/// reason to land on a frame boundary, and an estimator that only ever sees
/// integer delays in test is an estimator whose sub-frame path is untested.
static float sample_at(const float* play, int play_frames, double pos) {
    if (pos < 0.0 || pos >= (double)(play_frames - 1)) return 0.0f;
    const int i = (int)pos;
    const double f = pos - (double)i;
    return (float)((1.0 - f) * play[i] + f * play[i + 1]);
}

/// Builds the capture stream that the engine would see.
///
/// [play] is what the playback device emitted, indexed from playback frame 0.
/// The result is indexed from capture frame 0, where capture frame 0
/// corresponds to playback frame [cap_start_frame] — so a sound emitted at
/// playback frame P appears at capture index (P - cap_start_frame + delay).
///
/// [drift_ppm] follows the same convention as `gf_lat_result.drift_ppm`:
/// positive means the measured delay grows as the run proceeds, so the capture
/// falls progressively behind playback. Two crystals nominally at 48 kHz are
/// never exactly equal, and over a multi-second run the difference accumulates
/// into whole frames.
static void simulate_capture(const float* play, int play_frames,
                             float* cap, int cap_frames,
                             double delay_frames, long long cap_start_frame,
                             float noise_level, int add_echo, double drift_ppm) {
    OnePole hp = {0, 0}, lp = {0, 0};
    OnePole ehp = {0, 0}, elp = {0, 0};
    // Capture frame i reads playback position i*rate. A capture that falls
    // behind covers less playback material per frame, hence 1 - drift.
    const double rate = 1.0 - drift_ppm * 1e-6;

    for (int i = 0; i < cap_frames; i++) {
        // Which playback frame is heard at this capture frame.
        const double src = (double)i * rate + (double)cap_start_frame - delay_frames;
        float s = sample_at(play, play_frames, src);

        // Speaker and microphone passband.
        s = highpass(&hp, s, 180.0f);
        s = lowpass(&lp, s, 7000.0f);

        // A wall: the same sound again, later and quieter. This is what tempts
        // a naive correlator into answering with the reflection instead of the
        // direct path.
        if (add_echo) {
            const double esrc = src - 0.013 * SR;  // 13 ms
            float e = sample_at(play, play_frames, esrc);
            e = highpass(&ehp, e, 180.0f);
            e = lowpass(&elp, e, 7000.0f);
            s += 0.45f * e;
        }

        cap[i] = s + noise_level * noise_sample();
    }
}

// ─── Test 1: the measurement signal itself ───────────────────────────────────

static void test_chirp(void) {
    const int n = gf_lat_chirp_frames(SR);
    printf("  chirp: %d frames (%d ms at %d Hz)\n", n, GF_LAT_CHIRP_MS, SR);
    check(n == GF_LAT_CHIRP_MS * SR / 1000, "chirp length");

    float* chirp = (float*)calloc((size_t)n, sizeof(float));
    gf_lat_generate_chirp(chirp, SR);

    // The window must actually reach zero at both ends, or the edge becomes a
    // click that competes with the sweep.
    check(fabsf(chirp[0]) < 1e-4f, "fade in");
    check(fabsf(chirp[n - 1]) < 1e-4f, "fade out");
    if (fabsf(chirp[0]) >= 1e-4f || fabsf(chirp[n - 1]) >= 1e-4f) {
        printf("    FAIL: chirp edges not faded (%.5f .. %.5f)\n",
               chirp[0], chirp[n - 1]);
    }

    // And it must carry real energy in between.
    float peak = 0.0f;
    for (int i = 0; i < n; i++) if (fabsf(chirp[i]) > peak) peak = fabsf(chirp[i]);
    check(peak > 0.9f, "chirp amplitude");
    if (peak <= 0.9f) printf("    FAIL: chirp peak only %.3f\n", peak);

    free(chirp);
}

// ─── Test 2: recovering a known round trip ───────────────────────────────────

/// Runs one full measurement against a simulated device and returns the error
/// in frames, or INT_MAX-ish sentinel -1 if the run was rejected.
static int measure_error_ex(double true_delay_frames, long long cap_start_frame,
                            float noise_level, int add_echo, double drift_ppm,
                            float* out_jitter_ms, float* out_conf,
                            float* out_measured_ms, float* out_drift_ppm) {
    const int chirp_n = gf_lat_chirp_frames(SR);
    float* chirp = (float*)calloc((size_t)chirp_n, sizeof(float));
    gf_lat_generate_chirp(chirp, SR);

    gf_lat_emitter em;
    gf_lat_emitter_init(&em, chirp, SR);

    // Render what the playback device puts out over the whole run.
    const int play_frames = gf_lat_run_frames(SR) + SR;  // one second of tail
    float* play = (float*)calloc((size_t)play_frames, sizeof(float));
    const int block = 256;  // same block size the app runs
    for (int f = 0; f < play_frames; f += block) {
        const int n = (f + block <= play_frames) ? block : (play_frames - f);
        gf_lat_emitter_render(&em, play + f, n, f);
    }

    // Capture must cover the run plus the delay we are trying to find.
    const int cap_frames = play_frames;
    float* cap = (float*)calloc((size_t)cap_frames, sizeof(float));
    simulate_capture(play, play_frames, cap, cap_frames,
                     true_delay_frames, cap_start_frame, noise_level, add_echo,
                     drift_ppm);

    gf_lat_result res;
    const int ok = gf_lat_analyse_run(&em, cap, cap_frames, cap_start_frame,
                                      SR, &res);

    int err = -1;
    if (ok) {
        // With drift the true delay grows across the run, so the median shot
        // is compared against the delay at the middle of the run rather than
        // at its start.
        const double mid = (double)gf_lat_shot_frame(&em, GF_LAT_SHOTS / 2);
        const double true_at_mid = true_delay_frames + mid * drift_ppm * 1e-6;
        double d = (double)res.median_frames - true_at_mid;
        if (d < 0.0) d = -d;
        err = (int)(d + 0.5);
        if (out_jitter_ms) *out_jitter_ms = res.jitter_ms;
        if (out_conf) *out_conf = res.min_confidence;
        if (out_measured_ms) *out_measured_ms = res.median_ms;
        if (out_drift_ppm) *out_drift_ppm = res.drift_ppm;
    }

    free(cap);
    free(play);
    free(chirp);
    return ok ? err : -1;
}

/// The plain case: integer delay, no drift, generous signal-to-noise.
static int measure_error(int true_delay_frames, long long cap_start_frame,
                         float noise_level, int add_echo, float* out_jitter_ms,
                         float* out_conf) {
    return measure_error_ex((double)true_delay_frames, cap_start_frame,
                            noise_level, add_echo, 0.0,
                            out_jitter_ms, out_conf, NULL, NULL);
}

static void test_recovery(void) {
    // Wired headphones, Bluetooth, and the pathological end of Bluetooth.
    const float delays_ms[] = { 12.0f, 25.0f, 60.0f, 150.0f, 280.0f };
    // Capture starting before and after playback — the inter-device clock
    // offset. A sign error here would show up as a symmetric failure.
    const long long offsets[] = { 0, 5000, -3000, 41000 };

    const float tolerance_ms = 1.0f;
    const int tolerance_frames = gf_lat_ms_to_frames(tolerance_ms, SR);

    for (size_t d = 0; d < sizeof(delays_ms) / sizeof(delays_ms[0]); d++) {
        const int delay_frames = gf_lat_ms_to_frames(delays_ms[d], SR);
        for (size_t o = 0; o < sizeof(offsets) / sizeof(offsets[0]); o++) {
            float jitter = 0.0f, conf = 0.0f;
            const int err = measure_error(delay_frames, offsets[o],
                                          0.02f, 1, &jitter, &conf);
            if (err < 0) {
                printf("    FAIL: %.0f ms delay, offset %lld — run rejected\n",
                       delays_ms[d], offsets[o]);
                g_fails++;
                continue;
            }
            const float err_ms = 1000.0f * (float)err / (float)SR;
            if (err > tolerance_frames) {
                printf("    FAIL: %.0f ms delay, offset %lld — off by %.2f ms\n",
                       delays_ms[d], offsets[o], err_ms);
                g_fails++;
            } else if (o == 0) {
                printf("    %6.0f ms round trip: error %.3f ms, jitter %.3f ms, "
                       "confidence %.1f\n",
                       delays_ms[d], err_ms, jitter, conf);
            }
        }
    }
}

// ─── Test 2b: delays that do not land on a frame boundary ────────────────────

static void test_fractional_delay(void) {
    // Quarter-frame steps: nothing here is an exact number of samples, so the
    // integer peak alone can never be better than half a frame and the
    // sub-frame refinement has to carry the rest.
    const double delays[] = { 576.25, 1200.5, 2881.75, 7200.4 };
    const int tolerance_frames = gf_lat_ms_to_frames(1.0f, SR);

    for (size_t i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        float jitter = 0.0f, conf = 0.0f, measured = 0.0f;
        const int err = measure_error_ex(delays[i], 3000, 0.02f, 1, 0.0,
                                         &jitter, &conf, &measured, NULL);
        if (err < 0) {
            printf("    FAIL: fractional delay %.2f frames — run rejected\n",
                   delays[i]);
            g_fails++;
            continue;
        }
        printf("    %8.2f frames true -> %7.3f ms measured (error %.3f ms)\n",
               delays[i], measured,
               1000.0f * (float)err / (float)SR);
        if (err > tolerance_frames) {
            printf("    FAIL: fractional delay off by %d frames\n", err);
            g_fails++;
        }
    }
}

// ─── Test 2c: the two device clocks do not run at the same rate ──────────────

static void test_clock_drift(void) {
    // Two crystals nominally at 48 kHz differ by tens to hundreds of parts per
    // million. Over a 3-second run, 200 ppm is 600 us — about 29 frames of
    // spread between the first chirp and the last.
    const double drifts_ppm[] = { 0.0, 50.0, 200.0, -200.0 };
    const int tolerance_frames = gf_lat_ms_to_frames(1.5f, SR);

    for (size_t i = 0; i < sizeof(drifts_ppm) / sizeof(drifts_ppm[0]); i++) {
        float jitter = 0.0f, conf = 0.0f, measured = 0.0f, drift = 0.0f;
        const int err = measure_error_ex(2400.0, 0, 0.02f, 1, drifts_ppm[i],
                                         &jitter, &conf, &measured, &drift);
        if (err < 0) {
            printf("    FAIL: %.0f ppm drift — run rejected\n", drifts_ppm[i]);
            g_fails++;
            continue;
        }
        // What the drift costs over a real take is the number that decides
        // whether it needs handling at all.
        const float slide_ms_4min = drift * 1e-6f * 4.0f * 60.0f * 1000.0f;
        printf("    %+7.0f ppm true -> %+7.0f ppm measured; median error "
               "%.3f ms, jitter %.3f ms, 4-min take slides %+.0f ms\n",
               drifts_ppm[i], drift, 1000.0f * (float)err / (float)SR, jitter,
               slide_ms_4min);
        if (err > tolerance_frames) {
            printf("    FAIL: drift threw the median off by %d frames\n", err);
            g_fails++;
        }
        // The drift estimate is the whole point of the fit. A run of ±200 ppm
        // must come back as ±200 ppm and not, say, with the sign flipped —
        // resampling a take the wrong way would double the error instead of
        // removing it.
        if (fabs(drifts_ppm[i]) >= 50.0) {
            const double rel = fabs((double)drift - drifts_ppm[i]) /
                               fabs(drifts_ppm[i]);
            if (rel > 0.35) {
                printf("    FAIL: drift measured as %+.0f ppm, expected %+.0f\n",
                       drift, drifts_ppm[i]);
                g_fails++;
            }
        }
    }
}

// ─── Test 2d: a noisy room ───────────────────────────────────────────────────

static void test_low_snr(void) {
    // The chirp is emitted at 0.5 peak. Noise at 0.35 RMS is a loud rehearsal
    // room with people talking over the measurement — roughly 3 dB SNR, well
    // past what anyone would call comfortable.
    const float noise_levels[] = { 0.05f, 0.15f, 0.35f };
    const int tolerance_frames = gf_lat_ms_to_frames(1.0f, SR);

    for (size_t i = 0; i < sizeof(noise_levels) / sizeof(noise_levels[0]); i++) {
        float jitter = 0.0f, conf = 0.0f, measured = 0.0f;
        const int err = measure_error_ex(3600.0, 1024, noise_levels[i], 1, 0.0,
                                         &jitter, &conf, &measured, NULL);
        if (err < 0) {
            printf("    noise %.2f: run rejected (acceptable — it says so)\n",
                   noise_levels[i]);
            continue;
        }
        printf("    noise %.2f: error %.3f ms, confidence %.1f\n",
               noise_levels[i], 1000.0f * (float)err / (float)SR, conf);
        // The contract is not "always right" — it is "right, or honest about
        // failing". A confident wrong answer is the only unacceptable outcome.
        if (err > tolerance_frames) {
            printf("    FAIL: accepted a wrong answer at noise %.2f "
                   "(off by %d frames, confidence %.1f)\n",
                   noise_levels[i], err, conf);
            g_fails++;
        }
    }
}

// ─── Test 3: a failed measurement must report failure ────────────────────────

static void test_rejects_noise(void) {
    const int chirp_n = gf_lat_chirp_frames(SR);
    float* chirp = (float*)calloc((size_t)chirp_n, sizeof(float));
    gf_lat_generate_chirp(chirp, SR);

    gf_lat_emitter em;
    gf_lat_emitter_init(&em, chirp, SR);

    // A capture containing nothing but room noise — the microphone was muted,
    // or the speaker never played. The correct answer is "I don't know", and
    // silently returning a plausible-looking number would be the worst possible
    // outcome: every take in the session would be shifted by a random amount.
    const int cap_frames = gf_lat_run_frames(SR) + SR;
    float* cap = (float*)calloc((size_t)cap_frames, sizeof(float));
    for (int i = 0; i < cap_frames; i++) cap[i] = 0.05f * noise_sample();

    gf_lat_result res;
    const int ok = gf_lat_analyse_run(&em, cap, cap_frames, 0, SR, &res);
    if (ok) {
        printf("    FAIL: noise-only capture accepted as %.1f ms "
               "(confidence %.2f)\n", res.median_ms, res.min_confidence);
        g_fails++;
    } else {
        printf("    noise-only capture correctly rejected "
               "(%d/%d shots usable)\n", res.shots_found, GF_LAT_SHOTS);
    }

    free(cap);
    free(chirp);
}

// ─── Test 4: applying the compensation ───────────────────────────────────────

static void test_align(void) {
    float in[100];
    for (int i = 0; i < 100; i++) in[i] = (float)i;

    float out[100];
    const int written = gf_lat_align_take(in, 100, 10, out, 100);

    check(written == 90, "aligned length");
    check(out[0] == 10.0f, "shift amount");
    check(out[89] == 99.0f, "tail content");
    check(out[90] == 0.0f && out[99] == 0.0f, "zero padding");
    if (written != 90 || out[0] != 10.0f || out[90] != 0.0f) {
        printf("    FAIL: align wrote %d frames, out[0]=%.1f out[90]=%.1f\n",
               written, out[0], out[90]);
    }

    // A compensation longer than the take itself has no valid answer.
    check(gf_lat_align_take(in, 100, 100, out, 100) == 0, "over-long comp");
    check(gf_lat_align_take(in, 100, 200, out, 100) == 0, "over-long comp 2");
}

// ─── Test 5: end to end — does the note land on the beat? ────────────────────

static void test_lands_on_grid(void) {
    // 120 BPM, so one beat is half a second.
    const int beat_frames = SR / 2;
    const float true_rt_ms = 85.0f;             // a plausible Bluetooth-ish trip
    const int rt = gf_lat_ms_to_frames(true_rt_ms, SR);
    const long long cap_start = 7331;           // arbitrary clock offset

    // Step 1 — calibrate, exactly as the app would.
    const int chirp_n = gf_lat_chirp_frames(SR);
    float* chirp = (float*)calloc((size_t)chirp_n, sizeof(float));
    gf_lat_generate_chirp(chirp, SR);
    gf_lat_emitter em;
    gf_lat_emitter_init(&em, chirp, SR);

    const int play_frames = gf_lat_run_frames(SR) + SR;
    float* play = (float*)calloc((size_t)play_frames, sizeof(float));
    for (int f = 0; f < play_frames; f += 256) {
        const int n = (f + 256 <= play_frames) ? 256 : (play_frames - f);
        gf_lat_emitter_render(&em, play + f, n, f);
    }
    float* cap = (float*)calloc((size_t)play_frames, sizeof(float));
    simulate_capture(play, play_frames, cap, play_frames, rt, cap_start,
                     0.02f, 1, 0.0);

    gf_lat_result res;
    if (!gf_lat_analyse_run(&em, cap, play_frames, cap_start, SR, &res)) {
        printf("    FAIL: calibration run rejected\n");
        g_fails++;
        free(cap); free(play); free(chirp);
        return;
    }

    // Step 2 — the performance. Recording is armed at grid frame 0 (the
    // downbeat). The player hears the beats late by the output half of the
    // round trip and plays exactly in time with what they hear; their note
    // then takes the input half to reach us. Net: the note for beat b appears
    // in the capture at (b*beat + rt), on the capture clock.
    const int take_frames = 4 * beat_frames;
    const int cap_take_frames = take_frames + rt + beat_frames;
    float* take = (float*)calloc((size_t)cap_take_frames, sizeof(float));
    for (int b = 0; b < 4; b++) {
        const int at = b * beat_frames + rt;
        if (at < cap_take_frames) take[at] = 1.0f;  // an idealised transient
    }

    // Step 3 — compensate.
    float* aligned = (float*)calloc((size_t)take_frames, sizeof(float));
    gf_lat_align_take(take, cap_take_frames, res.median_frames,
                      aligned, take_frames);

    // Step 4 — where did the notes actually land?
    float worst_ms = 0.0f;
    for (int b = 0; b < 4; b++) {
        const int expect = b * beat_frames;
        // Find the transient nearest the beat.
        int found = -1;
        const int window = gf_lat_ms_to_frames(20.0f, SR);
        for (int d = 0; d < window; d++) {
            if (expect + d < take_frames && aligned[expect + d] > 0.5f) { found = expect + d; break; }
            if (expect - d >= 0 && aligned[expect - d] > 0.5f) { found = expect - d; break; }
        }
        if (found < 0) {
            printf("    FAIL: beat %d — no transient within 20 ms of the grid\n", b);
            g_fails++;
            continue;
        }
        const float off_ms = 1000.0f * (float)(found - expect) / (float)SR;
        if (fabsf(off_ms) > worst_ms) worst_ms = fabsf(off_ms);
    }

    printf("    measured %.2f ms (true %.2f ms); worst note lands %.3f ms "
           "off the beat\n", res.median_ms, true_rt_ms, worst_ms);

    // The plan's P0 target is well under 10 ms. Anything above 2 ms here would
    // mean the maths, not the hardware, is the problem.
    if (worst_ms > 2.0f) {
        printf("    FAIL: alignment error %.3f ms exceeds the 2 ms budget\n",
               worst_ms);
        g_fails++;
    }

    free(aligned); free(take); free(cap); free(play); free(chirp);
}

int main(void) {
    printf("gf_latency_smoke_test — overdub alignment (P0)\n\n");

    printf("1. measurement signal\n");
    test_chirp();

    printf("\n2. recovering a known round trip\n");
    test_recovery();

    printf("\n2b. delays between frame boundaries\n");
    test_fractional_delay();

    printf("\n2c. mismatched device clocks\n");
    test_clock_drift();

    printf("\n2d. a noisy room\n");
    test_low_snr();

    printf("\n3. rejecting an unmeasurable capture\n");
    test_rejects_noise();

    printf("\n4. applying the compensation\n");
    test_align();

    printf("\n5. end to end — landing on the grid\n");
    test_lands_on_grid();

    printf("\n");
    if (g_fails == 0) {
        printf("OK — all latency checks passed.\n");
        return 0;
    }
    printf("FAILED — %d check(s).\n", g_fails);
    return 1;
}
