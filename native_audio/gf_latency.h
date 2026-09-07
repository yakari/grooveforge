// gf_latency.h — Round-trip latency measurement and overdub alignment.
//
// The problem this solves
// ----------------------
// When a musician overdubs, they play along to what they HEAR. What they hear
// left the engine some milliseconds ago (output latency), and what they play
// reaches the engine some milliseconds after they played it (input latency).
// So the audio we capture is late relative to the grid it must line up with,
// by the sum of the two — the "round trip". Unless we shift the captured take
// earlier by exactly that amount, every overdub drags behind the beat.
//
// Why a measurement rather than the OS numbers
// -------------------------------------------
// GrooveForge runs a *separate* playback device and capture device (see
// `start_audio_capture` in audio_input.c). Two devices means two independent
// sample clocks that were started at two different moments, so the true
// offset between "playback frame P" and "capture frame C" contains a term the
// OS cannot report: the gap between the two device starts. Adding
// `outputLatency + inputLatency` from the OS therefore answers a *different*
// question than the one we need.
//
// What we actually need is the end-to-end answer: emit a known signal at
// playback frame P, find it in the capture stream at frame C, and compensate
// by (C - P). That single number folds in output latency, the flight time from
// speaker to microphone, and input latency. This file measures it.
//
// One term is deliberately NOT in it. The two counters also differ by the gap
// between the devices' start times, which is not latency at all. A caller
// removes that by reading both counters at one instant and passing the
// difference as `cap_start_frame`, so what comes back is the round trip alone.
// That split matters because the two behave differently: the start skew is
// free to re-read and changes on every device restart, while the round trip is
// a property of the route and costs a measurement to obtain. The rate
// difference between the clocks does survive, and is reported as `drift_ppm`.
//
// The measurement signal
// ---------------------
// A short linear chirp (a "sweep" — a sine rising quickly through the
// spectrum) rather than a click. A chirp spreads its energy over time but
// still correlates to a single sharp peak, which makes it far more robust
// than a click against room reverberation, phone-speaker resonances and
// background noise. Several chirps are emitted in a row so we can take the
// median and, just as usefully, see the spread: a large spread means the
// device clock is unstable and no single number will hold.
//
// Real-time safety
// ---------------
// `gf_lat_emitter_render` is the only function meant for the audio thread. It
// allocates nothing, locks nothing and takes no branches on unbounded data.
// Everything else — chirp generation, correlation, alignment — is offline
// work for a worker thread.

#ifndef GF_LATENCY_H
#define GF_LATENCY_H

