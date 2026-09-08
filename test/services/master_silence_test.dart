import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/services/master_silence.dart';

/// Writes a mono 16-bit WAV whose first [silentFrames] are digital black.
Future<String> writeWav(
  Directory dir,
  String name, {
  required int silentFrames,
  required int soundFrames,
  int amplitude = 8000,
}) async {
  final frames = silentFrames + soundFrames;
  final bytes = BytesBuilder();
  final data = ByteData(44);
  void ascii(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + frames * 2, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 48000, Endian.little);
  data.setUint32(28, 96000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, frames * 2, Endian.little);
  bytes.add(data.buffer.asUint8List());

  final samples = Int16List(frames);
  for (var i = silentFrames; i < frames; i++) {
    samples[i] = i.isEven ? amplitude : -amplitude;
  }
  bytes.add(samples.buffer.asUint8List());

  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes.takeBytes());
  return file.path;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('gf_silence');
  });
  tearDown(() => dir.delete(recursive: true));

  test('finds where a leading silence ends', () async {
    // Half a second of nothing, then a tone.
    final path = await writeWav(dir, 'a.wav',
        silentFrames: 24000, soundFrames: 48000);

    final at = await MasterSilence.firstSound(path);

    // Within the run length it needs before it will call something sound.
    expect(at, closeTo(24000, 128));
  });

  test('a recording that starts immediately reports the start', () async {
    final path =
        await writeWav(dir, 'b.wav', silentFrames: 0, soundFrames: 48000);
    expect(await MasterSilence.firstSound(path), 0);
  });

  test('silence throughout reports nothing rather than guessing', () async {
    final path =
        await writeWav(dir, 'c.wav', silentFrames: 48000, soundFrames: 0);
    expect(await MasterSilence.firstSound(path), 0);
  });

  test('a lone click is not the start of the music', () async {
    // One sample over the threshold is a decoder artefact, not a note. The
    // marker jumping to it would be worse than leaving it alone.
    final frames = 48000;
    final bytes = BytesBuilder();
    final header = ByteData(44);
    void ascii(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + frames * 2, Endian.little);
    ascii(8, 'WAVEfmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, 48000, Endian.little);
    header.setUint32(28, 96000, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, frames * 2, Endian.little);
    bytes.add(header.buffer.asUint8List());

    final samples = Int16List(frames);
    samples[1000] = 20000; // the click
    for (var i = 30000; i < frames; i++) {
      samples[i] = i.isEven ? 8000 : -8000; // the music
    }
    bytes.add(samples.buffer.asUint8List());
    final file = File('${dir.path}/d.wav');
    await file.writeAsBytes(bytes.takeBytes());

    final at = await MasterSilence.firstSound(file.path);

    expect(at, greaterThan(20000),
        reason: 'the click at 1000 must not be mistaken for the entry');
    expect(at, closeTo(30000, 128));
  });

  test('a missing file is not an error, just no answer', () async {
    expect(await MasterSilence.firstSound('${dir.path}/nope.wav'), 0);
  });
}
