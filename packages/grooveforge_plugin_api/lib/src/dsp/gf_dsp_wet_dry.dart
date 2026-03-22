import 'dart:typed_data';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

/// `wet_dry` node — blends a processed (wet) signal with the original (dry).
///
/// The node has two input ports:
/// - `"wet"`: the processed/effected signal.
/// - `"dry"`: the unprocessed/bypass signal.
///
/// | Node param | Range       | Default | Description                    |
/// |-----------|-------------|---------|--------------------------------|
/// | `mix`     | 0.0 – 1.0   | 0.5     | 0 = fully dry, 1 = fully wet   |
///
/// Formula per sample: `out = dry * (1 - mix) + wet * mix`
///
/// This is the standard insert-effect mix crossfade used in nearly every
/// guitar pedal and studio processor.
class GFDspWetDryNode extends GFDspNode {
  /// Wet-mix coefficient in [0, 1]. Reads atomically from audio thread.
  double _mix = 0.5;

  late Float32List _outL;
  late Float32List _outR;

  GFDspWetDryNode(super.nodeId);

  @override
  List<String> get inputPortNames => const ['wet', 'dry'];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
  }

  @override
  void setParam(String paramName, double normalizedValue) {
    if (paramName == 'mix') _mix = normalizedValue.clamp(0.0, 1.0);
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
    final wetSrc = inputs['wet'];
    final drySrc = inputs['dry'];

    final m = _mix;       // local copy for the hot loop
    final dry = 1.0 - m;

    for (var i = 0; i < frameCount; i++) {
      final wL = wetSrc != null ? wetSrc.$1[i] : 0.0;
      final wR = wetSrc != null ? wetSrc.$2[i] : 0.0;
      final dL = drySrc != null ? drySrc.$1[i] : 0.0;
      final dR = drySrc != null ? drySrc.$2[i] : 0.0;
      _outL[i] = dL * dry + wL * m;
      _outR[i] = dR * dry + wR * m;
    }
  }
}
