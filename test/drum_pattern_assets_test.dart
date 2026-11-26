import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/drum_pattern_data.dart';
import 'package:grooveforge/services/drum_pattern_parser.dart';

/// Guards the bundled `.gfdrum` library against the two mistakes the parser
/// cannot report: a step grid whose length does not match the pattern's
/// resolution, and a grid naming an instrument the file never declared.
///
/// Both fail silently at runtime — [DrumPatternParser] drops the offending
/// grid and the pattern simply plays with a missing voice or a bar that ends
/// early — so nothing but an explicit check catches them.
void main() {
  final drumDir = Directory('assets/drums');
  final files = drumDir.listSync().whereType<File>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('every bundled pattern file parses', () {
    expect(files, isNotEmpty, reason: 'assets/drums is empty');
    for (final file in files) {
      final pattern = DrumPatternParser.parse(
        file.readAsStringSync(),
        id: _stemOf(file),
      );
      expect(pattern, isNotNull, reason: '${file.path} failed to parse');
    }
  });

  test('every step grid fills whole bars of its subdivision', () {
    // A straight grid has `resolution` steps per bar, a triplet grid three
    // per beat. A loop variation may span several bars; a grid shorter than
    // the variation repeats, so it must still be a whole number of bars.
    for (final file in files) {
      final pattern =
          DrumPatternParser.parse(file.readAsStringSync(), id: _stemOf(file))!;
      for (final section in pattern.sections.entries) {
        for (final variation in section.value.variations) {
          final bars = <DrumBarGrid>[
            DrumBarGrid(variation.stepGrids,
                subdivision: variation.subdivision),
            ...?variation.barSequence,
          ];
          for (final bar in bars) {
            final perBar = pattern.stepsPerBar(bar.subdivision);
            bar.forEach((instrument, steps) {
              final where = '${pattern.id} / ${section.key} / '
                  '${variation.name} / $instrument';
              expect(steps.length % perBar, 0,
                  reason: '$where: ${steps.length} steps, not a whole '
                      'number of $perBar-step bars');
              // A sequence lists its bars one by one.
              if (variation.barSequence != null) {
                expect(steps.length, perBar, reason: where);
              }
            });
          }
        }
      }
    }
  });

  test('the crash section only plays beat 1', () {
    // The engine lays the crash over the groove. A crash section carrying a
    // whole groove would change the bar it lands on, so it holds the cymbal
    // and the low drum on beat 1, and nothing after.
    for (final file in files) {
      final pattern =
          DrumPatternParser.parse(file.readAsStringSync(), id: _stemOf(file))!;
      final crash = pattern.sections['crash'];
      expect(crash, isNotNull, reason: '${pattern.id} has no crash section');
      for (final v in crash!.variations) {
        v.stepGrids.forEach((instrument, steps) {
          expect(steps.substring(1).replaceAll('.', ''), isEmpty,
              reason: '${pattern.id} / crash / $instrument hits after beat 1');
        });
      }
    }
  });

  test('every grid names an instrument the file declares', () {
    // The parser drops unknown instrument keys before they reach
    // [DrumVariation], so this compares the raw YAML text against the parsed
    // instrument set rather than inspecting the parsed grids.
    for (final file in files) {
      final source = file.readAsStringSync();
      final pattern = DrumPatternParser.parse(source, id: _stemOf(file))!;
      for (final key in _gridKeysIn(source)) {
        expect(
          pattern.instruments.containsKey(key),
          isTrue,
          reason: '${pattern.id}: grid "$key" has no instruments: entry, so '
              'the parser silently discards it',
        );
      }
    }
  });

  test('every style has an ending and tags its verse and chorus grooves', () {
    // A song form plays the `ending` block from this section, and picks each
    // block's groove from these tags. A missing ending falls back to a plain
    // fill and hit, so it would not fail at runtime: only this test sees it.
    for (final file in files) {
      final pattern =
          DrumPatternParser.parse(file.readAsStringSync(), id: _stemOf(file))!;
      expect(pattern.sections.containsKey('ending'), isTrue,
          reason: '${pattern.id} has no ending section');
      final groove = pattern.sections['groove']!;
      if (groove.kind != DrumSectionKind.loop) continue;
      final roles = [
        for (final v in groove.variations)
          if (v.role != null) v.role!,
      ];
      expect(roles, containsAll(['verse', 'chorus']), reason: pattern.id);
      expect(roles.toSet().length, roles.length,
          reason: '${pattern.id} gives the same role to two grooves');
    }
  });

  test('the rock and funk breaks drop out, then pick up', () {
    for (final id in ['rock_basic', 'funk_tight']) {
      final pattern = DrumPatternParser.parse(
          File('assets/drums/$id.gfdrum').readAsStringSync(), id: id)!;
      final brk = pattern.sections['break']!;
      expect(brk.kind, DrumSectionKind.sequence, reason: id);
      final bars = brk.variations.single.barSequence!;
      expect(bars, hasLength(2), reason: id);
      // Bar 1: only beat 1 sounds.
      for (final grid in bars.first.values) {
        expect(grid.substring(1).replaceAll('.', ''), isEmpty, reason: id);
      }
    }
  });

  test('every pattern file is registered for loading in main.dart', () {
    final main = File('lib/main.dart').readAsStringSync();
    for (final file in files) {
      final asset = 'assets/drums/${_stemOf(file)}.gfdrum';
      expect(
        main.contains("'$asset'"),
        isTrue,
        reason: '$asset exists but is missing from _kBundledGfdrumAssets, so '
            'it never reaches the style dropdown',
      );
    }
  });
}

/// Returns the filename stem, which is also the pattern id (`rock_basic`).
String _stemOf(File file) =>
    file.uri.pathSegments.last.replaceAll('.gfdrum', '');

/// Collects every `key: "grid"` name that appears inside a variation or a
/// `bar_grids` entry — that is, every line whose value is a quoted step grid.
///
/// A step grid is recognisable without parsing the document: it is a quoted
/// string built only from the four hit characters and the rest character.
Set<String> _gridKeysIn(String source) {
  final gridLine = RegExp(r'^\s*-?\s*(\w+):\s*"([Xxog.]+)"\s*$');
  final keys = <String>{};
  for (final line in source.split('\n')) {
    final match = gridLine.firstMatch(line);
    if (match != null) keys.add(match.group(1)!);
  }
  return keys;
}
