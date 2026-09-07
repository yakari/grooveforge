// gf_latency_probe.c — Measures overdub latency on real audio hardware.
//
// The offline smoke test proves the maths. This proves the device: it opens a
// real playback device and a real capture device, emits the chirp train, and
// reports what the round trip actually is on this machine and this route.
//
// It deliberately mirrors GrooveForge's own audio setup — two *separate*
// devices at 48 kHz mono with 256-frame periods, not a duplex device — because
// the number we need depends on that arrangement. See the note on
// "what is actually being measured" below.
//
// Usage:
//   gf_latency_probe [--list] [--runs N] [--playback N] [--capture N]
//
//   --list       enumerate playback and capture devices and exit
//   --runs N     repeat the measurement N times (default 3) so the spread
//                between runs is visible, not just the spread within one
//   --playback N use playback device N from --list (default: system default)
//   --capture N  use capture device N from --list (default: system default)
//
// Pointing --capture at a "Monitor of ..." source turns the probe into an
// electrical loopback: it measures the same offset with the room, the speaker
// and the microphone taken out of the path. That is the right way to check the
// probe itself, and the right baseline to subtract when judging how much of an
// acoustic measurement is genuinely acoustic.
//
// Recording happens through the microphone, so this measures the *acoustic*
// path: the speaker must be audible to the mic. On headphones the mic hears
// nothing and the probe will correctly report a failed measurement — that is
// the expected result, not a bug, and it is exactly why the plan pairs this
// with OS-reported latency and a manual nudge for the headphone case.
//
// What is actually being measured
// -------------------------------
// The two devices are started at different moments, so at any instant their
// frame counters differ by a skew that has nothing to do with latency. A run
// reads BOTH counters at one instant and uses the difference as the origin for
// the analysis, which removes that skew by construction.
//
// What is left, and what the probe reports as `offset`, is the transport round
// trip: output buffering, the path from speaker to microphone, and input
// buffering. That is the compensation a take needs.
//
// The app can do the same thing — sample both counters together to get the
// skew, and add this measured offset — which is why the offset is the number
// worth persisting per route, and the skew is not: the skew changes every time
// a device restarts and is cheap to re-read, while the offset is a property of
// the route and costs a measurement.
//
// The counter skew is printed too, purely as a diagnostic, so it is visible
// that it was accounted for rather than ignored.

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "gf_latency.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
  #include <windows.h>
#else
  #include <time.h>
#endif

#define SR 48000
#define CHANNELS 1
#define PERIOD_FRAMES 256

// ─── Shared state between the two audio callbacks and main ───────────────────
//
// Both callbacks only ever advance their own counter and write their own
// buffer, so no lock is needed and none is taken — the audio thread rule in
// CLAUDE.md Rule 2 holds. `volatile` is enough here because main only reads
// these after both devices have been stopped.

static float* g_chirp = NULL;
static gf_lat_emitter g_em;

static volatile long long g_play_frame = 0;   // playback device frame counter
static volatile long long g_cap_frame  = 0;   // capture device frame counter

static float*  g_cap_buf = NULL;              // capture, indexed by cap frame
static int     g_cap_capacity = 0;

static volatile long long g_t_play0 = 0;      // monotonic ns at first callback
static volatile long long g_t_cap0  = 0;

static volatile int g_emitting = 0;           // 1 while the chirp train runs
static volatile long long g_play_base = 0;    // playback frame the run starts at
static volatile float g_cap_peak = 0.0f;      // input level, for the "is the
                                              // mic actually working" check

static long long monotonic_ns(void) {
#if defined(_WIN32)
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (long long)((double)c.QuadPart * 1e9 / (double)f.QuadPart);
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000000000LL + ts.tv_nsec;
#endif
}

// ─── Audio callbacks ─────────────────────────────────────────────────────────

