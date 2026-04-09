import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── MIDI event info (diagnostic display) ─────────────────────────────────────

/// A lightweight data model representing an incoming MIDI event.
///
/// Used primarily by the UI for diagnostic display (e.g., showing the user
/// what CC number they just triggered on their hardware).
class MidiEventInfo {
  final String type; // "CC", "Note On", "Note Off", etc.
  final int channel; // 0-15
  final int data1;
  final int data2;

  MidiEventInfo({
    required this.type,
    required this.channel,
    required this.data1,
    required this.data2,
  });
}

// ── CC mapping target hierarchy ──────────────────────────────────────────────
//
// Sealed class with six concrete subtypes. Each represents a different kind
// of action that a hardware CC can trigger.

/// The action performed when a hardware CC event matches a mapping.
///
/// Each subtype serializes to JSON with a `"type"` discriminator field
/// so it can be persisted in `.gf` project files.
sealed class CcMappingTarget {
  const CcMappingTarget();

  Map<String, dynamic> toJson();

  /// Deserializes a target from its JSON representation.
  ///
  /// The `"type"` field selects the concrete subclass:
  /// `gmCc`, `system`, `slotParam`, `swap`, `transport`, `global`.
  static CcMappingTarget fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'gmCc' => GmCcTarget.fromJson(json),
      'system' => SystemTarget.fromJson(json),
      'slotParam' => SlotParamTarget.fromJson(json),
      'swap' => SwapTarget.fromJson(json),
      'transport' => TransportTarget.fromJson(json),
      'global' => GlobalTarget.fromJson(json),
      _ => throw ArgumentError('Unknown CcMappingTarget type: $type'),
    };
  }
}

/// Standard GM CC remapping — translates one CC number to another.
///
/// Preserves existing behavior: CC 20 on hardware → CC 74 (filter cutoff)
/// on a specific channel, all channels, or the same incoming channel.
class GmCcTarget extends CcMappingTarget {
  /// GM CC number to send (0-127).
  final int targetCc;

  /// Channel routing: -1 = all 16, -2 = same as incoming, 0-15 = specific.
  final int targetChannel;

  const GmCcTarget({required this.targetCc, required this.targetChannel});

  factory GmCcTarget.fromJson(Map<String, dynamic> json) => GmCcTarget(
        targetCc: json['targetCc'] as int,
        targetChannel: json['channel'] as int? ?? -2,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'gmCc',
        'targetCc': targetCc,
        'channel': targetChannel,
      };
}

/// Legacy system actions (codes 1001-1014) for backward compatibility.
///
/// Covers: next/prev soundfont (1001-1002), next/prev patch (1003-1004),
/// absolute patch/bank sweep (1005-1006), jam mode toggle (1007),
/// cycle scale type (1008), looper button/stop (1009/1012),
/// mute/unmute channels (1014).
class SystemTarget extends CcMappingTarget {
  /// System action code (1001-1014).
  final int actionCode;

  /// Channel routing: -1 = all 16, -2 = same as incoming, 0-15 = specific.
  final int targetChannel;

  /// Channels to mute/unmute when [actionCode] == 1014 (0-based, 0-15).
  /// Null for all other action codes.
  final Set<int>? muteChannels;

  const SystemTarget({
    required this.actionCode,
    required this.targetChannel,
    this.muteChannels,
  });

  factory SystemTarget.fromJson(Map<String, dynamic> json) {
    Set<int>? mute;
    if (json.containsKey('muteChannels')) {
      mute = (json['muteChannels'] as List<dynamic>)
          .map((e) => e as int)
          .toSet();
    }
    return SystemTarget(
      actionCode: json['actionCode'] as int,
      targetChannel: json['channel'] as int? ?? -2,
      muteChannels: mute,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'type': 'system',
      'actionCode': actionCode,
      'channel': targetChannel,
    };
    if (muteChannels != null && muteChannels!.isNotEmpty) {
      map['muteChannels'] = muteChannels!.toList()..sort();
    }
    return map;
  }
}

