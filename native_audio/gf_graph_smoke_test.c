// gf_graph_smoke_test.c — The native interpreter for user `.gfpd` graphs.
//
// A `.gfpd` effect written by a user used to show its panel and make no
// sound: only the bundled effects had native code. gfpa_graph.cpp now builds
// the file's graph natively. These checks render audio through graphs built
// the way the Dart side builds them, and verify:
//
//   1. A gain node follows its plugin parameter, through gfpa_dsp_set_param.
//   2. Two wires into one input are summed.
//   3. A biquad low-pass keeps the bass and removes the treble.
//   4. A built-in effect runs as a node: a delay echoes after its set time.
//   5. A host block larger than the graph's buffers is processed in pieces.
//   6. Bypass passes the input through.
//   7. Broken graphs are refused: unknown node, unknown port, a loop, no
//      output.
//
// Build: see CMakeLists.txt — target "gf_graph_smoke_test".
// Run  : ./scripts/run_smoke_tests.sh graph

#include "gfpa_graph.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

void gfpa_set_sample_rate(double sampleRate);

#define RATE 48000
#define BLOCK 256
#define LONG 12000

static int g_failures = 0;

static void report(const char* name, int ok, const char* detail) {
    printf("   %-58s %s\n", name, ok ? "PASS" : "FAIL");
    if (detail && detail[0]) printf("      %s\n", detail);
    if (!ok) g_failures++;
}

static float g_inL[LONG], g_inR[LONG], g_outL[LONG], g_outR[LONG];

/// Runs [frames] frames of g_in through [h] into g_out, in one call.
static void run(GfpaDspHandle h, int frames) {
    gfpa_dsp_insert_fn(h)(g_inL, g_inR, g_outL, g_outR, frames,
                          gfpa_dsp_userdata(h));
}

/// Fills g_in with a sine of [hz] at amplitude 0.5.
static void sine(double hz, int frames) {
    for (int i = 0; i < frames; ++i) {
        g_inL[i] = g_inR[i] = (float)(0.5 * sin(2.0 * M_PI * hz * i / RATE));
    }
}

/// RMS of g_outL over [from, to).
static double rms(int from, int to) {
    double s = 0;
    for (int i = from; i < to; ++i) s += (double)g_outL[i] * g_outL[i];
    return sqrt(s / (to - from));
}

/// in -> gain(level) -> out, with the plugin parameter "level" 0..1,
/// default 0.5 (unity). Built on blocks of [block] frames.
static GfpaDspHandle gain_graph(int block) {
    GfpaGraphBuilder b = gfpa_graph_begin(RATE, block);
    gfpa_graph_add_node(b, "in", "audio_in");
    gfpa_graph_add_node(b, "g", "gain");
    gfpa_graph_add_node(b, "out", "audio_out");
    gfpa_graph_connect(b, "in", "out", "g", "in");
    gfpa_graph_connect(b, "g", "out", "out", "in");
    gfpa_graph_add_param(b, "level", 0.0, 1.0, 0.5);
    gfpa_graph_bind(b, "level", "g", "gain");
    return gfpa_graph_finish(b);
}

static void test_gain(void) {
    GfpaDspHandle h = gain_graph(BLOCK);
    report("a gain graph builds", h != NULL, "");
    if (!h) return;
    sine(440, BLOCK);
    run(h, BLOCK);
    report("the default level leaves the signal unchanged",
           fabsf(g_outL[10] - g_inL[10]) < 1e-6f, "");
    gfpa_dsp_set_param(h, "level", 1.0);
    run(h, BLOCK);
    report("level 1.0 doubles it", fabsf(g_outL[10] - 2.0f * g_inL[10]) < 1e-6f, "");
    gfpa_dsp_set_bypass(h, true);
    run(h, BLOCK);
    report("bypass passes the input through", g_outL[10] == g_inL[10], "");
    gfpa_dsp_destroy(h);
}

static void test_large_block(void) {
    GfpaDspHandle h = gain_graph(64);
    sine(440, 1000);
    run(h, 1000);
    int same = 1;
    for (int i = 0; i < 1000; ++i) same &= fabsf(g_outL[i] - g_inL[i]) < 1e-6f;
    report("1000 frames through a 64-frame graph come out whole", same, "");
    gfpa_dsp_destroy(h);
}

static void test_sum(void) {
    GfpaGraphBuilder b = gfpa_graph_begin(RATE, BLOCK);
    gfpa_graph_add_node(b, "in", "audio_in");
    gfpa_graph_add_node(b, "a", "gain");
    gfpa_graph_add_node(b, "b", "gain");
    gfpa_graph_add_node(b, "out", "audio_out");
    gfpa_graph_connect(b, "in", "out", "a", "in");
    gfpa_graph_connect(b, "in", "out", "b", "in");
    gfpa_graph_connect(b, "a", "out", "out", "in");
    gfpa_graph_connect(b, "b", "out", "out", "in");
    GfpaDspHandle h = gfpa_graph_finish(b);
    sine(440, BLOCK);
    run(h, BLOCK);
    report("two wires into one input are summed",
           h && fabsf(g_outL[10] - 2.0f * g_inL[10]) < 1e-6f, "");
    if (h) gfpa_dsp_destroy(h);
}

