import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'file_picker_service.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_engine.dart';
import 'audio_graph.dart';
import 'cc_mapping_service.dart';
import 'looper_engine.dart';
import 'project_migration_service.dart';
import 'rack_state.dart';
import 'transport_engine.dart';

/// Manages loading and saving current project state to a .gf file.
class ProjectService extends ChangeNotifier {
  static const String _formatVersion = '2.0.0';

  /// Direct reference to the CC mapping service, set once at startup.
  ///
  /// This avoids going through [AudioEngine.ccMappingService] which is null
  /// during splash screen initialisation (assigned later in RackScreen).
  CcMappingService? ccMappingService;

  String? _currentProjectPath;
  String? get currentProjectPath => _currentProjectPath;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  /// Debounce timer for [autosave].  Rapid mutations (e.g. a continuous knob
  /// drag) reset this timer on every call; the actual write only happens once
  /// the stream of changes quiets down for [_autosaveDelay].
  Timer? _autosaveDebounce;

  /// How long to wait after the last change before flushing an autosave.
  static const Duration _autosaveDelay = Duration(milliseconds: 500);

  /// Loads the last autosave or initializes a default project if none exists.
  Future<void> loadOrInitDefault(
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    if (kIsWeb) {
      // No persistent filesystem on web — always start with defaults.
      debugPrint('ProjectService: web target — initializing defaults');
      rackState.initDefaults();
      ccMappingService?.clear();
      notifyListeners();
      return;
    }
    final docsDir = await getApplicationDocumentsDirectory();
    final autosavePath = '${docsDir.path}/autosave.gf';

    if (await File(autosavePath).exists()) {
      try {
        await _readGfFile(
            autosavePath, rackState, engine, transport, audioGraph,
            looperEngine);
        _currentProjectPath = autosavePath;
      } catch (e) {
        debugPrint('ProjectService: autosave load failed ($e) — using defaults');
        rackState.initDefaults();
        ccMappingService?.clear();
        // Create per-slot FluidSynth instances for the default keyboard slots
        // so that GFPA routing works correctly on Android from the start.
        await rackState.initAndroidKeyboardSlots();
      }
    } else {
      debugPrint('ProjectService: no autosave found — initializing defaults');
      rackState.initDefaults();
      ccMappingService?.clear();
      // Create per-slot FluidSynth instances for the default keyboard slots
      // so that GFPA routing works correctly on Android from the start.
      await rackState.initAndroidKeyboardSlots();
    }
    notifyListeners();
  }

  /// Schedules an autosave, debounced by [_autosaveDelay].
  ///
  /// Each call resets the debounce timer, so a burst of rapid mutations
  /// (e.g. continuous knob drag) results in exactly one disk write that
  /// captures the final state once the stream of changes quiets down.
  ///
  /// Without debouncing, concurrent writes all target the same `.tmp` file:
  /// the first rename succeeds and every subsequent rename fails with ENOENT
  /// because the temp file has already been moved away.
  void autosave(
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) {
    if (kIsWeb) return;  // No filesystem on web; project state is not persisted.

    // Cancel any previously scheduled write and start a fresh countdown.
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(_autosaveDelay, () {
      _performAutosave(rackState, engine, transport, audioGraph, looperEngine);
    });
  }

