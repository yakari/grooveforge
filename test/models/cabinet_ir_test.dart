// Tests for the cabinet impulse response reader.
//
// IR files come from many tools (Celestion's, TONE3000 uploads, home-made
// captures in a DAW), so the reader is checked against every WAV variant they
// produce: integer and float samples, plain and "extensible" headers, mono
// and stereo, extra chunks before the data, and recorders that never fill in
// the data size.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/cabinet_ir.dart';

/// Builds a WAV file. [frames] holds one list of channel values per frame,
/// in [-1, 1]; they are encoded as [bits]-bit integers, or floats when
/// [float] is set.
Uint8List wav(
  List<List<double>> frames, {
  int bits = 16,
  bool float = false,
  bool extensible = false,
  int rate = 48000,
  bool oddChunkFirst = false,
  bool zeroDataSize = false,
  int? formatOverride,
}) {
  final channels = frames.first.length;
  final bytesPer = bits ~/ 8;
  final data = BytesBuilder();
  for (final frame in frames) {
    for (final v in frame) {
      data.add(_encode(v, bits, float));
    }
  }
  final format = formatOverride ?? (float ? 3 : 1);
  final fmt = BytesBuilder()
    ..add(_u16(extensible ? 0xFFFE : format))
    ..add(_u16(channels))
    ..add(_u32(rate))
    ..add(_u32(rate * channels * bytesPer))
    ..add(_u16(channels * bytesPer))
    ..add(_u16(bits));
  if (extensible) {
    fmt
      ..add(_u16(22)) // extension size
      ..add(_u16(bits)) // valid bits
      ..add(_u32(0)) // channel mask
      ..add(_u16(format)) // sub-format GUID, first two bytes
      ..add(List<int>.filled(14, 0));
  }
  final body = BytesBuilder()..add('WAVE'.codeUnits);
  if (oddChunkFirst) {
    body
      ..add('LIST'.codeUnits)
      ..add(_u32(3))
      ..add([1, 2, 3, 0]); // three bytes plus the pad byte
  }
  final fmtBytes = fmt.toBytes();
  body
    ..add('fmt '.codeUnits)
    ..add(_u32(fmtBytes.length))
    ..add(fmtBytes);
  final dataBytes = data.toBytes();
  body
    ..add('data'.codeUnits)
    ..add(_u32(zeroDataSize ? 0 : dataBytes.length))
    ..add(dataBytes);
  final bodyBytes = body.toBytes();
  return (BytesBuilder()
        ..add('RIFF'.codeUnits)
        ..add(_u32(bodyBytes.length))
        ..add(bodyBytes))
      .toBytes();
}

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) => [for (var i = 0; i < 4; i++) (v >> (8 * i)) & 0xFF];

List<int> _encode(double v, int bits, bool float) {
  final b = ByteData(8);
  if (float && bits == 32) {
    b.setFloat32(0, v, Endian.little);
    return b.buffer.asUint8List(0, 4);
  }
  if (float) {
    b.setFloat64(0, v, Endian.little);
    return b.buffer.asUint8List(0, 8);
  }
  if (bits == 8) return [((v * 127).round() + 128) & 0xFF];
  final scaled = (v * ((1 << (bits - 1)) - 1)).round();
  return [for (var i = 0; i < bits ~/ 8; i++) (scaled >> (8 * i)) & 0xFF];
}

/// A short decaying test IR, as one-channel frames.
List<List<double>> decay([int n = 64]) =>
    [for (var i = 0; i < n; i++) [(i.isEven ? 0.8 : -0.8) * (1 - i / n)]];

