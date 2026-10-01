// gf_aec — Offline removal of the phone's own speaker from a rehearsal take.
//
// The problem: when a take is recorded with the click and the other parts
// playing out of the phone's loudspeaker, the microphone hears them too, and
// they end up inside the recording. Android will not help here — its platform
// echo canceller only references the voice-communication output path, so an
// app playing music gets no cancellation at all (measured on a Fold 6: zero
// adaptation over a whole take, plus an AGC and a noise gate that make the
// take worse). What is left is to do it ourselves.
//
// What makes that tractable is that GrooveForge *generates* the sound coming
// out of the speaker, so it can keep a bit-exact copy of it. A studio tool
// doing the same job only ever gets a leaked acoustic copy of the backing
// track; here the reference is the actual signal, noise-free and sample-
// accurate. The job reduces to: find how the room turned that reference into
// what the microphone heard, and subtract it.
//
// ─── Why offline ────────────────────────────────────────────────────────────
//
// Nothing monitors through the phone while a take is recorded — the musician
// hears the click acoustically and plays along, and the take is time-aligned
// afterwards from the measured round trip. So no part of this has to happen
// inside an audio callback, and that buys three things a live canceller can
// never have:
//
//   - **No deadline.** The filter can be as long as the room needs.
//   - **Two passes.** An adaptive filter starts out knowing nothing and takes
//     seconds to converge — exactly when the count-in and the first bar
//     happen. Running the file once to learn the room and again to apply what
//     was learned means the opening is cancelled by a converged filter.
//   - **The delay is measured, not guessed.** Correlating the whole take
//     against the whole reference pins the bulk delay before any filtering
//     starts, so the adaptive part only has to model the room's tail.
//
// ─── What it does and does not remove ───────────────────────────────────────
//
// This is a *linear* canceller: it models the path from speaker to microphone
// as a filter and subtracts the result. It deliberately has no residual
// suppressor, no noise gate and no gain control — those are what make voice
// echo cancellers pump and smear, and they would wreck a recording of an
// instrument. The musician's own sound passes through untouched apart from
// the subtraction.
//
// The limit is what a linear filter cannot describe: a phone speaker driven
// hard distorts, and that distortion is not predictable from the reference.
// Expect the speaker bleed to drop a long way, not to vanish, and expect
// better results at moderate speaker volume than at maximum.

#ifndef GF_AEC_H
#define GF_AEC_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Result of a render. Negative values are failures.
typedef enum {
    GF_AEC_OK = 0,
    GF_AEC_ERR_OPEN_MIC = -1,   ///< missing, unreadable, or not mono 16-bit
    GF_AEC_ERR_OPEN_REF = -2,
    GF_AEC_ERR_OPEN_OUTPUT = -3,
    GF_AEC_ERR_MEMORY = -4,
    GF_AEC_ERR_WRITE = -5,
    GF_AEC_ERR_RATE_MISMATCH = -6,  ///< the two inputs disagree on sample rate
} gf_aec_result;

/// Samples per processing block. The transform runs at twice this.
///
/// 256 is a compromise: longer blocks mean fewer, larger transforms and less
/// work overall, but the filter then adapts in coarser steps and tracks a
/// drifting clock less well.
#define GF_AEC_BLOCK 256

/// How many blocks of room the filter covers, i.e. its length in blocks.
///
/// 48 blocks at 256 samples is 12288 samples, about 256 ms at 48 kHz. Longer
/// than the reverberation of any room a band rehearses in, with slack for the
/// bulk delay being slightly off and for drift between the capture and
/// playback clocks over a long take.
///
/// Swept against a real take: 96 and 192 partitions were no better, and past
/// that worse, because the extra taps only have adaptation noise to fit. What
/// limits this is not the filter's length.
#define GF_AEC_PARTITIONS 48

/// Largest bulk delay the estimator will look for, in seconds.
///
/// The real figure is a round trip through the output stream, the air and the
/// input stream: tens of milliseconds normally, and a couple of hundred on a
/// device that has dropped to a slow audio path.
///
/// Searching wider than that does not make the answer safer, it makes it
/// worse — every extra lag considered is another chance for two unrelated
/// periodic signals to line up by accident, and a false match half a second
/// out is not a delay any phone could produce. Half a second leaves generous
/// headroom over the worst real case while excluding the obviously impossible.
#define GF_AEC_MAX_DELAY_SEC 0.5f

// ─── Streaming core ─────────────────────────────────────────────────────────
//
// Exposed separately from the file driver so the same filter can be measured
// directly by the smoke test, and so a future live path could reuse it.

/// One canceller, holding the adaptive filter and its history.
typedef struct gf_aec_context gf_aec_context;

/// Creates a canceller for [sample_rate], covering [partitions] blocks of room.
///
/// Pass GF_AEC_PARTITIONS unless you are measuring the effect of the length.
/// Returns NULL if allocation fails.
gf_aec_context* gf_aec_create(int sample_rate, int partitions);

