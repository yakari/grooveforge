/// What the Autotune effect hears, and how to name it on its panel.
///
/// The native DSP publishes three numbers — the pitch coming in, the note it
/// is pulling that pitch towards, and how far it is pulling. Turning those
/// into "A3, 30 cents sharp, going to A3" is kept here, away from the widget,
/// so the rules can be tested without a rack or an audio engine.
library;

/// Plugin id of the Autotune audio effect.
const kAutotunePluginId = 'com.grooveforge.autotune';

/// Audio effects that follow a scale patched into their SCALE IN jack.
///
/// An audio effect has no MIDI channel to infer a scale from, so the cable
/// is the only way to tell it which Xen or Jam Mode module to follow. Shared
/// between the back panel, which decides who gets the jack, and the host,
/// which decides whose own key and scale controls a cable overrides.
const kScaleFollowingAudioEffects = {
  'com.grooveforge.audio_harmonizer',
  kAutotunePluginId,
};

/// One reading of the Autotune's readouts.
class AutotunePitch {
  const AutotunePitch({
    required this.inputNote,
    required this.targetNote,
    required this.correction,
  });

  /// Nothing pitched heard, nothing being corrected.
  static const silent =
      AutotunePitch(inputNote: null, targetNote: null, correction: 0);

  /// Builds a reading from the raw native readouts, where a negative note
  /// means "none" and null means the readout was unavailable.
  factory AutotunePitch.fromReadouts({
    required double? inputNote,
    required double? targetNote,
    required double? correction,
  }) {
    final heard = (inputNote != null && inputNote >= 0) ? inputNote : null;
    final target = (targetNote != null && targetNote >= 0)
        ? targetNote.round()
        : null;
    return AutotunePitch(
      inputNote: heard,
      targetNote: target,
      correction: correction ?? 0,
    );
  }

  /// The pitch heard, as a fractional MIDI note; null when nothing pitched is
  /// coming in (silence, a consonant, noise).
  final double? inputNote;

  /// The note being corrected towards; null when there is none.
  final int? targetNote;

  /// The correction being applied, in semitones. Positive raises the voice.
  final double correction;

  /// Whether the effect is hearing a note right now.
  bool get isVoiced => inputNote != null && targetNote != null;

  /// How far the singer is from the target, in cents: +30 is sharp, -30 flat.
  /// Null when nothing is heard.
  int? get centsOffTarget {
    final heard = inputNote;
    final target = targetNote;
    if (heard == null || target == null) return null;
    return ((heard - target) * 100).round();
  }

  @override
  bool operator ==(Object other) =>
      other is AutotunePitch &&
      other.inputNote == inputNote &&
      other.targetNote == targetNote &&
      other.correction == correction;

  @override
  int get hashCode => Object.hash(inputNote, targetNote, correction);
}

/// Letter names, sharps only, matching the Autotune's Key selector.
const _kLetterNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', //
];

/// Solfège names, sharps only.
const _kSolfegeNames = [
  'Do', 'Do#', 'Ré', 'Ré#', 'Mi', 'Fa', 'Fa#', 'Sol', 'Sol#', 'La', 'La#', //
  'Si',
];

/// Names MIDI [note] with its octave: `A3` for 57, or `La2` in solfège.
///
/// The two systems number octaves differently, not just the notes: in
/// letter notation middle C (60) is C4, while French solfège calls it Do3.
/// Printing `La3` for the A below middle C would put a French reader an
/// octave out.
String autotuneNoteName(int note, {bool solfege = false}) {
  final pitchClass = note % 12;
  final octave = note ~/ 12 - (solfege ? 2 : 1);
  final names = solfege ? _kSolfegeNames : _kLetterNames;
  return '${names[pitchClass]}$octave';
}
