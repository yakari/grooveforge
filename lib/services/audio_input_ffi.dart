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
}
