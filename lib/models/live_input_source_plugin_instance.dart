import '../audio/audio_source_descriptor.dart';
import 'plugin_instance.dart';

/// A rack source slot that exposes a hardware audio input (microphone,
/// line-in, instrument jack) as an audio-graph output jack.
///
/// Unlike the Audio Looper, this slot does not record or process audio —
/// it is a pure source node. Cable its audio output into any GFPA effect
/// (Audio Harmonizer, Vocoder, reverb…) to process a live input in
/// real time, the same way a guitar pedalboard does.
///
/// Typical use cases:
///   - Sing through the Audio Harmonizer for live 4-voice harmonies.
///   - Plug a guitar into a VST3 amp simulator.
///   - Route a second line-in (on multi-input interfaces) into the vocoder
///     as a modulator independent of the primary capture path.
///
/// The actual capture stream lives in C++ (miniaudio on desktop, Oboe on
/// Android). This Dart class holds only the persisted selection state and
/// the render-function pointer handed to [VstHostService.syncAudioRouting].
class LiveInputSourcePluginInstance extends PluginInstance
    with AudioSourcePlugin {
  @override
  AudioSourceDescriptor describeAudioSource() => const AudioSourceDescriptor(
        kind: AudioSourceKind.liveInput,
      );

  @override
  final String id;

  /// Source slots do not use MIDI channels.
  @override
  int midiChannel = 0;

  /// Miniaudio / Oboe capture device identifier, as returned by
  /// [AudioInputFFI.getCaptureDeviceName]. Empty string means
  /// "system default" — the engine picks whichever device is current.
  String deviceId;

  /// Which channel pair (or mono channel) of the device to tap.
  ///
  /// Values: `"1+2"` (stereo first pair), `"3+4"`, `"1"` (mono left),
  /// `"2"` (mono right), … Interpretation is handled by the native side;
  /// the Dart layer treats it as an opaque string.
  String channelPair;

  /// Input gain in decibels, clamped to −24…+24 by the UI. Applied
  /// post-capture, pre-graph so the cabled destination sees the scaled
  /// signal.
  double gainDb;

  /// When true, the slot mutes its direct monitor output so that only the
  /// cabled effect chain is audible. Prevents feedback when the user is
  /// not wearing headphones.
  bool monitorMute;

  LiveInputSourcePluginInstance({
    required this.id,
    this.deviceId = '',
    this.channelPair = '1+2',
    this.gainDb = 0.0,
    this.monitorMute = true,
  });

  @override
  String get displayName => 'Live Input';

  // ── JSON persistence ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> toJson() => {
        'type': 'live_input_source',
        'id': id,
        'deviceId': deviceId,
        'channelPair': channelPair,
        'gainDb': gainDb,
        'monitorMute': monitorMute,
      };

  /// Deserialises a [LiveInputSourcePluginInstance] from its JSON form.
  ///
  /// Missing fields fall back to constructor defaults so projects saved
  /// by earlier pre-release builds still load cleanly.
  factory LiveInputSourcePluginInstance.fromJson(Map<String, dynamic> json) {
    return LiveInputSourcePluginInstance(
      id: json['id'] as String,
      deviceId: (json['deviceId'] as String?) ?? '',
      channelPair: (json['channelPair'] as String?) ?? '1+2',
      gainDb: (json['gainDb'] as num?)?.toDouble() ?? 0.0,
      monitorMute: (json['monitorMute'] as bool?) ?? true,
    );
  }
}
