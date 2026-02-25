import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class CcMapping {
  final int incomingCc;
  final int targetCc;
  final int targetChannel; // -1 for All, -2 for Same, 0..15 for specific 1..16

  CcMapping({
    required this.incomingCc,
    required this.targetCc,
    required this.targetChannel,
  });

  factory CcMapping.fromString(String str) {
    final parts = str.split(':');
    return CcMapping(
      incomingCc: int.parse(parts[0]),
      targetCc: int.parse(parts[1]),
      targetChannel: parts.length > 2 ? int.parse(parts[2]) : -2,
    );
  }

  String encode() => '$incomingCc:$targetCc:$targetChannel';
}

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
    
    // --- Yakalive System Actions ---
    1001: '[System] Next Soundfont',
    1002: '[System] Prev Soundfont',
    1003: '[System] Next Program/Patch',
    1004: '[System] Prev Program/Patch',
    1005: '[System] Absolute Patch Sweep',
    1006: '[System] Absolute Bank/Tone Sweep',
    1007: '[System] Toggle Scale Lock',
    1008: '[System] Cycle Scale Type',
  };

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
    List<String> toSave = mappingsNotifier.value.values
        .map((m) => m.encode())
        .toList();
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
