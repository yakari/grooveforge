import 'package:flutter/foundation.dart';
import 'vst_host_service.dart';

class TransportEngine extends ChangeNotifier {
  double _bpm = 120.0;
  int _timeSigNumerator = 4;
  int _timeSigDenominator = 4;
  bool _isPlaying = false;
  final bool _isRecording = false;
  double _positionInBeats = 0.0;
  int _positionInSamples = 0;
  double _swing = 0.0;

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

  // Playback Control
  void play() {
    if (!_isPlaying) {
      _isPlaying = true;
      _syncToHost();
      notifyListeners();
    }
  }

  void stop() {
    if (_isPlaying) {
      _isPlaying = false;
      _syncToHost();
      notifyListeners();
    }
  }

  void reset() {
    _positionInBeats = 0.0;
    _positionInSamples = 0;
    _syncToHost();
    notifyListeners();
  }

  // Tap Tempo logic
  final List<DateTime> _tapTimestamps = [];
  
  void tapTempo() {
    final now = DateTime.now();
    
    // Reset if it's been more than 2 seconds since last tap
    if (_tapTimestamps.isNotEmpty && now.difference(_tapTimestamps.last).inSeconds > 2) {
      _tapTimestamps.clear();
    }
    
    _tapTimestamps.add(now);
    
    if (_tapTimestamps.length > 4) {
      _tapTimestamps.removeAt(0); // Keep only last 4 taps
    }
    
    if (_tapTimestamps.length >= 2) {
      // Calculate average diff
      int totalMs = 0;
      for (int i = 1; i < _tapTimestamps.length; i++) {
        totalMs += _tapTimestamps[i].difference(_tapTimestamps[i - 1]).inMilliseconds;
      }
      
      double avgMs = totalMs / (_tapTimestamps.length - 1);
      
      if (avgMs > 0) {
        // 60,000 ms in a minute
        double newBpm = 60000.0 / avgMs;
        
        // Outlier rejection (if it wildly fluctuates, we don't snap immediately, but length=4 makes it smooth)
        bpm = double.parse(newBpm.toStringAsFixed(1));
      }
    }
  }
}
