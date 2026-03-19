import 'dart:typed_data';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Freeverb constants (tuned for 44100 Hz)
// ─────────────────────────────────────────────────────────────────────────────

/// Comb filter buffer lengths (samples at 44 100 Hz), left channel.
const _combLengthsL = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];

/// Comb filter buffer lengths, right channel = left + stereo spread.
const _stereoSpread = 23;

/// Allpass filter buffer lengths, left channel.
const _allpassLengthsL = [556, 441, 341, 225];

/// Internal Freeverb gain constant applied before the comb bank.
const _fixedGain = 0.015;

// ─────────────────────────────────────────────────────────────────────────────
//  `freeverb` node
// ─────────────────────────────────────────────────────────────────────────────

/// `freeverb` node — stereo plate reverb based on the Freeverb algorithm.
///
/// Freeverb (Jezar at Dreampoint, 1997) uses a bank of 8 feedback comb filters
/// in parallel followed by 4 allpass filters in series, duplicated for stereo
/// with slightly different buffer lengths (the "stereo spread"). It produces a
/// dense, natural-sounding room or plate reverb at very low CPU cost.
///
/// | Node param   | Range     | Default | Description                        |
/// |-------------|-----------|---------|-------------------------------------|
/// | `roomSize`  | 0.0–1.0   | 0.5     | Reverb length (room size)           |
/// | `damping`   | 0.0–1.0   | 0.5     | High-frequency absorption           |
/// | `width`     | 0.0–1.0   | 1.0     | Stereo width of reverb tail         |
///
/// The output of this node is the fully-wet reverb tail. Connect it to a
/// [GFDspWetDryNode] to blend with the dry signal.
class GFDspFreeverbNode extends GFDspNode {
  // ── Parameters (written by UI thread, read by audio thread) ────────────────

  /// Room-size coefficient → comb feedback gain in [0.84, 1.12].
  double _roomSize = 0.84;

  /// High-frequency damping coefficient in [0, 0.4].
  double _damping = 0.2;

  /// Stereo width coefficient in [0, 1].
  double _width = 1.0;

  // ── Comb filter state ──────────────────────────────────────────────────────

  late List<Float32List> _combBufL; // 8 circular buffers, left channel
  late List<Float32List> _combBufR; // 8 circular buffers, right channel
  final List<int> _combIdxL = List.filled(8, 0); // write heads
  final List<int> _combIdxR = List.filled(8, 0);
  final List<double> _combFilterStateL = List.filled(8, 0.0); // low-pass memory
  final List<double> _combFilterStateR = List.filled(8, 0.0);

  // ── Allpass filter state ───────────────────────────────────────────────────

  late List<Float32List> _apBufL; // 4 allpass buffers, left channel
  late List<Float32List> _apBufR; // 4 allpass buffers, right channel
  final List<int> _apIdxL = List.filled(4, 0); // write heads
  final List<int> _apIdxR = List.filled(4, 0);

  // ── Output buffers ─────────────────────────────────────────────────────────

  late Float32List _outL;
  late Float32List _outR;

  GFDspFreeverbNode(super.nodeId);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  List<String> get inputPortNames => const ['in'];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    // Scale buffer lengths for sample rates other than 44 100 Hz.
    final scale = sampleRate / 44100.0;

    _combBufL = List.generate(
      8,
      (i) => Float32List((_combLengthsL[i] * scale).round()),
    );
    _combBufR = List.generate(
      8,
      (i) => Float32List(((_combLengthsL[i] + _stereoSpread) * scale).round()),
    );

