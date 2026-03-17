/// Web platform implementation of [FlutterMidiProPlatform].
///
/// Delegates all SF2 synthesis to the SpessaSynth-backed JS bridge defined
/// in web/js/grooveforge_audio.js. The bridge is exposed as
/// [window.grooveForgeAudio] and is loaded as a <script type="module"> in
/// the app's web/index.html before the Flutter engine boots.
///
/// Registration is automatic: [flutter_web_plugins] calls [registerWith]
/// at startup when running on a web target.
import 'dart:js_interop';

import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// JS interop extension type for [window.grooveForgeAudio].
///
/// Method signatures mirror the JavaScript API defined in
/// web/js/grooveforge_audio.js.
@JS()
extension type _GFAudio._(JSObject _) implements JSObject {
  /// Loads an SF2 file from [url] and returns a numeric sfId.
  external JSPromise<JSNumber> loadSoundfont(
      JSString url, JSNumber bank, JSNumber program);

  external void playNote(
      JSNumber channel, JSNumber key, JSNumber velocity, JSNumber sfId);

  external void stopNote(JSNumber channel, JSNumber key, JSNumber sfId);

  external void stopAllNotes(JSNumber sfId);

  external void selectInstrument(
      JSNumber sfId, JSNumber channel, JSNumber bank, JSNumber program);

  external void controlChange(
      JSNumber sfId, JSNumber channel, JSNumber controller, JSNumber value);

  external void pitchBend(JSNumber sfId, JSNumber channel, JSNumber value);

  external void setGain(JSNumber gain);

  external void unloadSoundfont(JSNumber sfId);
}

/// Accesses the global JS synthesis bridge set by grooveforge_audio.js.
@JS('window.grooveForgeAudio')
external _GFAudio? get _gfAudio;

/// Flutter web platform implementation of [FlutterMidiProPlatform].
///
/// All methods delegate to the [_gfAudio] JS bridge. If the bridge is not
/// yet initialised (e.g. slow CDN), [loadSoundfont] polls for up to
/// 10 seconds before giving up.
class FlutterMidiProWeb extends FlutterMidiProPlatform {
  /// Called automatically by [flutter_web_plugins] at app startup.
  static void registerWith(Registrar registrar) {
    FlutterMidiProPlatform.instance = FlutterMidiProWeb();
  }

  /// Returns the JS audio bridge once initialised, or null on timeout.
  Future<_GFAudio?> _awaitAudio() async {
    // The ES-module bridge is usually ready before the Dart isolate starts,
    // but we poll defensively to handle slow network or cold-cache scenarios.
    _GFAudio? audio = _gfAudio;
    for (int i = 0; i < 100 && audio == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      audio = _gfAudio;
    }
    return audio;
  }

  @override
  Future<int> loadSoundfont(String path, int bank, int program) async {
    final audio = await _awaitAudio();
    if (audio == null) return -1;
    final sfId =
        await audio.loadSoundfont(path.toJS, bank.toJS, program.toJS).toDart;
    return sfId.toDartDouble.toInt();
  }

  @override
  Future<void> selectInstrument(
      int sfId, int channel, int bank, int program) async {
    (await _awaitAudio())
        ?.selectInstrument(sfId.toJS, channel.toJS, bank.toJS, program.toJS);
  }

  @override
  Future<void> playNote(int channel, int key, int velocity, int sfId) async {
    _gfAudio?.playNote(channel.toJS, key.toJS, velocity.toJS, sfId.toJS);
  }

  @override
  Future<void> stopNote(int channel, int key, int sfId) async {
    _gfAudio?.stopNote(channel.toJS, key.toJS, sfId.toJS);
  }

  @override
  Future<void> stopAllNotes(int sfId) async {
    _gfAudio?.stopAllNotes(sfId.toJS);
  }

  @override
  Future<void> controlChange(
      int sfId, int channel, int controller, int value) async {
    _gfAudio?.controlChange(sfId.toJS, channel.toJS, controller.toJS, value.toJS);
  }

  @override
  Future<void> pitchBend(int sfId, int channel, int value) async {
    _gfAudio?.pitchBend(sfId.toJS, channel.toJS, value.toJS);
  }

  @override
  Future<void> setGain(double gain) async {
    _gfAudio?.setGain(gain.toJS);
  }

  @override
  Future<void> unloadSoundfont(int sfId) async {
    _gfAudio?.unloadSoundfont(sfId.toJS);
  }

  @override
  Future<void> dispose() async {
    // Synth instances are managed by the JS bridge; nothing to release here.
  }
}
