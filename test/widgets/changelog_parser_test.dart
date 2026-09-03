// Tests for the "what's new" changelog parser in the user guide.
//
// The bug this guards against is quiet by construction: the parser only read
// `### Added`, matched against a hard-coded English or French heading. Release
// 2.17.2 changed and fixed things without adding any, so the panel showed an
// empty list — and the empty case fell back to two hard-coded English bullets,
// telling a French user, in English, about contents the changelog never had.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/widgets/user_guide_modal.dart';

const _fr = '''
# Changelog

## [2.17.2] - 2026-09-03

### Modifié
- Rack par défaut : un clavier piloté par un module Xen.
- Guide : section Xen ajoutée.

### Corrigé
- Le bouton on/off de Xen n'avait aucun effet.

### Architecture
- Effacer l'accordage n'appelle plus le synthé pour rien.

## [2.17.1] - 2026-09-01

### Ajouté
- Une gamme par pad.
''';

const _en = '''
## [2.17.2] - 2026-09-03

### Fixed
- **Xen's** on/off button and its `bypass` CC had no effect.

## [2.17.1] - 2026-09-01

### Added
- Older entry that must not leak in.
''';

List<String> bulletsOf(String changelog) => parseLatestChangelogEntries(changelog)
    .where((e) => !e.isSection)
    .map((e) => e.text)
    .toList();

List<String> sectionsOf(String changelog) =>
    parseLatestChangelogEntries(changelog)
        .where((e) => e.isSection)
        .map((e) => e.text)
        .toList();

void main() {
  group('a release with no Added section', () {
    test('still reports its changes', () {
      // The whole point: 2.17.2 has Modifié, Corrigé and Architecture and
      // nothing else, so reading only "Ajouté" returned nothing at all.
      final bullets = bulletsOf(_fr);
      expect(bullets, hasLength(4));
      expect(bullets.first, startsWith('Rack par défaut'));
      expect(bullets, contains("Le bouton on/off de Xen n'avait aucun effet."));
    });

    test('keeps the section headings, in the changelog own language', () {
      // No ARB keys involved — the app already loaded the localised file, so a
      // fix is never presented as a new feature.
      expect(sectionsOf(_fr), ['Modifié', 'Corrigé', 'Architecture']);
    });
  });

  group('scope', () {
    test('stops at the previous release', () {
      expect(bulletsOf(_en), hasLength(1));
      expect(bulletsOf(_fr).join(), isNot(contains('Une gamme par pad')));
    });

    test('strips bold and code markup', () {
      expect(bulletsOf(_en).single,
          "Xen's on/off button and its bypass CC had no effect.");
    });
  });

  group('degenerate input', () {
    test('an empty changelog yields nothing', () {
      expect(parseLatestChangelogEntries(''), isEmpty);
    });

    test('a version block with headings but no bullets yields nothing', () {
      // Otherwise the panel would show bare headings under "what's new".
      const empty = '## [9.9.9] - 2026-01-01\n\n### Added\n\n## [9.9.8]\n';
      expect(parseLatestChangelogEntries(empty), isEmpty);
    });

    test('text before the first version block is ignored', () {
      const withPreamble = '# Changelog\n\nAll notable changes.\n\n'
          '- not a release note\n\n## [1.0.0]\n\n### Added\n- the real one\n';
      expect(bulletsOf(withPreamble), ['the real one']);
    });
  });

  group('the shipped changelogs parse', () {
    // Read the real files: a formatting slip in a release would otherwise only
    // surface as an empty panel on the user's screen.
    for (final path in const ['CHANGELOG.md', 'CHANGELOG.fr.md']) {
      test(path, () {
        final bullets = bulletsOf(File(path).readAsStringSync());
        expect(bullets, isNotEmpty,
            reason: '$path must show something under "what\'s new"');
        for (final bullet in bullets) {
          expect(bullet.trim(), isNotEmpty);
        }
      });
    }
  });
}
