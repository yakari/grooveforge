// gf_harmony.h — Multi-voice pitch-shifted harmony engine.
//
// The signal engine behind the Audio Harmonizer effect, factored out so the
// vocoder's harmonizer mode runs exactly the same code rather than a second
// take on the same idea. It owns a small set of phase vocoders, one per
// harmony voice, and everything needed to make them sound right in a
// real-time callback:
//
//   - **Latency banking.** A phase vocoder emits output in synthesis-frame
//     quanta, never in the audio device's block size. Draining "whatever is
//     ready" leaves a hole at the end of most blocks, and a hole at block
//     rate is a click. Each voice therefore runs a little behind the vocoder
//     and hands out whole blocks from the slack.
//
//   - **Headroom.** Harmony voices are pitch-shifted copies of one signal,
//     so their peaks line up and the sum approaches the arithmetic sum of the
//     mixes. Left alone that runs past full scale and the audio device
//     hard-clips it. The engine caps its own output at unity.
//
//   - **Voice lifecycle.** A voice that is switched off and back on restarts
//     from a clean vocoder, so it cannot replay a stale overlap-add tail.
//
// Each context is **mono**. Stereo callers create one per channel; a caller
// whose input is mono (a microphone, the Live Input passthrough) creates one
// and is done. That split is deliberate — it is what lets the harmonizer
// effect skip the right channel entirely when both channels are identical.
//
// Real-time safety: after gf_harmony_create, nothing on the hot path
// allocates, locks, or logs. Parameters may be set from any thread; they are
// read once per block.

#ifndef GF_HARMONY_H
#define GF_HARMONY_H

#ifdef __cplusplus
extern "C" {
#endif

/// Largest number of harmony voices a context can hold.
///
/// Four is a chord, and each voice is an independent phase vocoder — the
/// cost is linear, so this is the ceiling that keeps a full set inside an
/// Android audio callback.
#define GF_HARMONY_MAX_VOICES 4

/// Opaque handle. All state is owned by this struct.
typedef struct gf_harmony gf_harmony;

/// Creates an engine for up to [GF_HARMONY_MAX_VOICES] voices.
///
/// - [max_block] the largest number of frames a single
///   [gf_harmony_process] call will ever be given. Scratch buffers are
///   sized from it once; passing a value smaller than the audio device's
///   real block size is a buffer overrun.
///
/// Returns NULL on out-of-memory.
gf_harmony* gf_harmony_create(int max_block);

/// Destroys an engine and frees its vocoders. Safe to pass NULL.
void gf_harmony_destroy(gf_harmony* h);

/// Silences and flushes every voice. Use when the input stream restarts.
/// Allocation-free; safe from the audio thread.
void gf_harmony_reset(gf_harmony* h);

/// Sets voice [index]'s pitch offset and level.
///
/// - [semitones] offset from the input pitch, clamped to +/-24.
/// - [mix] 0 silences the voice — and skips its vocoder entirely, so an
///   unused voice costs nothing. Levels above 1 are allowed; the engine's
///   headroom stage keeps the sum inside full scale either way.
///
/// Safe to call between blocks from any thread.
void gf_harmony_set_voice(gf_harmony* h, int index, float semitones, float mix);

/// How many of the voices are considered at all, 1..[GF_HARMONY_MAX_VOICES].
/// Voices at or beyond [count] are skipped whatever their mix.
void gf_harmony_set_voice_count(gf_harmony* h, int count);

/// Renders [n] frames of harmony from [in] into [out].
///
/// [out] is *overwritten*, never accumulated into, and always receives
/// exactly [n] frames — silence while the voices are still filling their
/// banks. [in] and [out] may not overlap. The result is the summed voices
/// with the headroom stage applied; the caller owns any dry/wet mix.
///
/// Allocation-free and lock-free. [n] must not exceed the `max_block` the
/// context was created with.
void gf_harmony_process(gf_harmony* h, const float* in, float* out, int n);

#ifdef __cplusplus
}
#endif

#endif // GF_HARMONY_H
