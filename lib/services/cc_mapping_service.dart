import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Defines a routing rule for translating hardware MIDI input to application actions.
///
/// For example, a mapping might state: "When hardware CC #20 is received,
/// translate it to GM Filter Cutoff (CC #74) and apply it to all channels."
///
/// The optional [muteChannels] field is used exclusively by system action 1014
/// ([System] Mute / Unmute Channels) to specify which channels (0-based, 0-15)
/// are toggled by that CC.  It is null / ignored for all other target codes.
class CcMapping {
  final int incomingCc;
  final int targetCc;
  final int targetChannel; // -1 for All, -2 for Same, 0..15 for specific 1..16

  /// Channels to mute/unmute when [targetCc] == 1014 (sorted 0-15).
  /// Null for all other target codes.
  final Set<int>? muteChannels;

  CcMapping({
    required this.incomingCc,
    required this.targetCc,
    required this.targetChannel,
    this.muteChannels,
  });

  /// Encoded format: `incoming:target:channel[:m:ch1,ch2,…]`
  ///
  /// The optional `:m:…` suffix carries the mute-channel list for action 1014.
  factory CcMapping.fromString(String str) {
    final parts = str.split(':');
    Set<int>? mute;
    // Suffix format: …:m:0,3,5  — position 3 is the literal 'm' marker
    if (parts.length >= 5 && parts[3] == 'm') {
      mute = parts[4].split(',').map(int.parse).toSet();
    }
    return CcMapping(
      incomingCc: int.parse(parts[0]),
      targetCc: int.parse(parts[1]),
      targetChannel: parts.length > 2 ? int.parse(parts[2]) : -2,
      muteChannels: mute,
    );
  }

  String encode() {
    final base = '$incomingCc:$targetCc:$targetChannel';
    if (muteChannels != null && muteChannels!.isNotEmpty) {
      final channelList = (muteChannels!.toList()..sort()).join(',');
      return '$base:m:$channelList';
    }
    return base;
  }
}

/// Manages user-defined MIDI Control Change (CC) routing rules.
///
/// Intercepts incoming MIDI CC events and translates them according to user
/// preferences before they reach the main synthesizer engine. It handles:
/// - Persisting mappings using [SharedPreferences].
/// - Providing standard GM mapping targets (like Reverb, Chorus).
/// - Defining special system action targets (like `[System] Next Patch`).
class CcMappingService {
  final ValueNotifier<Map<int, CcMapping>> mappingsNotifier = ValueNotifier({});
  final ValueNotifier<MidiEventInfo?> lastEventNotifier = ValueNotifier(null);

  // Standard GM CCs for the dropdown
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

    // --- GrooveForge System Actions ---
    1001: '[System] Next Soundfont',
    1002: '[System] Prev Soundfont',
    1003: '[System] Next Program/Patch',
    1004: '[System] Prev Program/Patch',
    1005: '[System] Absolute Patch Sweep',
    1006: '[System] Absolute Bank/Tone Sweep',
    1007: '[System] Start/Stop Jam Mode',
    1008: '[System] Cycle Scale Type',

    // --- Looper Actions ---
    1009: '[Looper] Record / Stop Rec',
    1010: '[Looper] Play / Pause',
    1011: '[Looper] Overdub',
    1012: '[Looper] Stop',
    1013: '[Looper] Clear All',

    // --- Channel Mute ---
    1014: '[System] Mute / Unmute Channels',
  };

  /// Returns true if [targetCc] is a looper system action (1009-1013).
  ///
  /// Used by the CC preferences UI to hide the channel-routing selector,
  /// which is irrelevant for looper actions (they target the single looper slot).
  static bool isLooperAction(int targetCc) =>
      targetCc >= 1009 && targetCc <= 1013;

  /// Returns true if [targetCc] is the mute/unmute action (1014).
  ///
  /// Used by the CC preferences UI to show the channel multiselect widget
  /// instead of the standard channel-routing dropdown.
  static bool isMuteAction(int targetCc) => targetCc == 1014;

  SharedPreferences? _prefs;
  static const String _prefsKey = 'cc_advanced_mappings';

  CcMappingService() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadMappings();
  }

  void _loadMappings() {
    if (_prefs == null) return;
    // We changed the key to avoid parsing errors with the old simple mappings
    final List<String> savedList = _prefs!.getStringList(_prefsKey) ?? [];
    Map<int, CcMapping> loaded = {};
    for (String item in savedList) {
      try {
        final mapping = CcMapping.fromString(item);
        loaded[mapping.incomingCc] = mapping;
      } catch (e) {
        debugPrint('Error loading CC mapping: $e');
      }
    }
    mappingsNotifier.value = loaded;
  }

  Future<void> saveMapping(CcMapping mapping) async {
    final newMap = Map<int, CcMapping>.from(mappingsNotifier.value);
    newMap[mapping.incomingCc] = mapping;
    mappingsNotifier.value = newMap;
    await _persist();
  }

  Future<void> removeMapping(int incomingCc) async {
    final newMap = Map<int, CcMapping>.from(mappingsNotifier.value);
    newMap.remove(incomingCc);
    mappingsNotifier.value = newMap;
    await _persist();
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    List<String> toSave =
        mappingsNotifier.value.values.map((m) => m.encode()).toList();
    await _prefs!.setStringList(_prefsKey, toSave);
  }

  void updateLastEvent(String type, int channel, int data1, int data2) {
    lastEventNotifier.value = MidiEventInfo(
      type: type,
      channel: channel,
      data1: data1,
      data2: data2,
    );
  }

  CcMapping? getMapping(int incomingCc) {
    return mappingsNotifier.value[incomingCc];
  }
}
