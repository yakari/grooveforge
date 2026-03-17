import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

typedef StartAudioCaptureC = Int32 Function();
typedef StartAudioCaptureDart = int Function();

typedef StopAudioCaptureC = Void Function();
typedef StopAudioCaptureDart = void Function();

typedef GetInputPeakLevelC = Float Function();
typedef GetInputPeakLevelDart = double Function();

typedef GetOutputPeakLevelC = Float Function();
typedef GetOutputPeakLevelDart = double Function();

typedef VocoderNoteOnC = Void Function(Int32 key, Int32 velocity);
typedef VocoderNoteOnDart = void Function(int key, int velocity);

typedef VocoderNoteOffC = Void Function(Int32 key);
typedef VocoderNoteOffDart = void Function(int key);

typedef SetVocoderParametersC =
    Void Function(
      Int32 waveform,
      Float noiseMix,
      Float envRelease,
      Float bandwidth,
    );
typedef SetVocoderParametersDart =
    void Function(
      int waveform,
      double noiseMix,
      double envRelease,
      double bandwidth,
    );

typedef GetCaptureDeviceCountC = Int32 Function();
typedef GetCaptureDeviceCountDart = int Function();

typedef GetCaptureDeviceNameC = Pointer<Utf8> Function(Int32 index);
typedef GetCaptureDeviceNameDart = Pointer<Utf8> Function(int index);

typedef SetCaptureDeviceConfigC =
    Void Function(
      Int32 index,
      Float gain,
      Int32 androidDeviceId,
      Int32 androidOutputDeviceId,
    );
typedef SetCaptureDeviceConfigDart =
    void Function(
      int index,
      double gain,
      int androidDeviceId,
      int androidOutputDeviceId,
    );

typedef NativeFloatFunctionC = Float Function();
typedef DartFloatFunction = double Function();

typedef SetLatencyDebugC = Void Function(Int32 enabled);
typedef SetLatencyDebugDart = void Function(int enabled);

typedef GetLastCallbackPeriodMsC = Float Function();
typedef GetLastCallbackPeriodMsDart = double Function();

typedef GetEngineHealthC = Int32 Function();
typedef GetEngineHealthDart = int Function();

typedef SetGateThresholdC = Void Function(Float threshold);
typedef SetGateThresholdDart = void Function(double threshold);

typedef VocoderPitchBendC = Void Function(Int32 rawValue);
typedef VocoderPitchBendDart = void Function(int rawValue);

typedef VocoderControlChangeC = Void Function(Int32 cc, Int32 value);
typedef VocoderControlChangeDart = void Function(int cc, int value);

// ── Theremin FFI typedefs ─────────────────────────────────────────────────────

/// C signature for theremin_start: initialises the theremin device, returns int.
typedef ThereminStartC = Int32 Function();

/// Dart signature for theremin_start.
typedef ThereminStartDart = int Function();

/// C signature for theremin_stop: stops and frees the theremin device.
typedef ThereminStopC = Void Function();

/// Dart signature for theremin_stop.
typedef ThereminStopDart = void Function();

/// C signature for theremin_set_pitch_hz: sets target frequency in Hz.
typedef ThereminSetPitchHzC = Void Function(Float hz);

/// Dart signature for theremin_set_pitch_hz.
typedef ThereminSetPitchHzDart = void Function(double hz);

/// C signature for theremin_set_volume: sets target volume [0, 1].
typedef ThereminSetVolumeC = Void Function(Float volume);

/// Dart signature for theremin_set_volume.
typedef ThereminSetVolumeDart = void Function(double volume);

/// C signature for theremin_set_vibrato: sets vibrato depth [0, 1].
typedef ThereminSetVibratoC = Void Function(Float depth);

/// Dart signature for theremin_set_vibrato.
typedef ThereminSetVibratoDart = void Function(double depth);

// ── Stylophone FFI typedefs ───────────────────────────────────────────────────

/// C signature for stylophone_start: initialises the stylophone device, returns int.
typedef StyloStartC = Int32 Function();

/// Dart signature for stylophone_start.
typedef StyloStartDart = int Function();

/// C signature for stylophone_stop: stops and frees the stylophone device.
typedef StyloStopC = Void Function();

/// Dart signature for stylophone_stop.
typedef StyloStopDart = void Function();

/// C signature for stylophone_note_on: starts a note at the given Hz.
typedef StyloNoteOnC = Void Function(Float hz);

/// Dart signature for stylophone_note_on.
typedef StyloNoteOnDart = void Function(double hz);

/// C signature for stylophone_note_off: triggers the release envelope.
typedef StyloNoteOffC = Void Function();

/// Dart signature for stylophone_note_off.
typedef StyloNoteOffDart = void Function();

