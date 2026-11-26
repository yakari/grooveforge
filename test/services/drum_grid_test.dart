// Tests for how the drum generator reads and plays its grids:
//   - swing on eighth notes (jazz) as well as on sixteenths (funk);
//   - grids that span two bars (a clave, a bossa nova);
//   - triplet grids inside a 4/4 bar (a shuffle's middle note);
//   - the crash laid over the groove without doubling its notes;
//   - the drum kit a style asks for.

import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/models/drum_generator_plugin_instance.dart';
import 'package:grooveforge/models/drum_pattern_data.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/drum_generator_engine.dart';
import 'package:grooveforge/services/drum_pattern_parser.dart';
import 'package:grooveforge/services/drum_pattern_registry.dart';
import 'package:grooveforge/services/transport_engine.dart';

/// Records every note the drum generator plays, with the transport position
/// at that moment. Never reaches the real synth.
class _RecordingEngine extends AudioEngine {
  final List<({int key, double beat, int velocity})> notes = [];
  TransportEngine? transport;

  @override
  void playNote({
    required int channel,
    required int key,
    required int velocity,
  }) =>
      notes.add((
        key: key,
        beat: transport?.positionInBeats ?? 0,
        velocity: velocity,
      ));

  @override
  void stopNote({required int channel, required int key}) {}
}

/// A 4/4 pattern whose groove is [groove] (YAML lines of one variation)
/// and whose top-level keys include [header].
String patternYaml({required String groove, String header = ''}) => '''
name: Grid test
family: rock
time_signature: [4, 4]
resolution: 16
$header
instruments:
  kick: { note: 36 }
  snare: { note: 38 }
  hihat: { note: 42 }
  crash: { note: 49 }
sections:
  intro:
    type: count_in
    hits: 4
    note: 37
  groove:
    variations:
      - name: main
$groove
  crash:
    variations:
      - name: hit
        crash: "X..............."
        kick:  "X..............."
''';

