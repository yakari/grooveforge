import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart'
    show GFTransportContext;
import 'vst_host_service.dart';

// Sample rate for positionInSamples advancement — must match the audio engine.
const int _kSampleRate = 48000;

class TransportEngine extends ChangeNotifier {
  double _bpm = 120.0;
  int _timeSigNumerator = 4;
  int _timeSigDenominator = 4;
  bool _isPlaying = false;
  final bool _isRecording = false;
  double _positionInBeats = 0.0;
  int _positionInSamples = 0;
  double _swing = 0.0;
  bool _metronomeEnabled = false;

  // Fires on each beat boundary while playing. [isDownbeat] == true on beat 1 of each bar.
  void Function(bool isDownbeat)? onBeat;
  /// Additional beat callback for the audio looper bar-sync.
  void Function(bool isDownbeat)? onBeatAudioLooper;

  // Incremented on each beat; listen with ValueListenableBuilder for visual pulse.
  final ValueNotifier<int> beatCount = ValueNotifier(0);

  Timer? _ticker;
  DateTime? _lastTickTime;

  void _syncToHost() {
    VstHostService.instance.setTransport(
      bpm: _bpm,
      timeSigNum: _timeSigNumerator,
      timeSigDen: _timeSigDenominator,
      isPlaying: _isPlaying,
      positionInBeats: _positionInBeats,
      positionInSamples: _positionInSamples,
    );
  }

  void _startTicker() {
    _positionInBeats = 0.0;
    _positionInSamples = 0;
    _lastTickTime = DateTime.now();
    // Always start on beat 1 (downbeat): fire immediately so the LED pulses
    // and the metronome click sounds the instant play is pressed.
    beatCount.value = 1;
    onBeat?.call(true);
    onBeatAudioLooper?.call(true);
    // Advance past beat-1 so the next tick crossing (b=2) is beat 2, not a
    // second downbeat.
    _positionInBeats = 1.0;
    _ticker = Timer.periodic(const Duration(milliseconds: 10), _tick);
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTickTime = null;
  }

  void _tick(Timer _) {
    if (!_isPlaying) return;
    final now = DateTime.now();
    if (_lastTickTime == null) {
      _lastTickTime = now;
      return;
    }
    final elapsedSeconds = now.difference(_lastTickTime!).inMicroseconds / 1e6;
    _lastTickTime = now;
    if (elapsedSeconds <= 0) return;

    final prevBeat = _positionInBeats;
    _positionInBeats += elapsedSeconds * _bpm / 60.0;
    _positionInSamples += (elapsedSeconds * _kSampleRate).round();

    final prevFloor = prevBeat.floor();
    final currFloor = _positionInBeats.floor();
    if (currFloor > prevFloor) {
      for (int b = prevFloor + 1; b <= currFloor; b++) {
        // b=1 corresponds to beat 2 (beat 1 was fired immediately at start),
        // so downbeat formula is (b-1) % numerator == 0.
        final isDownbeat = (b - 1) % _timeSigNumerator == 0;
        beatCount.value++;
        debugPrint('[TRANSPORT] beat $b (pos=${_positionInBeats.toStringAsFixed(1)}) '
            '${isDownbeat ? "* BAR" : ""}');
        onBeat?.call(isDownbeat);
        onBeatAudioLooper?.call(isDownbeat);
      }
    }

    _syncToHost();
  }

  double get bpm => _bpm;
  set bpm(double value) {
    if (value < 20.0) value = 20.0;
    if (value > 300.0) value = 300.0;
    if (_bpm != value) {
      _bpm = value;
      _syncToHost();
      notifyListeners();
    }
  }

  int get timeSigNumerator => _timeSigNumerator;
  set timeSigNumerator(int value) {
    if (_timeSigNumerator != value) {
      _timeSigNumerator = value;
      _syncToHost();
      notifyListeners();
    }
  }

  int get timeSigDenominator => _timeSigDenominator;
  set timeSigDenominator(int value) {
    if (_timeSigDenominator != value) {
      _timeSigDenominator = value;
      _syncToHost();
      notifyListeners();
    }
  }

  bool get isPlaying => _isPlaying;
  bool get isRecording => _isRecording;
  double get positionInBeats => _positionInBeats;
  int get positionInSamples => _positionInSamples;
  double get swing => _swing;
  set swing(double value) {
    if (_swing != value) {
      _swing = value;
      notifyListeners();
    }
  }

  bool get metronomeEnabled => _metronomeEnabled;
  set metronomeEnabled(bool value) {
    if (_metronomeEnabled != value) {
      _metronomeEnabled = value;
      notifyListeners();
    }
  }

  // Playback Control
  void play() {
    if (!_isPlaying) {
      _isPlaying = true;
      beatCount.value = 0;
      _startTicker();
      _syncToHost();
      notifyListeners();
    }
  }

  void stop() {
    if (_isPlaying) {
      _isPlaying = false;
      _stopTicker();
      _syncToHost();
      notifyListeners();
    }
  }

  void reset() {
    _stopTicker();
    _positionInBeats = 0.0;
    _positionInSamples = 0;
    beatCount.value = 0;
    if (_isPlaying) _startTicker();
    _syncToHost();
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTicker();
    beatCount.dispose();
    super.dispose();
  }

  /// Snapshot the current transport state as a [GFTransportContext].
  ///
  /// Used by MIDI FX processing to pass BPM and playback state to nodes
  /// that perform beat-quantised transforms (e.g. arpeggiator).
  GFTransportContext toGFTransportContext() => GFTransportContext(
        bpm: _bpm,
        timeSigNumerator: _timeSigNumerator,
        timeSigDenominator: _timeSigDenominator,
        isPlaying: _isPlaying,
        isRecording: _isRecording,
        positionInBeats: _positionInBeats,
      );

  // Tap Tempo logic
  final List<DateTime> _tapTimestamps = [];

  void tapTempo() {
    final now = DateTime.now();

    if (_tapTimestamps.isNotEmpty && now.difference(_tapTimestamps.last).inSeconds > 2) {
      _tapTimestamps.clear();
    }

    _tapTimestamps.add(now);

    if (_tapTimestamps.length > 4) {
      _tapTimestamps.removeAt(0);
    }

    if (_tapTimestamps.length >= 2) {
      int totalMs = 0;
      for (int i = 1; i < _tapTimestamps.length; i++) {
        totalMs += _tapTimestamps[i].difference(_tapTimestamps[i - 1]).inMilliseconds;
      }

      final double avgMs = totalMs / (_tapTimestamps.length - 1);

      if (avgMs > 0) {
        bpm = (60000.0 / avgMs).roundToDouble();
      }
    }
  }
}
