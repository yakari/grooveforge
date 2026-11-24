// gf_limiter.c - Zero-latency output limiter. See gf_limiter.h.
#include "gf_limiter.h"

#include <math.h>
#include <string.h>

/// The hold is refreshed while the signal stays within this fraction of the
/// ceiling (about -0.5 dB). On a steady loud note each crest lands right at
/// the ceiling; refreshing only on a strict overshoot would let the hold run
/// out between crests and the gain wobble with the wave.
#define NEAR_CEILING 0.944f

void gf_limiter_init(gf_limiter* lim, float sample_rate) {
    if (sample_rate <= 0.0f) sample_rate = 48000.0f;
    lim->gain = 1.0f;
    lim->hold_left = 0;
    lim->hold_samples = (int)(GF_LIMITER_HOLD_SEC * sample_rate);
    // One-pole smoothing: the gap to unity shrinks by this factor per sample,
    // giving a time constant of GF_LIMITER_RELEASE_SEC.
    lim->release_coeff = expf(-1.0f / (GF_LIMITER_RELEASE_SEC * sample_rate));
}

/// Returns the gain to apply to a stereo sample whose louder side is [peak],
/// and advances the limiter's state by one sample.
static inline float next_gain(gf_limiter* lim, float peak) {
    float g = lim->gain;
    if (peak * g > GF_LIMITER_THRESHOLD) {
        // Instant attack: exactly enough reduction to land on the ceiling.
        g = GF_LIMITER_THRESHOLD / peak;
        lim->hold_left = lim->hold_samples;
    } else if (peak * g > GF_LIMITER_THRESHOLD * NEAR_CEILING) {
        // Still riding the ceiling: keep the gain where it is.
        lim->hold_left = lim->hold_samples;
    } else if (lim->hold_left > 0) {
        lim->hold_left--;
    } else {
        // Release: glide back towards unity.
        g = 1.0f - (1.0f - g) * lim->release_coeff;
    }
    lim->gain = g;
    return g;
}

/// Returns 1 when every sample of the block is a finite number.
static int block_is_finite(const float* left, const float* right, int frames) {
    for (int i = 0; i < frames; ++i) {
        if (!isfinite(left[i]) || !isfinite(right[i])) return 0;
    }
    return 1;
}

void gf_limiter_process(gf_limiter* lim, float* left, float* right, int frames) {
    if (!block_is_finite(left, right, frames)) {
        // A NaN would make every later gain NaN: silence and start over.
        memset(left, 0, sizeof(float) * (size_t)frames);
        memset(right, 0, sizeof(float) * (size_t)frames);
        lim->gain = 1.0f;
        lim->hold_left = 0;
        return;
    }
    for (int i = 0; i < frames; ++i) {
        const float l = left[i], r = right[i];
        const float peak = fmaxf(fabsf(l), fabsf(r));
        const float g = next_gain(lim, peak);
        left[i] = l * g;
        right[i] = r * g;
    }
}

void gf_limiter_process_interleave(gf_limiter* lim, const float* in_left,
                                   const float* in_right, float* out,
                                   int frames) {
    if (!block_is_finite(in_left, in_right, frames)) {
        memset(out, 0, sizeof(float) * (size_t)frames * 2);
        lim->gain = 1.0f;
        lim->hold_left = 0;
        return;
    }
    for (int i = 0; i < frames; ++i) {
        const float l = in_left[i], r = in_right[i];
        const float peak = fmaxf(fabsf(l), fabsf(r));
        const float g = next_gain(lim, peak);
        out[i * 2] = l * g;
        out[i * 2 + 1] = r * g;
    }
}
