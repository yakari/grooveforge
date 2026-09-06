// End-to-end test for the Audio Harmonizer's CHORD IN jack.
//
// The point is the whole path, not any one method: a chord held on a keyboard
// patched into the harmonizer must arrive as changed *parameter values*, since
// that is what makes the interval lanes show it and stay editable. Earlier
// attempts failed somewhere between the keyboard and the parameters while
// every layer looked correct on its own.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded once: rootBundle reads hang the second test in a file.
  late GFPluginDescriptor descriptor;
  setUpAll(() async {
    // The app does this at startup; without it the descriptor's graph cannot
    // be built and the effect never initialises.
    GFDescriptorLoader.registerBuiltinNodes();
    GFDescriptorLoader.registerBuiltinMidiNodes();
    final midiYaml =
        await rootBundle.loadString('assets/plugins/harmonizer.gfpd');
    final midiDesc = GFDescriptorLoader.parse(midiYaml)!;
    GFPluginRegistry.instance.register(GFMidiDescriptorPlugin(midiDesc));
    final yaml =
        await rootBundle.loadString('assets/plugins/audio_harmonizer.gfpd');
    descriptor = GFDescriptorLoader.parse(yaml)!;
    GFPluginRegistry.instance.register(GFDescriptorPlugin(descriptor));
  });

  /// Physical value of the parameter named [id] on the harmonizer slot.
  double paramOf(RackState rack, String id) {
    final plugin = rack.audioEffectInstanceForSlot('harm')!;
    final p = descriptor.parameters.firstWhere((e) => e.id == id);
    return p.min + plugin.getParameter(p.paramId) * (p.max - p.min);
  }

  /// Holds [notes] on engine channel 0 through the engine's own note path.
  ///
  /// Deliberately not `channels[0].activeNotes.value = ...`: that skips the
  /// engine, and skipping it is what hid the real defect — a project load
  /// replaces the ChannelState objects, orphaning anything attached to their
  /// notifiers.
  Future<void> holdChord(AudioEngine engine, List<int> notes) async {
    for (final n in notes) {
      engine.noteOnUiOnly(channel: 0, key: n);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }

  /// A rack holding a keyboard on MIDI channel 1 and a harmonizer.
  Future<RackState> buildRack(AudioEngine engine) async {
    final rack = RackState(engine, TransportEngine(), AudioGraph());
    rack.addPlugin(GFpaPluginInstance(
      id: 'kb',
      pluginId: 'com.grooveforge.keyboard',
      midiChannel: 1,
    ));
    rack.addPlugin(GFpaPluginInstance(
      id: 'harm',
      pluginId: 'com.grooveforge.audio_harmonizer',
      midiChannel: 1,
    ));
    rack.addPlugin(GFpaPluginInstance(
      id: 'midiharm',
      pluginId: 'com.grooveforge.harmonizer',
      midiChannel: 1,
    ));
    // Audio-effect plugins initialise asynchronously.
    await Future<void>.delayed(Duration.zero);
    return rack;
  }

  test('a chord held on a patched keyboard sets the voice intervals',
      () async {
    final engine = AudioEngine();
    final rack = await buildRack(engine);
    expect(rack.audioEffectInstanceForSlot('harm'), isNotNull,
        reason: 'the harmonizer effect must initialise for this to mean '
            'anything');

    rack.setChordSource('harm', 'kb');

    // C major on channel 1 (index 0): the C is the singer's, E and G are the
    // two harmony voices.
    await holdChord(engine, const [60, 64, 67]);

    expect(paramOf(rack, 'voice_count'), 2);
    expect(paramOf(rack, 'voice1_semitones'), 4);
    expect(paramOf(rack, 'voice2_semitones'), 7);

    rack.dispose();
  });

  test('releasing the keys leaves the intervals standing', () async {
    final engine = AudioEngine();
    final rack = await buildRack(engine);
    rack.setChordSource('harm', 'kb');

    await holdChord(engine, const [60, 64, 67]);
    for (final n in const [60, 64, 67]) {
      engine.noteOffUiOnly(channel: 0, key: n);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(paramOf(rack, 'voice1_semitones'), 4,
        reason: 'a released chord must not collapse the harmony');
    expect(paramOf(rack, 'voice2_semitones'), 7);

    rack.dispose();
  });

  test('the MIDI Harmonizer follows a chord too', () async {
    // The two modules look almost identical in the rack, so a chord cable
    // that only drives one of them reads as broken.
    final engine = AudioEngine();
    final rack = await buildRack(engine);
    final midi = rack.midiFxInstanceForSlot('midiharm');
    expect(midi, isNotNull, reason: 'the MIDI FX must initialise');

    rack.setChordSource('midiharm', 'kb');
    await holdChord(engine, const [60, 64, 67]);

    double param(String id) {
      final p = midi!.descriptor.parameters.firstWhere((e) => e.id == id);
      return p.min + midi.getParameter(p.paramId) * (p.max - p.min);
    }

    expect(param('voice_count'), 2);
    expect(param('interval1'), 4);
    expect(param('interval2'), 7);

    rack.dispose();
  });

  test('with nothing patched a chord changes nothing', () async {
    final engine = AudioEngine();
    final rack = await buildRack(engine);

    final before = paramOf(rack, 'voice1_semitones');
    await holdChord(engine, const [60, 64, 67]);

    expect(paramOf(rack, 'voice1_semitones'), before);

    rack.dispose();
  });
}
