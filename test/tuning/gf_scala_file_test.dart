// Tests for the Scala (.scl) reader and the experimental scale presets.
//
// The .scl format is older than most of what reads it and its two traps are
// both silent: the tonic is implicit (a twelve-note scale lists degrees 1–12,
// not 0–11) and the LAST line is the repeat interval rather than a degree.
// Getting either wrong yields a scale that loads, plays, and is a degree out
// of tune everywhere — so the round-trip values are what these tests pin down.

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Quarter-comma meantone, in the shape a real file has it: comments, ragged
/// indentation, a ratio for the octave, and trailing annotations.
const _meantoneScl = '''
! meanquar.scl
!
1/4-comma meantone scale
 12
!
 76.04900
 193.15686
 310.26471
 386.31371
 503.42157
 579.47057
 696.57843
 772.62743
 889.73529
 1006.84314
 1082.89214
 2/1
''';

/// Bohlen-Pierce: thirteen degrees repeating at a tritave, not an octave.
const _bohlenPierceScl = '''
! bohlen-p.scl
!
Bohlen-Pierce 13-tone equal
 13
!
 146.30435
 292.60870
 438.91304
 585.21739
 731.52174
 877.82609
 1024.13043
 1170.43478
 1316.73913
 1463.04348
 1609.34783
 1755.65217
 3/1
''';

