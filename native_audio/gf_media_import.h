// gf_media_import.h — Turns a music file into a take the rehearsal engine can
// stream.
//
// Why this exists
// --------------
// School groups take on famous tunes, so a rehearsal has to be able to start
// from an existing recording rather than a blank grid (REHEARSALS.md §7). That
// recording arrives as whatever the phone happens to hold — an MP3, a FLAC rip,
// an M4A from a music library, sometimes the audio of a screencast — and the
// engine streams exactly one thing: mono 16-bit WAV at the engine's sample
// rate. This converts the first into the second.
//
// What it can decode by itself
// ---------------------------
// miniaudio is already vendored for audio I/O and carries the dr_libs
// decoders, so WAV, FLAC and MP3 cost nothing to support on all five
// platforms — no new dependency, no bundled binary, nothing for F-Droid to
// object to. Resampling and stereo-to-mono folding come with it.
//
// Everything beyond that (AAC/M4A, and the audio track of a video container)
// needs a decoder we deliberately do not bundle: `ffmpeg_kit_flutter` was
// archived in 2025 and ships prebuilt binaries, which F-Droid will not take.
// Those formats go through the platform's own extractor instead — MediaCodec
// on Android, AVAssetReader on Apple — which is a system API and bundles
// nothing. [gf_media_can_decode] is how the Dart side finds out which path a
// given file needs.

#ifndef GF_MEDIA_IMPORT_H
#define GF_MEDIA_IMPORT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Whether miniaudio can decode [path] without help from the platform.
///
/// Returns 1 for the formats handled here, 0 for anything that needs the OS
/// extractor. Opens the file and reads its header rather than guessing from
/// the extension, because a `.m4a` that is really an MP3 is not rare and the
/// extension is the least reliable thing about a file someone downloaded.
int gf_media_can_decode(const char* path);

/// Decodes [src] into [dst] as mono 16-bit WAV at [sample_rate].
///
/// Mono because the master is played back against one player and one
/// microphone, and because halving it halves what has to be streamed and
/// eventually transferred. 16-bit for the same reason takes are: a phone
/// cannot hold a four-minute master as float alongside six parts.
///
/// Returns the number of frames written, or a negative value on failure
/// (-1 bad arguments, -2 cannot decode the source, -3 cannot write the
/// destination).
int64_t gf_media_to_mono_wav(const char* src, const char* dst, int sample_rate);

/// Fills [out] with [bins] peak values covering the whole of a mono 16-bit
/// WAV, for drawing a waveform.
///
/// Peak rather than RMS: the alignment screen exists so a player can find the
/// first downbeat by eye, and a transient is what marks it. RMS smooths
/// exactly the thing being looked for.
///
/// Returns 1 on success, 0 if the file cannot be read.
int gf_media_waveform(const char* wav_path, float* out, int bins);

#ifdef __cplusplus
}
#endif

#endif // GF_MEDIA_IMPORT_H
