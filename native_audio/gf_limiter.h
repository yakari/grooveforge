// gf_limiter.h - Zero-latency output limiter for the master bus.
//
// The last stage before the sound card on every platform. Its job is to keep
// the mix from ever leaving the converter's range: a float sample above 1.0
// is hard-clipped by the driver into a square wave, which sounds harsh and,
// played loud for long enough, burns out small speakers.
//
// How it works, for readers who are not audio developers:
//
//   - A *limiter* is an automatic volume knob that only ever turns down. When
//     a sample would cross the threshold, the volume (the "gain") drops at
//     once, by exactly as much as needed, so nothing crosses it.
//
//   - It then *holds* that gain for a while before letting it rise again.
//     Without the hold, the gain would creep back up between two crests of a
//     low note and be pulled down again on the next crest, reshaping every
//     cycle of the wave: that is distortion. The hold outlasts one cycle of
//     the lowest note a bass can play, so on a sustained loud note the gain
//     stays flat and the limiter only makes it quieter.
//
//   - Release is slow and smooth (an exponential approach back to unity), so
//     the volume does not audibly "pump" after a loud chord.
//
//   - No lookahead. A lookahead limiter sees peaks coming and is gentler on
//     the very first one, but it delays everything by its window, and this
//     app is played live. The cost of instant attack is that the rising edge
//     of the first overloaded cycle is flattened; after that the gain holds.
//
//   - Left and right share one gain, so loud notes do not drag the stereo
//     image to one side.
//
//   - A non-finite sample (NaN or infinity, from a misbehaving plugin) would
//     otherwise poison the gain for good. The block is silenced and the
//     limiter starts afresh.
//
// Real-time safety: no allocation, no lock, no logging. The state is a plain
// struct owned by the caller.

#ifndef GF_LIMITER_H
#define GF_LIMITER_H

#ifdef __cplusplus
extern "C" {
#endif

/// Ceiling, in linear amplitude: -1 dBFS. One decibel below full scale
/// leaves room for the overshoot a DAC's reconstruction filter adds between
/// samples.
#define GF_LIMITER_THRESHOLD 0.8912509f

/// How long the gain is held after the signal last came near the ceiling.
/// Longer than one period of a 41 Hz low E (24 ms).
#define GF_LIMITER_HOLD_SEC 0.040f

/// Time constant of the return to unity once the hold has run out.
#define GF_LIMITER_RELEASE_SEC 0.200f

/// Limiter state. Zero-initialised is not valid: call gf_limiter_init.
typedef struct {
    float gain;          ///< Current gain, 0 < gain <= 1.
    int hold_left;       ///< Samples left before the release may start.
    int hold_samples;    ///< GF_LIMITER_HOLD_SEC at the current rate.
    float release_coeff; ///< Per-sample smoothing factor of the release.
} gf_limiter;

/// Sets [lim] to unity gain and computes its timing for [sample_rate] Hz.
/// Call again whenever the stream's rate changes.
void gf_limiter_init(gf_limiter* lim, float sample_rate);

/// Limits [frames] stereo samples in place, planar layout ([left] and
/// [right] are separate arrays). Afterwards every sample's magnitude is at
/// most GF_LIMITER_THRESHOLD.
void gf_limiter_process(gf_limiter* lim, float* left, float* right, int frames);

/// Same, reading planar [in_left]/[in_right] and writing interleaved stereo
/// to [out] (L0 R0 L1 R1 ...). The inputs are not modified.
void gf_limiter_process_interleave(gf_limiter* lim, const float* in_left,
                                   const float* in_right, float* out,
                                   int frames);

#ifdef __cplusplus
}
#endif

#endif // GF_LIMITER_H
