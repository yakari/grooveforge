// gf_pitch.h — Monophonic pitch tracker for real-time audio.
//
// Answers one question: what note is being sung or played right now?
//
// The Audio Harmonizer needs it to scale-lock. A harmony voice set to "a
// third above" cannot stay a fixed +4 semitones — over C major that is E and
// correct, over A minor it is C# and wrong. To land on the right scale tone
// the harmonizer has to know which note the singer is on, and an audio
// effect, unlike a MIDI one, is not told.
//
// Method: normalised autocorrelation on a decimated copy of the signal.
// Autocorrelation is chosen over an FFT peak because the fundamental of a
// voice is often weaker than its harmonics — a spectral peak picker reports
// the second or third harmonic and the harmony comes out an octave or a
// twelfth high, which is the single worst failure mode here. Correlation
// looks for the *period*, which the harmonics reinforce rather than
// confuse.
//
// Decimation by four before correlating cuts the work to a sixteenth (the
// window and the lag range both shrink) and costs nothing: the pitches this
// has to resolve, roughly 65 Hz to 1 kHz, are far below the reduced Nyquist.
//
// Real-time safety: after gf_pitch_create nothing on the hot path allocates,
// locks or logs.

#ifndef GF_PITCH_H
#define GF_PITCH_H

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle. All state is owned by this struct.
typedef struct gf_pitch gf_pitch;

/// Creates a tracker for [sample_rate] Hz audio. Returns NULL on bad input
/// or out-of-memory.
gf_pitch* gf_pitch_create(float sample_rate);

/// Destroys a tracker. Safe to pass NULL.
void gf_pitch_destroy(gf_pitch* p);

/// Forgets the current pitch and clears the analysis buffer. Allocation-free;
/// safe from the audio thread.
void gf_pitch_reset(gf_pitch* p);

/// Feeds [n] mono frames and updates the estimate.
///
/// Analysis runs on its own schedule rather than once per call, so this is
/// safe to hand any block size, and the cost per second of audio does not
/// depend on the audio device's block size.
void gf_pitch_process(gf_pitch* p, const float* in, int n);

/// The current estimate in MIDI note numbers, fractional so a singer sitting
/// between two notes reads as such (69.5 is a quarter-tone above A4).
///
/// Returns a negative number when nothing usable is being heard — silence,
/// noise, or a signal too inharmonic to have a pitch. Callers must treat that
/// as "do not snap" rather than as a note.
float gf_pitch_midi_note(const gf_pitch* p);

/// How much to trust [gf_pitch_midi_note], from 0 to 1.
///
/// This is the normalised correlation at the chosen period: 1 is a perfectly
/// periodic signal, and anything under about 0.6 is usually noise, a
/// consonant, or two notes at once.
float gf_pitch_confidence(const gf_pitch* p);

#ifdef __cplusplus
}
#endif

#endif // GF_PITCH_H