/// Releases a canceller. Safe on NULL.
void gf_aec_destroy(gf_aec_context* ctx);

/// Clears the filter and its history, as if freshly created.
void gf_aec_reset(gf_aec_context* ctx);

/// Clears the signal history but keeps the filter it has learned.
///
/// This is what makes the second pass worth running: the file restarts from
/// its first sample, but the room the filter describes is still the same room.
void gf_aec_rewind_keep_filter(gf_aec_context* ctx);

/// Sets how fast the filter follows the room, in [0, 1].
///
/// Around 0.3 learns an unknown room at a sensible rate. Much lower only
/// holds onto a room already learned while following the slow drift between
/// the capture and playback clocks — which is what the second pass wants,
/// since a large step there would let a loud passage of the actual
/// performance drag the filter off the room it is supposed to describe.
void gf_aec_set_step(gf_aec_context* ctx, float mu);

/// Cancels one block of exactly GF_AEC_BLOCK frames.
///
/// [mic] is what the microphone heard and [ref] the matching block of the
/// signal that was sent to the speaker — already shifted by the bulk delay, so
/// that ref[i] is what was playing when mic[i] was captured. [out] receives
/// the result and may alias [mic].
///
/// [adapt] nonzero lets the filter learn from this block. Pass zero to apply
/// the filter without changing it.
void gf_aec_process_block(gf_aec_context* ctx, const float* mic,
                          const float* ref, float* out, int adapt);

/// Echo-to-residual ratio over everything processed since the last reset, in dB.
///
/// Positive means the output holds less energy than the input did — i.e. how
/// much was removed. Reported by the file driver and used by the smoke test
/// as its pass criterion.
float gf_aec_reduction_db(const gf_aec_context* ctx);

// ─── Delay estimation ───────────────────────────────────────────────────────

/// Finds how many frames [mic] lags [ref], by generalised cross-correlation.
///
/// Uses the phase transform (GCC-PHAT): the cross-spectrum is divided by its
/// own magnitude before coming back to the time domain, which throws away how
/// loud each frequency is and keeps only how well the two line up. That makes
/// the peak sharp and largely immune to the speaker and room colouring the
/// sound on the way, where a plain correlation would smear across a broad,
/// ambiguous maximum.
///
/// [n] is how many frames of each to use; more is more reliable, and the
/// function internally caps the transform it needs.
///
/// Returns the lag in frames, never more than GF_AEC_MAX_DELAY_SEC at
/// [sample_rate], or **-1 when the two signals are not related at all** — a
/// take recorded on headphones, or one where the reference never made it to
/// disk. That is a distinct answer from a lag of zero, and callers must treat
/// it as "there is nothing here to cancel" rather than as "aligned already":
/// running an adaptive filter against an unrelated reference does not sit
/// still, it slowly learns to subtract part of the performance.
int gf_aec_estimate_delay(const float* mic, const float* ref, int n,
                          int sample_rate);

// ─── File driver ────────────────────────────────────────────────────────────

/// Removes [ref_path] out of [mic_path] and writes the result to [out_path].
///
/// All three are mono 16-bit WAV at the same sample rate: [mic_path] is the
/// take as recorded, [ref_path] the copy of what the speaker was playing,
/// captured alongside it. The output is the same length as the take.
///
/// Runs the two passes described at the top of this file: one to learn the
/// room, one to apply what was learned from the first sample. The take itself
/// is never modified — callers keep it and write the cleaned version beside
/// it, so the result can be compared and discarded.
///
/// [expected_delay] is the round trip this device is already known to have, in
/// frames, or negative when nothing is known. **Pass it whenever it is
/// available.** The engine measures exactly this figure for every output route
/// in order to align takes, and it is the same number the canceller needs —
/// the reference drops the same compensation off its front as the take, which
/// leaves the lag between them equal to the plain acoustic round trip.
///
/// Supplying it is what makes the canceller work on a take someone played on.
/// Measuring the delay from the audio alone needs the bleed to stand clear of
/// everything else, and a player only 3 dB above it is enough to hide it — so
/// a take with anyone actually performing would otherwise be refused, which is
/// every take that matters. Given the figure, the correlation is only used to
/// confirm and refine it.
///
/// When [reduction_db] is non-NULL it receives how much energy was removed.
/// Zero means the take was passed through untouched, either because no bleed
/// was found or because cancelling it did not measurably help.
///
/// Returns [GF_AEC_OK], or a negative [gf_aec_result]. On failure the output
/// file is removed rather than left as a partial take.
int gf_aec_render_file(const char* mic_path, const char* ref_path,
                       const char* out_path, int expected_delay,
                       float* reduction_db);

#ifdef __cplusplus
}
#endif

#endif  // GF_AEC_H