#ifdef __cplusplus
extern "C" {
#endif

// ─── Measurement signal ──────────────────────────────────────────────────────

/// Duration of one chirp in milliseconds. Long enough to carry energy across
/// the band a phone speaker can actually reproduce, short enough that several
/// fit inside a couple of seconds of measurement.
#define GF_LAT_CHIRP_MS 40

/// Lowest and highest frequency of the sweep, in Hz. The low end stays well
/// clear of the ~150 Hz below which phone speakers produce nothing, and the
/// high end stops short of Nyquist so resampling en route cannot fold it.
#define GF_LAT_CHIRP_F0 300.0f
#define GF_LAT_CHIRP_F1 6000.0f

/// Number of chirps in one measurement run, and the gap between their starts.
/// The gap must exceed the largest round trip we expect to measure (Bluetooth
/// can reach ~300 ms) plus the chirp itself, or consecutive chirps would
/// overlap in the capture and confuse the correlator.
#define GF_LAT_SHOTS 6
#define GF_LAT_SHOT_PERIOD_MS 600

/// Largest round trip the correlator will search for, in milliseconds.
/// Anything beyond this is reported as a failed measurement rather than
/// silently wrapping onto a wrong peak.
#define GF_LAT_MAX_ROUND_TRIP_MS 500

/// Length of one chirp in frames at [sample_rate].
int gf_lat_chirp_frames(int sample_rate);

/// Total frames one full measurement run occupies on the playback timeline.
int gf_lat_run_frames(int sample_rate);

/// Writes one chirp into [out], which must hold at least
/// `gf_lat_chirp_frames(sample_rate)` floats.
///
/// The sweep is amplitude-windowed at both ends (a raised-cosine fade over
/// 20% of its length) so it starts and stops without a click of its own —
/// an abrupt edge would itself correlate, competing with the sweep.
void gf_lat_generate_chirp(float* out, int sample_rate);

// ─── Audio-thread emitter ────────────────────────────────────────────────────

/// Emits the chirp train on the playback timeline.
///
/// The caller owns the chirp buffer; the emitter only reads it. `frame` is the
/// playback device's absolute frame counter, which is also the timeline the
/// grid lives on — so the position of every chirp is known exactly rather than
/// having to be detected in the output.
typedef struct {
    const float* chirp;      ///< Pre-rendered chirp, `chirp_frames` long.
    int chirp_frames;
    int shot_period_frames;  ///< Distance between consecutive chirp starts.
    int shots;               ///< How many chirps this run emits.
    float amplitude;         ///< Peak level, 0..1. 0.5 is loud enough to
                             ///< measure and quiet enough not to alarm anyone.
} gf_lat_emitter;

/// Initialises an emitter for [sample_rate]. [chirp] must stay alive for as
/// long as the emitter is used.
void gf_lat_emitter_init(gf_lat_emitter* em, const float* chirp, int sample_rate);

/// Mixes the chirp train into [out] for the block beginning at absolute
/// playback frame [start_frame].
///
/// Audio-thread safe: no allocation, no locks, no I/O. Adds to [out] rather
/// than overwriting it, so the metronome can play underneath.
///
/// Returns 1 while the run is still in progress, 0 once every chirp has been
/// emitted.
int gf_lat_emitter_render(const gf_lat_emitter* em, float* out, int frames,
                          long long start_frame);

/// Playback frame at which chirp [shot_index] begins.
long long gf_lat_shot_frame(const gf_lat_emitter* em, int shot_index);

// ─── Delay estimation ────────────────────────────────────────────────────────

/// One chirp's worth of result.
typedef struct {
    int   delay_frames;      ///< Integer lag of the correlation peak. This is
                             ///< what compensation uses: a take can only be
                             ///< shifted by whole samples without resampling
                             ///< it, and one frame is 0.02 ms — nothing next
                             ///< to a 10 ms budget.
    float delay_frames_frac;  ///< Same lag refined to sub-frame precision.
                             ///< Diagnostic only; it makes the drift estimate
                             ///< meaningful and shows up in the probe's log.
    float peak;              ///< Normalised correlation at the peak, 0..1.
    float confidence;        ///< Peak height over the largest competing peak
                             ///< outside a guard band. Above ~2.5 the answer
                             ///< is trustworthy; near 1.0 the correlator found
                             ///< nothing it could distinguish from noise.
} gf_lat_shot;

/// Finds [ref] inside [cap] by normalised cross-correlation.
///
/// Searches lags in `[search_start, search_start + search_frames)`. The
/// correlation is normalised by the energy of the capture window at each lag,
/// so a loud burst elsewhere in the recording cannot outscore a quieter but
/// genuinely matching one — without that division, the estimator reliably
/// locks onto whatever was loudest rather than onto the chirp.
///
/// Returns 1 on success, 0 if the inputs are too short to search.
int gf_lat_estimate_delay(const float* ref, int ref_frames,
                          const float* cap, int cap_frames,
                          int search_start, int search_frames,
                          gf_lat_shot* out);

/// Aggregate of a whole measurement run.
typedef struct {
    int   shots_found;       ///< Chirps located with usable confidence.
    int   median_frames;     ///< The compensation to apply.
    float median_ms;
    int   min_frames, max_frames;
    float jitter_ms;         ///< Spread across shots. Large spread means the
                             ///< device clock wanders and no single
                             ///< compensation will hold.
    float min_confidence;

    /// How fast the measured delay *grows* over the run, in parts per million
    /// of elapsed playback time, from a straight-line fit across the shots.
    ///
    /// Defined by the observable rather than by "which clock is faster",
    /// because that phrasing has two defensible readings and the sign is the
    /// one thing a caller must not get wrong. Positive means the round trip
    /// measured later in the run is longer than the one measured earlier: the
    /// capture is falling progressively behind, so a take drags more and more
    /// as it goes and must be sped up to correct it. Negative is the reverse.
    ///
    /// This matters far more than it first appears. The compensation above is
    /// a single constant, which corrects the *start* of a take. But if the two
    /// devices run at even slightly different rates, the take slides against
    /// the grid as it plays: at 200 ppm a four-minute take ends 48 ms late,
    /// which is audible and cannot be fixed by any constant offset. Measuring
    /// it here is how we find out whether a take needs resampling as well as
    /// shifting.
    float drift_ppm;
    /// Frames a take slides per minute at this drift. Reported alongside the
    /// ppm figure because "48 ms by the end of the song" lands where
    /// "200 ppm" does not.
    float drift_frames_per_minute;
} gf_lat_result;

/// Correlates every chirp of a run and reduces them to one compensation.
///
/// [cap] is the capture stream indexed by the capture device's absolute frame
/// counter, starting at capture frame [cap_start_frame]. Each chirp is
/// searched only in the window where it could plausibly land, which keeps the
/// correlation cheap and stops one chirp being mistaken for its neighbour.
///
/// The median is used rather than the mean because a single mis-locked shot
/// (someone knocks the table, a notification chimes) would drag a mean off by
/// tens of milliseconds while leaving a median untouched.
///
/// Returns 1 if enough shots were found to trust the result, 0 otherwise.
int gf_lat_analyse_run(const gf_lat_emitter* em,
                       const float* cap, int cap_frames,
                       long long cap_start_frame,
                       int sample_rate,
                       gf_lat_result* out);

// ─── Applying the compensation ───────────────────────────────────────────────

/// Shifts a captured take earlier by [comp_frames] so it lands on the grid.
///
/// The first [comp_frames] of the capture are what the player recorded *before*
/// the grid position they were aiming at — a musician reacting to a count-in —
/// and are discarded. The tail is zero-padded so the take keeps the length the
/// grid expects.
///
/// [in] and [out] may not overlap. Returns the number of frames written, or 0
/// if the compensation exceeds the take itself.
int gf_lat_align_take(const float* in, int in_frames, int comp_frames,
                      float* out, int out_capacity);

/// Converts a round trip in milliseconds to the frame compensation to apply.
int gf_lat_ms_to_frames(float ms, int sample_rate);

#ifdef __cplusplus
}
#endif

#endif // GF_LATENCY_H
