import 'dart:typed_data';
import 'gf_plugin.dart';
import 'gf_plugin_type.dart';

/// A GFPA plugin that generates audio from MIDI input.
///
/// Examples: synthesizer, sampler, vocoder, soundfont player.
abstract class GFInstrumentPlugin extends GFPlugin {
  @override
  GFPluginType get type => GFPluginType.instrument;

  void noteOn(int channel, int note, int velocity);
  void noteOff(int channel, int note);
  void pitchBend(int channel, double semitones);
  void controlChange(int channel, int cc, int value);

  /// Called once per audio block on the audio thread.
  ///
  /// Fill [outL] and [outR] with [frameCount] stereo PCM frames (float 32).
  /// For plugins that delegate synthesis to a native backend (e.g. FluidSynth),
  /// this method may be a no-op — the native backend writes directly to the
  /// output buffer. The method signature is provided for plugins that implement
  /// DSP in pure Dart.
  void processBlock(Float32List outL, Float32List outR, int frameCount);
}