    _apBufL = List.generate(
      4,
      (i) => Float32List((_allpassLengthsL[i] * scale).round()),
    );
    _apBufR = List.generate(
      4,
      (i) => Float32List(((_allpassLengthsL[i] + _stereoSpread) * scale).round()),
    );

    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
  }

  // ── Parameters ─────────────────────────────────────────────────────────────

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'roomSize':
        // Map [0,1] → [0.84, 1.12] following Freeverb's scaleRoom/offsetRoom.
        _roomSize = 0.84 + normalizedValue * 0.28;
      case 'damping':
        // Map [0,1] → [0, 0.4].
        _damping = normalizedValue * 0.4;
      case 'width':
        _width = normalizedValue.clamp(0.0, 1.0);
    }
  }

  // ── Output buffers ─────────────────────────────────────────────────────────

  @override
  Float32List outputL(String portName) => _outL;

  @override
  Float32List outputR(String portName) => _outR;

  // ── Processing ─────────────────────────────────────────────────────────────

  @override
  void processBlock(
    Map<String, (Float32List, Float32List)> inputs,
    int frameCount,
    GFTransportContext transport,
  ) {
    final src = inputs['in'];

    // Cache parameter snapshots at the top of the block — avoids repeated
    // field reads inside the per-sample loop (safe: doubles are atomic).
    final feedback = _roomSize;
    final damp1 = _damping;
    final damp2 = 1.0 - damp1;
    final wet1 = _width / 2.0 + 0.5; // left-channel wet coefficient
    final wet2 = (1.0 - _width) / 2.0; // right-to-left cross-mix

    for (var i = 0; i < frameCount; i++) {
      // Mono input mix (average L+R) with fixed gain into the reverb bank.
      final srcL = src != null ? src.$1[i] : 0.0;
      final srcR = src != null ? src.$2[i] : 0.0;
      final monoIn = (srcL + srcR) * _fixedGain;

      var outL = 0.0;
      var outR = 0.0;

      // ── 8 feedback comb filters (parallel, independent L/R) ──────────────
      for (var c = 0; c < 8; c++) {
        outL += _processCombL(c, monoIn, feedback, damp1, damp2);
        outR += _processCombR(c, monoIn, feedback, damp1, damp2);
      }

      // ── 4 allpass filters (serial, independent L/R) ───────────────────────
      for (var a = 0; a < 4; a++) {
        outL = _processAllpassL(a, outL);
        outR = _processAllpassR(a, outR);
      }

      // Stereo width spread: mix L/R outputs so width=0 gives mono reverb.
      _outL[i] = outL * wet1 + outR * wet2;
      _outR[i] = outR * wet1 + outL * wet2;
    }
  }

  // ── Per-filter helpers (inlined for zero-allocation) ──────────────────────

  /// Process one sample through comb filter [c] on the left channel.
  ///
  /// The Freeverb comb filter is a feedback comb with an embedded one-pole
  /// low-pass filter that provides high-frequency damping. Damping models
  /// air absorption in a room: high frequencies decay faster than lows.
  double _processCombL(
    int c,
    double input,
    double feedback,
    double damp1,
    double damp2,
  ) {
    final buf = _combBufL[c];
    final idx = _combIdxL[c];
    final output = buf[idx];
    // Low-pass: damped output = output*(1-damp) + prevLowPass*damp
    _combFilterStateL[c] = output * damp2 + _combFilterStateL[c] * damp1;
    buf[idx] = input + _combFilterStateL[c] * feedback;
    _combIdxL[c] = (idx + 1) % buf.length;
    return output;
  }

  /// Process one sample through comb filter [c] on the right channel.
  double _processCombR(
    int c,
    double input,
    double feedback,
    double damp1,
    double damp2,
  ) {
    final buf = _combBufR[c];
    final idx = _combIdxR[c];
    final output = buf[idx];
    _combFilterStateR[c] = output * damp2 + _combFilterStateR[c] * damp1;
    buf[idx] = input + _combFilterStateR[c] * feedback;
    _combIdxR[c] = (idx + 1) % buf.length;
    return output;
  }

  /// Process one sample through allpass filter [a] on the left channel.
  ///
  /// The allpass filter preserves frequency magnitude but scatters phase,
  /// thickening the reverb density without colouring the spectrum.
  double _processAllpassL(int a, double input) {
    final buf = _apBufL[a];
    final idx = _apIdxL[a];
    final bufOut = buf[idx];
    buf[idx] = input + bufOut * 0.5;
    _apIdxL[a] = (idx + 1) % buf.length;
    return bufOut - input;
  }

  /// Process one sample through allpass filter [a] on the right channel.
  double _processAllpassR(int a, double input) {
    final buf = _apBufR[a];
    final idx = _apIdxR[a];
    final bufOut = buf[idx];
    buf[idx] = input + bufOut * 0.5;
    _apIdxR[a] = (idx + 1) % buf.length;
    return bufOut - input;
  }
}
