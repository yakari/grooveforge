import 'dart:typed_data';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

/// `delay` node — stereo ping-pong delay with BPM-syncable time.
///
/// "Ping-pong" means the echo alternates left→right→left, creating the
/// illusion of sound bouncing between speakers. It is the standard delay
/// topology in guitar pedals and studio FX processors.
///
/// When [bpmSync] is enabled the delay time is set by [beatDiv] (a beat
/// division index) rather than the raw [timeMs] parameter. The effective
/// delay time is recomputed each block from the host transport BPM.
///
/// | Node param   | Range       | Default | Description                          |
/// |-------------|-------------|---------|--------------------------------------|
/// | `timeMs`    | 1–2000 ms   | 500     | Delay time in milliseconds           |
/// | `feedback`  | 0.0–0.99    | 0.4     | Echo decay (0 = one shot, 0.99 = long)|
/// | `bpmSync`   | 0/1 toggle  | 0       | BPM-sync on/off                      |
/// | `beatDiv`   | 0–5 index   | 2       | Beat division (see [_kBeatDivs])     |
class GFDspDelayNode extends GFDspNode {
  // Beat division values as fractions of a quarter-note beat.
  // Index 0=2bars, 1=1bar, 2=1/2, 3=1/4, 4=1/8, 5=1/16.
  static const _kBeatDivs = [8.0, 4.0, 2.0, 1.0, 0.5, 0.25];

  int _sampleRate = 44100;

  // ── Parameters ─────────────────────────────────────────────────────────────

  double _timeMs = 500.0;       // delay time when BPM sync is off
  double _feedback = 0.4;       // echo feedback gain
  bool _bpmSync = false;        // BPM sync toggle
  int _beatDivIndex = 2;        // index into _kBeatDivs (default: 1/2 beat)

  // ── Delay buffers (circular, pre-allocated for max 2-second delay) ─────────

  late Float32List _bufL;
  late Float32List _bufR;
  int _writeIdx = 0;
  int _bufSize = 0;

  // ── Output buffers ─────────────────────────────────────────────────────────

  late Float32List _outL;
  late Float32List _outR;

  GFDspDelayNode(super.nodeId);

  @override
  List<String> get inputPortNames => const ['in'];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    _sampleRate = sampleRate;
    // Allocate for up to 2 seconds of delay at the current sample rate.
    _bufSize = sampleRate * 2;
    _bufL = Float32List(_bufSize);
    _bufR = Float32List(_bufSize);
    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    switch (paramName) {
      case 'timeMs':
        // Map [0,1] → [1, 2000] ms.
        _timeMs = 1.0 + normalizedValue * 1999.0;
      case 'feedback':
        // Map [0,1] → [0, 0.99] — keep below 1.0 to avoid infinite feedback.
        _feedback = normalizedValue * 0.99;
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
    final fb = _feedback;

    // Compute delay time in samples.
    int delaySamples;
    if (_bpmSync && transport.bpm > 0) {
      // BPM sync: delay = beat_division / BPM_in_Hz.
      // beatsPerSecond = bpm / 60. delaySeconds = beatsPerDiv / beatsPerSecond.
      final beatsPerDiv = _kBeatDivs[_beatDivIndex];
      final beatsPerSec = transport.bpm / 60.0;
      final delaySeconds = beatsPerDiv / beatsPerSec;
      delaySamples = (delaySeconds * _sampleRate).round();
    } else {
      delaySamples = (_timeMs / 1000.0 * _sampleRate).round();
    }
    delaySamples = delaySamples.clamp(1, _bufSize - 1);

    for (var i = 0; i < frameCount; i++) {
      final inL = src != null ? src.$1[i] : 0.0;
      final inR = src != null ? src.$2[i] : 0.0;

      // Ping-pong: left channel reads from left delay, feeds back to right.
      // Right channel reads from right delay, feeds back to left.
      final readIdx = (_writeIdx - delaySamples + _bufSize) % _bufSize;

      final delL = _bufL[readIdx];
      final delR = _bufR[readIdx];

      _bufL[_writeIdx] = inL + delR * fb; // receive cross-channel for ping-pong
      _bufR[_writeIdx] = inR + delL * fb;

      _outL[i] = inL + delL;
      _outR[i] = inR + delR;

      _writeIdx = (_writeIdx + 1) % _bufSize;
    }
  }
}
