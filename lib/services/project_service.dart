import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'audio_engine.dart';
import 'audio_graph.dart';
import 'looper_engine.dart';
import 'project_migration_service.dart';
import 'rack_state.dart';
import 'transport_engine.dart';

/// Manages loading and saving current project state to a .gf file.
class ProjectService extends ChangeNotifier {
  static const String _formatVersion = '2.0.0';
  
  String? _currentProjectPath;
  String? get currentProjectPath => _currentProjectPath;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  /// Loads the last autosave or initializes a default project if none exists.
  Future<void> loadOrInitDefault(
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
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
      }
    } else {
      debugPrint('ProjectService: no autosave found — initializing defaults');
      rackState.initDefaults();
    }
    notifyListeners();
  }

  /// Triggers an autosave.
  Future<void> autosave(
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final autosavePath = '${docsDir.path}/autosave.gf';
    await _writeGfFile(
        autosavePath, rackState, engine, transport, audioGraph, looperEngine);
    _currentProjectPath = autosavePath;
  }

  /// Opens a project using a file picker.
  Future<String?> openProject(
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      await loadProject(
          path, rackState, engine, transport, audioGraph, looperEngine);
      return path;
    }
    return null;
  }

  /// Saves the current project state to a new file using a file picker.
  Future<String?> saveProjectAs(
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Project As',
      fileName: 'project.gf',
      type: FileType.custom,
      allowedExtensions: ['gf'],
    );

    if (result != null) {
      // Ensure .gf extension.
      final path = result.endsWith('.gf') ? result : '$result.gf';
      await saveProject(
          path, rackState, engine, transport, audioGraph, looperEngine);
      return path;
    }
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

  Future<void> _writeGfFile(
    String path,
    RackState rackState,
    AudioEngine engine,
    TransportEngine transport,
    AudioGraph audioGraph,
    LooperEngine looperEngine,
  ) async {
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
      // MIDI and Audio graph connections (Phase 5).
      // Data (chord/scale) connections are stored within each plugin's state.
      'audioGraph': audioGraph.toJson(),
      // Looper sessions: per-slot recorded MIDI track data (Phase 7).
      'looperSessions': looperEngine.toJson(),
      'plugins': rackState.toJson(),
    };
    
    final file = File(path);
    final tmpPath = '$path.tmp';
    final tmpFile = File(tmpPath);
    
    try {
      await tmpFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
        flush: true,
      );
      
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

    debugPrint(
      'ProjectService: loaded from $path '
      '(${pluginsJson.length} slots, '
      '${audioGraph.connections.length} cables)',
    );
  }
}
