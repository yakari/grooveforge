import 'package:flutter_midi_pro/flutter_midi_pro_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class FlutterMidiProPlatform extends PlatformInterface {
  FlutterMidiProPlatform() : super(token: _token);
  static final Object _token = Object();
  static FlutterMidiProPlatform _instance = MethodChannelFlutterMidiPro();
  static FlutterMidiProPlatform get instance => _instance;

  static set instance(FlutterMidiProPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<int> loadSoundfont(String path, int bank, int program) {
    throw UnimplementedError('loadSoundfont() has not been implemented.');
  }

  Future<void> selectInstrument(int sfId, int channel, int bank, int program) {
    throw UnimplementedError('selectInstrument() has not been implemented.');
  }

  Future<void> playNote(int channel, int key, int velocity, int sfId) {
    throw UnimplementedError('playNote() has not been implemented.');
  }

  Future<void> stopNote(int channel, int key, int sfId) {
    throw UnimplementedError('stopNote() has not been implemented.');
  }

  Future<void> stopAllNotes(int sfId) {
    throw UnimplementedError('stopAllNotes() has not been implemented.');
  }

  /// Sends a MIDI Control Change (CC) message to the specified channel on a soundfont.
  /// [controller] is the CC number (0-127), [value] is the CC value (0-127).
  Future<void> controlChange(int sfId, int channel, int controller, int value) {
    throw UnimplementedError('controlChange() has not been implemented.');
  }

  /// Sends a MIDI Pitch Bend message to the specified channel on a soundfont.
  /// [value] is the pitch bend value (0-16383, center is 8192).
  Future<void> pitchBend(int sfId, int channel, int value) {
    throw UnimplementedError('pitchBend() has not been implemented.');
  }

  /// Sets the master output gain on all currently-loaded FluidSynth instances.
  ///
  /// [gain] must be in the range 0.0–10.0. Takes effect immediately without
  /// requiring a soundfont reload.
  Future<void> setGain(double gain) {
    throw UnimplementedError('setGain() has not been implemented.');
  }

  Future<void> unloadSoundfont(int sfId) {
    throw UnimplementedError('unloadSoundfont() has not been implemented.');
  }

  Future<void> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}
