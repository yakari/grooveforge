// Tests for the drum generator's song form: the user lays out a song as
// blocks (intro, verse, chorus, bridge, break, ending) and the drummer plays
// them one after the other.
//
// Most tests plan bars with the arranger on a small pattern written here, so
// each rule is checked against known variations. The last group drives the
// real engine with a running transport, to check that the ending stops it
// and that the editor is told which block is playing.

import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/models/drum_generator_plugin_instance.dart';
import 'package:grooveforge/models/drum_pattern_data.dart';
import 'package:grooveforge/models/drum_song_form.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/drum_arranger.dart';
import 'package:grooveforge/services/drum_form_arranger.dart';
import 'package:grooveforge/services/drum_generator_engine.dart';
import 'package:grooveforge/services/drum_pattern_parser.dart';
import 'package:grooveforge/services/drum_pattern_registry.dart';
import 'package:grooveforge/services/transport_engine.dart';

/// A small 4/4 pattern: a main groove (most likely), a busy one and a light
/// one; a one-bar fill; a crash bar. [extra] adds sections (break, ending).
String patternYaml({String extra = '', String roles = ''}) => '''
name: Test
family: rock
time_signature: [4, 4]
resolution: 16
instruments:
  kick: { note: 36 }
  snare: { note: 38 }
  hihat: { note: 42 }
  crash: { note: 49 }
sections:
  intro:
    type: count_in
    hits: 4
  groove:
    variations:
      - name: main
        weight: 3
        kick:  "X.......X......."
        snare: "....X.......X..."
        hihat: "x.x.x.x.x.x.x.x."
      - name: busy
        weight: 1
        kick:  "X.X...X.X.X...X."
        snare: "....X..x....X..x"
        hihat: "xxxxxxxxxxxxxxxx"
      - name: light
        weight: 1
        kick:  "X..............."
        hihat: "x...x...x...x..."
$roles
  fill:
    bars: 1
    variations:
      - name: roll
        snare: "....x.x.xxxxXXXX"
  crash:
    variations:
      - name: hit
        crash: "X..............."
        kick:  "X.......X......."
        hihat: "x.x.x.x.x.x.x.x."
$extra
''';

DrumPatternData parse(String yaml) =>
    DrumPatternParser.parse(yaml, id: 'test')!;

const noCountIn = DrumStructureConfig(
  introType: DrumIntroType.none,
  fillFrequency: DrumFillFrequency.every8,
);

/// Plans bars 0 to [count] - 1 of [form].
List<DrumBarPlan> plan(
  DrumSongForm form,
  DrumPatternData pattern, {
  DrumStructureConfig config = noCountIn,
  int count = 40,
}) =>
    [
      for (var bar = 0; bar < count; bar++)
        DrumArranger.planBar(
          bar: bar,
          config: config,
          pattern: pattern,
          seed: 7,
          form: form,
        ),
    ];

/// An audio engine that counts the drum hits instead of playing them: the
/// real one reaches native audio, which a unit test does not have.
class _CountingEngine extends AudioEngine {
  int hits = 0;

  @override
  void playNote({
    required int channel,
    required int key,
    required int velocity,
  }) =>
      hits++;

  @override
  void stopNote({required int channel, required int key}) {}
}

