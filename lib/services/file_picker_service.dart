import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Result of a fallback file-picker attempt.
///
/// Distinguishes three outcomes so the fallback chain knows when to stop:
///   - [selected] — the user chose a path.
///   - [cancelled] — the dialog opened but the user dismissed it.
///   - [unavailable] — the backend could not be launched at all.
enum _PickOutcome { selected, cancelled, unavailable }

/// Bundles a [_PickOutcome] with the optional file path.
class _PickResult {
  final _PickOutcome outcome;
  final String? path;
  const _PickResult.selected(String this.path) : outcome = _PickOutcome.selected;
  const _PickResult.cancelled() : outcome = _PickOutcome.cancelled, path = null;
  const _PickResult.unavailable() : outcome = _PickOutcome.unavailable, path = null;
}

/// A cross-platform file picker facade with a graceful fallback chain for
/// Linux environments where the XDG Desktop Portal is unavailable (e.g.
/// devcontainers, headless servers, or minimal desktop setups).
///
/// Fallback chain on Linux:
///   1. **XDG Desktop Portal** (via `file_picker` package) — the standard path.
///   2. **zenity** CLI — lightweight GTK dialog that works with X11/Wayland
///      forwarding but does not require a running D-Bus session bus.
///   3. **In-app text field** — last resort when no display server is reachable.
///      The user types or pastes a file path directly.
///
/// Each step only falls through to the next if the backend is **unavailable**.
/// If the user explicitly cancels a dialog, `null` is returned immediately
/// without showing further fallbacks.
///
/// On all other platforms (Android, iOS, macOS, Windows, web), the standard
/// `file_picker` package is used directly.
class FilePickerService {
  FilePickerService._();

  // ------------------------------------------------------------------
  // Pick one or more files
  // ------------------------------------------------------------------

