import 'plugin_instance.dart';

/// A rack slot that acts as a PCM audio looper.
///
/// Records raw stereo audio from the master mix (or a specific slot output)
/// and plays it back in a loop, synchronised to the global transport clock.
/// Supports overdub, reverse playback, and per-clip volume control.
///
/// Unlike the MIDI looper, this captures the actual rendered audio including
/// all effects, vocoder processing, and VST3 plugins — making it suitable
/// for hardware-style live looping workflows.
///
/// The PCM buffer lives in C++ (pre-allocated, RT-safe). The Dart side
/// controls state transitions and persists clip metadata + WAV sidecar files.
class AudioLooperPluginInstance extends PluginInstance {
  @override
  final String id;

  /// Audio looper slots do not use MIDI channels.
  @override
  int midiChannel = 0;

  AudioLooperPluginInstance({required this.id});

  @override
  String get displayName => 'Audio Looper';

  // ── JSON persistence ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> toJson() => {
        'type': 'audio_looper',
        'id': id,
      };

  /// Deserialises an [AudioLooperPluginInstance] from its JSON representation.
  factory AudioLooperPluginInstance.fromJson(Map<String, dynamic> json) =>
      AudioLooperPluginInstance(id: json['id'] as String);
}
