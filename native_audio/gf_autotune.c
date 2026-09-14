// gf_autotune.c — Implementation of the real-time pitch corrector.
// See gf_autotune.h for the method and why it is a delay line.

#include "gf_autotune.h"

#include "gf_pitch.h"

#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ── Configuration ────────────────────────────────────────────────────────────

/// Samples per control update. Pitch, target and correction are recomputed
/// this often; 64 frames is ~1.3 ms at 48 kHz, far finer than anyone can hear
/// a correction step, and it keeps the exp/pow maths off the per-sample path.
#define GF_AT_CHUNK 64

/// Length of one shifter grain (one head's window), in seconds.
///
/// Long enough to span two periods of the lowest voice the tracker follows
/// (65 Hz, 15 ms per period), so a splice always has a whole period to align
/// to. Shorter would splice more often; longer would add latency when
/// shifting up, because a head has to start far enough back to survive a
/// whole grain of catching up with the input.
#define GF_AT_GRAIN_SECONDS 0.030

/// Closest a read head may come to the write head, in samples. The 4-point
/// interpolator reads two samples past the head, which must already exist.
#define GF_AT_MIN_DELAY 4.0

/// How much closer a new note must be before the target switches to it, in
/// semitones.
///
/// Without it, a singer sitting exactly between two notes would flip the
/// target back and forth on every pitch estimate, which is heard as a fast
/// warble rather than as either note.
#define GF_AT_HYSTERESIS 0.15f

/// Humanize: extra retune time at 100 %, and when on a held note it applies.
/// A note shorter than the onset gets the plain Retune Speed; by the end of
/// the ramp the full extra smoothing is in place.
#define GF_AT_HUMANIZE_MAX_MS     300.0f
#define GF_AT_HUMANIZE_ONSET_S    0.15f
#define GF_AT_HUMANIZE_RAMP_S     0.25f

/// How long the correction is held through an unpitched gap (a consonant, a
/// breath, a tracker dropout) before it lets go, and how fast it then does.
///
/// Letting go at once would bend every "s" and "t" back to the raw pitch in
/// the middle of a robot-tuned word; holding forever would leave the last
/// note's correction on the next phrase's first syllable.
#define GF_AT_HOLD_SECONDS    0.100f
#define GF_AT_RELEASE_MS      60.0f

/// Total shift (correction + Transpose) is clamped to this many semitones.
#define GF_AT_MAX_SHIFT 24.0f

/// Ring buffer length, in seconds of audio at the highest supported rate.
/// Covers the deepest read a head can need — a +24 st shift starts a head
/// three grains back, plus a period of slack, about 0.11 s.
///
/// Sized for the highest rate rather than the creation rate so that the
/// audio device changing rate later never needs a bigger buffer, which
/// could only be allocated on the audio thread.
#define GF_AT_RING_SECONDS 0.125
#define GF_AT_MAX_SAMPLE_RATE 192000.0f

/// Semitone-relative templates for [gf_autotune_scale], bit 0 = the root.
static const int kScaleTemplates[GF_AUTOTUNE_SCALE_COUNT] = {
    0xFFF,  // chromatic:        every semitone
    0xAB5,  // major:            0 2 4 5 7 9 11
    0x5AD,  // natural minor:    0 2 3 5 7 8 10
    0x9AD,  // harmonic minor:   0 2 3 5 7 8 11
    0x295,  // major pentatonic: 0 2 4 7 9
    0x4A9,  // minor pentatonic: 0 3 5 7 10
    0x4E9,  // blues:            0 3 5 6 7 10
};

// ── State ────────────────────────────────────────────────────────────────────

/// One read head of the delay-line shifter.
typedef struct {
    /// How far behind the write position this head reads, in samples.
    double delay;
    /// Position inside the head's window, 0..1. The gain is sin^2(pi*phase),
    /// silent at both ends — which is when the head may jump.
    double phase;
} gf_autotune_head;

struct gf_autotune {
    float sample_rate;
    gf_pitch* pitch;

    // ── Shifter ──
    float* ring[2];         // input history per channel
    int    ring_size;       // power of two
    int    ring_mask;
    int    write;           // index the next input sample goes to
    gf_autotune_head head[2];
    double grain;           // window length, samples

