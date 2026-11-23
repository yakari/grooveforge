// gf_amp.c — Guitar amp simulator. See gf_amp.h for the signal chain and the
// references each stage is built from.

#include "gf_amp.h"

#include "gf_convolver.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#if defined(__SSE__) || defined(__x86_64__) || defined(_M_X64)
#include <xmmintrin.h>
#define GF_AMP_HAS_SSE 1
#endif

#define GF_AMP_PI 3.14159265358979323846

/// Allpass coefficients in the half-band filter (5 per polyphase path).
#define HB_COEFS 10

/// Width of the half-band filter's transition band, as a fraction of the
/// oversampled rate. 0.05 keeps everything up to 0.45 × 48 kHz = 21.6 kHz.
#define HB_TRANSITION 0.05

/// Frames processed per internal pass; sizes the oversampled scratch buffer.
#define CHUNK 256

/// Corner of the Tube Screamer's gain-stage high-pass: only content above it
/// is amplified into the clipper (4.7 kΩ and 47 nF in the original circuit).
#define OD_HP_HZ 720.0

/// The Tube Screamer's feedback capacitor rolls the gain stage off above here.
#define OD_LP_HZ 6000.0

/// Rumble filter ahead of the distortion clipper.
#define DS_HP_HZ 100.0

/// Bias of the preamp clipper. Non-zero makes it clip the two halves of the
/// wave differently, as a tube does, which adds even harmonics.
#define TUBE_BIAS 0.25

/// Blocks DC the biased preamp leaves behind.
#define DC_HZ 20.0

/// Section on/off crossfade and parameter smoothing time constants.
#define FADE_SEC 0.010
#define SMOOTH_SEC 0.020

/// Below this difference between consecutive clipper inputs, ADAA's
/// difference quotient is replaced by the function at the midpoint: dividing
/// by a near-zero step would amplify rounding error into noise.
#define ADAA_EPS 1e-5

// ── Small building blocks ───────────────────────────────────────────────────

/// One-pole filter in topology-preserving (TPT) form: stays accurate and
/// stable even when its corner moves every block.
typedef struct { float s; } onepole;

/// Gain coefficient for a one-pole corner at [hz] on a [rate] Hz stream.
static float onepole_g(double hz, double rate) {
    const double g = tan(GF_AMP_PI * hz / rate);
    return (float)(g / (1.0 + g));
}

static inline float onepole_lp(onepole* f, float g, float x) {
    const float v = (x - f->s) * g;
    const float y = v + f->s;
    f->s = y + v;
    return y;
}

static inline float onepole_hp(onepole* f, float g, float x) {
    return x - onepole_lp(f, g, x);
}

/// Second-order section (RBJ cookbook), transposed direct form II.
typedef struct { float b0, b1, b2, a1, a2, s1, s2; } biquad;

static inline float biquad_tick(biquad* q, float x) {
    const float y = q->b0 * x + q->s1;
    q->s1 = q->b1 * x - q->a1 * y + q->s2;
    q->s2 = q->b2 * x - q->a2 * y;
    return y;
}

/// Stores normalised coefficients, keeping the filter's state.
static void biquad_set(biquad* q, double b0, double b1, double b2,
                       double a0, double a1, double a2) {
    q->b0 = (float)(b0 / a0);
    q->b1 = (float)(b1 / a0);
    q->b2 = (float)(b2 / a0);
    q->a1 = (float)(a1 / a0);
    q->a2 = (float)(a2 / a0);
}

