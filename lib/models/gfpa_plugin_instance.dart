import '../audio/audio_source_descriptor.dart';
import 'keyboard_display_config.dart';
import 'plugin_instance.dart';

/// A rack slot backed by a GFPA (GrooveForge Plugin API) plugin.
///
/// The plugin is identified by [pluginId] and resolved at runtime from
/// [GFPluginRegistry]. If the plugin is not installed the slot shows a
/// placeholder without crashing — identical to how a missing VST3 path is
/// handled.
///
/// Serialised as `"type": "gfpa"` in `.gf` project files.
class GFpaPluginInstance with AudioSourcePlugin implements PluginInstance {
  /// Returns a descriptor for the three GFPA instruments that produce
  /// audio (theremin, stylophone, vocoder), or `null` for any other
  /// `pluginId` (effects, MIDI FX, and unrecognised slots). The plan
  /// builder uses `null` as the "skip — this is not a source" signal.
  @override
  AudioSourceDescriptor? describeAudioSource() => switch (pluginId) {
        'com.grooveforge.theremin' =>
          const AudioSourceDescriptor(kind: AudioSourceKind.theremin),
        'com.grooveforge.stylophone' =>
          const AudioSourceDescriptor(kind: AudioSourceKind.stylophone),
        'com.grooveforge.vocoder' =>
          const AudioSourceDescriptor(kind: AudioSourceKind.vocoder),
        _ => null,
      };


  @override
  final String id;

  /// MIDI channel (1–16) for instrument slots.
  /// 0 = no MIDI channel (MIDI FX and pure effect slots).
  @override
  int midiChannel;

  /// The plugin identifier, e.g. `"com.grooveforge.vocoder"`.
  final String pluginId;

  /// Plugin-specific state persisted to / restored from `.gf`.
  /// Content is defined by the plugin's own [GFPlugin.getState] /
  /// [GFPlugin.loadState] implementation.
  Map<String, dynamic> state;

  // ─── MIDI FX routing (Phase 3: pre-cable, stored as slot IDs) ─────────────

  /// For [GFMidiFxPlugin] slots: the rack slots whose notes get transformed.
  /// Multiple targets are supported — each target channel has its notes snapped
  /// independently. Becomes MIDI cables in Phase 5.
  List<String> targetSlotIds;

  /// For [GFMidiFxPlugin] slots: the rack slot that drives chord / scale
  /// detection. Becomes a MIDI cable in Phase 5.
  String? masterSlotId;

  /// When true, this slot is rendered in a pinned panel below the transport
  /// bar for quick access without scrolling to its rack slot.
  bool pinned;

  /// Per-slot keyboard display config (key count, height, gestures).
  ///
  /// Only meaningful for GFPA instrument slots that also show a virtual piano
  /// (currently the vocoder).  Null means "use global prefs".
  /// Persisted in the `state` map under the key `'keyboardConfig'`.
  KeyboardDisplayConfig? keyboardConfig;

  GFpaPluginInstance({
    required this.id,
    required this.pluginId,
    this.midiChannel = 0,
    Map<String, dynamic>? state,
    List<String>? targetSlotIds,
    this.masterSlotId,
    this.pinned = false,
    this.keyboardConfig,
  })  : state = state ?? {},
        targetSlotIds = targetSlotIds ?? [];

  // ─── PluginInstance ───────────────────────────────────────────────────────

  @override
  String get displayName {
    switch (pluginId) {
      case 'com.grooveforge.keyboard':
        return 'GrooveForge Keyboard';
      case 'com.grooveforge.vocoder':
        return 'Vocoder';
      case 'com.grooveforge.jammode':
        return 'Jam Mode';
      case 'com.grooveforge.stylophone':
        return 'Stylophone';
      case 'com.grooveforge.theremin':
        return 'Theremin';
      default:
        final parts = pluginId.split('.');
        return parts.isNotEmpty ? parts.last : pluginId;
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'gfpa',
        'pluginId': pluginId,
        'midiChannel': midiChannel,
        if (targetSlotIds.isNotEmpty) 'targetSlotIds': targetSlotIds,
        if (masterSlotId != null) 'masterSlotId': masterSlotId,
        if (pinned) 'pinned': true,
        'state': {
          ...state,
          // Persist keyboard config inside the state map so it round-trips
          // through project files alongside other plugin state.
          if (keyboardConfig != null)
            'keyboardConfig': keyboardConfig!.toJson(),
        },
      };

  factory GFpaPluginInstance.fromJson(Map<String, dynamic> json) {
    // Backward compat: old files had a single `targetSlotId` string.
    List<String> targetSlotIds;
    final newList = json['targetSlotIds'];
    if (newList is List) {
      targetSlotIds = List<String>.from(newList);
    } else {
      final old = json['targetSlotId'] as String?;
      targetSlotIds = old != null ? [old] : [];
    }

    final stateMap = Map<String, dynamic>.from(
      (json['state'] as Map<String, dynamic>?) ?? {},
    );
    final kbJson = stateMap['keyboardConfig'] as Map<String, dynamic>?;
    // Remove the nested keyboardConfig from the raw state map so it is not
    // duplicated — it is exposed via the typed keyboardConfig field instead.
    stateMap.remove('keyboardConfig');

    return GFpaPluginInstance(
      id: json['id'] as String,
      pluginId: json['pluginId'] as String,
      midiChannel: (json['midiChannel'] as num?)?.toInt() ?? 0,
      state: stateMap,
      targetSlotIds: targetSlotIds,
      masterSlotId: json['masterSlotId'] as String?,
      pinned: (json['pinned'] as bool?) ?? false,
      keyboardConfig:
          kbJson != null ? KeyboardDisplayConfig.fromJson(kbJson) : null,
    );
  }

  GFpaPluginInstance copyWith({
    String? id,
    String? pluginId,
    int? midiChannel,
    Map<String, dynamic>? state,
    List<String>? targetSlotIds,
    String? masterSlotId,
    bool clearMasterSlot = false,
    bool? pinned,
    KeyboardDisplayConfig? keyboardConfig,
    bool clearKeyboardConfig = false,
  }) =>
      GFpaPluginInstance(
        id: id ?? this.id,
        pluginId: pluginId ?? this.pluginId,
        midiChannel: midiChannel ?? this.midiChannel,
        state: state ?? Map.from(this.state),
        targetSlotIds: targetSlotIds ?? List.from(this.targetSlotIds),
        masterSlotId: clearMasterSlot ? null : (masterSlotId ?? this.masterSlotId),
        pinned: pinned ?? this.pinned,
        keyboardConfig: clearKeyboardConfig
            ? null
            : (keyboardConfig ?? this.keyboardConfig),
      );
}