/// Controls a specific parameter on a specific rack slot.
///
/// For example: CC 21 → reverb mix on slot-3 (absolute mode),
/// or CC 64 → bypass toggle on slot-3 (toggle mode).
class SlotParamTarget extends CcMappingTarget {
  /// Rack slot identifier (e.g. "slot-2").
  final String slotId;

  /// Parameter key from the curated registry (e.g. "bypass", "mix", "waveform").
  final String paramKey;

  /// How the CC value maps to the parameter.
  final CcParamMode mode;

  const SlotParamTarget({
    required this.slotId,
    required this.paramKey,
    required this.mode,
  });

  factory SlotParamTarget.fromJson(Map<String, dynamic> json) =>
      SlotParamTarget(
        slotId: json['slotId'] as String,
        paramKey: json['paramKey'] as String,
        mode: CcParamMode.values.byName(json['mode'] as String),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'slotParam',
        'slotId': slotId,
        'paramKey': paramKey,
        'mode': mode.name,
      };
}

/// Swaps two instrument slots' MIDI channels and optionally their cables.
///
/// When [swapCables] is true, AudioGraph connections, Jam Mode references,
/// and CC mappings targeting either slot are also swapped — the two instruments
/// trade their entire signal chains. When false, only the MIDI channels swap.
class SwapTarget extends CcMappingTarget {
  final String slotIdA;
  final String slotIdB;

  /// If true, swap AudioGraph cables, Jam Mode references, and CC slot refs.
  /// If false, only swap MIDI channels.
  final bool swapCables;

  const SwapTarget({
    required this.slotIdA,
    required this.slotIdB,
    this.swapCables = true,
  });

  factory SwapTarget.fromJson(Map<String, dynamic> json) => SwapTarget(
        slotIdA: json['slotIdA'] as String,
        slotIdB: json['slotIdB'] as String,
        swapCables: json['swapCables'] as bool? ?? true,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'swap',
        'slotIdA': slotIdA,
        'slotIdB': slotIdB,
        'swapCables': swapCables,
      };
}

/// Transport-level actions (play/stop, tap tempo, metronome toggle).
class TransportTarget extends CcMappingTarget {
  final TransportAction action;

  const TransportTarget({required this.action});

  factory TransportTarget.fromJson(Map<String, dynamic> json) =>
      TransportTarget(
        action: TransportAction.values.byName(json['action'] as String),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'transport',
        'action': action.name,
      };
}

/// System-level global actions (OS media volume control).
class GlobalTarget extends CcMappingTarget {
  final GlobalAction action;

  const GlobalTarget({required this.action});

  factory GlobalTarget.fromJson(Map<String, dynamic> json) => GlobalTarget(
        action: GlobalAction.values.byName(json['action'] as String),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'global',
        'action': action.name,
      };
}

/// How a CC value (0-127) maps to a slot parameter.
enum CcParamMode {
  /// CC 0-127 maps linearly to the parameter's normalized range [0.0, 1.0].
  absolute,

  /// Toggles a boolean state (debounced 250ms).
  toggle,

  /// Advances a discrete parameter to the next option (debounced).
  cycle,
}

/// Transport-level actions that can be triggered by CC.
enum TransportAction {
  /// Toggle transport play/stop.
  playStop,

  /// Tap tempo — fires on every CC event.
  tapTempo,

  /// Toggle metronome click on/off.
  metronomeToggle,
}

/// System-level global actions that can be triggered by CC.
enum GlobalAction {
  /// CC 0-127 maps to OS media volume (0-100%).
  /// Platform-specific: AudioManager on Android, pactl on Linux, osascript on macOS.
  systemVolume,
}

// ── CC mapping model ─────────────────────────────────────────────────────────

/// A single CC mapping: "when hardware CC [incomingCc] fires, do [target]."
///
/// Multiple mappings can share the same [incomingCc] — one hardware knob
/// can control several targets simultaneously (e.g. reverb mix + delay mix).
class CcMapping {
  /// Hardware CC number (0-127).
  final int incomingCc;