  /// Executes the actual autosave write, guarded against concurrent runs.
  ///
  /// [autosave] is the public entry point; this method performs the I/O.
  Future<void> _performAutosave(
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    // Skip if a manual saveProject is already in flight (rare but possible).
    if (_isSaving) return;

    _isSaving = true;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final autosavePath = '${docsDir.path}/autosave.gf';
      await _writeGfFile(
          autosavePath, rackState, engine, transport, audioGraph, looperEngine);
      _currentProjectPath = autosavePath;
    } catch (e) {
      // Log but do not rethrow — autosave failures are non-fatal.
      debugPrint('ProjectService: autosave failed: $e');
    } finally {
      _isSaving = false;
    }
  }

  /// Opens a project using a file picker.
  Future<String?> openProject(
    BuildContext context,
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    final path = await FilePickerService.pickFile(
      context: context,
      allowedExtensions: ['gf'],
    );

    if (path != null) {
      await loadProject(
          path, rackState, engine, transport, audioGraph, looperEngine);
      return path;
    }
    return null;
  }

  /// Saves the current project state to a new file using a file picker.
  ///
  /// On **web**, the plugin triggers a browser download (no path returned);
  /// we return the empty string so the UI can show success. On **Android**
  /// and **iOS**, the plugin requires [bytes]; we pass the project JSON so
  /// the plugin writes the file and returns the path. On **desktop**, passing
  /// [bytes] lets the plugin write the chosen path; we then set
  /// [_currentProjectPath] and return it.
  Future<String?> saveProjectAs(
    BuildContext context,
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    final jsonStr = _projectDataToJsonString(
        rackState, engine, transport, audioGraph, looperEngine);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    final result = await FilePickerService.saveFile(
      context: context,
      dialogTitle: 'Save Project As',
      fileName: 'project.gf',
      allowedExtensions: ['gf'],
      bytes: bytes,
    );

    if (result != null) {
      final path = result.endsWith('.gf') ? result : '$result.gf';
      _currentProjectPath = path;
      notifyListeners();
      return path;
    }

    // Web: saveFile triggers a download and returns null; treat as success.
    if (kIsWeb) return '';
    return null;
  }

  /// Saves the project to the given path.
  Future<void> saveProject(
    String path,
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    _isSaving = true;
    notifyListeners();
    try {
      await _writeGfFile(
          path, rackState, engine, transport, audioGraph, looperEngine);
      _currentProjectPath = path;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Loads a project from the given path.
  Future<void> loadProject(
    String path,
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    await _readGfFile(
        path, rackState, engine, transport, audioGraph, looperEngine);
    _currentProjectPath = path;
    notifyListeners();
  }

  // ─── Internal I/O ────────────────────────────────────────────────────────

  /// Builds the project document as a JSON string (no file I/O).
  ///
  /// Used by [saveProjectAs] to pass bytes to the file picker on web and
  /// mobile, and by [_writeGfFile] for desktop autosave/save.
  String _projectDataToJsonString(
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) {
    final data = {
      'version': _formatVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'transport': {
        'bpm': transport.bpm,
        'timeSigNumerator': transport.timeSigNumerator,
        'timeSigDenominator': transport.timeSigDenominator,
        'swing': transport.swing,
        'metronomeEnabled': transport.metronomeEnabled,
      },
      'audioGraph': audioGraph.toJson(),
      'looperSessions': looperEngine.toJson(),
      'plugins': rackState.toJson(),
      'ccMappings': ccMappingService?.toJson() ?? [],
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  Future<void> _writeGfFile(
    String path,
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    final jsonStr = _projectDataToJsonString(
        rackState, engine, transport, audioGraph, looperEngine);

    final file = File(path);
    final tmpPath = '$path.tmp';
    final tmpFile = File(tmpPath);

    try {
      await tmpFile.writeAsString(jsonStr, flush: true);

      if (await file.exists()) {
        await file.delete();
      }

      await tmpFile.rename(path);
      debugPrint('ProjectService: saved to $path');
    } catch (e) {
      debugPrint('ProjectService: Failed to save project: $e');
      if (await tmpFile.exists()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _readGfFile(
    String path,
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    final content = await File(path).readAsString();
    if (content.isEmpty) throw FormatException('Empty project file');

    final Map<String, dynamic> data =
        jsonDecode(content) as Map<String, dynamic>;

    // Migrate data if necessary.
    ProjectMigrationService.migrate(data);

    // Restore transport if present.
    final transportJson = data['transport'] as Map<String, dynamic>?;
    if (transportJson != null) {
      transport.bpm = (transportJson['bpm'] as num?)?.toDouble() ?? 120.0;
      transport.timeSigNumerator =
          (transportJson['timeSigNumerator'] as num?)?.toInt() ?? 4;
      transport.timeSigDenominator =
          (transportJson['timeSigDenominator'] as num?)?.toInt() ?? 4;
      transport.swing = (transportJson['swing'] as num?)?.toDouble() ?? 0.0;
      transport.metronomeEnabled =
          (transportJson['metronomeEnabled'] as bool?) ?? false;
    }

    // Restore rack plugins first — slot IDs must exist before the audio graph
    // can reference them by ID.
    final pluginsJson = data['plugins'] as List<dynamic>? ?? [];
    rackState.loadFromJson(pluginsJson);

    // On Android, provision a dedicated FluidSynth instance per GF Keyboard
    // slot so GFPA effects on one keyboard cannot bleed into another.
    await rackState.initAndroidKeyboardSlots();

    // Restore the MIDI/Audio graph connections.
    // Older .gf files with 'audioGraph: {}' produce an empty connection list,
    // which is correct behaviour (no cables).
    final audioGraphJson =
        data['audioGraph'] as Map<String, dynamic>? ?? const {};
    audioGraph.loadFromJson(audioGraphJson);

    // Restore looper sessions (Phase 7). Older files without this key
    // produce an empty session map — correct for fresh projects.
    final looperJson =
        data['looperSessions'] as Map<String, dynamic>? ?? const {};
    looperEngine.loadFromJson(looperJson);

    // Restore CC mappings (Phase A of per-project CC mappings).
    // If the key is absent (older .gf files), migrate from SharedPreferences.
    final ccMappingsJson = data['ccMappings'] as List<dynamic>?;
    final ccService = ccMappingService;
    if (ccService != null) {
      if (ccMappingsJson != null) {
        ccService.loadFromJson(ccMappingsJson);
      } else {
        // Old project without ccMappings — migrate from SharedPreferences.
        final migrated = await ccService.migrateFromPrefs();
        if (migrated.isNotEmpty) {
          ccService.loadFromJson(
            migrated.map((m) => m.toJson()).toList(),
          );
          debugPrint(
            'ProjectService: migrated ${migrated.length} CC mapping(s) '
            'from SharedPreferences',
          );
          // The next autosave will persist them into the .gf file.
          // Legacy prefs are cleaned up after the first successful save.
        } else {
          ccService.clear();
        }
      }
    }

    debugPrint(
      'ProjectService: loaded from $path '
      '(${pluginsJson.length} slots, '
      '${audioGraph.connections.length} cables, '
      '${ccMappingsJson?.length ?? 0} CC mappings)',
    );
  }
}
