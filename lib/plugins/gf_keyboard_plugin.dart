import 'dart:typed_data';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import '../services/audio_engine.dart';

/// The built-in GrooveForge Keyboard as a GFPA instrument plugin.
///
/// Delegates all audio processing to FluidSynth via [AudioEngine]. The
/// [processBlock] method is a no-op because FluidSynth writes directly to
/// the native ALSA / CoreAudio output buffer without going through Dart.
///
/// This implementation is internal — it has full access to [AudioEngine].
/// Third-party GFPA plugins must not depend on app internals.
class GFKeyboardPlugin implements GFInstrumentPlugin {
  final AudioEngine _engine;

  GFKeyboardPlugin(this._engine);

  @override
  String get pluginId => 'com.grooveforge.keyboard';

  @override
  String get name => 'GrooveForge Keyboard';

  @override
  String get version => '1.0.0';

  @override
  GFPluginType get type => GFPluginType.instrument;

  /// The keyboard has a bespoke UI — parameters are managed directly through
  /// [AudioEngine] and [RackState], not via the generic parameter grid.
  @override
  List<GFPluginParameter> get parameters => const [];

  @override
  double getParameter(int paramId) => 0.0;

  @override
  void setParameter(int paramId, double normalizedValue) {}

  @override
  Map<String, dynamic> getState() => {};

  @override
  void loadState(Map<String, dynamic> state) {}

  @override
  Future<void> initialize(GFPluginContext context) async {}

  @override
  Future<void> dispose() async {}

  @override
  void noteOn(int channel, int note, int velocity) =>
      _engine.playNote(channel: channel, key: note, velocity: velocity);

  @override
  void noteOff(int channel, int note) =>
      _engine.stopNote(channel: channel, key: note);

  @override
  void pitchBend(int channel, double semitones) {
    final raw = ((semitones / 2.0).clamp(-1.0, 1.0) * 8191).round() + 8192;
    _engine.setPitchBend(channel: channel, value: raw);
  }

  @override
  void controlChange(int channel, int cc, int value) =>
      _engine.setControlChange(channel: channel, controller: cc, value: value);

  @override
  void processBlock(Float32List outL, Float32List outR, int frameCount) {
    // FluidSynth writes to the native audio output directly.
  }
}
