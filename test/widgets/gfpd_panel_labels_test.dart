// Widget tests for translated `.gfpd` panels: every text the generated panel
// draws goes through the host's label resolver, a third-party `.gfpd` can
// carry its own translations, and the bundled plugins show French labels in
// a French rack.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge_plugin_ui/grooveforge_plugin_ui.dart';

import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/widgets/rack/gfpa_label.dart';

/// Every bundled descriptor, by file name.
const _bundled = [
  'amp', 'arpeggiator', 'audio_harmonizer', 'autotune', 'chord_expand',
  'chorus', 'compressor', 'delay', 'eq', 'gate', 'harmonizer', 'microtone',
  'reverb', 'riff', 'transposer', 'velocity_curve', 'wah',
];

/// Texts that read the same in every language and so have no ARB entry:
/// symbols, abbreviations, note names, chord symbols, note divisions, amp
/// models and cabinet sizes.
final _neutral = RegExp(
  r'^(V\d|LFO|BPM|Div|FB|Flex|Tri|US|Brit|AC|IR|\d+x12|\d+|[A-G]#?|'
  r'Maj7?|Min7?|Dim7?|Aug|Sus\d|Dom7|m7b5|±\d+ st|1/\d+T?)$',
);

/// One panel per kind of text: a group heading, a control with its own
/// label, a control showing its parameter's name, a selector and a button.
const _allKindsYaml = '''
spec: "1.0"
id: "com.example.kinds"
name: "Kinds"
version: "1.0.0"
type: effect
parameters:
  - id: mix
    paramId: 0
    name: "Mix"
    min: 0
    max: 1
    default: 0.5
  - id: room
    paramId: 1
    name: "Room"
    min: 0
    max: 1
    default: 0.5
  - id: mode
    paramId: 2
    name: "Mode"
    type: selector
    min: 0
    max: 1
    default: 0
    options: ["Soft", "Hard"]
ui:
  layout: row
  groups:
    - label: "Main Group"
      controls:
        - type: knob
          param: mix
          label: "Wet"
        - type: knob
          param: room
        - type: selector
          param: mode
        - type: button
          action: reset
          label: "Flat"
''';

