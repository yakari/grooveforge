// Widget tests for the generated harmonizer panels.
//
// Both harmonizers now print a value under several of their knobs, which is
// the first time the generated `.gfpd` UI puts a second line of text under a
// control. Two things are worth pinning:
//
//   1. The readouts are actually rendered, and localised — a French user
//      reads `5J`, not `P5`.
//   2. Adding that line did not break Rule 1. An interval readout is wider
//      than the knob above it, so a phone-width panel is the case that
//      would overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge_plugin_ui/grooveforge_plugin_ui.dart';

import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/widgets/rack/gfpa_param_readout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Descriptors are read once, up front. Reaching for `rootBundle` from
  // inside a `testWidgets` body borrows the same host channel the test
  // harness is driving the widget test over, and the second such read in a
  // file deadlocks it.
  final descriptors = <String, GFPluginDescriptor>{};

  setUpAll(() async {
    for (final asset in const [
      'assets/plugins/audio_harmonizer.gfpd',
      'assets/plugins/harmonizer.gfpd',
    ]) {
      final parsed = GFDescriptorLoader.parse(await rootBundle.loadString(asset));
      expect(parsed, isNotNull, reason: '$asset must parse cleanly');
      descriptors[asset] = parsed!;
    }
  });

  /// Renders one descriptor plugin's generated panel at [width] logical
  /// pixels, wired to the same localised readout the rack uses.
  Future<void> pumpPanel(
    WidgetTester tester, {
    required String asset,
    required double width,
    Locale locale = const Locale('en'),
  }) async {
    final descriptor = descriptors[asset]!;
    final plugin = descriptor.type == GFPluginType.midiFx
        ? GFMidiDescriptorPlugin(descriptor) as GFAbstractDescriptorPlugin
        : GFDescriptorPlugin(descriptor);

    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(
            child: Builder(
              builder: (ctx) {
                final l10n = AppLocalizations.of(ctx)!;
                return GFDescriptorPluginUI(
                  plugin: plugin,
                  paramNotifier: ValueNotifier<int>(0),
                  valueFormatter: (param, raw) =>
                      gfpaParamReadout(l10n, param, raw),
                );
              },
            ),
          ),
        ),
      ),
    );
    // Two frames rather than pumpAndSettle: the panel has no entry
    // animation to wait out, and pumpAndSettle would keep pumping for its
    // full ten-minute budget if any knob ever scheduled a repeating frame.
    await tester.pump();
    await tester.pump();
  }

  group('Audio Harmonizer panel', () {
    testWidgets('interval knobs show the interval, not just an angle',
        (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);

      // Defaults are +7, +12, +4 and -5 semitones.
      expect(find.text('+7 st · P5'), findsOneWidget);
      expect(find.text('+12 st · 8ve'), findsOneWidget);
      expect(find.text('+4 st · M3'), findsOneWidget);
      expect(find.text('-5 st · P4'), findsOneWidget);
    });

    testWidgets('the voice count is spelled out', (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('mix and dry/wet knobs stay label-only', (tester) async {
      // Only parameters that asked for a readout get one; a "how much"
      // control is not improved by a number under it.
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);
      expect(find.text('0.7'), findsNothing);
      expect(find.text('0.5'), findsNothing);
    });
  });

  group('MIDI Harmonizer panel', () {
    testWidgets('four voices and a count knob are rendered', (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/harmonizer.gfpd', width: 1280);

      expect(find.text('Count'), findsOneWidget);
      for (final v in ['Voice 1', 'Voice 2', 'Voice 3', 'Voice 4']) {
        expect(find.text(v), findsOneWidget);
      }
      expect(find.text('+4 st · M3'), findsOneWidget);
      expect(find.text('+7 st · P5'), findsOneWidget);
      expect(find.text('+12 st · 8ve'), findsOneWidget);
      expect(find.text('+16 st · M3+8ve'), findsOneWidget);
    });

    testWidgets('French names the intervals its own way', (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/harmonizer.gfpd',
          width: 1280,
          locale: const Locale('fr'));
      expect(find.text('+7 st · 5J'), findsOneWidget);
      expect(find.text('+4 st · 3M'), findsOneWidget);
    });
  });

  group('responsive layout (Rule 1)', () {
    for (final width in [360.0, 600.0, 900.0, 1280.0]) {
      testWidgets('audio harmonizer renders without overflow at $width dp',
          (tester) async {
        await pumpPanel(tester,
            asset: 'assets/plugins/audio_harmonizer.gfpd', width: width);
        expect(tester.takeException(), isNull);
      });

      testWidgets('midi harmonizer renders without overflow at $width dp',
          (tester) async {
        await pumpPanel(tester,
            asset: 'assets/plugins/harmonizer.gfpd', width: width);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