static void playback_callback(ma_device* dev, void* out, const void* in,
                              ma_uint32 frames) {
    (void)dev; (void)in;
    float* o = (float*)out;

    if (g_t_play0 == 0) g_t_play0 = monotonic_ns();

    // Silence first: the emitter mixes into the buffer rather than replacing
    // it, matching how it will sit under the metronome in the real app.
    memset(o, 0, sizeof(float) * frames * CHANNELS);

    if (g_emitting) {
        // The emitter places chirp s at frame s*period on whatever axis it is
        // handed, so subtracting the run's base frame puts the train at
        // g_play_base + s*period on the device's own timeline. Before the base
        // is reached this is negative, which the emitter handles by simply not
        // overlapping any chirp yet.
        if (!gf_lat_emitter_render(&g_em, o, (int)frames,
                                   g_play_frame - g_play_base)) {
            g_emitting = 0;
        }
    }
    g_play_frame += frames;
}

static void capture_callback(ma_device* dev, void* out, const void* in,
                             ma_uint32 frames) {
    (void)dev; (void)out;
    const float* i = (const float*)in;

    if (g_t_cap0 == 0) g_t_cap0 = monotonic_ns();

    const long long at = g_cap_frame;
    if (at >= 0 && at + (long long)frames <= (long long)g_cap_capacity) {
        memcpy(g_cap_buf + at, i, sizeof(float) * frames * CHANNELS);
        float peak = g_cap_peak;
        for (ma_uint32 n = 0; n < frames; n++) {
            const float a = i[n] < 0 ? -i[n] : i[n];
            if (a > peak) peak = a;
        }
        g_cap_peak = peak;
    }
    g_cap_frame = at + frames;
}

// ─── Device listing ──────────────────────────────────────────────────────────

static int list_devices(void) {
    ma_context ctx;
    if (ma_context_init(NULL, 0, NULL, &ctx) != MA_SUCCESS) {
        fprintf(stderr, "could not initialise audio context\n");
        return 1;
    }
    ma_device_info* play; ma_uint32 n_play;
    ma_device_info* cap;  ma_uint32 n_cap;
    if (ma_context_get_devices(&ctx, &play, &n_play, &cap, &n_cap) != MA_SUCCESS) {
        fprintf(stderr, "could not enumerate devices\n");
        ma_context_uninit(&ctx);
        return 1;
    }
    printf("playback devices:\n");
    for (ma_uint32 i = 0; i < n_play; i++)
        printf("  [%u] %s%s\n", i, play[i].name, play[i].isDefault ? "  (default)" : "");
    printf("capture devices:\n");
    for (ma_uint32 i = 0; i < n_cap; i++)
        printf("  [%u] %s%s\n", i, cap[i].name, cap[i].isDefault ? "  (default)" : "");
    ma_context_uninit(&ctx);
    return 0;
}

// ─── One measurement ─────────────────────────────────────────────────────────

/// Runs the chirp train once and analyses the capture.
/// Returns 1 on a usable measurement, 0 otherwise.
static int run_once(ma_device* play_dev, ma_device* cap_dev, gf_lat_result* res,
                    float* out_skew_ms) {
    (void)play_dev; (void)cap_dev;

    // Both devices keep running between runs, so their frame counters are NOT
    // reset — that correspondence is the whole measurement. A run just marks
    // out a window on each timeline.
    // Both counters are read back to back on this one thread and then advanced
    // by the same lead, so the two bases name the same instant on their
    // respective clocks. That shared instant is what puts the emitter and the
    // capture buffer on a common axis.
    const long long lead = SR / 10;
    const long long cap_base = g_cap_frame + lead;
    const long long play_base = g_play_frame + lead;

    g_cap_peak = 0.0f;
    g_play_base = play_base;
    g_emitting = 1;

    // Wait for the train to finish, plus a full maximum round trip so the last
    // chirp has time to come back, plus a little slack.
    const int run_frames = gf_lat_run_frames(SR);
    const int tail = gf_lat_ms_to_frames(GF_LAT_MAX_ROUND_TRIP_MS, SR) + SR / 5;
    while (g_play_frame < play_base + run_frames + tail) ma_sleep(20);
    g_emitting = 0;

    const long long cap_span = g_cap_frame - cap_base;
    if (cap_span <= 0 || cap_base + cap_span > (long long)g_cap_capacity) {
        printf("  capture buffer exhausted\n");
        return 0;
    }
    if (g_cap_peak < 1e-4f) {
        printf("  input is silent (peak %.6f) — microphone muted, or "
               "permission denied?\n", (double)g_cap_peak);
        return 0;
    }

    // Origin zero: the slice is indexed from cap_base and the emitter counts
    // from play_base, and those two name the same instant, so chirp s is
    // expected at slice index s*period plus the round trip.
    const int ok = gf_lat_analyse_run(&g_em,
                                      g_cap_buf + cap_base, (int)cap_span,
                                      0, SR, res);

    // Diagnostic only: how far apart the counters were when the run began.
    // Already removed from the result above, by having been used as the origin.
    if (out_skew_ms) {
        *out_skew_ms = (float)(1000.0 * (double)(cap_base - play_base) / (double)SR);
    }
    return ok;
}