/// A third-party plugin carrying its own French text.
const _thirdPartyYaml = '''
spec: "1.0"
id: "com.example.gate"
name: {en: "Noise Gate", fr: "Porte de bruit"}
version: "1.0.0"
type: effect
parameters:
  - id: threshold
    paramId: 0
    name: {en: "Threshold", fr: "Seuil"}
    min: -60
    max: 0
    default: -40
  - id: mode
    paramId: 1
    name: "Mode"
    type: selector
    min: 0
    max: 1
    default: 0
    options: [{en: "Soft", fr: "Doux"}, {en: "Hard", fr: "Dur"}]
ui:
  layout: row
  groups:
    - label: {en: "Gate", fr: "Porte"}
      controls:
        - type: knob
          param: threshold
        - type: selector
          param: mode
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded once up front: a second rootBundle read from inside a
  // testWidgets body deadlocks the harness.
  final bundled = <String, GFPluginDescriptor>{};
  setUpAll(() async {
    for (final name in _bundled) {
      bundled[name] = GFDescriptorLoader.parse(
          await rootBundle.loadString('assets/plugins/$name.gfpd'))!;
    }
  });

  /// A plugin instance for [d], of the class its type calls for.
  GFAbstractDescriptorPlugin pluginFor(GFPluginDescriptor d) =>
      d.type == GFPluginType.midiFx
          ? GFMidiDescriptorPlugin(d)
          : GFDescriptorPlugin(d);

  /// Renders [panel] in a desktop-wide window, so every group shows its
  /// heading as plain text, with the app's localizations for [locale].
  Future<void> pump(
    WidgetTester tester,
    Widget Function(AppLocalizations l10n) panel, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(
            builder: (ctx) => panel(AppLocalizations.of(ctx)!),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('every kind of text goes through the resolver', (tester) async {
    final seen = <GFLabelKind>{};
    final d = GFDescriptorLoader.parse(_allKindsYaml)!;
    await pump(
      tester,
      (_) => GFDescriptorPluginUI(
        plugin: GFDescriptorPlugin(d),
        paramNotifier: ValueNotifier<int>(0),
        labelResolver: (kind, key, fallback) {
          seen.add(kind);
          return '${kind.name}:$key';
        },
      ),
    );

    for (final text in [
      'group:main_group',
      'control:mix',
      'parameter:room',
      'option:mode.0',
      'option:mode.1',
      'control:reset',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(seen, {
      GFLabelKind.group,
      GFLabelKind.control,
      GFLabelKind.parameter,
      GFLabelKind.option,
    });
    // Nothing the descriptor wrote reaches the screen untranslated.
    for (final english in ['Main Group', 'Wet', 'Room', 'Soft', 'Flat']) {
      expect(find.text(english), findsNothing, reason: english);
    }
  });

  testWidgets('a third-party .gfpd shows its own French text', (tester) async {
    final d = GFDescriptorLoader.parse(_thirdPartyYaml)!;
    await pump(
      tester,
      (l10n) => GFDescriptorPluginUI(
        plugin: GFDescriptorPlugin(d),
        paramNotifier: ValueNotifier<int>(0),
        labelResolver: gfpaLabelResolver(l10n, d.id),
        languageCode: gfpaLanguageCode(l10n),
      ),
      locale: const Locale('fr'),
    );
    for (final text in ['Porte', 'Seuil', 'Doux', 'Dur']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('Gate'), findsNothing);
  });

  testWidgets('the French rack translates a bundled panel', (tester) async {
    final d = bundled['compressor']!;
    await pump(
      tester,
      (l10n) => GFDescriptorPluginUI(
        plugin: GFDescriptorPlugin(d),
        paramNotifier: ValueNotifier<int>(0),
        labelResolver: gfpaLabelResolver(l10n, d.id),
        languageCode: gfpaLanguageCode(l10n),
      ),
      locale: const Locale('fr'),
    );
    for (final text in ['Enveloppe', 'Sortie', 'Seuil', 'Relâchement']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text('Envelope'), findsNothing);
  });

  testWidgets('the slot header names a bundled plugin in French',
      (tester) async {
    GFPluginRegistry.instance
        .register(GFDescriptorPlugin(bundled['reverb']!), replace: true);
    final slot = GFpaPluginInstance(id: 's1', pluginId: 'com.grooveforge.reverb');
    String? name;
    await pump(
      tester,
      (l10n) {
        name = gfpaSlotHeaderName(l10n, slot);
        return const SizedBox();
      },
      locale: const Locale('fr'),
    );
    expect(name, 'Réverb à plaque');
  });

  // Guards the generated table against a label added to a bundled `.gfpd`
  // without an ARB entry: such a label would stay English in every language.
  for (final name in _bundled) {
    testWidgets('$name: every text has a translation', (tester) async {
      final d = bundled[name]!;
      final missing = <String>[];
      await pump(
        tester,
        (l10n) => GFDescriptorPluginUI(
          plugin: pluginFor(d),
          paramNotifier: ValueNotifier<int>(0),
          labelResolver: (kind, key, fallback) {
            const sentinel = '\u0000';
            final hit = gfpaLabel(l10n, d.id, kind, key, sentinel);
            if (hit == sentinel && !_neutral.hasMatch(fallback)) {
              missing.add('${kind.name} $key "$fallback"');
            }
            return fallback;
          },
        ),
      );
      expect(missing, isEmpty);
      expect(
        gfpaLabel(lookupAppLocalizations(const Locale('fr')), d.id,
            GFLabelKind.pluginName, '', '\u0000'),
        isNot('\u0000'),
      );
    });
  }
}
