// Tests for how the drum generator arranges a pattern over time.
//
// The generator used to decide every bar on its own: a new groove variation
// each bar, a break wherever a coin toss fell, a new "random" fill interval
// each bar. It sounded like a drummer changing their mind mid-phrase. It now
// plays in phrases, and these tests pin that down on the bundled patterns.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/models/drum_generator_plugin_instance.dart';
import 'package:grooveforge/models/drum_pattern_data.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/drum_arranger.dart';
import 'package:grooveforge/services/drum_generator_engine.dart';
import 'package:grooveforge/services/drum_pattern_parser.dart';
import 'package:grooveforge/services/drum_pattern_registry.dart';
import 'package:grooveforge/services/transport_engine.dart';

/// Parses the bundled pattern `assets/drums/[stem].gfdrum`.
DrumPatternData bundled(String stem) => DrumPatternParser.parse(
      File('assets/drums/$stem.gfdrum').readAsStringSync(),
      id: stem,
    )!;

/// The plans for bars 0 to [count] - 1.
List<DrumBarPlan> planBars(
  DrumPatternData pattern,
  DrumStructureConfig config, {
  int count = 200,
  int seed = 42,
}) =>
    [
      for (var bar = 0; bar < count; bar++)
        DrumArranger.planBar(
          bar: bar,
          config: config,
          pattern: pattern,
          seed: seed,
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final rock = bundled('rock_basic');
  final bossa = bundled('latin_bossa_nova');

  test('the groove keeps one variation for a whole phrase', () {
    const config = DrumStructureConfig(introType: DrumIntroType.none);
    final plans = planBars(rock, config);
    final seedsByPhrase = <int, Set<int>>{};
    for (final p in plans.where((p) => p.section == 'groove')) {
      seedsByPhrase.putIfAbsent(p.phraseIndex, () => {}).add(p.variationSeed);
    }
    for (final seeds in seedsByPhrase.values) {
      expect(seeds, hasLength(1));
    }
    // ...and still changes from one phrase to another.
    final grids = {
      for (final seeds in seedsByPhrase.values)
        DrumGeneratorEngine.resolveStepGrid(
          rock.sections['groove']!,
          barInSection: 0,
          variationSeed: seeds.single,
        ).toString(),
    };
    expect(grids.length, greaterThan(1));
  });

  test('a fill ends every phrase, and only there', () {
    const config = DrumStructureConfig(
      introType: DrumIntroType.countIn1,
      fillFrequency: DrumFillFrequency.every8,
    );
    final plans = planBars(rock, config);
    for (var bar = 1; bar < plans.length; bar++) {
      // Bar 0 is the count-in; the phrases start at bar 1.
      final isLastOfPhrase = (bar - 1) % 8 == 7;
      expect(plans[bar].section == 'fill', isLastOfPhrase, reason: 'bar $bar');
    }
  });

  test('random fills still fall on the last bar of a phrase', () {
    const config = DrumStructureConfig(
      introType: DrumIntroType.none,
      fillFrequency: DrumFillFrequency.random,
    );
    final plans = planBars(rock, config, count: 400);
    var phraseStart = 0;
    for (var bar = 0; bar < plans.length; bar++) {
      if (plans[bar].section != 'fill') continue;
      final length = bar - phraseStart + 1;
      expect(DrumArranger.randomPhraseBars, contains(length),
          reason: 'a phrase of $length bars ending at bar $bar');
      phraseStart = bar + 1;
    }
  });

  test('a break only opens a phrase, never the first one', () {
    const config = DrumStructureConfig(
      introType: DrumIntroType.none,
      breakFrequency: DrumBreakFrequency.frequent,
    );
    final plans = planBars(rock, config);
    final breaks = plans.where((p) => p.section == 'break').toList();
    expect(breaks, isNotEmpty, reason: 'the break section must now play');
    for (var bar = 0; bar < plans.length; bar++) {
      if (plans[bar].section != 'break') continue;
      expect(plans[bar].phraseIndex, greaterThan(0));
      // Rock's break is two bars, at the very start of the phrase.
      expect(bar % 8, lessThan(rock.sections['break']!.bars));
    }
  });

  test('the crash lands after the count-in, a fill or a break', () {
    const config = DrumStructureConfig(
      introType: DrumIntroType.countIn1,
      breakFrequency: DrumBreakFrequency.frequent,
    );
    final plans = planBars(rock, config);
    expect(plans[1].crash, isTrue, reason: 'first bar after the count-in');
    for (var bar = 1; bar < plans.length; bar++) {
      final previous = plans[bar - 1].section;
      final current = plans[bar].section;
      final landing = current == 'groove' &&
          (previous == 'fill' || previous == 'break' || previous == 'intro');
      expect(plans[bar].crash, landing, reason: 'bar $bar ($previous → $current)');
    }
  });

  test('no crash when the switch is off', () {
    const config = DrumStructureConfig(crashAfterFill: false);
    expect(planBars(rock, config).where((p) => p.crash), isEmpty);
  });

  test('a sequence starts on its first bar after a count-in', () {
    const config = DrumStructureConfig(introType: DrumIntroType.countIn1);
    final plan = DrumArranger.planBar(
      bar: 1,
      config: config,
      pattern: bossa,
      seed: 7,
    );
    expect(plan.section, 'groove');
    expect(plan.barInSection, 0);
    final groove = bossa.sections['groove']!;
    expect(
      DrumGeneratorEngine.resolveStepGrid(
        groove,
        barInSection: plan.barInSection,
        variationSeed: plan.variationSeed,
      ),
      groove.variations.first.barSequence!.first,
    );
  });

  test('dynamic build rises through the phrase, and only when switched on',
      () {
    const on = DrumStructureConfig(introType: DrumIntroType.none);
    final scales = planBars(rock, on, count: 7).map((p) => p.velocityScale);
    expect(scales.first, DrumArranger.buildStartScale);
    expect(scales.last, 1.0);
    expect(scales.toList(), orderedEquals(scales.toList()..sort()));

    const off = DrumStructureConfig(dynamicBuild: false);
    expect(planBars(rock, off).every((p) => p.velocityScale == 1.0), isTrue);
  });

  group('custom patterns', () {
    test('a custom file named like a bundled pattern does not replace it', () {
      DrumPatternRegistry.instance.register(rock);
      final engine = DrumGeneratorEngine(TransportEngine(), AudioEngine());
      final instance = DrumGeneratorPluginInstance(id: 'drums');
      engine.ensureSession('drums', instance);

      final yaml = File('assets/drums/disco.gfdrum').readAsStringSync();
      final loaded =
          engine.loadCustomPattern('drums', yaml, '/sdcard/rock_basic.gfdrum');

      expect(loaded, isTrue);
      expect(engine.patternFor('drums')!.id, 'custom:rock_basic');
      expect(DrumPatternRegistry.instance.find('rock_basic')!.name, rock.name,
          reason: 'the bundled Classic Rock must stay as it is');
      engine.dispose();
    });

    test('a project with a custom pattern plays it after reopening', () {
      final first = DrumGeneratorEngine(TransportEngine(), AudioEngine());
      final instance = DrumGeneratorPluginInstance(id: 'drums');
      first.ensureSession('drums', instance);
      final yaml = File('assets/drums/disco.gfdrum').readAsStringSync();
      first.loadCustomPattern('drums', yaml, '/tmp/gone/my_disco.gfdrum');
      final saved = instance.toJson();
      first.dispose();

      // A fresh start: the file is gone, only the project remains.
      final restored = DrumGeneratorPluginInstance.fromJson(saved);
      final second = DrumGeneratorEngine(TransportEngine(), AudioEngine());
      second.ensureSession('drums', restored);
      expect(second.patternFor('drums'), isNotNull);
      expect(second.patternFor('drums')!.id, 'custom:my_disco');
      second.dispose();
    });

    test('a file that is not a pattern is refused and changes nothing', () {
      DrumPatternRegistry.instance.register(rock);
      final engine = DrumGeneratorEngine(TransportEngine(), AudioEngine());
      final instance =
          DrumGeneratorPluginInstance(id: 'drums', builtinPatternId: 'rock_basic');
      engine.ensureSession('drums', instance);
      expect(engine.loadCustomPattern('drums', 'not: [a pattern', '/x.gfdrum'),
          isFalse);
      expect(instance.builtinPatternId, 'rock_basic');
      expect(engine.patternFor('drums')!.id, 'rock_basic');
      engine.dispose();
    });
  });
}
