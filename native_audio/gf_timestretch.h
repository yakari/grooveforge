// gf_timestretch — offline time-stretching of a recorded take.
//
// Slowing a rehearsal down to practise is not the same as playing the file
// slower: reading a recording at 70% of its rate drops it roughly six
// semitones, which makes it useless to play along to. The duration has to
// change while the pitch stays put, which is what the phase vocoder does.
//
// Deliberately offline, writing a whole file rather than processing blocks in
// the audio callback. Stretching N tracks live means N FFTs per block on the
// audio thread, and the device most likely to be in a school rehearsal is the
// one least able to afford it — a dropout mid-take is a worse outcome than
// waiting two seconds after moving a tempo slider. Rendering once also lifts
// the real-time constraint, so the analysis window can be larger than a live
// path would allow.
//
// The rehearsal engine then plays the rendered file through the same disk
// streaming path as any other take, knowing nothing about stretching at all.

#ifndef GF_TIMESTRETCH_H
#define GF_TIMESTRETCH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Result of a render. Negative values are failures.
typedef enum {
    GF_TS_OK = 0,
    GF_TS_ERR_OPEN_INPUT = -1,   ///< missing, unreadable, or not mono 16-bit
    GF_TS_ERR_OPEN_OUTPUT = -2,
    GF_TS_ERR_RATIO = -3,        ///< outside the supported range
    GF_TS_ERR_MEMORY = -4,
    GF_TS_ERR_WRITE = -5,
} gf_ts_result;

/// Smallest and largest supported stretch.
///
/// A quarter speed is already past what the vocoder can make musical, and
/// nobody practises a tune at four times its written tempo.
#define GF_TS_MIN_RATIO 0.25f
#define GF_TS_MAX_RATIO 4.0f

/// Writes [in_path] to [out_path], [ratio] times as long, at the same pitch.
///
/// A ratio above 1 makes the file longer, which is what practising slowly
/// asks for: 2.0 is half speed. Below 1 makes it shorter. Both files are mono
/// 16-bit WAV, the format every take is already stored in.
///
/// Always render from the *original* recording. Rendering from an earlier
/// render compounds the vocoder's artefacts with every tempo nudge, and a few
/// adjustments are enough to hear it.
///
/// Returns [GF_TS_OK], or a negative [gf_ts_result]. On failure the output
/// file is removed rather than left as a partial recording that would play as
/// a truncated take.
int gf_ts_render_file(const char* in_path, const char* out_path, float ratio);

/// Frames [gf_ts_render_file] would write for an input of [in_frames].
///
/// Exact, so callers can scale a grid offset by the same amount the audio
/// moved instead of computing a ratio twice and rounding differently.
int64_t gf_ts_output_frames(int64_t in_frames, float ratio);

#ifdef __cplusplus
}
#endif

#endif  // GF_TIMESTRETCH_H