DrumPatternData parse(String yaml) =>
    DrumPatternParser.parse(yaml, id: 'grid_test')!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('swing', () {
    test('an eighth-note swing moves the "and" to the last third of the beat',
        () {
      double swung(double beat) =>
          DrumGeneratorEngine.swungBeat(beat, 2 / 3, 1.0);
      expect(swung(0.0), 0.0);
      expect(swung(0.5), closeTo(2 / 3, 1e-9)); // the "and" of beat 1
      expect(swung(1.5), closeTo(1 + 2 / 3, 1e-9)); // the "and" of beat 2
      // The "e" and the "a" move with it and stay in order.
      expect(swung(0.25), closeTo(1 / 3, 1e-9));
      expect(swung(0.75), closeTo(2 / 3 + 1 / 6, 1e-9));
    });

    test('a sixteenth swing moves only the second sixteenth of each eighth',
        () {
      double swung(double beat) =>
          DrumGeneratorEngine.swungBeat(beat, 2 / 3, 0.5);
      expect(swung(0.5), 0.5); // the "and" stays put
      expect(swung(0.25), closeTo(1 / 3, 1e-9));
      expect(swung(0.75), closeTo(0.5 + 1 / 3, 1e-9));
    });

    test('a straight ratio leaves the grid alone', () {
      expect(DrumGeneratorEngine.swungBeat(0.75, 0.5, 1.0), 0.75);
    });

    test('swing_unit 8 is read from the file, 16 is the default', () {
      expect(
          parse(patternYaml(groove: '        kick: "X..............."'))
              .swingUnit,
          DrumSwingUnit.sixteenth);
      expect(
          parse(patternYaml(
                  header: 'swing_unit: 8',
                  groove: '        kick: "X..............."'))
              .swingUnit,
          DrumSwingUnit.eighth);
    });
  });

  group('human feel', () {
    test('the middle of the knob plays the file as written', () {
      expect(DrumGeneratorEngine.humanFactorOf(0), 0);
      expect(DrumGeneratorEngine.humanFactorOf(0.5), 1);
      expect(DrumGeneratorEngine.humanFactorOf(1), 2);
    });

    test('ghost notes start dropping out past the middle', () {
      expect(DrumGeneratorEngine.ghostSkipChance(1), 0);
      expect(DrumGeneratorEngine.ghostSkipChance(2), 0.25);
    });

    test('the energy drifts slowly, within the file\'s velocity_drift', () {
      final wave = [
        for (var bar = 0; bar < 16; bar++)
          DrumGeneratorEngine.driftScale(bar: bar, drift: 0.1, seed: 123),
      ];
      for (final v in wave) {
        expect(v, inInclusiveRange(0.9, 1.1));
      }
      // One full rise and fall every 8 bars.
      expect(wave[8], closeTo(wave[0], 1e-9));
      expect(wave.toSet().length, greaterThan(4));
      expect(DrumGeneratorEngine.driftScale(bar: 3, drift: 0, seed: 1), 1.0);
    });
  });

  group('grids', () {
    test('spaces and bars in a grid only help the eye', () {
      final pattern = parse(patternYaml(
          groove: '        kick: "X... X... | X.X. ...."'));
      final v = pattern.sections['groove']!.variations.single;
      expect(v.stepGrids['kick'], 'X...X...X.X.....');
      expect(v.bars, 1);
    });

    test('a two-bar grid makes a two-bar variation, a shorter one repeats',
        () {
      final pattern = parse(patternYaml(groove: '''
        kick:  "X.....X.....X... | ....X...X......."
        hihat: "x.x.x.x.x.x.x.x."'''));
      final v = pattern.sections['groove']!.variations.single;
      expect(v.bars, 2);
      final bar1 = DrumGeneratorEngine.barOf(v, 0);
      final bar2 = DrumGeneratorEngine.barOf(v, 1);
      expect(bar1['kick'], 'X.....X.....X...');
      expect(bar2['kick'], '....X...X.......');
      expect(bar1['hihat'], 'x.x.x.x.x.x.x.x.');
      expect(bar2['hihat'], 'x.x.x.x.x.x.x.x.');
      // Bar 3 starts the pattern again.
      expect(DrumGeneratorEngine.barOf(v, 2)['kick'], 'X.....X.....X...');
    });

    test('grid: triplet splits each beat in three, 12 steps in 4/4', () {
      final pattern = parse(patternYaml(groove: '''
        grid: triplet
        hihat: "x.x x.x x.x x.x"
        snare: ".g. Xg. .g. Xg."'''));
      final v = pattern.sections['groove']!.variations.single;
      expect(v.subdivision, DrumSubdivision.triplet);
      expect(v.bars, 1);
      expect(pattern.stepsPerBar(DrumSubdivision.triplet), 12);
      expect(DrumGeneratorEngine.barOf(v, 0).subdivision,
          DrumSubdivision.triplet);
    });

    test('a sequence bar can be a triplet bar', () {
      final yaml = patternYaml(groove: '        kick: "X..............."')
          .replaceFirst('''
  crash:
    variations:''', '''
  fill:
    type: sequence
    bars: 2
    bar_grids:
      - snare: "....X.......X..."
      - grid: triplet
        snare: "xxx xxx xxx XXX"
  crash:
    variations:''');
      final fill = parse(yaml).sections['fill']!;
      final bar2 = DrumGeneratorEngine.resolveStepGrid(fill,
          barInSection: 1, variationSeed: 0)!;
      expect(bar2.subdivision, DrumSubdivision.triplet);
      expect(bar2['snare'], 'xxxxxxxxxXXX');
    });
  });

  group('crash overlay', () {
    test('a hit both grids play sounds once, at the stronger level', () {
      final main = DrumBarGrid({'kick': 'x.......X.......', 'hihat': 'x.x.'});
      final crash = DrumBarGrid({'crash': 'X...', 'kick': 'X...............'});
      final merged = DrumGeneratorEngine.mergeOverlay(main, crash);
      expect(merged, hasLength(1));
      expect(merged.single['kick'], 'X.......X.......');
      expect(merged.single['crash'], 'X...');
      expect(merged.single['hihat'], 'x.x.');
    });

    test('a crash on beat 1 merges into a triplet bar too', () {
      final main = DrumBarGrid({'kick': 'X.....x.....'},
          subdivision: DrumSubdivision.triplet);
      final crash = DrumBarGrid(
          {'crash': 'X...............', 'kick': 'X...............'});
      final merged = DrumGeneratorEngine.mergeOverlay(main, crash);
      expect(merged, hasLength(1));
      expect(merged.single.subdivision, DrumSubdivision.triplet);
      expect(merged.single['kick'], 'X.....x.....');
      expect(merged.single['crash'], 'X...........');
    });

    test('a straight overlay with more than beat 1 stays apart', () {
      final main = DrumBarGrid({'kick': 'X...........'},
          subdivision: DrumSubdivision.triplet);
      final other = DrumBarGrid({'snare': '....X.......X...'});
      expect(DrumGeneratorEngine.mergeOverlay(main, other), hasLength(2));
    });
  });

  group('engine', () {
    // These play for real: the transport clock runs on wall time. A fast
    // tempo keeps them short.
    late TransportEngine transport;
    late DrumGeneratorEngine engine;
    late _RecordingEngine audio;

    DrumGeneratorPluginInstance start(
      String yaml,
      DrumIntroType intro, {
      double human = 0.5,
      double? swing,
    }) {
      DrumPatternRegistry.instance
          .register(DrumPatternParser.parse(yaml, id: 'grid_test')!);
      transport = TransportEngine()..bpm = 300;
      audio = _RecordingEngine()..transport = transport;
      engine = DrumGeneratorEngine(transport, audio);
      final instance = DrumGeneratorPluginInstance(
        id: 'drums',
        builtinPatternId: 'grid_test',
        isActive: true,
        humanizationAmount: human,
        swingOverride: swing,
        structureConfig: DrumStructureConfig(
          introType: intro,
          fillFrequency: DrumFillFrequency.off,
          // The phrase's rising velocity would blur the velocity checks.
          dynamicBuild: false,
        ),
      );
      engine.ensureSession('drums', instance);
      return instance;
    }

    tearDown(() {
      transport.stop();
      engine.dispose();
    });

    /// Plays until [count] notes of [key] were heard, or 5 s went by.
    Future<void> playUntil(int key, int count) async {
      transport.play();
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (audio.notes.where((n) => n.key == key).length < count &&
          DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      transport.stop();
    }

    test('the bar after the count-in crashes without a second kick on 1',
        () async {
      start(patternYaml(groove: '        kick: "X.......X......."'),
          DrumIntroType.countIn1);
      // Count-in bar, crash bar, and the first kick of the bar after.
      await playUntil(36, 3);
      final kicks = [for (final n in audio.notes) if (n.key == 36) n.beat];
      expect(audio.notes.where((n) => n.key == 49), hasLength(1));
      // Before the merge, the groove's kick and the crash's kick fired in
      // the same instant.
      expect(kicks.toSet(), hasLength(kicks.length));
    });

    test('a two-bar variation plays its two bars in turn', () async {
      start(
          patternYaml(groove: '''
        kick:  "X............... | ................"
        snare: "................ | X..............."'''),
          DrumIntroType.none);
      await playUntil(38, 2);
      final order = [
        for (final n in audio.notes)
          if (n.key == 36 || n.key == 38) n.key,
      ];
      expect(order.take(4), [36, 38, 36, 38]);
    });

    /// Gaps in beats between the hi-hat notes heard so far.
    List<double> hihatGaps() {
      final beats = [for (final n in audio.notes) if (n.key == 42) n.beat];
      return [for (var i = 1; i < beats.length; i++) beats[i] - beats[i - 1]];
    }

    const eighths = '''
        hihat: "x.x.x.x.x.x.x.x."''';

    test('the Swing knob swings a straight style', () async {
      // Robotic human feel, so only the swing moves the notes. At 300 BPM a
      // tick of the clock is a twentieth of a beat; a triplet swing makes
      // the gaps 0.67 and 0.33 beat long, far apart from that.
      start(patternYaml(header: 'swing_unit: 8', groove: eighths),
          DrumIntroType.none, human: 0, swing: 2 / 3);
      await playUntil(42, 9);
      final gaps = hihatGaps();
      final longs = [for (var i = 0; i < gaps.length; i += 2) gaps[i]];
      final shorts = [for (var i = 1; i < gaps.length; i += 2) gaps[i]];
      double mean(List<double> l) => l.reduce((a, b) => a + b) / l.length;
      expect(mean(longs) - mean(shorts), greaterThan(0.2));
    });

    test('without swing the hi-hat eighths stay even', () async {
      start(patternYaml(header: 'swing_unit: 8', groove: eighths),
          DrumIntroType.none, human: 0);
      await playUntil(42, 9);
      for (final gap in hihatGaps()) {
        expect(gap, closeTo(0.5, 0.12));
      }
    });

    test('Human feel at 0 plays every hit alike, at 100 % it spreads', () async {
      final yaml = patternYaml(groove: '''
        hihat: "X.X.X.X.X.X.X.X."''');
      Future<Set<int>> velocities(double human) async {
        start(yaml, DrumIntroType.none, human: human);
        await playUntil(42, 16);
        return {for (final n in audio.notes) if (n.key == 42) n.velocity};
      }

      final robotic = await velocities(0);
      engine.dispose(); // the second engine is disposed by tearDown
      final live = await velocities(1);
      expect(robotic, hasLength(1));
      expect(live.length, greaterThan(3));
    });

    test('a project opened over the slot replaces the instance it plays', () {
      DrumPatternRegistry.instance.register(DrumPatternParser.parse(
          patternYaml(groove: eighths), id: 'grid_test')!);
      DrumPatternRegistry.instance.register(DrumPatternParser.parse(
          patternYaml(groove: eighths).replaceFirst('Grid test', 'Other'),
          id: 'grid_other')!);
      transport = TransportEngine();
      audio = _RecordingEngine();
      engine = DrumGeneratorEngine(transport, audio);
      engine.ensureSession('drums',
          DrumGeneratorPluginInstance(id: 'drums', builtinPatternId: 'grid_test'));
      // The opened project has its own instance for the same slot id.
      final opened =
          DrumGeneratorPluginInstance(id: 'drums', builtinPatternId: 'grid_other');
      engine.ensureSession('drums', opened);
      expect(engine.patternFor('drums')!.name, 'Other');
      // Its settings are the ones the engine now reads.
      engine.loadBuiltinPattern('drums', 'grid_test');
      expect(opened.builtinPatternId, 'grid_test');
    });

    test('the style\'s kit is selected when the soundfont has it', () {
      const sf = '/fake/kits.sf2';
      final yaml = patternYaml(
          header: 'kit: brush', groove: '        kick: "X..............."');
      DrumPatternRegistry.instance
          .register(DrumPatternParser.parse(yaml, id: 'grid_test')!);
      transport = TransportEngine();
      audio = _RecordingEngine();
      final instance = DrumGeneratorPluginInstance(
          id: 'drums', builtinPatternId: 'grid_test', isActive: true);
      final channel = instance.midiChannel - 1;
      audio.channels[channel].soundfontPath = sf;
      engine = DrumGeneratorEngine(transport, audio);

      // A soundfont without the brush kit: the standard kit.
      audio.sf2Presets[sf] = {
        128: {0: 'Standard'},
      };
      engine.ensureSession('drums', instance);
      expect(audio.channels[channel].program, 0);
      expect(audio.channels[channel].bank, 128);

      // One with it: the brush kit.
      audio.sf2Presets[sf] = {
        128: {0: 'Standard', 40: 'Brush'},
      };
      engine.loadBuiltinPattern('drums', 'grid_test');
      expect(audio.channels[channel].program, DrumKit.brush.program);
    });
  });
}