/// C signature for stylophone_set_waveform: selects waveform 0–3.
typedef StyloSetWaveformC = Void Function(Int32 waveform);

/// Dart signature for stylophone_set_waveform.
typedef StyloSetWaveformDart = void Function(int waveform);

/// C signature for stylophone_set_vibrato: sets vibrato depth [0.0, 1.0].
typedef StyloSetVibratoC = Void Function(Float depth);

/// Dart signature for stylophone_set_vibrato.
typedef StyloSetVibratoDart = void Function(double depth);

class AudioInputFFI {
  static AudioInputFFI? _instance;
  late DynamicLibrary _lib;

  late StartAudioCaptureDart _startCapture;
  late StopAudioCaptureDart _stopCapture;
  late GetInputPeakLevelDart _getInputPeakLevel;
  late GetOutputPeakLevelDart _getOutputPeakLevel;
  late VocoderNoteOnDart _vocoderNoteOn;
  late VocoderNoteOffDart _vocoderNoteOff;
  late SetVocoderParametersDart _setVocoderParameters;
  late GetCaptureDeviceCountDart _getCaptureDeviceCount;
  late final GetCaptureDeviceNameDart _getCaptureDeviceName;
  late final SetCaptureDeviceConfigDart _setCaptureDeviceConfig;
  late final DartFloatFunction _getVocoderInputPeak;
  late final DartFloatFunction _getVocoderOutputPeak;
  late final SetLatencyDebugDart _setLatencyDebug;
  late final GetLastCallbackPeriodMsDart _getLastCallbackPeriodMs;
  late final GetEngineHealthDart _getEngineHealth;
  late final SetGateThresholdDart _setGateThreshold;
  late final VocoderPitchBendDart _vocoderPitchBend;
  late final VocoderControlChangeDart _vocoderControlChange;

  // ── Theremin FFI function references ───────────────────────────────────────

  /// Bound reference to `theremin_start` in the native library.
  late final ThereminStartDart _thereminStart;

  /// Bound reference to `theremin_stop` in the native library.
  late final ThereminStopDart _thereminStop;

  /// Bound reference to `theremin_set_pitch_hz` in the native library.
  late final ThereminSetPitchHzDart _thereminSetPitchHz;

  /// Bound reference to `theremin_set_volume` in the native library.
  late final ThereminSetVolumeDart _thereminSetVolume;

  /// Bound reference to `theremin_set_vibrato` in the native library.
  late final ThereminSetVibratoDart _thereminSetVibrato;

  // ── Stylophone FFI function references ─────────────────────────────────────

  /// Bound reference to `stylophone_start` in the native library.
  late final StyloStartDart _styloStart;

  /// Bound reference to `stylophone_stop` in the native library.
  late final StyloStopDart _styloStop;

  /// Bound reference to `stylophone_note_on` in the native library.
  late final StyloNoteOnDart _styloNoteOn;

  /// Bound reference to `stylophone_note_off` in the native library.
  late final StyloNoteOffDart _styloNoteOff;

  /// Bound reference to `stylophone_set_waveform` in the native library.
  late final StyloSetWaveformDart _styloSetWaveform;

  /// Bound reference to `stylophone_set_vibrato` in the native library.
  late final StyloSetVibratoDart _styloSetVibrato;

  factory AudioInputFFI() {
    _instance ??= AudioInputFFI._internal();
    return _instance!;
  }

