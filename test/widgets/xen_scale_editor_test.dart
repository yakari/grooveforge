// Tests for the custom scale editor and the library behind it.
//
// The editor's job is to make three shapes reachable that no preset covers,
// and those are what these tests pin down:
//
//   1. a subset that fits the octave, on the familiar keyboard layout;
//   2. a division that spreads across more keys than an octave has;
//   3. a scale with a coloured degree that sounds but is not a snap target.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/services/custom_scale_library.dart';
import 'package:grooveforge/widgets/rack/xen_scale_editor_dialog.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

Future<void> pumpEditor(
  WidgetTester tester, {
  required CustomScaleLibrary library,
  GFScale? initial,
  double width = 900,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<CustomScaleLibrary>.value(
      value: library,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: XenScaleEditorDialog(library: library, initial: initial),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GFScaleLibrary.clearCustom();
  });

  group('the editor opens and edits', () {
    testWidgets('a new scale starts with one degree', (tester) async {
      await pumpEditor(tester, library: CustomScaleLibrary());
      expect(find.text('Scale editor'), findsWidgets);
      expect(find.text('1 degrees, 1 active'), findsOneWidget);
    });

    testWidgets('degrees can be added and removed', (tester) async {
      await pumpEditor(tester, library: CustomScaleLibrary());

      await tester.tap(find.text('Add degree'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add degree'));
      await tester.pumpAndSettle();
      expect(find.text('3 degrees, 3 active'), findsOneWidget);

      // The list is not fixed at twelve rows in either direction.
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();
      expect(find.text('2 degrees, 2 active'), findsOneWidget);
    });

    testWidgets('an existing scale loads its degrees', (tester) async {
      await pumpEditor(
        tester,
        library: CustomScaleLibrary(),
        initial: GFScaleLibrary.maqamRast,
      );
      expect(find.text('7 degrees, 7 active'), findsOneWidget);
    });
  });

  group('muting', () {
    testWidgets('a muted degree still counts as a row but not as active',
        (tester) async {
      await pumpEditor(
        tester,
        library: CustomScaleLibrary(),
        initial: GFScaleLibrary.blues,
      );
      expect(find.text('6 degrees, 6 active'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.volume_up).first);
      await tester.pumpAndSettle();
      expect(find.text('6 degrees, 5 active'), findsOneWidget);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);
    });

    testWidgets('the saved scale keeps the mute', (tester) async {
      final library = CustomScaleLibrary();
      await pumpEditor(tester, library: library, initial: GFScaleLibrary.blues);

      await tester.tap(find.byIcon(Icons.volume_up).at(3));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = library.scales.single;
      expect(saved.degreeCount, 6);
      expect(saved.activeDegreeCount, 5);
      expect(saved.hasMutedDegrees, isTrue);
      // The whole point: the muted key still carries its tuning.
      expect(saved.family, GFScaleFamily.custom);
    });
  });

  group('layout', () {
    testWidgets('the layout can be switched to linear', (tester) async {
      final library = CustomScaleLibrary();
      await pumpEditor(
        tester,
        library: library,
        initial: GFScaleLibrary.majorPentatonic,
      );

      await tester.tap(find.text('Linear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = library.scales.single;
      expect(saved.mapping, GFScaleMapping.linear);
      // Five degrees now span five keys rather than an octave.
      expect(saved.keysPerPeriod, 5);
    });

    testWidgets('a 19-EDO seed keeps all nineteen degrees', (tester) async {
      // The player's own example: a division that spreads across the keyboard
      // rather than folding into twelve keys.
      final library = CustomScaleLibrary();
      await pumpEditor(tester, library: library, initial: GFScaleLibrary.edo19);
      expect(find.text('19 degrees, 19 active'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(library.scales.single.keysPerPeriod, 19);
    });
  });

  group('library', () {
    test('a saved scale is registered and resolvable by id', () async {
      SharedPreferences.setMockInitialValues({});
      final library = CustomScaleLibrary();
      const scale = GFScale(
        id: 'custom-test',
        name: 'Test',
        family: GFScaleFamily.custom,
        provenance: 'test',
        degrees: [GFScaleDegree(0), GFScaleDegree(7)],
      );

      await library.save(scale);
      // One lookup point for shipped, saved and imported scales alike.
      expect(GFScaleLibrary.byId('custom-test'), isNotNull);
      expect(GFScaleLibrary.byFamily(GFScaleFamily.custom), hasLength(1));
    });

    test('it survives a reload from preferences', () async {
      SharedPreferences.setMockInitialValues({});
      const scale = GFScale(
        id: 'custom-persist',
        name: 'Persisted',
        family: GFScaleFamily.custom,
        provenance: 'test',
        degrees: [GFScaleDegree(0), GFScaleDegree(6, -50.0, false)],
      );
      await CustomScaleLibrary().save(scale);

      GFScaleLibrary.clearCustom();
      final reloaded = CustomScaleLibrary();
      await reloaded.load();

      final restored = GFScaleLibrary.byId('custom-persist')!;
      expect(restored.name, 'Persisted');
      expect(restored.degrees[1].active, isFalse);
      expect(restored.degrees[1].cents, -50.0);
    });

    test('one corrupt entry does not cost the rest of the library', () async {
      SharedPreferences.setMockInitialValues({
        'xen_custom_scales':
            '[{"nonsense": true}, {"id":"ok","name":"OK","degrees":'
                '[{"semitone":0,"cents":0.0}]}]',
      });
      final library = CustomScaleLibrary();
      await library.load();
      expect(library.scales, hasLength(1));
      expect(library.scales.single.id, 'ok');
    });

    test('corrupt preferences start empty rather than refusing to launch',
        () async {
      SharedPreferences.setMockInitialValues({
        'xen_custom_scales': 'not json at all',
      });
      final library = CustomScaleLibrary();
      await library.load();
      expect(library.scales, isEmpty);
    });

    test('generated ids never collide with an existing scale', () {
      GFScaleLibrary.clearCustom();
      final first = CustomScaleLibrary.generateId('Blues');
      GFScaleLibrary.registerCustom(GFScale(
        id: first,
        name: 'Blues',
        family: GFScaleFamily.custom,
        provenance: 'test',
        degrees: const [GFScaleDegree(0)],
      ));
      final second = CustomScaleLibrary.generateId('Blues');
      // Colliding would silently repoint an existing CC pad mapping.
      expect(second, isNot(first));
      expect(GFScaleLibrary.byId(second), isNull);
    });

    test('export and import round-trip through JSON', () {
      const scale = GFScale(
        id: 'custom-rt',
        name: 'Round trip',
        family: GFScaleFamily.custom,
        provenance: 'test',
        mapping: GFScaleMapping.linear,
        periodCents: 1901.955,
        degrees: [
          GFScaleDegree(0),
          GFScaleDegree(1, 46.3),
          GFScaleDegree(2, -7.4, false),
        ],
      );
      final restored =
          CustomScaleLibrary.decodeExported(
              CustomScaleLibrary.encodeForExport(scale))!;

      expect(restored.id, scale.id);
      expect(restored.mapping, GFScaleMapping.linear);
      expect(restored.periodCents, closeTo(1901.955, 0.001));
      expect(restored.degrees[2].active, isFalse);
      expect(restored.tuningOffsetsFor(0), scale.tuningOffsetsFor(0));
    });

    test('a file that is not a scale is rejected, not thrown on', () {
      expect(CustomScaleLibrary.decodeExported('{'), isNull);
      expect(CustomScaleLibrary.decodeExported('[1,2,3]'), isNull);
      expect(CustomScaleLibrary.decodeExported('{"id":"x"}'), isNull);
    });
  });

  group('responsive layout (Rule 1)', () {
    for (final width in const [360.0, 700.0, 1280.0]) {
      testWidgets('renders without overflow at ${width.toInt()} dp',
          (tester) async {
        await pumpEditor(
          tester,
          library: CustomScaleLibrary(),
          initial: GFScaleLibrary.maqamRast,
          width: width,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
