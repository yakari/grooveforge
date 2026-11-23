// Contract and routing tests for Riff, the modelled guitar.
//
// The guitar is driven through four layers edited separately: the
// descriptor, the C++ pool that receives its parameters by string id, the
// CC registry that points a pedal at a parameter by number, and the engine
// that routes a channel's MIDI to the right slot. A name one side does not
// recognise is silently ignored — the knob turns and nothing happens — so
// these tests read the native source and check the names line up, and drive
// the real engine to check where the notes go.
//
// The sound itself is measured by native_audio/gf_riff_smoke_test.c, and the
// native pool by native_audio/gf_riff_pool_smoke_test.c.

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/constants/soundfont_sentinels.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/cc_param_registry.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Records what the engine hands to the guitar.
class _RecordingSink implements RiffMidiSink {
  final events = <String>[];

  @override
  void riffNoteOn(int channel, int note, int velocity) =>
      events.add('on $channel $note $velocity');

  @override
  void riffNoteOff(int channel, int note) => events.add('off $channel $note');

  @override
  void riffPitchBend(int channel, double bend) =>
      events.add('bend $channel ${bend.toStringAsFixed(2)}');

  @override
  void riffControlChange(int channel, int controller, int value) =>
      events.add('cc $channel $controller $value');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded once: rootBundle reads hang the second test in a file.
  late GFPluginDescriptor descriptor;

  setUpAll(() async {
    final yaml = await rootBundle.loadString('assets/plugins/riff.gfpd');
    final parsed = GFDescriptorLoader.parse(yaml);
    expect(parsed, isNotNull, reason: 'riff.gfpd must parse cleanly');
    descriptor = parsed!;
    GFPluginRegistry.instance.register(GFDescriptorPlugin(descriptor));
  });

  final pool = File(
    'packages/flutter_vst3/dart_vst_host/native/src/gfpa_riff.cpp',
  ).readAsStringSync();
  final dsp = File(
    'packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp',
  ).readAsStringSync();

  group('descriptor', () {
    test('is an instrument with fixed parameter ids', () {
      expect(descriptor.type, GFPluginType.instrument);
      // paramId values are stored in saved projects: never renumber these.
      final ids = {for (final p in descriptor.parameters) p.paramId: p.id};
      expect(ids, {
        0: 'palm_mute',
        1: 'pick_pos',
        2: 'attack',
        3: 'pickup',
        4: 'pickup_type',
        5: 'tone',
        6: 'sustain',
        7: 'bend_range',
        8: 'level',
        9: 'legato',
        10: 'legato_overlap',
      });
    });

    test('every parameter is one the native guitar recognises', () {
      for (final p in descriptor.parameters) {
        expect(pool, contains('strcmp(id, "${p.id}")'),
            reason: '${p.id} would be silently ignored by the native guitar');
      }
    });

    test('the native side creates the guitar under this id', () {
      expect(dsp, contains('id == "$kRiffPluginId"'));
    });

    test('pickup options follow the native enum', () {
      final header = File('native_audio/gf_riff.h').readAsStringSync();
      List<String>? options(String id) =>
          descriptor.parameters.firstWhere((p) => p.id == id).options;
      expect(options('pickup'), ['Neck', 'Middle', 'Bridge', 'Neck+Bridge']);
      expect(
        header,
        matches(RegExp(r'GF_RIFF_PICKUP_NECK = 0,[^\n]*\n\s*GF_RIFF_PICKUP_MIDDLE,'
            r'[^\n]*\n\s*GF_RIFF_PICKUP_BRIDGE,[^\n]*\n\s*GF_RIFF_PICKUP_NECK_BRIDGE,')),
      );
      expect(options('pickup_type'), ['Single coil', 'Humbucker']);
    });

    test('the native entry points the bindings look up exist', () {
      final header = File(
        'packages/flutter_vst3/dart_vst_host/native/include/gfpa_dsp.h',
      ).readAsStringSync();
      final desktop = File(
        'packages/flutter_vst3/dart_vst_host/lib/src/bindings.dart',
      ).readAsStringSync();
      final android =
          File('lib/services/gfpa_android_bindings_native.dart').readAsStringSync();
      for (final symbol in [
        'gfpa_riff_note_on',
        'gfpa_riff_note_off',
        'gfpa_riff_pitch_bend',
        'gfpa_riff_control_change',
      ]) {
        expect(header, contains('$symbol('), reason: symbol);
        expect(desktop, contains("'$symbol'"), reason: 'desktop $symbol');
        expect(android, contains("'$symbol'"), reason: 'Android $symbol');
      }
      expect(header, contains('gfpa_riff_render_fn('));
      expect(desktop, contains("'gfpa_riff_render_fn'"));
      expect(header, contains('gfpa_riff_bus_render_fn('));
      expect(android, contains("'gfpa_riff_bus_render_fn'"));
    });
  });

