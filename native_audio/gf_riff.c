// gf_riff.c — Riff: a physically modelled electric guitar. See gf_riff.h.

#include "gf_riff.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SSE__) || defined(_M_X64) || defined(_M_AMD64)
#include <xmmintrin.h>
#define GF_RIFF_HAS_SSE 1
#endif

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/// Ring buffer size: holds the longest loop (low E bent down an octave at
/// 192 kHz, about 4700 samples) and the longest pick burst.
#define BUF 8192
#define MASK (BUF - 1)

/// Samples between two updates of the slowly moving values (pitch, filter
/// coefficients, pickup mix). Within a chunk they ramp linearly.
#define CHUNK 32

/// Two planes of vibration per string.
#define POLS 2

/// Open strings in standard tuning, low E to high E.
static const int k_open[GF_RIFF_STRINGS] = {40, 45, 50, 55, 59, 64};

/// Pickup positions as a fraction of the open string's length, measured from
/// the bridge (typical of a three-pickup guitar), and the gap between a
/// humbucker's two coils.
static const double k_pickup_pos[3] = {0.25, 0.16, 0.07};
static const double k_coil_gap = 0.028;

/// Level trims that bring the three pickups to the same loudness: the
/// bridge pickup hears much less of the fundamental, as on a real guitar,
/// where it is wound hotter to compensate.
static const float k_pickup_gain[3] = {0.80f, 1.0f, 1.65f};

/// Stiffness all-passes per vibration plane. Four first-order sections
/// reach the inharmonicity of real strings to within about a quarter up to
/// the 20th harmonic; two fell short by a factor of a hundred.
#define DISP_SECTIONS 4

/// Inharmonicity coefficient B of each open string (a light electric set,
/// after measurements quoted by Fastl and Völk): harmonic n sounds at
/// n f0 sqrt(1 + B n^2) instead of n f0. B grows as the square of the
/// fretted string's shortening.
static const double k_inharm[GF_RIFF_STRINGS] = {1.1e-4, 6.5e-5, 4.5e-5, 3.0e-5, 2.5e-5, 2.0e-5};

/// Spread of the strings' tuning, cents: no guitar is perfectly in tune
/// with itself, and under distortion the slow beating between strings
/// that are a hair apart is much of what makes a chord sound played.
#define INTONATION_CENTS 0.8f

/// The finger's pressure drifts the pitch by up to this much, slowly.
#define DRIFT_CENTS 0.6f

/// Frequency where the "high" decay time is set.
#define HIGH_HZ 4000.0

/// Fully palm-muted string: how long it rings, seconds.
#define PALM_T60 0.12

/// Released string: how fast the finger's lift damps it.
#define RELEASE_T60 0.09
#define RELEASE_T60_HIGH 0.03

/// Re-picking a ringing string damps it this long first, as the pick does,
/// down to REPICK_FLOOR of its level.
#define REPICK_SEC 0.003
#define REPICK_FLOOR 0.03f

/// Cost of playing a note out of a string's range (see string_cost): above
/// any fret, so a string in range always wins, but below a ringing string, so
/// a free string retuned for the note beats cutting a sustained one short.
#define OUT_OF_RANGE_COST 50.0

/// Fingers a string can hold down under its sounding note: the notes a
/// pull-off can fall back to.
#define MAX_FINGERS 4

/// Notes struck closer together than this are a chord, never a slur: a hand
/// on a keyboard spreads a chord over a few milliseconds.
#define LEGATO_CHORD_SEC 0.03

/// Hammer-on and pull-off: the level of the finger's tap or pluck, as a
/// share of a pick at the same velocity, and how bright it is. A hammer is a
/// soft thud; a pull-off plucks the string with the fingertip.
#define HAMMER_LEVEL 0.30f
#define HAMMER_BRIGHT 0.30f
#define PULL_LEVEL 0.45f
#define PULL_BRIGHT 0.55f

/// A hammer-on or pull-off puts energy back into the string: a guitarist's
/// fretting hand keeps a run like Thunderstruck at an even level for as long
/// as it goes on. A slur brings the string back up to this share of the
/// power its pick reached (scaled by how hard the slur is played against the
/// pick), over BOOST_SEC so the rise has no click, and by at most
/// BOOST_MAX in amplitude so a string that has all but died stays quiet.
#define SLUR_SUSTAIN 0.7f

/// Sustain pedal: at full Pedal sustain, strings ring this many times longer
/// than when their keys are only held (about 10 minutes for the low E: as
/// good as endless). The highs gain the square root of it, so a long ring
/// still mellows as a string's does.
#define PEDAL_STRETCH 40.0
#define MAX_T60 600.0

/// Feedback (the amp's sound driving the strings back): the amplitude a
/// string's chosen harmonic settles at with Feedback at full, about a hard
/// pick's, and how fast it can grow there, in nepers a second (5: from a
/// whisper to full in about a second, the bloom of a guitar facing its amp).
#define FB_LEVEL 0.30f
#define FB_GROWTH 5.0f
/// Width of the filter that picks the harmonic out of the string.
#define FB_Q 6.0
/// Highest harmonic frequency that feeds back: past it the chosen harmonic
/// steps down. A guitar's feedback lives well below this; up there a short
/// string loses more per trip than any amp gives back.
#define FB_MAX_HZ 3000.0
/// Integral gain of the feedback's level control, nepers a second per
/// second of error, and its bounds: it makes up the losses the makeup term
/// does not model (the interpolation's own high-frequency loss on a short
/// loop), so even the top of the neck holds its harmonic.
#define FB_KI 10.0f
#define FB_INT_MIN -10.0f
#define FB_INT_MAX 60.0f
/// Safety rails. The level control only sees the string through its
/// band-pass; bent far off the harmonic it was tuned for, energy can build
/// where the band-pass hardly looks. So the drive is capped per trip round
/// the loop, and stops outright while the string's whole power is above
/// what a hard pick reaches (about 0.14, see FB_LEVEL).
#define FB_DRIVE_MAX 0.08
#define FB_ENV_MAX 0.2f
#define BOOST_SEC 0.003
#define BOOST_MAX 4.0f

/// Output scale: six strings struck at once at full velocity, the loudest
/// thing a player can do, stay just below full scale; a single note picked
/// hard peaks around -17 dBFS, about where a guitar's DI signal sits.
#define OUT_GAIN 0.14f

/// Strength of the pitch glide after a hard pick (see tension_ratio).
#define TENSION_K 0.035f

