// Tests for the MIDI FX chain shared by every note source.
//
// Notes from a hardware controller and notes tapped on the screen used to go
// through two separate copies of the chain. The copies disagreed on which
// effects applied and in what order, a keyboard set to "MIDI only" skipped
// the effects altogether, and the harmonizer read its scale from a channel
// captured when it was created. These tests play notes through the engine
// and the rack, the way the app does.

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge/models/audio_port_id.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/models/grooveforge_keyboard_plugin.dart';
import 'package:grooveforge/models/looper_plugin_instance.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded once: rootBundle reads hang the second test in a file.
  setUpAll(() async {
    GFDescriptorLoader.registerBuiltinNodes();
    GFDescriptorLoader.registerBuiltinMidiNodes();
    for (final name in ['harmonizer', 'transposer']) {
      final yaml = await rootBundle.loadString('assets/plugins/$name.gfpd');
      final desc = GFDescriptorLoader.parse(yaml)!;
      GFPluginRegistry.instance.register(GFMidiDescriptorPlugin(desc));
    }
  });

  const transport = GFTransportContext.stopped;

  /// Restricts [channel] (0-based) to the notes of C major.
  ///
  /// Sets the channel's allowed notes directly. Jam Mode and Xen publish them
  /// through listeners that only `AudioEngine.init` attaches, and init needs
  /// the native audio library. What is under test here is the reading side:
  /// that the harmonizer looks the channel up when it plays, not when it was
  /// created.
  void lockCMajor(AudioEngine engine, int channel) {
    engine.channels[channel].validPitchClasses.value = const {
      0, 2, 4, 5, 7, 9, 11,
    };
  }

  /// Sets parameter [paramId] of the MIDI FX at [slotId] to [normalized].
  void setFx(RackState rack, String slotId, int paramId, double normalized) {
    rack.midiFxInstanceForSlot(slotId)!.setParameter(paramId, normalized);
  }

  /// The pitches of the note-ons in [events].
  List<int> noteOns(List<TimestampedMidiEvent> events) =>
      [for (final e in events) if (e.isNoteOn) e.data1];

  test('screen and controller run the MIDI FX in rack order', () async {
    final engine = AudioEngine();
    final graph = AudioGraph();
    final rack = RackState(engine, TransportEngine(), graph);
    rack.addPlugin(GrooveForgeKeyboardPlugin(id: 'kb', midiChannel: 1));
    // Rack order: transposer above harmonizer.
    rack.addPlugin(GFpaPluginInstance(
        id: 'tr', pluginId: 'com.grooveforge.transposer', midiChannel: 0));
    rack.addPlugin(GFpaPluginInstance(
        id: 'harm', pluginId: 'com.grooveforge.harmonizer', midiChannel: 0));
    await Future<void>.delayed(Duration.zero);
    lockCMajor(engine, 0);

    // Cables drawn in the opposite order to the rack.
    graph.connect('kb', AudioPortId.midiOut, 'harm', AudioPortId.midiIn);
    graph.connect('kb', AudioPortId.midiOut, 'tr', AudioPortId.midiIn);

    setFx(rack, 'tr', 0, 25 / 48); // +1 semitone (range -24..24)

    final screen = noteOns(rack.applyMidiFxToNote(
      sourceSlotId: 'kb',
      channel: 0,
      note: 60,
      velocity: 100,
      transport: transport,
    ));
    final controller = noteOns(rack.applyMidiFxForChannel(
      1,
      const [TimestampedMidiEvent(
          ppqPosition: 0, status: 0x90, data1: 60, data2: 100)],
      transport,
    ));

    expect(screen, controller);
    // Transposer first: C# 61, then the harmonizer adds a third (F 65) and
    // a fifth snapped into C major (G# 68 → G 67). Harmonizer first would
    // give 61, 65, 68.
    expect(screen, [61, 65, 67]);
    rack.dispose();
  });

  test('the harmonizer follows a CHORD IN cable drawn after it was created',
      () async {
    final engine = AudioEngine();
    final rack = RackState(engine, TransportEngine(), AudioGraph());
    // A real keyboard, on a channel other than 1.
    rack.addPlugin(GrooveForgeKeyboardPlugin(id: 'kb', midiChannel: 3));
    rack.addPlugin(GFpaPluginInstance(
        id: 'harm', pluginId: 'com.grooveforge.harmonizer', midiChannel: 0,
        targetSlotIds: ['kb']));
    await Future<void>.delayed(Duration.zero);
    setFx(rack, 'harm', 3, 0); // one voice
    setFx(rack, 'harm', 0, 1 / 24); // a semitone above

    lockCMajor(engine, 2);

    List<int> play() => noteOns(rack.applyMidiFxForChannel(
          3,
          const [TimestampedMidiEvent(
              ppqPosition: 0, status: 0x92, data1: 60, data2: 100)],
          transport,
        ));

    expect(play(), [60, 61], reason: 'no CHORD IN yet: every note allowed');

    rack.setChordSource('harm', 'kb');
    expect(play(), [60, 60],
        reason: 'C# is not in C major, so the voice snaps down to C');
    rack.dispose();
  });

  test('only instruments play notes sent down a MIDI cable', () {
    final engine = AudioEngine();
    final rack = RackState(engine, TransportEngine(), AudioGraph());
    expect(rack.playsMidiNotes(
        GrooveForgeKeyboardPlugin(id: 'kb', midiChannel: 2)), isTrue);
    expect(rack.playsMidiNotes(GFpaPluginInstance(
        id: 'harm', pluginId: 'com.grooveforge.harmonizer', midiChannel: 0)),
        isFalse, reason: 'a MIDI FX has no channel to play on');
    expect(rack.playsMidiNotes(LooperPluginInstance(id: 'loop', midiChannel: 1)),
        isFalse, reason: 'a looper records the note instead');
    rack.dispose();
  });
}
