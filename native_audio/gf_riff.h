// gf_riff.h — Riff: a physically modelled electric guitar.
//
// Instead of playing back recordings, Riff simulates the six strings of an
// electric guitar. Each string is a loop: a delay line as long as one period
// of the note, through filters that take away a little energy on every trip,
// the way a real string loses energy to the air and the bridge. A short burst
// of noise — the "pick" — is injected into the loop, and the loop rings at
// the note's pitch and dies away like a string. This is the extended
// Karplus-Strong / digital waveguide family (Karplus and Strong 1983; Jaffe
// and Smith, "Extensions of the Karplus-Strong Plucked-String Algorithm",
// CMJ 1983; Karjalainen, Välimäki and Tolonen, "Plucked-String Models: From
// the Karplus-Strong Algorithm to Digital Waveguides and Beyond", CMJ 1998),
// reimplemented from the papers.
//
// What each part does, in plain terms:
//
//   - **Pick.** The burst is darker for a finger or a soft note, brighter for
//     a hard pick. Where the string is picked matters: a pick near the bridge
//     sounds thin and snappy, over the neck round and warm. That is a comb
//     filter on the burst, because picking at a point cancels the harmonics
//     that have a node there.
//   - **Loss filter.** Low harmonics ring for many seconds, high ones die in
//     a fraction of a second. A one-pole low-pass in the loop, solved per
//     note so the fundamental and the 4 kHz region die in the set times.
//   - **Tuning.** The delay is read between samples (third-order Lagrange
//     interpolation), with the filters' own delay subtracted, so every note
//     is in tune and bends and vibrato glide without clicks.
//   - **Stiffness.** Wound strings are slightly stiff, so their upper
//     harmonics run a little sharp; two all-pass filters give them that.
//   - **Two planes of vibration.** A real string swings in two directions at
//     very slightly different pitches and fades differently in each; the two
//     beat slowly against each other. That slow movement is much of what
//     makes a real string sound alive, so each string runs two loops.
//   - **Pitch glide.** A hard pick stretches the string and raises its pitch
//     for a moment (tension modulation, Tolonen, Välimäki and Karjalainen,
//     IEEE TSAP 2000), modelled cheaply from the string's energy.
//   - **Pickups.** A magnetic pickup hears the string at one point, which
//     again cancels the harmonics with a node there: the neck pickup sounds
//     round, the bridge one thin and biting. A humbucker hears two points
//     side by side. The coil and the cable then make a resonant low-pass
//     around 2-5 kHz, which gives each pickup its voice (Paiva, Pakarinen and
//     Välimäki, "Acoustics and Modeling of Pickups", JAES 2012).
//
// Playing it like a guitar. A note is given to one of the six strings, in
// standard tuning, that can play it (the low string also takes everything
// below it, the high string everything above its 24th fret, so a keyboard's
// whole range plays at pitch); two notes cannot share a string, so a
// new note on a ringing string replaces it, as on a guitar. Picking a string
// that still rings first damps it for a few milliseconds, as the pick does,
// instead of wiping it, which would click. Releasing a key lifts the finger:
// the string is damped. Palm mute, the pick position, the pickups and the
// tone act on the strings that are ringing, so a pedal or a ribbon can play
// them.
//
// Real-time safety: after gf_riff_create nothing on the hot path allocates,
// locks or logs. Every function here runs on the audio thread except create
// and destroy; the host queues events from other threads.

#ifndef GF_RIFF_H
#define GF_RIFF_H