void main() {
  group('decoding', () {
    for (final bits in [8, 16, 24, 32]) {
      test('$bits-bit PCM', () {
        final ir = CabinetIr.fromWav(wav(decay(), bits: bits), 'cab.wav');
        expect(ir.samples.length, 64);
        expect(ir.samples[0], closeTo(0.8, 0.01));
        expect(ir.samples[1], closeTo(-0.8 * (1 - 1 / 64), 0.01));
      });
    }

    test('32- and 64-bit float, plain and extensible', () {
      for (final bits in [32, 64]) {
        for (final ext in [false, true]) {
          final ir = CabinetIr.fromWav(
            wav(decay(), bits: bits, float: true, extensible: ext),
            'f.wav',
          );
          expect(ir.samples[1], closeTo(-0.8 * (1 - 1 / 64), 1e-6),
              reason: '$bits-bit, extensible: $ext');
        }
      }
    });

    test('a stereo file gives its first channel', () {
      final frames = [
        for (var i = 0; i < 32; i++) [0.5, -0.25],
      ];
      final ir = CabinetIr.fromWav(wav(frames, bits: 24), 'st.wav');
      expect(ir.samples.every((v) => (v - 0.5).abs() < 1e-3), isTrue);
    });

    test('keeps the file rate', () {
      final ir = CabinetIr.fromWav(wav(decay(), rate: 44100), 'r.wav');
      expect(ir.sampleRate, 44100);
    });

    test('skips an odd-sized chunk before the data', () {
      final ir = CabinetIr.fromWav(wav(decay(), oddChunkFirst: true), 'o.wav');
      expect(ir.samples.length, 64);
    });

    test('a data size left at zero runs to the end of the file', () {
      final ir = CabinetIr.fromWav(wav(decay(), zeroDataSize: true), 'z.wav');
      expect(ir.samples.length, 64);
    });
  });

  group('rejects', () {
    void rejects(Uint8List bytes, CabinetIrError error) {
      expect(
        () => CabinetIr.fromWav(bytes, 'x.wav'),
        throwsA(isA<CabinetIrException>().having((e) => e.error, 'error', error)),
      );
    }

    test('a file that is not a WAV', () {
      rejects(Uint8List.fromList('ID3 this is an mp3'.codeUnits),
          CabinetIrError.notWav);
    });

    test('a compressed WAV', () {
      rejects(wav(decay(), formatOverride: 2), CabinetIrError.unsupportedFormat);
    });

    test('a silent IR', () {
      rejects(wav([for (var i = 0; i < 16; i++) [0.0]]), CabinetIrError.silent);
    });

    test('a WAV with no samples', () {
      final empty = wav([[0.5]]);
      // Cut the one sample off and declare an empty data chunk.
      final bytes = Uint8List.fromList(empty.sublist(0, empty.length - 2));
      ByteData.sublistView(bytes).setUint32(bytes.length - 4, 0, Endian.little);
      expect(
        () => CabinetIr.fromWav(bytes, 'e.wav'),
        throwsA(isA<CabinetIrException>()),
      );
    });
  });

  group('what is kept', () {
    test('silence before the attack is dropped', () {
      final frames = [
        for (var i = 0; i < 300; i++) [0.0],
        ...decay(),
      ];
      final ir = CabinetIr.fromWav(wav(frames, float: true, bits: 32), 's.wav');
      expect(ir.samples.length, 64);
      expect(ir.samples.first, closeTo(0.8, 1e-6));
    });

    test('a long file is cut at the storage cap', () {
      const rate = 8000;
      final frames = decay(rate); // one second
      final ir = CabinetIr.fromWav(wav(frames, rate: rate), 'l.wav');
      expect(ir.samples.length, (CabinetIr.maxStoredSeconds * rate).ceil());
    });
  });

  group('project file', () {
    test('round-trips exactly', () {
      final ir = CabinetIr.fromWav(
          wav(decay(), float: true, bits: 32, rate: 96000), 'My Cab.wav');
      final back = CabinetIr.fromJson(ir.toJson())!;
      expect(back.name, 'My Cab.wav');
      expect(back.sampleRate, 96000);
      expect(back.samples, ir.samples);
    });

    test('anything malformed reads as no IR', () {
      expect(CabinetIr.fromJson(null), isNull);
      expect(CabinetIr.fromJson('x'), isNull);
      expect(CabinetIr.fromJson({'name': 'a', 'rate': 48000}), isNull);
      expect(
          CabinetIr.fromJson({'name': 'a', 'rate': 48000, 'data': '%%%'}),
          isNull);
      expect(CabinetIr.fromJson({'name': 'a', 'rate': 48000, 'data': ''}),
          isNull);
    });
  });
}
