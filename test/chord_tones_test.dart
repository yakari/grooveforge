// The chord's own notes, as opposed to the scale it implies.
//
// A harmonizer voices itself on these: snapping to the implied scale can land
// a voice on a passing note that clashes with the chord actually being
// played, where snapping to the chord tones cannot.

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/chord_detector.dart';

void main() {
  /// Note names for readable failures.
  const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
  String show(Set<int> pcs) {
    final sorted = pcs.toList()..sort();
    return sorted.map((pc) => names[pc]).join(' ');
  }

  /// Identifies [notes] (MIDI numbers) and returns its chord tones.
  Set<int> tonesOf(List<int> notes) {
    final match = ChordDetector.identifyChord(notes.toSet());
    expect(match, isNotNull, reason: 'no chord identified for $notes');
    return match!.chordPitchClasses;
  }

  test('a major triad gives root, major third and fifth', () {
    expect(show(tonesOf([60, 64, 67])), 'C E G');
  });

  test('a minor triad gives the minor third', () {
    expect(show(tonesOf([60, 63, 67])), 'C D# G');
  });

  test('a dominant seventh includes its seventh', () {
    expect(show(tonesOf([60, 64, 67, 70])), 'C E G A#');
  });

  test('a major seventh includes the leading tone', () {
    expect(show(tonesOf([60, 64, 67, 71])), 'C E G B');
  });

  test('chords away from C rotate correctly', () {
    // F major: F A C.
    expect(show(tonesOf([65, 69, 72])), 'C F A');
    // A minor: A C E.
    expect(show(tonesOf([69, 72, 76])), 'C E A');
  });

  test('two notes are not a chord, so nothing is identified', () {
    // A root and a fifth are ambiguous — major, minor and everything else
    // share them — and the detector declines rather than guessing. The
    // harmonizer therefore keeps whatever chord it last saw, which is the
    // behaviour wanted anyway: a passing two-note voicing should not wipe
    // out the harmony.
    expect(ChordDetector.identifyChord({60, 67}), isNull);
  });

  test('chord tones are a subset of the implied scale', () {
    // The scale is the wider context; every chord tone must sit inside it, or
    // one of the two is wrong.
    for (final notes in [
      [60, 64, 67],
      [60, 63, 67],
      [60, 64, 67, 70],
      [65, 69, 72],
    ]) {
      final match = ChordDetector.identifyChord(notes.toSet())!;
      expect(
        match.chordPitchClasses.difference(match.scalePitchClasses),
        isEmpty,
        reason: '${match.name}: chord tones outside its own scale',
      );
    }
  });

  test('a triad voices three notes, a seventh chord four', () {
    // This is what drives the harmonizer's voice count.
    expect(tonesOf([60, 64, 67]).length, 3);
    expect(tonesOf([60, 64, 67, 70]).length, 4);
  });
}