static void test_lowpass(void) {
    // in -> biquad (low pass, ~250 Hz) -> wet_dry (all wet) -> out, plus the
    // dry wire, as a typical filter plugin would be written.
    GfpaGraphBuilder b = gfpa_graph_begin(RATE, BLOCK);
    gfpa_graph_add_node(b, "in", "audio_in");
    gfpa_graph_add_node(b, "f", "biquad_filter");
    gfpa_graph_add_node(b, "mix", "wet_dry");
    gfpa_graph_add_node(b, "out", "audio_out");
    gfpa_graph_connect(b, "in", "out", "f", "in");
    gfpa_graph_connect(b, "in", "out", "mix", "dry");
    gfpa_graph_connect(b, "f", "out", "mix", "wet");
    gfpa_graph_connect(b, "mix", "out", "out", "in");
    gfpa_graph_set_const(b, "f", "mode", 0.0);
    gfpa_graph_set_const(b, "f", "freq", 0.366);  // 20 * 1000^0.366 ≈ 250 Hz
    gfpa_graph_set_const(b, "mix", "mix", 1.0);
    GfpaDspHandle h = gfpa_graph_finish(b);
    if (!h) { report("a filter graph builds", 0, ""); return; }
    sine(60, LONG);
    run(h, LONG);
    const double bass = rms(LONG / 2, LONG) / (0.5 / sqrt(2.0));
    sine(5000, LONG);
    run(h, LONG);
    const double treble = rms(LONG / 2, LONG) / (0.5 / sqrt(2.0));
    char d[96];
    snprintf(d, sizeof d, "60 Hz kept at %.2f, 5 kHz left at %.4f", bass, treble);
    report("a low pass keeps the bass and removes the treble",
           bass > 0.9 && treble < 0.01, d);
    gfpa_dsp_destroy(h);
}

static void test_delay(void) {
    // in -> delay (100 ms, no feedback) -> out: an impulse comes back once.
    GfpaGraphBuilder b = gfpa_graph_begin(RATE, BLOCK);
    gfpa_graph_add_node(b, "in", "audio_in");
    int added = gfpa_graph_add_node(b, "d", "delay");
    gfpa_graph_add_node(b, "out", "audio_out");
    gfpa_graph_connect(b, "in", "out", "d", "in");
    gfpa_graph_connect(b, "d", "out", "out", "in");
    gfpa_graph_set_const(b, "d", "timeMs", 99.0 / 1999.0);  // 1 + n*1999 = 100
    gfpa_graph_set_const(b, "d", "feedback", 0.0);
    GfpaDspHandle h = gfpa_graph_finish(b);
    report("a built-in delay can be a node", added == 0 && h != NULL, "");
    if (!h) return;
    memset(g_inL, 0, sizeof g_inL);
    memset(g_inR, 0, sizeof g_inR);
    g_inL[0] = g_inR[0] = 1.0f;
    for (int at = 0; at < LONG; at += BLOCK) {
        gfpa_dsp_insert_fn(h)(g_inL + at, g_inR + at, g_outL + at, g_outR + at,
                              BLOCK, gfpa_dsp_userdata(h));
    }
    int peak = 0;
    for (int i = 1; i < LONG; ++i) {
        const float v = fmaxf(fabsf(g_outL[i]), fabsf(g_outR[i]));
        const float p = fmaxf(fabsf(g_outL[peak]), fabsf(g_outR[peak]));
        if (v > p) peak = i;
    }
    char d[96];
    snprintf(d, sizeof d, "echo at frame %d (100 ms = 4800)", peak);
    report("the echo comes back after the set time, with no dry signal",
           abs(peak - 4800) <= 2 && fabsf(g_outL[0]) < 1e-6f, d);
    gfpa_dsp_destroy(h);
}

static void test_refused(void) {
    GfpaGraphBuilder b = gfpa_graph_begin(RATE, BLOCK);
    report("an unknown node type is refused",
           gfpa_graph_add_node(b, "x", "flanger_9000") == -1, "");
    gfpa_graph_add_node(b, "in", "audio_in");
    gfpa_graph_add_node(b, "a", "gain");
    gfpa_graph_add_node(b, "c", "gain");
    gfpa_graph_add_node(b, "out", "audio_out");
    report("an unknown port is refused",
           gfpa_graph_connect(b, "in", "out", "a", "sidechain") == -1, "");
    report("an unknown node parameter is refused",
           gfpa_graph_set_const(b, "a", "drive", 0.5) == -1, "");
    gfpa_graph_connect(b, "a", "out", "c", "in");
    gfpa_graph_connect(b, "c", "out", "a", "in");
    gfpa_graph_connect(b, "c", "out", "out", "in");
    report("a loop is refused", gfpa_graph_finish(b) == NULL, "");

    b = gfpa_graph_begin(RATE, BLOCK);
    gfpa_graph_add_node(b, "in", "audio_in");
    gfpa_graph_add_node(b, "a", "gain");
    gfpa_graph_connect(b, "in", "out", "a", "in");
    report("a graph without audio_out is refused", gfpa_graph_finish(b) == NULL, "");
}

int main(void) {
    printf("GFPA graph smoke test\n\n");
    gfpa_set_sample_rate(RATE);
    test_gain();
    test_large_block();
    test_sum();
    test_lowpass();
    test_delay();
    test_refused();
    printf("\n%s (%d failure%s)\n", g_failures ? "FAILED" : "ALL PASSED",
           g_failures, g_failures == 1 ? "" : "s");
    return g_failures ? 1 : 0;
}
