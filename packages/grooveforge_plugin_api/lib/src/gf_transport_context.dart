/// Read-only snapshot of the host transport state, passed to plugins on every
/// audio / MIDI processing call.
class GFTransportContext {
  final double bpm;
  final int timeSigNumerator;
  final int timeSigDenominator;
  final bool isPlaying;
  final bool isRecording;
  final double positionInBeats;

  const GFTransportContext({
    this.bpm = 120.0,
    this.timeSigNumerator = 4,
    this.timeSigDenominator = 4,
    this.isPlaying = false,
    this.isRecording = false,
    this.positionInBeats = 0.0,
  });

  /// Stopped transport at position 0, 120 BPM, 4/4.
  static const GFTransportContext stopped = GFTransportContext();
}
