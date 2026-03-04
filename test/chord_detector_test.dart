import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/chord_detector.dart';

void main() {
  group('ChordDetector Tests', () {
    test('Identifies C Major', () {
      expect(
        ChordDetector.identifyChord({60, 64, 67})?.name,
        'C',
      ); // Root position
      expect(
        ChordDetector.identifyChord({64, 67, 72})?.name,
        'C/E',
      ); // 1st inversion
      expect(
        ChordDetector.identifyChord({67, 72, 76})?.name,
        'C/G',
      ); // 2nd inversion
    });

    test('Identifies C Minor', () {
      expect(ChordDetector.identifyChord({60, 63, 67})?.name, 'Cm');
    });

    test('Identifies G Dominant 7th', () {
      expect(ChordDetector.identifyChord({67, 71, 74, 77})?.name, 'G7');
    });

    test('Identifies F# Diminished', () {
      expect(ChordDetector.identifyChord({66, 69, 72})?.name, 'F#dim');
    });

    test('Identifies complex chords regardless of octave spreading', () {
      // C, E, G, B spread across octaves
      expect(ChordDetector.identifyChord({48, 64, 79, 83})?.name, 'Cmaj7');
    });

    test('Returns null for non-chords (e.g., clusters)', () {
      expect(ChordDetector.identifyChord({60, 61, 62}), isNull);
    });

    test('Returns null for less than 3 notes', () {
      expect(ChordDetector.identifyChord({60, 64}), isNull);
      expect(ChordDetector.identifyChord({60}), isNull);
    });

    test('Identifies add9 and other extensions', () {
      expect(ChordDetector.identifyChord({60, 64, 67, 74})?.name, 'C(add9)');
      expect(
        ChordDetector.identifyChord({60, 64, 67, 71, 74})?.name,
        'Cmaj7(9)',
      );
      expect(ChordDetector.identifyChord({62, 65, 69, 72, 76})?.name, 'Dm7(9)');
      expect(ChordDetector.identifyChord({67, 71, 74, 77, 81})?.name, 'G7(9)');
    });

    test('Identifies slash chords', () {
      // D/F#
      expect(ChordDetector.identifyChord({54, 62, 66, 69})?.name, 'D/F#');
      // Bb/F
      expect(ChordDetector.identifyChord({53, 58, 62, 65})?.name, 'Bb/F');
    });

    test('Identifies complex jazz chords', () {
      // C7#11/F#
      // Bass: F#(54), Root: F#. C is the #11.
      expect(
        ChordDetector.identifyChord({54, 60, 64, 70, 78})?.name,
        'F#7(#11)',
      );
    });

    test('Identifies 11th and 13th chords explicitly', () {
      // C11 (Root=C(60), M3=E(64), P5=G(67), m7=Bb(70), P11=F(77))
      expect(ChordDetector.identifyChord({60, 64, 67, 70, 77})?.name, 'C7(11)');
      // C13 (Root=C(60), M3=E(64), P5=G(67), m7=Bb(70), M13=A(81))
      expect(ChordDetector.identifyChord({60, 64, 67, 70, 81})?.name, 'C7(13)');
      // Cm11 (Root=C(60), m3=Eb(63), P5=G(67), m7=Bb(70), P11=F(77))
      expect(
        ChordDetector.identifyChord({60, 63, 67, 70, 77})?.name,
        'Cm7(11)',
      );
      // Cm13 (Root=C(60), m3=Eb(63), P5=G(67), m7=Bb(70), M13=A(81))
      expect(
        ChordDetector.identifyChord({60, 63, 67, 70, 81})?.name,
        'Cm7(13)',
      );
    });

    test('Identifies chords with solfege notation correctly', () {
      // C Major (Do)
      expect(
        ChordDetector.identifyChord({
          60,
          64,
          67,
        }, format: NotationFormat.solfege)?.name,
        'Do ',
      );
      expect(
        ChordDetector.identifyChord({
          64,
          67,
          72,
        }, format: NotationFormat.solfege)?.name,
        'Do /Mi ',
      );

      // F# Diminished (Fa#dim)
      expect(
        ChordDetector.identifyChord({
          66,
          69,
          72,
        }, format: NotationFormat.solfege)?.name,
        'Fa# dim',
      );

      // Bb/F (Sib/Fa)
      expect(
        ChordDetector.identifyChord({
          53,
          58,
          62,
          65,
        }, format: NotationFormat.solfege)?.name,
        'Sib /Fa ',
      );
    });
  });
}
