import 'dart:typed_data';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import '../services/audio_engine.dart';
import '../services/audio_input_ffi.dart';

/// The GrooveForge Vocoder as a GFPA instrument plugin.
///
/// Implements [GFInstrumentPlugin] (not [GFEffectPlugin]) because the vocoder
/// requires a MIDI channel to route note-on/off events and responds to keyboard
/// input. The audio "source" is the microphone, processed via [AudioInputFFI].
///
/// In Phase 3, the vocoder is still a singleton DSP engine (one active instance
/// at a time). Multiple vocoder slots in a rack are allowed, but the last one
/// applied to the engine wins for global param settings.
///
/// Phase 5 (audio graph) will restructure this as a true [GFEffectPlugin] with
/// the keyboard's AUDIO OUT cabled into the vocoder's AUDIO IN.
class GFVocoderPlugin implements GFInstrumentPlugin {
  final AudioEngine _engine;

  GFVocoderPlugin(this._engine);

  // ─── Parameter IDs ────────────────────────────────────────────────────────

  static const int paramWaveform = 0;
  static const int paramNoiseMix = 1;
  static const int paramEnvRelease = 2;
  static const int paramBandwidth = 3;
  static const int paramGateThreshold = 4;
  static const int paramInputGain = 5;

  // ─── Internal state ───────────────────────────────────────────────────────

  int _waveform = 0;
  double _noiseMix = 0.05;
  double _envRelease = 0.02;
  double _bandwidth = 0.2;
  double _gateThreshold = 0.01;
  double _inputGain = 1.0;

  // ─── GFPlugin identity ────────────────────────────────────────────────────

  @override
  String get pluginId => 'com.grooveforge.vocoder';

  @override
  String get name => 'Vocoder';

  @override
  String get version => '1.0.0';

  @override
  GFPluginType get type => GFPluginType.instrument;

  @override
  List<GFPluginParameter> get parameters => const [
    GFPluginParameter(
      id: paramWaveform,
      name: 'Waveform',
      min: 0,
      max: 3,
      defaultValue: 0,
    ),
    GFPluginParameter(
      id: paramNoiseMix,
      name: 'Noise Mix',
      min: 0,
      max: 1,
      defaultValue: 0.05,
    ),
    GFPluginParameter(
      id: paramEnvRelease,
      name: 'Env Release',
      min: 0,
      max: 1,
      defaultValue: 0.02,
      unitLabel: 's',
    ),
    GFPluginParameter(
      id: paramBandwidth,
      name: 'Bandwidth',
      min: 0,
      max: 1,
      defaultValue: 0.2,
    ),
    GFPluginParameter(
      id: paramGateThreshold,
      name: 'Gate',
      min: 0,
      max: 1,
      defaultValue: 0.01,
    ),
    GFPluginParameter(
      id: paramInputGain,
      name: 'Input Gain',
      min: 0,
      max: 2,
      defaultValue: 1.0,
    ),
  ];

  // ─── Parameter access ─────────────────────────────────────────────────────

  @override
  double getParameter(int paramId) {
    switch (paramId) {
      case paramWaveform: return _waveform / 3.0;
      case paramNoiseMix: return _noiseMix;
      case paramEnvRelease: return _envRelease;
      case paramBandwidth: return _bandwidth;
      case paramGateThreshold: return _gateThreshold;
      case paramInputGain: return _inputGain / 2.0;
      default: return 0.0;
    }
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    switch (paramId) {
      case paramWaveform:
        _waveform = (normalizedValue * 3).round().clamp(0, 3);
        _engine.vocoderWaveform.value = _waveform;
      case paramNoiseMix:
        _noiseMix = normalizedValue;
        _engine.vocoderNoiseMix.value = _noiseMix;
      case paramEnvRelease:
        _envRelease = normalizedValue;
        _engine.vocoderEnvRelease.value = _envRelease;
      case paramBandwidth:
        _bandwidth = normalizedValue;
        _engine.vocoderBandwidth.value = _bandwidth;
      case paramGateThreshold:
        _gateThreshold = normalizedValue;
        _engine.vocoderGateThreshold.value = _gateThreshold;
      case paramInputGain:
        _inputGain = normalizedValue * 2.0;
        _engine.vocoderInputGain.value = _inputGain;
    }
    _engine.updateVocoderParameters();
  }

  // ─── State serialisation ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> getState() => {
    'waveform': _waveform,
    'noiseMix': _noiseMix,
    'envRelease': _envRelease,
    'bandwidth': _bandwidth,
    'gateThreshold': _gateThreshold,
    'inputGain': _inputGain,
  };

  @override
  void loadState(Map<String, dynamic> state) {
    _waveform = (state['waveform'] as num?)?.toInt() ?? 0;
    _noiseMix = (state['noiseMix'] as num?)?.toDouble() ?? 0.05;
    _envRelease = (state['envRelease'] as num?)?.toDouble() ?? 0.02;
    _bandwidth = (state['bandwidth'] as num?)?.toDouble() ?? 0.2;
    _gateThreshold = (state['gateThreshold'] as num?)?.toDouble() ?? 0.01;
    _inputGain = (state['inputGain'] as num?)?.toDouble() ?? 1.0;
    _pushToEngine();
  }

  void _pushToEngine() {
    _engine.vocoderWaveform.value = _waveform;
    _engine.vocoderNoiseMix.value = _noiseMix;
    _engine.vocoderEnvRelease.value = _envRelease;
    _engine.vocoderBandwidth.value = _bandwidth;
    _engine.vocoderGateThreshold.value = _gateThreshold;
    _engine.vocoderInputGain.value = _inputGain;
    _engine.updateVocoderParameters();
  }

  /// Snapshot current engine params into this plugin's internal state.
  /// Called by [RackState.snapshotVocoderParams] before autosave.
  void snapshotFromEngine() {
    _waveform = _engine.vocoderWaveform.value;
    _noiseMix = _engine.vocoderNoiseMix.value;
    _envRelease = _engine.vocoderEnvRelease.value;
    _bandwidth = _engine.vocoderBandwidth.value;
    _gateThreshold = _engine.vocoderGateThreshold.value;
    _inputGain = _engine.vocoderInputGain.value;
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> initialize(GFPluginContext context) async {}

  @override
  Future<void> dispose() async {}

  // ─── MIDI dispatch ────────────────────────────────────────────────────────

  @override
  void noteOn(int channel, int note, int velocity) =>
      AudioInputFFI().playNote(key: note, velocity: velocity);

  @override
  void noteOff(int channel, int note) =>
      AudioInputFFI().stopNote(key: note);

  @override
  void pitchBend(int channel, double semitones) {}

  @override
  void controlChange(int channel, int cc, int value) {}

  @override
  void processBlock(Float32List outL, Float32List outR, int frameCount) {
    // Vocoder DSP runs inside the native audio_input C engine.
  }
}
