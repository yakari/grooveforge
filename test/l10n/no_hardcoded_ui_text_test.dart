// Guards against user-visible English text written straight into widgets.
//
// Every word on screen goes through the ARB files (CLAUDE.md, rule 4). The app
// once had more than 200 strings that bypassed them, so French players saw
// English panels, tooltips and messages. This test reads the widget code and
// fails on a new one, naming the file and the text.
//
// It is a text scan, not a compiler: it looks at string literals passed to
// the usual places a word reaches the screen (Text, tooltips, hints, labels).
// Interpolations are removed first, so `'CC $n'` counts as the word "CC".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Arguments that put a string on screen.
final _sinks = RegExp(
  r'''(?:\bText\(|\bTextSpan\(\s*text:|\btooltip:|\bmessage:|\bhintText:|\blabelText:|\bhelperText:|\bsemanticLabel:|\btitle:)\s*(['"])((?:\\.|(?!\1).)*)\1''',
);

/// Interpolations inside a literal: `${expr}` and `$name`.
final _interpolation = RegExp(r'\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*');

/// Two letters in a row: a word, as opposed to a number, a unit sign or
/// punctuation.
final _word = RegExp(r'[A-Za-zÀ-ÿ]{2,}');

/// Text that is the same in every language, by design.
const _allowed = <String>{
  // Language names are written in their own language.
  'English',
  'Français',
  // MIDI control change numbers ("CC 7") are notation, not words.
  'CC',
  // Units.
  'dB',
};

void main() {
  test('no user-visible text is hardcoded in widgets or screens', () {
    final offenders = <String>[];
    for (final dir in ['lib/widgets', 'lib/screens']) {
      final files = Directory(dir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final file in files) {
        _scan(file, offenders);
      }
    }
    expect(offenders, isEmpty,
        reason: 'Move these strings to lib/l10n/app_en.arb and app_fr.arb:\n'
            '${offenders.join('\n')}');
  });
}

/// Adds to [offenders] every literal in [file] that puts a word on screen.
void _scan(File file, List<String> offenders) {
  final source = file.readAsStringSync();
  for (final match in _sinks.allMatches(source)) {
    final literal = match.group(2)!;
    // A quote inside an interpolation (`${x.padLeft(3, '0')}`) ends the match
    // early; what is left is code, not text.
    if (literal.contains(r'${') && !literal.contains('}')) continue;
    final text = literal.replaceAll(_interpolation, ' ').trim();
    if (!_word.hasMatch(text)) continue;
    if (_allowed.contains(text)) continue;
    final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
    offenders.add('${file.path}:$line  $literal');
  }
}
