// Regression test for a heap corruption with VST3 plugins on Linux.
//
// A plugin is resumed with a maximum block size (256 frames), but JACK and
// PipeWire call the host with their own block size, often 1024 frames. The
// host used to pass those 1024 frames straight to the plugin, which then wrote
// its extra output buses (Surge XT has three) past their buffers. The app died
// with "malloc(): invalid size" as soon as audio started. The host now cuts a
// long block into chunks of the size it promised.
//
// Needs the built native library and Surge XT installed; skipped otherwise.

import 'dart:io';
import 'dart:typed_data';

import 'package:dart_vst_host/dart_vst_host.dart';
import 'package:flutter_test/flutter_test.dart';

const _lib =
    '../../../build/linux/x64/release/bundle/lib/libdart_vst_host.so';
const _surge = '/usr/lib/vst3/Surge XT.vst3';

void main() {
  final available = File(_lib).existsSync() && Directory(_surge).existsSync();

  test('a plugin survives blocks larger than the size it was promised', () {
    final host =
        VstHost.create(sampleRate: 48000, maxBlock: 256, dylibPath: _lib);
    final plugin = host.load(_surge);
    expect(plugin.resume(sampleRate: 48000, maxBlock: 256), isTrue);

    // Four times the promised block size, as a 1024-frame JACK period.
    const frames = 1024;
    final inL = Float32List(frames), inR = Float32List(frames);
    final outL = Float32List(frames), outR = Float32List(frames);
    var peak = 0.0;
    for (var block = 0; block < 300; block++) {
      if (block % 50 == 0) plugin.noteOn(0, 60, 0.9);
      plugin.processStereoF32(inL, inR, outL, outR);
      for (final v in outL) {
        if (v.abs() > peak) peak = v.abs();
      }
    }
    expect(peak, greaterThan(0.0), reason: 'the synth must still make sound');

    plugin.suspend();
    plugin.unload();
  },
      skip: available
          ? false
          : 'needs build/linux release bundle and Surge XT in /usr/lib/vst3');

  test('pitch bend and CC reach the plugin', () {
    final host =
        VstHost.create(sampleRate: 48000, maxBlock: 256, dylibPath: _lib);
    final plugin = host.load(_surge);
    expect(plugin.resume(sampleRate: 48000, maxBlock: 256), isTrue);

    expect(plugin.pitchBend(0, 8192), isTrue,
        reason: 'Surge maps pitch bend to a parameter (IMidiMapping)');
    expect(plugin.controlChange(0, 1, 64), isTrue,
        reason: 'Surge maps the mod wheel');

    // The pitch of a held note, measured by counting zero crossings, must
    // rise when the bend goes up: proof the bend reaches the sound.
    final centre = _crossings(plugin, bend: 8192);
    final up = _crossings(plugin, bend: 16383);
    expect(centre, greaterThan(100), reason: 'the note must sound');
    expect(up, greaterThan(centre * 1.05),
        reason: 'centre $centre crossings, bent up $up');

    plugin.suspend();
    plugin.unload();
  },
      skip: available
          ? false
          : 'needs build/linux release bundle and Surge XT in /usr/lib/vst3');
}

/// Zero crossings of the left output while middle C is held with the given
/// [bend], after letting the attack settle.
int _crossings(VstPlugin plugin, {required int bend}) {
  const frames = 256;
  final inL = Float32List(frames), inR = Float32List(frames);
  final outL = Float32List(frames), outR = Float32List(frames);
  plugin.pitchBend(0, bend);
  plugin.noteOn(0, 60, 0.9);
  var count = 0;
  var previous = 0.0;
  for (var block = 0; block < 200; block++) {
    plugin.processStereoF32(inL, inR, outL, outR);
    if (block < 40) continue; // attack and bend glide
    for (final v in outL) {
      if ((previous < 0) != (v < 0)) count++;
      previous = v;
    }
  }
  plugin.noteOff(0, 60, 0);
  for (var block = 0; block < 100; block++) {
    plugin.processStereoF32(inL, inR, outL, outR); // let the note die out
  }
  return count;
}