  /// What this CC controls — one of the six target types.
  final CcMappingTarget target;

  const CcMapping({required this.incomingCc, required this.target});

  factory CcMapping.fromJson(Map<String, dynamic> json) => CcMapping(
        incomingCc: json['cc'] as int,
        target: CcMappingTarget.fromJson(json['target'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'cc': incomingCc,
        'target': target.toJson(),
      };

  // ── Migration from legacy format ──────────────────────────────────────

  /// Converts a legacy `incoming:targetCc:channel[:m:ch1,ch2,…]` string
  /// into the new model.  Used for one-time migration from SharedPreferences.
  factory CcMapping.fromLegacyString(String str) {
    final parts = str.split(':');
    final incomingCc = int.parse(parts[0]);
    final targetCc = int.parse(parts[1]);
    final targetChannel = parts.length > 2 ? int.parse(parts[2]) : -2;

    // Parse optional mute channels suffix: …:m:0,3,5
    Set<int>? muteChannels;
    if (parts.length >= 5 && parts[3] == 'm') {
      muteChannels = parts[4].split(',').map(int.parse).toSet();
    }

    // Route to the appropriate target type.
    final CcMappingTarget target;
    if (targetCc >= 1000) {
      target = SystemTarget(
        actionCode: targetCc,
        targetChannel: targetChannel,
        muteChannels: muteChannels,
      );
    } else {
      target = GmCcTarget(
        targetCc: targetCc,
        targetChannel: targetChannel,
      );
    }

    return CcMapping(incomingCc: incomingCc, target: target);
  }
}

// ── CC mapping service ───────────────────────────────────────────────────────

/// Manages user-defined MIDI Control Change (CC) routing rules.
///
/// Intercepts incoming MIDI CC events and translates them according to
/// project-specific mappings. Mappings are stored per-project in `.gf` files
/// and loaded/saved by [ProjectService].
///
/// Legacy SharedPreferences mappings are migrated once on first project save
/// and then deleted.
class CcMappingService {
  /// All active CC mappings, indexed by incoming CC for O(1) lookup.
  final ValueNotifier<List<CcMapping>> mappingsNotifier = ValueNotifier([]);

  /// Most recent MIDI event for UI diagnostic display.
  final ValueNotifier<MidiEventInfo?> lastEventNotifier = ValueNotifier(null);

  /// Pre-built index: incoming CC → list of mappings with that CC.
  /// Rebuilt whenever [mappingsNotifier] changes.
  Map<int, List<CcMapping>> _index = {};

  // ── Standard GM CCs (used by the CC preferences dropdown) ────────────

  static const Map<int, String> standardGmCcs = {
    0: 'Bank Select (MSB)',
    1: 'Modulation Wheel (Vibrato)',
    2: 'Breath Control',
    4: 'Foot Pedal',
    5: 'Portamento Time',
    7: 'Main Volume',
    10: 'Pan (Stereo)',
    11: 'Expression',
    64: 'Sustain Pedal',
    65: 'Portamento',
    71: 'Resonance (Filter)',
    74: 'Frequency Cutoff (Filter)',
    91: 'Reverb Send Level',
    93: 'Chorus Send Level',

    // --- Legacy GrooveForge System Actions ---
    1001: '[System] Next Soundfont',
    1002: '[System] Prev Soundfont',
    1003: '[System] Next Program/Patch',
    1004: '[System] Prev Program/Patch',
    1005: '[System] Absolute Patch Sweep',
    1006: '[System] Absolute Bank/Tone Sweep',
    1007: '[System] Start/Stop Jam Mode',
    1008: '[System] Cycle Scale Type',

    // --- MIDI Looper Actions ---
    1009: '[MIDI Looper] Loop Button',
    1012: '[MIDI Looper] Stop',

    // --- Audio Looper Actions ---
    1015: '[Audio Looper] Loop Button',
    1016: '[Audio Looper] Stop',

    // --- Channel Mute ---
    1014: '[System] Mute / Unmute Channels',
  };

  /// Returns true if [targetCc] is a MIDI looper system action (1009 or 1012).
  static bool isLooperAction(int targetCc) =>
      targetCc == 1009 || targetCc == 1012;

  /// Returns true if [targetCc] is an audio looper system action (1015 or 1016).
  static bool isAudioLooperAction(int targetCc) =>
      targetCc == 1015 || targetCc == 1016;

  /// Returns true if [targetCc] is the mute/unmute action (1014).
  static bool isMuteAction(int targetCc) => targetCc == 1014;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  CcMappingService();

  // ── Query ─────────────────────────────────────────────────────────────

  /// Returns all mappings for [incomingCc], or an empty list if none.
  List<CcMapping> getMappings(int incomingCc) {
    return _index[incomingCc] ?? const [];
  }

  /// Backward-compatible single-mapping lookup.
  ///
  /// Returns the first `GmCcTarget` or `SystemTarget` mapping for
  /// [incomingCc], or null.  Used by the existing dispatch code in
  /// [AudioEngine] until the full sealed dispatch is wired in Phase C.
  CcMapping? getMapping(int incomingCc) {
    final list = _index[incomingCc];
    if (list == null || list.isEmpty) return null;
    // Return the first legacy-compatible mapping (GmCc or System).
    for (final m in list) {
      if (m.target is GmCcTarget || m.target is SystemTarget) return m;
    }
    return list.first;
  }

  // ── Mutation ──────────────────────────────────────────────────────────

  /// Adds a mapping to the active set.
  void addMapping(CcMapping mapping) {
    final newList = List<CcMapping>.from(mappingsNotifier.value)..add(mapping);
    _setMappings(newList);
  }

  /// Removes all mappings that match [incomingCc] and have an identical target.
  void removeMapping(CcMapping mapping) {
    final newList = mappingsNotifier.value
        .where((m) =>
            !(m.incomingCc == mapping.incomingCc &&
              _targetsEqual(m.target, mapping.target)))
        .toList();
    _setMappings(newList);
  }

  /// Removes ALL mappings for a given incoming CC number.
  void removeAllForCc(int incomingCc) {
    final newList =
        mappingsNotifier.value.where((m) => m.incomingCc != incomingCc).toList();
    _setMappings(newList);
  }

  /// Removes all mappings that reference [slotId] in a `SlotParamTarget`
  /// or `SwapTarget`.  Called when a slot is deleted from the rack.
  void removeOrphanedSlotMappings(String slotId) {
    final newList = mappingsNotifier.value.where((m) {
      final t = m.target;
      if (t is SlotParamTarget && t.slotId == slotId) return false;
      if (t is SwapTarget && (t.slotIdA == slotId || t.slotIdB == slotId)) {
        return false;
      }
      return true;
    }).toList();
    if (newList.length != mappingsNotifier.value.length) {
      _setMappings(newList);
    }
  }

  /// Rewrites all [SlotParamTarget] and [SwapTarget] entries so that every
  /// reference to [slotIdA] becomes [slotIdB] and vice versa.
  ///
  /// Called by the channel-swap macro when `swapCables == true` to keep CC
  /// mappings consistent after the two slots trade signal chains.
  void swapSlotReferences(String slotIdA, String slotIdB) {
    if (slotIdA == slotIdB) return;
    bool changed = false;
    final newList = mappingsNotifier.value.map((m) {
      final t = m.target;
      CcMappingTarget? swapped;
      if (t is SlotParamTarget) {
        if (t.slotId == slotIdA) {
          swapped = SlotParamTarget(
              slotId: slotIdB, paramKey: t.paramKey, mode: t.mode);
        } else if (t.slotId == slotIdB) {
          swapped = SlotParamTarget(
              slotId: slotIdA, paramKey: t.paramKey, mode: t.mode);
        }
      } else if (t is SwapTarget) {
        final a = _swapId(t.slotIdA, slotIdA, slotIdB);
        final b = _swapId(t.slotIdB, slotIdA, slotIdB);
        if (a != t.slotIdA || b != t.slotIdB) {
          swapped = SwapTarget(slotIdA: a, slotIdB: b, swapCables: t.swapCables);
        }
      }
      if (swapped != null) {
        changed = true;
        return CcMapping(incomingCc: m.incomingCc, target: swapped);
      }
      return m;
    }).toList();
    if (changed) _setMappings(newList);
  }

  /// Returns [slotIdB] if [current] equals [slotIdA], [slotIdA] if it equals
  /// [slotIdB], or [current] unchanged.
  static String _swapId(String current, String slotIdA, String slotIdB) {
    if (current == slotIdA) return slotIdB;
    if (current == slotIdB) return slotIdA;
    return current;
  }

  /// Replaces all mappings wholesale.  Called by [ProjectService] on load.
  void loadFromJson(List<dynamic> json) {
    final list = <CcMapping>[];
    for (final entry in json) {
      try {
        list.add(CcMapping.fromJson(entry as Map<String, dynamic>));
      } catch (e) {
        debugPrint('CcMappingService: skipping invalid mapping — $e');
      }
    }
    _setMappings(list);
  }

  /// Serializes all mappings for project save.
  List<Map<String, dynamic>> toJson() {
    return mappingsNotifier.value.map((m) => m.toJson()).toList();
  }

  /// Clears all mappings (used on app start with no project).
  void clear() {
    _setMappings([]);
  }

  // ── Legacy migration ──────────────────────────────────────────────────

  /// Key used by the old SharedPreferences-based storage.
  static const String _legacyPrefsKey = 'cc_advanced_mappings';

  /// Migrates mappings from the legacy SharedPreferences format into the
  /// current in-memory model.  Returns the migrated list, or an empty list
  /// if there was nothing to migrate.
  ///
  /// Call this when loading a `.gf` file that has no `ccMappings` key.
  /// After migration, the caller should save the project (so the mappings
  /// are persisted in the `.gf` file) and then call [deleteLegacyPrefs].
  Future<List<CcMapping>> migrateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_legacyPrefsKey);
    if (saved == null || saved.isEmpty) return [];
    final migrated = <CcMapping>[];
    for (final str in saved) {
      try {
        migrated.add(CcMapping.fromLegacyString(str));
      } catch (e) {
        debugPrint('CcMappingService: skipping legacy mapping "$str" — $e');
      }
    }
    return migrated;
  }