    // ── Parameters ──
    gf_autotune_params params;

    // ── Control state ──
    float  input_note;      // latest pitch estimate, negative when unpitched
    int    target;          // note being pulled towards, -1 for none
    float  correction;      // smoothed correction, semitones
    double held;            // samples spent on the current target
    double unvoiced;        // samples since the last pitched estimate
    double period;          // sung period in samples, 0 when unknown
    double ratio;           // playback-rate ratio the heads read at
};

// ── Lifecycle ────────────────────────────────────────────────────────────────

/// Smallest power of two that is at least [n].
static int gf_autotune_pow2(int n) {
    int size = 1;
    while (size < n) size <<= 1;
    return size;
}

gf_autotune* gf_autotune_create(float sample_rate) {
    if (sample_rate < 8000.0f || sample_rate > GF_AT_MAX_SAMPLE_RATE) return NULL;

    gf_autotune* a = (gf_autotune*)calloc(1, sizeof(gf_autotune));
    if (!a) return NULL;

    a->sample_rate = sample_rate;
    a->grain       = sample_rate * GF_AT_GRAIN_SECONDS;
    a->ring_size   = gf_autotune_pow2(
            (int)(GF_AT_MAX_SAMPLE_RATE * GF_AT_RING_SECONDS));
    a->ring_mask   = a->ring_size - 1;
    a->ring[0]     = (float*)calloc((size_t)a->ring_size, sizeof(float));
    a->ring[1]     = (float*)calloc((size_t)a->ring_size, sizeof(float));
    a->pitch       = gf_pitch_create(sample_rate);
    if (!a->ring[0] || !a->ring[1] || !a->pitch) {
        gf_autotune_destroy(a);
        return NULL;
    }

    // Full-on, chromatic, instant: the sound people mean by "autotune".
    a->params.scale_mask = 0xFFF;
    a->params.strength   = 1.0f;
    gf_autotune_reset(a);
    return a;
}

void gf_autotune_destroy(gf_autotune* a) {
    if (!a) return;
    gf_pitch_destroy(a->pitch);
    free(a->ring[0]);
    free(a->ring[1]);
    free(a);
}

void gf_autotune_reset(gf_autotune* a) {
    if (!a) return;
    memset(a->ring[0], 0, sizeof(float) * (size_t)a->ring_size);
    memset(a->ring[1], 0, sizeof(float) * (size_t)a->ring_size);
    gf_pitch_reset(a->pitch);
    a->write = 0;

    // Half a window apart, so one head is fully open while the other is shut.
    a->head[0].delay = GF_AT_MIN_DELAY;
    a->head[0].phase = 0.0;
    a->head[1].delay = GF_AT_MIN_DELAY;
    a->head[1].phase = 0.5;

    a->input_note = -1.0f;
    a->target     = -1;
    a->correction = 0.0f;
    a->held       = 0.0;
    a->unvoiced   = 0.0;
    a->period     = 0.0;
    a->ratio      = 1.0;
}

void gf_autotune_set_sample_rate(gf_autotune* a, float sample_rate) {
    if (!a || sample_rate < 8000.0f || sample_rate > GF_AT_MAX_SAMPLE_RATE) return;
    if (sample_rate == a->sample_rate) return;
    a->sample_rate = sample_rate;
    a->grain       = sample_rate * GF_AT_GRAIN_SECONDS;
    gf_pitch_set_sample_rate(a->pitch, sample_rate);
    // History recorded at the old rate would play back at the wrong pitch for
    // a grain; a clean start is a moment of silence instead.
    gf_autotune_reset(a);
}

// ── Parameters ───────────────────────────────────────────────────────────────

