import 'dart:ffi';
import 'dart:io';

typedef StartAudioCaptureC = Int32 Function();
typedef StartAudioCaptureDart = int Function();

typedef StopAudioCaptureC = Void Function();
typedef StopAudioCaptureDart = void Function();

typedef GetCurrentPeakLevelC = Float Function();
typedef GetCurrentPeakLevelDart = double Function();

class AudioInputFFI {
  static AudioInputFFI? _instance;
  late DynamicLibrary _lib;

  late StartAudioCaptureDart _startCapture;
  late StopAudioCaptureDart _stopCapture;
  late GetCurrentPeakLevelDart _getPeakLevel;

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
    _getPeakLevel =
        _lib
            .lookup<NativeFunction<GetCurrentPeakLevelC>>(
              'get_current_peak_level',
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

  double getPeakLevel() {
    return _getPeakLevel();
  }
}
