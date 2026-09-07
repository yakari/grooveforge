// gf_rehearsal_smoke_test.c — Offline verification of the rehearsal engine.
//
// P1 of the Rehearsals plan (docs/dev/REHEARSALS.md). Everything here runs
// without an audio device: takes are written to disk, streamed back through
// the engine's offline render path, and the mix is inspected sample by sample.
//
// What it checks:
//   1. grid arithmetic — frames per beat and per bar
//   2. WAV round trip — a take written by the engine reads back identically
//   3. alignment — two takes with transients at known grid frames land on
//      exactly those frames in the mix, which is the whole point of the engine
//   4. gain and mute
//   5. metronome — clicks on every beat, a different one on the downbeat
//   6. count-in — the transport starts negative, plays nothing until it
//      crosses zero, and crosses it after exactly the requested bars
//   7. recording — captured audio is shifted earlier by the latency
//      compensation, so what the player performed on the downbeat lands at
//      frame 0 of the take
//
// Build: see CMakeLists.txt — target "gf_rehearsal_smoke_test".
// Run  : ./build-smoke/gf_rehearsal_smoke_test [work_dir]

#include "gf_rehearsal.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SR 48000
#define BLOCK 256

static int g_fails = 0;
static char g_dir[512] = "/tmp";

static void fail(const char* fmt, ...) { (void)fmt; g_fails++; }

static const char* path_for(const char* name) {
    static char buf[1024];
    snprintf(buf, sizeof(buf), "%s/%s", g_dir, name);
    return buf;
}

// ─── Test-side WAV helpers ───────────────────────────────────────────────────
//
// Deliberately written here rather than reused from the engine: a test that
// reads files with the same code that wrote them would pass even if both
// agreed on a wrong layout.

static void put_u32(unsigned char* p, unsigned int v) {
    p[0] = (unsigned char)(v & 0xFF);
    p[1] = (unsigned char)((v >> 8) & 0xFF);
    p[2] = (unsigned char)((v >> 16) & 0xFF);
    p[3] = (unsigned char)((v >> 24) & 0xFF);
}

/// Writes a mono 16-bit WAV with a plain 44-byte header.
static int write_wav(const char* path, const float* data, int frames) {
    FILE* f = fopen(path, "wb");
    if (!f) return 0;
    unsigned char h[44];
    memcpy(h, "RIFF", 4);
    put_u32(h + 4, (unsigned int)(36 + frames * 2));
    memcpy(h + 8, "WAVEfmt ", 8);
    put_u32(h + 16, 16);
    h[20] = 1; h[21] = 0; h[22] = 1; h[23] = 0;
    put_u32(h + 24, SR);
    put_u32(h + 28, SR * 2);
    h[32] = 2; h[33] = 0; h[34] = 16; h[35] = 0;
    memcpy(h + 36, "data", 4);
    put_u32(h + 40, (unsigned int)(frames * 2));
    fwrite(h, 1, 44, f);
    for (int i = 0; i < frames; i++) {
        float v = data[i];
        if (v > 1.0f) v = 1.0f;
        if (v < -1.0f) v = -1.0f;
        const short s = (short)(v * 32767.0f);
        fputc(s & 0xFF, f);
        fputc((s >> 8) & 0xFF, f);
    }
    fclose(f);
    return 1;
}

/// Reads a mono 16-bit WAV written with a 44-byte header. Returns frames read.
static int read_wav(const char* path, float* out, int max_frames) {
    FILE* f = fopen(path, "rb");
    if (!f) return 0;
    fseek(f, 0, SEEK_END);
    const long size = ftell(f);
    if (size <= 44) { fclose(f); return 0; }
    fseek(f, 44, SEEK_SET);
    int frames = (int)((size - 44) / 2);
    if (frames > max_frames) frames = max_frames;
    for (int i = 0; i < frames; i++) {
        const int lo = fgetc(f), hi = fgetc(f);
        if (lo < 0 || hi < 0) { frames = i; break; }
        out[i] = (float)(short)((hi << 8) | lo) / 32768.0f;
    }
    fclose(f);
    return frames;
}

/// Index of the loudest sample in [buf], or -1 if nothing exceeds [threshold].
static int peak_index(const float* buf, int frames, float threshold) {
    int best = -1;
    float best_v = threshold;
    for (int i = 0; i < frames; i++) {
        const float a = fabsf(buf[i]);
        if (a > best_v) { best_v = a; best = i; }
    }
    return best;
}

/// Renders [frames] through the offline path into [out].
static void render_all(float* out, int frames) {
    int done = 0;
    while (done < frames) {
        const int n = (frames - done) < BLOCK ? (frames - done) : BLOCK;
        gf_reh_render_offline(out + done, NULL, n);
        done += n;
    }
}

