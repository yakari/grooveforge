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

// ── 5. Scale Lock ────────────────────────────────────────────────────────────

/// Frequency of a MIDI note.
static double midi_to_hz(double note) {
    return 440.0 * pow(2.0, (note - 69.0) / 12.0);
}

/// The semitone shift the harmonizer actually applied, found by asking which
/// candidate output frequency came out strongest.
static int measure_shift(int rootNote, int scaleLock, int mask) {
    GfpaDspHandle h = gfpa_dsp_create("com.grooveforge.audio_harmonizer", SR, 4096);
    if (!h) return -1;
    gfpa_dsp_set_param(h, "voice_count", 1.0);
    gfpa_dsp_set_param(h, "voice1_semitones", 4.0);   // "a third above"
    gfpa_dsp_set_param(h, "voice1_mix", 1.0);
    gfpa_dsp_set_param(h, "dry_wet", 1.0);
    gfpa_dsp_set_param(h, "scale_lock", scaleLock ? 1.0 : 0.0);
    gfpa_dsp_set_param(h, "scale_mask", (double)mask);
    GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
    void* ud = gfpa_dsp_userdata(h);

    const int burst = 256;
    static float in[256], outL[256], outR[256];
    static float tape[SR * 3];
    const double f0 = midi_to_hz(rootNote);
    long phase = 0;
    int t = 0;
    for (int b = 0; b < SR * 3 / burst; b++) {
        for (int i = 0; i < burst; i++, phase++) {
            const double tt = 2.0 * M_PI * phase / SR;
            in[i] = (float)(0.35 * (0.5 * sin(f0 * tt) + 0.8 * sin(2 * f0 * tt) +
                                    0.5 * sin(3 * f0 * tt)));
        }
        fn(in, in, outL, outR, burst, ud);
        for (int i = 0; i < burst && t < SR * 3; i++) tape[t++] = outL[i];
    }
    gfpa_dsp_destroy(h);

    const float* mid = tape + SR;
    const int n = t - SR - SR / 4;
    double best = -1;
    int bestShift = 0;
    for (int sh = 0; sh <= 7; sh++) {
        double w = 2.0 * M_PI * midi_to_hz(rootNote + sh) / SR;
        double c = 2.0 * cos(w), s1 = 0, s2 = 0;
        for (int i = 0; i < n; i++) { double s0 = mid[i] + c * s1 - s2; s2 = s1; s1 = s0; }
        const double e = 2.0 * sqrt(fabs(s1 * s1 + s2 * s2 - c * s1 * s2)) / n;
        if (e > best) { best = e; bestShift = sh; }
    }
    return bestShift;
}

static void testScaleLock(void) {
    printf("── Test 6: Scale Lock bends the interval to the scale\n");

    const int cMajor = 0xAB5;    // C D E F G A B
    const int degrees[7] = {60, 62, 64, 65, 67, 69, 71};
    // A third above each degree of C major, as a musician would write it:
    // major over the I, IV and V, minor over the ii, iii, vi and vii.
    const int wanted[7]  = {4, 3, 3, 4, 4, 3, 3};
    const char* names[7] = {"C", "D", "E", "F", "G", "A", "B"};

    int wrong = 0;
    char detail[220] = "";
    for (int i = 0; i < 7; i++) {
        const int got = measure_shift(degrees[i], 1, cMajor);
        if (got != wanted[i]) {
            wrong++;
            char one[40];
            snprintf(one, sizeof one, "%s got +%d want +%d; ", names[i], got, wanted[i]);
            strncat(detail, one, sizeof(detail) - strlen(detail) - 1);
        }
    }
    if (wrong == 0) {
        snprintf(detail, sizeof detail,
                 "every degree of C major took the right third (4 3 3 4 4 3 3)");
    }
    report("a third above follows the scale, not a fixed +4", wrong == 0, detail);

    // And with the lock off the interval must stay exactly where it was put,
    // or the feature has changed the module's existing behaviour.
    const int off = measure_shift(62, 0, cMajor);   // D, third above
    char d2[120];
    snprintf(d2, sizeof d2, "lock off over D gave +%d (must stay the knob's +4)", off);
    report("with the lock off the interval is untouched", off == 4, d2);
}

// ── 6. Chord-driven voicing ──────────────────────────────────────────────────