typedef struct {
    float buf[POLS][BUF];  ///< The loops, one per vibration plane.
    float hist[BUF];       ///< The string's motion, for the pickups.
    float exc[BUF];        ///< Pick burst still to inject.
    int   w;               ///< Write index, shared by every ring.
    int   exc_len, exc_pos;

    int   note;            ///< MIDI note whose key owns the string, -1 when free.
    /// Note the loop is tuned to. Differs from [note] only while a re-pick
    /// damps the string: the loop keeps the old note's length, stiffness
    /// and losses until the new pick starts. Retuning the loop for the new
    /// note with the old note's stiffness left a few-sample loop with
    /// all-passes designed for a long one, which can run away.
    int   tuned;
    int   fret;
    int   held;            ///< The key is down.
    int   sustained;       ///< Released while the sustain pedal was down.
    int   released;        ///< Finger lifted: the string is being damped.
    int   active;          ///< Worth computing.
    unsigned age;          ///< Order of the last pick, for stealing.
    double started;        ///< When the last note started, in samples.
    /// Keys still down under the sounding note (legato), oldest first: a
    /// pull-off falls back to the last of them.
    int   fingers[MAX_FINGERS];
    int   n_fingers;
    float peak_env;        ///< Highest [env] since the last pick.
    int   boost_left;      ///< Samples of a slur's energy boost still to go.
    float loss_stretch;    ///< Pedal stretch the loss filters were solved for.
    // Feedback: a band-pass on the string's own motion, centred on the
    // harmonic that blooms, and the power found there.
    float fb_b0, fb_a1, fb_a2;
    float fb_x1, fb_x2, fb_y1, fb_y2;
    float fb_pow;
    float fb_prev;         ///< The string's last output sample.
    int   fb_note, fb_harm; ///< What the band-pass is tuned for.
    float fb_w;            ///< Its centre, radians per sample.
    float fb_int;          ///< Integral of the level error, nepers a second.
    float boost_mul;       ///< Per-sample step of [gain] during it.
    float vel;             ///< Velocity of the last pick, 0-1.

    // A pick waiting for the string to be damped first.
    int   repick_left;
    float repick_mul;      ///< Per-sample step of [gain] while damping.
    /// Gain applied to the whole loop as it is read. The rings hold the
    /// string's motion divided by it, so lowering it fades every point of
    /// the string at once — damping by the loop filter alone would take a
    /// full trip round the loop, longer than a pick's touch on a low string.
    float gain;
    int   pending_note, pending_fret, pending_vel;

    double open_period;    ///< Samples per period of the open string.
    float d[POLS];         ///< Current delay read, in samples.
    float lp[POLS];        ///< Loss filter state.
    float ap_x[POLS][DISP_SECTIONS], ap_y[POLS][DISP_SECTIONS];  ///< Stiffness.
    float la[POLS], lb[POLS];            ///< Loss filter: y = lb*x - la*y1.
    float c_disp;          ///< Stiffness all-pass coefficient, set per note.
    float intonation;      ///< This string's fixed tuning offset, cents.
    float drift, drift_to; ///< Slow pitch drift, cents, and where it heads.
    int   drift_left;      ///< Samples until the drift picks a new target.
    // The scrape of the pick, which the pickup hears before the string
    // settles into its note: a short burst of high-passed noise.
    int   scrape_left;
    float scrape_amp, scrape_decay, scrape_hp;
    float loss_pm;         ///< Palm mute the loss filters were solved for.
    float loss_sus;        ///< Sustain they were solved for.
    int   loss_rel;        ///< Release state they were solved for.
    int   loss_note;       ///< Note they were solved for (-1 = never).
    float env;             ///< Smoothed power: pitch glide and silence.
    double period_eff;     ///< Last full loop length, for inspection.
} rstring;

struct gf_riff {
    float rate;
    gf_riff_params p;
    rstring s[GF_RIFF_STRINGS];
    unsigned clock;        ///< Pick counter.
    unsigned noise;        ///< Noise generator state.

    float bend;            ///< Pitch bend, -1..1, as received.
    float bend_s;          ///< Smoothed: wheels and ribbons send steps.
    float vib_depth;       ///< 0..1.
    double vib_phase;
    int   pedal;
    int   legato_pedal;    ///< MIDI CC 68 down.
    double time;           ///< Samples rendered so far.
    int   humanize;        ///< Intonation spread and drift on (test switch).

    // Smoothed controls.
    float pm;              ///< Palm mute.
    float pick_w[3];       ///< Pickup mix: neck, middle, bridge.
    float hb;              ///< Humbucker blend.
    float tone;
    float level;
    float fb;              ///< Feedback amount, 0-1.

    // Pickup resonance: RBJ low-pass, coefficients for [res_tone, res_hb].
    float res_b0, res_b1, res_b2, res_a1, res_a2;
    float res_x1, res_x2, res_y1, res_y2;
    float res_tone, res_hb;
    float dc_x1, dc_y1, dc_g;  ///< DC blocker.
};

// ── Small helpers ────────────────────────────────────────────────────────────

static float clampf(float x, float lo, float hi) {
    return x < lo ? lo : (x > hi ? hi : x);
}

/// White noise in [-1, 1] from a 32-bit LCG: allocation-free and fast.
static float noise(gf_riff* r) {
    r->noise = r->noise * 1664525u + 1013904223u;
    return (float)((int32_t)r->noise) * (1.0f / 2147483648.0f);
}

static double note_hz(double note) { return 440.0 * pow(2.0, (note - 69.0) / 12.0); }

/// Reads ring [b] [delay] samples back from write index [w], between samples,
/// by third-order Lagrange interpolation. [delay] must be at least 2.
static float read_lagrange(const float* b, int w, float delay) {
    const int base = (int)floorf(delay) - 1;
    const float d = delay - (float)base;      // in [1, 2)
    const float dm1 = d - 1.0f, dm2 = d - 2.0f, dm3 = d - 3.0f;
    const float h0 = -dm1 * dm2 * dm3 * (1.0f / 6.0f);
    const float h1 = d * dm2 * dm3 * 0.5f;
    const float h2 = -d * dm1 * dm3 * 0.5f;
    const float h3 = d * dm1 * dm2 * (1.0f / 6.0f);
    const int i = w - base;
    return h0 * b[i & MASK] + h1 * b[(i - 1) & MASK]
         + h2 * b[(i - 2) & MASK] + h3 * b[(i - 3) & MASK];
}

/// Reads ring [b] [delay] samples back, linearly interpolated: enough for
/// the pickup and pick combs, whose delays move slowly if at all.
static float read_linear(const float* b, int w, float delay) {
    const int k = (int)delay;
    const float f = delay - (float)k;
    const float a = b[(w - k) & MASK], c = b[(w - k - 1) & MASK];
    return a + (c - a) * f;
}

// ── Loss filter and tuning ──────────────────────────────────────────────────

/// |1 + a e^{-jw}|: the loss filter's denominator magnitude.
static double den_mag(double a, double w) {
    const double re = 1.0 + a * cos(w), im = -a * sin(w);
    return sqrt(re * re + im * im);
}

/// Phase delay, in samples, of the loss filter b / (1 + a z^-1) at [w].
static double loss_delay(double a, double w) {
    return atan2(-a * sin(w), 1.0 + a * cos(w)) / w;
}

/// Phase delay of one all-pass (c + z^-1) / (1 + c z^-1) at [w].
static double allpass_delay(double c, double w) {
    const double num = atan2(-sin(w), c + cos(w));
    const double den = atan2(-c * sin(w), 1.0 + c * cos(w));
    return -(num - den) / w;
}

/// Decay time of the fundamental, seconds, for note frequency [f0]: the
/// sustain control sets the open low E's, and higher notes die sooner, as
/// on a real guitar.
static double t60_fundamental(double sustain, double f0) {
    const double ref = 2.0 * pow(10.0, sustain);
    return ref * pow(note_hz(k_open[0]) / f0, 0.9);
}

