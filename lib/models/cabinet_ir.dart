import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// Why a file could not be used as a cabinet impulse response.
///
/// An enum rather than a message so the panel can show it in the player's
/// language.
enum CabinetIrError {
  /// Not a RIFF/WAVE file at all.
  notWav,

  /// A WAV in a sample format this reader does not decode (compressed
  /// formats such as ADPCM or MP3-in-WAV).
  unsupportedFormat,

  /// A valid WAV with no sample data.
  noAudio,

  /// Sample data that is all zeros.
  silent,
}

/// Thrown by [CabinetIr.fromWav] when a file cannot be used.
class CabinetIrException implements Exception {
  /// Creates an exception for [error].
  const CabinetIrException(this.error);

  /// What was wrong with the file.
  final CabinetIrError error;

  @override
  String toString() => 'CabinetIrException(${error.name})';
}

/// A speaker-cabinet impulse response loaded into an Amp slot.
///
/// An impulse response (IR) is a recording of what a cabinet and its
/// microphone did to a single click. Played through the Amp's convolver, it
/// makes the guitar sound as if it came out of that cabinet. IR files are
/// small WAVs that guitarists collect and share.
///
/// The IR is stored inside the `.gf` project — not as a path — so a project
/// opened on another device, or after the original file was moved, still
/// sounds the same. Only what the Amp can use is kept: the first channel,
/// from the attack on, for at most [maxStoredSeconds]. That is about 50 KB
/// in the project at 48 kHz.
class CabinetIr {
  /// Creates an IR from already-decoded mono [samples] at [sampleRate] Hz.
  CabinetIr({
    required this.name,
    required this.sampleRate,
    required this.samples,
  });

  /// Key of the IR in the Amp slot's state map. The double underscore marks
  /// it as slot data rather than a descriptor parameter, so the rack keeps it
  /// when the knobs rewrite the parameters.
  static const String stateKey = '__cabIr';

  /// Longest IR kept. The native Amp uses at most 0.1 s of it (see
  /// GF_AMP_IR_MAX_SEC in native_audio/gf_amp.h); the margin covers the
  /// native side trimming a little more from the start than this side does.
  static const double maxStoredSeconds = 0.25;

  /// Samples before the first one within this ratio of the peak (-60 dB) are
  /// dropped: silence before the attack would only take room in the project.
  static const double _attackRatio = 1e-3;

  /// What the player sees: the file name without its folder.
  final String name;

  /// Rate the IR was recorded at, in Hz.
  final double sampleRate;

  /// Mono samples, from the attack on.
  final Float32List samples;

  /// Decodes a WAV file's [bytes] into an IR named [name].
  ///
  /// Accepts 8/16/24/32-bit integer and 32/64-bit float WAVs, plain or
  /// "extensible", at any rate and channel count; the first channel is used.
  /// (A stereo IR usually holds two microphones, and averaging them would
  /// put comb-filter notches in the sound.)
  ///
  /// Throws [CabinetIrException] when the file cannot be used.
  factory CabinetIr.fromWav(Uint8List bytes, String name) {
    final wav = _WavReader(bytes);
    final mono = wav.firstChannel();
    if (mono.isEmpty) throw const CabinetIrException(CabinetIrError.noAudio);
    return CabinetIr(
      name: name,
      sampleRate: wav.sampleRate.toDouble(),
      samples: _keepUsefulPart(mono, wav.sampleRate),
    );
  }

  /// Restores an IR saved by [toJson], or returns null for anything else —
  /// an old or hand-edited project must open, just without its IR.
  static CabinetIr? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final rate = json['rate'];
    final data = json['data'];
    if (name is! String || rate is! num || data is! String) return null;
    try {
      final bytes = base64Decode(data);
      final view = ByteData.sublistView(bytes);
      final samples = Float32List(bytes.length ~/ 4);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = view.getFloat32(i * 4, Endian.little);
      }
      if (samples.isEmpty) return null;
      return CabinetIr(name: name, sampleRate: rate.toDouble(), samples: samples);
    } on FormatException {
      return null;
    }
  }

  /// Serialises the IR for the project file: samples as little-endian 32-bit
  /// floats in base64, so the file reads the same on every platform.
  Map<String, dynamic> toJson() {
    final data = ByteData(samples.length * 4);
    for (var i = 0; i < samples.length; i++) {
      data.setFloat32(i * 4, samples[i], Endian.little);
    }
    return {
      'name': name,
      'rate': sampleRate,
      'data': base64Encode(data.buffer.asUint8List()),
    };
  }

  /// Drops the silence before the attack and anything past
  /// [maxStoredSeconds]. Throws when the IR is all zeros.
  static Float32List _keepUsefulPart(Float32List x, int rate) {
    var peak = 0.0;
    for (final v in x) {
      if (v.isFinite) peak = math.max(peak, v.abs());
    }
    if (peak == 0.0) throw const CabinetIrException(CabinetIrError.silent);
    var start = 0;
    while (start < x.length && !(x[start].abs() >= peak * _attackRatio)) {
      start++;
    }
    final cap = (maxStoredSeconds * rate).ceil();
    final end = math.min(x.length, start + cap);
    return Float32List.fromList(x.sublist(start, end));
  }
}