// ─── 1. Grid arithmetic ──────────────────────────────────────────────────────

static void test_grid(void) {
    gf_reh_set_grid(120.0, 4, 4);
    const int fpb = gf_reh_frames_per_beat();
    const int fbar = gf_reh_frames_per_bar();
    printf("  120 BPM 4/4: %d frames/beat, %d frames/bar\n", fpb, fbar);
    if (fpb != SR / 2) { printf("    FAIL: expected %d frames/beat\n", SR / 2); fail(""); }
    if (fbar != SR * 2) { printf("    FAIL: expected %d frames/bar\n", SR * 2); fail(""); }

    // 3/4 at 90 BPM — a waltz, and a check that the bar is not hard-wired to 4.
    gf_reh_set_grid(90.0, 3, 4);
    if (gf_reh_frames_per_bar() != gf_reh_frames_per_beat() * 3) {
        printf("    FAIL: 3/4 bar is not three beats\n");
        fail("");
    }
    gf_reh_set_grid(120.0, 4, 4);
}

// ─── 3. Alignment ────────────────────────────────────────────────────────────

static void test_alignment(void) {
    const int len = SR * 4;               // 4 seconds = 2 bars at 120 BPM
    float* a = (float*)calloc((size_t)len, sizeof(float));
    float* b = (float*)calloc((size_t)len, sizeof(float));

    // One transient per take, at different, known grid frames.
    const int at_a = SR / 2;              // beat 2
    const int at_b = SR * 3;              // beat 7
    a[at_a] = 0.9f;
    b[at_b] = 0.8f;
    write_wav(path_for("gf_reh_a.wav"), a, len);
    write_wav(path_for("gf_reh_b.wav"), b, len);

    gf_reh_clear_tracks();
    gf_reh_set_metronome(0, 0.0f);        // clicks would drown the transients
    const int ta = gf_reh_add_track(path_for("gf_reh_a.wav"));
    const int tb = gf_reh_add_track(path_for("gf_reh_b.wav"));
    if (ta < 0 || tb < 0) {
        printf("    FAIL: could not load takes (%d, %d)\n", ta, tb);
        fail("");
        free(a); free(b);
        return;
    }
    if (gf_reh_track_frames(ta) != len) {
        printf("    FAIL: track length %lld, expected %d\n",
               (long long)gf_reh_track_frames(ta), len);
        fail("");
    }

    float* mix = (float*)calloc((size_t)len, sizeof(float));
    gf_reh_play(0);
    render_all(mix, len);
    gf_reh_stop();

    // Each transient must appear at exactly its own grid frame. Off-by-a-block
    // is the failure this whole engine exists to prevent, so the tolerance is
    // zero frames rather than "close enough".
    int found_a = -1, found_b = -1;
    for (int i = 0; i < len; i++) {
        if (fabsf(mix[i]) > 0.85f) found_a = i;
        else if (fabsf(mix[i]) > 0.7f) found_b = i;
    }
    printf("    take A transient at %d (expected %d)\n", found_a, at_a);
    printf("    take B transient at %d (expected %d)\n", found_b, at_b);
    if (found_a != at_a) { printf("    FAIL: take A misaligned\n"); fail(""); }
    if (found_b != at_b) { printf("    FAIL: take B misaligned\n"); fail(""); }

    // ── 4. Gain and mute ────────────────────────────────────────────────────
    gf_reh_set_track_gain(ta, 0.5f);
    memset(mix, 0, sizeof(float) * (size_t)len);
    gf_reh_play(0);
    render_all(mix, len);
    gf_reh_stop();
    const float halved = fabsf(mix[at_a]);
    if (fabsf(halved - 0.45f) > 0.01f) {
        printf("    FAIL: gain 0.5 gave %.3f, expected ~0.45\n", halved);
        fail("");
    }

    gf_reh_set_track_gain(ta, 1.0f);
    gf_reh_set_track_mute(ta, 1);
    memset(mix, 0, sizeof(float) * (size_t)len);
    gf_reh_play(0);
    render_all(mix, len);
    gf_reh_stop();
    if (fabsf(mix[at_a]) > 0.001f) {
        printf("    FAIL: muted track still audible (%.4f)\n", mix[at_a]);
        fail("");
    }
    if (fabsf(mix[at_b]) < 0.7f) {
        printf("    FAIL: muting one track silenced the other\n");
        fail("");
    }
    printf("    gain and mute behave\n");

    gf_reh_set_track_mute(ta, 0);
    gf_reh_clear_tracks();
    free(mix); free(a); free(b);
}

// ─── 5. Metronome ────────────────────────────────────────────────────────────