void main() {
  group('parsing a familiar scale', () {
    late GFScale scale;

    setUpAll(() {
      final result = GFScalaFile.parse(_meantoneScl, id: 'imported-meantone');
      expect(result.error, isNull);
      scale = result.scale!;
    });

    test('takes its name from the description line', () {
      expect(scale.name, '1/4-comma meantone scale');
      expect(scale.family, GFScaleFamily.custom);
    });

    test('the tonic is implicit — twelve lines mean twelve degrees', () {
      // The file lists degrees 1–12; degree 0 is never written down. Reading
      // the lines as degrees 0–11 would put the whole scale one step out.
      expect(scale.degreeCount, 12);
      expect(scale.degrees.first.semitone, 0);
      expect(scale.degrees.first.cents, 0.0);
    });

    test('the last line is the period, not a degree', () {
      expect(scale.periodCents, closeTo(1200.0, 0.001),
          reason: '2/1 is an octave');
      // 1082.89 is the twelfth degree; the octave is not in the degree list.
      expect(scale.degrees.last.centsFromRoot, closeTo(1082.892, 0.01));
    });

    test('twelve degrees keep the familiar keyboard layout', () {
      expect(scale.mapping, GFScaleMapping.pitchClass);
      expect(scale.coversEveryKey, isTrue);
    });

    test('the cent values match the tuning it describes', () {
      // Quarter-comma meantone's pure major third, 5/4 = 386.31 cents.
      final third = scale.degrees[4];
      expect(third.semitone, 4);
      expect(third.centsFromRoot, closeTo(386.314, 0.01));
      // And its narrowed fifth.
      expect(scale.degrees[7].centsFromRoot, closeTo(696.578, 0.01));
    });
  });

  group('ratios and cents', () {
    test('a ratio is converted to cents', () {
      final result = GFScalaFile.parse(
        'Pure fifth\n 2\n 3/2\n 2/1\n',
        id: 'x',
      );
      expect(result.scale!.degrees[1].centsFromRoot, closeTo(701.955, 0.001));
    });

    test('a bare integer is read as n/1', () {
      final result = GFScalaFile.parse('Octaves\n 1\n 2\n', id: 'x');
      expect(result.scale!.periodCents, closeTo(1200.0, 0.001));
    });

    test('trailing text on a pitch line is a comment', () {
      final result = GFScalaFile.parse(
        'Annotated\n 2\n 701.955 the fifth\n 2/1 octave\n',
        id: 'x',
      );
      expect(result.error, isNull);
      expect(result.scale!.degrees[1].centsFromRoot, closeTo(701.955, 0.001));
    });
  });

  group('non-octave and large scales', () {
    test('Bohlen-Pierce keeps its tritave', () {
      final scale =
          GFScalaFile.parse(_bohlenPierceScl, id: 'imported-bp').scale!;
      expect(scale.periodCents, closeTo(1901.955, 0.01),
          reason: '3/1 is the tritave — losing it would force an octave');
      expect(scale.degreeCount, 13);
      // Thirteen degrees cannot be spelled on twelve keys.
      expect(scale.mapping, GFScaleMapping.linear);
    });

    test('a scale beyond twelve degrees takes the linear layout', () {
      final lines = [for (var i = 1; i <= 24; i++) '${i * 50.0}'];
      final result = GFScalaFile.parse(
        '24-EDO\n 24\n${lines.join('\n')}\n',
        id: 'x',
      );
      final scale = result.scale!;
      expect(scale.mapping, GFScaleMapping.linear);
      expect(scale.keysPerPeriod, 24,
          reason: 'one sounding octave spans 24 keys');
    });

    test('degrees that would collide on one key fall back to linear', () {
      // Two degrees 10 cents apart both round to the same key, which the
      // familiar layout cannot express — one would silently overwrite the
      // other.
      final result = GFScalaFile.parse(
        'Colliding\n 3\n 10.0\n 20.0\n 2/1\n',
        id: 'x',
      );
      expect(result.scale!.mapping, GFScaleMapping.linear);
    });
  });

  group('malformed files', () {
    test('a missing note count is reported, not thrown', () {
      final result = GFScalaFile.parse('Just a name\n', id: 'x');
      expect(result.isSuccess, isFalse);
      expect(result.error, contains('description'));
    });

    test('a non-numeric count is reported', () {
      final result = GFScalaFile.parse('Name\n twelve\n', id: 'x');
      expect(result.error, contains('note count'));
    });

    test('too few pitch lines is reported', () {
      final result = GFScalaFile.parse('Name\n 5\n 100.0\n 2/1\n', id: 'x');
      expect(result.error, contains('declares 5'));
    });

    test('a junk pitch line names its line number', () {
      final result =
          GFScalaFile.parse('Name\n 2\n banana\n 2/1\n', id: 'x');
      expect(result.error, contains('Line 3'));
    });

    test('an empty description falls back to the filename', () {
      final result = GFScalaFile.parse(
        '\n 1\n 2/1\n',
        id: 'x',
        fallbackName: 'mystery.scl',
      );
      expect(result.scale!.name, 'mystery.scl');
    });
  });

  group('experimental presets', () {
    test('24-EDO puts a quarter-tone on every key', () {
      final table = GFScaleLibrary.quarterTone24Edo.tuningOffsetsFor(0);
      // Anchored on middle C, successive keys rise 50 cents each.
      for (var i = 0; i <= 24; i++) {
        expect(60 * 100.0 + table[60] + i * 50.0,
            closeTo((60 + i) * 100.0 + table[60 + i], 0.001),
            reason: 'key ${60 + i} must sound $i quarter-tones above C4');
      }
    });

    test('24-EDO reaches the octave after 24 keys', () {
      final table = GFScaleLibrary.quarterTone24Edo.tuningOffsetsFor(0);
      final c4 = 6000.0 + table[60];
      final octaveUp = 8400.0 + table[84];
      expect(octaveUp - c4, closeTo(1200.0, 0.001));
    });

    test('Bohlen-Pierce never produces an octave', () {
      final scale = GFScaleLibrary.bohlenPierce;
      expect(scale.periodCents, closeTo(1901.955, 0.001));
      final table = scale.tuningOffsetsFor(0);
      final root = 6000.0 + table[60];
      // Thirteen keys up is the tritave, not two octaves.
      expect((7300.0 + table[73]) - root, closeTo(1901.955, 0.01));
    });

    test('the quarter-tone cluster compresses four keys into a semitone', () {
      // The user-facing shape of the feature: C, C#, D, D# sound 0, 50, 100
      // and 150 cents, then the scale resumes at E.
      final table = GFScaleLibrary.quarterToneCluster.tuningOffsetsFor(0);
      expect(6000.0 + table[60], 6000.0);
      expect(6100.0 + table[61], 6050.0);
      expect(6200.0 + table[62], 6100.0);
      expect(6300.0 + table[63], 6150.0);
      expect(6400.0 + table[64], 6400.0, reason: 'E is untouched');
    });

    test('every experimental preset is microtonal and well formed', () {
      final family = GFScaleLibrary.byFamily(GFScaleFamily.experimental);
      expect(family, isNotEmpty);
      for (final scale in family) {
        expect(scale.isMicrotonal, isTrue, reason: scale.id);
        expect(scale.degrees.first.centsFromRoot, 0.0, reason: scale.id);
        expect(scale.provenance, isNotEmpty, reason: scale.id);
      }
    });
  });

  group('exporting to Scala', () {
    test('nothing has to be recomputed — centsFromRoot is what .scl wants', () {
      final text = GFScalaFile.export(GFScaleLibrary.maqamRast);
      // Rast on its tonic: 200, 350, 500, 700, 900, 1050, then the octave.
      expect(text, contains('350.000000'));
      expect(text, contains('1050.000000'));
      expect(text, contains('1200.000000'));
    });

    test('the tonic is omitted and the period closes the file', () {
      final text = GFScalaFile.export(GFScaleLibrary.maqamRast);
      final lines = text
          .split('\n')
          .where((l) => l.trim().isNotEmpty && !l.trimLeft().startsWith('!'))
          .toList();
      // description, count, then one line per degree above the tonic + period.
      expect(lines[1].trim(), '7', reason: 'seven degrees means seven lines');
      expect(lines.length, 2 + 7);
      expect(double.parse(lines.last.trim()), closeTo(1200.0, 0.001));
      expect(text, isNot(contains('\n 0.000000')),
          reason: 'the tonic is implicit and must not be written');
    });

    test('cents are always dotted', () {
      // An undotted "1200" would be read back as the ratio 1200/1.
      final text = GFScalaFile.export(GFScaleLibrary.bohlenPierce);
      for (final line in text.split('\n')) {
        final t = line.trim();
        if (t.isEmpty || t.startsWith('!')) continue;
        if (double.tryParse(t) == null) continue;
        if (t == '13') continue; // the note count
        expect(t, contains('.'), reason: '"$t" would be read as a ratio');
      }
    });

    test('a non-octave scale keeps its period', () {
      final text = GFScalaFile.export(GFScaleLibrary.bohlenPierce);
      final reimported = GFScalaFile.parse(text, id: 'bp-round').scale!;
      expect(reimported.periodCents, closeTo(1901.955, 0.01));
      expect(reimported.degreeCount, GFScaleLibrary.bohlenPierce.degreeCount);
    });

    test('pitches survive the round trip exactly', () {
      final original = GFScaleLibrary.maqamRast;
      final text = GFScalaFile.export(original);
      final reimported = GFScalaFile.parse(text, id: 'rast-round').scale!;

      expect(reimported.degreeCount, original.degreeCount);
      for (var i = 0; i < original.degreeCount; i++) {
        expect(
          reimported.degrees[i].centsFromRoot,
          closeTo(original.degrees[i].centsFromRoot, 0.001),
          reason: 'degree $i must sound identical after a round trip',
        );
      }
      // For a scale whose degrees sit near distinct keys, the fingering
      // survives too.
      expect(reimported.mapping, original.mapping);
      expect(reimported.pitchClassesFor(0), original.pitchClassesFor(0));
    });

    test('a crowded scale keeps its pitches but changes fingering', () {
      // The quarter-tone cluster puts four degrees inside one semitone. .scl
      // cannot say which key each belongs to, so they come back on successive
      // keys: same sound, different fingering. Worth pinning down so the
      // limitation is a documented behaviour rather than a surprise.
      final original = GFScaleLibrary.quarterToneCluster;
      final text = GFScalaFile.export(original);
      final reimported = GFScalaFile.parse(text, id: 'cluster-round').scale!;

      for (var i = 0; i < original.degreeCount; i++) {
        expect(
          reimported.degrees[i].centsFromRoot,
          closeTo(original.degrees[i].centsFromRoot, 0.001),
        );
      }
      expect(reimported.mapping, GFScaleMapping.linear);
      expect(original.mapping, GFScaleMapping.pitchClass);
    });

    test('an equal division round-trips step for step', () {
      final text = GFScalaFile.export(GFScaleLibrary.quarterTone24Edo);
      final reimported = GFScalaFile.parse(text, id: 'edo24-round').scale!;
      expect(reimported.degreeCount, 24);
      expect(reimported.mapping, GFScaleMapping.linear);
      for (var i = 0; i < 24; i++) {
        expect(reimported.degrees[i].centsFromRoot, closeTo(i * 50.0, 0.001));
      }
    });
  });

  group('serialisation', () {
    test('a scale round-trips through JSON', () {
      final original =
          GFScalaFile.parse(_bohlenPierceScl, id: 'imported-bp').scale!;
      final restored = GFScale.fromJson(original.toJson())!;

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.mapping, original.mapping);
      expect(restored.periodCents, original.periodCents);
      expect(restored.degreeCount, original.degreeCount);
      expect(restored.tuningOffsetsFor(3), original.tuningOffsetsFor(3));
    });

    test('a malformed payload yields null rather than throwing', () {
      // A hand-edited scale file must cost the player that one scale, not the
      // whole library or the project it lives in.
      expect(GFScale.fromJson({'id': 'x'}), isNull);
      expect(GFScale.fromJson({'id': 'x', 'name': 'y', 'degrees': []}), isNull);
      expect(
        GFScale.fromJson({
          'id': 'x',
          'name': 'y',
          'degrees': [
            {'semitone': 0},
          ],
        }),
        isNull,
      );
    });
  });
}