/// Solves the loss filter of plane [pol] of string [s] so its fundamental
/// dies in [t0] seconds and the 4 kHz region in [th]: two conditions, two
/// coefficients. Bisection on the pole (the decay ratio is monotonic in it),
/// then the gain from the first condition.
static void solve_loss(gf_riff* r, rstring* s, int pol, double f0, double t0, double th) {
    const double w0 = 2.0 * M_PI * f0 / r->rate;
    const double hh = fmin(HIGH_HZ, 0.45 * r->rate);
    const double wh = 2.0 * M_PI * fmax(hh, 1.5 * f0) / r->rate;
    // Gain per trip round the loop; the loop runs f0 times a second.
    const double m0 = pow(10.0, -3.0 / (f0 * t0));
    const double mh = pow(10.0, -3.0 / (f0 * th));
    const double want = mh / m0;   // how much more the highs lose per trip
    double lo = -0.999, hi = 0.0;
    for (int i = 0; i < 40; ++i) {
        const double a = 0.5 * (lo + hi);
        const double ratio = den_mag(a, w0) / den_mag(a, wh);
        if (ratio > want) hi = a; else lo = a;   // more negative = darker
    }
    const double a = 0.5 * (lo + hi);
    double b = m0 * den_mag(a, w0);
    // The loop must never gain at DC, or a pick could build up an offset.
    if (b / (1.0 + a) > 0.99995) b = 0.99995 * (1.0 + a);
    s->la[pol] = (float)a;
    s->lb[pol] = (float)b;
}

/// Delay the loop's filters add at [f0]: the loss filter and the stiffness
/// all-passes. Subtracted from the delay line so the note is in tune.
static double filter_delay(const gf_riff* r, const rstring* s, int pol, double f0) {
    const double w0 = 2.0 * M_PI * f0 / r->rate;
    double d = loss_delay(s->la[pol], w0);
    if (s->c_disp != 0.0f) d += DISP_SECTIONS * allpass_delay(s->c_disp, w0);
    return d;
}

/// The two planes beat slowly against each other: a fraction of a hertz on
/// the low strings, a little more higher up. The main plane, picked harder
/// and ringing longer, is the note; the second sits slightly sharp of it.
static double plane_hz(const gf_riff* r, int pol, double f0) {
    if (!r->humanize) return f0;
    const double beat = 0.25 + 0.0015 * f0;
    return pol == 0 ? f0 : f0 + beat;
}

/// Second plane: picked less hard, and dies a little sooner.
static const float k_plane_exc[POLS] = {0.7f, 0.3f};
static const double k_plane_t60[POLS] = {1.0, 0.6};

// ── String assignment ───────────────────────────────────────────────────────

/// Moves [note] by octaves into the range the guitar can play: a piano's,
/// far wider than a real guitar's, so a keyboard player never hears a note
/// jump an octave in the middle of a line. Only notes past a piano's ends
/// fold back.
static int fold_note(int note) {
    while (note < GF_RIFF_NOTE_MIN) note += 12;
    while (note > GF_RIFF_NOTE_MAX) note -= 12;
    return note;
}

/// How many semitones [note] lies outside string [i]'s range, 0 inside it.
/// Below the low E, the low string plays the note as if tuned down (a
/// baritone guitar); past the 24th fret, the high string keeps climbing.
/// Every other string's range is its open note to its 24th fret.
static int out_of_range(int i, int note) {
    const int fret = note - k_open[i];
    const int lowest = i == 0 ? GF_RIFF_NOTE_MIN - k_open[0] : 0;
    const int highest = i == GF_RIFF_STRINGS - 1 ? GF_RIFF_NOTE_MAX - k_open[i] : GF_RIFF_FRETS;
    if (fret < lowest) return lowest - fret;
    if (fret > highest) return fret - highest;
    return 0;
}

/// How unwelcome string [i] is for [note]: low frets first (open-position
/// voicings, as a guitarist reaches for), strings still held or ringing
/// last; a string out of its range only when the ones in range are busy.
static double string_cost(const gf_riff* r, int i, int note) {
    const rstring* s = &r->s[i];
    const int fret = note - k_open[i];
    double cost = fret < 0 ? -fret : fret;
    // Out of its range, a string still plays the note, retuned: a keyboard
    // player's E2 and F2 together, which only the low E string reaches on a
    // real guitar, then both sound instead of one cutting the other off.
    const int out = out_of_range(i, note);
    if (out > 0) cost += OUT_OF_RANGE_COST + out;
    if (s->held) cost += 1000.0 + (double)(r->clock - s->age) * -0.001;
    else if (s->active && !s->released) cost += 100.0;
    else if (s->active) cost += 10.0;
    return cost;
}

/// Picks the string for [note]: the one already playing it, or the
/// cheapest. Among held strings, the cost favours the oldest pick, so a
/// seventh note steals the string that was picked first.
static int choose_string(const gf_riff* r, int note) {
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        if (r->s[i].active && r->s[i].note == note) return i;
    }
    int best = -1;
    double best_cost = 0.0;
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        const double c = string_cost(r, i, note);
        if (c < 0.0) continue;
        if (best < 0 || c < best_cost) { best = i; best_cost = c; }
    }
    return best;
}

// ── Picking ─────────────────────────────────────────────────────────────────

/// Builds the pick burst for string [s]: a smooth push, as the pick drags
/// the string aside and lets go, with a little noise for the scrape of the
/// pick and so no two picks are identical; low-passed by how
/// soft the attack and the note are, then combed by the pick position.
/// Scaled so the string starts at a level set by the velocity.
///
/// [bright] scales the cutoff: 1 for a pick, lower for a finger tapping or
/// plucking the string in a hammer-on or a pull-off.
static void build_burst(gf_riff* r, rstring* s, double period, float vel, float bright) {
    // A burst of at most 4 ms, and never longer than one trip round the loop.
    int len = (int)fmin(period, 0.004 * r->rate);
    if (len < 8) len = 8;
    // Brightness: a hard pick and a hard note reach high; a finger is dark.
    const double atk = r->p.attack;
    double fc = 900.0 + 7000.0 * pow(atk, 1.5) * (0.35 + 0.65 * vel);
    fc *= 1.0 - 0.35 * r->pm;   // the palm also dulls the attack
    fc *= bright;
    const float k = (float)(1.0 - exp(-2.0 * M_PI * fc / r->rate));
    float l1 = 0.0f, l2 = 0.0f;
    // Pick position: from near the bridge (thin) to over the neck (round),
    // a fraction of the open string, as the pick does not move with frets.
    const double beta = 0.05 + 0.30 * clampf(r->p.pick_pos, 0.0f, 1.0f);
    float comb = (float)(beta * s->open_period);
    if (comb > 0.5f * (float)period) comb = 0.5f * (float)period;
    const int total = len + (int)comb + 2;
    float* e = s->exc;
    for (int i = 0; i < total; ++i) {
        float x = 0.0f;
        if (i < len) {
            const float win = 0.5f - 0.5f * cosf(2.0f * (float)M_PI * (i + 0.5f) / len);
            // The push is mostly a smooth bump; the noise share is small so
            // picks vary by about a decibel, as a player's do, not more.
            x = win * (1.0f + 0.35f * noise(r));
        }
        l1 += (x - l1) * k;
        l2 += (l1 - l2) * k;
        e[i] = l2;
    }
    // Comb, in place from the end so earlier samples are still unfiltered.
    for (int i = total - 1; i >= 0; --i) {
        const float back = (float)i - comb;
        float v = 0.0f;
        if (back >= 0.0f) {
            const int k0 = (int)back;
            const float f = back - (float)k0;
            v = e[k0] + (e[k0 + 1 < total ? k0 + 1 : k0] - e[k0]) * f;
        }
        e[i] -= v;
    }
    // Level: the loop holds one period, so set its RMS over a period.
    double energy = 0.0;
    for (int i = 0; i < total; ++i) energy += (double)e[i] * e[i];
    const double target = 0.5 * pow(vel, 1.4);
    const float g = energy > 0.0 ? (float)(target * sqrt(period / energy)) : 0.0f;
    for (int i = 0; i < total; ++i) e[i] *= g;
    s->exc_len = total;
    s->exc_pos = 0;
}