  AudioInputFFI._internal() {
    if (Platform.isAndroid || Platform.isLinux) {
      _lib = DynamicLibrary.open('libaudio_input.so');
    } else if (Platform.isMacOS) {
      // For development, we can try to find it in the project root or use an absolute path.
      // In a real app, it would be bundled in the app's Frameworks or Resources.
      _lib = DynamicLibrary.open('libaudio_input.dylib');
    } else {
      throw UnsupportedError('This platform is not supported');
    }

    _startCapture =
        _lib
            .lookup<NativeFunction<StartAudioCaptureC>>('start_audio_capture')
            .asFunction();
    _stopCapture =
        _lib
            .lookup<NativeFunction<StopAudioCaptureC>>('stop_audio_capture')
            .asFunction();
    _getInputPeakLevel =
        _lib
            .lookup<NativeFunction<GetInputPeakLevelC>>('getInputPeakLevel')
            .asFunction();
    _getOutputPeakLevel =
        _lib
            .lookup<NativeFunction<GetOutputPeakLevelC>>('getOutputPeakLevel')
            .asFunction();
    _vocoderNoteOn =
        _lib
            .lookup<NativeFunction<VocoderNoteOnC>>('VocoderNoteOn')
            .asFunction();
    _vocoderNoteOff =
        _lib
            .lookup<NativeFunction<VocoderNoteOffC>>('VocoderNoteOff')
            .asFunction();
    _setVocoderParameters =
        _lib
            .lookup<NativeFunction<SetVocoderParametersC>>(
              'setVocoderParameters',
            )
            .asFunction();
    _getCaptureDeviceCount =
        _lib
            .lookup<NativeFunction<GetCaptureDeviceCountC>>(
              'get_capture_device_count',
            )
            .asFunction();
    _getCaptureDeviceName =
        _lib
            .lookup<NativeFunction<GetCaptureDeviceNameC>>(
              'get_capture_device_name',
            )
            .asFunction();
    _setCaptureDeviceConfig =
        _lib
            .lookup<NativeFunction<SetCaptureDeviceConfigC>>(
              'set_capture_device_config',
            )
            .asFunction();
    _getVocoderInputPeak =
        _lib
            .lookup<NativeFunction<NativeFloatFunctionC>>(
              'get_vocoder_input_peak',
            )
            .asFunction();
    _getVocoderOutputPeak =
        _lib
            .lookup<NativeFunction<NativeFloatFunctionC>>(
              'get_vocoder_output_peak',
            )
            .asFunction();
    _setLatencyDebug =
        _lib
            .lookup<NativeFunction<SetLatencyDebugC>>('set_latency_debug')
            .asFunction();
    _getLastCallbackPeriodMs =
        _lib
            .lookup<NativeFunction<GetLastCallbackPeriodMsC>>(
              'get_last_callback_period_ms',
            )
            .asFunction();
    _getEngineHealth =
        _lib
            .lookup<NativeFunction<GetEngineHealthC>>('get_engine_health')
            .asFunction();
    _setGateThreshold =
        _lib
            .lookup<NativeFunction<SetGateThresholdC>>('set_gate_threshold')
            .asFunction();
    _vocoderPitchBend =
        _lib
            .lookup<NativeFunction<VocoderPitchBendC>>('VocoderPitchBend')
            .asFunction();
    _vocoderControlChange =
        _lib
            .lookup<NativeFunction<VocoderControlChangeC>>('VocoderControlChange')
            .asFunction();

    // ── Theremin bindings ─────────────────────────────────────────────────
    _thereminStart =
        _lib
            .lookup<NativeFunction<ThereminStartC>>('theremin_start')
            .asFunction();
    _thereminStop =
        _lib
            .lookup<NativeFunction<ThereminStopC>>('theremin_stop')
            .asFunction();
    _thereminSetPitchHz =
        _lib
            .lookup<NativeFunction<ThereminSetPitchHzC>>('theremin_set_pitch_hz')
            .asFunction();
    _thereminSetVolume =
        _lib
            .lookup<NativeFunction<ThereminSetVolumeC>>('theremin_set_volume')
            .asFunction();
    _thereminSetVibrato =
        _lib
            .lookup<NativeFunction<ThereminSetVibratoC>>('theremin_set_vibrato')
            .asFunction();

    // ── Stylophone bindings ───────────────────────────────────────────────
    _styloStart =
        _lib
            .lookup<NativeFunction<StyloStartC>>('stylophone_start')
            .asFunction();
    _styloStop =
        _lib
            .lookup<NativeFunction<StyloStopC>>('stylophone_stop')
            .asFunction();
    _styloNoteOn =
        _lib
            .lookup<NativeFunction<StyloNoteOnC>>('stylophone_note_on')
            .asFunction();
    _styloNoteOff =
        _lib
            .lookup<NativeFunction<StyloNoteOffC>>('stylophone_note_off')
            .asFunction();
    _styloSetWaveform =
        _lib
            .lookup<NativeFunction<StyloSetWaveformC>>('stylophone_set_waveform')
            .asFunction();
    _styloSetVibrato =
        _lib
            .lookup<NativeFunction<StyloSetVibratoC>>('stylophone_set_vibrato')
            .asFunction();
  }

  bool startCapture() {
    final result = _startCapture();
    return result == 0;
  }

  void stopCapture() {
    _stopCapture();
  }

  double getInputPeakLevel() {
    return _getInputPeakLevel();
  }

  double getOutputPeakLevel() {
    return _getOutputPeakLevel();
  }

  void playNote({required int key, required int velocity}) {
    _vocoderNoteOn(key, velocity);
  }

  void stopNote({required int key}) {
    _vocoderNoteOff(key);
  }

  void setVocoderParameters({
    int waveform = 0,
    double noiseMix = 0.05,
    double envRelease = 0.02,
    double bandwidth = 0.2,
  }) {
    _setVocoderParameters(waveform, noiseMix, envRelease, bandwidth);
  }

