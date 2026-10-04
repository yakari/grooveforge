// Contract and behaviour tests for the Wah.
//
// Three files are edited separately and must agree: the descriptor, the C++
// effect that receives its parameters by string id, and the CC registry that
// points a pedal at a parameter by number. A name the C++ side does not
// recognise is silently ignored — the pedal moves and nothing happens — so
// the contract tests read the native source and check the names line up.
//
// The behaviour tests drive the Dart node, which mirrors the native maths,
// and check the one thing manual mode promises: the pedal moves the filter.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/cc_param_registry.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

const _sampleRate = 48000;
const _block = 480;

/// Runs a steady sine at [hz] through [node] and returns the RMS level of the
/// last block, once the filter and the pedal smoothing have settled.
double _levelAt(GFDspWahFilterNode node, double hz) {
  final inL = Float32List(_block);
  final inR = Float32List(_block);
  var rms = 0.0;
  // One second of audio: far longer than the 15 ms pedal smoothing.
  for (var b = 0; b < _sampleRate ~/ _block; b++) {
    for (var i = 0; i < _block; i++) {
      final n = b * _block + i;
      inL[i] = inR[i] = math.sin(2 * math.pi * hz * n / _sampleRate);
    }
    node.processBlock({'in': (inL, inR)}, _block, GFTransportContext.stopped);
    final out = node.outputL('out');
    var sum = 0.0;
    for (var i = 0; i < _block; i++) {
      sum += out[i] * out[i];
    }
    rms = math.sqrt(sum / _block);
  }
  return rms;
}

/// A wah in manual mode with the pedal at [pedal], centred on 1200 Hz with
/// the default depth of 0.8 — a sweep of 1.6 octaves either side.
GFDspWahFilterNode _manualWah(double pedal) {
  final node = GFDspWahFilterNode('wah')..initialize(_sampleRate, _block);
  // center is exponential: 200 * 20^n = 1200 Hz.
  node.setParam('center', math.log(6) / math.log(20));
  node.setParam('depth', 0.8);
  node.setParam('mode', 1.0);
  node.setParam('pedal', pedal);
  return node;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GFPluginDescriptor descriptor;

  setUpAll(() async {
    final yaml = await rootBundle.loadString('assets/plugins/wah.gfpd');
    final parsed = GFDescriptorLoader.parse(yaml);
    expect(parsed, isNotNull, reason: 'wah.gfpd must parse cleanly');
    descriptor = parsed!;
  });

  group('descriptor', () {
    test('is named Wah under the id saved projects already use', () {
      expect(descriptor.name, 'Wah');
      expect(descriptor.id, 'com.grooveforge.wah');
    });

    test('parameters keep their ids, with mode and pedal appended', () {
      // paramId values are stored in saved projects: never renumber these.
      final ids = {for (final p in descriptor.parameters) p.paramId: p.id};
      expect(ids, {
        0: 'center',
        1: 'resonance',
        2: 'rate',
        3: 'depth',
        4: 'waveform',
        5: 'bpm_sync',
        6: 'beat_div',
        7: 'mix',
        8: 'mode',
        9: 'pedal',
      });
    });

    test('defaults to auto mode, so existing projects sound the same', () {
      final mode = descriptor.parameters.firstWhere((p) => p.id == 'mode');
      expect(mode.defaultValue, 0.0);
    });

    test('every parameter is one the native effect recognises', () {
      final native = File(
        'packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp',
      ).readAsStringSync();
      final start = native.indexOf('struct WahEffect');
      final wah = native.substring(start, native.indexOf('\n};', start));
      for (final p in descriptor.parameters) {
        expect(wah, contains('strcmp(id,"${p.id}")'),
            reason: '${p.id} would be silently ignored by the native wah');
      }
    });
  });

  group('CC registry', () {
    test('pedal and mode point at the descriptor parameters', () {
      final pedal = CcParamRegistry.findParam('com.grooveforge.wah', 'pedal')!;
      final mode = CcParamRegistry.findParam('com.grooveforge.wah', 'mode')!;
      final byId = {for (final p in descriptor.parameters) p.paramId: p.id};

      expect(byId[pedal.gfpaParamId], 'pedal');
      expect(pedal.defaultMode, CcParamMode.absolute);
      expect(byId[mode.gfpaParamId], 'mode');
      expect(mode.defaultMode, CcParamMode.cycle);
      expect(mode.cycleCount, 2);
    });
  });

  group('manual mode', () {
    test('heel down passes lows, toe down passes highs', () {
      // 1200 Hz ∓ 1.6 octaves: about 396 Hz heel down, 3638 Hz toe down.
      final heelLow = _levelAt(_manualWah(0.0), 396);
      final heelHigh = _levelAt(_manualWah(0.0), 3638);
      final toeLow = _levelAt(_manualWah(1.0), 396);
      final toeHigh = _levelAt(_manualWah(1.0), 3638);

      expect(heelLow, greaterThan(heelHigh * 4));
      expect(toeHigh, greaterThan(toeLow * 4));
    });

    test('pedal at halfway sits on the center frequency', () {
      final node = _manualWah(0.5);
      final atCenter = _levelAt(node, 1200);
      expect(atCenter, greaterThan(_levelAt(_manualWah(0.5), 396) * 4));
      expect(atCenter, greaterThan(_levelAt(_manualWah(0.5), 3638) * 4));
    });

    test('the pedal does nothing in auto mode', () {
      // Depth 0 parks the LFO on the center frequency, so any change in
      // level between the two pedal positions would be the pedal leaking in.
      GFDspWahFilterNode autoWah(double pedal) => _manualWah(pedal)
        ..setParam('mode', 0.0)
        ..setParam('depth', 0.0);

      expect(_levelAt(autoWah(0.0), 1200),
          closeTo(_levelAt(autoWah(1.0), 1200), 1e-6));
    });

    test('a pedal jump glides instead of stepping', () {
      final node = _manualWah(0.0);
      _levelAt(node, 396); // settle heel down
      node.setParam('pedal', 1.0);

      // One block is 10 ms, under the 15 ms smoothing: a 396 Hz tone must
      // still be audible, where an instant jump would have cut it already.
      final inL = Float32List(_block);
      for (var i = 0; i < _block; i++) {
        inL[i] = math.sin(2 * math.pi * 396 * i / _sampleRate);
      }
      node.processBlock({'in': (inL, inL)}, _block, GFTransportContext.stopped);
      final settledToe = _levelAt(_manualWah(1.0), 396);
      final out = node.outputL('out');
      var sum = 0.0;
      for (var i = 0; i < _block; i++) {
        sum += out[i] * out[i];
      }
      expect(math.sqrt(sum / _block), greaterThan(settledToe * 2));
    });
  });
}