/// Stretch, in cents, of harmonic [n] of a loop of [period] samples through
/// DISP_SECTIONS all-passes of coefficient [c], the loop being tuned so the
/// fundamental stays exact. Solved by fixed point: harmonic n sits where n
/// trips of 2 pi fit in the loop's delay at that frequency. Returns a huge
/// value when the coefficient cannot fit in the loop.
static double dispersion_stretch(double c, double period, int n) {
    const double w0 = 2.0 * M_PI / period;
    const double d = period - DISP_SECTIONS * allpass_delay(c, w0);
    if (d < 4.0) return 1e9;
    double w = n * w0;
    for (int i = 0; i < 12; ++i) {
        w = 2.0 * M_PI * n / (d + DISP_SECTIONS * allpass_delay(c, w));
        if (w >= M_PI) return 1e9;
    }
    return 1200.0 * log2(w / (n * w0));
}

/// Sets the stiffness all-passes of string [s] for [note] at [fret]: the
/// coefficient whose stretch of the 10th harmonic (or the highest one below
/// 40% of Nyquist) matches the string's inharmonicity. A note-on cost of a
/// few hundred trigonometric calls, nothing per sample.
static void design_dispersion(const gf_riff* r, rstring* s, int string, int note, int fret) {
    const double period = r->rate / note_hz(note);
    int n = (int)(0.2 * period);
    if (n > 10) n = 10;
    if (n < 2) { s->c_disp = 0.0f; return; }
    // Past the 24th fret the high string is an invented extension: its
    // stiffness stays where a real fretboard ends rather than growing
    // without bound as the string shortens.
    const int f = fret > GF_RIFF_FRETS ? GF_RIFF_FRETS : fret;
    // Never stiffer than the high E at its 24th fret, the stiffest a real
    // fretboard gets: a string playing out of its range (see string_cost),
    // such as the wound low E retuned for a note five octaves up, would
    // otherwise get all-passes so strong that a bend pumps energy into the
    // loop.
    const double b = fmin(k_inharm[string] * pow(2.0, 2.0 * f / 12.0),
                          k_inharm[GF_RIFF_STRINGS - 1] * pow(2.0, 2.0 * GF_RIFF_FRETS / 12.0));
    const double want = 1200.0 * log2(sqrt(1.0 + b * n * n));
    double lo = -0.95, hi = 0.0;   // more negative = more stretch
    for (int i = 0; i < 24; ++i) {
        const double c = 0.5 * (lo + hi);
        if (dispersion_stretch(c, period, n) > want) lo = c; else hi = c;
    }
    s->c_disp = (float)(0.5 * (lo + hi));
}

/// Starts [note] on string [s] now: the loop takes the new length and the
/// pick burst starts.
static void start_note(gf_riff* r, rstring* s, int note, int fret, int velocity) {
    s->n_fingers = 0;      // a pick starts afresh: no finger to pull off to
    s->peak_env = 0.0f;
    s->note = note;
    s->tuned = note;
    s->fret = fret;
    s->vel = clampf((float)velocity / 127.0f, 0.0f, 1.0f);
    s->released = 0;
    s->sustained = 0;
    s->active = 1;
    s->loss_note = -1;     // solve the loss filters again
    const double period = r->rate / note_hz(note);
    design_dispersion(r, s, (int)(s - r->s), note, fret);
    // The pick's scrape: brighter and louder for a hard pick, nearly
    // nothing for a finger.
    s->scrape_left = (int)(0.012 * r->rate);
    s->scrape_amp = 0.10f * powf(s->vel, 1.4f) * (0.15f + 0.85f * r->p.attack)
                  * (1.0f - 0.5f * r->pm);
    s->scrape_decay = expf(-1.0f / (0.0015f * r->rate));
    if (s->env < 1e-9f) {
        // A silent string starts at the right length rather than gliding.
        for (int p = 0; p < POLS; ++p) s->d[p] = (float)(r->rate / plane_hz(r, p, note_hz(note)));
    }
    build_burst(r, s, period, s->vel, 1.0f);
}

/// Ends a damping: folds the loop gain back into the rings, so the string
/// carries on from where the damping left it with the gain back at 1.
///
/// The whole ring is folded, not just the current loop: samples written
/// while the gain was low are stored large, and a new note lower than the
/// old one reads further back than the old loop reached. Leaving those
/// unfolded made a quick run of re-picks dropping in pitch explode. Two
/// rings of BUF samples, once per pick: a few microseconds.
static void end_damping(rstring* s) {
    for (int p = 0; p < POLS; ++p) {
        for (int k = 0; k < BUF; ++k) s->buf[p][k] *= s->gain;
    }
    s->gain = 1.0f;
    s->repick_left = 0;
}

// ── Public API: events ──────────────────────────────────────────────────────

// ── Legato: hammer-ons and pull-offs ──────────────────────────────────────────

/// Whether a new note slurs on string [last], the last one played: always
/// with the Legato switch or pedal; with Overlap, only when the new key went
/// down while [last]'s key was still held and no other key is, as a legato
/// line on a keyboard is played. A melody over a held chord is picked, so it
/// does not swallow a chord note.
static int legato_wanted(const gf_riff* r, int last) {
    if (r->p.legato || r->legato_pedal) return 1;
    if (!r->p.legato_overlap) return 0;
    const rstring* s = &r->s[last];
    if (!s->held) return 0;
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        if (i != last && r->s[i].held) return 0;
    }
    return 1;
}

/// The string a legato [note] slurs on, or -1 to pick it instead: the last
/// string played, if legato applies to it (legato_wanted), it still rings,
/// was not struck as part of a chord just now, and reaches [note] within a
/// hand's span (or [note] or its own note is the open string) and its range.
static int legato_string(const gf_riff* r, int note) {
    int last = -1;
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        const rstring* s = &r->s[i];
        if (!s->active || s->note < 0) continue;
        if (last < 0 || s->age > r->s[last].age) last = i;
    }
    if (last < 0 || !legato_wanted(r, last)) return -1;
    const rstring* s = &r->s[last];
    const int jump = note > s->note ? note - s->note : s->note - note;
    // An octave at most (GF_RIFF_LEGATO_REACH), but an open string needs no
    // finger: pulling off to it, or hammering from it, works from anywhere
    // on the neck.
    const int open = note == k_open[last] || s->fret == 0;
    if (jump == 0 || (jump > GF_RIFF_LEGATO_REACH && !open)) return -1;
    if (s->repick_left > 0 || s->env < 1e-7f) return -1;
    if (r->time - s->started < LEGATO_CHORD_SEC * r->rate) return -1;
    if (out_of_range(last, note) > 0) return -1;
    return last;
}

