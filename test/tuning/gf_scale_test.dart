// Tests for the Xen module's scale and tuning model.
//
// Two things are being pinned down here:
//
//   1. **The arithmetic** — that a scale turns into the right set of pitch
//      classes and the right 128-entry cent table for any root, including the
//      awkward cases (root near B where the pattern wraps, the linear layout
//      used by slendro, keys at the very edges of the MIDI range).
//
//   2. **The catalogue itself** — that no scale in the library has a
//      malformed degree list. These are hand-entered tuning tables of
//      three-decimal cent values; a transposed digit would be inaudible in a
//      code review and very audible in a chord.

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

void main() {
  group('GFScaleDegree', () {
    test('centsFromRoot combines the key offset and the detuning', () {
      // The Rast third sits on the E key (400 cents) but sounds 50 cents flat.
      const third = GFScaleDegree(4, -50.0);
      expect(third.centsFromRoot, 350.0);
      expect(third.isTempered, isFalse);
    });

    test('a degree with no detuning is tempered', () {
      const fifth = GFScaleDegree(7);
      expect(fifth.centsFromRoot, 700.0);
      expect(fifth.isTempered, isTrue);
    });
  });

  group('pitchClassesFor', () {
    test('C major yields the white keys', () {
      expect(GFScaleLibrary.major.pitchClassesFor(0),
          {0, 2, 4, 5, 7, 9, 11});
    });

    test('the pattern wraps past B when the root is high', () {
      // Rooted on B (11), the major scale's 2nd degree lands on C# (1).
      expect(GFScaleLibrary.major.pitchClassesFor(11),
          {11, 1, 3, 4, 6, 8, 10});
    });

    test('a maqam keeps its keyboard keys despite the detuning', () {
      // Rast's flattened 3rd and 7th still live on E and B: the quarter-tone
      // is in the tuning table, not in the key layout.
      expect(GFScaleLibrary.maqamRast.pitchClassesFor(0),
          {0, 2, 4, 5, 7, 9, 11});
    });

    test('a temperament constrains nothing — every key is in scale', () {
      expect(GFScaleLibrary.justIntonation.pitchClassesFor(0), isNull);
      expect(GFScaleLibrary.justIntonation.coversEveryKey, isTrue);
    });

    test('a linear scale constrains nothing either', () {
      expect(GFScaleLibrary.slendro.pitchClassesFor(0), isNull);
    });
  });

  group('tuningOffsetsFor — pitch-class layout', () {
    test('an equal-tempered scale asks for no retuning at all', () {
      final table = GFScaleLibrary.major.tuningOffsetsFor(0);
      expect(table.length, 128);
      expect(table.every((c) => c == 0.0), isTrue,
          reason: 'a 12-TET scale must leave the synth exactly where it was');
    });

    test('Rast flattens its 3rd and 7th in every octave', () {
      final table = GFScaleLibrary.maqamRast.tuningOffsetsFor(0);
      for (final e in [52, 64, 76]) {
        expect(table[e], -50.0, reason: 'E at key $e is the half-flat 3rd');
      }
      for (final b in [59, 71, 83]) {
        expect(table[b], -50.0, reason: 'B at key $b is the half-flat 7th');
      }
      expect(table[60], 0.0, reason: 'the tonic C stays put');
      expect(table[67], 0.0, reason: 'the fifth is untouched in Rast');
    });

    test('the table follows the root', () {
      // Rooted on D (2), Rast's half-flat 3rd moves from E to F#.
      final table = GFScaleLibrary.maqamRast.tuningOffsetsFor(2);
      expect(table[66], -50.0, reason: 'F# is now the third');
      expect(table[64], 0.0, reason: 'E is now the plain second');
    });

    test('out-of-scale keys stay chromatic', () {
      // C# is not in C major; it must keep its equal-tempered pitch so that a
      // player who turns snapping off still gets a usable keyboard.
      final table = GFScaleLibrary.maqamRast.tuningOffsetsFor(0);
      expect(table[61], 0.0);
    });

    test('just intonation retunes all twelve keys', () {
      final table = GFScaleLibrary.justIntonation.tuningOffsetsFor(0);
      expect(table[64], closeTo(-13.686, 0.001), reason: 'pure major third 5/4');
      expect(table[67], closeTo(1.955, 0.001), reason: 'pure fifth 3/2');
      expect(table[60], 0.0, reason: 'the tonic is the reference');
    });
  });

  group('tuningOffsetsFor — linear layout', () {
    test('slendro walks five keys per octave', () {
      final table = GFScaleLibrary.slendro.tuningOffsetsFor(0);
      // Anchored on middle C: key 60 is the tonic, and the five degrees run
      // 0, 240, 480, 720, 960 cents while the keyboard only climbs 100 a key.
      expect(table[60], 0.0);
      expect(table[61], closeTo(140.0, 0.001)); // 240 sounded − 100 written
      expect(table[62], closeTo(280.0, 0.001));
      expect(table[63], closeTo(420.0, 0.001));
      expect(table[64], closeTo(560.0, 0.001));
      // Key 65 restarts the scale one octave up: 1200 sounded − 500 written.
      expect(table[65], closeTo(700.0, 0.001));
    });

    test('slendro descends correctly below the anchor', () {
      final table = GFScaleLibrary.slendro.tuningOffsetsFor(0);
      // Key 55 is one full period below the anchor: 5 keys down the keyboard
      // (−500 cents written) but a whole octave down in the scale (−1200), so
      // it must be pulled a further 700 cents flat.
      expect(table[55], closeTo(-700.0, 0.001));
      // Key 59 is the last degree of that lower period.
      expect(table[59], closeTo(560.0 - 700.0, 0.001));
    });

    test('extreme keys stay inside the synth’s valid pitch window', () {
      final table = GFScaleLibrary.slendro.tuningOffsetsFor(0);
      for (var key = 0; key < 128; key++) {
        final absolute = key * 100.0 + table[key];
        expect(absolute, inInclusiveRange(0.0, 12700.0),
            reason: 'key $key resolves outside FluidSynth’s tuning range');
      }
    });
  });

  group('centsByPitchClassFor', () {
    test('reports only the degrees that are actually detuned', () {
      final marks = GFScaleLibrary.maqamRast.centsByPitchClassFor(0);
      expect(marks, {4: -50.0, 11: -50.0},
          reason: 'the piano should only badge the two quarter-tones');
    });

    test('is empty for a linear scale, where pitch class means nothing', () {
      expect(GFScaleLibrary.slendro.centsByPitchClassFor(0), isEmpty);
    });
  });

  group('isMicrotonal', () {
    test('separates the equal-tempered maqamat from the quarter-tone ones', () {
      // The distinction the module's UI badge depends on — and the reason
      // "microtonal" and "maqam" are not synonyms.
      expect(GFScaleLibrary.maqamRast.isMicrotonal, isTrue);
      expect(GFScaleLibrary.maqamHijaz.isMicrotonal, isFalse);
      expect(GFScaleLibrary.maqamNahawand.isMicrotonal, isFalse);
    });

    test('every Western scale is equal-tempered', () {
      for (final scale in GFScaleLibrary.byFamily(GFScaleFamily.western)) {
        expect(scale.isMicrotonal, isFalse, reason: '${scale.id} must be 12-TET');
      }
    });

    test('every temperament and raga is not', () {
      for (final scale in [
        ...GFScaleLibrary.byFamily(GFScaleFamily.temperament),
        ...GFScaleLibrary.byFamily(GFScaleFamily.raga),
      ]) {
        expect(scale.isMicrotonal, isTrue, reason: '${scale.id} must retune');
      }
    });
  });

  group('catalogue integrity', () {
    test('ids are unique', () {
      final ids = GFScaleLibrary.all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate scale id');
    });

    test('byId round-trips every scale and rejects unknown ids', () {
      for (final scale in GFScaleLibrary.all) {
        expect(GFScaleLibrary.byId(scale.id), same(scale));
      }
      expect(GFScaleLibrary.byId('no.such.scale'), isNull);
    });

    test('every scale starts on its tonic', () {
      for (final scale in GFScaleLibrary.all) {
        expect(scale.degrees.first.semitone, 0, reason: scale.id);
        expect(scale.degrees.first.cents, 0.0, reason: scale.id);
      }
    });

    test('degrees ascend and never share a key', () {
      for (final scale in GFScaleLibrary.all) {
        final semitones = scale.degrees.map((d) => d.semitone).toList();
        expect(semitones.toSet().length, semitones.length,
            reason: '${scale.id} puts two degrees on the same key');
        for (var i = 1; i < semitones.length; i++) {
          expect(semitones[i], greaterThan(semitones[i - 1]),
              reason: '${scale.id} degree $i is out of order');
        }
      }
    });

    test('pitch-class scales fit inside one octave', () {
      for (final scale in GFScaleLibrary.all) {
        if (scale.mapping != GFScaleMapping.pitchClass) continue;
        expect(scale.degrees.last.semitone, lessThan(12),
            reason: '${scale.id} runs past the octave');
        expect(scale.degrees.length, lessThanOrEqualTo(12), reason: scale.id);
      }
    });

    test('no traditional degree drifts a full semitone from its key', () {
      // For a scale that belongs to a tradition, a deviation beyond ±50 cents
      // means the degree was written on the wrong key: it would be closer to
      // its neighbour, and the greyed-out keys on the piano would no longer
      // match what the player hears.
      //
      // The experimental family is deliberately exempt. Pulling a key far from
      // its nominal pitch is the entire point there — the quarter-tone cluster
      // drops one key a full semitone on purpose — so applying the check to it
      // would be enforcing a rule that only makes sense for music that has a
      // notation to be faithful to.
      for (final scale in GFScaleLibrary.all) {
        if (scale.mapping != GFScaleMapping.pitchClass) continue;
        if (scale.family == GFScaleFamily.experimental) continue;
        if (scale.family == GFScaleFamily.custom) continue;
        for (final degree in scale.degrees) {
          expect(degree.cents.abs(), lessThanOrEqualTo(50.0),
              reason: '${scale.id} degree ${degree.semitone} is mis-keyed');
        }
      }
    });

    test('every scale carries a provenance note', () {
      for (final scale in GFScaleLibrary.all) {
        expect(scale.provenance, isNotEmpty, reason: scale.id);
      }
    });

    test('every family is represented, except custom', () {
      for (final family in GFScaleFamily.values) {
        if (family == GFScaleFamily.custom) {
          // Custom scales are made by the player; the catalogue ships none,
          // and shipping one would be a bug.
          expect(GFScaleLibrary.byFamily(family), isEmpty);
          continue;
        }
        expect(GFScaleLibrary.byFamily(family), isNotEmpty,
            reason: '$family has no scales');
      }
    });
  });
}