int main(int argc, char** argv) {
    int runs = 3;
    int play_idx = -1, cap_idx = -1;   // -1 = the system default device
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--list") == 0) return list_devices();
        if (strcmp(argv[i], "--runs") == 0 && i + 1 < argc) runs = atoi(argv[++i]);
        else if (strcmp(argv[i], "--playback") == 0 && i + 1 < argc) play_idx = atoi(argv[++i]);
        else if (strcmp(argv[i], "--capture") == 0 && i + 1 < argc) cap_idx = atoi(argv[++i]);
    }
    if (runs < 1) runs = 1;

    printf("gf_latency_probe — overdub latency on real hardware\n");
    printf("%d Hz mono, %d-frame periods, separate playback and capture "
           "devices (as the app runs them)\n\n", SR, PERIOD_FRAMES);

    // ── Signal ──────────────────────────────────────────────────────────────
    const int chirp_n = gf_lat_chirp_frames(SR);
    g_chirp = (float*)calloc((size_t)chirp_n, sizeof(float));
    gf_lat_generate_chirp(g_chirp, SR);
    gf_lat_emitter_init(&g_em, g_chirp, SR);

    // ── Capture buffer: the whole session, so nothing is ever reallocated
    //    while a callback might be running.
    const int per_run = gf_lat_run_frames(SR)
                      + gf_lat_ms_to_frames(GF_LAT_MAX_ROUND_TRIP_MS, SR)
                      + SR;
    g_cap_capacity = per_run * (runs + 1) + SR;
    g_cap_buf = (float*)calloc((size_t)g_cap_capacity, sizeof(float));
    if (!g_cap_buf) { fprintf(stderr, "out of memory\n"); return 1; }

    // ── Devices ─────────────────────────────────────────────────────────────
    ma_context ctx;
    if (ma_context_init(NULL, 0, NULL, &ctx) != MA_SUCCESS) {
        fprintf(stderr, "could not initialise audio context\n");
        return 1;
    }

    // Resolve any explicit device indices against the same enumeration --list
    // prints, so the numbers a user reads there are the numbers they can pass.
    ma_device_id play_id, cap_id;
    int have_play_id = 0, have_cap_id = 0;
    if (play_idx >= 0 || cap_idx >= 0) {
        ma_device_info* pl; ma_uint32 n_pl;
        ma_device_info* cp; ma_uint32 n_cp;
        if (ma_context_get_devices(&ctx, &pl, &n_pl, &cp, &n_cp) == MA_SUCCESS) {
            if (play_idx >= 0 && (ma_uint32)play_idx < n_pl) {
                play_id = pl[play_idx].id; have_play_id = 1;
            } else if (play_idx >= 0) {
                fprintf(stderr, "no playback device %d\n", play_idx); return 1;
            }
            if (cap_idx >= 0 && (ma_uint32)cap_idx < n_cp) {
                cap_id = cp[cap_idx].id; have_cap_id = 1;
            } else if (cap_idx >= 0) {
                fprintf(stderr, "no capture device %d\n", cap_idx); return 1;
            }
        }
    }

    ma_device_config cap_cfg = ma_device_config_init(ma_device_type_capture);
    cap_cfg.capture.format = ma_format_f32;
    cap_cfg.capture.channels = CHANNELS;
    cap_cfg.sampleRate = SR;
    cap_cfg.periodSizeInFrames = PERIOD_FRAMES;
    cap_cfg.periods = 2;
    cap_cfg.performanceProfile = ma_performance_profile_low_latency;
    cap_cfg.dataCallback = capture_callback;
    if (have_cap_id) cap_cfg.capture.pDeviceID = &cap_id;

    ma_device cap_dev;
    if (ma_device_init(&ctx, &cap_cfg, &cap_dev) != MA_SUCCESS) {
        fprintf(stderr, "could not open the capture device\n");
        ma_context_uninit(&ctx);
        return 1;
    }

    ma_device_config play_cfg = ma_device_config_init(ma_device_type_playback);
    play_cfg.playback.format = ma_format_f32;
    play_cfg.playback.channels = CHANNELS;
    play_cfg.sampleRate = SR;
    play_cfg.periodSizeInFrames = PERIOD_FRAMES;
    play_cfg.periods = 2;
    play_cfg.performanceProfile = ma_performance_profile_low_latency;
    play_cfg.dataCallback = playback_callback;
    if (have_play_id) play_cfg.playback.pDeviceID = &play_id;

    ma_device play_dev;
    if (ma_device_init(&ctx, &play_cfg, &play_dev) != MA_SUCCESS) {
        fprintf(stderr, "could not open the playback device\n");
        ma_device_uninit(&cap_dev);
        ma_context_uninit(&ctx);
        return 1;
    }

    printf("playback: %s\ncapture : %s\n\n", play_dev.playback.name,
           cap_dev.capture.name);
    printf("Point the speaker at the microphone and keep the room quiet.\n");
    printf("On headphones the mic hears nothing and the run will be rejected — "
           "that is the correct answer, not a failure.\n\n");

    ma_device_start(&cap_dev);
    ma_device_start(&play_dev);
    ma_sleep(300);  // let both settle before the first chirp

    int good = 0;
    for (int r = 0; r < runs; r++) {
        gf_lat_result res;
        float skew_ms = 0.0f;
        printf("run %d/%d ...\n", r + 1, runs);
        if (!run_once(&play_dev, &cap_dev, &res, &skew_ms)) {
            printf("  no usable measurement\n\n");
            continue;
        }
        good++;
        printf("  round trip      %8.2f ms  (%d frames) — this is the "
               "compensation\n", res.median_ms, res.median_frames);
        printf("  counter skew    %8.2f ms  (diagnostic, not part of the result)\n",
               skew_ms);
        // A bit-exact loopback leaves nothing for the runner-up peak, so the
        // ratio runs to six figures. Printing that verbatim looks like a bug.
        if (res.min_confidence > 999.0f)
            printf("  jitter          %8.2f ms   confidence >999   shots %d/%d\n",
                   res.jitter_ms, res.shots_found, GF_LAT_SHOTS);
        else
            printf("  jitter          %8.2f ms   confidence %.1f   shots %d/%d\n",
                   res.jitter_ms, (double)res.min_confidence, res.shots_found,
                   GF_LAT_SHOTS);
        printf("  clock drift     %+8.1f ppm — a 4-minute take would slide "
               "%+.0f ms\n\n",
               (double)res.drift_ppm,
               (double)res.drift_frames_per_minute * 4.0 * 1000.0 / SR);
    }

    ma_device_stop(&play_dev);
    ma_device_stop(&cap_dev);
    ma_device_uninit(&play_dev);
    ma_device_uninit(&cap_dev);
    ma_context_uninit(&ctx);
    free(g_cap_buf);
    free(g_chirp);

    printf("%d of %d runs produced a measurement.\n", good, runs);
    return good > 0 ? 0 : 1;
}