  group('CC registry', () {
    test('every entry points at a descriptor parameter', () {
      final byId = {for (final p in descriptor.parameters) p.paramId: p};
      for (final entry in CcParamRegistry.forPluginId(kRiffPluginId)!) {
        if (entry.paramKey == 'bypass') continue;
        final param = byId[entry.gfpaParamId];
        expect(param, isNotNull, reason: entry.paramKey);
        // A "_switch" entry is the same parameter on a button.
        expect(entry.paramKey.replaceAll('_switch', ''), param!.id);
      }
    });

    test('palm mute and pick position ride a continuous controller', () {
      for (final key in ['palm_mute', 'pick_pos']) {
        final entry = CcParamRegistry.findParam(kRiffPluginId, key)!;
        expect(entry.defaultMode, CcParamMode.absolute, reason: key);
      }
    });

    test('a pedal moves the palm mute of the slot', () async {
      final rack = RackState(AudioEngine(), TransportEngine(), AudioGraph());
      final slot = GFpaPluginInstance(
        id: 'riff-cc',
        pluginId: kRiffPluginId,
        midiChannel: 3,
      );
      rack.addPlugin(slot);
      await Future<void>.delayed(Duration.zero);

      rack.handleSlotParamCc('riff-cc', 'palm_mute', CcParamMode.absolute, 127);
      expect(slot.state['palm_mute'], 1.0);
      rack.handleSlotParamCc('riff-cc', 'palm_mute', CcParamMode.absolute, 0);
      expect(slot.state['palm_mute'], 0.0);
      rack.dispose();
    });

    /// A rack with one Riff slot, its live plugin ready.
    Future<(RackState, GFpaPluginInstance)> riffRack(String id) async {
      final rack = RackState(AudioEngine(), TransportEngine(), AudioGraph());
      final slot = GFpaPluginInstance(
        id: id,
        pluginId: kRiffPluginId,
        midiChannel: 4,
      );
      rack.addPlugin(slot);
      await Future<void>.delayed(Duration.zero);
      return (rack, slot);
    }

    /// One pad press, as the Alesis Vortex sends it: value 0, every time.
    /// Spaced past the 250 ms debounce of switch mappings.
    Future<void> press(RackState rack, String slot, String key) async {
      final entry = CcParamRegistry.findParam(kRiffPluginId, key)!;
      rack.handleSlotParamCc(slot, key, entry.defaultMode, 0);
      await Future<void>.delayed(const Duration(milliseconds: 260));
    }

    test('a pad switches legato on and off, whatever value it sends',
        () async {
      final (rack, slot) = await riffRack('riff-legato');
      await press(rack, 'riff-legato', 'legato');
      expect(slot.state['legato'], 1.0);
      await press(rack, 'riff-legato', 'legato');
      expect(slot.state['legato'], 0.0);
      rack.dispose();
    });

    test('a mapping saved when Legato was absolute now works as a switch',
        () async {
      final (rack, slot) = await riffRack('riff-old-map');
      // The mode an older version saved in the mapping; the pad sends 0.
      for (final expected in [1.0, 0.0, 1.0]) {
        rack.handleSlotParamCc('riff-old-map', 'legato', CcParamMode.absolute, 0);
        expect(slot.state['legato'], expected);
        await Future<void>.delayed(const Duration(milliseconds: 260));
      }
      rack.dispose();
    });

    test('a pad switches palm mute off and back to the knob\'s amount',
        () async {
      final (rack, slot) = await riffRack('riff-palm');
      // Never set: a press brings the full mute.
      await press(rack, 'riff-palm', 'palm_mute_switch');
      expect(slot.state['palm_mute'], 1.0);
      // The knob (here a pedal) sets an amount; the pad toggles around it.
      rack.handleSlotParamCc('riff-palm', 'palm_mute', CcParamMode.absolute, 64);
      final amount = slot.state['palm_mute'] as double;
      await press(rack, 'riff-palm', 'palm_mute_switch');
      expect(slot.state['palm_mute'], 0.0);
      await press(rack, 'riff-palm', 'palm_mute_switch');
      expect(slot.state['palm_mute'], amount);
      rack.dispose();
    });

    test('a CC moves the panel too, and a knob turned after keeps it',
        () async {
      final (rack, slot) = await riffRack('riff-panel');
      rack.handleSlotParamCc('riff-panel', 'palm_mute', CcParamMode.absolute, 127);
      final live = rack.audioEffectInstanceForSlot('riff-panel')!;
      expect(live.getParameter(0), 1.0, reason: 'the panel knob follows');
      // Turning another knob on the panel must not put the old palm mute back.
      live.setParameter(5, 0.2); // tone
      rack.audioEffectParamNotifierForSlot('riff-panel')!.value++;
      expect(slot.state['palm_mute'], 1.0);
      rack.dispose();
    });

    test('the guitar takes CC 68 as the legato pedal', () {
      expect(pool, contains('case 68:  gf_riff_legato_pedal'));
    });
  });

