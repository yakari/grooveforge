import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/gfpa_plugin_instance.dart';
import 'rack_state.dart';
import 'audio_engine.dart';

/// Handles saving and loading GrooveForge project files (.gf format, JSON).
///
/// A .gf file contains:
/// - The full ordered rack plugin list with per-slot state
/// - Global Jam Mode settings (enabled, scale type, lock mode)
///
/// An autosave file (`autosave.gf`) is written to the app's documents
/// directory after every rack mutation so that state is always restored
/// on next launch without any user action.
class ProjectService {
  static const _autosaveFilename = 'autosave.gf';
  static const _fileExtension = 'gf';
  static const _formatVersion = '2.0.0';

  // ─── Autosave ─────────────────────────────────────────────────────────────

  Future<String> _autosavePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, _autosaveFilename);
  }

  Future<bool> hasAutosave() async {
    try {
      return File(await _autosavePath()).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Silently serialises [rackState] + [engine] global jam state to the
  /// autosave file. Errors are swallowed and printed as debug output.
  Future<void> autosave(RackState rackState, AudioEngine engine) async {
    try {
      // Snapshot GFPA vocoder params before saving.
      for (final plugin in rackState.plugins) {
        if (plugin is GFpaPluginInstance &&
            plugin.pluginId == 'com.grooveforge.vocoder') {
          rackState.snapshotGfpaVocoderParams(plugin.id);
        }
      }
      final path = await _autosavePath();
      await _writeGfFile(path, rackState, engine);
    } catch (e) {
      debugPrint('ProjectService: autosave failed — $e');
    }
  }

  /// Loads the autosave file into [rackState], or calls [rackState.initDefaults]
  /// if no autosave exists (first launch).
  Future<void> loadOrInitDefault(
    RackState rackState,
    AudioEngine engine,
  ) async {
    if (await hasAutosave()) {
      try {
        final path = await _autosavePath();
        await _readGfFile(path, rackState, engine);
        return;
      } catch (e) {
        debugPrint('ProjectService: autosave load failed ($e) — using defaults');
      }
    }
    rackState.initDefaults();
  }

  // ─── Explicit Save ────────────────────────────────────────────────────────

  /// Opens a save-file dialog and writes a .gf project file.
  /// Returns the chosen path, or null if the user cancelled.
  Future<String?> saveProjectAs(
    RackState rackState,
    AudioEngine engine,
  ) async {
    // Snapshot GFPA vocoder params before saving.
    for (final plugin in rackState.plugins) {
      if (plugin is GFpaPluginInstance &&
          plugin.pluginId == 'com.grooveforge.vocoder') {
        rackState.snapshotGfpaVocoderParams(plugin.id);
      }
    }

    // On mobile, default to the documents directory.
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(dir.path, 'project.$_fileExtension');
      await _writeGfFile(path, rackState, engine);
      return path;
    }

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save GrooveForge Project',
      fileName: 'project.$_fileExtension',
      type: FileType.custom,
      allowedExtensions: [_fileExtension],
    );

    if (result == null) return null;

    final path = result.endsWith('.$_fileExtension')
        ? result
        : '$result.$_fileExtension';
    await _writeGfFile(path, rackState, engine);
    return path;
  }

  // ─── Explicit Open ────────────────────────────────────────────────────────

  /// Opens a file-picker dialog and loads the chosen .gf project.
  /// Returns the path of the loaded file, or null if cancelled / error.
  Future<String?> openProject(
    RackState rackState,
    AudioEngine engine,
  ) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Open GrooveForge Project',
        type: FileType.custom,
        allowedExtensions: [_fileExtension],
        allowMultiple: false,
      );
    } catch (e) {
      debugPrint('ProjectService: file picker error — $e');
      return null;
    }

    final path = result?.files.single.path;
    if (path == null) return null;

    await _readGfFile(path, rackState, engine);
    // Persist the freshly loaded state as the autosave too.
    await autosave(rackState, engine);
    return path;
  }

  // ─── Internal I/O ────────────────────────────────────────────────────────

  Future<void> _writeGfFile(
    String path,
    RackState rackState,
    AudioEngine engine,
  ) async {
    final data = {
      'version': _formatVersion,
      'savedAt': DateTime.now().toIso8601String(),
      'plugins': rackState.toJson(),
    };
    final file = File(path);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
    debugPrint('ProjectService: saved to $path');
  }

  Future<void> _readGfFile(
    String path,
    RackState rackState,
    AudioEngine engine,
  ) async {
    final content = await File(path).readAsString();
    final Map<String, dynamic> data = jsonDecode(content) as Map<String, dynamic>;

    // Restore rack plugins.
    final pluginsJson = data['plugins'] as List<dynamic>? ?? [];
    rackState.loadFromJson(pluginsJson);

    debugPrint('ProjectService: loaded from $path (${pluginsJson.length} slots)');
  }
}