  /// Deletes the legacy SharedPreferences key after successful migration.
  Future<void> deleteLegacyPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyPrefsKey);
  }

  // ── MIDI event logging ────────────────────────────────────────────────

  void updateLastEvent(String type, int channel, int data1, int data2) {
    lastEventNotifier.value = MidiEventInfo(
      type: type,
      channel: channel,
      data1: data1,
      data2: data2,
    );
  }

  // ── Internal ──────────────────────────────────────────────────────────

  void _setMappings(List<CcMapping> list) {
    mappingsNotifier.value = list;
    _rebuildIndex();
  }

  /// Rebuilds the O(1) lookup index from the flat list.
  void _rebuildIndex() {
    final idx = <int, List<CcMapping>>{};
    for (final m in mappingsNotifier.value) {
      (idx[m.incomingCc] ??= []).add(m);
    }
    _index = idx;
  }

  /// Structural equality for targets (used by [removeMapping]).
  bool _targetsEqual(CcMappingTarget a, CcMappingTarget b) {
    if (a.runtimeType != b.runtimeType) return false;
    // Compare JSON representations for simplicity.
    final ja = a.toJson();
    final jb = b.toJson();
    if (ja.length != jb.length) return false;
    for (final key in ja.keys) {
      if (ja[key].toString() != jb[key].toString()) return false;
    }
    return true;
  }
}