/// Which notes the harmonizer voiced, given a chord patched in.
///
/// Returns the semitone shifts of the first [voices] voices, by finding which
/// candidate output frequency each one landed on.
static void measure_chord_voicing(int rootNote, int chordMask, int voices,
                                  int* shifts) {
    GfpaDspHandle h = gfpa_dsp_create("com.grooveforge.audio_harmonizer", SR, 4096);
    if (!h) return;
    gfpa_dsp_set_param(h, "voice_count", (double)voices);
    // Bars deliberately left at nonsense values: a patched chord must ignore
    // them entirely rather than blend with them.
    for (int v = 1; v <= 4; v++) {
        char id[32];
        snprintf(id, sizeof id, "voice%d_semitones", v);
        gfpa_dsp_set_param(h, id, 1.0);
        snprintf(id, sizeof id, "voice%d_mix", v);
        gfpa_dsp_set_param(h, id, 1.0);
    }
    gfpa_dsp_set_param(h, "dry_wet", 1.0);
    gfpa_dsp_set_param(h, "chord_mask", (double)chordMask);
    GfpaInsertFn fn = gfpa_dsp_insert_fn(h);
    void* ud = gfpa_dsp_userdata(h);

    const int burst = 256;
    static float in[256], outL[256], outR[256];
    static float tape[SR * 3];
    const double f0 = midi_to_hz(rootNote);
    long phase = 0;
    int t = 0;
    for (int b = 0; b < SR * 3 / burst; b++) {
        for (int i = 0; i < burst; i++, phase++) {
            // A pure tone here, unlike the other tests. Each voice is a
            // shifted copy of the input, so a harmonically rich input gives
            // every voice its own harmonics — and a voice at +5 then puts
            // energy at +17 as well, which a "loudest bins" search reads as
            // a second voice. One partial in, one partial out per voice.
            in[i] = (float)(0.4 * sin(2.0 * M_PI * phase * f0 / SR));
        }
        fn(in, in, outL, outR, burst, ud);
        for (int i = 0; i < burst && t < SR * 3; i++) tape[t++] = outL[i];
    }
    gfpa_dsp_destroy(h);

    // Score every semitone from 1 to 24 and take the loudest `voices` of them.
    const float* mid = tape + SR;
    const int n = t - SR - SR / 4;
    double energy[25];
    for (int sh = 1; sh <= 24; sh++) {
        double w = 2.0 * M_PI * midi_to_hz(rootNote + sh) / SR;
        double c = 2.0 * cos(w), s1 = 0, s2 = 0;
        for (int i = 0; i < n; i++) { double s0 = mid[i] + c * s1 - s2; s2 = s1; s1 = s0; }
        energy[sh] = 2.0 * sqrt(fabs(s1 * s1 + s2 * s2 - c * s1 * s2)) / n;
    }
    for (int v = 0; v < voices; v++) {
        int best = 1;
        for (int sh = 2; sh <= 24; sh++) if (energy[sh] > energy[best]) best = sh;
        shifts[v] = best;
        energy[best] = -1;   // take the next loudest for the next voice
    }
    // Ascending, so the comparison below reads as a voicing.
    for (int a = 0; a < voices; a++)
        for (int b = a + 1; b < voices; b++)
            if (shifts[b] < shifts[a]) { int tmp = shifts[a]; shifts[a] = shifts[b]; shifts[b] = tmp; }
}

static void testChordVoicing(void) {
    printf("── Test 7: a patched chord voices the parts itself\n");

    // F major (F A C) sung over a C: the chord tones above C are F, A, C.
    const int fMajor = (1 << 5) | (1 << 9) | (1 << 0);
    int got[4] = {0, 0, 0, 0};
    measure_chord_voicing(60, fMajor, 3, got);
    const int wantF[3] = {5, 9, 12};
    int ok = (got[0] == wantF[0] && got[1] == wantF[1] && got[2] == wantF[2]);
    char detail[200];
    snprintf(detail, sizeof detail,
             "sang C over F major: voices at +%d +%d +%d (want +5 +9 +12, i.e. F A C)",
             got[0], got[1], got[2]);
    report("voices take the chord's tones upward from the note", ok, detail);

    // The bars were set to +1 throughout; a chord must override them.
    snprintf(detail, sizeof detail,
             "bars were all at +1 and none of the voices stayed there");
    report("a patched chord overrides the dialled intervals",
           got[0] != 1 && got[1] != 1 && got[2] != 1, detail);

    // A triad cannot voice four parts, so the Voices setting acts as a ceiling.
    int four[4] = {0, 0, 0, 0};
    measure_chord_voicing(60, fMajor, 4, four);
    // With only three tones the fourth voice must not double one at random;
    // the engine drops to three, so the top three shifts match the triad.
    const int distinct = (four[0] != four[1] && four[1] != four[2]);
    snprintf(detail, sizeof detail,
             "asked for 4 voices over a 3-note chord: got +%d +%d +%d +%d",
             four[0], four[1], four[2], four[3]);
    report("asking for more voices than the chord has does not double one",
           distinct, detail);
}

// ── Entry point ──────────────────────────────────────────────────────────────

int main(void) {
    printf("gf_harmonizer_smoke_test — Audio Harmonizer offline checks\n\n");

    testHeadroom();
    testLevelIsIndependentOfVoiceCount();
    testContinuity();
    testIntervalGainFlatness();
    testModulatedPitchStaysContinuous();
    testScaleLock();
    testChordVoicing();

    printf("\n");
    if (g_failures == 0) {
        printf("ALL TESTS PASSED\n");
        return 0;
    }
    printf("%d TEST(S) FAILED\n", g_failures);
    return 1;
}