  int getCaptureDeviceCount() {
    return _getCaptureDeviceCount();
  }

  String getCaptureDeviceName(int index) {
    return _getCaptureDeviceName(index).toDartString();
  }

  void setCaptureDeviceConfig(
    int index,
    double gain,
    int androidDeviceId,
    int androidOutputDeviceId,
  ) {
    _setCaptureDeviceConfig(
      index,
      gain,
      androidDeviceId,
      androidOutputDeviceId,
    );
  }

  double getVocoderInputPeak() {
    return _getVocoderInputPeak();
  }

  double getVocoderOutputPeak() {
    return _getVocoderOutputPeak();
  }

  /// Enable or disable C-level latency logging to Android logcat.
  /// When enabled, logs a rolling average callback period every ~1 second.
  /// Filter with: `adb logcat -s GrooveForgeAudio`
  void setLatencyDebug({required bool enabled}) {
    _setLatencyDebug(enabled ? 1 : 0);
  }

  /// Returns the most-recently measured duration between two consecutive
  /// audio callbacks in milliseconds. Multiply by ~2 for a rough
  /// full-duplex round-trip estimate. Returns 0.0 before the first callback.
  double getLastCallbackPeriodMs() {
    return _getLastCallbackPeriodMs();
  }

  /// Returns the current health of the audio engine.
  /// 0 = OK, 1 = UNHEALTHY (too many consecutive late callbacks)
  int getEngineHealth() {
    return _getEngineHealth();
  }

  /// Sets the mic noise gate threshold (0.0 = off, 0.1 = aggressive).
  /// Mic samples below this amplitude are silenced before vocoder processing.
  void setGateThreshold(double threshold) {
    _setGateThreshold(threshold);
  }

  /// Applies MIDI pitch bend to the vocoder carrier oscillator.
  ///
  /// [rawValue] is the standard 14-bit MIDI pitch-bend word (0–16383, center 8192).
  /// The C engine uses a ±2 semitone range. Call with 8192 to reset to center.
  void pitchBend(int rawValue) {
    _vocoderPitchBend(rawValue);
  }

  /// Dispatches a MIDI Control Change to the vocoder carrier oscillator.
  ///
  /// Currently handles CC#1 (modulation wheel / vibrato depth):
  /// value 0 disables vibrato, value 127 applies ±1 semitone LFO at 5.5 Hz.
  void controlChange(int cc, int value) {
    _vocoderControlChange(cc, value);
  }

  // ── Theremin public API ───────────────────────────────────────────────────

  /// Starts the theremin native synthesis device.
  ///
  /// Returns 0 on success; non-zero values indicate miniaudio init errors.
  /// Idempotent: safe to call when the device is already running.
  int thereminStart() => _thereminStart();

  /// Stops the theremin native synthesis device and frees resources.
  void thereminStop() => _thereminStop();

  /// Sets the theremin target pitch in Hz (clamped to [20, 20000] by C).
  ///
  /// The C engine glides smoothly to the new frequency over ~42 ms.
  void thereminSetPitchHz(double hz) => _thereminSetPitchHz(hz);

  /// Sets the theremin output volume (normalised [0, 1]; C scales to 0.85).
  ///
  /// The C engine smooths amplitude changes over ~7 ms to prevent clicks.
  void thereminSetVolume(double volume) => _thereminSetVolume(volume);

  /// Sets the 6.5 Hz vibrato depth (normalised [0, 1]).
  ///
  /// 0 = no vibrato; 1 = ±0.5 semitone LFO modulation.
  void thereminSetVibrato(double depth) => _thereminSetVibrato(depth);

  // ── Stylophone public API ─────────────────────────────────────────────────

  /// Starts the stylophone native synthesis device.
  ///
  /// Returns 0 on success; non-zero values indicate miniaudio init errors.
  int styloStart() => _styloStart();

  /// Stops the stylophone native synthesis device and frees resources.
  void styloStop() => _styloStop();

  /// Starts a note at [hz] (clamped to [20, 20000]).
  ///
  /// Phase is preserved so sliding between keys is seamless (no click).
  void styloNoteOn(double hz) => _styloNoteOn(hz);

  /// Releases the current note, starting the exponential release envelope.
  void styloNoteOff() => _styloNoteOff();

  /// Selects the oscillator waveform: 0=Square, 1=Sawtooth, 2=Sine, 3=Triangle.
  void styloSetWaveform(int waveform) => _styloSetWaveform(waveform);

  /// Sets the stylophone vibrato depth: 0.0 = off, 1.0 = full wobble.
  void styloSetVibrato(double depth) => _styloSetVibrato(depth);
}
