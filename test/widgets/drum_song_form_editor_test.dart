// Widget tests for the drum song-form editor.
//
// Two things matter here:
//   1. Editing goes through the engine: adding a block, applying a template
//      and changing a block's length all land on the slot's saved form.
//   2. Nothing moves while the song plays. The block being played is lit and
//      the status line changes every bar; the card must keep its exact size,
//      or the whole rack below it jumps in time with the music.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/models/drum_generator_plugin_instance.dart';
import 'package:grooveforge/models/drum_song_form.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/drum_generator_engine.dart';
import 'package:grooveforge/services/drum_pattern_parser.dart';
import 'package:grooveforge/services/drum_pattern_registry.dart';
import 'package:grooveforge/services/transport_engine.dart';
import 'package:grooveforge/widgets/rack/drum_song_form_editor.dart';

const _pattern = '''
name: Test
family: rock
time_signature: [4, 4]
resolution: 16
instruments:
  kick: { note: 36 }
  crash: { note: 49 }
sections:
  groove:
    variations:
      - name: main
        kick: "X.......X......."
  fill:
    variations:
      - name: roll
        kick: "X.X.X.X.XXXXXXXX"
  crash:
    variations:
      - name: hit
        crash: "X..............."
''';

/// Builds the editor for a slot whose form is [form], at [width] pixels,
/// runs [body], then tears the tree down.
Future<void> withEditor(
  WidgetTester tester, {
  required double width,
  required DrumSongForm form,
  required Future<void> Function(
          DrumGeneratorEngine engine, DrumGeneratorPluginInstance plugin)
      body,
}) async {
  DrumPatternRegistry.instance
      .register(DrumPatternParser.parse(_pattern, id: 'editor_test')!);
  final transport = TransportEngine();
  final engine = DrumGeneratorEngine(transport, AudioEngine());
  final plugin = DrumGeneratorPluginInstance(
    id: 'drums',
    builtinPatternId: 'editor_test',
    songForm: form,
  );
  engine.ensureSession('drums', plugin);

  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<DrumGeneratorEngine>.value(value: engine),
        ChangeNotifierProvider<TransportEngine>.value(value: transport),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: engine,
              builder: (_, _) => DrumSongFormEditor(plugin: plugin),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  try {
    await body(engine, plugin);
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    engine.dispose();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('turning the form on starts from a real song shape',
      (tester) async {
    await withEditor(tester, width: 380, form: const DrumSongForm(),
        body: (engine, plugin) async {
      expect(find.text('Song form'), findsOneWidget);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(plugin.songForm.isActive, isTrue);
      expect(plugin.songForm.blocks.last.kind, DrumBlockKind.ending);
      expect(find.text('Chorus'), findsWidgets);
    });
  });

  testWidgets('a block added with + goes before the ending', (tester) async {
    await withEditor(tester,
        width: 800,
        form: DrumSongForm.fromTemplate(DrumSongTemplate.rock),
        body: (engine, plugin) async {
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bridge').last);
      await tester.pumpAndSettle();
      final kinds = plugin.songForm.blocks.map((b) => b.kind).toList();
      expect(kinds.last, DrumBlockKind.ending);
      expect(kinds[kinds.length - 2], DrumBlockKind.bridge);
    });
  });

  testWidgets('a template replaces the form, and a block can be edited',
      (tester) async {
    await withEditor(tester,
        width: 800,
        form: DrumSongForm.fromTemplate(DrumSongTemplate.jam),
        body: (engine, plugin) async {
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Blues'));
      await tester.pumpAndSettle();
      expect([for (final b in plugin.songForm.blocks) (b.kind, b.bars)].take(3),
          List.filled(3, (DrumBlockKind.verse, 12)));
      expect(plugin.songForm.blocks.last.kind, DrumBlockKind.ending);

      // Open the first block and shorten it by one bar.
      await tester.tap(find.text('Verse').first);
      await tester.pumpAndSettle();
      expect(find.text('Block 1: Verse'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(plugin.songForm.blocks.first.bars, 11);
    });
  });

  for (final width in [380.0, 800.0]) {
    testWidgets('the card keeps its size while the song plays ($width px)',
        (tester) async {
      await withEditor(tester,
          width: width,
          form: DrumSongForm.fromTemplate(DrumSongTemplate.pop),
          body: (engine, plugin) async {
        final card = find.byType(DrumSongFormEditor);
        final stopped = tester.getSize(card);
        // The engine publishes the play position on this notifier, once a
        // bar; step it through every bar of the song.
        final position =
            engine.formPositionFor('drums')! as ValueNotifier<DrumFormPosition?>;
        final blocks = plugin.songForm.blocks;
        for (var b = 0; b < blocks.length; b++) {
          for (var bar = 0; bar < blocks[b].bars; bar++) {
            position.value = DrumFormPosition(b, bar);
            await tester.pump();
            expect(tester.getSize(card), stopped,
                reason: 'block ${b + 1}, bar ${bar + 1}');
          }
        }
        position.value = null;
        await tester.pump();
        expect(tester.getSize(card), stopped);
      });
    });
  }
}