DrumSongForm formOf(List<DrumSongBlock> blocks) =>
    DrumSongForm(enabled: true, blocks: blocks);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pattern = parse(patternYaml());

  group('blocks', () {
    test('each bar belongs to its block, and a form without ending loops', () {
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 4),
        DrumSongBlock(kind: DrumBlockKind.chorus, bars: 2),
      ]);
      final plans = plan(form, pattern, count: 12);
      expect([for (final p in plans) p.blockIndex],
          [0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1]);
      expect([for (final p in plans) p.barInBlock],
          [0, 1, 2, 3, 0, 1, 0, 1, 2, 3, 0, 1]);
    });

    test('the count-in still comes first', () {
      final form = formOf(const [DrumSongBlock(kind: DrumBlockKind.verse)]);
      final plans = plan(form, pattern,
          config: const DrumStructureConfig(introType: DrumIntroType.countIn1));
      expect(plans[0].section, 'intro');
      expect(plans[0].blockIndex, -1);
      expect(plans[1].blockIndex, 0);
      expect(plans[1].barInBlock, 0);
    });

    test('a turned-off form leaves the phrase arranging as it was', () {
      const config = noCountIn;
      final form = formOf(const [DrumSongBlock(kind: DrumBlockKind.verse, bars: 2)])
          .copyWith(enabled: false);
      for (var bar = 0; bar < 20; bar++) {
        final withForm = DrumArranger.planBar(
            bar: bar, config: config, pattern: pattern, seed: 7, form: form);
        final without = DrumArranger.planBar(
            bar: bar, config: config, pattern: pattern, seed: 7);
        expect(withForm.section, without.section);
        expect(withForm.blockIndex, -1);
      }
    });
  });

  group('fills and crashes', () {
    test('a block ends with a fill, unless it asks for none', () {
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 4),
        DrumSongBlock(kind: DrumBlockKind.chorus, bars: 4, fillAtEnd: false),
      ]);
      final sections = [for (final p in plan(form, pattern, count: 8)) p.section];
      expect(sections, [
        'groove', 'groove', 'groove', 'fill', //
        'groove', 'groove', 'groove', 'groove',
      ]);
    });

    test('a block longer than the fill phrase gets fills inside it too', () {
      final form = formOf(const [DrumSongBlock(kind: DrumBlockKind.verse, bars: 16)]);
      final fills = [
        for (final p in plan(form, pattern, count: 16))
          if (p.section == 'fill') p.barInBlock,
      ];
      expect(fills, [7, 15]);

      const noFills = DrumStructureConfig(
          introType: DrumIntroType.none, fillFrequency: DrumFillFrequency.off);
      final onlyEnd = [
        for (final p in plan(form, pattern, config: noFills, count: 16))
          if (p.section == 'fill') p.barInBlock,
      ];
      expect(onlyEnd, [15]);
    });

    test('the crash lands after a fill and after the count-in, not on an intro',
        () {
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 2),
        DrumSongBlock(kind: DrumBlockKind.chorus, bars: 2),
        DrumSongBlock(kind: DrumBlockKind.intro, bars: 2),
      ]);
      final plans = plan(form, pattern,
          config: const DrumStructureConfig(introType: DrumIntroType.countIn1),
          count: 7);
      expect([for (final p in plans) p.crash],
          [false, true, false, true, false, false, false]);
    });

    test('no random break is drawn while a form is playing', () {
      const config = DrumStructureConfig(
        introType: DrumIntroType.none,
        breakFrequency: DrumBreakFrequency.frequent,
      );
      final withBreak = parse(patternYaml(extra: '''
  break:
    bars: 1
    variations:
      - name: drop
        kick: "X..............."
'''));
      final form = formOf(const [DrumSongBlock(kind: DrumBlockKind.verse, bars: 4)]);
      final plans = plan(form, withBreak, config: config, count: 80);
      expect(plans.any((p) => p.section == 'break'), isFalse);
    });
  });

  group('groove variations', () {
    final groove = pattern.sections['groove']!;

    test('without roles: verse = main, chorus = busiest, intro = lightest, '
        'bridge = another one', () {
      expect(DrumFormArranger.autoVariation(groove, DrumBlockKind.verse), 'main');
      expect(DrumFormArranger.autoVariation(groove, DrumBlockKind.chorus), 'busy');
      expect(DrumFormArranger.autoVariation(groove, DrumBlockKind.intro), 'light');
      expect(DrumFormArranger.autoVariation(groove, DrumBlockKind.bridge), 'light');
    });

    test('a role in the file wins over the guess', () {
      final tagged = parse(patternYaml().replaceFirst(
          '      - name: light\n', '      - name: light\n        role: chorus\n'));
      expect(
          DrumFormArranger.autoVariation(
              tagged.sections['groove']!, DrumBlockKind.chorus),
          'light');
    });

    test('a block plays its variation for every groove bar, and a forced one '
        'wins', () {
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.chorus, bars: 3),
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 3, variation: 'light'),
      ]);
      final plans = plan(form, pattern, count: 6);
      expect([for (final p in plans) p.variation],
          ['busy', 'busy', null, 'light', 'light', null]);
      // The engine plays the variation the plan names.
      final grid = DrumGeneratorEngine.resolveStepGrid(groove,
          barInSection: 0, variationSeed: 1, variation: 'busy');
      expect(grid!['hihat'], 'xxxxxxxxxxxxxxxx');
    });

    test('a forced variation the style does not have falls back to Auto', () {
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 2, variation: 'bonham'),
      ]);
      expect(plan(form, pattern, count: 1).single.variation, 'main');
    });
  });

  group('break', () {
    test('without a break section: a hit on beat 1, silence, then the pickup',
        () {
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.breakdown, bars: 3),
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 1),
      ]);
      final plans = plan(form, pattern, count: 4);
      expect([for (final p in plans) p.section],
          [DrumBarPlan.drop, DrumBarPlan.silence, 'fill', 'groove']);
      expect(plans[3].crash, isTrue, reason: 'the band comes back in');
    });

    test('the hit on beat 1 is the first step of the crash bar', () {
      final crash = DrumGeneratorEngine.resolveStepGrid(
          pattern.sections['crash']!,
          barInSection: 0,
          variationSeed: 0)!;
      expect(DrumGeneratorEngine.firstStepOf(crash), {
        'crash': 'X...............',
        'kick': 'X...............',
        'hihat': 'x...............',
      });
    });

    test("the style's own break is played when it has one", () {
      final withBreak = parse(patternYaml(extra: '''
  break:
    type: sequence
    bars: 2
    bar_grids:
      - kick: "X..............."
      - snare: "........xxxxXXXX"
'''));
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.breakdown, bars: 2, fillAtEnd: false),
      ]);
      final plans = plan(form, withBreak, count: 2);
      expect([for (final p in plans) (p.section, p.barInSection)],
          [('break', 0), ('break', 1)]);
    });
  });

  group('ending', () {
    test("plays the style's ending, then nothing", () {
      final withEnding = parse(patternYaml(extra: '''
  ending:
    type: sequence
    bars: 2
    bar_grids:
      - snare: "X.X.X.X.XXXXXXXX"
      - crash: "X..............."
        kick:  "X..............."
'''));
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 2, fillAtEnd: false),
        DrumSongBlock(kind: DrumBlockKind.ending, bars: 8),
      ]);
      expect(DrumFormArranger.formBars(form, withEnding), 4,
          reason: "the ending lasts as long as the style's section");
      final plans = plan(form, withEnding, count: 6);
      expect([for (final p in plans) p.section], [
        'groove', 'groove', 'ending', 'ending',
        DrumBarPlan.silence, DrumBarPlan.silence,
      ]);
      expect(plans[4].blockIndex, -1);
    });

    test('without an ending section: a fill, then the final hit', () {
      final form = formOf(const [
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 1),
        DrumSongBlock(kind: DrumBlockKind.ending),
      ]);
      expect([for (final p in plan(form, pattern, count: 4)) p.section],
          ['groove', 'fill', DrumBarPlan.drop, DrumBarPlan.silence]);
    });
  });

  group('editing and saving', () {
    test('a new block goes before the ending, and there is only one ending', () {
      var form = DrumSongForm.fromTemplate(DrumSongTemplate.pop);
      form = form.withAdded(DrumBlockKind.bridge).withAdded(DrumBlockKind.ending);
      expect(form.blocks.last.kind, DrumBlockKind.ending);
      expect(form.blocks[form.blocks.length - 2].kind, DrumBlockKind.bridge);
      expect(form.blocks.where((b) => b.kind == DrumBlockKind.ending),
          hasLength(1));
    });

    test('nothing moves past the ending, and the ending does not move', () {
      final form = DrumSongForm.fromTemplate(DrumSongTemplate.rock);
      final moved = form.withMoved(0, 99);
      expect(moved.blocks.last.kind, DrumBlockKind.ending);
      expect(moved.blocks[moved.blocks.length - 2].kind, DrumBlockKind.intro);
      expect(form.withMoved(form.blocks.length - 1, 0).blocks, form.blocks);
      expect(form.withDuplicated(form.blocks.length - 1).blocks, form.blocks);
    });

    test('the form is saved with the slot and read back', () {
      final instance = DrumGeneratorPluginInstance(
        id: 'drums',
        songForm: formOf(const [
          DrumSongBlock(kind: DrumBlockKind.intro, bars: 4),
          DrumSongBlock(kind: DrumBlockKind.chorus, bars: 6, variation: 'busy'),
          DrumSongBlock(kind: DrumBlockKind.breakdown, bars: 2, fillAtEnd: false),
          DrumSongBlock(kind: DrumBlockKind.ending, stopTransport: false),
        ]),
      );
      final back = DrumGeneratorPluginInstance.fromJson(instance.toJson())
          .songForm;
      expect(back.enabled, isTrue);
      expect([for (final b in back.blocks) b.toJson()],
          [for (final b in instance.songForm.blocks) b.toJson()]);
    });

    test('a project from before song forms opens without one', () {
      final json = DrumGeneratorPluginInstance(id: 'drums').toJson();
      expect(json.containsKey('songForm'), isFalse);
      final back = DrumGeneratorPluginInstance.fromJson(json);
      expect(back.songForm.isActive, isFalse);
    });

    test('an ending saved in the middle is dropped on load', () {
      final form = DrumSongForm.fromJson({
        'enabled': true,
        'blocks': [
          {'kind': 'ending'},
          {'kind': 'verse', 'bars': 4},
        ],
      });
      expect(form.blocks.map((b) => b.kind), [DrumBlockKind.verse]);
    });
  });

  group('engine', () {
    // These play for real: the transport clock runs on wall time. A fast
    // tempo keeps them short.
    late TransportEngine transport;
    late DrumGeneratorEngine engine;
    late DrumGeneratorPluginInstance instance;
    late _CountingEngine audio;

    setUp(() {
      DrumPatternRegistry.instance.register(
          DrumPatternParser.parse(patternYaml(), id: 'song_form_test')!);
      transport = TransportEngine()..bpm = 300;
      audio = _CountingEngine();
      engine = DrumGeneratorEngine(transport, audio);
      instance = DrumGeneratorPluginInstance(
        id: 'drums',
        builtinPatternId: 'song_form_test',
        isActive: true,
        structureConfig: const DrumStructureConfig(introType: DrumIntroType.none),
      );
      engine.ensureSession('drums', instance);
    });

    tearDown(() {
      transport.stop();
      engine.dispose();
    });

    /// Waits until [done] or [timeout], checking every 20 ms.
    Future<void> waitFor(bool Function() done,
        {Duration timeout = const Duration(seconds: 5)}) async {
      final end = DateTime.now().add(timeout);
      while (!done() && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    test('the ending stops the transport, and the editor follows the blocks',
        () async {
      engine.setSongForm('drums', formOf(const [
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 1, fillAtEnd: false),
        DrumSongBlock(kind: DrumBlockKind.ending),
      ]));
      final seen = <DrumFormPosition>{};
      final position = engine.formPositionFor('drums')!;
      void record() {
        final p = position.value;
        if (p != null) seen.add(p);
      }
      position.addListener(record);

      transport.play();
      // 1 verse bar + 2 ending bars at 300 BPM: 2.4 s.
      await waitFor(() => !transport.isPlaying);
      position.removeListener(record);

      expect(transport.isPlaying, isFalse, reason: 'the ending stops the song');
      expect(seen, {
        const DrumFormPosition(0, 0),
        const DrumFormPosition(1, 0),
        const DrumFormPosition(1, 1),
      });
      expect(position.value, isNull);
    });

    test('with "stop the transport" off, the drums go quiet but the song '
        'goes on', () async {
      engine.setSongForm('drums', formOf(const [
        DrumSongBlock(kind: DrumBlockKind.verse, bars: 1, fillAtEnd: false),
        DrumSongBlock(kind: DrumBlockKind.ending, stopTransport: false),
      ]));
      transport.play();
      // Past the ending (3 bars = 2.4 s) and one more bar.
      await Future<void>.delayed(const Duration(milliseconds: 3200));
      final hitsAfterEnding = audio.hits;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(transport.isPlaying, isTrue);
      expect(audio.hits, hitsAfterEnding, reason: 'the drums are quiet');
      expect(hitsAfterEnding, greaterThan(0));
      expect(engine.formPositionFor('drums')!.value, isNull,
          reason: 'past the ending, no block is playing');
    });
  });
}
