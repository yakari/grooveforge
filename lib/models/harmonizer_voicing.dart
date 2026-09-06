/// Turning a chord played on a keyboard into harmonizer voice intervals.
///
/// The Audio Harmonizer's CHORD IN jack is a shortcut for dialling intervals,
/// not a mode that takes the controls over: whatever this returns is written
/// into the voice parameters as ordinary values, so the lanes show it and stay
/// editable afterwards. Keeping the mapping here, rather than inside the host,
/// is what lets it be tested without a rack.
library;

/// Plugin ids of the modules that voice themselves on a patched chord.
///
/// Both harmonizers, deliberately. They are separate plugins — one an audio
/// effect, one a MIDI FX — that present near-identical panels, so a chord
/// cable working on only one of them reads as the feature being broken rather
/// than as a distinction between modules.
///
/// Shared with the patch overlay, which decides from the same set which slots
/// get a CHORD IN jack: a module that behaves like a follower but shows no
/// jack cannot be patched, and one that shows a jack but ignores the cable is
/// worse.
const kChordFollowingHarmonizers = {
  'com.grooveforge.audio_harmonizer',
  'com.grooveforge.harmonizer',
};

/// The voice intervals a chord asks for, in semitones, lowest first.
///
/// The lowest note played is treated as the one the singer is supplying, so
/// only the notes above it become harmony voices: C-E-G returns `[4, 7]` —
/// two voices, a third and a fifth up. That makes the mapping predictable
/// while playing, since the shape under the hand is the shape of the harmony.
///
/// - [notes] MIDI note numbers currently held. Order does not matter.
/// - [maxVoices] the module's voice ceiling; extra notes are dropped rather
///   than folded in, because there is nowhere to put them.
///
/// Returns an empty list when there is no chord to read — fewer than two
/// notes, or a [maxVoices] of zero. Callers treat that as "change nothing",
/// which is what leaves a released chord's intervals standing.
List<int> harmonizerVoicingFromChord(
  Set<int> notes, {
  required int maxVoices,
}) {
  if (notes.length < 2 || maxVoices < 1) return const [];

  final sorted = notes.toList()..sort();
  final root = sorted.first;

  return sorted
      .skip(1)
      // Clamped to the parameter's own range: two octaves is the widest
      // interval a voice can be set to, and a note past it would otherwise
      // be silently rescaled into something unrelated.
      .map((note) => (note - root).clamp(-24, 24))
      .take(maxVoices)
      .toList();
}
