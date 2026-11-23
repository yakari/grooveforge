// Contract tests for the guitar Amp.
//
// Three files are edited separately and must agree: the descriptor, the C++
// adapter that receives its parameters by string id, and the CC registry that
// points a footswitch at a parameter by number. A name the C++ side does not
// recognise is silently ignored — the switch clicks and nothing happens — so
// these tests read the native source and check the names line up.
//
// The DSP itself is measured by native_audio/gf_amp_smoke_test.c.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/cabinet_ir.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/cc_param_registry.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

const _ampId = 'com.grooveforge.amp';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Loaded once: rootBundle reads hang the second test in a file.
  late GFPluginDescriptor descriptor;

  setUpAll(() async {
    final yaml = await rootBundle.loadString('assets/plugins/amp.gfpd');
    final parsed = GFDescriptorLoader.parse(yaml);
    expect(parsed, isNotNull, reason: 'amp.gfpd must parse cleanly');
    descriptor = parsed!;
    GFPluginRegistry.instance.register(GFDescriptorPlugin(descriptor));
  });

  group('descriptor', () {
    test('parameter ids are fixed', () {
      // paramId values are stored in saved projects: never renumber these.
      final ids = {for (final p in descriptor.parameters) p.paramId: p.id};
      expect(ids, {
        0: 'drive_on',
        1: 'drive_mode',
        2: 'drive',
        3: 'drive_tone',
        4: 'amp_on',
        5: 'amp_model',
        6: 'gain',
        7: 'bass',
        8: 'middle',
        9: 'treble',
        10: 'cab_on',
        11: 'cab_type',
        12: 'level',
      });
    });

    test('every parameter is one the native effect recognises', () {
      final native = File(
        'packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp',
      ).readAsStringSync();
      final start = native.indexOf('struct AmpEffect');
      expect(start, isNot(-1), reason: 'AmpEffect is missing from gfpa_dsp');
      final amp = native.substring(start, native.indexOf('\n};', start));
      for (final p in descriptor.parameters) {
        expect(amp, contains('strcmp(id, "${p.id}")'),
            reason: '${p.id} would be silently ignored by the native amp');
      }
    });

    test('the native side creates the effect under this id', () {
      final native = File(
        'packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp',
      ).readAsStringSync();
      expect(native, contains('id == "$_ampId"'));
    });

    test('selector options match the native enums', () {
      // The C enums are indexed by these options; a reordering on one side
      // only would make "Brit" load the "AC" circuit.
      final header = File('native_audio/gf_amp.h').readAsStringSync();
      List<String>? options(String id) =>
          descriptor.parameters.firstWhere((p) => p.id == id).options;
      expect(options('drive_mode'), ['Overdrive', 'Distortion']);
      expect(header, contains('GF_AMP_DRIVE_OVERDRIVE = 0'));
      expect(options('amp_model'), ['US', 'Brit', 'AC']);
      expect(header, contains('GF_AMP_MODEL_FENDER = 0'));
      expect(options('cab_type'), ['1x12', '2x12', '4x12', 'IR']);
      expect(header, contains('GF_AMP_CAB_1X12 = 0'));
      // IR must stay the fourth entry, right after the three built-ins.
      expect(
        header,
        matches(RegExp(r'GF_AMP_CAB_4X12,[^\n]*\n\s*GF_AMP_CAB_IR,')),
      );
    });
  });

  group('CC registry', () {
    test('every entry points at a descriptor parameter', () {
      final byId = {for (final p in descriptor.parameters) p.paramId: p};
      for (final entry in CcParamRegistry.forPluginId(_ampId)!) {
        if (entry.paramKey == 'bypass') continue;
        final param = byId[entry.gfpaParamId];
        expect(param, isNotNull, reason: entry.paramKey);
        expect(param!.id, entry.paramKey);
      }
    });

    test('the three section switches flip on each press', () {
      for (final key in ['drive_on', 'amp_on', 'cab_on']) {
        final entry = CcParamRegistry.findParam(_ampId, key)!;
        expect(entry.defaultMode, CcParamMode.cycle, reason: key);
        expect(entry.cycleCount, 2, reason: key);
      }
    });

    test('a footswitch press toggles the drive, and the next one untoggles',
        () async {
      final rack = RackState(AudioEngine(), TransportEngine(), AudioGraph());
      final slot = GFpaPluginInstance(
        id: 'amp-1',
        pluginId: _ampId,
        midiChannel: 0,
      );
      rack.addPlugin(slot);
      await Future<void>.delayed(Duration.zero);

      // Drive starts off (the descriptor default).
      slot.state['drive_on'] = 0.0;
      // Some controllers send 0 on press; the cycle must not care.
      rack.handleSlotParamCc('amp-1', 'drive_on', CcParamMode.cycle, 0);
      expect(slot.state['drive_on'], 1.0);

      // Past the 250 ms debounce that swallows a press/release pair.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      rack.handleSlotParamCc('amp-1', 'drive_on', CcParamMode.cycle, 127);
      expect(slot.state['drive_on'], 0.0);

      rack.dispose();
    });
  });

  group('cabinet IR', () {
    // What a loaded IR leaves in the slot state.
    final saved = CabinetIr(
      name: 'cab.wav',
      sampleRate: 48000,
      samples: Float32List.fromList([1, 0.5, 0.25]),
    ).toJson();

    test('the native side exports the loader the Dart bindings look up', () {
      final header = File(
        'packages/flutter_vst3/dart_vst_host/native/include/gfpa_dsp.h',
      ).readAsStringSync();
      for (final symbol in ['gfpa_dsp_load_ir', 'gfpa_dsp_clear_ir']) {
        expect(header, contains('$symbol('));
        for (final path in [
          'packages/flutter_vst3/dart_vst_host/lib/src/bindings.dart',
          'lib/services/gfpa_android_bindings_native.dart',
        ]) {
          expect(File(path).readAsStringSync(), contains("'$symbol'"),
              reason: '$symbol in $path');
        }
      }
    });

    test('turning a knob keeps the IR in the slot', () async {
      final rack = RackState(AudioEngine(), TransportEngine(), AudioGraph());
      final slot = GFpaPluginInstance(
        id: 'amp-ir',
        pluginId: _ampId,
        state: {CabinetIr.stateKey: saved},
      );
      rack.addPlugin(slot);
      await Future<void>.delayed(Duration.zero);

      // The panel's knobs report through the slot's param notifier, which
      // rewrites the state from the plugin's parameters.
      final plugin = rack.audioEffectInstanceForSlot('amp-ir')!;
      plugin.setParameter(6, 0.9); // gain
      rack.audioEffectParamNotifierForSlot('amp-ir')!.value++;

      expect(slot.state['gain'], closeTo(0.9, 1e-9));
      expect(slot.state[CabinetIr.stateKey], saved);
      expect(rack.cabinetIrName('amp-ir'), 'cab.wav');
      rack.dispose();
    });

    test('the IR is saved with the project and read back', () {
      final slot = GFpaPluginInstance(
        id: 'amp-ir',
        pluginId: _ampId,
        state: {CabinetIr.stateKey: saved},
      );
      final json = jsonDecode(jsonEncode(slot.toJson())) as Map<String, dynamic>;
      final back = GFpaPluginInstance.fromJson(json);
      final ir = CabinetIr.fromJson(back.state[CabinetIr.stateKey])!;
      expect(ir.samples, [1, 0.5, 0.25]);
    });

    test('an IR the native amp cannot take changes nothing', () async {
      // No native host runs under test, so the load is refused — the same
      // path as a rejected file: no IR stored, cabinet untouched.
      final rack = RackState(AudioEngine(), TransportEngine(), AudioGraph());
      final slot = GFpaPluginInstance(id: 'amp-no', pluginId: _ampId);
      rack.addPlugin(slot);
      await Future<void>.delayed(Duration.zero);
      final cabBefore = slot.state['cab_type'];

      final ok = rack.loadCabinetIr('amp-no', CabinetIr.fromJson(saved)!);

      expect(ok, isFalse);
      expect(slot.state.containsKey(CabinetIr.stateKey), isFalse);
      expect(slot.state['cab_type'], cabBefore);
      rack.dispose();
    });

    // cab_type is saved normalised: option index / 3 (1x12, 2x12, 4x12, IR).
    Future<(RackState, GFpaPluginInstance)> ampWithIr(double cab) async {
      final rack = RackState(AudioEngine(), TransportEngine(), AudioGraph());
      final slot = GFpaPluginInstance(
        id: 'amp-rm',
        pluginId: _ampId,
        state: {CabinetIr.stateKey: saved, 'cab_type': cab},
      );
      rack.addPlugin(slot);
      await Future<void>.delayed(Duration.zero);
      return (rack, slot);
    }

    test('removing the IR takes the cabinet from "IR" back to the 2x12',
        () async {
      final (rack, slot) = await ampWithIr(1.0); // IR
      var notified = 0;
      rack.addListener(() => notified++);

      rack.removeCabinetIr('amp-rm');

      expect(slot.state.containsKey(CabinetIr.stateKey), isFalse);
      expect(rack.cabinetIrName('amp-rm'), isNull);
      expect(slot.state['cab_type'], closeTo(1 / 3, 1e-9)); // 2x12
      expect(notified, greaterThan(0));
      rack.dispose();
    });

    test('removing the IR leaves a built-in cabinet selection alone',
        () async {
      final (rack, slot) = await ampWithIr(2 / 3); // 4x12
      rack.removeCabinetIr('amp-rm');
      expect(slot.state.containsKey(CabinetIr.stateKey), isFalse);
      expect(slot.state['cab_type'], closeTo(2 / 3, 1e-9));
      rack.dispose();
    });
  });
}
