import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/harmonizer_voicing.dart';

void main() {
  group('harmonizerVoicingFromChord', () {
    test('a major triad asks for a third and a fifth', () {
      // C4 E4 G4 — the singer supplies the C, so two voices harmonise it.
      expect(harmonizerVoicingFromChord({60, 64, 67}, maxVoices: 4), [4, 7]);
    });

    test('the voicing played is the voicing returned, not a normalised one', () {
      // A wide, open chord must keep its shape: the octave-plus-third stays a
      // tenth rather than being folded back inside one octave.
      expect(harmonizerVoicingFromChord({60, 76, 79}, maxVoices: 4), [16, 19]);
    });

    test('note order does not matter', () {
      expect(
        harmonizerVoicingFromChord({67, 60, 64}, maxVoices: 4),
        harmonizerVoicingFromChord({60, 64, 67}, maxVoices: 4),
      );
    });

    test('a single key is not a chord and changes nothing', () {
      expect(harmonizerVoicingFromChord({60}, maxVoices: 4), isEmpty);
      expect(harmonizerVoicingFromChord(<int>{}, maxVoices: 4), isEmpty);
    });

    test('extra notes are dropped at the voice ceiling', () {
      // Six notes, four voices: the lowest is the singer's, and only the next
      // four are voiced.
      expect(
        harmonizerVoicingFromChord({60, 62, 64, 65, 67, 69}, maxVoices: 4),
        [2, 4, 5, 7],
      );
    });

    test('a chord wider than the voice range is clamped, not wrapped', () {
      // Three octaves up is past the +/-24 a voice can be set to. Clamping
      // keeps it at the top of the range; wrapping would put it somewhere
      // unrelated to what was played.
      expect(harmonizerVoicingFromChord({36, 72}, maxVoices: 4), [24]);
    });
  });
}
