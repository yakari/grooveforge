import 'plugin_instance.dart';

/// A rack slot that acts as a multi-track MIDI looper.
///
/// The looper captures incoming MIDI events (routed via the patch cable system)
/// and plays them back in a loop, synchronised to the global [TransportEngine]
/// beat clock.  Multiple [LoopTrack]s can play in parallel inside a single
/// looper slot, enabling live overdub layering.
///
/// **MIDI routing** (patch view):
/// ```
/// [Keyboard] MIDI OUT ──► [Looper] MIDI IN
///                          MIDI OUT ──► [Keyboard] MIDI IN   (playback)
///                          MIDI OUT ──► [Jam Mode] MIDI IN   (harmony lock)
/// ```
///
/// The looper slot itself produces no audio — it re-emits MIDI events that
/// were previously recorded.  Connect its MIDI OUT cable(s) to any instrument
/// or Jam Mode slot to hear the playback.
///
/// **Pinned display**: when [pinned] is true the UI shows this slot in a
/// dedicated area below the transport bar (like the Jam Mode quick-access
/// panel) rather than inside the scrollable rack list.
class LooperPluginInstance extends PluginInstance {
  @override
  final String id;

  /// MIDI channel filter for recording (1–16).
  /// 0 = record all channels (omni mode).
  @override
  int midiChannel;

  /// When true, this slot is rendered in a pinned panel below the transport
  /// bar rather than in the main rack scroll list.
  bool pinned;

  LooperPluginInstance({
    required this.id,
    this.midiChannel = 0,
    this.pinned = false,
  });

  @override
  // Localised label resolved at widget layer; this fallback covers contexts
  // without a BuildContext (e.g. JSON log messages).
  String get displayName => 'MIDI Looper';

  // ── JSON persistence ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> toJson() => {
        'type': 'looper',
        'id': id,
        'midiChannel': midiChannel,
        'pinned': pinned,
      };

  /// Deserialises a [LooperPluginInstance] from its JSON representation.
  factory LooperPluginInstance.fromJson(Map<String, dynamic> json) =>
      LooperPluginInstance(
        id: json['id'] as String,
        midiChannel: (json['midiChannel'] as int?) ?? 0,
        pinned: (json['pinned'] as bool?) ?? false,
      );
}
