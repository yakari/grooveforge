import 'package:flutter/foundation.dart';

/// Handles migrating legacy .gf project files to the current version.
class ProjectMigrationService {
  static const String currentVersion = '2.0.0';

  /// Migrates [data] in-place to the latest format if necessary.
  /// Returns true if any migration was applied.
  static bool migrate(Map<String, dynamic> data) {
    final version = data['version'] as String? ?? '1.0.0';
    
    if (version == currentVersion) return false;

    debugPrint('ProjectMigrationService: Migrating from $version to $currentVersion');

    if (version == '1.0.0') {
      _migrateFromV1ToV2(data);
    }

    data['version'] = currentVersion;
    return true;
  }

  static void _migrateFromV1ToV2(Map<String, dynamic> data) {
    // Port old global jam settings to the new GFPA jam slot if missing.
    // In v1, we had "jamMode": { "enabled": ..., "scaleType": ... }
    final oldJam = data['jamMode'] as Map<String, dynamic>?;
    final plugins = data['plugins'] as List<dynamic>? ?? [];

    if (oldJam != null && !plugins.any((p) => (p as Map)['pluginId'] == 'com.grooveforge.jammode')) {
      debugPrint('ProjectMigrationService: Porting legacy global jam state to new GFPA slot');
      
      // Create a new Jam Mode slot based on old global settings
      final jamSlot = {
        'id': 'slot-jam-migrated',
        'type': 'gfpa',
        'pluginId': 'com.grooveforge.jammode',
        'midiChannel': 0, // Global
        'masterSlotId': 'slot-1', // Reasonable guess for v1
        'targetSlotIds': ['slot-0'], // Reasonable guess for v1
        'state': {
          'enabled': oldJam['enabled'] ?? false,
          'scaleType': oldJam['scaleType'] ?? 'standard',
          'detectionMode': 'chord',
          'bpmLockBeats': 0,
        }
      };
      plugins.add(jamSlot);
      data['plugins'] = plugins;
    }
    
    // Cleanup old keys
    data.remove('jamMode');
  }
}