static void biquad_lowpass(biquad* q, double hz, double qf, double rate) {
    const double w = 2.0 * GF_AMP_PI * hz / rate, c = cos(w);
    const double al = sin(w) / (2.0 * qf);
    biquad_set(q, (1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al);
}

static void biquad_highpass(biquad* q, double hz, double qf, double rate) {
    const double w = 2.0 * GF_AMP_PI * hz / rate, c = cos(w);
    const double al = sin(w) / (2.0 * qf);
    biquad_set(q, (1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al);
}

static void biquad_peak(biquad* q, double hz, double qf, double db,
                        double rate) {
    const double A = pow(10.0, db / 40.0);
    const double w = 2.0 * GF_AMP_PI * hz / rate, c = cos(w);
    const double al = sin(w) / (2.0 * qf);
    biquad_set(q, 1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A);
}

static float clampf(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

/// Coefficient of a one-pole smoother reaching ~63 % of a step in [sec].
static float smoother_k(double sec, double rate) {
    return (float)(1.0 - exp(-1.0 / (sec * rate)));
}

// ── Clippers and their antiderivatives ──────────────────────────────────────
//
// ADAA replaces y = f(x[n]) with the *average* of f over the straight line
// from x[n-1] to x[n]:  y = (F(x[n]) - F(x[n-1])) / (x[n] - x[n-1]), where F
// is the antiderivative of f. Averaging is a gentle low-pass applied before
// sampling, which is exactly what stops the clipper's harmonics from folding.

typedef enum { CLIP_SOFT, CLIP_HARD, CLIP_TUBE } clip_kind;

/// log(cosh(x)) without overflow: cosh(x) exceeds double range near |x| = 710.
static double logcosh(double x) {
    const double ax = fabs(x);
    return ax + log1p(exp(-2.0 * ax)) - 0.69314718055994530942;
}

/// The clipping curve itself.
static double clip_f(clip_kind k, double x) {
    switch (k) {
        case CLIP_SOFT: return tanh(x);
        case CLIP_HARD: return x < -1.0 ? -1.0 : (x > 1.0 ? 1.0 : x);
        case CLIP_TUBE: return tanh(x + TUBE_BIAS) - tanh(TUBE_BIAS);
    }
    return x;
}

/// Its antiderivative (any constant of integration works; it cancels).
static double clip_F(clip_kind k, double x) {
    switch (k) {
        case CLIP_SOFT: return logcosh(x);
        case CLIP_HARD: return fabs(x) <= 1.0 ? 0.5 * x * x : fabs(x) - 0.5;
        case CLIP_TUBE: return logcosh(x + TUBE_BIAS) - x * tanh(TUBE_BIAS);
    }
    return 0.5 * x * x;
}

/// Memory of a first-order ADAA clipper: the previous input and F of it.
typedef struct { double x1, F1; } adaa;

/// Runs one sample through a clipper, antialiased when [aa] is set. The
/// memory is kept up to date either way so switching never jumps.
static float clip_tick(adaa* st, clip_kind k, double x, int aa) {
    const double Fx = clip_F(k, x);
    const double d = x - st->x1;
    double y;
    if (!aa) {
        y = clip_f(k, x);
    } else if (fabs(d) > ADAA_EPS) {
        y = (Fx - st->F1) / d;
    } else {
        y = clip_f(k, 0.5 * (x + st->x1));
    }
    st->x1 = x;
    st->F1 = Fx;
    return (float)y;
}

// ── Half-band polyphase resampler ───────────────────────────────────────────
//
// A half-band low-pass split into two chains of first-order allpasses running
// at the base rate. Upsampling feeds each input sample to both chains and
// emits their two outputs in turn; downsampling feeds the odd and even
// samples to one chain each and averages. Allpasses are cheap (one multiply
// each) and their elliptic design gives a steep cutoff with few of them.
//
// The coefficient design is Laurent de Soras's closed form for HIIR
// (WTFPL-licensed), which derives the allpass coefficients of an elliptic
// half-band filter from its transition width.

/// x^n for a non-negative integer n.
static double ipow(double x, long n) {
    double z = 1.0;
    while (n) {
        if (n & 1) z *= x;
        n >>= 1;
        x *= x;
    }
    return z;
}

static double hb_acc_num(double q, int order, int c) {
    double acc = 0.0, term;
    int i = 0, sign = 1;
    do {
        term = ipow(q, (long)i * (i + 1))
             * sin((i * 2 + 1) * c * GF_AMP_PI / order) * sign;
        acc += term;
        sign = -sign;
        ++i;
    } while (fabs(term) > 1e-100);
    return acc;
}

static double hb_acc_den(double q, int order, int c) {
    double acc = 0.0, term;
    int i = 1, sign = -1;
    do {
        term = ipow(q, (long)i * i) * cos(i * 2 * c * GF_AMP_PI / order) * sign;
        acc += term;
        sign = -sign;
        ++i;
    } while (fabs(term) > 1e-100);
    return acc;
}

/// Fills [coefs] with the allpass coefficients of the half-band filter.
static void hb_design(float coefs[HB_COEFS]) {
    // Elliptic modulus and nome for the requested transition width.
    double k = tan((1.0 - HB_TRANSITION * 2.0) * GF_AMP_PI / 4.0);
    k *= k;
    const double kk = pow(1.0 - k * k, 0.25);
    const double e = 0.5 * (1.0 - kk) / (1.0 + kk);
    const double e4 = e * e * e * e;
    const double q = e * (1.0 + e4 * (2.0 + e4 * (15.0 + 150.0 * e4)));
    const int order = HB_COEFS * 2 + 1;
    for (int i = 0; i < HB_COEFS; ++i) {
        const int c = i + 1;
        const double num = hb_acc_num(q, order, c) * pow(q, 0.25);
        const double den = hb_acc_den(q, order, c) + 0.5;
        const double ww = num / den, w2 = ww * ww;
        const double x = sqrt((1.0 - w2 * k) * (1.0 - w2 / k)) / (1.0 + w2);
        coefs[i] = (float)((1.0 - x) / (1.0 + x));
    }
}

/// Memory of the two allpass chains.
typedef struct { float x[HB_COEFS], y[HB_COEFS]; } hb_state;

/// Runs [p0] through the even-indexed allpasses and [p1] through the odd ones.
static inline void hb_paths(const float* c, hb_state* st, float* p0, float* p1) {
    float a = *p0, b = *p1;
    for (int i = 0; i < HB_COEFS; i += 2) {
        const float ta = (a - st->y[i]) * c[i] + st->x[i];
        const float tb = (b - st->y[i + 1]) * c[i + 1] + st->x[i + 1];
        st->x[i] = a;
        st->x[i + 1] = b;
        st->y[i] = ta;
        st->y[i + 1] = tb;
        a = ta;
        b = tb;
    }
    *p0 = a;
    *p1 = b;
}

/// 2x upsampling of [n] frames into [up] (2n frames).
static void hb_up(const float* c, hb_state* st, const float* in, float* up,
                  int n, int aa) {
    for (int i = 0; i < n; ++i) {
        float a = in[i], b = in[i];
        if (aa) hb_paths(c, st, &a, &b);
        up[2 * i] = a;
        up[2 * i + 1] = b;
    }
}

/// 2x downsampling of [up] (2n frames) into [out] (n frames).
static void hb_down(const float* c, hb_state* st, const float* up, float* out,
                    int n, int aa) {
    for (int i = 0; i < n; ++i) {
        if (!aa) {
            out[i] = up[2 * i];
            continue;
        }
        float a = up[2 * i + 1], b = up[2 * i];
        hb_paths(c, st, &a, &b);
        out[i] = 0.5f * (a + b);
    }
}

// ── Tone stack (Yeh & Smith, DAFx-06) ───────────────────────────────────────
//
// The circuit's transfer function is third order:
//
//          b1 s + b2 s^2 + b3 s^3
//   H(s) = -------------------------
//          1 + a1 s + a2 s^2 + a3 s^3
//
// with every coefficient a polynomial in the pot positions t (treble),
// m (middle) and l (bass). The bilinear transform maps it to a third-order
// digital filter whose coefficients are recomputed whenever a knob moves.

/// C1, C2, C3, R1 (treble pot), R2 (bass pot), R3 (mid pot), R4.
static const double k_parts[GF_AMP_MODEL_COUNT][7] = {
    {250e-12, 20e-9, 20e-9, 250e3, 1e6, 25e3, 56e3},  // Fender '59 Bassman
    {470e-12, 22e-9, 22e-9, 220e3, 1e6, 22e3, 33e3},  // Marshall JCM800
    {50e-12,  22e-9, 22e-9, 1e6,   1e6, 10e3, 100e3}, // Vox AC30-style
};

int gf_amp_tonestack_parts(int model, double out[7]) {
    if (model < 0 || model >= GF_AMP_MODEL_COUNT) return -1;
    memcpy(out, k_parts[model], sizeof(k_parts[model]));
    return 0;
}

void gf_amp_tonestack_tapers(double bass, double middle, double treble,
                             double* l, double* m, double* t) {
    // An audio-taper pot changes resistance roughly exponentially with
    // rotation (3.4 is the curve Yeh uses for the Bassman's bass pot),
    // offset so it reaches 0 ohm at the end stop as a real pot does. Without
    // the offset the knob bottoms out at 3 % and loses half its range.
    *l = (exp(3.4 * bass) - 1.0) / (exp(3.4) - 1.0);
    *m = middle;
    *t = treble;
}

/// Analog coefficients b[0..3], a[0..3] for pot positions l, m, t.
static void ts_analog(const double* p, double l, double m, double t,
                      double b[4], double a[4]) {
    const double C1 = p[0], C2 = p[1], C3 = p[2];
    const double R1 = p[3], R2 = p[4], R3 = p[5], R4 = p[6];
    const double C123 = C1 * C2 * C3, R33 = R3 * R3;

    b[0] = 0.0;
    b[1] = t * C1 * R1 + m * C3 * R3 + l * (C1 * R2 + C2 * R2)
         + (C1 * R3 + C2 * R3);
    b[2] = t * (C1 * C2 * R1 * R4 + C1 * C3 * R1 * R4)
         - m * m * (C1 * C3 * R33 + C2 * C3 * R33)
         + m * (C1 * C3 * R1 * R3 + C1 * C3 * R33 + C2 * C3 * R33)
         + l * (C1 * C2 * R1 * R2 + C1 * C2 * R2 * R4 + C1 * C3 * R2 * R4)
         + l * m * (C1 * C3 * R2 * R3 + C2 * C3 * R2 * R3)
         + (C1 * C2 * R1 * R3 + C1 * C2 * R3 * R4 + C1 * C3 * R3 * R4);
    b[3] = l * m * C123 * (R1 * R2 * R3 + R2 * R3 * R4)
         - m * m * C123 * (R1 * R33 + R33 * R4)
         + m * C123 * (R1 * R33 + R33 * R4)
         + t * C123 * R1 * R3 * R4 - t * m * C123 * R1 * R3 * R4
         + t * l * C123 * R1 * R2 * R4;

    a[0] = 1.0;
    a[1] = (C1 * R1 + C1 * R3 + C2 * R3 + C2 * R4 + C3 * R4)
         + m * C3 * R3 + l * (C1 * R2 + C2 * R2);
    a[2] = m * (C1 * C3 * R1 * R3 - C2 * C3 * R3 * R4 + C1 * C3 * R33
                + C2 * C3 * R33)
         + l * m * (C1 * C3 * R2 * R3 + C2 * C3 * R2 * R3)
         - m * m * (C1 * C3 * R33 + C2 * C3 * R33)
         + l * (C1 * C2 * R2 * R4 + C1 * C2 * R1 * R2 + C1 * C3 * R2 * R4
                + C2 * C3 * R2 * R4)
         + (C1 * C2 * R1 * R4 + C1 * C3 * R1 * R4 + C1 * C2 * R3 * R4
            + C1 * C2 * R1 * R3 + C1 * C3 * R3 * R4 + C2 * C3 * R3 * R4);
    a[3] = l * m * C123 * (R1 * R2 * R3 + R2 * R3 * R4)
         - m * m * C123 * (R1 * R33 + R33 * R4)
         + m * C123 * (R33 * R4 + R1 * R33 - R1 * R3 * R4)
         + l * C123 * R1 * R2 * R4 + C123 * R1 * R3 * R4;
}

/// Bilinear transform s = c (1 - z^-1) / (1 + z^-1), c = 2 fs, of a cubic.
/// Expanding (1+z)^3, (1-z)(1+z)^2, (1-z)^2(1+z) and (1-z)^3 gives the four
/// rows below.
static void bilinear3(const double s[4], double c, double z[4]) {
    const double s1 = s[1] * c, s2 = s[2] * c * c, s3 = s[3] * c * c * c;
    z[0] = s[0] + s1 + s2 + s3;
    z[1] = 3 * s[0] + s1 - s2 - 3 * s3;
    z[2] = 3 * s[0] - s1 - s2 + 3 * s3;
    z[3] = s[0] - s1 + s2 - s3;
}

/// Digital coefficients for a model and knob settings, normalised so a[0] = 1.
static void ts_digital(int model, double bass, double middle, double treble,
                       double rate, double b[4], double a[4]) {
    double l, m, t, sb[4], sa[4];
    gf_amp_tonestack_tapers(bass, middle, treble, &l, &m, &t);
    ts_analog(k_parts[model], l, m, t, sb, sa);
    bilinear3(sb, 2.0 * rate, b);
    bilinear3(sa, 2.0 * rate, a);
    const double a0 = a[0];
    for (int i = 0; i < 4; ++i) {
        b[i] /= a0;
        a[i] /= a0;
    }
}

static int clamp_model(int model) {
    return (model < 0 || model >= GF_AMP_MODEL_COUNT) ? 0 : model;
}

double gf_amp_tonestack_analog_db(int model, double bass, double middle,
                                  double treble, double freq_hz) {
    double l, m, t, b[4], a[4];
    gf_amp_tonestack_tapers(bass, middle, treble, &l, &m, &t);
    ts_analog(k_parts[clamp_model(model)], l, m, t, b, a);
    // s = jw: s^2 = -w^2, s^3 = -j w^3.
    const double w = 2.0 * GF_AMP_PI * freq_hz, w2 = w * w, w3 = w2 * w;
    const double nr = b[0] - b[2] * w2, ni = b[1] * w - b[3] * w3;
    const double dr = a[0] - a[2] * w2, di = a[1] * w - a[3] * w3;
    return 10.0 * log10((nr * nr + ni * ni) / (dr * dr + di * di));
}

/// |sum c[k] e^{-jkw}|^2 for a cubic in z^-1.
static double cubic_mag2(const double c[4], double w) {
    double re = 0.0, im = 0.0;
    for (int k = 0; k < 4; ++k) {
        re += c[k] * cos(k * w);
        im -= c[k] * sin(k * w);
    }
    return re * re + im * im;
}

double gf_amp_tonestack_digital_db(int model, double bass, double middle,
                                   double treble, double sample_rate,
                                   double freq_hz) {
    double b[4], a[4];
    ts_digital(clamp_model(model), bass, middle, treble, sample_rate, b, a);
    const double w = 2.0 * GF_AMP_PI * freq_hz / sample_rate;
    return 10.0 * log10(cubic_mag2(b, w) / cubic_mag2(a, w));
}

// ── Cabinet ─────────────────────────────────────────────────────────────────

/// One cabinet's response as a chain of filters: a low cut below the
/// speaker's resonance, the resonance bump itself, the boxy-mids dip, the
/// cone's presence peak, and the steep top-end roll-off that turns fizz into
/// a guitar tone.
typedef struct {
    double hp_hz, hp_q;
    double low_hz, low_q, low_db;
    double mid_hz, mid_q, mid_db;
    double pres_hz, pres_q, pres_db;
    double lp_hz, lp_q;
} cab_shape;

/// Indexed by gf_amp_cab; the IR cabinet has no filter shape of its own.
static const cab_shape k_cabs[GF_AMP_CAB_IR] = {
    // 1x12 open back: the open back cancels the deepest lows.
    {90, 0.7, 130, 1.0, 2.5, 600, 1.0, -2.5, 2500, 1.5, 4.0, 6000, 0.7},
    // 2x12.
    {80, 0.8, 110, 1.2, 4.0, 500, 1.2, -4.0, 2200, 1.8, 5.0, 5200, 0.7},
    // 4x12 closed back: deep thump, scooped mids, darker top.
    {70, 0.9, 100, 1.4, 6.0, 400, 1.0, -5.0, 2000, 2.0, 5.0, 4600, 0.8},
};

#define CAB_SECTIONS 6

/// Builds the filter chain of built-in cabinet [type] at [rate] into [q],
/// keeping the filters' state.
static void cab_build(biquad q[CAB_SECTIONS], int type, double rate) {
    const cab_shape* s = &k_cabs[type];
    biquad_highpass(&q[0], s->hp_hz, s->hp_q, rate);
    biquad_peak(&q[1], s->low_hz, s->low_q, s->low_db, rate);
    biquad_peak(&q[2], s->mid_hz, s->mid_q, s->mid_db, rate);
    biquad_peak(&q[3], s->pres_hz, s->pres_q, s->pres_db, rate);
    biquad_lowpass(&q[4], s->lp_hz, s->lp_q, rate);
    biquad_lowpass(&q[5], s->lp_hz, s->lp_q, rate);
}

/// Squared magnitude of one second-order section at [w] radians per sample.
static double biquad_mag2(const biquad* q, double w) {
    const double c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w);
    const double nr = q->b0 + q->b1 * c1 + q->b2 * c2;
    const double ni = -q->b1 * s1 - q->b2 * s2;
    const double dr = 1.0 + q->a1 * c1 + q->a2 * c2;
    const double di = -q->a1 * s1 - q->a2 * s2;
    return (nr * nr + ni * ni) / (dr * dr + di * di);
}

// ── Cabinet impulse responses ───────────────────────────────────────────────

/// Rates an IR is always prepared for: those audio devices actually run at.
static const double k_ir_rates[] = {44100.0, 48000.0, 88200.0, 96000.0};
#define IR_FIXED_RATES ((int)(sizeof(k_ir_rates) / sizeof(k_ir_rates[0])))
#define IR_RATES_MAX (IR_FIXED_RATES + 1)

struct gf_amp_ir {
    int count;
    double rates[IR_RATES_MAX];
    gf_convolver* conv[IR_RATES_MAX];
};

/// Trimming thresholds relative to the IR's peak: what comes before the
/// attack (-60 dB) and after the decay (-80 dB) is dropped.
#define IR_START_DB_RATIO 1e-3
#define IR_END_DB_RATIO 1e-4

/// Fade applied over the end of an IR cut at GF_AMP_IR_MAX_SEC, so the cut
/// is not a step.
#define IR_FADE_SEC 0.010

/// Resampler: windowed-sinc half-width in zero crossings, Kaiser window
/// shape (beta 9: side lobes ~90 dB down), and cutoff as a fraction of the
/// lower Nyquist frequency. A cabinet has nothing left above 18 kHz, so the
/// 5 % margin costs nothing audible.
#define RS_ZEROS 32
#define RS_BETA 9.0
#define RS_CUTOFF 0.95
#define RS_TABLE 4096

/// Band the level of an IR is measured over: where a guitar cabinet lives.
#define IR_BAND_LO_HZ 100.0
#define IR_BAND_HI_HZ 4000.0
#define IR_BAND_POINTS 48

/// Zeroth-order modified Bessel function of the first kind (Kaiser window).
static double bessel_i0(double x) {
    double sum = 1.0, term = 1.0;
    for (int k = 1; k < 60; ++k) {
        const double h = x / (2.0 * k);
        term *= h * h;
        sum += term;
        if (term < sum * 1e-14) break;
    }
    return sum;
}

/// Finds the part of [x] worth keeping: from the first sample within 60 dB
/// of the peak to the last within 80 dB, at most GF_AMP_IR_MAX_SEC long.
/// Returns the length (0 for a silent IR) and writes the start and whether
/// the end had to be cut.
static int ir_trim(const float* x, int n, double rate, int* start, int* cut) {
    float peak = 0.0f;
    for (int i = 0; i < n; ++i) {
        const float v = fabsf(x[i]);
        if (v > peak && isfinite(v)) peak = v;
    }
    if (!(peak > 0.0f)) return 0;
    int first = 0, last = n - 1;
    while (first < n && !(fabsf(x[first]) >= peak * IR_START_DB_RATIO)) ++first;
    while (last > first && !(fabsf(x[last]) >= peak * IR_END_DB_RATIO)) --last;
    const int cap = (int)ceil(GF_AMP_IR_MAX_SEC * rate);
    int len = last - first + 1;
    *cut = len > cap;
    if (*cut) len = cap;
    *start = first;
    return len;
}

/// Copies the kept part of the IR, fading out its last 10 ms if it was cut.
/// Non-finite samples (a corrupt file) become silence.
static float* ir_extract(const float* x, int n, double rate, int* out_len) {
    int start = 0, cut = 0;
    const int len = ir_trim(x, n, rate, &start, &cut);
    if (len < 1) return NULL;
    float* y = (float*)malloc((size_t)len * sizeof(float));
    if (!y) return NULL;
    for (int i = 0; i < len; ++i) y[i] = isfinite(x[start + i]) ? x[start + i] : 0.0f;
    if (cut) {
        int fade = (int)(IR_FADE_SEC * rate);
        if (fade > len) fade = len;
        for (int i = 0; i < fade; ++i) {
            const double u = (double)(i + 1) / fade;  // 0 → 1 towards the end
            y[len - fade + i] *= (float)(0.5 * (1.0 + cos(GF_AMP_PI * u)));
        }
    }
    *out_len = len;
    return y;
}

/// Changes [x]'s rate from [from] to [to] Hz with a band-limited
/// (windowed-sinc) interpolator, the standard way to resample without
/// aliasing. Returns a malloc'd buffer and its length.
static float* resample(const float* x, int n, double from, double to, int* out_n) {
    const double ratio = to / from;
    const int m = (int)ceil(n * ratio);
    float* y = (float*)malloc((size_t)m * sizeof(float));
    float* win = (float*)malloc((RS_TABLE + 2) * sizeof(float));
    if (!y || !win) { free(y); free(win); return NULL; }
    // Kaiser window tabulated over its right half; the sum below looks it up.
    const double i0b = bessel_i0(RS_BETA);
    for (int i = 0; i <= RS_TABLE + 1; ++i) {
        const double u = i < RS_TABLE ? (double)i / RS_TABLE : 1.0;
        win[i] = (float)(bessel_i0(RS_BETA * sqrt(1.0 - u * u)) / i0b);
    }
    // Cutoff in cycles per input sample (relative to its Nyquist): below
    // the output's Nyquist when going down in rate, so nothing folds.
    const double fc = (ratio < 1.0 ? ratio : 1.0) * RS_CUTOFF;
    const double hw = RS_ZEROS / fc;           // half-width in input samples
    for (int j = 0; j < m; ++j) {
        const double t = j / ratio;            // output instant, in input samples
        int k0 = (int)ceil(t - hw), k1 = (int)floor(t + hw);
        if (k0 < 0) k0 = 0;
        if (k1 > n - 1) k1 = n - 1;
        double acc = 0.0;
        for (int k = k0; k <= k1; ++k) {
            const double d = t - k;
            const double a = GF_AMP_PI * fc * d;
            const double sinc = fabs(a) < 1e-12 ? 1.0 : sin(a) / a;
            acc += x[k] * fc * sinc * win[(int)(fabs(d) / hw * RS_TABLE)];
        }
        y[j] = (float)acc;
    }
    free(win);
    *out_n = m;
    return y;
}

/// Mean power gain of [h] over the guitar band, at log-spaced frequencies.
static double ir_band_power(const float* h, int n, double rate) {
    double sum = 0.0;
    for (int p = 0; p < IR_BAND_POINTS; ++p) {
        const double hz = IR_BAND_LO_HZ *
            pow(IR_BAND_HI_HZ / IR_BAND_LO_HZ, (double)p / (IR_BAND_POINTS - 1));
        const double w = 2.0 * GF_AMP_PI * hz / rate;
        // e^{-jwk} by rotation: one complex multiply per tap instead of two
        // trig calls.
        const double cr = cos(w), ci = -sin(w);
        double zr = 1.0, zi = 0.0, re = 0.0, im = 0.0;
        for (int k = 0; k < n; ++k) {
            re += h[k] * zr;
            im += h[k] * zi;
            const double t = zr * cr - zi * ci;
            zi = zr * ci + zi * cr;
            zr = t;
        }
        sum += re * re + im * im;
    }
    return sum / IR_BAND_POINTS;
}

/// The same measure for a built-in cabinet's filters.
static double cab_band_power(int type, double rate) {
    biquad q[CAB_SECTIONS];
    memset(q, 0, sizeof(q));
    cab_build(q, type, rate);
    double sum = 0.0;
    for (int p = 0; p < IR_BAND_POINTS; ++p) {
        const double hz = IR_BAND_LO_HZ *
            pow(IR_BAND_HI_HZ / IR_BAND_LO_HZ, (double)p / (IR_BAND_POINTS - 1));
        const double w = 2.0 * GF_AMP_PI * hz / rate;
        double g = 1.0;
        for (int i = 0; i < CAB_SECTIONS; ++i) g *= biquad_mag2(&q[i], w);
        sum += g;
    }
    return sum / IR_BAND_POINTS;
}

/// One rate's version of the IR: resampled, levelled to the 2x12, ready to
/// convolve.
static gf_convolver* ir_build_for_rate(const float* src, int len, double from,
                                       double to) {
    const int same_rate = fabs(to - from) < 0.5;
    int m = len;
    float* h = same_rate ? NULL : resample(src, len, from, to, &m);
    if (!same_rate && !h) return NULL;
    const float* use = h ? h : src;
    const double scale = sqrt(cab_band_power(GF_AMP_CAB_2X12, to) /
                              ir_band_power(use, m, to));
    float* scaled = (float*)malloc((size_t)m * sizeof(float));
    gf_convolver* c = NULL;
    if (scaled && isfinite(scale) && scale > 0.0) {
        for (int i = 0; i < m; ++i) scaled[i] = (float)(use[i] * scale);
        c = gf_convolver_create(scaled, m);
    }
    free(scaled);
    free(h);
    return c;
}

static int rate_ok(double r) { return r >= 8000.0 && r <= 384000.0; }

gf_amp_ir* gf_amp_ir_create(const float* samples, int n, double rate,
                            double also_rate) {
    if (!samples || n < 1 || !rate_ok(rate)) return NULL;
    int len = 0;
    float* src = ir_extract(samples, n, rate, &len);
    if (!src) return NULL;
    gf_amp_ir* ir = (gf_amp_ir*)calloc(1, sizeof(gf_amp_ir));
    if (!ir) { free(src); return NULL; }
    for (int i = 0; i < IR_FIXED_RATES; ++i) ir->rates[ir->count++] = k_ir_rates[i];
    int extra = rate_ok(also_rate);
    for (int i = 0; i < IR_FIXED_RATES; ++i) {
        if (fabs(k_ir_rates[i] - also_rate) < 1.0) extra = 0;
    }
    if (extra) ir->rates[ir->count++] = also_rate;
    for (int i = 0; i < ir->count; ++i) {
        ir->conv[i] = ir_build_for_rate(src, len, rate, ir->rates[i]);
        if (!ir->conv[i]) { free(src); gf_amp_ir_destroy(ir); return NULL; }
    }
    free(src);
    return ir;
}

void gf_amp_ir_destroy(gf_amp_ir* ir) {
    if (!ir) return;
    for (int i = 0; i < ir->count; ++i) gf_convolver_destroy(ir->conv[i]);
    free(ir);
}

/// The IR's convolver for [rate]: the exact one if prepared, else the
/// nearest in ratio.
static gf_convolver* ir_for_rate(const gf_amp_ir* ir, double rate) {
    int best = 0;
    double best_d = 1e9;
    for (int i = 0; i < ir->count; ++i) {
        const double d = fabs(log(ir->rates[i] / rate));
        if (d < best_d) { best_d = d; best = i; }
    }
    return ir->conv[best];
}

int gf_amp_ir_length(const gf_amp_ir* ir, double rate) {
    return ir ? gf_convolver_length(ir_for_rate(ir, rate)) : 0;
}

// ── The amp ─────────────────────────────────────────────────────────────────

struct gf_amp {
    float rate;              ///< Base sample rate.
    int   aa;                ///< Antialiasing enabled (test hook).
    gf_amp_params p;         ///< Current targets.

    float hb[HB_COEFS];
    hb_state hb_upst, hb_downst;
    float up[2 * CHUNK];     ///< Oversampled scratch.

    // Drive pedal, at 2x.
    onepole od_hp, od_lp, ds_hp, tone_lp;
    float g_od_hp, g_od_lp, g_ds_hp, g_tone;
    adaa od_clip, ds_clip;
    float drive_gain;        ///< Smoothed.
    float drive_mix;         ///< Smoothed on/off.

    // Preamp, at 2x.
    adaa pre_clip;
    float pre_gain;          ///< Smoothed.
    float pre_trim;          ///< pre_gain^-0.75, refreshed with pre_gain.
    float amp_mix_os;        ///< Smoothed on/off, oversampled side.

    // Tone stack, at the base rate.
    onepole dc;
    float g_dc;
    double ts_b[4], ts_a[4], ts_s[3];
    double ts_knobs[3];      ///< Smoothed bass, middle, treble.
    int    ts_model;         ///< Model the coefficients were built for.
    double ts_makeup;        ///< Brings the stack's peak to 0 dB, knobs at 5.
    float amp_mix;           ///< Smoothed on/off, base-rate side.

    // Cabinet, at the base rate.
    biquad cab[CAB_SECTIONS];
    int filter_cab;          ///< Built-in cabinet the filters are set to.
    int f_running;           ///< The filters ran last chunk.
    float cab_mix;

    // Impulse response cabinet. The amp owns every IR pointer below.
    gf_amp_ir* ir;           ///< The IR in use, or NULL.
    gf_convolver* conv;      ///< Its version for the current rate.
    gf_amp_ir* ir_old;       ///< The IR being crossfaded away from.
    gf_convolver* conv_old;
    gf_amp_ir* retired;      ///< Done with; gf_amp_take_retired_ir hands it back.
    int ir_running;          ///< The convolver ran last chunk.
    int ir_clearing;         ///< gf_amp_clear_ir: fading [ir] out to drop it.
    float ir_mix;            ///< Smoothed: 0 = filter cabinet, 1 = IR.
    float ir_swap;           ///< Smoothed: 0 = old IR, 1 = new IR.
    float cab_f[CHUNK], cab_g[CHUNK], cab_o[CHUNK];  ///< Scratch.

    float level;             ///< Smoothed output gain.

    float k_fade_os, k_fade, k_smooth_os, k_smooth;
};

void gf_amp_default_params(gf_amp_params* out) {
    out->drive_on = 0;
    out->drive_mode = GF_AMP_DRIVE_OVERDRIVE;
    out->drive = 0.5f;
    out->drive_tone = 0.5f;
    out->amp_on = 1;
    out->amp_model = GF_AMP_MODEL_FENDER;
    out->gain = 0.4f;
    out->bass = 0.5f;
    out->middle = 0.5f;
    out->treble = 0.5f;
    out->cab_on = 1;
    out->cab_type = GF_AMP_CAB_2X12;
    out->level_db = 0.0f;
}

/// Gain into the drive clipper. Overdrive tops out near the Tube Screamer's
/// ~118x; distortion pedals go much further.
static float drive_gain_target(const gf_amp_params* p) {
    const double top = p->drive_mode == GF_AMP_DRIVE_DISTORTION ? 500.0 : 118.0;
    return (float)pow(top, p->drive);
}

/// Preamp gain: 1x (clean, barely touching the curve) to 40x (crunch).
static float pre_gain_target(const gf_amp_params* p) {
    return (float)pow(40.0, p->gain);
}

static float level_target(const gf_amp_params* p) {
    return (float)pow(10.0, p->level_db / 20.0);
}

static void update_cab(gf_amp* a) { cab_build(a->cab, a->filter_cab, a->rate); }

/// Which built-in cabinet the filters should be. With "IR" selected they keep
/// the last one, which the IR crossfades from — or stand in as the 2x12
/// until an IR is loaded.
static int filter_cab_target(const gf_amp* a) {
    if (a->p.cab_type != GF_AMP_CAB_IR) return a->p.cab_type;
    return a->conv ? a->filter_cab : GF_AMP_CAB_2X12;
}

/// 1 when the IR should be heard.
static float ir_target(const gf_amp* a) {
    if (a->ir_clearing) return 0.0f;
    return (a->p.cab_type == GF_AMP_CAB_IR && a->conv) ? 1.0f : 0.0f;
}

/// Rebuilds the tone stack for the smoothed knobs, and its level makeup when
/// the model changed.
static void update_tonestack(gf_amp* a, int model_changed) {
    ts_digital(a->ts_model, a->ts_knobs[0], a->ts_knobs[1], a->ts_knobs[2],
               a->rate, a->ts_b, a->ts_a);
    if (!model_changed) return;
    // Level the stack so its loudest point across a guitar's range, knobs at
    // noon, sits at 0 dB. Levelling at one frequency instead would boost
    // everything else whenever that frequency lands in the mid scoop.
    double peak = -1e9;
    for (double hz = 60.0; hz <= 5000.0; hz *= 1.1) {
        const double db = gf_amp_tonestack_digital_db(a->ts_model, 0.5, 0.5,
                                                      0.5, a->rate, hz);
        if (db > peak) peak = db;
    }
    a->ts_makeup = pow(10.0, -peak / 20.0);
}

/// Everything that depends on the sample rate but not on the knobs.
static void update_rate(gf_amp* a) {
    const double os = 2.0 * a->rate;
    a->g_od_hp = onepole_g(OD_HP_HZ, os);
    a->g_od_lp = onepole_g(OD_LP_HZ, os);
    a->g_ds_hp = onepole_g(DS_HP_HZ, os);
    a->g_dc = onepole_g(DC_HZ, a->rate);
    a->k_fade_os = smoother_k(FADE_SEC, os);
    a->k_fade = smoother_k(FADE_SEC, a->rate);
    a->k_smooth_os = smoother_k(SMOOTH_SEC, os);
    a->k_smooth = smoother_k(SMOOTH_SEC, a->rate);
    update_cab(a);
    update_tonestack(a, 1);
}

/// Clamps everything the caller handed over into range.
static gf_amp_params sanitize(const gf_amp_params* in) {
    gf_amp_params p = *in;
    p.drive = clampf(p.drive, 0.0f, 1.0f);
    p.drive_tone = clampf(p.drive_tone, 0.0f, 1.0f);
    p.gain = clampf(p.gain, 0.0f, 1.0f);
    p.bass = clampf(p.bass, 0.0f, 1.0f);
    p.middle = clampf(p.middle, 0.0f, 1.0f);
    p.treble = clampf(p.treble, 0.0f, 1.0f);
    p.level_db = clampf(p.level_db, -60.0f, 24.0f);
    if (p.drive_mode < 0 || p.drive_mode >= GF_AMP_DRIVE_COUNT) p.drive_mode = 0;
    if (p.amp_model < 0 || p.amp_model >= GF_AMP_MODEL_COUNT) p.amp_model = 0;
    if (p.cab_type < 0 || p.cab_type >= GF_AMP_CAB_COUNT) p.cab_type = 0;
    return p;
}

void gf_amp_set_params(gf_amp* a, const gf_amp_params* params) {
    if (!a || !params) return;
    a->p = sanitize(params);
    // Tone knob: a low-pass from 500 Hz (dark) to 10 kHz (bright), swept
    // exponentially so each turn of the knob is the same musical step.
    a->g_tone = onepole_g(500.0 * pow(20.0, a->p.drive_tone), 2.0 * a->rate);
    const int fc = filter_cab_target(a);
    if (fc != a->filter_cab) {
        a->filter_cab = fc;
        update_cab(a);
    }
}

void gf_amp_reset(gf_amp* a) {
    if (!a) return;
    memset(&a->hb_upst, 0, sizeof(a->hb_upst));
    memset(&a->hb_downst, 0, sizeof(a->hb_downst));
    a->od_hp.s = a->od_lp.s = a->ds_hp.s = a->tone_lp.s = a->dc.s = 0.0f;
    memset(&a->od_clip, 0, sizeof(adaa));
    memset(&a->ds_clip, 0, sizeof(adaa));
    memset(&a->pre_clip, 0, sizeof(adaa));
    memset(a->ts_s, 0, sizeof(a->ts_s));
    for (int i = 0; i < CAB_SECTIONS; ++i) a->cab[i].s1 = a->cab[i].s2 = 0.0f;
    // Start every smoother on its target: a fresh amp must not fade in.
    a->drive_gain = drive_gain_target(&a->p);
    a->pre_gain = pre_gain_target(&a->p);
    a->pre_trim = powf(a->pre_gain, -0.75f);
    a->drive_mix = a->p.drive_on ? 1.0f : 0.0f;
    a->amp_mix_os = a->amp_mix = a->p.amp_on ? 1.0f : 0.0f;
    a->cab_mix = a->p.cab_on ? 1.0f : 0.0f;
    a->level = level_target(&a->p);
    gf_convolver_reset(a->conv);
    gf_convolver_reset(a->conv_old);
    a->ir_mix = ir_target(a);
    a->ir_running = 0;
    a->f_running = 0;
}

gf_amp* gf_amp_create(float sample_rate) {
    if (!(sample_rate >= 8000.0f && sample_rate <= 384000.0f)) return NULL;
    gf_amp* a = (gf_amp*)calloc(1, sizeof(gf_amp));
    if (!a) return NULL;
    a->rate = sample_rate;
    a->aa = 1;
    hb_design(a->hb);
    gf_amp_default_params(&a->p);
    a->filter_cab = a->p.cab_type;
    a->ts_model = a->p.amp_model;
    a->ts_knobs[0] = a->p.bass;
    a->ts_knobs[1] = a->p.middle;
    a->ts_knobs[2] = a->p.treble;
    update_rate(a);
    gf_amp_set_params(a, &a->p);
    gf_amp_reset(a);
    return a;
}

void gf_amp_destroy(gf_amp* a) {
    if (!a) return;
    gf_amp_ir_destroy(a->ir);
    gf_amp_ir_destroy(a->ir_old);
    gf_amp_ir_destroy(a->retired);
    free(a);
}

/// Ends an IR crossfade: the old IR goes to the retired slot.
static void retire_old_ir(gf_amp* a) {
    if (!a->ir_old) return;
    a->retired = a->ir_old;
    a->ir_old = NULL;
    a->conv_old = NULL;
    a->ir_swap = 1.0f;
}

int gf_amp_ir_busy(const gf_amp* a) {
    return a && (a->ir_old != NULL || a->retired != NULL);
}

int gf_amp_set_ir(gf_amp* a, gf_amp_ir* ir) {
    if (!a || !ir || gf_amp_ir_busy(a)) return 0;
    gf_convolver* c = ir_for_rate(ir, a->rate);
    gf_convolver_reset(c);
    if (a->ir && a->ir_running) {
        // An IR is sounding: crossfade from it rather than cut.
        a->ir_old = a->ir;
        a->conv_old = a->conv;
        a->ir_swap = 0.0f;
    } else if (a->ir) {
        a->retired = a->ir;   // not heard, nothing to fade
    }
    a->ir = ir;
    a->conv = c;
    a->ir_clearing = 0;   // a new IR cancels a pending removal
    return 1;
}

void gf_amp_clear_ir(gf_amp* a) {
    if (a && a->ir) a->ir_clearing = 1;
}

/// Ends a removal once the IR is silent: nothing of it is heard any more, no
/// swap is fading, and the retired slot is free to take it.
static void finish_clear(gf_amp* a) {
    if (!a->ir_clearing || a->ir_old || a->retired) return;
    if (a->ir_running && a->ir_mix > 1e-6f) return;
    a->retired = a->ir;
    a->ir = NULL;
    a->conv = NULL;
    a->ir_clearing = 0;
    a->ir_mix = 0.0f;
}

gf_amp_ir* gf_amp_take_retired_ir(gf_amp* a) {
    if (!a) return NULL;
    gf_amp_ir* r = a->retired;
    a->retired = NULL;
    return r;
}

int gf_amp_has_ir(const gf_amp* a) { return a && a->ir != NULL; }

void gf_amp_set_sample_rate(gf_amp* a, float sample_rate) {
    if (!a || !(sample_rate >= 8000.0f && sample_rate <= 384000.0f)) return;
    if (sample_rate == a->rate) return;
    a->rate = sample_rate;
    // Switch to the IR version prepared for the new rate. A crossfade in
    // progress is abandoned: the stream restarting is a break anyway.
    retire_old_ir(a);
    if (a->ir) a->conv = ir_for_rate(a->ir, sample_rate);
    update_rate(a);
    gf_amp_set_params(a, &a->p);
    gf_amp_reset(a);
}

void gf_amp_debug_set_antialias(gf_amp* a, int enabled) {
    if (a) a->aa = enabled ? 1 : 0;
}

// ── Per-sample stages ───────────────────────────────────────────────────────

/// The drive pedal, one oversampled sample.
static float drive_tick(gf_amp* a, float x) {
    float y;
    if (a->p.drive_mode == GF_AMP_DRIVE_DISTORTION) {
        // Whole band (minus rumble) into a hard clipper.
        const float hp = onepole_hp(&a->ds_hp, a->g_ds_hp, x);
        y = 0.6f * clip_tick(&a->ds_clip, CLIP_HARD, a->drive_gain * hp, a->aa);
    } else {
        // Tube Screamer: only the band above ~720 Hz is driven into the soft
        // clipper; the clean signal, lows included, is added back. The gain
        // stage's own roll-off keeps the clipper from being fed fizz.
        const float hp = onepole_hp(&a->od_hp, a->g_od_hp, x);
        const float u = onepole_lp(&a->od_lp, a->g_od_lp, a->drive_gain * hp);
        y = 0.7f * (x + clip_tick(&a->od_clip, CLIP_SOFT, u, a->aa));
    }
    return onepole_lp(&a->tone_lp, a->g_tone, y);
}

/// The preamp, one oversampled sample.
static float pre_tick(gf_amp* a, float x) {
    const float y = clip_tick(&a->pre_clip, CLIP_TUBE, a->pre_gain * x, a->aa);
    // More gain means more breakup and a little more level, as on a real
    // amp, but only a quarter as much level in dB: a clean sound stays near
    // unity and a crunch does not jump out of the mix.
    return y * a->pre_trim;
}

/// The tone stack, one base-rate sample (transposed direct form II, double
/// precision: a third-order filter with poles this close to the unit circle
/// loses accuracy in float).
static float tonestack_tick(gf_amp* a, float xf) {
    const double x = xf, *b = a->ts_b, *ac = a->ts_a;
    double* s = a->ts_s;
    const double y = b[0] * x + s[0];
    s[0] = b[1] * x - ac[1] * y + s[1];
    s[1] = b[2] * x - ac[2] * y + s[2];
    s[2] = b[3] * x - ac[3] * y;
    return (float)(y * a->ts_makeup);
}

static float cab_tick(gf_amp* a, float x) {
    for (int i = 0; i < CAB_SECTIONS; ++i) x = biquad_tick(&a->cab[i], x);
    return x;
}

/// Eases the tone stack knobs towards their targets once per chunk and
/// rebuilds the filter when they moved, so a knob turn is a glide, not a
/// series of steps.
static void chase_tonestack(gf_amp* a) {
    const double target[3] = {a->p.bass, a->p.middle, a->p.treble};
    const int model_changed = a->p.amp_model != a->ts_model;
    int moved = model_changed;
    for (int i = 0; i < 3; ++i) {
        const double d = target[i] - a->ts_knobs[i];
        if (d == 0.0) continue;
        a->ts_knobs[i] = fabs(d) < 1e-4 ? target[i] : a->ts_knobs[i] + 0.25 * d;
        moved = 1;
    }
    a->ts_model = a->p.amp_model;
    if (moved) update_tonestack(a, model_changed);
}

/// Drive and preamp over the oversampled chunk.
static void process_oversampled(gf_amp* a, int n2) {
    const float dg = drive_gain_target(&a->p), pg = pre_gain_target(&a->p);
    const float dm = a->p.drive_on ? 1.0f : 0.0f;
    const float am = a->p.amp_on ? 1.0f : 0.0f;
    for (int j = 0; j < n2; ++j) {
        a->drive_gain += (dg - a->drive_gain) * a->k_smooth_os;
        if (a->pre_gain != pg) {
            a->pre_gain += (pg - a->pre_gain) * a->k_smooth_os;
            if (fabsf(pg - a->pre_gain) < 1e-6f) a->pre_gain = pg;
            a->pre_trim = powf(a->pre_gain, -0.75f);
        }
        a->drive_mix += (dm - a->drive_mix) * a->k_fade_os;
        a->amp_mix_os += (am - a->amp_mix_os) * a->k_fade_os;
        float x = a->up[j];
        // A section fully faded out is skipped, not computed and discarded.
        if (a->drive_mix > 1e-6f) x += (drive_tick(a, x) - x) * a->drive_mix;
        if (a->amp_mix_os > 1e-6f) x += (pre_tick(a, x) - x) * a->amp_mix_os;
        a->up[j] = x;
    }
}

/// The tone stack (and the DC blocker ahead of it) over a base-rate chunk.
static void tonestack_stage(gf_amp* a, float* buf, int n) {
    const float am = a->p.amp_on ? 1.0f : 0.0f;
    for (int i = 0; i < n; ++i) {
        a->amp_mix += (am - a->amp_mix) * a->k_fade;
        if (a->amp_mix <= 1e-6f) continue;
        const float x = buf[i];
        const float t = tonestack_tick(a, onepole_hp(&a->dc, a->g_dc, x));
        buf[i] = x + (t - x) * a->amp_mix;
    }
}

/// The IR cabinet into [g]: the current IR, crossfaded from the previous one
/// while a swap is in progress.
static void ir_render(gf_amp* a, const float* in, float* g, int n) {
    gf_convolver_process(a->conv, in, g, n);
    if (!a->conv_old) return;
    float* o = a->cab_o;
    gf_convolver_process(a->conv_old, in, o, n);
    for (int i = 0; i < n; ++i) {
        a->ir_swap += (1.0f - a->ir_swap) * a->k_fade;
        g[i] = o[i] + (g[i] - o[i]) * a->ir_swap;
    }
    if (a->ir_swap >= 1.0f - 1e-4f) retire_old_ir(a);
}

/// Starts or stops the filter and IR paths. One that resumes after being
/// skipped starts from silence rather than from stale history.
static void cab_paths(gf_amp* a, int use_f, int use_ir) {
    if (use_f && !a->f_running) {
        for (int i = 0; i < CAB_SECTIONS; ++i) a->cab[i].s1 = a->cab[i].s2 = 0.0f;
    }
    if (use_ir && !a->ir_running) {
        gf_convolver_reset(a->conv);
        gf_convolver_reset(a->conv_old);
    }
    if (!use_ir) retire_old_ir(a);   // nothing heard, nothing to fade
    a->f_running = use_f;
    a->ir_running = use_ir;
}

/// The cabinet over a base-rate chunk: built-in filters, the IR, or a
/// crossfade between them, faded in and out by the Cab switch. Each path is
/// only computed while it can be heard.
static void cab_stage(gf_amp* a, float* buf, int n) {
    const float cm = a->p.cab_on ? 1.0f : 0.0f;
    const float im = ir_target(a);
    if (a->cab_mix <= 1e-6f && cm == 0.0f) {
        cab_paths(a, 0, 0);
        finish_clear(a);
        return;
    }
    const int use_f = !(a->ir_mix >= 1.0f - 1e-6f && im == 1.0f);
    const int use_ir = a->conv && (a->ir_mix > 1e-6f || im == 1.0f);
    cab_paths(a, use_f, use_ir);
    float* f = a->cab_f;
    float* g = a->cab_g;
    if (use_f) for (int i = 0; i < n; ++i) f[i] = cab_tick(a, buf[i]);
    if (use_ir) ir_render(a, buf, g, n);
    for (int i = 0; i < n; ++i) {
        a->cab_mix += (cm - a->cab_mix) * a->k_fade;
        a->ir_mix += (im - a->ir_mix) * a->k_fade;
        float c = use_f ? f[i] : g[i];
        if (use_f && use_ir) c += (g[i] - f[i]) * a->ir_mix;
        buf[i] += (c - buf[i]) * a->cab_mix;
    }
    finish_clear(a);
}

/// Output level over a base-rate chunk.
static void level_stage(gf_amp* a, float* buf, int n) {
    const float lv = level_target(&a->p);
    for (int i = 0; i < n; ++i) {
        a->level += (lv - a->level) * a->k_smooth;
        buf[i] *= a->level;
    }
}

/// Tone stack, cabinet and output level over a base-rate chunk, in place.
static void process_base(gf_amp* a, float* buf, int n) {
    tonestack_stage(a, buf, n);
    cab_stage(a, buf, n);
    level_stage(a, buf, n);
}

static void process_chunk(gf_amp* a, const float* in, float* out, int n) {
    chase_tonestack(a);
    hb_up(a->hb, &a->hb_upst, in, a->up, n, a->aa);
    process_oversampled(a, 2 * n);
    hb_down(a->hb, &a->hb_downst, a->up, out, n, a->aa);
    process_base(a, out, n);
}

void gf_amp_process(gf_amp* a, const float* in, float* out, int n) {
    if (!a || !in || !out || n <= 0) return;
#ifdef GF_AMP_HAS_SSE
    // Flush denormals: filter tails decaying towards silence otherwise slow
    // x86 floating point down by orders of magnitude. Restored on the way out
    // so the host's own settings are left alone.
    const unsigned int csr = _mm_getcsr();
    _mm_setcsr(csr | 0x8040);
#endif
    for (int done = 0; done < n; done += CHUNK) {
        const int len = (n - done < CHUNK) ? n - done : CHUNK;
        process_chunk(a, in + done, out + done, len);
    }
#ifdef GF_AMP_HAS_SSE
    _mm_setcsr(csr);
#endif
}

int gf_amp_debug_resample_roundtrip(const float* in, float* out, int n) {
    gf_amp* a = gf_amp_create(48000.0f);
    if (!a) return -1;
    for (int done = 0; done < n; done += CHUNK) {
        const int len = (n - done < CHUNK) ? n - done : CHUNK;
        hb_up(a->hb, &a->hb_upst, in + done, a->up, len, 1);
        hb_down(a->hb, &a->hb_downst, a->up, out + done, len, 1);
    }
    gf_amp_destroy(a);
    return 0;
}

int gf_amp_debug_upsample(const float* in, float* up, int n) {
    gf_amp* a = gf_amp_create(48000.0f);
    if (!a) return -1;
    for (int done = 0; done < n; done += CHUNK) {
        const int len = (n - done < CHUNK) ? n - done : CHUNK;
        hb_up(a->hb, &a->hb_upst, in + done, up + 2 * done, len, 1);
    }
    gf_amp_destroy(a);
    return 0;
}