  /// Opens a file-open dialog filtered by [allowedExtensions].
  ///
  /// Returns the selected file path, or `null` if the user cancelled.
  /// [context] is required for the in-app fallback dialog on Linux.
  static Future<String?> pickFile({
    required BuildContext context,
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    // Non-Linux platforms: use file_picker directly, no fallback needed.
    if (kIsWeb || !Platform.isLinux) {
      return _pickViaFilePicker(
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      );
    }

    // Linux fallback chain: portal → zenity → manual path input.
    // Each step only falls through on "unavailable"; a user cancel stops
    // the chain immediately.
    return _runFallbackChain(
      context: context,
      portalPick: () => _portalPickFile(
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      ),
      zenityPick: () => _zenityPick(
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      ),
      dialogPick: () => _pickViaDialog(
        context,
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Pick a directory
  // ------------------------------------------------------------------

  /// Opens a directory-selection dialog.
  ///
  /// Returns the selected directory path, or `null` if the user cancelled.
  static Future<String?> pickDirectory({
    required BuildContext context,
    String? dialogTitle,
  }) async {
    if (kIsWeb || !Platform.isLinux) {
      return FilePicker.platform.getDirectoryPath(dialogTitle: dialogTitle);
    }

    return _runFallbackChain(
      context: context,
      portalPick: () => _portalPickDirectory(dialogTitle: dialogTitle),
      zenityPick: () => _zenityPick(
        dialogTitle: dialogTitle,
        directory: true,
      ),
      dialogPick: () => _pickViaDialog(
        context,
        dialogTitle: dialogTitle,
        directory: true,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Save file
  // ------------------------------------------------------------------

  /// Opens a save-file dialog.
  ///
  /// Returns the chosen save path, or `null` if the user cancelled.
  /// On platforms where `file_picker` handles writing (web), [bytes] is
  /// forwarded so the data is written by the plugin itself.
  static Future<String?> saveFile({
    required BuildContext context,
    String? dialogTitle,
    String? fileName,
    List<String>? allowedExtensions,
    Uint8List? bytes,
  }) async {
    if (kIsWeb || !Platform.isLinux) {
      return FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
      );
    }

    return _runFallbackChain(
      context: context,
      portalPick: () => _portalSaveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
      ),
      zenityPick: () => _zenityPick(
        dialogTitle: dialogTitle,
        save: true,
        fileName: fileName,
      ),
      dialogPick: () => _pickViaDialog(
        context,
        dialogTitle: dialogTitle,
        save: true,
        fileName: fileName,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Fallback chain runner
  // ------------------------------------------------------------------

  /// Executes the portal → zenity → in-app dialog chain.
  ///
  /// Stops as soon as a backend returns [_PickOutcome.selected] or
  /// [_PickOutcome.cancelled].  Only [_PickOutcome.unavailable] advances
  /// to the next fallback.
  static Future<String?> _runFallbackChain({
    required BuildContext context,
    required Future<_PickResult> Function() portalPick,
    required Future<_PickResult> Function() zenityPick,
    required Future<String?> Function() dialogPick,
  }) async {
    // 1. XDG Desktop Portal.
    final portalResult = await portalPick();
    if (portalResult.outcome != _PickOutcome.unavailable) {
      return portalResult.path;
    }

    // 2. zenity CLI.
    final zenityResult = await zenityPick();
    if (zenityResult.outcome != _PickOutcome.unavailable) {
      return zenityResult.path;
    }

    // 3. In-app text input (last resort).
    if (!context.mounted) return null;
    return dialogPick();
  }

  // ------------------------------------------------------------------
  // Portal backends (return _PickResult)
  // ------------------------------------------------------------------

  /// Standard file_picker path (XDG portal on Linux).
  static Future<String?> _pickViaFilePicker({
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
    return result?.files.single.path;
  }

  /// Wraps [_pickViaFilePicker] into a [_PickResult], catching D-Bus /
  /// portal errors as [_PickOutcome.unavailable].
  static Future<_PickResult> _portalPickFile({
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    try {
      final path = await _pickViaFilePicker(
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      );
      return path != null
          ? _PickResult.selected(path)
          : const _PickResult.cancelled();
    } on SocketException catch (_) {
      return const _PickResult.unavailable();
    } catch (e) {
      debugPrint('FilePickerService: portal pick failed ($e)');
      return const _PickResult.unavailable();
    }
  }

  /// Portal-based directory picker wrapped as [_PickResult].
  static Future<_PickResult> _portalPickDirectory({
    String? dialogTitle,
  }) async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: dialogTitle,
      );
      return path != null
          ? _PickResult.selected(path)
          : const _PickResult.cancelled();
    } on SocketException catch (_) {
      return const _PickResult.unavailable();
    } catch (e) {
      debugPrint('FilePickerService: portal directory pick failed ($e)');
      return const _PickResult.unavailable();
    }
  }

  /// Portal-based save dialog wrapped as [_PickResult].
  static Future<_PickResult> _portalSaveFile({
    String? dialogTitle,
    String? fileName,
    List<String>? allowedExtensions,
    Uint8List? bytes,
  }) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: allowedExtensions != null ? FileType.custom : FileType.any,
        allowedExtensions: allowedExtensions,
        bytes: bytes,
      );
      return path != null
          ? _PickResult.selected(path)
          : const _PickResult.cancelled();
    } on SocketException catch (_) {
      return const _PickResult.unavailable();
    } catch (e) {
      debugPrint('FilePickerService: portal save failed ($e)');
      return const _PickResult.unavailable();
    }
  }

  // ------------------------------------------------------------------
  // Zenity backend (return _PickResult)
  // ------------------------------------------------------------------

  /// Invokes zenity as an external process.
  ///
  /// Returns [_PickOutcome.selected] with the path on success,
  /// [_PickOutcome.cancelled] when the user dismissed the dialog (exit
  /// code 1), or [_PickOutcome.unavailable] when zenity is not installed
  /// or the display is unreachable.
  static Future<_PickResult> _zenityPick({
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? fileName,
    bool directory = false,
    bool save = false,
  }) async {
    try {
      final args = <String>['--file-selection'];
      if (dialogTitle != null) args.add('--title=$dialogTitle');
      if (directory) args.add('--directory');
      if (save) {
        args.add('--save');
        if (fileName != null) args.add('--filename=$fileName');
      }
      if (allowedExtensions != null && allowedExtensions.isNotEmpty) {
        // zenity --file-filter="SoundFont | *.sf2 *.SF2"
        final patterns = allowedExtensions.map((e) => '*.$e').join(' ');
        args.add('--file-filter=$patterns');
      }
      final result = await Process.run('zenity', args);

      // Exit code 0 = user selected a file.
      if (result.exitCode == 0) {
        final path = (result.stdout as String).trim();
        if (path.isNotEmpty) return _PickResult.selected(path);
      }

      // Exit code 1 = user pressed Cancel.  Exit code 5 = timeout / error
      // but the dialog was shown, so still treat as an explicit dismiss.
      if (result.exitCode == 1 || result.exitCode == 5) {
        return const _PickResult.cancelled();
      }

      // Any other exit code (e.g. zenity crashed) — treat as unavailable.
      return const _PickResult.unavailable();
    } catch (_) {
      // zenity not installed or Process.run failed — truly unavailable.
      return const _PickResult.unavailable();
    }
  }

  // ------------------------------------------------------------------
  // In-app fallback dialog
  // ------------------------------------------------------------------

  /// Shows a simple in-app dialog where the user types or pastes a path.
  static Future<String?> _pickViaDialog(
    BuildContext context, {
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? fileName,
    bool directory = false,
    bool save = false,
  }) async {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: fileName ?? '');
    final title = dialogTitle ??
        (directory ? loc.selectDirectory : loc.selectFile);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (allowedExtensions != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${loc.filePickerAllowedTypes}: ${allowedExtensions.join(', ')}',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: directory ? '/path/to/directory' : '/path/to/file',
              ),
              onSubmitted: (val) => Navigator.pop(ctx, val),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(loc.confirmButton),
          ),
        ],
      ),
    );

    if (result == null || result.trim().isEmpty) return null;
    return result.trim();
  }
}
