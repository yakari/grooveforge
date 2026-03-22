import 'dart:math' as math;
import 'dart:typed_data';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

/// `compressor` node — RMS dynamics compressor with attack / release envelope.
///
/// A compressor reduces the dynamic range of a signal: loud passages are
/// attenuated while quiet passages are left relatively unchanged. The key
/// parameters are:
/// - **Threshold**: the level above which compression starts.
/// - **Ratio**: how much gain reduction is applied above the threshold. A ratio
///   of 4:1 means that for every 4 dB the signal exceeds the threshold only
///   1 dB comes through.
/// - **Attack**: how quickly the compressor reacts to a loud signal.
/// - **Release**: how quickly it lets go after the signal falls back below the
///   threshold.
/// - **Makeup gain**: post-compression amplification to restore perceived volume.
///
/// This implementation uses RMS (root-mean-square) level detection which is
/// smoother and more musical than peak detection.
///
/// | Node param   | Range         | Default | Description                        |
/// |-------------|--------------|---------|-------------------------------------|
/// | `threshold` | -60–0 dB      | -18     | Level above which compression starts|
/// | `ratio`     | 1.0–20.0      | 4.0     | Compression ratio (x:1)            |
/// | `attack`    | 0.1–200 ms    | 10      | Attack time in milliseconds         |
/// | `release`   | 10–2000 ms    | 100     | Release time in milliseconds        |
/// | `makeup`    | 0–+24 dB      | 0       | Post-compression makeup gain in dB  |
class GFDspCompressorNode extends GFDspNode {
  int _sampleRate = 44100;

  // ── Parameters ─────────────────────────────────────────────────────────────

  double _thresholdDb = -18.0;
  double _ratio = 4.0;
  double _attackMs = 10.0;
  double _releaseMs = 100.0;
  double _makeupDb = 0.0;

  // ── Envelope follower state ────────────────────────────────────────────────

  double _envelope = 0.0; // current gain reduction envelope (linear)

  // ── Output buffers ─────────────────────────────────────────────────────────

  late Float32List _outL;
  late Float32List _outR;

  GFDspCompressorNode(super.nodeId);

  @override
  List<String> get inputPortNames => const ['in'];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    _sampleRate = sampleRate;
    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'threshold':
        // Map [0,1] → [-60, 0] dB.
        _thresholdDb = -60.0 + normalizedValue * 60.0;
      case 'ratio':
        // Map [0,1] → [1.0, 20.0] on an exponential curve.
        _ratio = 1.0 + normalizedValue * 19.0;
      case 'attack':
        // Map [0,1] → [0.1, 200] ms.
        _attackMs = 0.1 + normalizedValue * 199.9;
      case 'release':
        // Map [0,1] → [10, 2000] ms.
        _releaseMs = 10.0 + normalizedValue * 1990.0;
      case 'makeup':
        // Map [0,1] → [0, 24] dB.
        _makeupDb = normalizedValue * 24.0;
    }
  }

  @override
  Float32List outputL(String portName) => _outL;

  @override
  Float32List outputR(String portName) => _outR;

  @override
  void processBlock(
    Map<String, (Float32List, Float32List)> inputs,
    int frameCount,
    GFTransportContext transport,
  ) {
    final src = inputs['in'];

    // Pre-compute per-sample time constants from attack/release in ms.
    // τ = -1 / (fs * ln(0.01)) gives a ~99% rise in the stated time.
    final attackCoeff = math.exp(-1.0 / (_sampleRate * _attackMs / 1000.0));
    final releaseCoeff = math.exp(-1.0 / (_sampleRate * _releaseMs / 1000.0));

    // Linear threshold and makeup gain (convert from dB once per block).
    final threshold = math.pow(10.0, _thresholdDb / 20.0).toDouble();
    final makeup = math.pow(10.0, _makeupDb / 20.0).toDouble();
    final ratio = _ratio;

    var env = _envelope;

    for (var i = 0; i < frameCount; i++) {
      final inL = src != null ? src.$1[i] : 0.0;
      final inR = src != null ? src.$2[i] : 0.0;

      // ── RMS-level detector (mono sum for simplicity) ──────────────────────
      final rms = math.sqrt((inL * inL + inR * inR) * 0.5);

      // ── Gain computer: how much do we want to reduce? ─────────────────────
      // Above threshold, apply ratio. Below threshold, gain = 1.0 (bypass).
      final double targetGain;
      if (rms > threshold && threshold > 0) {
        // Gain reduction in dB: GR = (level - threshold) * (1 - 1/ratio).
        // Simplified linear version: targetGain = threshold/rms * (1/ratio) ...
        // We use the log-domain version for accuracy.
        final overDb = 20.0 * math.log(rms / threshold) / math.ln10;
        final reductionDb = overDb * (1.0 - 1.0 / ratio);
        targetGain = math.pow(10.0, -reductionDb / 20.0).toDouble();
      } else {
        targetGain = 1.0;
      }

      // ── Smooth envelope (attack when reducing, release when opening) ───────
      if (targetGain < env) {
        env = attackCoeff * env + (1.0 - attackCoeff) * targetGain;
      } else {
        env = releaseCoeff * env + (1.0 - releaseCoeff) * targetGain;
      }

      // Apply gain reduction + makeup gain.
      final g = env * makeup;
      _outL[i] = inL * g;
      _outR[i] = inR * g;
    }

    _envelope = env;
  }
}
