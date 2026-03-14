import 'keyboard_display_config.dart';
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

  /// MIDI channel on which this slot's on-screen keyboard sends note events.
  ///
  /// Notes played on the front-panel piano are dispatched on this channel,
  /// allowing the slot to participate in Jam Mode and other channel-based
  /// processing. The channel can be changed via the badge in the slot header.
  @override
  int midiChannel;

  /// Per-slot keyboard display and expression overrides.
  ///
  /// When non-null, the fields inside override the corresponding global
  /// Preferences values for this slot only. Null fields within the config
  /// still fall back to global prefs. Persisted in the project .gf file.
  KeyboardDisplayConfig? keyboardConfig;

  VirtualPianoPlugin({
    required this.id,
    required this.midiChannel,
    this.keyboardConfig,
  });

  @override
  // Localised label is resolved at the widget layer via AppLocalizations.
  // This fallback is used in contexts where a BuildContext is unavailable.
  String get displayName => 'Virtual Piano';

  // ── JSON persistence ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> toJson() => {
        'type': 'virtual_piano',
        'id': id,
        'midiChannel': midiChannel,
        if (keyboardConfig != null)
          'keyboardConfig': keyboardConfig!.toJson(),
      };

  /// Deserialises a [VirtualPianoPlugin] from its JSON representation.
  factory VirtualPianoPlugin.fromJson(Map<String, dynamic> json) {
    final cfgJson = json['keyboardConfig'] as Map<String, dynamic>?;
    return VirtualPianoPlugin(
      id: json['id'] as String,
      midiChannel: (json['midiChannel'] as int?) ?? 1,
      keyboardConfig:
          cfgJson != null ? KeyboardDisplayConfig.fromJson(cfgJson) : null,
    );
  }
}
