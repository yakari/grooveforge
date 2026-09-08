import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/chord_symbol.dart';

/// Semitones above the root, sorted, for readable expectations.
List<int> intervalsOf(String symbol) {
  final chord = ChordSymbol.parse(symbol);
  expect(chord, isNotNull, reason: '"$symbol" should parse');
  return chord!.intervals.toList()..sort();
}

void main() {
  group('roots', () {
    test('naturals and accidentals land on the right pitch class', () {
      expect(ChordSymbol.parse('C')!.rootPitchClass, 0);
      expect(ChordSymbol.parse('Ab')!.rootPitchClass, 8);
      expect(ChordSymbol.parse('G#')!.rootPitchClass, 8);
      expect(ChordSymbol.parse('Cb')!.rootPitchClass, 11);
      expect(ChordSymbol.parse('B#')!.rootPitchClass, 0);
    });

    test('the spelling the player used is kept', () {
      // A flat and a sharp can be the same key and mean different things about
      // the key someone is thinking in; respelling would throw that away.
      expect(ChordSymbol.parse('Ab')!.rootName, 'Ab');
      expect(ChordSymbol.parse('G#')!.rootName, 'G#');
    });

    test('nonsense is refused', () {
      for (final bad in ['', ' ', 'H', 'Cx', 'xyz', '7', 'C+-', 'Cm2']) {
        expect(ChordSymbol.parse(bad), isNull, reason: '"$bad" is not a chord');
      }
    });
  });

  group('triads', () {
    test('a bare root is major', () => expect(intervalsOf('C'), [0, 4, 7]));
    test('minor', () {
      // Three spellings a chart might use, one chord.
      for (final s in ['Cm', 'Cmin', 'C-']) {
        expect(intervalsOf(s), [0, 3, 7], reason: s);
      }
    });
    test('diminished', () {
      for (final s in ['Cdim', 'Co', 'C°']) {
        expect(intervalsOf(s), [0, 3, 6], reason: s);
      }
    });
    test('augmented', () {
      for (final s in ['Caug', 'C+']) {
        expect(intervalsOf(s), [0, 4, 8], reason: s);
      }
    });
    test('suspended', () {
      expect(intervalsOf('Csus2'), [0, 2, 7]);
      expect(intervalsOf('Csus4'), [0, 5, 7]);
      // A bare sus means sus4 by convention, not by guesswork.
      expect(intervalsOf('Csus'), [0, 5, 7]);
    });
    test('a power chord has no third', () {
      expect(intervalsOf('C5'), [0, 7]);
    });
  });

  group('contradictions', () {
    test('a symbol may name its triad only once', () {
      // Without this the last token quietly wins and a typo becomes a
      // plausible chord nobody meant.
      for (final bad in ['C+-', 'Cmaug', 'Cdimsus4', 'Cm-']) {
        expect(ChordSymbol.parse(bad), isNull, reason: bad);
      }
    });

    test('naming a triad after a degree is fine, because charts do it', () {
      // C7sus4 is ordinary. The rule is one triad, not triad-comes-first.
      expect(intervalsOf('C7sus4'), [0, 5, 7, 10]);
      expect(intervalsOf('C9sus4'), [0, 5, 7, 10, 14]);
    });
  });

  group('sevenths', () {
    test('dominant', () => expect(intervalsOf('C7'), [0, 4, 7, 10]));
    test('minor seventh', () => expect(intervalsOf('Cm7'), [0, 3, 7, 10]));

    test('major seventh, in every spelling a chart uses', () {
      for (final s in ['Cmaj7', 'CM7', 'CΔ7', 'CΔ']) {
        expect(intervalsOf(s), [0, 4, 7, 11], reason: s);
      }
    });

    test('a major marker without a 7 is still just a triad', () {
      // The trap in reading these left to right: `CM` is C major, not CM7.
      expect(intervalsOf('CM'), [0, 4, 7]);
      expect(intervalsOf('Cmaj'), [0, 4, 7]);
    });

    test('minor with a major seventh', () {
      // The one that catches naive parsers: the m and the M mean different
      // things and both matter.
      for (final s in ['CmM7', 'Cm(M7)', 'Cminmaj7']) {
        expect(intervalsOf(s), [0, 3, 7, 11], reason: s);
      }
    });

    test('fully diminished takes a diminished seventh', () {
      expect(intervalsOf('Cdim7'), [0, 3, 6, 9]);
    });

    test('half-diminished, written both ways', () {
      // ø and m7b5 are the same chord: a diminished triad with a minor 7th.
      expect(intervalsOf('Cø'), [0, 3, 6, 10]);
      expect(intervalsOf('Cm7b5'), [0, 3, 6, 10]);
    });
  });

  group('extensions and alterations', () {
    test('an extension implies the seventh below it', () {
      expect(intervalsOf('C9'), [0, 4, 7, 10, 14]);
      expect(intervalsOf('C11'), [0, 4, 7, 10, 14, 17]);
      expect(intervalsOf('C13'), [0, 4, 7, 10, 14, 17, 21]);
    });

    test('add does not imply a seventh', () {
      // The difference between add9 and 9, which is the whole reason both
      // spellings exist.
      expect(intervalsOf('Cadd9'), [0, 4, 7, 14]);
    });

    test('a sixth is a sixth, not a seventh', () {
      expect(intervalsOf('C6'), [0, 4, 7, 9]);
      expect(intervalsOf('Cm6'), [0, 3, 7, 9]);
    });

    test('6/9 is two added tones, not a slash bass', () {
      // The slash here joins degrees. Reading it as a bass note would give a
      // C6 over a note called 9, which does not exist.
      final chord = ChordSymbol.parse('C6/9')!;
      expect(chord.bassName, isNull);
      expect(intervalsOf('C6/9'), [0, 4, 7, 9, 14]);
    });

    test('alterations replace the degree they alter', () {
      expect(intervalsOf('C7b5'), [0, 4, 6, 10]);
      expect(intervalsOf('C7#5'), [0, 4, 8, 10]);
      expect(intervalsOf('C7b9'), [0, 4, 7, 10, 13]);
      expect(intervalsOf('C7#9'), [0, 4, 7, 10, 15]);
    });
  });

  group('slash bass', () {
    test('a bass note is read and kept', () {
      final chord = ChordSymbol.parse('Am(M7)/B')!;
      expect(chord.rootName, 'A');
      expect(chord.bassName, 'B');
      expect(chord.bassPitchClass, 11);
      expect(chord.intervals.toList()..sort(), [0, 3, 7, 11]);
    });

    test('the bass joins the pitch classes even when foreign to the chord', () {
      // The point of a slash chord: the bass is not one of the chord tones.
      final chord = ChordSymbol.parse('C/B')!;
      expect(chord.pitchClasses, containsAll(<int>[0, 4, 7, 11]));
    });

    test('a flat bass is a note, not an alteration', () {
      expect(ChordSymbol.parse('F/Bb')!.bassPitchClass, 10);
    });
  });

  group('display', () {
    test('accidentals become signs where they are accidentals', () {
      expect(ChordSymbol.parse('Ab')!.display, 'A♭');
      expect(ChordSymbol.parse('C#m7')!.display, 'C♯m7');
      expect(ChordSymbol.parse('Gm7b5')!.display, 'Gm7♭5');
    });

    test('a b that is not an accidental is left alone', () {
      // `sus` and `add` contain no flats, and neither does the b in `Bb`'s
      // *letter*. Getting this wrong turns sus4 into su♭4.
      expect(ChordSymbol.parse('Csus4')!.display, 'Csus4');
      expect(ChordSymbol.parse('Cadd9')!.display, 'Cadd9');
      expect(ChordSymbol.parse('Bb')!.display, 'B♭');
    });

    test('what the player typed is what is kept', () {
      expect(ChordSymbol.parse('  CM7 ')!.text, 'CM7');
      expect(ChordSymbol.parse('Cmaj7')!.text, 'Cmaj7');
    });
  });

  group("the symbols the user asked for", () {
    test('all parse', () {
      for (final s in ['Ab', 'C#m7', 'Ddim', 'Gm7b5', 'C6/9', 'Am(M7)/B']) {
        expect(ChordSymbol.isValid(s), isTrue, reason: s);
      }
    });
  });
}
