import 'dart:math' as math;
import 'dart:typed_data';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  `wah_filter` node — resonant bandpass filter with BPM-syncable LFO
// ─────────────────────────────────────────────────────────────────────────────

/// `wah_filter` node — auto-wah effect driven by an internal LFO.
///
/// A wah pedal is historically a bandpass (or resonant peak) filter whose
/// centre frequency sweeps up and down, mimicking a human vowel sound.
/// This node implements that sweep using a Chamberlin state-variable filter
/// (SVF), which is numerically stable across the wide frequency excursions
/// needed for a convincing wah sound.
///
/// The centre frequency sweeps between [centerHz] ± [depthHz] according to
/// a low-frequency oscillator. The LFO rate can be free-running (in Hz) or
/// locked to the host BPM via a selectable beat division.
///
/// **Chamberlin SVF topology** (Hal Chamberlin, "Musical Applications of
/// Microprocessors", 1985):
/// ```
///   hp = input − q*band − low
///   band = f*hp + band   (previous band)
///   low  = f*band + low  (previous low)
/// ```
/// where `f = 2*sin(π*fc/sampleRate)` (tuned driving coefficient).
/// We use the `band` output which is the bandpass response.
///
/// | Node param   | Range        | Default | Description                         |
/// |-------------|-------------|---------|--------------------------------------|
/// | `center`    | 200–4000 Hz  | 1200    | Sweep centre frequency               |
/// | `resonance` | 0.5–20.0     | 5.0     | Filter Q / resonance (higher = sharper wah) |
/// | `rate`      | 0.1–10.0 Hz  | 1.0     | LFO rate when BPM sync is off        |
/// | `depth`     | 0.0–1.0      | 0.8     | Sweep depth (fraction of centre)     |
/// | `waveform`  | 0–2 index    | 0       | LFO shape: 0=sine, 1=triangle, 2=saw|
/// | `bpmSync`   | 0/1 toggle   | 0       | BPM sync on/off                      |
/// | `beatDiv`   | 0–5 index    | 2       | Beat division for BPM sync           |
class GFDspWahFilterNode extends GFDspNode {
  // Beat divisions (beats per LFO cycle, in quarter-note beats).
  static const _kBeatDivs = [8.0, 4.0, 2.0, 1.0, 0.5, 0.25];

  int _sampleRate = 44100;

  // ── Parameters ─────────────────────────────────────────────────────────────

  double _centerHz = 1200.0;
  double _resonance = 5.0;
  double _rateHz = 1.0;
  double _depth = 0.8;
  int _waveform = 0;       // 0=sine, 1=triangle, 2=sawtooth
  bool _bpmSync = false;
  int _beatDivIndex = 2;

  // ── LFO state ─────────────────────────────────────────────────────────────

  double _lfoPhase = 0.0; // current LFO phase in [0, 2π]

  // ── SVF state ─────────────────────────────────────────────────────────────

  double _svfLowL = 0.0, _svfBandL = 0.0;
  double _svfLowR = 0.0, _svfBandR = 0.0;

  // ── Output buffers ─────────────────────────────────────────────────────────

  late Float32List _outL;
  late Float32List _outR;

  GFDspWahFilterNode(super.nodeId);

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

  // ── Parameters ─────────────────────────────────────────────────────────────

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'center':
        // Map [0,1] → [200, 4000] Hz on an exponential curve.
        _centerHz = 200.0 * math.pow(20.0, normalizedValue);
      case 'resonance':
        // Map [0,1] → [0.5, 20.0]. High Q = sharp resonant peak.
        _resonance = 0.5 + normalizedValue * 19.5;
      case 'rate':
        // Map [0,1] → [0.1, 10.0] Hz.
        _rateHz = 0.1 + normalizedValue * 9.9;
      case 'depth':
        _depth = normalizedValue.clamp(0.0, 1.0);
      case 'waveform':
        _waveform = (normalizedValue * 2.0).round().clamp(0, 2);
      case 'bpmSync':
        _bpmSync = normalizedValue >= 0.5;
      case 'beatDiv':
        _beatDivIndex = (normalizedValue * (_kBeatDivs.length - 1))
            .round()
            .clamp(0, _kBeatDivs.length - 1);
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

    // Determine LFO rate in radians-per-sample.
    final double rateHz;
    if (_bpmSync && transport.bpm > 0) {
      // BPM sync: rate = BPM / 60 / beats_per_cycle.
      rateHz = (transport.bpm / 60.0) / _kBeatDivs[_beatDivIndex];
    } else {
      rateHz = _rateHz;
    }
    final phaseInc = 2.0 * math.pi * rateHz / _sampleRate;

    // Cache parameters as locals for the inner loop.
    final center = _centerHz;
    final depth = _depth;
    final q = _resonance;
    final wave = _waveform;
    final fs = _sampleRate.toDouble();

    // Restore filter state.
    var lowL = _svfLowL, bandL = _svfBandL;
    var lowR = _svfLowR, bandR = _svfBandR;
    var phase = _lfoPhase;

    for (var i = 0; i < frameCount; i++) {
      // ── LFO output in [-1, 1] ─────────────────────────────────────────────
      final double lfoOut;
      switch (wave) {
        case 1: // triangle: ramp up then down linearly
          final t = phase / (2.0 * math.pi);
          lfoOut = t < 0.5 ? 4.0 * t - 1.0 : 3.0 - 4.0 * t;
        case 2: // sawtooth: linear ramp 0→1, instant reset
          lfoOut = (phase / math.pi) - 1.0;
        default: // sine (case 0 and fallback)
          lfoOut = math.sin(phase);
      }

      // ── Modulated centre frequency ─────────────────────────────────────────
      // Sweep: fc = center * 2^(lfoOut * depth * 2)
      // Using exponential sweep gives a more musical, ear-pleasing feel
      // (equal pitch intervals rather than equal Hz intervals).
      final fc = center * math.pow(2.0, lfoOut * depth * 2.0);
      final fcClamped = fc.clamp(20.0, fs * 0.45);

      // ── Chamberlin SVF driving coefficient ────────────────────────────────
      // f = 2 * sin(π * fc / Fs). For fc << Fs we can approximate with
      // 2 * π * fc / Fs, but sin() is more accurate at high frequencies.
      final f = 2.0 * math.sin(math.pi * fcClamped / fs);

      // ── State-variable filter — left channel ──────────────────────────────
      final inL = src != null ? src.$1[i] : 0.0;
      final hpL = inL - (1.0 / q) * bandL - lowL;
      bandL = f * hpL + bandL;
      lowL = f * bandL + lowL;
      _outL[i] = bandL; // bandpass output = the wah character

      // ── State-variable filter — right channel ─────────────────────────────
      final inR = src != null ? src.$2[i] : 0.0;
      final hpR = inR - (1.0 / q) * bandR - lowR;
      bandR = f * hpR + bandR;
      lowR = f * bandR + lowR;
      _outR[i] = bandR;

      // Advance LFO phase, wrap at 2π.
      phase += phaseInc;
      if (phase >= 2.0 * math.pi) phase -= 2.0 * math.pi;
    }

    // Write back mutable state.
    _svfLowL = lowL;
    _svfBandL = bandL;
    _svfLowR = lowR;
    _svfBandR = bandR;
    _lfoPhase = phase;
  }
}
