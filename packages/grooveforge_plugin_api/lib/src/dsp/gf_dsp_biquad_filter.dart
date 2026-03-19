import 'dart:math' as math;
import 'dart:typed_data';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

/// Second-order IIR (biquad) filter — the workhorse of digital EQ.
///
/// Implements the Audio EQ Cookbook formulas (Robert Bristow-Johnson).
/// Supported modes: low-pass, high-pass, band-pass, notch, peaking-EQ,
/// low-shelf, high-shelf.
///
/// Uses transposed direct form II which is numerically stable for the wide
/// frequency sweeps typical in parametric EQ and the wah effect.
///
/// | Node param  | Range          | Default | Description                              |
/// |------------|----------------|---------|------------------------------------------|
/// | `freq`     | 20–20000 Hz    | 1000    | Centre/corner frequency in Hz            |
/// | `q`        | 0.1–20.0       | 0.707   | Quality factor (bandwidth). Q=0.707=flat |
/// | `gain`     | -24–+24 dB     | 0       | Peaking/shelf gain in dB (EQ modes only) |
/// | `mode`     | 0–6            | 0       | Filter mode (see [BiquadMode])           |
///
/// All params are normalised [0,1] when set via [setParam].
enum BiquadMode {
  /// Passes frequencies below [freq]; rolls off above.
  lowPass, // 0

  /// Passes frequencies above [freq]; rolls off below.
  highPass, // 1

  /// Passes a narrow band centred on [freq]; controlled by [q].
  bandPass, // 2

  /// Rejects a narrow band centred on [freq]; notch/band-stop filter.
  notch, // 3

  /// Boosts or cuts a band centred on [freq] with gain [gainDb].
  peaking, // 4

  /// Applies a shelf boost/cut below [freq].
  lowShelf, // 5

  /// Applies a shelf boost/cut above [freq].
  highShelf, // 6
}

class GFDspBiquadFilterNode extends GFDspNode {
  int _sampleRate = 44100;

  // ── Parameters ─────────────────────────────────────────────────────────────

  double _freqHz = 1000.0;  // corner/centre frequency in Hz
  double _q = 0.707;        // quality factor
  double _gainDb = 0.0;     // only used in peaking/shelf modes
  BiquadMode _mode = BiquadMode.lowPass;

  // ── IIR coefficients (updated when params change) ─────────────────────────

  double _b0 = 1.0, _b1 = 0.0, _b2 = 0.0;
  double _a1 = 0.0, _a2 = 0.0; // a0 is normalised to 1

  // ── Filter state (transposed direct form II) ───────────────────────────────

  double _s1L = 0.0, _s2L = 0.0; // left channel delay elements
  double _s1R = 0.0, _s2R = 0.0; // right channel delay elements

  // ── Output buffers ─────────────────────────────────────────────────────────

  late Float32List _outL;
  late Float32List _outR;

  GFDspBiquadFilterNode(super.nodeId);

