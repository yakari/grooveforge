// gf_harmonizer_smoke_test.c — Offline checks for the Audio Harmonizer.
//
// Three classes of defect have reached a release or a test build of this
// module, none of them catchable from the Dart suite because they only exist
// once real audio is rendered:
//
//   1. **Level.** Harmony voices are pitch-shifted copies of one signal, so
//      their peaks line up and the sum approaches the arithmetic sum of the
//      mixes. Nothing downstream attenuates, so anything above full scale is
//      hard-clipped by the audio device and heard as crackle.
//
//   2. **Continuity.** A phase vocoder emits output in synthesis-frame
//      quanta, never in the audio device's block size. A block the vocoder
//      cannot fill leaves a hole, and a hole at block rate is a click. This
//      has to hold at every burst size a device might hand over, not just a
//      convenient one. (2.17.4 passes this one — its gaps were confined to
//      the warm-up, which the measurement skips. It guards the banking logic
//      that replaced it, which is easy to get wrong in the other direction.)
//
//   3. **Gain flatness across intervals.** The overlap-add normalisation
//      depends on the synthesis hop; get it wrong and each interval comes out
//      at its own level, with a tremolo stamped on top of the upward ones.
//
//   4. **A shift that moves.** The vocoder's Harmony mode re-pitches every
//      voice every block, from the pitch it hears being sung. That churns the
//      vocoder's internal rates in a way a fixed interval never does.
//
// Build: see CMakeLists.txt — target "gf_harmonizer_smoke_test".
// Run  : ./build/gf_harmonizer_smoke_test

#include "gfpa_dsp.h"
#include "gf_harmony.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

/// Builds a harmonizer with [voices] active at the descriptor's default
/// intervals and mixes.
static GfpaDspHandle makeHarmonizer(int voices, double dryWet) {
    GfpaDspHandle h =
        gfpa_dsp_create("com.grooveforge.audio_harmonizer", SR, 4096);
    if (!h) return NULL;
    gfpa_dsp_set_param(h, "voice_count", (double)voices);

    // The descriptor's defaults: a fifth, an octave, a major third, and a
    // fourth below.
    static const double semis[4] = {7, 12, 4, -5};
    static const double mix[4]   = {0.7, 0.7, 0.5, 0.5};
    for (int v = 0; v < 4; v++) {
        char id[32];
        snprintf(id, sizeof id, "voice%d_semitones", v + 1);
        gfpa_dsp_set_param(h, id, semis[v]);
        snprintf(id, sizeof id, "voice%d_mix", v + 1);
        gfpa_dsp_set_param(h, id, mix[v]);
    }
    gfpa_dsp_set_param(h, "dry_wet", dryWet);
    return h;
}

/// A held note with a few harmonics — what a keyboard or a voice actually
/// feeds a harmonizer.
static float testSample(long phase, double amplitude) {
    const double t = 2.0 * M_PI * (double)phase / SR;
    return (float)(amplitude * (0.7 * sin(220 * t) + 0.2 * sin(440 * t) +
                                0.1 * sin(660 * t)));
}

// ── 1. Headroom ──────────────────────────────────────────────────────────────

/// Peak output for [voices] voices at input amplitude [amplitude].
static double peakOutput(int voices, double amplitude, double dryWet) {
    GfpaDspHandle h = makeHarmonizer(voices, dryWet);
    if (!h) return -1;
    GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
    void* ud = gfpa_dsp_userdata(h);

    const int burst = 256;
    static float in[256], outL[256], outR[256];
    long phase = 0;
    double peak = 0;
    for (int b = 0; b < SR * 3 / burst; b++) {
        for (int i = 0; i < burst; i++, phase++) in[i] = testSample(phase, amplitude);
        fn(in, in, outL, outR, burst, ud);
        if (b > SR / burst) {           // skip the vocoder's warm-up
            for (int i = 0; i < burst; i++) {
                const double a = fabs(outL[i]);
                if (a > peak) peak = a;
            }
        }
    }
    gfpa_dsp_destroy(h);
    return peak;
}

static void testHeadroom(void) {
    printf("── Test 1: the summed voices stay inside full scale\n");
    double worst = 0;
    int worstVoices = 0;
    double worstDryWet = 0;

    const double dryWets[2] = {0.5, 1.0};
    for (int d = 0; d < 2; d++) {
        for (int voices = 1; voices <= 4; voices++) {
            // A full-scale input is the case that matters: it is what a
            // chord through a hot synth actually delivers.
            const double peak = peakOutput(voices, 1.0, dryWets[d]);
            if (peak > worst) {
                worst = peak;
                worstVoices = voices;
                worstDryWet = dryWets[d];
            }
        }
    }

    char detail[160];
    snprintf(detail, sizeof detail,
             "worst peak %.2f at %d voice(s), dry/wet %.1f (must stay <= 1.00)",
             worst, worstVoices, worstDryWet);
    report("full-scale input never clips, at any voice count", worst <= 1.0,
           detail);
}