/// Moves string [s] to [note] without picking it: the fretting hand alone.
/// The loop takes the new length within a chunk and is topped back up
/// towards its pick's level (top_up); the finger adds a soft tap (hammer-on,
/// going up) or a small pluck (pull-off, going down).
/// Brings string [s] back up towards the power its pick reached, for a slur
/// played at velocity [vel] (0-1): see SLUR_SUSTAIN. Rides the loop gain, as
/// the re-pick damping does, so the whole string rises at once.
static void top_up(gf_riff* r, rstring* s, float vel) {
    if (s->repick_left > 0 || s->vel <= 0.0f || s->env < 1e-12f) return;
    const float rel = fminf(vel / s->vel, 1.0f);
    const float floor_env = s->peak_env * SLUR_SUSTAIN * powf(rel, 2.8f);
    if (s->env >= floor_env) return;
    const float k = fminf(sqrtf(floor_env / s->env), BOOST_MAX);
    if (s->boost_left > 0) end_damping(s);   // fold an unfinished boost in
    s->boost_left = (int)(BOOST_SEC * r->rate);
    if (s->boost_left < 1) s->boost_left = 1;
    s->boost_mul = powf(k, 1.0f / (float)s->boost_left);
}

static void slur(gf_riff* r, rstring* s, int note, float vel) {
    top_up(r, s, vel);
    const int up = note > s->note;
    s->note = note;
    s->tuned = note;
    s->fret = note - k_open[s - r->s];
    s->loss_note = -1;     // solve the loss filters for the new length
    design_dispersion(r, s, (int)(s - r->s), note, s->fret);
    const double period = r->rate / note_hz(note);
    if (up) build_burst(r, s, period, vel * HAMMER_LEVEL, HAMMER_BRIGHT);
    else build_burst(r, s, period, vel * PULL_LEVEL, PULL_BRIGHT);
}

/// Hammers [note] onto string [i]. The key that was sounding stays under
/// the finger if it is still down, so letting go of [note] pulls off to it.
static void hammer(gf_riff* r, int i, int note, int velocity) {
    rstring* s = &r->s[i];
    if (s->held && note > s->note && s->n_fingers < MAX_FINGERS) {
        s->fingers[s->n_fingers++] = s->note;
    }
    s->held = 1;
    s->released = 0;
    s->sustained = 0;
    s->age = ++r->clock;
    s->started = r->time;
    slur(r, s, note, clampf((float)velocity / 127.0f, 0.0f, 1.0f));
}

/// Forgets [note] as a finger held under some string's sounding note.
/// Returns 1 when it was one.
static int lift_finger(gf_riff* r, int note) {
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        rstring* s = &r->s[i];
        for (int k = 0; k < s->n_fingers; ++k) {
            if (s->fingers[k] != note) continue;
            for (int j = k + 1; j < s->n_fingers; ++j) s->fingers[j - 1] = s->fingers[j];
            s->n_fingers--;
            return 1;
        }
    }
    return 0;
}

void gf_riff_note_on(gf_riff* r, int note, int velocity) {
    if (!r) return;
    if (velocity <= 0) { gf_riff_note_off(r, note); return; }
    note = fold_note(note);
    const int li = legato_string(r, note);
    if (li >= 0) { hammer(r, li, note, velocity); return; }
    const int i = choose_string(r, note);
    if (i < 0) return;
    rstring* s = &r->s[i];
    s->held = 1;
    s->age = ++r->clock;
    s->started = r->time;
    const int fret = note - k_open[i];
    if (s->active && s->env > 1e-8f) {
        // Damp the ringing string for a few ms, then pick: no click, and no
        // pile-up of energy from repeated picks. A slur's boost still rising
        // is folded in first: both ride the same loop gain.
        if (s->boost_left > 0) { end_damping(s); s->boost_left = 0; }
        // Down to REPICK_FLOOR of full level, from wherever the gain is: a
        // pick landing on a damping still under way carries on to the same
        // floor instead of sinking it again.
        s->repick_left = (int)(REPICK_SEC * r->rate);
        if (s->repick_left < 1) s->repick_left = 1;
        s->repick_mul = s->gain > REPICK_FLOOR
                      ? powf(REPICK_FLOOR / s->gain, 1.0f / (float)s->repick_left) : 1.0f;
        s->pending_note = note;
        s->pending_fret = fret;
        s->pending_vel = velocity;
        s->note = note;   // the key now belongs to this string
        s->n_fingers = 0;
        s->released = 0;
        return;
    }
    start_note(r, s, note, fret, velocity);
}

/// Lifts the finger off string [s].
static void release_string(rstring* s) {
    s->held = 0;
    s->released = 1;
    s->sustained = 0;
}

void gf_riff_note_off(gf_riff* r, int note) {
    if (!r) return;
    note = fold_note(note);
    // A finger under a hammered note: lifting it changes nothing heard.
    if (lift_finger(r, note)) return;
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        rstring* s = &r->s[i];
        if (!s->held || s->note != note) continue;
        if (s->n_fingers > 0) {
            // Pull-off: the string falls back to the finger still down.
            slur(r, s, s->fingers[--s->n_fingers], s->vel);
            continue;
        }
        if (r->pedal) { s->held = 0; s->sustained = 1; }
        else release_string(s);
    }
}

void gf_riff_all_notes_off(gf_riff* r) {
    if (!r) return;
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        r->s[i].n_fingers = 0;
        if (r->s[i].boost_left > 0) { end_damping(&r->s[i]); r->s[i].boost_left = 0; }
        if (r->s[i].active) release_string(&r->s[i]);
        if (r->s[i].repick_left > 0) end_damping(&r->s[i]);
    }
}

void gf_riff_pitch_bend(gf_riff* r, float bend) {
    if (r) r->bend = clampf(bend, -1.0f, 1.0f);
}

void gf_riff_sustain_pedal(gf_riff* r, int down) {
    if (!r) return;
    r->pedal = down ? 1 : 0;
    if (r->pedal) return;
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        if (r->s[i].sustained) release_string(&r->s[i]);
    }
}

void gf_riff_legato_pedal(gf_riff* r, int down) {
    if (r) r->legato_pedal = down ? 1 : 0;
}

void gf_riff_vibrato(gf_riff* r, float depth) {
    if (r) r->vib_depth = clampf(depth, 0.0f, 1.0f);
}

// ── Per-chunk updates ───────────────────────────────────────────────────────

/// Solves the loss filters again when what they depend on moved: the note,
/// palm mute, sustain, or the finger lifting.
/// How much longer string [s] rings because of the sustain pedal: 1 unless
/// the pedal is down and the string is not being damped by a lifted finger.
static float pedal_stretch(const gf_riff* r, const rstring* s) {
    if (!r->pedal || s->released) return 1.0f;
    const double x = clampf(r->p.pedal_sustain, 0.0f, 1.0f);
    return (float)pow(PEDAL_STRETCH, x);
}

