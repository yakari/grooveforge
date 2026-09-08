// gf_rehearsal.h — Multitrack rehearsal engine: grid, streaming playback,
// aligned recording and a metronome.
//
// What this is for
// ---------------
// A band rehearses one tune. Each member records their own part at home,
// playing along to whatever parts already exist, and the parts have to line up
// on a shared bar grid when they are played back together. This engine owns
// that: it keeps the grid, streams every existing take from disk, clicks a
// metronome, and captures one new take aligned to the grid.
//
// Why the takes live on disk
// -------------------------
// The rack's audio looper pre-allocates its clips in RAM as stereo float,
// which is right for a few bars of loop and impossible for a band: five
// minutes of stereo float is about 115 MB per clip, so six members would need
// 690 MB. Rehearsal takes are mono 16-bit on disk and streamed a block at a
// time, which makes a six-piece band cost a few megabytes of RAM instead of
// most of the phone.
//
// The position model
// -----------------
// Position is a *signed* frame count on the grid. Frame 0 is the downbeat of
// bar 1, the point every take is aligned to. Negative positions are the
// count-in: the metronome clicks, nothing plays and nothing is committed to a
// take, and the transport crosses zero exactly on the downbeat the player is
// waiting for. One signed number therefore expresses "two bars of count-in,
// then the song" without a second state machine.
//
// Latency compensation
// -------------------
// What a player performs is captured late by the round trip measured in
// gf_latency.h — they play along to what they *hear*, which the engine emitted
// milliseconds earlier. So a take is shifted earlier by that many frames as it
// is written: the first `compensation` frames of captured audio are dropped,
// and what lands at frame 0 of the take file is what the player played on the
// downbeat.
//
// Threading
// --------
// - `gf_reh_render` and `gf_reh_feed_input` run on the audio threads. They
//   only read and write pre-allocated ring buffers: no allocation, no locks,
//   no file I/O.
// - A worker thread does every read and write to disk, filling playback rings
//   ahead of the playhead and draining the record ring to file.
// - Everything else is called from the UI thread.

#ifndef GF_REHEARSAL_H
#define GF_REHEARSAL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Maximum simultaneous tracks. Six members plus a master track, plus room to
/// spare; the cost of a slot is its ring buffer, so this is not free.
#define GF_REH_MAX_TRACKS 12

/// Frames of audio held ahead of the playhead per track (~0.68 s at 48 kHz).
/// Long enough to ride out a scheduler hiccup or a slow read, short enough
/// that twelve of them stay under 2 MB.
#define GF_REH_RING_FRAMES 32768

/// Transport states. Mirrors the Dart enum in rehearsal_engine.dart.
/// Named `..._transport_state` rather than `gf_reh_state` so it does not
/// collide with the getter of that name below.
typedef enum {
    GF_REH_STOPPED = 0,
    GF_REH_PLAYING = 1,
    /// Counting in: the metronome clicks, nothing plays, nothing is recorded.
    /// Entered only when recording was armed with a count-in.
    GF_REH_COUNT_IN = 2,
    GF_REH_RECORDING = 3,
} gf_reh_transport_state;

// ─── Lifecycle ───────────────────────────────────────────────────────────────

/// Creates the engine. Returns 0 on success. Only one instance exists; calling
/// twice without a destroy is a no-op that returns 0.
int gf_reh_create(int sample_rate);

/// Stops everything, joins the worker thread and releases every buffer.
void gf_reh_destroy(void);

// ─── Grid ────────────────────────────────────────────────────────────────────

/// Sets the bar grid. Safe to call while stopped; ignored while running,
/// because moving the grid under a take that is already aligned to it would
/// silently put every existing part in the wrong place.
void gf_reh_set_grid(double bpm, int beats_per_bar, int beat_unit);

/// Frames per beat and per bar at the current tempo.
int gf_reh_frames_per_beat(void);
int gf_reh_frames_per_bar(void);

// ─── Tracks ──────────────────────────────────────────────────────────────────

/// Loads a take from [wav_path] into a free slot and returns its index, or a
/// negative value on failure (-1 no free slot, -2 cannot open, -3 not a mono
/// 16-bit WAV this engine can stream).
///
/// The file is not read into memory; only its header is parsed and its length
/// recorded. Audio arrives block by block from the worker thread.
int gf_reh_add_track(const char* wav_path);

/// Releases a track slot. Safe while playing.
void gf_reh_remove_track(int idx);

/// Removes every track.
void gf_reh_clear_tracks(void);