  @override
  List<String> get inputPortNames => const ['in'];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    _sampleRate = sampleRate;
    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
    _computeCoefficients();
  }

  // ── Parameters ─────────────────────────────────────────────────────────────

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'freq':
        // Map [0,1] → [20, 20000] Hz on an exponential curve.
        _freqHz = 20.0 * math.pow(1000.0, normalizedValue);
      case 'q':
        // Map [0,1] → [0.1, 20.0] on an exponential curve.
        _q = 0.1 * math.pow(200.0, normalizedValue);
      case 'gain':
        // Map [0,1] → [-24, +24] dB linearly.
        _gainDb = (normalizedValue * 48.0) - 24.0;
      case 'mode':
        // Map [0,1] to one of 7 integer modes.
        final index = (normalizedValue * 6.0).round().clamp(0, 6);
        _mode = BiquadMode.values[index];
    }
    _computeCoefficients();
  }

  // ── Coefficient computation ────────────────────────────────────────────────

  /// Recompute IIR coefficients from current parameters.
  ///
  /// Follows the Audio EQ Cookbook formulas exactly, so the implementation
  /// matches documented biquad filter behaviour at all sample rates.
  void _computeCoefficients() {
    final fs = _sampleRate.toDouble();
    final f0 = _freqHz.clamp(20.0, fs / 2.0 - 1.0);
    final w0 = 2.0 * math.pi * f0 / fs;
    final cosW0 = math.cos(w0);
    final sinW0 = math.sin(w0);
    final alpha = sinW0 / (2.0 * _q);
    final A = math.pow(10.0, _gainDb / 40.0).toDouble(); // amplitude = 10^(dBgain/40)

    double b0, b1, b2, a0, a1, a2;

    switch (_mode) {
      case BiquadMode.lowPass:
        b0 = (1.0 - cosW0) / 2.0;
        b1 = 1.0 - cosW0;
        b2 = (1.0 - cosW0) / 2.0;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;

      case BiquadMode.highPass:
        b0 = (1.0 + cosW0) / 2.0;
        b1 = -(1.0 + cosW0);
        b2 = (1.0 + cosW0) / 2.0;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;

      case BiquadMode.bandPass:
        // Constant 0 dB peak gain variant.
        b0 = alpha;
        b1 = 0.0;
        b2 = -alpha;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;

      case BiquadMode.notch:
        b0 = 1.0;
        b1 = -2.0 * cosW0;
        b2 = 1.0;
        a0 = 1.0 + alpha;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha;

      case BiquadMode.peaking:
        b0 = 1.0 + alpha * A;
        b1 = -2.0 * cosW0;
        b2 = 1.0 - alpha * A;
        a0 = 1.0 + alpha / A;
        a1 = -2.0 * cosW0;
        a2 = 1.0 - alpha / A;

      case BiquadMode.lowShelf:
        final sqrtA2alpha = 2.0 * math.sqrt(A) * alpha;
        b0 = A * ((A + 1.0) - (A - 1.0) * cosW0 + sqrtA2alpha);
        b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosW0);
        b2 = A * ((A + 1.0) - (A - 1.0) * cosW0 - sqrtA2alpha);
        a0 = (A + 1.0) + (A - 1.0) * cosW0 + sqrtA2alpha;
        a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosW0);
        a2 = (A + 1.0) + (A - 1.0) * cosW0 - sqrtA2alpha;

      case BiquadMode.highShelf:
        final sqrtA2alpha = 2.0 * math.sqrt(A) * alpha;
        b0 = A * ((A + 1.0) + (A - 1.0) * cosW0 + sqrtA2alpha);
        b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosW0);
        b2 = A * ((A + 1.0) + (A - 1.0) * cosW0 - sqrtA2alpha);
        a0 = (A + 1.0) - (A - 1.0) * cosW0 + sqrtA2alpha;
        a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosW0);
        a2 = (A + 1.0) - (A - 1.0) * cosW0 - sqrtA2alpha;
    }

    // Normalise by a0 so the recurrence relation is: y = b0*x + s1
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = a1 / a0;
    _a2 = a2 / a0;
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

    // Snapshot coefficients once per block (they change between blocks when
    // the user sweeps a knob, not within a block).
    final b0 = _b0, b1 = _b1, b2 = _b2, a1 = _a1, a2 = _a2;

    // Snapshot filter state into local variables for the inner loop.
    var s1L = _s1L, s2L = _s2L;
    var s1R = _s1R, s2R = _s2R;

    for (var i = 0; i < frameCount; i++) {
      final xL = src != null ? src.$1[i] : 0.0;
      final xR = src != null ? src.$2[i] : 0.0;

      // Transposed direct form II: y = b0*x + s1; s1 = b1*x - a1*y + s2; …
      final yL = b0 * xL + s1L;
      s1L = b1 * xL - a1 * yL + s2L;
      s2L = b2 * xL - a2 * yL;
      _outL[i] = yL;

      final yR = b0 * xR + s1R;
      s1R = b1 * xR - a1 * yR + s2R;
      s2R = b2 * xR - a2 * yR;
      _outR[i] = yR;
    }

    // Write back filter state.
    _s1L = s1L;
    _s2L = s2L;
    _s1R = s1R;
    _s2R = s2R;
  }
}
