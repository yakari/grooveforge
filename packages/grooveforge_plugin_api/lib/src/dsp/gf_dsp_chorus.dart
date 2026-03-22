import 'dart:math' as math;
import 'dart:typed_data';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

/// `chorus` node — stereo chorus / flanger with BPM-syncable rate.
///
/// Chorus is created by mixing the original (dry) signal with one or more
/// slightly-delayed, pitch-modulated copies. The delay time is modulated by
/// an LFO, producing the characteristic "shimmering" ensemble sound.
///
/// The left and right channels use LFOs 180° out of phase, which spreads the
/// effect across the stereo field and gives a wide, immersive sound.
///
/// At very short delay times (< 10 ms) and high modulation depth the effect
/// becomes a **flanger** (comb-filter sweep). At longer delays (20–50 ms)
/// with subtle depth it becomes a **chorus**.
///
/// | Node param   | Range        | Default | Description                           |
/// |-------------|-------------|---------|----------------------------------------|
/// | `rate`      | 0.1–10 Hz    | 0.5     | LFO modulation rate                   |
/// | `depth`     | 0.0–1.0      | 0.5     | Modulation depth (delay sweep range)  |
/// | `delay`     | 5–50 ms      | 20      | Centre delay time in milliseconds     |
/// | `mix`       | 0.0–1.0      | 0.5     | Dry/wet blend (0=dry, 1=wet)          |
/// | `feedback`  | 0.0–0.9      | 0.0     | Feedback for flanger-style resonance  |
/// | `bpmSync`   | 0/1 toggle   | 0       | Lock LFO rate to BPM                  |
/// | `beatDiv`   | 0–5 index    | 3       | Beat division for BPM sync            |
class GFDspChorusNode extends GFDspNode {
  static const _kBeatDivs = [8.0, 4.0, 2.0, 1.0, 0.5, 0.25];

  // Maximum modulated delay: 50 ms + 25 ms depth at 48 000 Hz ≈ 3600 samples.
  static const _kMaxDelaySamples = 4096;

  int _sampleRate = 44100;

  // ── Parameters ─────────────────────────────────────────────────────────────

  double _rateHz = 0.5;
  double _depth = 0.5;
  double _delayMs = 20.0;
  double _mix = 0.5;
  double _feedback = 0.0;
  bool _bpmSync = false;
  int _beatDivIndex = 3;

  // ── Delay buffers (circular) ───────────────────────────────────────────────

  late Float32List _delayBufL;
  late Float32List _delayBufR;
  int _writeIdx = 0;

  // ── LFO state (two channels, 180° apart) ──────────────────────────────────

  double _phaseL = 0.0;             // left channel LFO phase
  double _phaseR = math.pi;         // right channel — offset by half cycle

  // ── Output buffers ─────────────────────────────────────────────────────────

  late Float32List _outL;
  late Float32List _outR;

  GFDspChorusNode(super.nodeId);

  @override
  List<String> get inputPortNames => const ['in'];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    _sampleRate = sampleRate;
    _delayBufL = Float32List(_kMaxDelaySamples);
    _delayBufR = Float32List(_kMaxDelaySamples);
    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'rate':
        _rateHz = 0.1 + normalizedValue * 9.9;
      case 'depth':
        _depth = normalizedValue.clamp(0.0, 1.0);
      case 'delay':
        _delayMs = 5.0 + normalizedValue * 45.0;
      case 'mix':
        _mix = normalizedValue.clamp(0.0, 1.0);
      case 'feedback':
        _feedback = normalizedValue * 0.9;
      case 'bpmSync':
        _bpmSync = normalizedValue >= 0.5;
      case 'beatDiv':
        _beatDivIndex = (normalizedValue * (_kBeatDivs.length - 1))
            .round()
            .clamp(0, _kBeatDivs.length - 1);
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

    // Effective LFO rate.
    final double rateHz;
    if (_bpmSync && transport.bpm > 0) {
      rateHz = (transport.bpm / 60.0) / _kBeatDivs[_beatDivIndex];
    } else {
      rateHz = _rateHz;
    }
    final phaseInc = 2.0 * math.pi * rateHz / _sampleRate;

    // Centre delay in samples. Depth scales the modulation swing around it.
    final centreDelaySamples = _delayMs / 1000.0 * _sampleRate;
    // Maximum modulation swing = depth * centreDelay (swing in samples).
    final swing = _depth * centreDelaySamples;

    final mix = _mix;
    final dry = 1.0 - mix;
    final fb = _feedback;

    var phaseL = _phaseL;
    var phaseR = _phaseR;
    var writeIdx = _writeIdx;

    for (var i = 0; i < frameCount; i++) {
      final inL = src != null ? src.$1[i] : 0.0;
      final inR = src != null ? src.$2[i] : 0.0;

      // ── LFO-modulated read positions (fractional sample indices) ───────────
      final delayL = centreDelaySamples + swing * math.sin(phaseL);
      final delayR = centreDelaySamples + swing * math.sin(phaseR);

      // ── Linear interpolation for fractional delay ─────────────────────────
      // Integer and fractional parts of the delay.
      final int dIntL = delayL.toInt();
      final fracL = delayL - dIntL;
      final int dIntR = delayR.toInt();
      final fracR = delayR - dIntR;

      // Clamp read indices to valid buffer range.
      final r0L = (writeIdx - dIntL + _kMaxDelaySamples) % _kMaxDelaySamples;
      final r1L = (r0L - 1 + _kMaxDelaySamples) % _kMaxDelaySamples;
      final r0R = (writeIdx - dIntR + _kMaxDelaySamples) % _kMaxDelaySamples;
      final r1R = (r0R - 1 + _kMaxDelaySamples) % _kMaxDelaySamples;

      // Interpolated delayed samples.
      final wetL = _delayBufL[r0L] * (1.0 - fracL) + _delayBufL[r1L] * fracL;
      final wetR = _delayBufR[r0R] * (1.0 - fracR) + _delayBufR[r1R] * fracR;

      // ── Write to delay buffer (with optional feedback) ─────────────────────
      _delayBufL[writeIdx] = inL + wetL * fb;
      _delayBufR[writeIdx] = inR + wetR * fb;

      // ── Mix dry + wet ──────────────────────────────────────────────────────
      _outL[i] = inL * dry + wetL * mix;
      _outR[i] = inR * dry + wetR * mix;

      // Advance LFO phases and write index.
      phaseL += phaseInc;
      if (phaseL >= 2.0 * math.pi) phaseL -= 2.0 * math.pi;
      phaseR += phaseInc;
      if (phaseR >= 2.0 * math.pi) phaseR -= 2.0 * math.pi;

      writeIdx = (writeIdx + 1) % _kMaxDelaySamples;
    }

    _phaseL = phaseL;
    _phaseR = phaseR;
    _writeIdx = writeIdx;
  }
}