static void update_loss(gf_riff* r, rstring* s) {
    const float sus = r->p.sustain;
    const float stretch = pedal_stretch(r, s);
    if (s->loss_note == s->tuned && fabsf(s->loss_pm - r->pm) < 1e-3f
        && s->loss_sus == sus && s->loss_rel == s->released
        && s->loss_stretch == stretch) return;
    const double f0 = note_hz(s->tuned);
    // With the pedal down the string rings longer than held (see
    // PEDAL_STRETCH): the pedal is the player's sustainer.
    double t0 = fmin(t60_fundamental(sus, f0) * stretch, MAX_T60);
    // Palm mute: the hand on the strings cuts the ring to a fixed, short
    // time whatever the sustain, moving there on a log scale as the palm
    // presses harder. Shortening by a ratio was not enough: a heavy
    // distortion compresses a 1 s tail back up to full level, and the mute
    // vanished.
    const double press = pow(r->pm, 0.7);
    t0 = exp(log(t0) * (1.0 - press) + log(PALM_T60) * press);
    // Muted, the highs still die faster than the fundamental, but not so
    // fast that only a sine is left: a near-sine into a distortion pedal
    // comes out as a square wave, the sound of a 16-bit console.
    double th = t0 / sqrt(stretch) * (0.12 + 0.33 * r->pm);
    if (s->released) {
        t0 = fmin(t0, RELEASE_T60);
        th = fmin(th, RELEASE_T60_HIGH);
    }
    th = fmin(th, t0);
    for (int p = 0; p < POLS; ++p) {
        solve_loss(r, s, p, f0, t0 * k_plane_t60[p], th * k_plane_t60[p]);
    }
    s->loss_note = s->tuned;
    s->loss_pm = r->pm;
    s->loss_sus = sus;
    s->loss_rel = s->released;
    s->loss_stretch = stretch;
}

/// Pitch ratio from the string's energy: a hard pick stretches the string
/// and raises its pitch; it settles as the string calms down.
static double tension_ratio(const rstring* s) {
    return 1.0 + TENSION_K * s->env;
}

/// Target delay of plane [pol] for the current pitch, bend and vibrato.
static float target_delay(const gf_riff* r, rstring* s, int pol, double semis) {
    const double cents = r->humanize ? s->intonation + s->drift : 0.0;
    const double f0 = note_hz(s->tuned + semis + cents / 100.0) * tension_ratio(s);
    const double hz = plane_hz(r, pol, f0);
    double d = r->rate / hz - filter_delay(r, s, pol, hz);
    if (pol == 0) s->period_eff = r->rate / hz;
    return (float)fmax(2.0, fmin(d, BUF - 8.0));
}

/// Ends a damping-before-pick, starting the waiting note.
static void finish_repick(gf_riff* r, rstring* s) {
    end_damping(s);
    start_note(r, s, s->pending_note, s->pending_fret, s->pending_vel);
}

/// The guitar's tone knob and pickup type set the coil's resonance. Single
/// coils peak higher and sharper than humbuckers.
static void update_resonance(gf_riff* r) {
    if (fabsf(r->res_tone - r->tone) < 1e-4f && fabsf(r->res_hb - r->hb) < 1e-4f) return;
    r->res_tone = r->tone;
    r->res_hb = r->hb;
    const double base = 4300.0 + (2500.0 - 4300.0) * r->hb;
    double fc = base * pow(2.0, (r->tone - 0.7) * 1.6);
    fc = fmin(fc, 0.45 * r->rate);
    const double q = (0.75 + 1.6 * r->tone) * (1.0 - 0.25 * r->hb);
    const double w = 2.0 * M_PI * fc / r->rate, al = sin(w) / (2.0 * q), cw = cos(w);
    const double a0 = 1.0 + al;
    r->res_b0 = (float)((1.0 - cw) * 0.5 / a0);
    r->res_b1 = (float)((1.0 - cw) / a0);
    r->res_b2 = r->res_b0;
    r->res_a1 = (float)(-2.0 * cw / a0);
    r->res_a2 = (float)((1.0 - al) / a0);
}

/// Moves the smoothed controls one chunk towards their targets (~20 ms).
static void chase_controls(gf_riff* r) {
    const float k = 1.0f - expf(-(float)CHUNK / (0.02f * r->rate));
    float target_w[3] = {0.0f, 0.0f, 0.0f};
    switch (r->p.pickup) {
        case GF_RIFF_PICKUP_NECK: target_w[0] = 1.0f; break;
        case GF_RIFF_PICKUP_MIDDLE: target_w[1] = 1.0f; break;
        case GF_RIFF_PICKUP_BRIDGE: target_w[2] = 1.0f; break;
        default: target_w[0] = 0.6f; target_w[2] = 0.6f; break;
    }
    for (int i = 0; i < 3; ++i) r->pick_w[i] += (target_w[i] - r->pick_w[i]) * k;
    r->pm += (clampf(r->p.palm_mute, 0.0f, 1.0f) - r->pm) * k;
    r->hb += ((r->p.humbucker ? 1.0f : 0.0f) - r->hb) * k;
    r->tone += (clampf(r->p.tone, 0.0f, 1.0f) - r->tone) * k;
    const float lv = powf(10.0f, clampf(r->p.level_db, -60.0f, 12.0f) / 20.0f);
    r->level += (lv - r->level) * k;
    r->fb += (clampf(r->p.feedback, 0.0f, 1.0f) - r->fb) * k;
}

// ── Per-sample processing ───────────────────────────────────────────────────

/// One plane of one string, one sample: read the loop, lose energy, add
/// stiffness, add the pick, write back.
static float plane_tick(rstring* s, int p, float d, float exc) {
    float y = s->gain * read_lagrange(s->buf[p], s->w, d);
    s->lp[p] = s->lb[p] * y - s->la[p] * s->lp[p];
    y = s->lp[p];
    if (s->c_disp != 0.0f) {
        const float c = s->c_disp;
        for (int k = 0; k < DISP_SECTIONS; ++k) {
            const float o = c * y + s->ap_x[p][k] - c * s->ap_y[p][k];
            s->ap_x[p][k] = y;
            s->ap_y[p][k] = o;
            y = o;
        }
    }
    const float v = y + exc * k_plane_exc[p];
    s->buf[p][s->w] = v / s->gain;
    return v;
}

/// What the pickups hear of string [s] after the sample at [w-1] was
/// written: each pickup cancels the harmonics with a node under it.
static float pickup_tick(const gf_riff* r, const rstring* s) {
    const float h = s->hist[(s->w - 1) & MASK];
    const float cap = 0.95f * s->d[0];
    float out = 0.0f;
    for (int k = 0; k < 3; ++k) {
        const float wk = r->pick_w[k];
        if (wk < 1e-4f) continue;
        float d1 = (float)(k_pickup_pos[k] * s->open_period);
        float d2 = (float)((k_pickup_pos[k] + k_coil_gap) * s->open_period);
        if (d1 > cap) d1 = cap;
        if (d2 > cap) d2 = cap;
        const float t1 = read_linear(s->hist, s->w - 1, d1);
        float back = t1;
        if (r->hb > 1e-4f) {
            const float t2 = read_linear(s->hist, s->w - 1, d2);
            back = t1 + (t2 - t1) * 0.5f * r->hb;
        }
        out += wk * k_pickup_gain[k] * (h - back);
    }
    return out;
}

/// Renders one string over a chunk, adding into [out].
/// Moves the string's slow pitch drift one chunk: a new random target every
/// quarter to half second, approached over ~0.3 s.
static void chase_drift(gf_riff* r, rstring* s, int n) {
    s->drift_left -= n;
    if (s->drift_left <= 0) {
        s->drift_to = DRIFT_CENTS * noise(r);
        s->drift_left = (int)((0.25f + 0.25f * (noise(r) + 1.0f)) * r->rate);
    }
    s->drift += (s->drift_to - s->drift) * (1.0f - expf(-(float)n / (0.3f * r->rate)));
}

