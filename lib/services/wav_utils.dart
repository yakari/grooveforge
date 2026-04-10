import 'dart:io';
import 'dart:typed_data';

/// Utilities for reading and writing 32-bit float stereo WAV files.
///
/// Used by the audio looper to persist PCM clip data as sidecar files
/// alongside the `.gf` project JSON.  WAV format chosen over raw `.pcm`
/// because it embeds sample rate, channel count, and bit depth — any
/// audio tool (Audacity, SoX, ffmpeg) can open the files for inspection.

// ── WAV constants ──────────────────────────────────────────────────────────

/// WAV header size for PCM/float format with a single data chunk.
const int _wavHeaderSize = 44;

/// Format tag for IEEE 754 32-bit float samples.
const int _wavFormatFloat = 3;

// ── Write ──────────────────────────────────────────────────────────────────

/// Writes a 32-bit float stereo WAV file from native PCM buffers.
///
/// [dataL] and [dataR] are native `float*` pointers (from the audio looper).
/// [lengthFrames] is the number of stereo frames to write.
/// [sampleRate] is the sample rate (e.g. 48000).
/// [path] is the output file path.
///
/// The samples are interleaved (L0, R0, L1, R1, …) in the WAV data chunk.
/// This function runs synchronously — call from an isolate for large files.
/// [dataL] and [dataR] are native float pointers (Pointer from dart:ffi).
/// Passed as dynamic to avoid importing dart:ffi in this file (web compat).
void writeWavFile({
  required dynamic dataL,
  required dynamic dataR,
  required int lengthFrames,
  required int sampleRate,
  required String path,
}) {
  final numChannels = 2;
  final bitsPerSample = 32;
  final bytesPerSample = bitsPerSample ~/ 8;
  final blockAlign = numChannels * bytesPerSample;
  final byteRate = sampleRate * blockAlign;
  final dataSize = lengthFrames * blockAlign;
  final fileSize = _wavHeaderSize + dataSize - 8; // RIFF chunk size excludes first 8 bytes

  final buffer = ByteData(_wavHeaderSize + dataSize);
  var offset = 0;

  // ── RIFF header ──────────────────────────────────────────────────────
  // "RIFF"
  buffer.setUint8(offset++, 0x52); // R
  buffer.setUint8(offset++, 0x49); // I
  buffer.setUint8(offset++, 0x46); // F
  buffer.setUint8(offset++, 0x46); // F
  // File size - 8
  buffer.setUint32(offset, fileSize, Endian.little);
  offset += 4;
  // "WAVE"
  buffer.setUint8(offset++, 0x57); // W
  buffer.setUint8(offset++, 0x41); // A
  buffer.setUint8(offset++, 0x56); // V
  buffer.setUint8(offset++, 0x45); // E

  // ── fmt chunk ────────────────────────────────────────────────────────
  // "fmt "
  buffer.setUint8(offset++, 0x66); // f
  buffer.setUint8(offset++, 0x6D); // m
  buffer.setUint8(offset++, 0x74); // t
  buffer.setUint8(offset++, 0x20); // (space)
  // Chunk size (16 for PCM/float without extra params)
  buffer.setUint32(offset, 16, Endian.little);
  offset += 4;
  // Audio format (3 = IEEE float)
  buffer.setUint16(offset, _wavFormatFloat, Endian.little);
  offset += 2;
  // Number of channels
  buffer.setUint16(offset, numChannels, Endian.little);
  offset += 2;
  // Sample rate
  buffer.setUint32(offset, sampleRate, Endian.little);
  offset += 4;
  // Byte rate
  buffer.setUint32(offset, byteRate, Endian.little);
  offset += 4;
  // Block align
  buffer.setUint16(offset, blockAlign, Endian.little);
  offset += 2;
  // Bits per sample
  buffer.setUint16(offset, bitsPerSample, Endian.little);
  offset += 2;

  // ── data chunk ───────────────────────────────────────────────────────
  // "data"
  buffer.setUint8(offset++, 0x64); // d
  buffer.setUint8(offset++, 0x61); // a
  buffer.setUint8(offset++, 0x74); // t
  buffer.setUint8(offset++, 0x61); // a
  // Data size
  buffer.setUint32(offset, dataSize, Endian.little);
  offset += 4;

  // Interleave L/R samples into the data chunk.
  for (int i = 0; i < lengthFrames; i++) {
    buffer.setFloat32(offset, dataL[i], Endian.little);
    offset += 4;
    buffer.setFloat32(offset, dataR[i], Endian.little);
    offset += 4;
  }

  File(path).writeAsBytesSync(buffer.buffer.asUint8List());
}

