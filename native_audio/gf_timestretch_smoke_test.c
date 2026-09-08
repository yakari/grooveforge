// Offline checks for gf_timestretch.
//
// The property that matters is not "does it produce a file" but "does it
// produce a file of exactly the right length at the same pitch". A take one
// frame off the grid drifts against every other track in the tune, and a take
// whose pitch moved is useless to practise against — those are the two things
// worth failing over.

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "gf_timestretch.h"

#define SR 48000

static int g_failures = 0;

static void fail(const char* what) {
    printf("    FAIL: %s\n", what);
    g_failures++;
}

/// A rotating pool, because a single static buffer makes f(path(a), path(b))
/// pass the same string twice.
static const char* path_for(const char* name) {
    static char pool[4][512];
    static int next = 0;
    char* buf = pool[next];
    next = (next + 1) % 4;
    const char* dir = getenv("TMPDIR");
    if (!dir || !*dir) dir = "/tmp";
    snprintf(buf, 512, "%s/%s", dir, name);
    return buf;
}

static void write_sine(const char* path, double hz, int frames) {
    FILE* f = fopen(path, "wb");
    if (!f) { fail("could not write the input"); return; }
    const uint32_t data_bytes = (uint32_t)frames * 2u;
    const uint32_t riff = data_bytes + 36u;
    const uint32_t rate = SR, byte_rate = SR * 2u;
    unsigned char h[44];
    memcpy(h, "RIFF", 4);
    for (int i = 0; i < 4; i++) h[4 + i] = (unsigned char)((riff >> (8 * i)) & 0xFF);
    memcpy(h + 8, "WAVEfmt ", 8);
    h[16] = 16; h[17] = h[18] = h[19] = 0;
    h[20] = 1; h[21] = 0; h[22] = 1; h[23] = 0;
    for (int i = 0; i < 4; i++) h[24 + i] = (unsigned char)((rate >> (8 * i)) & 0xFF);
    for (int i = 0; i < 4; i++) h[28 + i] = (unsigned char)((byte_rate >> (8 * i)) & 0xFF);
    h[32] = 2; h[33] = 0; h[34] = 16; h[35] = 0;
    memcpy(h + 36, "data", 4);
    for (int i = 0; i < 4; i++) h[40 + i] = (unsigned char)((data_bytes >> (8 * i)) & 0xFF);
    fwrite(h, 1, 44, f);
    for (int i = 0; i < frames; i++) {
        const double v = 0.6 * sin(2.0 * M_PI * hz * (double)i / SR);
        const int16_t s = (int16_t)lrint(v * 32767.0);
        const unsigned char b[2] = {(unsigned char)(s & 0xFF),
                                    (unsigned char)((s >> 8) & 0xFF)};
        fwrite(b, 1, 2, f);
    }
    fclose(f);
}

/// Reads a mono 16-bit WAV into floats. Returns the frame count, 0 on failure.
static int read_wav(const char* path, float** out) {
    FILE* f = fopen(path, "rb");
    if (!f) return 0;
    unsigned char h[44];
    if (fread(h, 1, 44, f) != 44) { fclose(f); return 0; }
    const uint32_t data_bytes = (uint32_t)h[40] | ((uint32_t)h[41] << 8) |
                                ((uint32_t)h[42] << 16) | ((uint32_t)h[43] << 24);
    const int frames = (int)(data_bytes / 2);
    if (frames <= 0) { fclose(f); return 0; }
    float* buf = (float*)malloc(sizeof(float) * (size_t)frames);
    for (int i = 0; i < frames; i++) {
        unsigned char b[2];
        if (fread(b, 1, 2, f) != 2) { fclose(f); free(buf); return 0; }
        const int16_t s = (int16_t)((uint16_t)b[0] | ((uint16_t)b[1] << 8));
        buf[i] = (float)s / 32768.0f;
    }
    fclose(f);
    *out = buf;
    return frames;
}

/// Dominant frequency by zero crossings over the steady middle of the signal.
///
/// Crude on purpose: the question is "is this still a 440 Hz tone or is it now
/// a 300 Hz one", and counting crossings answers that without an FFT.
static double dominant_hz(const float* x, int frames) {
    const int start = frames / 4, end = frames - frames / 4;
    int crossings = 0;
    for (int i = start + 1; i < end; i++) {
        if ((x[i - 1] < 0.0f && x[i] >= 0.0f)) crossings++;
    }
    const double seconds = (double)(end - start) / SR;
    return seconds > 0 ? crossings / seconds : 0.0;
}

int main(void) {
    printf("gf_timestretch smoke test\n");

    const int in_frames = SR;  // one second
    write_sine(path_for("gf_ts_in.wav"), 440.0, in_frames);

    printf("\n1. length is exactly what the grid expects\n");
    const float ratios[] = {0.5f, 0.75f, 1.0f, 1.5f, 2.0f};
    for (int i = 0; i < 5; i++) {
        const char* out = path_for("gf_ts_out.wav");
        const int rc = gf_ts_render_file(path_for("gf_ts_in.wav"), out, ratios[i]);
        if (rc != GF_TS_OK) { printf("    FAIL: render returned %d\n", rc); g_failures++; continue; }
        float* got = NULL;
        const int frames = read_wav(out, &got);
        const int64_t want = gf_ts_output_frames(in_frames, ratios[i]);
        printf("    ratio %.2f -> %d frames (want %lld)\n",
               (double)ratios[i], frames, (long long)want);
        if ((int64_t)frames != want) fail("length does not match the grid");
        free(got);
    }

    printf("\n2. pitch is unchanged — the whole point\n");
    for (int i = 0; i < 5; i++) {
        const char* out = path_for("gf_ts_out.wav");
        if (gf_ts_render_file(path_for("gf_ts_in.wav"), out, ratios[i]) != GF_TS_OK) {
            fail("render failed");
            continue;
        }
        float* got = NULL;
        const int frames = read_wav(out, &got);
        if (frames <= 0) { fail("could not read the render"); continue; }
        const double hz = dominant_hz(got, frames);
        printf("    ratio %.2f -> %.0f Hz\n", (double)ratios[i], hz);
        // Resampling instead of stretching would put 2.0 at 220 Hz and 0.5 at
        // 880, so a generous tolerance still catches the failure that matters.
        if (fabs(hz - 440.0) > 30.0) fail("the pitch moved");
        free(got);
    }

    printf("\n3. refusing what it cannot do\n");
    if (gf_ts_render_file(path_for("gf_ts_in.wav"), path_for("gf_ts_out.wav"), 0.01f)
            != GF_TS_ERR_RATIO) {
        fail("an absurd ratio was accepted");
    }
    if (gf_ts_render_file(path_for("gf_ts_nope.wav"), path_for("gf_ts_out.wav"), 1.5f)
            != GF_TS_ERR_OPEN_INPUT) {
        fail("a missing input was accepted");
    }
    printf("    bad ratios and missing files are refused\n");

    if (g_failures == 0) {
        printf("\nOK — all time-stretch checks passed.\n");
        return 0;
    }
    printf("\n%d check(s) FAILED.\n", g_failures);
    return 1;
}