  group('engine routing', () {
    test('a Riff channel sends notes, bends and controllers to the guitar', () {
      final engine = AudioEngine();
      final sink = _RecordingSink();
      engine.riffSink = sink;
      engine.assignSoundfontToChannel(2, riffMode);

      engine.playNote(channel: 2, key: 52, velocity: 100);
      engine.setPitchBend(channel: 2, value: 16383);
      engine.setControlChange(channel: 2, controller: 64, value: 127);
      engine.stopNote(channel: 2, key: 52);

      expect(sink.events, [
        'on 2 52 100',
        'bend 2 1.00',
        'cc 2 64 127',
        'off 2 52',
      ]);
    });

    test('other channels never reach the guitar', () {
      final engine = AudioEngine();
      final sink = _RecordingSink();
      engine.riffSink = sink;
      engine.assignSoundfontToChannel(2, riffMode);
      // A controller-only channel: no synth of its own, so nothing native
      // is reached, and nothing may leak to the guitar on channel 2.
      engine.assignSoundfontToChannel(5, kMidiControllerOnlySoundfont);
      engine.playNote(channel: 5, key: 60, velocity: 90);
      engine.setPitchBend(channel: 5, value: 8192);
      engine.setControlChange(channel: 5, controller: 1, value: 64);
      expect(sink.events, isEmpty);
    });

    test('adding a Riff slot puts its channel in Riff mode', () async {
      final engine = AudioEngine();
      final rack = RackState(engine, TransportEngine(), AudioGraph());
      expect(engine.riffSink, isNotNull, reason: 'the rack routes Riff MIDI');
      rack.addPlugin(GFpaPluginInstance(
        id: 'riff-1',
        pluginId: kRiffPluginId,
        midiChannel: 4,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(engine.channels[3].soundfontPath, riffMode);

      // Moving it hands the old channel back.
      rack.setPluginMidiChannel('riff-1', 6);
      expect(engine.channels[3].soundfontPath, isNot(riffMode));
      expect(engine.channels[5].soundfontPath, riffMode);
      rack.dispose();
    });
  });
}