/// One sample of the pick's scrape: high-passed noise, decaying fast.
static float scrape_tick(gf_riff* r, rstring* s) {
    if (s->scrape_left <= 0) return 0.0f;
    s->scrape_left--;
    const float x = noise(r);
    const float hp = x - s->scrape_hp;   // first difference: a gentle high-pass
    s->scrape_hp = x;
    const float v = hp * s->scrape_amp;
    s->scrape_amp *= s->scrape_decay;
    return v;
}

// ── Feedback ────────────────────────────────────────────────────────────────

/// Harmonic numbers the Harmonic selector offers, in its order: the
/// fundamental, the octave, the octave and a fifth, two octaves.
static const int k_fb_harm[4] = {1, 2, 3, 4};

/// Tunes string [s]'s feedback band-pass on the chosen harmonic of its note,
/// or the highest one below FB_MAX_HZ (the fundamental at worst).
static void tune_feedback(gf_riff* r, rstring* s) {
    const int sel = r->p.fb_harmonic < 0 ? 0 : (r->p.fb_harmonic > 3 ? 3 : r->p.fb_harmonic);
    if (s->fb_note == s->tuned && s->fb_harm == sel) return;
    s->fb_int = 0.0f;   // a new note or harmonic starts its control afresh
    s->fb_note = s->tuned;
    s->fb_harm = sel;
    const double f0 = note_hz(s->tuned);
    int n = k_fb_harm[sel];
    while (n > 1 && n * f0 > fmin(FB_MAX_HZ, 0.4 * r->rate)) n--;
    const double fc = fmin(n * f0, 0.45 * r->rate);
    // RBJ band-pass, 0 dB at the centre.
    const double w = 2.0 * M_PI * fc / r->rate, al = sin(w) / (2.0 * FB_Q);
    s->fb_w = (float)w;
    const double a0 = 1.0 + al;
    s->fb_b0 = (float)(al / a0);
    s->fb_a1 = (float)(-2.0 * cos(w) / a0);
    s->fb_a2 = (float)((1.0 - al) / a0);
}

/// How much of string [s]'s band-passed motion goes back into it on every
/// sample during this chunk: the amp driving the string. Only a string free
/// to ring feeds back (held, or kept by the pedal; not one being damped, and
/// less and less under the palm), and only up to a level set by Feedback,
/// so the harmonic blooms, then holds instead of running away.
static float feedback_drive(gf_riff* r, rstring* s, int n) {
    const float target = FB_LEVEL * r->fb * (1.0f - r->pm);
    if (s->released || !(s->held || s->sustained) || target <= 1e-6f) {
        s->fb_int = 0.0f;
        return 0.0f;
    }
    if (s->env > FB_ENV_MAX) {
        s->fb_int = fminf(s->fb_int, 0.0f);
        return 0.0f;
    }
    const float amp = sqrtf(2.0f * s->fb_pow);   // RMS to peak, for a sine
    // Each trip round the loop scales the harmonic by (1 + drive). First
    // make up what the loop loses there on a trip (the loss filter's gain
    // at the harmonic; upper harmonics die fast, so this is most of it on a
    // high note), then grow or shrink by up to FB_GROWTH nepers a second
    // towards the target, spread over the trips the loop makes.
    const double loss = (double)s->lb[0] / den_mag(s->la[0], s->fb_w);
    const double makeup = loss > 1e-3 ? 1.0 / loss - 1.0 : 0.0;
    const float err = clampf((target - amp) / target, -1.0f, 1.0f);
    s->fb_int = clampf(s->fb_int + FB_KI * err * (float)n / r->rate, FB_INT_MIN, FB_INT_MAX);
    const double drive = makeup + (FB_GROWTH * err + s->fb_int) / note_hz(s->tuned);
    return (float)fmax(0.0, fmin(drive, FB_DRIVE_MAX));
}

static void string_chunk(gf_riff* r, rstring* s, float* out, int n, double semis) {
    update_loss(r, s);
    chase_drift(r, s, n);
    float d0[POLS], step[POLS];
    for (int p = 0; p < POLS; ++p) {
        d0[p] = s->d[p];
        step[p] = (target_delay(r, s, p, semis) - d0[p]) / (float)n;
    }
    const float k_env = 1.0f - expf(-1.0f / (0.02f * r->rate));
    const int fb_on = r->fb > 1e-4f && s->tuned >= 0;
    float drive = 0.0f;
    if (fb_on) {
        tune_feedback(r, s);
        drive = feedback_drive(r, s, n);
    }
    for (int i = 0; i < n; ++i) {
        if (s->boost_left > 0) {
            s->gain *= s->boost_mul;
            if (--s->boost_left == 0) end_damping(s);
        }
        if (s->repick_left > 0) {
            s->gain *= s->repick_mul;
            if (--s->repick_left == 0) finish_repick(r, s);
        }
        float exc = 0.0f;
        if (s->exc_pos < s->exc_len) exc = s->exc[s->exc_pos++];
        if (fb_on) {
            // The harmonic, picked out of the string's last sample, fed back.
            const float x = s->fb_prev;
            const float y = s->fb_b0 * (x - s->fb_x2) - s->fb_a1 * s->fb_y1 - s->fb_a2 * s->fb_y2;
            s->fb_x2 = s->fb_x1; s->fb_x1 = x;
            s->fb_y2 = s->fb_y1; s->fb_y1 = y;
            s->fb_pow += (y * y - s->fb_pow) * k_env;
            exc += drive * y;
        }
        float h = 0.0f;
        for (int p = 0; p < POLS; ++p) {
            s->d[p] = d0[p] + step[p] * (float)(i + 1);
            h += plane_tick(s, p, s->d[p], exc);
        }
        s->fb_prev = h;
        s->hist[s->w] = h + scrape_tick(r, s);
        s->w = (s->w + 1) & MASK;
        s->env += (h * h - s->env) * k_env;
        out[i] += pickup_tick(r, s);
    }
    if (s->env > s->peak_env) s->peak_env = s->env;
    // A string that has died away, with no pick pending, stops computing.
    if (s->env < 1e-10f && s->exc_pos >= s->exc_len && s->repick_left == 0) {
        s->active = 0;
        if (!s->held) s->note = -1;
    }
}

/// Pickup resonance and DC blocker over a chunk, then the output level.
static void output_chunk(gf_riff* r, float* out, int n) {
    for (int i = 0; i < n; ++i) {
        const float x = out[i];
        const float y = r->res_b0 * x + r->res_b1 * r->res_x1 + r->res_b2 * r->res_x2
                      - r->res_a1 * r->res_y1 - r->res_a2 * r->res_y2;
        r->res_x2 = r->res_x1; r->res_x1 = x;
        r->res_y2 = r->res_y1; r->res_y1 = y;
        const float dc = y - r->dc_x1 + r->dc_g * r->dc_y1;
        r->dc_x1 = y;
        r->dc_y1 = dc;
        out[i] = dc * OUT_GAIN * r->level;
    }
}