/// Minimal WAV decoder: walks the RIFF chunks for `fmt ` and `data` and
/// decodes the first channel to floats in [-1, 1].
class _WavReader {
  _WavReader(this._bytes) : _view = ByteData.sublistView(_bytes) {
    _parse();
  }

  final Uint8List _bytes;
  final ByteData _view;

  /// WAVE_FORMAT_PCM, WAVE_FORMAT_IEEE_FLOAT and WAVE_FORMAT_EXTENSIBLE.
  static const int _formatPcm = 1;
  static const int _formatFloat = 3;
  static const int _formatExtensible = 0xFFFE;

  int format = 0;
  int channels = 0;
  int sampleRate = 0;
  int bitsPerSample = 0;
  int _dataOffset = -1;
  int _dataLength = 0;

  /// Reads the header and finds the sample data.
  void _parse() {
    if (_bytes.length < 12 ||
        _fourCc(0) != 'RIFF' ||
        _fourCc(8) != 'WAVE') {
      throw const CabinetIrException(CabinetIrError.notWav);
    }
    var offset = 12;
    while (offset + 8 <= _bytes.length) {
      final id = _fourCc(offset);
      final size = _view.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'fmt ') _readFormat(body, size);
      if (id == 'data') {
        _dataOffset = body;
        // Streaming recorders sometimes leave the size at 0 or 0xFFFFFFFF;
        // the data then runs to the end of the file.
        final available = _bytes.length - body;
        _dataLength = (size == 0 || size > available) ? available : size;
        break;
      }
      // Chunks are padded to an even length.
      offset = body + size + (size & 1);
    }
    if (channels == 0 || _dataOffset < 0) {
      throw const CabinetIrException(CabinetIrError.notWav);
    }
    if (!_supported) {
      throw const CabinetIrException(CabinetIrError.unsupportedFormat);
    }
  }

  /// Reads the `fmt ` chunk. An extensible header's real format is the first
  /// two bytes of its sub-format GUID.
  void _readFormat(int at, int size) {
    if (size < 16 || at + 16 > _bytes.length) return;
    format = _view.getUint16(at, Endian.little);
    channels = _view.getUint16(at + 2, Endian.little);
    sampleRate = _view.getUint32(at + 4, Endian.little);
    bitsPerSample = _view.getUint16(at + 14, Endian.little);
    if (format == _formatExtensible && size >= 26 && at + 26 <= _bytes.length) {
      format = _view.getUint16(at + 24, Endian.little);
    }
  }

  bool get _supported {
    if (sampleRate <= 0) return false;
    if (format == _formatPcm) return const [8, 16, 24, 32].contains(bitsPerSample);
    if (format == _formatFloat) return bitsPerSample == 32 || bitsPerSample == 64;
    return false;
  }

  String _fourCc(int at) => String.fromCharCodes(_bytes, at, at + 4);

  /// The first channel's samples as floats.
  Float32List firstChannel() {
    final bytesPerSample = bitsPerSample ~/ 8;
    final frameBytes = bytesPerSample * channels;
    final frames = _dataLength ~/ frameBytes;
    final out = Float32List(frames);
    for (var i = 0; i < frames; i++) {
      out[i] = _sample(_dataOffset + i * frameBytes);
    }
    return out;
  }

  /// One sample at byte [at], scaled to [-1, 1].
  double _sample(int at) {
    if (format == _formatFloat) {
      return bitsPerSample == 32
          ? _view.getFloat32(at, Endian.little)
          : _view.getFloat64(at, Endian.little);
    }
    switch (bitsPerSample) {
      case 8:
        return (_view.getUint8(at) - 128) / 128.0; // 8-bit WAV is unsigned
      case 16:
        return _view.getInt16(at, Endian.little) / 32768.0;
      case 24:
        // Three little-endian bytes, sign-extended from bit 23.
        var v = _bytes[at] | (_bytes[at + 1] << 8) | (_bytes[at + 2] << 16);
        if (v & 0x800000 != 0) v -= 0x1000000;
        return v / 8388608.0;
      default:
        return _view.getInt32(at, Endian.little) / 2147483648.0;
    }
  }
}
