// Contract tests for the Autotune descriptor.
//
// The correction itself runs natively and is measured by
// native_audio/gf_autotune_smoke_test.c. What can drift on the Dart side is
// the agreement between three files that are edited separately: the
// descriptor, the C++ wrapper that receives its parameters by string id, and
// the C engine whose scale list the descriptor's selector mirrors. A
// parameter the wrapper does not recognise is silently ignored — the knob
// turns and nothing happens — so these tests read the native sources and
// check the names line up.

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GFPluginDescriptor descriptor;

  setUpAll(() async {
    final yaml = await rootBundle.loadString('assets/plugins/autotune.gfpd');
    final parsed = GFDescriptorLoader.parse(yaml);
    expect(parsed, isNotNull, reason: 'autotune.gfpd must parse cleanly');
    descriptor = parsed!;
  });

  test('is an audio effect under its own id', () {
    expect(descriptor.id, 'com.grooveforge.autotune');
    expect(descriptor.type, GFPluginType.effect);
  });

  test('parameters keep their ids and order', () {
    // paramId values are stored in saved projects: never renumber these.
    final ids = {for (final p in descriptor.parameters) p.paramId: p.id};
    expect(ids, {
      0: 'key',
      1: 'scale',
      2: 'strength',
      3: 'retune',
      4: 'humanize',
      5: 'flex_tune',
      6: 'transpose',
      7: 'mix',
    });
  });

  test('defaults are the full-on robot', () {
    double def(String id) => descriptor.paramById(id)!.defaultValue;
    expect(def('strength'), 100);
    expect(def('retune'), 0);
    expect(def('humanize'), 0);
    expect(def('flex_tune'), 0);
    expect(def('transpose'), 0);
    expect(def('mix'), 100);
  });

  test('the patched scale is host state, not a saved parameter', () {
    expect(descriptor.paramById('scale_mask'), isNull);
  });

  test('knobs whose value is a number print it', () {
    for (final id in ['strength', 'retune', 'humanize', 'flex_tune', 'mix']) {
      expect(descriptor.paramById(id)!.display, GFParamDisplay.value,
          reason: id);
    }
    expect(descriptor.paramById('transpose')!.display, GFParamDisplay.interval);
  });

  test('the key selector names all twelve notes', () {
    final key = descriptor.paramById('key')!;
    expect(key.type, GFDescriptorParamType.selector);
    expect(key.options, hasLength(12));
    expect(key.max, 11);
  });

  test('the scale selector matches the native scale list', () {
    // gf_autotune_scale in the C header is the list the selector indexes.
    final header = File('native_audio/gf_autotune.h').readAsStringSync();
    final enumBody = RegExp(r'typedef enum \{([^}]*)\} gf_autotune_scale;')
        .firstMatch(header)!
        .group(1)!;
    final nativeScales = RegExp(r'GF_AUTOTUNE_SCALE_(\w+)')
        .allMatches(enumBody)
        .map((m) => m.group(1))
        .where((name) => name != 'COUNT')
        .toList();

    final scale = descriptor.paramById('scale')!;
    expect(scale.options, hasLength(nativeScales.length));
    expect(scale.max, nativeScales.length - 1);
  });

  test('every parameter is one the native wrapper listens for', () {
    // AutotuneEffect::setParam matches ids with strcmp; a typo on either
    // side leaves a control that does nothing.
    final source = File(
      'packages/flutter_vst3/dart_vst_host/native/src/gfpa_dsp.cpp',
    ).readAsStringSync();
    final start = source.indexOf('struct AutotuneEffect');
    final end = source.indexOf('double readout(', start);
    expect(start, greaterThanOrEqualTo(0));
    final setParam = source.substring(start, end);
    final nativeIds = RegExp(r'strcmp\(id, "(\w+)"\)')
        .allMatches(setParam)
        .map((m) => m.group(1))
        .toSet();

    for (final p in descriptor.parameters) {
      expect(nativeIds, contains(p.id), reason: '${p.id} is not handled');
    }
    expect(nativeIds, contains('scale_mask'));
  });
}