static void process_chunk(gf_riff* r, float* out, int n) {
    chase_controls(r);
    update_resonance(r);
    // Bend and vibrato, in semitones, for the whole chunk.
    r->vib_phase += 2.0 * M_PI * 5.5 * n / r->rate;
    if (r->vib_phase > 2.0 * M_PI) r->vib_phase -= 2.0 * M_PI;
    // ~8 ms: fast enough to follow a hand, slow enough to round off the
    // steps a pitch wheel sends.
    r->bend_s += (r->bend - r->bend_s) * (1.0f - expf(-(float)n / (0.008f * r->rate)));
    const double semis = r->bend_s * clampf(r->p.bend_range, 0.0f, 12.0f)
                       + 0.4 * r->vib_depth * sin(r->vib_phase);
    memset(out, 0, sizeof(float) * (size_t)n);
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        if (r->s[i].active) string_chunk(r, &r->s[i], out, n, semis);
    }
    output_chunk(r, out, n);
}

void gf_riff_process(gf_riff* r, float* out, int n) {
    if (!r || !out || n <= 0) return;
#ifdef GF_RIFF_HAS_SSE
    // Flush denormals: decaying loops otherwise slow x86 floating point
    // down by orders of magnitude. Restored on the way out.
    const unsigned int csr = _mm_getcsr();
    _mm_setcsr(csr | 0x8040);
#endif
    for (int done = 0; done < n; done += CHUNK) {
        const int len = (n - done < CHUNK) ? (n - done) : CHUNK;
        process_chunk(r, out + done, len);
        r->time += len;
    }
#ifdef GF_RIFF_HAS_SSE
    _mm_setcsr(csr);
#endif
}

// ── Lifecycle and parameters ────────────────────────────────────────────────

void gf_riff_default_params(gf_riff_params* out) {
    out->palm_mute = 0.0f;
    out->pick_pos = 0.35f;
    out->pickup = GF_RIFF_PICKUP_BRIDGE;
    out->humbucker = 1;
    out->tone = 0.7f;
    out->sustain = 0.7f;
    out->attack = 0.7f;
    out->bend_range = 2.0f;
    out->level_db = 0.0f;
    out->legato = 0;
    out->legato_overlap = 0;
    out->pedal_sustain = 0.5f;
    out->feedback = 0.0f;
    out->fb_harmonic = 1;
}

void gf_riff_set_params(gf_riff* r, const gf_riff_params* p) {
    if (!r || !p) return;
    r->p = *p;
    if (r->p.pickup < 0 || r->p.pickup >= GF_RIFF_PICKUP_COUNT) r->p.pickup = GF_RIFF_PICKUP_BRIDGE;
    r->p.sustain = clampf(r->p.sustain, 0.0f, 1.0f);
    r->p.attack = clampf(r->p.attack, 0.0f, 1.0f);
}

/// Values that follow the sample rate.
static void update_rate(gf_riff* r) {
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        rstring* s = &r->s[i];
        s->open_period = r->rate / note_hz(k_open[i]);
    }
    r->dc_g = 1.0f - (float)(2.0 * M_PI * 20.0 / r->rate);
    r->res_tone = -1.0f;   // recompute the resonance
}

void gf_riff_reset(gf_riff* r) {
    if (!r) return;
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        rstring* s = &r->s[i];
        memset(s->buf, 0, sizeof(s->buf));
        memset(s->hist, 0, sizeof(s->hist));
        memset(s->lp, 0, sizeof(s->lp));
        memset(s->ap_x, 0, sizeof(s->ap_x));
        memset(s->ap_y, 0, sizeof(s->ap_y));
        s->exc_len = s->exc_pos = 0;
        s->note = -1;
        s->tuned = -1;
        s->held = s->sustained = s->released = s->active = 0;
        s->repick_left = 0;
        s->scrape_left = 0;
        s->scrape_hp = 0.0f;
        s->drift = s->drift_to = 0.0f;
        s->drift_left = 0;
        s->gain = 1.0f;
        s->env = 0.0f;
        s->loss_note = -1;
        s->n_fingers = 0;
        s->peak_env = 0.0f;
        s->boost_left = 0;
        s->loss_stretch = 1.0f;
        s->fb_x1 = s->fb_x2 = s->fb_y1 = s->fb_y2 = 0.0f;
        s->fb_pow = s->fb_prev = 0.0f;
        s->fb_note = -1;
        s->fb_int = 0.0f;
        for (int p = 0; p < POLS; ++p) s->d[p] = 100.0f;
    }
    r->legato_pedal = 0;
    r->res_x1 = r->res_x2 = r->res_y1 = r->res_y2 = 0.0f;
    r->dc_x1 = r->dc_y1 = 0.0f;
}

/// Starts every smoothed control on its target: a fresh guitar must not
/// fade in or sweep its pickups.
static void snap_controls(gf_riff* r) {
    r->pm = r->p.palm_mute;
    r->hb = r->p.humbucker ? 1.0f : 0.0f;
    r->tone = r->p.tone;
    r->level = powf(10.0f, clampf(r->p.level_db, -60.0f, 12.0f) / 20.0f);
    r->fb = clampf(r->p.feedback, 0.0f, 1.0f);
    const gf_riff_pickup pk = (gf_riff_pickup)r->p.pickup;
    for (int i = 0; i < 3; ++i) r->pick_w[i] = 0.0f;
    if (pk == GF_RIFF_PICKUP_NECK) r->pick_w[0] = 1.0f;
    else if (pk == GF_RIFF_PICKUP_MIDDLE) r->pick_w[1] = 1.0f;
    else if (pk == GF_RIFF_PICKUP_BRIDGE) r->pick_w[2] = 1.0f;
    else r->pick_w[0] = r->pick_w[2] = 0.6f;
}

gf_riff* gf_riff_create(float sample_rate) {
    if (!(sample_rate >= 8000.0f && sample_rate <= 192000.0f)) return NULL;
    gf_riff* r = (gf_riff*)calloc(1, sizeof(gf_riff));
    if (!r) return NULL;
    r->rate = sample_rate;
    r->noise = 0x9E3779B9u;
    r->humanize = 1;
    for (int i = 0; i < GF_RIFF_STRINGS; ++i) {
        r->s[i].intonation = INTONATION_CENTS * noise(r);
    }
    gf_riff_default_params(&r->p);
    update_rate(r);
    gf_riff_reset(r);
    snap_controls(r);
    return r;
}

void gf_riff_destroy(gf_riff* r) { free(r); }

void gf_riff_set_sample_rate(gf_riff* r, float sample_rate) {
    if (!r || !(sample_rate >= 8000.0f && sample_rate <= 192000.0f)) return;
    if (sample_rate == r->rate) return;
    r->rate = sample_rate;
    update_rate(r);
    gf_riff_reset(r);
}

// ── Inspection ──────────────────────────────────────────────────────────────

int gf_riff_string_note(const gf_riff* r, int s) {
    if (!r || s < 0 || s >= GF_RIFF_STRINGS || !r->s[s].active) return -1;
    return r->s[s].note;
}

int gf_riff_string_fret(const gf_riff* r, int s) {
    if (!r || s < 0 || s >= GF_RIFF_STRINGS || !r->s[s].active) return -1;
    return r->s[s].fret;
}

double gf_riff_string_period(const gf_riff* r, int s) {
    if (!r || s < 0 || s >= GF_RIFF_STRINGS) return 0.0;
    const rstring* st = &r->s[s];
    const double f = r->rate / st->d[0];
    return st->d[0] + filter_delay(r, st, 0, f);
}

void gf_riff_debug_set_humanize(gf_riff* r, int enabled) {
    if (r) r->humanize = enabled ? 1 : 0;
}