/// Linear gain, 0..2. Applied on the audio thread without smoothing, so change
/// it from a slider rather than per sample.
void gf_reh_set_track_gain(int idx, float gain);

/// Local mute. A muted track still streams, so unmuting is instant and does
/// not have to wait for the ring to refill.
void gf_reh_set_track_mute(int idx, int muted);

/// Sets which file frame corresponds to grid frame 0.
///
/// Takes are aligned to the grid by construction and leave this at zero. An
/// imported master is not: the recording has an intro, a count-in, or simply
/// silence before the first downbeat, and the grid has to be anchored to that
/// downbeat rather than to the start of the file. An offset of 57600 frames
/// means the tune's first downbeat sits 1.2 s into the recording at 48 kHz.
///
/// Audio before the offset is not played, because there is no grid there to
/// play it against.
void gf_reh_set_track_offset(int idx, int64_t frames);

/// Length of a track in frames, or 0 if the slot is empty.
int64_t gf_reh_track_frames(int idx);

/// Peak level of a track since the last call, for a meter. Resets on read.
float gf_reh_track_peak(int idx);

// ─── Metronome ───────────────────────────────────────────────────────────────

/// Enables the click and sets its level (0..1).
void gf_reh_set_metronome(int enabled, float gain);

// ─── Transport ───────────────────────────────────────────────────────────────

/// Starts playback from [start_frame] on the grid (may be negative for a
/// count-in). Returns 0 on success.
///
/// Playback stops on its own once every track has run out — see
/// [gf_reh_content_end]. Recording does not: a player laying down a part
/// longer than anything already there is the normal way a rehearsal grows.
int gf_reh_play(int64_t start_frame);

/// Arms recording into [wav_path], compensating by [compensation_frames]
/// (from gf_latency), after [count_in_bars] bars of metronome.
///
/// Playback of existing tracks starts at the same moment, so the player hears
/// the band while laying their part down. Returns 0 on success.
int gf_reh_record(const char* wav_path, int compensation_frames,
                  int count_in_bars);

/// Stops the transport and finalises a take in progress. Blocks briefly while
/// the worker flushes the last of the recording to disk — call it off the
/// audio thread.
void gf_reh_stop(void);

/// Frames from the start of the take just recorded to the tune's downbeat.
///
/// Capture begins with the count-in, so a player following a recording's intro
/// is recorded from where they actually came in rather than from bar one. This
/// is what the take's own offset should be set to, and it is zero when the
/// tune has no count-in.
int64_t gf_reh_take_offset(void);

/// Sets a floor for where the tune ends, in grid frames.
///
/// The written form is a length even when nothing has been recorded against
/// it: a band that types out thirty-two bars and presses play expects to hear
/// the click run through them, not stop immediately because no track is
/// loaded. Zero removes the floor.
void gf_reh_set_min_end(int64_t frames);

/// Grid frame at which the tune ends, or 0 if it has no length yet.
///
/// The later of where the last track runs out and the floor set by
/// [gf_reh_set_min_end]. Accounts for each track's offset, so a master
/// anchored partway into a recording ends where its audio does rather than
/// where the file does.
int64_t gf_reh_content_end(void);

/// Current position in frames on the grid; negative during a count-in.
int64_t gf_reh_position(void);

/// Current transport state.
int gf_reh_state(void);

/// Peak level of the input since the last call, for the record meter.
float gf_reh_input_peak(void);

/// Frames captured into the take so far, which is what the UI should show as
/// the take's length while recording.
int64_t gf_reh_recorded_frames(void);

// ─── Audio-thread entry points ───────────────────────────────────────────────

/// Mixes every unmuted track plus the metronome into [outL]/[outR] and
/// advances the transport. Writes, never accumulates. Audio-thread safe.
void gf_reh_render(float* outL, float* outR, int frames);

/// Hands the engine a block of microphone input. Audio-thread safe: the frames
/// are copied into a ring and written to disk by the worker.
void gf_reh_feed_input(const float* in, int frames);

// ─── Offline rendering ───────────────────────────────────────────────────────

/// Same as [gf_reh_render], but reads from disk inline instead of relying on
/// the worker thread to have filled the rings ahead of time.
///
/// Rendering offline runs far faster than real time, so the worker can never
/// keep up and the rings would starve. This exists for the smoke test and for
/// the eventual bounce-to-file; it must never be called from an audio thread,
/// because it does file I/O.
void gf_reh_render_offline(float* outL, float* outR, int frames);

#ifdef __cplusplus
}
#endif

#endif // GF_REHEARSAL_H
