// Widget tests for the Xen rack slot panel.
//
// Three things are worth pinning down here, and none of them is pixel layout:
//
//   1. **The gesture is reachable.** Tapping a scale button must travel
//      through RackState to the live plugin and come back as a changed LCD.
//      That is the whole module in one interaction, across four layers.
//   2. **The panel fits a phone.** Rule 1 — the grid holds 43 buttons across
//      seven families, exactly the content that overflows a 360 dp screen if
//      the tabs or the tonic strip fail to scroll.
//   3. **The two stages are separately reachable**, since the point of
//      splitting snap from tune is dropping one and keeping the other
//      mid-piece.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';
import 'package:grooveforge/widgets/rack/gfpa_xen_slot_ui.dart';

/// Builds the panel inside the providers it reads, runs [body], then tears the
/// tree down.
///
/// Disposal happens inside the test body rather than in `addTearDown`:
/// [RackState] starts a 10 ms MIDI FX ticker in its constructor, and the test
/// framework checks for pending timers before tear-downs run.
Future<void> withXenPanel(
  WidgetTester tester, {
  required double width,
  required Future<void> Function(RackState rack) body,
}) async {
  final engine = AudioEngine();
  final transport = TransportEngine();
  final graph = AudioGraph();
  final rack = RackState(engine, transport, graph);

  final slot = GFpaPluginInstance(
    id: 'slot-xen',
    pluginId: 'com.grooveforge.xen',
    midiChannel: 0,
  );
  rack.addPlugin(slot);

  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<RackState>.value(value: rack),
        ChangeNotifierProvider<AudioEngine>.value(value: engine),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(child: GFpaXenSlotUI(plugin: slot)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  try {
    await body(rack);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    rack.dispose();
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the gesture', () {
    testWidgets('tapping a scale drives the live plugin and the LCD',
        (tester) async {
      await withXenPanel(tester, width: 1000, body: (rack) async {
        expect(rack.xenPluginFor('slot-xen')!.scale.id, 'major');

        // Cross to the Maqam family and pick Rast — the headline case.
        await tester.tap(find.text('Maqam'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rast'));
        await tester.pumpAndSettle();

        expect(rack.xenPluginFor('slot-xen')!.scale.id, 'maqamRast');
        // Both the grid button and the LCD now say Rast.
        expect(find.text('Rast'), findsWidgets);
      });
    });

    testWidgets('the tonic strip sets the root', (tester) async {
      await withXenPanel(tester, width: 1000, body: (rack) async {
        await tester.tap(find.text('F#'));
        await tester.pumpAndSettle();
        expect(rack.xenPluginFor('slot-xen')!.rootPc, 6);
      });
    });

    testWidgets('the hint explains the gesture when nothing is held',
        (tester) async {
      await withXenPanel(tester, width: 1000, body: (rack) async {
        expect(find.text('Hold a note, then tap a scale'), findsOneWidget);
      });
    });

    testWidgets('tapping the LCD explains the module', (tester) async {
      await withXenPanel(tester, width: 1000, body: (rack) async {
        // The LCD is the panel's only explanatory surface; if it stops
        // opening, the module ships with an unreachable description.
        // "Major" appears twice — on the LCD and on its grid button. The
        // LCD's is the larger one.
        await tester.tap(find.text('Major').first);
        await tester.pumpAndSettle();
        expect(find.textContaining('Hold a note, tap a scale'), findsOneWidget);

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      });
    });
  });

  group('the two stages', () {
    testWidgets('snap and tune toggle independently', (tester) async {
      await withXenPanel(tester, width: 1000, body: (rack) async {
        final xen = rack.xenPluginFor('slot-xen')!;
        expect(xen.snapEnabled, isTrue);
        expect(xen.tuneEnabled, isTrue);

        await tester.tap(find.text('SNAP'));
        await tester.pumpAndSettle();
        expect(xen.snapEnabled, isFalse);
        expect(xen.tuneEnabled, isTrue,
            reason: 'dropping the lock must not drop the intonation');

        await tester.tap(find.text('TUNE'));
        await tester.pumpAndSettle();
        expect(xen.tuneEnabled, isFalse);
        expect(xen.snapEnabled, isFalse);
      });
    });
  });

  group('responsive layout (Rule 1)', () {
    for (final form in const [
      (name: 'phone portrait', width: 360.0),
      (name: 'tablet portrait', width: 700.0),
      (name: 'desktop', width: 1280.0),
    ]) {
      testWidgets('renders without overflow — ${form.name}', (tester) async {
        await withXenPanel(tester, width: form.width, body: (rack) async {
          expect(tester.takeException(), isNull);
          expect(find.byType(GFpaXenSlotUI), findsOneWidget);
        });
      });

      testWidgets('a scale stays tappable — ${form.name}', (tester) async {
        await withXenPanel(tester, width: form.width, body: (rack) async {
          await tester.tap(find.text('Blues'));
          await tester.pumpAndSettle();
          expect(rack.xenPluginFor('slot-xen')!.scale.id, 'blues');
          expect(tester.takeException(), isNull);
        });
      });
    }
  });

  group('every family is browsable', () {
    testWidgets('each tab lists its scales', (tester) async {
      await withXenPanel(tester, width: 1280, body: (rack) async {
        for (final tab in const [
          ('Maqam', 'Rast'),
          ('Raga', 'Yaman'),
          ('Far East', 'Hirajoshi'),
          ('Celtic', 'Highland Pipe'),
          ('Gamelan', 'Slendro'),
          ('Temperaments', 'Pythagorean'),
        ]) {
          await tester.tap(find.text(tab.$1));
          await tester.pumpAndSettle();
          expect(find.text(tab.$2), findsOneWidget,
              reason: '${tab.$1} must list ${tab.$2}');
        }
      });
    });
  });
}
