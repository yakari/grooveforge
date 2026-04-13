// Scaffold tests for the Audio Harmonizer GFPA effect plugin.
//
// At this stage the plugin is a pure pass-through: the .gfpd descriptor
// declares 10 parameters and a graph that routes the input straight through
// a wet/dry crossfade. These tests pin down the descriptor-level contract
// (parameter list, defaults, plugin type) so that future DSP wiring cannot
// silently drop a parameter or change a default value.
//
// The full audio-rate pass-through verification will land alongside the
// phase-vocoder-backed `pv_harmonizer` DSP node in the next session.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio Harmonizer descriptor', () {
    late GFPluginDescriptor descriptor;

    setUpAll(() async {
      // Load the bundled descriptor through the asset bundle so the test
      // exercises the same code path as the real app startup.
      final yaml = await rootBundle
          .loadString('assets/plugins/audio_harmonizer.gfpd');
      final parsed = GFDescriptorLoader.parse(yaml);
      expect(parsed, isNotNull,
          reason: 'audio_harmonizer.gfpd must parse cleanly');
      descriptor = parsed!;
    });

    test('identity fields are correct', () {
      // The id is intentionally distinct from `com.grooveforge.harmonizer`,
      // which already exists as a MIDI FX plugin. Two plugins with the same
      // id would be silently de-duplicated by GFPluginRegistry.
      expect(descriptor.id, 'com.grooveforge.audio_harmonizer');
      expect(descriptor.name, 'Audio Harmonizer');
      expect(descriptor.type, GFPluginType.effect);
    });

    test('exposes the 10 expected parameters in order', () {
      // Order must match the paramId numbering in the .gfpd file so a
      // user-saved .gf project can map paramId → semantic role unambiguously.
      final ids = descriptor.parameters.map((p) => p.id).toList();
      expect(ids, [
        'voice_count',
        'voice1_semitones',
        'voice2_semitones',
        'voice3_semitones',
        'voice4_semitones',
        'voice1_mix',
        'voice2_mix',
        'voice3_mix',
        'voice4_mix',
        'dry_wet',
      ]);
    });

    test('default voice intervals are musically sensible', () {
      // Pin the harmonic intervals so future tweaks are deliberate:
      //   V1 = perfect fifth above (+7 st)
      //   V2 = octave above (+12 st)
      //   V3 = major third above (+4 st)
      //   V4 = perfect fourth below (-5 st)
      double def(String id) =>
          descriptor.parameters.firstWhere((p) => p.id == id).defaultValue;

      expect(def('voice1_semitones'), 7.0);
      expect(def('voice2_semitones'), 12.0);
      expect(def('voice3_semitones'), 4.0);
      expect(def('voice4_semitones'), -5.0);
    });

    test('voice count defaults to 2 with a 1..4 range', () {
      final p = descriptor.parameters
          .firstWhere((p) => p.id == 'voice_count');
      expect(p.min, 1.0);
      expect(p.max, 4.0);
      expect(p.defaultValue, 2.0);
    });

    test('master dry/wet is 0..1 with a 50/50 default', () {
      final p =
          descriptor.parameters.firstWhere((p) => p.id == 'dry_wet');
      expect(p.min, 0.0);
      expect(p.max, 1.0);
      expect(p.defaultValue, 0.5);
    });
  });
}
