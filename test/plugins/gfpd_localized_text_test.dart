// Tests for the two ways a `.gfpd` can write a user-visible text: a plain
// string (what every bundled plugin uses) and a language map such as
// `label: {en: "Gate", fr: "Porte"}` (for third-party plugins, which the
// app's ARB files cannot translate).

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// A descriptor that uses the map form wherever a text is allowed, with a
/// plain string mixed in at each level to prove both forms coexist.
const _localizedYaml = '''
spec: "1.0"
id: "com.example.gate"
name: {en: "Noise Gate", fr: "Porte de bruit"}
version: "1.0.0"
type: effect
parameters:
  - id: threshold
    paramId: 0
    name: {en: "Threshold", fr: "Seuil"}
    min: -60.0
    max: 0.0
    default: -40.0
  - id: mode
    paramId: 1
    name: "Mode"
    type: selector
    min: 0
    max: 2
    default: 0
    options: [{en: "Soft", fr: "Doux"}, "Hard", {de: "Schnell"}]
ui:
  layout: row
  groups:
    - label: {en: "Gate", fr: "Porte"}
      controls:
        - type: knob
          param: threshold
          label: {en: "Thresh", fr: "Seuil"}
        - type: selector
          param: mode
    - label: "Output"
      controls:
        - type: knob
          param: threshold
          label: "Level"
''';

/// The same plugin with plain strings only, the form every existing `.gfpd`
/// uses.
const _plainYaml = '''
spec: "1.0"
id: "com.example.plain"
name: "Plain"
version: "1.0.0"
type: effect
parameters:
  - id: mode
    paramId: 0
    name: "Mode"
    type: selector
    min: 0
    max: 1
    default: 0
    options: ["A", "B"]
ui:
  layout: row
  groups:
    - label: "Main"
      controls:
        - type: selector
          param: mode
''';

void main() {
  group('GFLocalizedText', () {
    const text = GFLocalizedText({'fr': 'Porte', 'en': 'Gate'});

    test('picks the requested language', () {
      expect(text.resolve('fr'), 'Porte');
    });

    test('falls back to English for a missing language', () {
      expect(text.resolve('de'), 'Gate');
    });

    test('reads a regional locale as its bare language', () {
      expect(text.resolve('fr_CA'), 'Porte');
      expect(text.resolve('fr-BE'), 'Porte');
    });

    test('falls back to the first entry when there is no English', () {
      const noEnglish = GFLocalizedText({'de': 'Tor', 'fr': 'Porte'});
      expect(noEnglish.defaultText, 'Tor');
      expect(noEnglish.resolve('es'), 'Tor');
    });
  });

  group('GFDescriptorLoader, language maps', () {
    late GFPluginDescriptor d;
    setUp(() => d = GFDescriptorLoader.parse(_localizedYaml)!);

    test('plugin name', () {
      expect(d.name, 'Noise Gate');
      expect(d.nameIn('fr'), 'Porte de bruit');
      expect(d.nameIn('de'), 'Noise Gate');
    });

    test('parameter name, map and plain', () {
      final threshold = d.paramById('threshold')!;
      expect(threshold.name, 'Threshold');
      expect(threshold.nameIn('fr'), 'Seuil');

      final mode = d.paramById('mode')!;
      expect(mode.localizedName, isNull);
      expect(mode.nameIn('fr'), 'Mode');
    });

    test('options mix maps and plain strings', () {
      final mode = d.paramById('mode')!;
      expect(mode.options, ['Soft', 'Hard', 'Schnell']);
      expect(mode.optionsIn('fr'), ['Doux', 'Hard', 'Schnell']);
      expect(mode.optionsIn('de'), ['Soft', 'Hard', 'Schnell']);
    });

    test('group labels, map and plain', () {
      expect(d.groups[0].label, 'Gate');
      expect(d.groups[0].labelIn('fr'), 'Porte');
      expect(d.groups[1].localizedLabel, isNull);
      expect(d.groups[1].labelIn('fr'), 'Output');
    });

    test('control labels, map, plain and absent', () {
      final gate = d.groups[0].controls;
      expect(gate[0].label, 'Thresh');
      expect(gate[0].labelIn('fr'), 'Seuil');
      // No label: stays null so the panel shows the parameter name.
      expect(gate[1].label, isNull);
      expect(gate[1].labelIn('fr'), isNull);
      expect(d.groups[1].controls.single.labelIn('fr'), 'Level');
    });
  });

  group('GFDescriptorLoader, plain strings', () {
    test('parse exactly as before, with no language maps', () {
      final d = GFDescriptorLoader.parse(_plainYaml)!;
      expect(d.name, 'Plain');
      expect(d.localizedName, isNull);
      final mode = d.paramById('mode')!;
      expect(mode.options, ['A', 'B']);
      expect(mode.localizedOptions, isNull);
      expect(mode.optionsIn('fr'), ['A', 'B']);
      expect(d.groups.single.label, 'Main');
      expect(d.groups.single.localizedLabel, isNull);
      expect(d.groups.single.controls.single.label, isNull);
    });
  });
}
