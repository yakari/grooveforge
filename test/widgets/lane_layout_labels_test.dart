// Widget tests for the "lanes" panel layout (Riff, Amp, Autotune,
// harmonizers): every label must be readable, at a phone's width as well as
// on a desktop. The lane label column used to be a fixed 46 px and the
// segmented selector was capped at 120 px, so "Picking hand", "Humbucker" or
// "4x12" were cut to an ellipsis even with the whole screen free beside them.
//
// Widths are measured with Roboto, the font the app draws with, taken from
// the Flutter SDK's own cache: the test font (Ahem) draws every glyph as a
// full square and would fail labels that fit on a real screen.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge_plugin_ui/grooveforge_plugin_ui.dart';

import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/widgets/rack/gfpa_label.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded once up front: a second rootBundle read from inside a
  // testWidgets body deadlocks the harness.
  final descriptors = <String, GFPluginDescriptor>{};
  setUpAll(() async {
    await _loadRoboto();
    for (final name in ['riff', 'amp']) {
      descriptors[name] = GFDescriptorLoader.parse(
          await rootBundle.loadString('assets/plugins/$name.gfpd'))!;
    }
  });

  /// Renders the panel of [name] in a window [width] px wide, with the
  /// labels the app shows in [locale].
  Future<void> pumpPanel(
    WidgetTester tester,
    String name,
    double width, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final descriptor = descriptors[name]!;
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(builder: (ctx) {
            final l10n = AppLocalizations.of(ctx)!;
            return GFDescriptorPluginUI(
              plugin: GFDescriptorPlugin(descriptor),
              paramNotifier: ValueNotifier<int>(0),
              labelResolver: gfpaLabelResolver(l10n, descriptor.id),
              languageCode: gfpaLanguageCode(l10n),
            );
          }),
        ),
      ),
    ));
    await tester.pump();
  }

  /// The texts that were cut short by their width or line limit.
  List<String> truncatedTexts(WidgetTester tester) => tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .where((p) => p.didExceedMaxLines)
      .map((p) => p.text.toPlainText())
      .toList();

  for (final name in ['riff', 'amp']) {
    for (final width in [360.0, 768.0, 1280.0]) {
      testWidgets('$name: no label is cut at $width px', (tester) async {
        await pumpPanel(tester, name, width);
        expect(tester.takeException(), isNull);
        expect(truncatedTexts(tester), isEmpty);
      });
      // French labels run longer ("Pos. médiator", "Manche+Chev.").
      testWidgets('$name: no French label is cut at $width px',
          (tester) async {
        await pumpPanel(tester, name, width, locale: const Locale('fr'));
        expect(tester.takeException(), isNull);
        expect(truncatedTexts(tester), isEmpty);
      });
    }
  }
}

/// Registers the Flutter SDK's Roboto (regular and bold) as the "Roboto"
/// family, which Material text uses by default.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) throw StateError('FLUTTER_ROOT is not set');
  final loader = FontLoader('Roboto');
  for (final style in ['Regular', 'Bold']) {
    final file = File('$root/bin/cache/artifacts/material_fonts/Roboto-$style.ttf');
    final bytes = await file.readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}