static void test_metronome(void) {
    gf_reh_clear_tracks();
    gf_reh_set_grid(120.0, 4, 4);
    gf_reh_set_metronome(1, 1.0f);

    const int fpb = gf_reh_frames_per_beat();
    const int len = fpb * 8;              // two bars
    float* mix = (float*)calloc((size_t)len, sizeof(float));
    gf_reh_play(0);
    render_all(mix, len);
    gf_reh_stop();

    // A click must start within a frame or two of every beat, and the two
    // downbeats must be distinguishable from the beats between them.
    for (int beat = 0; beat < 8; beat++) {
        const int at = beat * fpb;
        float energy = 0.0f;
        for (int i = at; i < at + 200 && i < len; i++) energy += fabsf(mix[i]);
        if (energy < 0.5f) {
            printf("    FAIL: no click at beat %d (frame %d), energy %.3f\n",
                   beat, at, energy);
            fail("");
        }
    }

    // The downbeat click is a different pitch, so the two differ in waveform
    // even where their levels match — compare a short window.
    float diff = 0.0f;
    for (int i = 0; i < 200; i++) diff += fabsf(mix[i] - mix[fpb + i]);
    printf("    clicks on all 8 beats; downbeat differs from beat 2 by %.1f\n", diff);
    if (diff < 1.0f) {
        printf("    FAIL: downbeat click is not distinguishable\n");
        fail("");
    }

    // Silence between clicks: a click that rang for a whole beat would make
    // the grid unreadable.
    const int mid = fpb / 2;
    if (fabsf(mix[mid]) > 0.02f) {
        printf("    FAIL: click still ringing mid-beat (%.4f)\n", mix[mid]);
        fail("");
    }
    free(mix);
    gf_reh_set_metronome(0, 0.0f);
}

// ─── 6. Count-in ─────────────────────────────────────────────────────────────

static void test_count_in(void) {
    const int len = SR * 2;
    float* a = (float*)calloc((size_t)len, sizeof(float));
    a[0] = 0.9f;                          // transient exactly on the downbeat
    write_wav(path_for("gf_reh_c.wav"), a, len);

    gf_reh_clear_tracks();
    gf_reh_set_metronome(0, 0.0f);
    gf_reh_set_grid(120.0, 4, 4);
    const int t = gf_reh_add_track(path_for("gf_reh_c.wav"));
    if (t < 0) { printf("    FAIL: load failed\n"); fail(""); free(a); return; }

    const int bars = 2;
    const int fbar = gf_reh_frames_per_bar();
    gf_reh_record(path_for("gf_reh_rec_ci.wav"), 0, bars);

    if (gf_reh_position() != -(int64_t)bars * fbar) {
        printf("    FAIL: count-in start %lld, expected %d\n",
               (long long)gf_reh_position(), -bars * fbar);
        fail("");
    }
    if (gf_reh_state() != GF_REH_COUNT_IN) {
        printf("    FAIL: state %d, expected COUNT_IN\n", gf_reh_state());
        fail("");
    }

    // Render the count-in and one bar past it.
    const int total = bars * fbar + fbar;
    float* mix = (float*)calloc((size_t)total, sizeof(float));
    render_all(mix, total);

    // Nothing from the take may sound during the count-in.
    int leaked = -1;
    for (int i = 0; i < bars * fbar; i++) {
        if (fabsf(mix[i]) > 0.01f) { leaked = i; break; }
    }
    if (leaked >= 0) {
        printf("    FAIL: take audible during count-in at frame %d\n", leaked);
        fail("");
    }

    // And the downbeat transient must land on the first frame after it.
    const int at = peak_index(mix, total, 0.5f);
    printf("    count-in %d bars (%d frames); downbeat transient at %d\n",
           bars, bars * fbar, at);
    if (at != bars * fbar) {
        printf("    FAIL: transient at %d, expected %d\n", at, bars * fbar);
        fail("");
    }
    if (gf_reh_state() != GF_REH_RECORDING) {
        printf("    FAIL: state %d after count-in, expected RECORDING\n",
               gf_reh_state());
        fail("");
    }
    gf_reh_stop();
    gf_reh_clear_tracks();
    free(mix); free(a);
}

// ─── 7. Recording alignment ──────────────────────────────────────────────────

