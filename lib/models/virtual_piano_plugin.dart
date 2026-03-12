import 'plugin_instance.dart';

/// A lightweight rack slot that represents the touchscreen keyboard as a
/// standalone MIDI signal source.
///
/// Unlike [GrooveForgeKeyboardPlugin], this slot produces **no audio** and
/// loads no soundfont. Its sole purpose is to expose a **MIDI OUT** jack in
/// the patch view, enabling advanced routing scenarios such as:
///
/// ```
/// [Virtual Piano] MIDI OUT ──► [Jam Mode] MIDI IN
///                                   │ MIDI OUT
///                                   ▼
///                             [Keyboard] MIDI IN
/// ```
///
/// This allows on-screen touch input to pass through scale-locking (Jam Mode)
/// before arriving at an instrument slot — useful on tablets where no hardware
/// MIDI controller is connected.
///
/// **The existing [GrooveForgeKeyboardPlugin] is unchanged.** The
/// [VirtualPianoPlugin] is a new, optional, addable slot type. Users who want
/// the simple all-in-one experience (touchscreen + soundfont in one slot)
/// continue to use [GrooveForgeKeyboardPlugin] as before.
class VirtualPianoPlugin extends PluginInstance {
  @override
  final String id;

  /// MIDI channel is unused for [VirtualPianoPlugin] — this slot does not
  /// transmit MIDI channel messages directly to the audio engine. Routing
  /// is performed entirely through audio-graph cable connections.
  @override
  int midiChannel = 0;

  VirtualPianoPlugin({required this.id});

  @override
  // Localised label is resolved at the widget layer via AppLocalizations.
  // This fallback is used in contexts where a BuildContext is unavailable.
  String get displayName => 'Virtual Piano';

  // ── JSON persistence ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> toJson() => {
        'type': 'virtual_piano',
        'id': id,
      };

  /// Deserialises a [VirtualPianoPlugin] from its JSON representation.
  factory VirtualPianoPlugin.fromJson(Map<String, dynamic> json) {
    return VirtualPianoPlugin(id: json['id'] as String);
  }
}