static void testLevelIsIndependentOfVoiceCount(void) {
    printf("── Test 2: adding a voice redistributes level, it does not add it\n");
    double peaks[4];
    for (int v = 1; v <= 4; v++) peaks[v - 1] = peakOutput(v, 0.5, 1.0);

    // Voices two through four should sit within a few dB of each other; a
    // harmonizer that gets louder every time a voice is added is one that
    // will clip as soon as the player uses it fully.
    double lo = peaks[1], hi = peaks[1];
    for (int v = 2; v < 4; v++) {
        if (peaks[v] < lo) lo = peaks[v];
        if (peaks[v] > hi) hi = peaks[v];
    }
    const double spreadDb = 20.0 * log10(hi / (lo > 1e-9 ? lo : 1e-9));

    char detail[200];
    snprintf(detail, sizeof detail,
             "peaks 1..4 voices: %.2f %.2f %.2f %.2f — spread across 2..4 = %.2f dB",
             peaks[0], peaks[1], peaks[2], peaks[3], spreadDb);
    report("level within 1.5 dB from two voices to four", spreadDb <= 1.5,
           detail);
}

// ── 2. Continuity ────────────────────────────────────────────────────────────

/// Largest sample-to-sample jump in the output, as a fraction of its peak.
///
/// A held note moves smoothly; a block the vocoder could not fill shows up as
/// a step at the block boundary.
static double worstStepRatio(int burst) {
    GfpaDspHandle h = makeHarmonizer(4, 1.0);
    if (!h) return -1;
    GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
    void* ud = gfpa_dsp_userdata(h);

    static float in[4096], outL[4096], outR[4096];
    const int blocks = SR * 3 / burst;
    long phase = 0;
    double prev = 0, worst = 0, peak = 0;
    int started = 0;
    for (int b = 0; b < blocks; b++) {
        for (int i = 0; i < burst; i++, phase++) in[i] = testSample(phase, 0.5);
        fn(in, in, outL, outR, burst, ud);
        if (b <= SR / burst) { prev = outL[burst - 1]; continue; }  // warm-up
        for (int i = 0; i < burst; i++) {
            if (started) {
                const double step = fabs(outL[i] - prev);
                if (step > worst) worst = step;
            }
            prev = outL[i];
            started = 1;
            const double a = fabs(outL[i]);
            if (a > peak) peak = a;
        }
    }
    gfpa_dsp_destroy(h);
    return (peak > 1e-9) ? worst / peak : 0;
}

static void testContinuity(void) {
    printf("── Test 3: every audio block comes out whole, at any burst size\n");
    // The sizes a real device hands over: Android bursts run 96..240, desktop
    // periods 256..2048.
    const int bursts[] = {64, 96, 128, 192, 240, 256, 512, 1024, 2048};
    const int count = (int)(sizeof(bursts) / sizeof(bursts[0]));

    double worst = 0;
    int worstBurst = 0;
    for (int i = 0; i < count; i++) {
        const double ratio = worstStepRatio(bursts[i]);
        if (ratio > worst) {
            worst = ratio;
            worstBurst = bursts[i];
        }
    }

    // The test tone's own slew sets the floor: its fastest partial is 660 Hz,
    // so at 48 kHz it moves up to 2*pi*660/48000 = 8.6% of peak per sample.
    // The threshold sits just above that, and a dropped block is not a near
    // miss — it steps most of the way to zero, an order of magnitude higher.
    char detail[180];
    snprintf(detail, sizeof detail,
             "worst sample-to-sample step %.1f%% of peak, at burst %d "
             "(the tone's own slew is 8.6%%; a dropped block reads far higher)",
             100.0 * worst, worstBurst);
    report("no block-rate discontinuities at any burst size", worst < 0.10,
           detail);
}

// ── 3. Gain flatness across intervals ────────────────────────────────────────