static void test_record_alignment(void) {
    gf_reh_clear_tracks();
    gf_reh_set_metronome(0, 0.0f);
    gf_reh_set_grid(120.0, 4, 4);

    // A round trip of 30 ms, close to what the phone actually measured in P0.
    const int comp = (int)(0.030 * SR);
    const int impulse_at = comp + 1000;   // 1000 frames after the downbeat
    const int feed_frames = SR;           // one second of input

    gf_reh_record(path_for("gf_reh_rec.wav"), comp, 0);
    if (gf_reh_state() != GF_REH_RECORDING) {
        printf("    FAIL: no count-in should start recording immediately\n");
        fail("");
    }

    float out[BLOCK];
    float in[BLOCK];
    int fed = 0;
    while (fed < feed_frames) {
        // The last block is short, so exactly feed_frames are fed. Rounding up
        // to a whole block instead would make the expected take length wrong
        // by the remainder and turn a correct engine into a failing test.
        const int n = (feed_frames - fed) < BLOCK ? (feed_frames - fed) : BLOCK;
        gf_reh_render_offline(out, NULL, n);
        // The input the engine sees, counted from the moment the transport
        // crossed the downbeat — exactly what rec_input_seen counts.
        for (int i = 0; i < n; i++) {
            in[i] = ((fed + i) == impulse_at) ? 0.9f : 0.0f;
        }
        gf_reh_feed_input(in, n);
        fed += n;
    }
    gf_reh_stop();

    float* take = (float*)calloc((size_t)feed_frames, sizeof(float));
    const int got = read_wav(path_for("gf_reh_rec.wav"), take, feed_frames);
    const int at = peak_index(take, got, 0.5f);

    printf("    compensation %d frames (%.1f ms); transient fed at input %d, "
           "written at take frame %d\n",
           comp, 1000.0 * comp / SR, impulse_at, at);

    // The player performed 1000 frames after the downbeat, so that is where it
    // must sit in the take — the captured position minus the round trip.
    if (at != impulse_at - comp) {
        printf("    FAIL: expected take frame %d, got %d\n",
               impulse_at - comp, at);
        fail("");
    }
    if (got != feed_frames - comp) {
        printf("    FAIL: take is %d frames, expected %d\n",
               got, feed_frames - comp);
        fail("");
    }
    free(take);
}

// ─── 2. WAV round trip ───────────────────────────────────────────────────────

static void test_wav_roundtrip(void) {
    // A take the engine wrote must read back through the engine's own loader,
    // including a length that is not a whole number of blocks.
    const int len = 12345;
    float* src = (float*)calloc((size_t)len, sizeof(float));
    for (int i = 0; i < len; i++) src[i] = sinf((float)i * 0.01f) * 0.5f;
    write_wav(path_for("gf_reh_rt.wav"), src, len);

    gf_reh_clear_tracks();
    const int t = gf_reh_add_track(path_for("gf_reh_rt.wav"));
    if (t < 0) {
        printf("    FAIL: engine could not load its own WAV (%d)\n", t);
        fail("");
        free(src);
        return;
    }
    if (gf_reh_track_frames(t) != len) {
        printf("    FAIL: length %lld, expected %d\n",
               (long long)gf_reh_track_frames(t), len);
        fail("");
    }

    gf_reh_set_metronome(0, 0.0f);
    float* mix = (float*)calloc((size_t)len, sizeof(float));
    gf_reh_play(0);
    render_all(mix, len);
    gf_reh_stop();

    // 16-bit quantisation is the only difference allowed.
    float worst = 0.0f;
    for (int i = 0; i < len; i++) {
        const float d = fabsf(mix[i] - src[i]);
        if (d > worst) worst = d;
    }
    printf("    %d frames round-tripped, worst sample error %.6f\n", len, worst);
    if (worst > 0.0001f) {
        printf("    FAIL: round trip error %.6f exceeds 16-bit quantisation\n",
               worst);
        fail("");
    }

    // A non-WAV file must be refused rather than streamed as noise.
    FILE* junk = fopen(path_for("gf_reh_junk.bin"), "wb");
    if (junk) { fwrite("not a wav at all", 1, 16, junk); fclose(junk); }
    if (gf_reh_add_track(path_for("gf_reh_junk.bin")) >= 0) {
        printf("    FAIL: a non-WAV file was accepted as a take\n");
        fail("");
    }

    gf_reh_clear_tracks();
    free(mix); free(src);
}

int main(int argc, char** argv) {
    if (argc > 1) snprintf(g_dir, sizeof(g_dir), "%s", argv[1]);
    printf("gf_rehearsal_smoke_test — multitrack rehearsal engine (P1)\n");
    printf("working directory: %s\n\n", g_dir);

    if (gf_reh_create(SR) != 0) {
        printf("FAILED — engine would not start.\n");
        return 1;
    }

    printf("1. grid arithmetic\n");            test_grid();
    printf("\n2. WAV round trip\n");           test_wav_roundtrip();
    printf("\n3-4. alignment, gain and mute\n"); test_alignment();
    printf("\n5. metronome\n");                test_metronome();
    printf("\n6. count-in\n");                 test_count_in();
    printf("\n7. recording alignment\n");      test_record_alignment();

    gf_reh_destroy();

    printf("\n");
    if (g_fails == 0) {
        printf("OK — all rehearsal engine checks passed.\n");
        return 0;
    }
    printf("FAILED — %d check(s).\n", g_fails);
    return 1;
}
