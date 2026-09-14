// gf_autotune.h — Real-time pitch correction ("autotune") for a sung line.
//
// Listens to a monophonic voice, works out which note it is closest to, and
// bends it onto that note. Turned all the way up it is the hard, stepped,
// robotic sound pop records made famous; turned down it nudges a singer who
// drifts flat back into tune.
//
// Three stages, run in 64-sample control chunks:
//
//   1. **Hear the note.** The shared YIN tracker (gf_pitch) reports the sung
//      pitch as a fractional MIDI note.
//
//   2. **Decide where it should be.** The nearest note of the active scale is
//      the target; the correction is the distance to it, scaled by Strength
//      and faded out by Flex-Tune for notes that are nowhere near a scale
//      note. Retune Speed smooths the correction — 0 ms jumps straight to the
//      target, which is the robot — and Humanize slows it further on held
//      notes so their vibrato survives.
//
//   3. **Move the pitch.** A two-head delay-line shifter. Each head reads the
//      recent input at a rate of `ratio` (faster reads raise the pitch) under
//      a sin^2 window; the heads are half a window apart, so their gains always
//      sum to one. When a head's window closes it jumps back to a fresh read
//      position, placed a whole number of *sung periods* away from the other
//      head so the two overlap in phase. That pitch-synchronous splice is what
//      stops the crossfade from sounding like a flanger.
//
// Why not the phase vocoder the harmonizer uses: a vocoder adds ~45 ms of
// latency, which a singer monitoring themselves hears as a slap-back echo,
// and it stalls for a few blocks whenever the shift jumps — which a hard
// retune does every time the note changes. The delay line adds a few
// milliseconds and follows any change of ratio without a gap. Its cost is
// that it resamples each grain, so large shifts move the formants too (the
// chipmunk effect). For corrections of a semitone or two that is inaudible,
// and for Transpose it is half the fun.
//
// Real-time safety: after gf_autotune_create nothing on the hot path
// allocates, locks or logs.

#ifndef GF_AUTOTUNE_H
#define GF_AUTOTUNE_H

#ifdef __cplusplus
extern "C" {
#endif

/// Built-in scales, in the order the descriptor's `scale` selector lists them.
typedef enum {
    GF_AUTOTUNE_SCALE_CHROMATIC = 0,
    GF_AUTOTUNE_SCALE_MAJOR,
    GF_AUTOTUNE_SCALE_MINOR,
    GF_AUTOTUNE_SCALE_HARMONIC_MINOR,
    GF_AUTOTUNE_SCALE_MAJOR_PENTATONIC,
    GF_AUTOTUNE_SCALE_MINOR_PENTATONIC,
    GF_AUTOTUNE_SCALE_BLUES,
    GF_AUTOTUNE_SCALE_COUNT
} gf_autotune_scale;

/// Everything the caller controls, set together once per block.
typedef struct {
    /// Allowed pitch classes as a 12-bit mask, bit 0 = C. 0 is treated as
    /// chromatic. See [gf_autotune_scale_mask] to build one from a key.
    int scale_mask;

    /// How much of the distance to the target note is corrected, 0..1.
    float strength;

    /// Time constant of the correction, in milliseconds. 0 snaps instantly.
    float retune_ms;

    /// 0..1. Extra smoothing applied to notes held longer than a moment, so
    /// vibrato on a sustained note passes through while short notes still
    /// snap.
    float humanize;

    /// 0..1. Narrows the zone around each scale note inside which correction
    /// applies; a pitch far from every scale note — a slide, a scoop, a
    /// deliberate blue note — is left alone. 0 corrects everything.
    float flex;

    /// Fixed shift added after correction, in semitones.
    float transpose;
} gf_autotune_params;

/// Opaque handle. All state is owned by this struct.
typedef struct gf_autotune gf_autotune;

/// Creates a corrector for [sample_rate] Hz audio. Returns NULL on bad input
/// or out-of-memory.
gf_autotune* gf_autotune_create(float sample_rate);

/// Re-targets the corrector at a new [sample_rate] after the audio device
/// changed rate. Allocation-free; safe from the audio thread. Clears the audio
/// history, so the voice drops out for a grain. Out-of-range rates are
/// ignored.
void gf_autotune_set_sample_rate(gf_autotune* a, float sample_rate);

/// Destroys a corrector. Safe to pass NULL.
void gf_autotune_destroy(gf_autotune* a);

/// Clears all audio history and forgets the current note. Allocation-free;
/// safe from the audio thread.
void gf_autotune_reset(gf_autotune* a);

/// Applies [params]. Cheap; call once per block from the audio thread.
void gf_autotune_set_params(gf_autotune* a, const gf_autotune_params* params);

/// Corrects [n] frames.
///
/// [in_r] and [out_r] are NULL for a mono signal. For a stereo one the pitch
/// is tracked on the sum of both channels and the same correction is applied
/// to each, so the image does not smear. Input and output may be the same
/// buffer. Any block size is accepted.
void gf_autotune_process(gf_autotune* a,
                         const float* in_l, const float* in_r,
                         float* out_l, float* out_r, int n);

/// The pitch currently heard, as a fractional MIDI note, or a negative number
/// when nothing pitched is being heard.
float gf_autotune_input_note(const gf_autotune* a);

/// The note the voice is being pulled towards, or -1 when there is none.
int gf_autotune_target_note(const gf_autotune* a);

/// The correction currently applied, in semitones, excluding Transpose.
float gf_autotune_correction(const gf_autotune* a);

/// Builds a pitch-class mask for [scale] rooted on [key] (0 = C .. 11 = B).
/// Out-of-range values fall back to chromatic and C respectively.
int gf_autotune_scale_mask(int scale, int key);

#ifdef __cplusplus
}
#endif

#endif // GF_AUTOTUNE_H