static void testIntervalGainFlatness(void) {
    printf("── Test 4: every interval comes out at the same level\n");
    // One voice, wet only, so the measurement is that voice alone.
    const double semis[] = {-24, -12, -7, -5, 0, 4, 7, 12, 24};
    const int count = (int)(sizeof(semis) / sizeof(semis[0]));

    double lo = 1e9, hi = 0, loAt = 0, hiAt = 0;
    for (int i = 0; i < count; i++) {
        GfpaDspHandle h = gfpa_dsp_create("com.grooveforge.audio_harmonizer",
                                          SR, 4096);
        if (!h) { report("harmonizer could be created", 0, ""); return; }
        gfpa_dsp_set_param(h, "voice_count", 1.0);
        gfpa_dsp_set_param(h, "voice1_semitones", semis[i]);
        gfpa_dsp_set_param(h, "voice1_mix", 1.0);
        gfpa_dsp_set_param(h, "dry_wet", 1.0);
        GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
        void* ud = gfpa_dsp_userdata(h);

        const int burst = 256;
        static float in[256], outL[256], outR[256];
        long phase = 0;
        double sum = 0;
        long n = 0;
        for (int b = 0; b < SR * 3 / burst; b++) {
            for (int k = 0; k < burst; k++, phase++)
                in[k] = (float)(0.4 * sin(2.0 * M_PI * 220.0 * phase / SR));
            fn(in, in, outL, outR, burst, ud);
            if (b > SR / burst) {
                for (int k = 0; k < burst; k++) { sum += outL[k] * outL[k]; n++; }
            }
        }
        gfpa_dsp_destroy(h);

        const double rms = sqrt(sum / (double)n);
        if (rms < lo) { lo = rms; loAt = semis[i]; }
        if (rms > hi) { hi = rms; hiAt = semis[i]; }
    }

    const double spreadDb = 20.0 * log10(hi / (lo > 1e-9 ? lo : 1e-9));
    char detail[200];
    snprintf(detail, sizeof detail,
             "quietest %+.0f st, loudest %+.0f st, spread %.2f dB "
             "(the 2.17.4 overlap bug measured 21 dB here)",
             loAt, hiAt, spreadDb);
    report("level flat within 1 dB from -24 to +24 semitones", spreadDb <= 1.0,
           detail);
}

// ── 4. A voice whose pitch moves every block ─────────────────────────────────

/// The vocoder's Harmony mode drives `gf_harmony` differently from the
/// effect: instead of a fixed interval from a knob, it recomputes each
/// voice's offset every block from the pitch it hears the singer holding.
/// That value never sits still — the detector smooths towards the sung
/// pitch, so the shift wanders continuously.
///
/// Changing the shift changes the vocoder's internal analysis hop and drain
/// rate, which is exactly what the output bank exists to absorb. If it
/// cannot, a voice re-primes and goes silent for a few blocks, and a singer
/// holding one note would hear the harmony stutter.
static void testModulatedPitchStaysContinuous(void) {
    printf("── Test 5: a voice re-pitched every block does not stutter\n");

    const int burst = 128;
    gf_harmony* h = gf_harmony_create(burst);
    if (!h) { report("harmony engine could be created", 0, ""); return; }
    gf_harmony_set_voice_count(h, 2);

    static float in[128], out[128];
    long phase = 0;
    double prev = 0, worst = 0, peak = 0;
    int started = 0, silentBlocks = 0, measured = 0;

    for (int b = 0; b < SR * 4 / burst; b++) {
        // A shift that drifts a whole tone up and back over a few seconds,
        // standing in for a detector tracking a real voice.
        const double t = (double)b * burst / SR;
        const float wander = (float)(7.0 + 2.0 * sin(2.0 * M_PI * 0.25 * t));
        gf_harmony_set_voice(h, 0, wander, 0.7f);
        gf_harmony_set_voice(h, 1, wander + 5.0f, 0.7f);

        for (int i = 0; i < burst; i++, phase++) in[i] = testSample(phase, 0.5);
        gf_harmony_process(h, in, out, burst);

        if (b <= SR / burst) { prev = out[burst - 1]; continue; }   // warm-up

        // A block that came out silent after warm-up means a voice dropped
        // back into re-priming.
        double blockPeak = 0;
        for (int i = 0; i < burst; i++) {
            const double a = fabs(out[i]);
            if (a > blockPeak) blockPeak = a;
        }
        if (blockPeak < 1e-6) silentBlocks++;
        measured++;

        for (int i = 0; i < burst; i++) {
            if (started) {
                const double step = fabs(out[i] - prev);
                if (step > worst) worst = step;
            }
            prev = out[i];
            started = 1;
            if (fabs(out[i]) > peak) peak = fabs(out[i]);
        }
    }
    gf_harmony_destroy(h);

    const double ratio = (peak > 1e-9) ? worst / peak : 0;
    char detail[200];
    snprintf(detail, sizeof detail,
             "%d silent block(s) of %d, worst step %.1f%% of peak "
             "(the tone's own slew is 8.6%%)",
             silentBlocks, measured, 100.0 * ratio);
    report("continuous while the shift wanders", silentBlocks == 0 && ratio < 0.10,
           detail);
}

// ── Entry point ──────────────────────────────────────────────────────────────

int main(void) {
    printf("gf_harmonizer_smoke_test — Audio Harmonizer offline checks\n\n");

    testHeadroom();
    testLevelIsIndependentOfVoiceCount();
    testContinuity();
    testIntervalGainFlatness();
    testModulatedPitchStaysContinuous();

    printf("\n");
    if (g_failures == 0) {
        printf("ALL TESTS PASSED\n");
        return 0;
    }
    printf("%d TEST(S) FAILED\n", g_failures);
    return 1;
}
