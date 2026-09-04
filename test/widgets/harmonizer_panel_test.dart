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
    testWidgets('each voice gets its own lane, with an interval bar',
        (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);

      // One lane per voice plus the setup lane.
      for (final lane in ['Setup', 'V1', 'V2', 'V3', 'V4']) {
        expect(find.text(lane), findsOneWidget);
      }
      expect(find.byType(GFIntervalBar), findsNWidgets(4));

      // Defaults are +7, +12, +4 and -5 semitones, each shown as the count
      // and the interval it names.
      expect(find.text('+7 st'), findsOneWidget);
      expect(find.text('Perfect 5th'), findsOneWidget);
      expect(find.text('+12 st'), findsOneWidget);
      expect(find.text('Octave'), findsOneWidget);
      expect(find.text('+4 st'), findsOneWidget);
      expect(find.text('Major 3rd'), findsOneWidget);
      expect(find.text('-5 st'), findsOneWidget);
      expect(find.text('Perfect 4th'), findsOneWidget);
    });

    testWidgets('voice count is a segmented selector, not a knob',
        (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);

      // Every count is on screen as its own segment — the whole point of
      // the change: a four-position choice should not need a drag.
      expect(find.byType(GFOptionSelector), findsOneWidget);
      for (final n in ['1', '2', '3', '4']) {
        expect(find.text(n), findsOneWidget);
      }
    });

    testWidgets('each voice keeps its level in its own lane', (tester) async {
      // Pitch and level used to live in two separate groups, so V1's
      // interval sat four controls away from V1's level.
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);
      expect(find.text('Level'), findsNWidgets(4));

      for (final lane in ['V1', 'V2', 'V3', 'V4']) {
        final row = find.ancestor(
          of: find.text(lane),
          matching: find.byType(Row),
        );
        expect(
          find.descendant(of: row.first, matching: find.text('Level')),
          findsOneWidget,
          reason: '$lane should carry its own level control',
        );
      }
    });

    testWidgets('lanes past the voice count are dimmed', (tester) async {
      // The descriptor defaults to two voices, so V3 and V4 are silent and
      // must not look as live as V1 and V2.
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);

      double laneOpacity(String lane) {
        final opacity = find
            .ancestor(of: find.text(lane), matching: find.byType(Opacity))
            .first;
        return tester.widget<Opacity>(opacity).opacity;
      }

      expect(laneOpacity('V1'), 1.0);
      expect(laneOpacity('V2'), 1.0);
      expect(laneOpacity('V3'), lessThan(1.0));
      expect(laneOpacity('V4'), lessThan(1.0));
    });

    testWidgets('the step button moves the interval one semitone',
        (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);

      // V1 starts at a perfect fifth; one step up is a minor sixth.
      final bar = find.byType(GFIntervalBar).first;
      await tester.tap(find.descendant(
        of: bar,
        matching: find.byIcon(Icons.add),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('+8 st'), findsOneWidget);
      expect(find.text('Minor 6th'), findsOneWidget);
    });

    testWidgets('dragging the track moves the voice and keeps the value',
        (tester) async {
      // The first cut mirrored the value locally, compared the new value
      // against its own mirror, and so never told the host: the handle
      // followed the finger and then snapped back on release.
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);

      final track = find.descendant(
        of: find.byType(GFIntervalBar).first,
        matching: find.byType(CustomPaint),
      );

      await tester.drag(track.first, const Offset(60, 0));
      await tester.pump();
      await tester.pump();

      // Moved up, and stayed there after the finger left.
      expect(find.text('+7 st'), findsNothing);
      expect(find.textContaining('st'), findsWidgets);
      final moved = tester
          .widgetList<GFIntervalBar>(find.byType(GFIntervalBar))
          .first
          .value;
      expect(moved, greaterThan(7));
    });

    testWidgets('the readout carries a tooltip spelling the interval out',
        (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/audio_harmonizer.gfpd', width: 1280);

      final tooltip = tester.widgetList<Tooltip>(find.byType(Tooltip));
      expect(
        tooltip.map((t) => t.message),
        contains('Perfect 5th, 7 semitones above the played note'),
      );
    });
  });

  group('MIDI Harmonizer panel', () {
    testWidgets('four voice lanes and a count selector', (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/harmonizer.gfpd', width: 1280);

      for (final lane in ['Setup', 'V1', 'V2', 'V3', 'V4']) {
        expect(find.text(lane), findsOneWidget);
      }
      expect(find.byType(GFIntervalBar), findsNWidgets(4));
      expect(find.byType(GFOptionSelector), findsOneWidget);
      expect(find.text('+4 st'), findsOneWidget);
      expect(find.text('+7 st'), findsOneWidget);
      expect(find.text('+12 st'), findsOneWidget);
      expect(find.text('+16 st'), findsOneWidget);
      expect(find.text('Major 3rd +1 oct'), findsOneWidget);
    });

    testWidgets('French names the intervals its own way', (tester) async {
      await pumpPanel(tester,
          asset: 'assets/plugins/harmonizer.gfpd',
          width: 1280,
          locale: const Locale('fr'));
      expect(find.text('Quinte juste'), findsOneWidget);
      expect(find.text('Tierce majeure'), findsOneWidget);
    });
  });

  group('responsive layout (Rule 1)', () {
    for (final width in [360.0, 600.0, 900.0, 1280.0]) {
      testWidgets('audio harmonizer renders without overflow at $width dp',
          (tester) async {
        await pumpPanel(tester,
            asset: 'assets/plugins/audio_harmonizer.gfpd', width: width);
        expect(tester.takeException(), isNull);
        // The readout survives every width — below the track on a phone,
        // beside it on a tablet — rather than being dropped to make room.
        expect(find.text('+7 st'), findsOneWidget);
        expect(find.text('Perfect 5th'), findsOneWidget);
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
