import 'dart:typed_data';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

/// `gain` node — applies a linear amplitude multiplier to a stereo signal.
///
/// | Node param | Range       | Default | Description              |
/// |-----------|-------------|---------|--------------------------|
/// | `gain`    | 0.0 – 2.0   | 1.0     | Linear gain multiplier   |
///
/// Normalised value 0.5 → raw gain 1.0 (unity). Values above 0.5 amplify;
/// below 0.5 attenuate. This maps the full 0–1 knob range to 0–2× gain.
class GFDspGainNode extends GFDspNode {
  /// Linear gain multiplier, read atomically by the audio thread.
  double _gain = 1.0;

  late Float32List _outL;
  late Float32List _outR;

  GFDspGainNode(super.nodeId);

  @override
  List<String> get inputPortNames => const ['in'];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    if (paramName == 'gain') {
      // Map [0,1] → [0, 2] so 0.5 = unity gain.
      _gain = normalizedValue * 2.0;
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
    if (src == null) {
      // No input — silence the output.
      for (var i = 0; i < frameCount; i++) {
        _outL[i] = 0.0;
        _outR[i] = 0.0;
      }
      return;
    }

    final (inL, inR) = src;
    final g = _gain; // local copy — avoids repeated field access in hot loop

    for (var i = 0; i < frameCount; i++) {
      _outL[i] = inL[i] * g;
      _outR[i] = inR[i] * g;
    }
  }
}