#ifdef __cplusplus
extern "C" {
#endif

/// Number of strings.
#define GF_RIFF_STRINGS 6

/// Highest fret a note can be played at, except on the high E string.
#define GF_RIFF_FRETS 24

/// Playable range, MIDI: a piano's, A0 to C8. Below the low E the low string
/// plays as if tuned down; past the 24th fret the high string keeps climbing.
#define GF_RIFF_NOTE_MIN 21
#define GF_RIFF_NOTE_MAX 108

/// Which pickup the guitar listens through, in the order the panel lists them.
typedef enum {
    GF_RIFF_PICKUP_NECK = 0,     ///< Round, warm: the "blues" pickup.
    GF_RIFF_PICKUP_MIDDLE,
    GF_RIFF_PICKUP_BRIDGE,       ///< Thin and biting: the "rock lead" pickup.
    GF_RIFF_PICKUP_NECK_BRIDGE,  ///< Both together.
    GF_RIFF_PICKUP_COUNT
} gf_riff_pickup;

/// What the player sets. Everything acts on strings that are already ringing.
typedef struct {
    float palm_mute;   ///< 0 = strings ring freely, 1 = fully muted by the palm.
    float pick_pos;    ///< 0 = picked at the bridge, 1 = over the neck.
    int   pickup;      ///< gf_riff_pickup.
    int   humbucker;   ///< 0 = single-coil pickups, 1 = humbuckers.
    float tone;        ///< The guitar's tone knob: 0 = dark, 1 = bright.
    float sustain;     ///< 0 = short (about 2 s on the low E), 1 = long (20 s).
    float attack;      ///< 0 = soft finger, 1 = hard pick.
    float bend_range;  ///< Semitones a full pitch-bend reaches (1-12).
    float level_db;    ///< Output level, dB.
} gf_riff_params;

typedef struct gf_riff gf_riff;

/// Creates a guitar for [sample_rate] Hz (8-192 kHz). Returns NULL on a bad
/// rate or when memory runs out. Allocates about 800 KB.
gf_riff* gf_riff_create(float sample_rate);

void gf_riff_destroy(gf_riff* r);

/// Fills [out] with the panel's defaults.
void gf_riff_default_params(gf_riff_params* out);

/// Applies [p]. Changes are smoothed, so moving a control never clicks.
void gf_riff_set_params(gf_riff* r, const gf_riff_params* p);

/// Follows a stream that reopened at another rate. Silences every string.
void gf_riff_set_sample_rate(gf_riff* r, float sample_rate);

/// Silences every string at once.
void gf_riff_reset(gf_riff* r);

/// Plays MIDI [note] at [velocity] (1-127; 0 is a note-off). Every note of a
/// piano's range plays at its pitch (see GF_RIFF_NOTE_MIN); only notes past
/// it move by octaves into it.
void gf_riff_note_on(gf_riff* r, int note, int velocity);

/// Releases MIDI [note]: its string is damped, or keeps ringing while the
/// sustain pedal is down.
void gf_riff_note_off(gf_riff* r, int note);

/// Damps every string, as a hand laid across them.
void gf_riff_all_notes_off(gf_riff* r);

/// Pitch bend in [-1, 1], scaled by the bend range. Bends every string.
void gf_riff_pitch_bend(gf_riff* r, float bend);

/// Sustain pedal: while down, released strings keep ringing.
void gf_riff_sustain_pedal(gf_riff* r, int down);

/// Vibrato depth in [0, 1] (mod wheel or aftertouch): up to ±0.4 semitone.
void gf_riff_vibrato(gf_riff* r, float depth);

/// Renders [n] mono samples into [out], replacing its content.
void gf_riff_process(gf_riff* r, float* out, int n);

// ── Inspection (smoke test and future panel graphics) ───────────────────────

/// MIDI note string [s] (0 = low E) was last given, or -1 when it is silent.
int gf_riff_string_note(const gf_riff* r, int s);

/// Fret of that note on string [s], or -1 when it is silent.
int gf_riff_string_fret(const gf_riff* r, int s);

/// Effective loop length of string [s]'s main vibration plane, in samples,
/// as the loop actually runs it: the delay read plus the filters' delay.
/// The note's frequency is sample_rate / this.
double gf_riff_string_period(const gf_riff* r, int s);

/// Test only: 0 tunes every string exactly, without the small offsets, the
/// slow drift and the beating between the two planes of vibration that
/// make the guitar sound played. On by default.
void gf_riff_debug_set_humanize(gf_riff* r, int enabled);

#ifdef __cplusplus
}
#endif

#endif // GF_RIFF_H
