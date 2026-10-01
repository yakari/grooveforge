// gf_wav.h — Mono 16-bit WAV reading and writing for the offline renderers.
//
// Every rehearsal take, every decoded master and every reference capture is
// stored as mono 16-bit PCM, so that is the only format this handles. A
// general reader would be dead weight: nothing in the app ever asks for one.
//
// Reading is streaming rather than whole-file, and the reader can rewind.
// Both matter for the echo canceller, which walks a take twice — once to
// adapt its filter and once to apply it — and must not hold a five-minute
// recording in memory as floats to do it.
//
// This lived inside gf_timestretch.c until the echo canceller needed the same
// four functions. Nothing about it is specific to either.

#ifndef GF_WAV_H
#define GF_WAV_H

#include <stdint.h>
#include <stdio.h>

#ifdef __cplusplus
extern "C" {
#endif

/// An open mono 16-bit WAV, positioned somewhere in its sample data.
typedef struct {
    FILE*   file;         ///< NULL when the open failed.
    int64_t frames;       ///< Total frames in the data chunk.
    int     sample_rate;  ///< As declared in the fmt chunk.
    long    data_offset;  ///< Byte offset of the first sample, for rewinding.
} gf_wav_reader;

/// Opens [path] and positions the reader at its first sample.
///
/// Rejects anything that is not mono 16-bit PCM, because a stereo or float
/// file read as mono would decode to noise rather than fail.
///
/// Returns a reader whose `file` is NULL on failure. A failed reader is safe
/// to pass to [gf_wav_close].
gf_wav_reader gf_wav_open_read(const char* path);

/// Reads up to [count] frames into [dst] as floats in [-1, 1].
///
/// Returns the number of frames actually read, which is short at end of file.
int gf_wav_read(gf_wav_reader* r, float* dst, int count);

/// Returns the reader to the first sample, for a second pass over the file.
void gf_wav_rewind(gf_wav_reader* r);

/// Positions the reader at [frame], for sampling a long file in places.
///
/// Clamped to the file: a frame past the end leaves the reader at the end,
/// where the next read returns nothing rather than garbage.
void gf_wav_seek(gf_wav_reader* r, int64_t frame);

/// Closes the file and clears the reader. Safe on a failed open.
void gf_wav_close(gf_wav_reader* r);

/// Creates [path] and writes a mono 16-bit header with placeholder sizes.
///
/// The sizes are not known until writing finishes, so [gf_wav_finish] must be
/// called to patch them before the file is closed; a file left unpatched
/// reports zero length and plays as silence.
///
/// Returns NULL on failure.
FILE* gf_wav_open_write(const char* path, int sample_rate);

/// Appends [count] floats as mono 16-bit, clipping rather than wrapping.
///
/// Clipping is deliberate: a DSP tail can overshoot slightly even when the
/// input never did, and a wrapped sample is a loud click in the middle of
/// someone's take.
///
/// Returns nonzero on success.
int gf_wav_write(FILE* f, const float* samples, int count);

/// Patches the RIFF and data sizes for a file holding [frames] frames.
///
/// Leaves the file open; the caller still closes it.
void gf_wav_finish(FILE* f, int64_t frames);

#ifdef __cplusplus
}
#endif

#endif  // GF_WAV_H
