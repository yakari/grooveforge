// Tests that a user's own .gfpd effect makes sound.
//
// A .gfpd effect written by a user used to show its panel and leave the audio
// unchanged: only the bundled effects had native code, chosen by plugin id.
// The native graph interpreter now builds the file's `graph:` section. These
// tests run the app's own builder (buildGfpaGraph) against the real native
// library and listen to what comes out, so they cover the whole chain: the
// Dart parser, the node and port names the file uses, the parameter
// mapping, and the native processing.
//
// They need the Linux release bundle (`flutter build linux --release`) and
// are skipped without it.

import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

import 'package:grooveforge/services/gfpa_graph_builder.dart';

const _libPath = 'build/linux/x64/release/bundle/lib/libdart_vst_host.so';
const _rate = 48000;
const _frames = 4800;

typedef _InsertFn = Void Function(Pointer<Float>, Pointer<Float>,
    Pointer<Float>, Pointer<Float>, Int32, Pointer<Void>);

/// The native calls the host makes on an effect handle.
class _Effect {
  _Effect(DynamicLibrary lib, this.handle)
      : _insertFn = lib.lookupFunction<
            Pointer<NativeFunction<_InsertFn>> Function(Pointer<Void>),
            Pointer<NativeFunction<_InsertFn>> Function(
                Pointer<Void>)>('gfpa_dsp_insert_fn'),
        _setParam = lib.lookupFunction<
            Void Function(Pointer<Void>, Pointer<Utf8>, Double),
            void Function(
                Pointer<Void>, Pointer<Utf8>, double)>('gfpa_dsp_set_param'),
        _destroy = lib.lookupFunction<Void Function(Pointer<Void>),
            void Function(Pointer<Void>)>('gfpa_dsp_destroy');

  final Pointer<Void> handle;
  final Pointer<NativeFunction<_InsertFn>> Function(Pointer<Void>) _insertFn;
  final void Function(Pointer<Void>, Pointer<Utf8>, double) _setParam;
  final void Function(Pointer<Void>) _destroy;

  /// Sets a plugin parameter, in the units its `.gfpd` declares.
  void set(String id, double value) => using(
      (arena) => _setParam(handle, id.toNativeUtf8(allocator: arena), value));

  /// Runs a sine of [hz] (amplitude 0.5) through the effect and returns the
  /// output RMS over the second half, relative to the input's.
  double gainAt(double hz) => using((arena) {
        final inL = arena<Float>(_frames), inR = arena<Float>(_frames);
        final outL = arena<Float>(_frames), outR = arena<Float>(_frames);
        for (var i = 0; i < _frames; i++) {
          inL[i] = inR[i] = 0.5 * math.sin(2 * math.pi * hz * i / _rate);
        }
        _insertFn(handle).asFunction<
            void Function(Pointer<Float>, Pointer<Float>, Pointer<Float>,
                Pointer<Float>, int, Pointer<Void>)>()(
          inL, inR, outL, outR, _frames, handle);
        var sum = 0.0;
        for (var i = _frames ~/ 2; i < _frames; i++) {
          sum += outL[i] * outL[i];
        }
        return math.sqrt(sum / (_frames / 2)) / (0.5 / math.sqrt2);
      });

  void dispose() => _destroy(handle);
}

/// A user's own effect: a low-pass filter with a "cutoff" knob, blended with
/// the dry signal, then a "volume" knob. Ports left out (`from: in`,
/// `to: filter`) default to `out` and `in`, as the guide says.
const _userFilter = '''
spec: "1.0"
id: "org.example.darkener"
name: "Darkener"
version: "1.0.0"
type: effect
parameters:
  - id: cutoff
    paramId: 0
    name: "Cutoff"
    min: 0.0
    max: 1.0
    default: 0.366
  - id: blend
    paramId: 1
    name: "Blend"
    min: 0.0
    max: 100.0
    default: 100.0
  - id: volume
    paramId: 2
    name: "Volume"
    min: 0.0
    max: 1.0
    default: 0.5
graph:
  nodes:
    - id: in
      type: audio_in
    - id: lp
      type: biquad_filter
      params:
        freq: { param: cutoff }
        mode: { value: 0.0 }
    - id: mix
      type: wet_dry
      params:
        mix: { param: blend }
    - id: vol
      type: gain
      params:
        gain: { param: volume }
    - id: out
      type: audio_out
  connections:
    - from: in
      to: [lp, mix.dry]
    - from: lp.out
      to: mix.wet
    - from: mix.out
      to: vol
    - from: vol.out
      to: out.in
''';

void main() {
  final available = File(_libPath).existsSync();
  final lib = available ? DynamicLibrary.open(File(_libPath).absolute.path) : null;
  final api = lib == null ? null : GfpaGraphApi(lib);

  _Effect? build(String yaml) {
    final descriptor = GFDescriptorLoader.parse(yaml)!;
    final handle = buildGfpaGraph(api!, descriptor,
        sampleRate: _rate, blockSize: 512);
    return handle == nullptr ? null : _Effect(lib!, handle);
  }

  final skip = available ? false : 'needs the Linux release bundle';

  test('a user effect filters the sound and follows its knobs', () {
    final fx = build(_userFilter)!;
    expect(fx.gainAt(60), closeTo(1.0, 0.05), reason: 'bass passes');
    expect(fx.gainAt(5000), lessThan(0.01), reason: 'treble is filtered');

    fx.set('blend', 0); // all dry: the filter is out of the sound
    expect(fx.gainAt(5000), closeTo(1.0, 0.05));

    fx.set('volume', 1.0); // gain 0.5 -> 1.0 doubles the level
    expect(fx.gainAt(5000), closeTo(2.0, 0.1));
    fx.dispose();
  }, skip: skip);

  test('a graph using an unknown node is refused', () {
    final broken = _userFilter.replaceFirst('type: gain', 'type: fuzz_box');
    expect(build(broken), isNull);
  }, skip: skip);

  test('every bundled effect graph also builds as a user plugin', () {
    // The bundled effects run their own native code, but their files are the
    // reference examples users copy. Under a user id they go through the
    // interpreter, which must understand every node, port and parameter.
    for (final name in ['reverb', 'delay', 'wah', 'chorus', 'compressor',
        'eq', 'audio_harmonizer']) {
      final yaml = File('assets/plugins/$name.gfpd')
          .readAsStringSync()
          .replaceFirst(RegExp(r'id: "com\.grooveforge\.[a-z_]+"'),
              'id: "org.example.copy"');
      final fx = build(yaml);
      expect(fx, isNotNull, reason: '$name.gfpd');
      expect(fx!.gainAt(440), greaterThan(0.0), reason: '$name.gfpd is silent');
      fx.dispose();
    }
  }, skip: skip);
}
