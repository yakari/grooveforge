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
#include "gf_media_import.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SR 48000
#define BLOCK 256

static int g_fails = 0;
static char g_dir[512] = "/tmp";

static void fail(const char* fmt, ...) { (void)fmt; g_fails++; }

/// Builds a path under the working directory.
///
/// Rotates through a small pool of buffers rather than reusing one: a single
/// static buffer means two calls in the same expression — `f(path_for(a),
/// path_for(b))` — silently return the *same* string, and the caller ends up
/// reading and writing one file. Which is exactly what happened here first
/// time round.
static const char* path_for(const char* name) {
    static char pool[4][1024];
    static int next = 0;
    char* buf = pool[next];
    next = (next + 1) % 4;
    snprintf(buf, 1024, "%s/%s", g_dir, name);
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

// ─── 8. Anchoring the grid inside a recording ────────────────────────────────

static void test_track_offset(void) {
    // A "master": four seconds of silence with a transient 1.5 s in, standing
    // for a tune whose first downbeat arrives after an intro.
    const int len = SR * 4;
    const int downbeat_at = SR * 3 / 2;          // 1.5 s into the recording
    float* master = (float*)calloc((size_t)len, sizeof(float));
    master[downbeat_at] = 0.9f;
    // A second transient exactly one bar (2 s at 120 BPM) later.
    master[downbeat_at + SR * 2] = 0.8f;
    write_wav(path_for("gf_reh_master.wav"), master, len);

    gf_reh_clear_tracks();
    gf_reh_set_metronome(0, 0.0f);
    gf_reh_set_grid(120.0, 4, 4);
    const int t = gf_reh_add_track(path_for("gf_reh_master.wav"));
    if (t < 0) { printf("    FAIL: master would not load\n"); fail(""); free(master); return; }

    // Anchor grid frame 0 to the first downbeat.
    gf_reh_set_track_offset(t, downbeat_at);

    const int span = SR * 2 + 1000;
    float* mix = (float*)calloc((size_t)span, sizeof(float));
    gf_reh_play(0);
    render_all(mix, span);
    gf_reh_stop();

    // The downbeat must now be at grid frame 0, and the next bar at exactly
    // one bar's worth of frames.
    const int first = peak_index(mix, 100, 0.5f);
    printf("    downbeat %d frames into the file -> grid frame %d\n",
           downbeat_at, first);
    if (first != 0) {
        printf("    FAIL: expected the downbeat at grid frame 0, got %d\n", first);
        fail("");
    }
    int second = -1;
    for (int i = 100; i < span; i++) {
        if (fabsf(mix[i]) > 0.7f) { second = i; break; }
    }
    const int fbar = gf_reh_frames_per_bar();
    printf("    next transient at grid frame %d (one bar = %d)\n", second, fbar);
    if (second != fbar) {
        printf("    FAIL: second transient at %d, expected %d\n", second, fbar);
        fail("");
    }

    // Audio before the offset is not played: there is no grid there.
    gf_reh_set_track_offset(t, downbeat_at);
    memset(mix, 0, sizeof(float) * (size_t)span);
    gf_reh_play(0);
    render_all(mix, 200);
    gf_reh_stop();

    gf_reh_clear_tracks();
    free(mix); free(master);
}

// ─── 9. Importing a recording ────────────────────────────────────────────────

static void test_media_import(void) {
    // A stereo 44.1 kHz WAV, so the import has real work to do: fold to mono
    // and resample to the engine's rate. Written by hand because write_wav
    // only does mono at SR.
    const int src_rate = 44100;
    const int src_frames = src_rate * 2;         // two seconds
    const char* src = path_for("gf_reh_src_stereo.wav");
    FILE* f = fopen(src, "wb");
    if (!f) { printf("    FAIL: cannot write source\n"); fail(""); return; }
    unsigned char h[44];
    memcpy(h, "RIFF", 4);
    put_u32(h + 4, (unsigned int)(36 + src_frames * 4));
    memcpy(h + 8, "WAVEfmt ", 8);
    put_u32(h + 16, 16);
    h[20] = 1; h[21] = 0; h[22] = 2; h[23] = 0;   // stereo
    put_u32(h + 24, (unsigned int)src_rate);
    put_u32(h + 28, (unsigned int)(src_rate * 4));
    h[32] = 4; h[33] = 0; h[34] = 16; h[35] = 0;
    memcpy(h + 36, "data", 4);
    put_u32(h + 40, (unsigned int)(src_frames * 4));
    fwrite(h, 1, 44, f);
    for (int i = 0; i < src_frames; i++) {
        // A 440 Hz tone in both channels.
        const double t = (double)i / (double)src_rate;
        const short s = (short)(sin(2.0 * M_PI * 440.0 * t) * 12000.0);
        fputc(s & 0xFF, f); fputc((s >> 8) & 0xFF, f);
        fputc(s & 0xFF, f); fputc((s >> 8) & 0xFF, f);
    }
    fclose(f);

    if (!gf_media_can_decode(src)) {
        printf("    FAIL: a plain stereo WAV was reported undecodable\n");
        fail("");
    }

    const char* dst = path_for("gf_reh_master_imported.wav");
    const int64_t frames = gf_media_to_mono_wav(src, dst, SR);
    const int64_t expected = (int64_t)src_frames * SR / src_rate;
    printf("    %d frames at %d Hz stereo -> %lld frames at %d Hz mono "
           "(expected ~%lld)\n",
           src_frames, src_rate, (long long)frames, SR, (long long)expected);
    if (frames <= 0) {
        printf("    FAIL: import returned %lld\n", (long long)frames);
        fail("");
        return;
    }
    // Resamplers differ by a few frames at the tail; anything beyond a
    // millisecond means the rate conversion is wrong, not just rounding.
    if (llabs((long long)(frames - expected)) > SR / 1000) {
        printf("    FAIL: length off by %lld frames\n",
               (long long)(frames - expected));
        fail("");
    }

    // And the engine must be able to stream what the importer wrote.
    gf_reh_clear_tracks();
    const int t = gf_reh_add_track(dst);
    if (t < 0) {
        printf("    FAIL: engine would not load the imported master (%d)\n", t);
        fail("");
        return;
    }
    if (gf_reh_track_frames(t) != frames) {
        printf("    FAIL: engine sees %lld frames, importer wrote %lld\n",
               (long long)gf_reh_track_frames(t), (long long)frames);
        fail("");
    }

    // A waveform for the alignment screen: a steady tone must come back as a
    // steady envelope, not silence.
    float bins[64];
    if (!gf_media_waveform(dst, bins, 64)) {
        printf("    FAIL: no waveform\n");
        fail("");
    } else {
        float lo = 1.0f, hi = 0.0f;
        for (int i = 0; i < 64; i++) {
            if (bins[i] < lo) lo = bins[i];
            if (bins[i] > hi) hi = bins[i];
        }
        printf("    waveform over 64 bins: %.3f .. %.3f\n", lo, hi);
        if (hi < 0.2f) { printf("    FAIL: waveform is silent\n"); fail(""); }
        if (lo < 0.2f) {
            printf("    FAIL: a steady tone produced an uneven envelope\n");
            fail("");
        }
    }

    // Something that is not audio at all must be refused rather than turned
    // into noise.
    const char* junk = path_for("gf_reh_notaudio.txt");
    FILE* j = fopen(junk, "wb");
    if (j) { fwrite("hello, this is not audio", 1, 24, j); fclose(j); }
    if (gf_media_can_decode(junk)) {
        printf("    FAIL: a text file was reported decodable\n");
        fail("");
    }
    if (gf_media_to_mono_wav(junk, path_for("gf_reh_junk_out.wav"), SR) >= 0) {
        printf("    FAIL: importing a text file appeared to succeed\n");
        fail("");
    }

    gf_reh_clear_tracks();
}

// ─── 10. Playback ends when the audio does ───────────────────────────────────

static void test_stops_at_end(void) {
    const int len = SR;                       // one second
    float* a = (float*)calloc((size_t)len, sizeof(float));
    for (int i = 0; i < len; i++) a[i] = 0.2f;
    write_wav(path_for("gf_reh_short.wav"), a, len);

    gf_reh_clear_tracks();
    gf_reh_set_metronome(0, 0.0f);
    gf_reh_set_grid(120.0, 4, 4);
    const int t = gf_reh_add_track(path_for("gf_reh_short.wav"));
    if (t < 0) { printf("    FAIL: load failed\n"); fail(""); free(a); return; }

    printf("    content ends at %lld frames (track is %d)\n",
           (long long)gf_reh_content_end(), len);
    if (gf_reh_content_end() != len) {
        printf("    FAIL: content end is %lld, expected %d\n",
               (long long)gf_reh_content_end(), len);
        fail("");
    }

    float out[BLOCK];
    gf_reh_play(0);
    // Render well past the end; the transport should have stopped itself.
    int blocks = 0;
    while (gf_reh_state() != GF_REH_STOPPED && blocks < (len * 3) / BLOCK) {
        gf_reh_render_offline(out, NULL, BLOCK);
        blocks++;
    }
    const long long stopped_at = (long long)gf_reh_position();
    printf("    stopped at %lld frames after %d blocks\n", stopped_at, blocks);
    if (gf_reh_state() != GF_REH_STOPPED) {
        printf("    FAIL: still running past the end of every track\n");
        fail("");
    }
    // Within one block of the end: the check runs once per block, not per
    // frame, and stopping mid-block would mean tearing the buffer.
    if (stopped_at < len || stopped_at > len + BLOCK) {
        printf("    FAIL: stopped at %lld, expected within a block of %d\n",
               stopped_at, len);
        fail("");
    }

    // An offset track ends where its *audio* does, not where its file does.
    gf_reh_set_track_offset(t, SR / 2);
    if (gf_reh_content_end() != len - SR / 2) {
        printf("    FAIL: offset track end is %lld, expected %d\n",
               (long long)gf_reh_content_end(), len - SR / 2);
        fail("");
    }
    gf_reh_set_track_offset(t, 0);

    // A written form is a length even with nothing recorded against it: type
    // out thirty-two bars, press play, and the click should run through them.
    gf_reh_clear_tracks();
    gf_reh_set_min_end(SR * 2);
    if (gf_reh_content_end() != SR * 2) {
        printf("    FAIL: a form with no tracks has no length\n");
        fail("");
    }
    gf_reh_play(0);
    blocks = 0;
    while (gf_reh_state() != GF_REH_STOPPED && blocks < (SR * 6) / BLOCK) {
        gf_reh_render_offline(out, NULL, BLOCK);
        blocks++;
    }
    if (gf_reh_state() != GF_REH_STOPPED) {
        printf("    FAIL: playback ran past the end of the form\n");
        fail("");
    }
    printf("    a form of %d frames stopped at %lld\n",
           SR * 2, (long long)gf_reh_position());

    // A track longer than the form still decides the end.
    gf_reh_add_track(path_for("gf_reh_short.wav"));
    gf_reh_set_min_end(SR / 2);
    if (gf_reh_content_end() != len) {
        printf("    FAIL: a short form should not truncate a long take\n");
        fail("");
    }
    gf_reh_set_min_end(0);
    gf_reh_clear_tracks();

    // With nothing loaded and no form the transport is a metronome and has no
    // end to reach, so it must keep running.
    gf_reh_clear_tracks();
    gf_reh_set_metronome(1, 0.5f);
    gf_reh_play(0);
    for (int i = 0; i < 200; i++) gf_reh_render_offline(out, NULL, BLOCK);
    if (gf_reh_state() != GF_REH_PLAYING) {
        printf("    FAIL: metronome-only playback stopped itself\n");
        fail("");
    }
    gf_reh_stop();

    // Recording must not be cut off at the old end: that is how a rehearsal
    // grows past its first take.
    gf_reh_clear_tracks();
    gf_reh_set_metronome(0, 0.0f);
    gf_reh_add_track(path_for("gf_reh_short.wav"));
    gf_reh_record(path_for("gf_reh_rec_long.wav"), 0, 0);
    for (int i = 0; i < (len * 2) / BLOCK; i++) {
        gf_reh_render_offline(out, NULL, BLOCK);
        gf_reh_feed_input(out, BLOCK);
    }
    if (gf_reh_state() != GF_REH_RECORDING) {
        printf("    FAIL: recording was cut off at the end of the other track\n");
        fail("");
    }
    printf("    recording ran past it to %lld frames\n",
           (long long)gf_reh_position());
    gf_reh_stop();
    gf_reh_clear_tracks();
    free(a);
}

// ─── 11. A lead-in is heard during the count-in ──────────────────────────────

static void test_count_in_preroll(void) {
    // A master anchored a quarter of a second in: everything before that is
    // the recording's own lead-in, and the tune's first downbeat is at 0.
    const int len = SR;
    const int lead = SR / 4;
    float* a = (float*)malloc(sizeof(float) * (size_t)len);
    for (int i = 0; i < len; i++) a[i] = 0.5f;
    write_wav(path_for("gf_reh_lead.wav"), a, len);

    gf_reh_clear_tracks();
    gf_reh_set_metronome(0, 0.0f);
    gf_reh_set_grid(120.0, 4, 4);
    const int t = gf_reh_add_track(path_for("gf_reh_lead.wav"));
    if (t < 0) { fail("could not load the master"); free(a); return; }
    gf_reh_set_track_offset(t, lead);

    float out[BLOCK];

    // Rendering from where the lead-in begins: the grid is still before its
    // downbeat, but the recording has audio there and it must be heard.
    gf_reh_play(-(int64_t)lead);
    gf_reh_render_offline(out, NULL, BLOCK);
    float peak = 0.0f;
    for (int i = 0; i < BLOCK; i++) {
        const float v = out[i] < 0 ? -out[i] : out[i];
        if (v > peak) peak = v;
    }
    printf("    at the start of the lead-in: peak %.3f\n", (double)peak);
    if (peak < 0.1f) {
        fail("the recording's lead-in was silent during the count-in");
    }

    // Further back than the recording itself reaches: silence, because there
    // is nothing there rather than because the count-in mutes it.
    gf_reh_play(-(int64_t)lead * 3);
    gf_reh_render_offline(out, NULL, BLOCK);
    peak = 0.0f;
    for (int i = 0; i < BLOCK; i++) {
        const float v = out[i] < 0 ? -out[i] : out[i];
        if (v > peak) peak = v;
    }
    printf("    before the recording begins: peak %.3f\n", (double)peak);
    if (peak > 0.001f) fail("audio appeared before the recording starts");

    // A take has no offset, so it must stay silent before the downbeat —
    // nobody played anything there.
    gf_reh_clear_tracks();
    gf_reh_add_track(path_for("gf_reh_lead.wav"));
    gf_reh_play(-(int64_t)lead);
    gf_reh_render_offline(out, NULL, BLOCK);
    peak = 0.0f;
    for (int i = 0; i < BLOCK; i++) {
        const float v = out[i] < 0 ? -out[i] : out[i];
        if (v > peak) peak = v;
    }
    printf("    a take before the downbeat: peak %.3f\n", (double)peak);
    if (peak > 0.001f) fail("a take sounded before the downbeat");

    gf_reh_stop();
    gf_reh_clear_tracks();
    free(a);
}

// ─── 12. A count-in is recorded, not thrown away ─────────────────────────────

static void test_records_through_count_in(void) {
    gf_reh_clear_tracks();
    gf_reh_set_metronome(0, 0.0f);
    // A brisk tempo on purpose: offline there is no worker draining the
    // record ring, so the whole take has to fit inside it.
    gf_reh_set_grid(240.0, 4, 4);

    const int64_t bar = gf_reh_frames_per_bar();
    if (gf_reh_record(path_for("gf_reh_countin.wav"), 0, 1) != 0) {
        fail("could not start recording");
        return;
    }
    if (gf_reh_take_offset() != bar) {
        printf("    FAIL: offset is %lld, expected %lld\n",
               (long long)gf_reh_take_offset(), (long long)bar);
        fail("");
    }

    // Feed input from the very first block, as a player following a
    // recording's intro would be singing from before bar one.
    float out[BLOCK], in[BLOCK];
    for (int i = 0; i < BLOCK; i++) in[i] = 0.4f;
    const int blocks = (int)((bar + SR / 8) / BLOCK);
    for (int i = 0; i < blocks; i++) {
        gf_reh_render_offline(out, NULL, BLOCK);
        gf_reh_feed_input(in, BLOCK);
    }

    const int64_t captured = gf_reh_recorded_frames();
    printf("    captured %lld frames over a %lld-frame count-in\n",
           (long long)captured, (long long)bar);
    // Everything from the count-in onwards, not merely from the downbeat.
    if (captured < bar) {
        fail("the count-in was thrown away instead of recorded");
    }
    gf_reh_stop();

    // A slot must not keep the previous track's offset. This is what put a
    // take a second ahead of the recording it was played against: it landed in
    // the slot the master had been using and inherited its offset.
    gf_reh_clear_tracks();
    const int reused = gf_reh_add_track(path_for("gf_reh_short.wav"));
    gf_reh_set_track_offset(reused, SR / 2);
    gf_reh_clear_tracks();
    gf_reh_add_track(path_for("gf_reh_short.wav"));
    if (gf_reh_content_end() != SR) {
        printf("    FAIL: a reused slot kept an offset (end %lld, want %d)\n",
               (long long)gf_reh_content_end(), SR);
        fail("");
    }
    printf("    a reused slot starts with no offset\n");
    gf_reh_clear_tracks();

    // Without a count-in the downbeat is the start of the file, which is what
    // every take before this did.
    if (gf_reh_record(path_for("gf_reh_nocount.wav"), 0, 0) != 0) {
        fail("could not start recording");
        return;
    }
    if (gf_reh_take_offset() != 0) {
        printf("    FAIL: no count-in should mean no offset, got %lld\n",
               (long long)gf_reh_take_offset());
        fail("");
    }
    printf("    with no count-in the offset is 0\n");
    gf_reh_stop();
    gf_reh_clear_tracks();
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
    printf("\n8. anchoring the grid in a recording\n"); test_track_offset();
    printf("\n9. importing a recording\n");    test_media_import();
    printf("\n10. playback ends with the audio\n"); test_stops_at_end();
    printf("\n11. a lead-in plays during the count-in\n");
    test_count_in_preroll();
    printf("\n12. the count-in is recorded\n");
    test_records_through_count_in();

    gf_reh_destroy();

    printf("\n");
    if (g_fails == 0) {
        printf("OK — all rehearsal engine checks passed.\n");
        return 0;
    }
    printf("FAILED — %d check(s).\n", g_fails);
    return 1;
}
