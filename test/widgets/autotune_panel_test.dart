// Widget tests for the Autotune panel: the live note display and the
// generated controls at a phone's width.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge_plugin_ui/grooveforge_plugin_ui.dart';

import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/models/autotune_pitch.dart';
import 'package:grooveforge/widgets/rack/autotune_pitch_display.dart';
import 'package:grooveforge/widgets/rack/gfpa_param_readout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded once up front: a second rootBundle read from inside a
  // testWidgets body deadlocks the harness.
  late GFPluginDescriptor descriptor;
  setUpAll(() async {
    descriptor = GFDescriptorLoader.parse(
        await rootBundle.loadString('assets/plugins/autotune.gfpd'))!;
  });

  Widget app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: SingleChildScrollView(child: child),
        ),
      );

  group('AutotunePitchDisplay', () {
    testWidgets('asks for a voice when nothing is heard', (tester) async {
      await tester.pumpWidget(app(
        AutotunePitchDisplay(read: () => AutotunePitch.silent),
      ));
      expect(find.text('Sing something…'), findsOneWidget);
    });

    testWidgets('shows the note sung, how far off, and the target',
        (tester) async {
      await tester.pumpWidget(app(
        AutotunePitchDisplay(
          read: () => const AutotunePitch(
              inputNote: 57.3, targetNote: 57, correction: -0.3),
        ),
      ));
      expect(find.text('A3'), findsNWidgets(2));
      expect(find.text('+30 ¢'), findsOneWidget);
    });

    testWidgets('follows the voice as the DSP readings change',
        (tester) async {
      var reading = AutotunePitch.silent;
      await tester.pumpWidget(app(AutotunePitchDisplay(read: () => reading)));
      expect(find.text('Sing something…'), findsOneWidget);

      reading = const AutotunePitch(
          inputNote: 60.1, targetNote: 60, correction: -0.1);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('C4'), findsNWidgets(2));
      expect(find.text('Sing something…'), findsNothing);
    });

    testWidgets('names notes in solfège when asked', (tester) async {
      await tester.pumpWidget(app(
        AutotunePitchDisplay(
          solfege: true,
          read: () => const AutotunePitch(
              inputNote: 69, targetNote: 69, correction: 0),
        ),
        locale: const Locale('fr'),
      ));
      expect(find.text('La3'), findsNWidgets(2));
    });

    testWidgets('says when a patched scale is in charge', (tester) async {
      await tester.pumpWidget(app(
        AutotunePitchDisplay(
          scalePatched: true,
          read: () => AutotunePitch.silent,
        ),
      ));
      expect(find.text('Following the patched scale'), findsOneWidget);
    });
  });

  group('Autotune controls', () {
    Future<void> pumpPanel(WidgetTester tester, double width,
        {bool Function(GFDescriptorControlGroup)? laneEnabled}) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final plugin = GFDescriptorPlugin(descriptor);
      await tester.pumpWidget(app(Builder(builder: (ctx) {
        final l10n = AppLocalizations.of(ctx)!;
        return GFDescriptorPluginUI(
          plugin: plugin,
          paramNotifier: ValueNotifier<int>(0),
          valueFormatter: (param, raw) => gfpaParamReadout(l10n, param, raw),
          laneEnabled: laneEnabled,
        );
      })));
      await tester.pump();
      await tester.pump();
    }

    for (final width in [360.0, 768.0, 1280.0]) {
      testWidgets('lays out without overflow at $width px', (tester) async {
        await pumpPanel(tester, width);
        expect(tester.takeException(), isNull);
        for (final lane in ['Notes', 'Tune', 'Voice']) {
          expect(find.text(lane), findsOneWidget);
        }
      });
    }

    testWidgets('knobs print their values with units', (tester) async {
      await pumpPanel(tester, 1280);
      expect(find.text('100 %'), findsNWidgets(2)); // strength and mix
      expect(find.text('0 ms'), findsOneWidget);
    });

    testWidgets('a patched scale dims only the key and scale lane',
        (tester) async {
      await pumpPanel(tester, 1280,
          laneEnabled: (g) =>
              !g.controls.any((c) => c.paramId == 'key' || c.paramId == 'scale'));

      double laneOpacity(String lane) => tester
          .widget<Opacity>(find
              .ancestor(of: find.text(lane), matching: find.byType(Opacity))
              .first)
          .opacity;
      expect(laneOpacity('Notes'), lessThan(1.0));
      expect(laneOpacity('Tune'), 1.0);
    });
  });
}
