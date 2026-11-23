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
        expect(param!.id, entry.paramKey);
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
