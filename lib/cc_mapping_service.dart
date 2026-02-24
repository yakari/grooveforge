import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CcMappingService {
  final ValueNotifier<Map<int, int>> mappingsNotifier = ValueNotifier({});
  final ValueNotifier<int?> lastReceivedCcNotifier = ValueNotifier(null);
  final ValueNotifier<int?> lastReceivedValueNotifier = ValueNotifier(null);

  SharedPreferences? _prefs;
  static const String _prefsKey = 'cc_mappings';

  CcMappingService() {
    _init();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _loadMappings();
  }

  void _loadMappings() {
    if (_prefs == null) return;
    final List<String> savedList = _prefs!.getStringList(_prefsKey) ?? [];
    Map<int, int> loaded = {};
    for (String item in savedList) {
      final parts = item.split(':');
      if (parts.length == 2) {
        int? incoming = int.tryParse(parts[0]);
        int? target = int.tryParse(parts[1]);
        if (incoming != null && target != null) {
          loaded[incoming] = target;
        }
      }
    }
    mappingsNotifier.value = loaded;
  }

  Future<void> saveMapping(int incomingCc, int targetCc) async {
    final newMap = Map<int, int>.from(mappingsNotifier.value);
    newMap[incomingCc] = targetCc;
    mappingsNotifier.value = newMap; // Update UI immediately
    await _persist();
  }

  Future<void> removeMapping(int incomingCc) async {
    final newMap = Map<int, int>.from(mappingsNotifier.value);
    newMap.remove(incomingCc);
    mappingsNotifier.value = newMap;
    await _persist();
  }

  Future<void> _persist() async {
    if (_prefs == null) return;
    List<String> toSave = mappingsNotifier.value.entries
        .map((e) => '${e.key}:${e.value}')
        .toList();
    await _prefs!.setStringList(_prefsKey, toSave);
  }

  void updateLastReceived(int cc, int value) {
    // Only update if it actually changed to prevent excessive rebuilds
    if (lastReceivedCcNotifier.value != cc) {
      lastReceivedCcNotifier.value = cc;
    }
    lastReceivedValueNotifier.value = value;
  }

  int getTargetCc(int incomingCc) {
    return mappingsNotifier.value[incomingCc] ?? incomingCc;
  }
}