/// Clamps [v] into [lo, hi].
static float gf_autotune_clamp(float v, float lo, float hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

void gf_autotune_set_params(gf_autotune* a, const gf_autotune_params* p) {
    if (!a || !p) return;
    a->params.scale_mask = (p->scale_mask & 0xFFF) ? (p->scale_mask & 0xFFF) : 0xFFF;
    a->params.strength   = gf_autotune_clamp(p->strength, 0.0f, 1.0f);
    a->params.retune_ms  = gf_autotune_clamp(p->retune_ms, 0.0f, 2000.0f);
    a->params.humanize   = gf_autotune_clamp(p->humanize, 0.0f, 1.0f);
    a->params.flex       = gf_autotune_clamp(p->flex, 0.0f, 1.0f);
    a->params.transpose  = gf_autotune_clamp(p->transpose, -GF_AT_MAX_SHIFT, GF_AT_MAX_SHIFT);
}

int gf_autotune_scale_mask(int scale, int key) {
    if (scale < 0 || scale >= GF_AUTOTUNE_SCALE_COUNT) scale = 0;
    if (key < 0 || key > 11) key = 0;
    const int t = kScaleTemplates[scale];
    // Rotate the root-relative template up to the key, wrapping at the octave.
    return ((t << key) | (t >> (12 - key))) & 0xFFF;
}

// ── Target note ──────────────────────────────────────────────────────────────

/// True when MIDI [note]'s pitch class is in [mask].
static int gf_autotune_allowed(int note, int mask) {
    return (mask & (1 << (((note % 12) + 12) % 12))) != 0;
}

/// Nearest allowed note to the fractional [note]. Ties go to the lower note,
/// the convention the harmonizers' Scale Lock also follows.
static int gf_autotune_nearest(float note, int mask) {
    const int base = (int)floorf(note);
    int best = -1;
    float best_distance = 1e9f;
    // Every scale repeats within an octave, so one octave either side is
    // guaranteed to contain the answer. Ascending with a strict comparison
    // is what makes the lower note win a tie.
    for (int n = base - 12; n <= base + 13; n++) {
        if (!gf_autotune_allowed(n, mask)) continue;
        const float distance = fabsf((float)n - note);
        if (distance < best_distance) {
            best_distance = distance;
            best = n;
        }
    }
    return best;
}

/// The target for [note], keeping the previous one unless the new one is
/// clearly closer. See [GF_AT_HYSTERESIS].
static int gf_autotune_choose_target(const gf_autotune* a, float note) {
    const int mask = a->params.scale_mask;
    const int nearest = gf_autotune_nearest(note, mask);
    const int previous = a->target;

    if (previous < 0 || nearest == previous) return nearest;
    // The scale changed under the note: the old target is no longer valid.
    if (!gf_autotune_allowed(previous, mask)) return nearest;

    const float advantage = fabsf(note - (float)previous) - fabsf(note - (float)nearest);
    return (advantage < GF_AT_HYSTERESIS) ? previous : nearest;
}

/// Flex-Tune weight for a pitch [distance] semitones from its target.
///
/// The correction zone shrinks from a full semitone at 0 % to nothing at
/// 100 %. Inside its inner half a note is corrected fully; across the outer
/// half the correction fades out, so a slide crossing the edge does not jump.
static float gf_autotune_flex_weight(float flex, float distance) {
    if (flex <= 0.0f) return 1.0f;
    const float reach = 1.0f - flex;
    if (distance <= reach * 0.5f) return 1.0f;
    if (distance >= reach) return 0.0f;
    return (reach - distance) / (reach * 0.5f);
}

/// Retune time for the current note, including Humanize's extra smoothing on
/// notes that have been held for a while.
static float gf_autotune_retune_ms(const gf_autotune* a) {
    const float held_s = (float)(a->held / a->sample_rate);
    const float ramp = gf_autotune_clamp(
            (held_s - GF_AT_HUMANIZE_ONSET_S) / GF_AT_HUMANIZE_RAMP_S, 0.0f, 1.0f);
    return a->params.retune_ms + a->params.humanize * GF_AT_HUMANIZE_MAX_MS * ramp;
}

// ── Control ──────────────────────────────────────────────────────────────────

/// Works out the correction to aim for while a pitch is heard, and how fast
/// to get there.
static void gf_autotune_track_voiced(gf_autotune* a, float note, int n,
                                     float* desired, float* tau_ms) {
    a->unvoiced = 0.0;

    const int target = gf_autotune_choose_target(a, note);
    if (target != a->target) {
        a->target = target;
        a->held = 0.0;          // a new note: Humanize starts over
    } else {
        a->held += n;
    }

    const float distance = (float)target - note;
    const float weight = gf_autotune_flex_weight(a->params.flex, fabsf(distance));
    *desired = distance * a->params.strength * weight;
    *tau_ms  = gf_autotune_retune_ms(a);

    // The period the shifter aligns its splices to: MIDI 69 is A4 = 440 Hz.
    const double hz = 440.0 * pow(2.0, (note - 69.0) / 12.0);
    a->period = a->sample_rate / hz;
}

/// Works out the correction to aim for while nothing pitched is heard: hold
/// it briefly, then let go.
static void gf_autotune_track_unvoiced(gf_autotune* a, int n,
                                       float* desired, float* tau_ms) {
    a->unvoiced += n;
    if (a->unvoiced < GF_AT_HOLD_SECONDS * a->sample_rate) {
        // A gap inside a word: keep correcting exactly as before, and keep
        // aligning splices to the last period heard.
        *desired = a->correction;
        *tau_ms  = 0.0f;
        return;
    }
    *desired  = 0.0f;
    *tau_ms   = GF_AT_RELEASE_MS;
    a->target = -1;
    a->held   = 0.0;
    a->period = 0.0;
}

/// Updates the correction and the shifter's ratio for the next [n] samples.
static void gf_autotune_update_control(gf_autotune* a, int n) {
    const float note = gf_pitch_midi_note(a->pitch);
    float desired = 0.0f;
    float tau_ms = 0.0f;

    if (note >= 0.0f) {
        gf_autotune_track_voiced(a, note, n, &desired, &tau_ms);
    } else {
        gf_autotune_track_unvoiced(a, n, &desired, &tau_ms);
    }
    a->input_note = note;

    // One-pole smoothing towards the desired correction. A time constant of
    // zero is the robot: the correction lands in a single step.
    const float alpha = (tau_ms <= 0.0f)
            ? 1.0f
            : 1.0f - (float)exp(-(double)n / (tau_ms * 0.001 * a->sample_rate));
    a->correction += (desired - a->correction) * alpha;

    // Semitones to a playback-rate ratio: +12 reads twice as fast.
    const float shift = gf_autotune_clamp(a->correction + a->params.transpose,
                                          -GF_AT_MAX_SHIFT, GF_AT_MAX_SHIFT);
    a->ratio = pow(2.0, shift / 12.0);
}

// ── Shifter ──────────────────────────────────────────────────────────────────

/// Reads [ring] [delay] samples behind [write] with 4-point Hermite
/// interpolation. Heads sit between samples almost all the time; linear
/// interpolation would dull the top end noticeably at the rates used here.
static float gf_autotune_read(const float* ring, int mask, int write, double delay) {
    const double pos = (double)write - delay;
    const double floor_pos = floor(pos);
    const int i = (int)floor_pos;          // may be negative; the mask wraps it
    const float t = (float)(pos - floor_pos);

    const float xm1 = ring[(i - 1) & mask];
    const float x0  = ring[i & mask];
    const float x1  = ring[(i + 1) & mask];
    const float x2  = ring[(i + 2) & mask];

    const float c1 = 0.5f * (x1 - xm1);
    const float c2 = xm1 - 2.5f * x0 + 2.0f * x1 - 0.5f * x2;
    const float c3 = 0.5f * (x2 - xm1) + 1.5f * (x0 - x1);
    return ((c3 * t + c2) * t + c1) * t + x0;
}

/// Moves head [index] to a fresh read position at the start of its window.
///
/// The new position is placed a whole number of sung periods away from the
/// other head, which is fully open at this moment. The two then carry the
/// same waveform in phase through the crossfade — the difference between a
/// clean splice and a comb filter. With no pitch to align to (noise, a
/// consonant) there is nothing to be in phase with, so it goes straight to
/// the shallowest safe position.
static void gf_autotune_relocate(gf_autotune* a, int index) {
    gf_autotune_head* head = &a->head[index];
    const gf_autotune_head* other = &a->head[1 - index];

    // Reading faster than real time eats into the delay by (ratio - 1) per
    // sample, so a head shifting up must start far enough back to last its
    // whole window. Reading slower grows the delay instead.
    const double shrink = (a->ratio > 1.0) ? (a->ratio - 1.0) * a->grain : 0.0;
    const double grow   = (a->ratio < 1.0) ? (1.0 - a->ratio) * a->grain : 0.0;
    const double lowest  = GF_AT_MIN_DELAY + shrink;
    const double highest = (double)a->ring_size - 8.0 - grow;

    double delay = lowest;
    if (a->period > 1.0) {
        const double periods = ceil((lowest - other->delay) / a->period);
        delay = other->delay + periods * a->period;
    }
    if (delay > highest) delay = highest;
    head->delay = delay;
}

/// Runs the two heads over [n] samples at the current ratio.
static void gf_autotune_render(gf_autotune* a,
                               const float* in_l, const float* in_r,
                               float* out_l, float* out_r, int n) {
    const double drift = 1.0 - a->ratio;   // delay change per sample
    const double step  = 1.0 / a->grain;   // window phase advance per sample
    const double max_delay = (double)a->ring_size - 8.0;

    for (int i = 0; i < n; i++) {
        // Record first, so a head may read the sample that just arrived. The
        // right ring is kept current even for mono input, so a source that
        // turns stereo later has history to read from.
        const float l = in_l[i];
        a->ring[0][a->write] = l;
        a->ring[1][a->write] = in_r ? in_r[i] : l;

        float sum_l = 0.0f;
        float sum_r = 0.0f;
        for (int h = 0; h < 2; h++) {
            gf_autotune_head* head = &a->head[h];
            const float s = (float)sin(M_PI * head->phase);
            const float gain = s * s;

            sum_l += gain * gf_autotune_read(a->ring[0], a->ring_mask, a->write, head->delay);
            if (out_r) {
                sum_r += gain * gf_autotune_read(a->ring[1], a->ring_mask, a->write, head->delay);
            }

            // Drift, kept inside the buffer. Hitting either bound only
            // happens when the ratio moves a lot mid-window; the head then
            // briefly plays at the input's own pitch, which is inaudible next
            // to reading outside the history.
            head->delay += drift;
            if (head->delay < GF_AT_MIN_DELAY) head->delay = GF_AT_MIN_DELAY;
            if (head->delay > max_delay) head->delay = max_delay;

            head->phase += step;
            if (head->phase >= 1.0) {
                head->phase -= 1.0;
                gf_autotune_relocate(a, h);   // silent now, so it may jump
            }
        }

        out_l[i] = sum_l;
        if (out_r) out_r[i] = sum_r;
        a->write = (a->write + 1) & a->ring_mask;
    }
}

// ── Processing ───────────────────────────────────────────────────────────────

void gf_autotune_process(gf_autotune* a,
                         const float* in_l, const float* in_r,
                         float* out_l, float* out_r, int n) {
    if (!a || !in_l || !out_l || n <= 0) return;

    float mid[GF_AT_CHUNK];
    int done = 0;
    while (done < n) {
        const int len = (n - done < GF_AT_CHUNK) ? (n - done) : GF_AT_CHUNK;

        // Track a stereo source on its mid signal, so a voice panned to one
        // side is still heard.
        const float* track = in_l + done;
        if (in_r) {
            for (int k = 0; k < len; k++) {
                mid[k] = 0.5f * (in_l[done + k] + in_r[done + k]);
            }
            track = mid;
        }

        gf_pitch_process(a->pitch, track, len);
        gf_autotune_update_control(a, len);
        gf_autotune_render(a,
                           in_l + done, in_r ? in_r + done : NULL,
                           out_l + done, out_r ? out_r + done : NULL,
                           len);
        done += len;
    }
}

// ── Readouts ─────────────────────────────────────────────────────────────────

float gf_autotune_input_note(const gf_autotune* a) { return a ? a->input_note : -1.0f; }
int   gf_autotune_target_note(const gf_autotune* a) { return a ? a->target : -1; }
float gf_autotune_correction(const gf_autotune* a) { return a ? a->correction : 0.0f; }
