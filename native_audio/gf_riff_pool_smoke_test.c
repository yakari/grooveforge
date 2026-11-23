// gf_riff_pool_smoke_test.c — The Riff guitar through the GFPA C API, as the
// app drives it.
//
// gf_riff_smoke_test.c checks the guitar itself; this one checks the plumbing
// between it and the audio backends (packages/.../gfpa_riff.cpp):
//
//   1. A note pushed from the "Dart side" is heard on the next render.
//   2. Four guitars can play at once; a fifth create is refused cleanly.
//   3. A removed guitar's render function stays callable and is silent —
//      the backends may call it once more after the slot is gone.
//   4. A pool slot reused by a new rack slot starts silent, without the
//      notes its previous owner left ringing.
//   5. Bypass mutes the guitar; knobs set through gfpa_dsp_set_param reach it.
//   6. It follows the stream's sample rate.
//
// Build: see CMakeLists.txt — target "gf_riff_pool_smoke_test".
// Run  : ./scripts/run_smoke_tests.sh riff

#include "gfpa_dsp.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

void gfpa_set_sample_rate(double sampleRate);

typedef void (*RenderFn)(float* outL, float* outR, int32_t frames);

#define BLOCK 256

static int g_failures = 0;

static void report(const char* name, int ok, const char* detail) {
    printf("   %-58s %s\n", name, ok ? "PASS" : "FAIL");
    if (detail && detail[0]) printf("      %s\n", detail);
    if (!ok) g_failures++;
}

/// RMS of [blocks] blocks rendered through [fn].
static double render_rms(RenderFn fn, int blocks) {
    float l[BLOCK], r[BLOCK];
    double s = 0;
    for (int b = 0; b < blocks; ++b) {
        fn(l, r, BLOCK);
        for (int i = 0; i < BLOCK; ++i) s += (double)l[i] * l[i];
    }
    return sqrt(s / (blocks * BLOCK));
}

static RenderFn fn_of(GfpaDspHandle h) { return (RenderFn)(intptr_t)gfpa_riff_render_fn(h); }

int main(void) {
    printf("Riff pool smoke test\n\n");
    gfpa_set_sample_rate(48000.0);

    // 1. A note is heard.
    GfpaDspHandle a = gfpa_dsp_create("com.grooveforge.riff", 48000, 8192);
    RenderFn fa = a ? fn_of(a) : NULL;
    report("a Riff handle and its render function exist", a && fa, "");
    if (!a || !fa) return 1;
    const double before = render_rms(fa, 4);
    gfpa_riff_note_on(a, 52, 100);
    const double after = render_rms(fa, 20);
    char d[96];
    snprintf(d, sizeof d, "rms %.5f before the note, %.4f after", before, after);
    report("a queued note is heard on the next render", before == 0.0 && after > 0.005, d);

    // 5. Knobs and bypass.
    gfpa_dsp_set_bypass(a, true);
    report("bypass mutes the guitar", render_rms(fa, 4) == 0.0, "");
    gfpa_dsp_set_bypass(a, false);
    gfpa_dsp_set_param(a, "level", -24.0);
    render_rms(fa, 20);   // let the level glide down
    const double quiet = render_rms(fa, 4);
    gfpa_dsp_set_param(a, "level", 0.0);
    render_rms(fa, 20);
    const double loud = render_rms(fa, 4);
    snprintf(d, sizeof d, "%.1f dB between Level 0 and -24 dB", 20 * log10(loud / quiet));
    report("the Level knob reaches the guitar", loud / quiet > 8.0, d);
    GfpaDspHandle amp = gfpa_dsp_create("com.grooveforge.amp", 48000, 8192);
    report("an Amp handle reports no Riff render function", amp && gfpa_riff_render_fn(amp) == 0, "");
    gfpa_riff_note_on(amp, 60, 100);   // must be a harmless no-op
    gfpa_dsp_destroy(amp);

    // 2. Four at once, a fifth refused.
    GfpaDspHandle h[4] = {a, 0, 0, 0};
    for (int i = 1; i < 4; ++i) h[i] = gfpa_dsp_create("com.grooveforge.riff", 48000, 8192);
    GfpaDspHandle fifth = gfpa_dsp_create("com.grooveforge.riff", 48000, 8192);
    int distinct = 1;
    for (int i = 0; i < 4; ++i)
        for (int j = i + 1; j < 4; ++j)
            if (!h[i] || !h[j] || gfpa_riff_render_fn(h[i]) == gfpa_riff_render_fn(h[j])) distinct = 0;
    report("four guitars at once, each with its own render function", distinct, "");
    report("a fifth guitar is refused", fifth == NULL, "");

    // 3. A removed guitar's render function is still safe, and silent.
    RenderFn f3 = fn_of(h[3]);
    gfpa_riff_note_on(h[3], 64, 100);
    render_rms(f3, 4);
    gfpa_dsp_destroy(h[3]);
    report("a removed guitar renders silence, not freed memory", render_rms(f3, 4) == 0.0, "");

    // 4. Reused slot starts silent, then plays.
    GfpaDspHandle reused = gfpa_dsp_create("com.grooveforge.riff", 48000, 8192);
    RenderFn fr = reused ? fn_of(reused) : NULL;
    const int same = fr == f3;
    const double fresh = fr ? render_rms(fr, 4) : 1.0;
    report("a reused slot starts silent, without the old notes", same && fresh == 0.0, "");
    if (reused) {
        gfpa_riff_note_on(reused, 45, 100);
        report("and plays its own", render_rms(fr, 20) > 0.005, "");
    }

    // 6. Rate follow: a note still sounds after the stream reopens at 44.1.
    gfpa_set_sample_rate(44100.0);
    gfpa_riff_note_on(a, 57, 100);
    const double at44 = render_rms(fa, 20);
    report("it follows the stream to 44.1 kHz and keeps playing", at44 > 0.005, "");

    for (int i = 0; i < 3; ++i) gfpa_dsp_destroy(h[i]);
    if (reused) gfpa_dsp_destroy(reused);
    printf("\n%s (%d failure%s)\n", g_failures ? "FAILED" : "ALL PASSED",
           g_failures, g_failures == 1 ? "" : "s");
    return g_failures ? 1 : 0;
}
