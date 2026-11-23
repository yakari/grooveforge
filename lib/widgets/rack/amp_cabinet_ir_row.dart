import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cabinet_ir.dart';
import '../../services/file_picker_service.dart';
import '../../services/rack_state.dart';

/// Plugin id of the guitar Amp, whose panel shows this row.
const kAmpPluginId = 'com.grooveforge.amp';

/// The Amp panel's impulse-response row: which cabinet IR is loaded, a
/// button to remove it, and one to load another from a `.wav` file.
///
/// Loading an IR also switches the Cabinet selector to "IR", so the player
/// hears the new cabinet straight away. The IR is saved inside the project.
///
/// Hidden on the web, where the Amp's DSP does not run.
class AmpCabinetIrRow extends StatefulWidget {
  /// Creates the row for the Amp in rack slot [slotId].
  const AmpCabinetIrRow({super.key, required this.slotId});

  /// The Amp's rack slot.
  final String slotId;

  @override
  State<AmpCabinetIrRow> createState() => _AmpCabinetIrRowState();
}

class _AmpCabinetIrRowState extends State<AmpCabinetIrRow> {
  /// True while a file is being read and prepared, to block a second tap.
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final name = context.watch<RackState>().cabinetIrName(widget.slotId);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
      child: Row(
        children: [
          Icon(Icons.graphic_eq, size: 16, color: theme.hintColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name == null ? l10n.ampIrNone : l10n.ampIrLoaded(name),
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          if (name != null)
            IconButton(
              tooltip: l10n.ampIrRemove,
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              onPressed: _loading ? null : _remove,
            ),
          TextButton.icon(
            onPressed: _loading ? null : _pickAndLoad,
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(l10n.ampIrLoad),
          ),
        ],
      ),
    );
  }

  /// Asks for a `.wav`, decodes it and hands it to the rack.
  Future<void> _pickAndLoad() async {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();
    final path = await FilePickerService.pickFile(
      context: context,
      allowedExtensions: const ['wav'],
      dialogTitle: l10n.ampIrPickTitle,
    );
    if (path == null || !mounted) return;
    setState(() => _loading = true);
    final message = await _load(rack, path, l10n);
    if (!mounted) return;
    setState(() => _loading = false);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Drops the IR: the cabinet goes back to the built-in 2x12.
  void _remove() => context.read<RackState>().removeCabinetIr(widget.slotId);

  /// Reads and loads the IR at [path]. Returns an error message for the
  /// player, or null on success.
  Future<String?> _load(RackState rack, String path, AppLocalizations l10n) async {
    try {
      final bytes = await File(path).readAsBytes();
      final ir = CabinetIr.fromWav(bytes, _fileName(path));
      return rack.loadCabinetIr(widget.slotId, ir) ? null : l10n.ampIrRejected;
    } on CabinetIrException catch (e) {
      return _errorText(l10n, e.error);
    } on FileSystemException {
      return l10n.ampIrUnreadable;
    }
  }

  /// The file name without its folder, whichever separator the platform uses.
  static String _fileName(String path) => path.split(RegExp(r'[/\\]')).last;

  static String _errorText(AppLocalizations l10n, CabinetIrError error) =>
      switch (error) {
        CabinetIrError.notWav => l10n.ampIrNotWav,
        CabinetIrError.unsupportedFormat => l10n.ampIrUnsupported,
        CabinetIrError.noAudio || CabinetIrError.silent => l10n.ampIrEmpty,
      };
}
