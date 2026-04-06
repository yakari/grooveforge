// Web-only stub for AudioInputFFI — selected when dart.library.js_interop is
// available (i.e., Flutter web and Wasm targets).
//
// All Vocoder methods are no-ops (the native C vocoder is unavailable in a
// browser sandbox). Stylophone and Theremin are delegated to the Web Audio
// oscillator bridge exposed as window.grooveForgeOscillator by
// web/js/grooveforge_audio.js.

import 'dart:js_interop';

/// JS interop extension type for [window.grooveForgeOscillator].
///
/// Matches the API surface defined in web/js/grooveforge_audio.js.
@JS()
extension type _GFOscillator._(JSObject _) implements JSObject {
  external void styloStart();
  external void styloStop();
  external void styloNoteOn(JSNumber hz);
  external void styloNoteOff();
  external void styloSetWaveform(JSNumber waveform);
  external void styloSetVibrato(JSNumber depth);

  external void thereminStart();
  external void thereminStop();
  external void thereminSetPitchHz(JSNumber hz);
  external void thereminSetVolume(JSNumber volume);
  external void thereminSetVibrato(JSNumber depth);
}

/// Accesses the global JS oscillator bridge set by grooveforge_audio.js.
@JS('window.grooveForgeOscillator')
external _GFOscillator? get _gfOscillator;

/// Web stub that mirrors the [AudioInputFFI] public API.
///
/// Vocoder operations are silently ignored — the browser has no native microphone
/// capture pipeline compatible with the native vocoder DSP. Stylophone and
/// Theremin operations are forwarded to the Web Audio oscillator bridge so that
/// those instruments produce real sound in the browser.
class AudioInputFFI {
  static AudioInputFFI? _instance;

  factory AudioInputFFI() {
    _instance ??= AudioInputFFI._();
    return _instance!;
  }

  AudioInputFFI._();

  /// Returns the JS oscillator bridge, or null if not yet initialised.
  _GFOscillator? get _osc => _gfOscillator;

  // ── Capture / Vocoder (all no-ops on web) ──────────────────────────────

  /// Not supported on web — returns false.
  bool startCapture() => false;

  /// Not supported on web — no-op.
  void stopCapture() {}

  /// Not supported on web — returns 0.0.
  double getInputPeakLevel() => 0.0;

  /// Not supported on web — returns 0.0.
  double getOutputPeakLevel() => 0.0;

  /// Not supported on web — no-op.
  void playNote({required int key, required int velocity}) {}

  /// Not supported on web — no-op.
  void stopNote({required int key}) {}

  /// Not supported on web — no-op.
  void setVocoderParameters({
    int waveform = 0,
    double noiseMix = 0.05,
    double envRelease = 0.02,
    double bandwidth = 0.2,
  }) {}

  /// Not supported on web — returns 0.
  int getCaptureDeviceCount() => 0;

  /// Not supported on web — returns empty string.
  String getCaptureDeviceName(int index) => '';

  /// Not supported on web — no-op.
  void setCaptureDeviceConfig(
    int index,
    double gain,
    int androidDeviceId,
    int androidOutputDeviceId,
  ) {}

  /// Not supported on web — returns 0.0.
  double getVocoderInputPeak() => 0.0;

  /// Not supported on web — returns 0.0.
  double getVocoderOutputPeak() => 0.0;

  /// Not supported on web — no-op.
  void setLatencyDebug({required bool enabled}) {}

  /// Not supported on web — returns 0.0.
  double getLastCallbackPeriodMs() => 0.0;

  /// Not supported on web — reports healthy (0).
  int getEngineHealth() => 0;

  /// Not supported on web — no-op.
  void setGateThreshold(double threshold) {}

  /// Not supported on web — no-op.
  void pitchBend(int rawValue) {}

  /// Not supported on web — no-op.
  void controlChange(int cc, int value) {}

  // ── Theremin — forwarded to Web Audio oscillator ───────────────────────

  /// Starts the theremin Web Audio oscillator.
  ///
  /// Returns 0 on success (the JS bridge may silently fail if the
  /// AudioContext cannot be resumed before the first user gesture).
  int thereminStart() {
    _osc?.thereminStart();
    return 0;
  }

  /// Stops and frees the theremin Web Audio oscillator.
  void thereminStop() => _osc?.thereminStop();

  /// Sets the theremin pitch in Hz via [AudioParam.setTargetAtTime] (~42 ms portamento).
  void thereminSetPitchHz(double hz) => _osc?.thereminSetPitchHz(hz.toJS);

  /// Sets the theremin amplitude [0, 1]; scaled to 0.85 peak in the JS bridge.
  void thereminSetVolume(double volume) => _osc?.thereminSetVolume(volume.toJS);

  /// Sets the 6.5 Hz vibrato LFO depth [0, 1].
  void thereminSetVibrato(double depth) => _osc?.thereminSetVibrato(depth.toJS);

  /// No-op on web — capture mode and bus routing are Android-only.
  void thereminSetCaptureMode({required bool enabled}) {}

  /// Returns 0 on web — bus render function addresses are Android-only.
  int thereminBusRenderFnAddr() => 0;

  // ── Stylophone — forwarded to Web Audio oscillator ─────────────────────

  /// Starts the stylophone Web Audio oscillator.
  int styloStart() {
    _osc?.styloStart();
    return 0;
  }

  /// Stops and frees the stylophone Web Audio oscillator.
  void styloStop() => _osc?.styloStop();

  /// Starts a note at [hz]; a quick gain ramp prevents click transients.
  void styloNoteOn(double hz) => _osc?.styloNoteOn(hz.toJS);

  /// Releases the current note with a ~150 ms exponential decay.
  void styloNoteOff() => _osc?.styloNoteOff();

  /// Selects the oscillator waveform: 0 = square, 1 = sawtooth, 2 = sine, 3 = triangle.
  void styloSetWaveform(int waveform) => _osc?.styloSetWaveform(waveform.toJS);

  /// Sets vibrato depth [0.0, 1.0] (LFO modulates oscillator frequency by ±15 Hz at depth 1).
  void styloSetVibrato(double depth) => _osc?.styloSetVibrato(depth.toJS);

  // ── GF Keyboard — all no-ops on web (uses soundfont-player JS bridge) ──

  /// Not supported on web — keyboard audio is handled by the JS soundfont bridge.
  int keyboardInit(double sampleRate) => 0;

  /// Not supported on web — no-op, returns 0.
  int keyboardInitSlot(int slotIdx, double sampleRate) => 0;

  /// Not supported on web — no-op.
  void keyboardDestroy() {}

  /// Not supported on web — returns -1.
  int keyboardLoadSf(String path) => -1;

  /// Not supported on web — no-op.
  void keyboardUnloadSf(int sfId) {}

  /// Not supported on web — no-op.
  void keyboardProgramSelect(int ch, int sfId, int bank, int program) {}

  /// Not supported on web — no-op.
  void keyboardNoteOn(int ch, int key, int velocity) {}

  /// Not supported on web — no-op.
  void keyboardNoteOff(int ch, int key) {}

  /// Not supported on web — no-op.
  void keyboardPitchBend(int ch, int value) {}

  /// Not supported on web — no-op.
  void keyboardControlChange(int ch, int cc, int value) {}

  /// Not supported on web — no-op.
  void keyboardSetGain(double gain) {}
}
