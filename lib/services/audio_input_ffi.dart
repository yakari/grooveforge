import 'dart:ffi';
import 'dart:io';

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

  factory AudioInputFFI() {
    _instance ??= AudioInputFFI._internal();
    return _instance!;
  }

  AudioInputFFI._internal() {
    if (Platform.isAndroid || Platform.isLinux) {
      _lib = DynamicLibrary.open('libaudio_input.so');
    } else {
      throw UnsupportedError('This prototype supports Linux and Android only');
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
}