// ── Read ───────────────────────────────────────────────────────────────────

/// Result of reading a WAV file.
class WavData {
  /// Left channel samples.
  final Float32List left;

  /// Right channel samples.
  final Float32List right;

  /// Sample rate from the WAV header.
  final int sampleRate;

  /// Number of stereo frames.
  int get lengthFrames => left.length;

  const WavData({required this.left, required this.right, required this.sampleRate});
}

/// Reads a 32-bit float stereo WAV file and returns deinterleaved L/R buffers.
///
/// Throws [FormatException] if the file is not a valid 32-bit float stereo WAV.
/// This function runs synchronously — call from an isolate for large files.
WavData readWavFile(String path) {
  final bytes = File(path).readAsBytesSync();
  final data = ByteData.sublistView(bytes);

  if (bytes.length < _wavHeaderSize) {
    throw FormatException('WAV file too small: ${bytes.length} bytes');
  }

  // Validate RIFF header.
  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  if (riff != 'RIFF') throw FormatException('Not a RIFF file');
  final wave = String.fromCharCodes(bytes.sublist(8, 12));
  if (wave != 'WAVE') throw FormatException('Not a WAVE file');

  // Parse fmt chunk.
  final fmt = String.fromCharCodes(bytes.sublist(12, 16));
  if (fmt != 'fmt ') throw FormatException('Missing fmt chunk');

  final audioFormat = data.getUint16(20, Endian.little);
  if (audioFormat != _wavFormatFloat) {
    throw FormatException(
        'Unsupported WAV format: $audioFormat (expected IEEE float = $_wavFormatFloat)');
  }

  final numChannels = data.getUint16(22, Endian.little);
  if (numChannels != 2) {
    throw FormatException('Expected stereo (2 channels), got $numChannels');
  }

  final sampleRate = data.getUint32(24, Endian.little);
  final bitsPerSample = data.getUint16(34, Endian.little);
  if (bitsPerSample != 32) {
    throw FormatException('Expected 32-bit samples, got $bitsPerSample');
  }

  // Find the data chunk (may not be at offset 36 if extra fmt params exist).
  int dataOffset = 36;
  final fmtChunkSize = data.getUint32(16, Endian.little);
  dataOffset = 20 + fmtChunkSize; // skip past fmt chunk payload
  // Scan for "data" chunk ID.
  while (dataOffset + 8 < bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(dataOffset, dataOffset + 4));
    final chunkSize = data.getUint32(dataOffset + 4, Endian.little);
    if (chunkId == 'data') {
      dataOffset += 8; // skip chunk header
      final lengthFrames = chunkSize ~/ (numChannels * (bitsPerSample ~/ 8));
      final left = Float32List(lengthFrames);
      final right = Float32List(lengthFrames);

      // Deinterleave: L0, R0, L1, R1, …
      var off = dataOffset;
      for (int i = 0; i < lengthFrames; i++) {
        left[i] = data.getFloat32(off, Endian.little);
        off += 4;
        right[i] = data.getFloat32(off, Endian.little);
        off += 4;
      }
      return WavData(left: left, right: right, sampleRate: sampleRate);
    }
    // Skip unknown chunk.
    dataOffset += 8 + chunkSize;
    // Chunks are word-aligned.
    if (chunkSize % 2 != 0) dataOffset++;
  }
  throw FormatException('No data chunk found in WAV file');
}
