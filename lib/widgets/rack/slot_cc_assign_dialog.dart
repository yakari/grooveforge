import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/cc_mapping_service.dart';
import '../../services/cc_param_registry.dart';
import '../../services/rack_state.dart';

/// A dialog that lists every CC-controllable parameter of a rack slot and lets
/// the user learn-assign or remove a hardware CC for each one.
///
/// This is the **primary workflow** for CC assignment — the user sees a "CC"
/// button on each rack slot card, taps it, and this dialog appears with all
/// the slot's parameters listed. For each parameter, the user can:
/// - Tap "Learn" → move a hardware knob → CC is assigned.
/// - Tap the delete icon on an existing assignment to remove it.
///
/// The dialog reads parameters from [CcParamRegistry] and creates/removes
/// [SlotParamTarget] mappings in [CcMappingService].
class SlotCcAssignDialog extends StatefulWidget {
  /// The rack slot ID (e.g. "slot-2").
  final String slotId;

  /// The plugin ID for registry lookup (e.g. "com.grooveforge.reverb").
  /// Use "_gf_keyboard" for GF Keyboard slots.
  final String pluginId;

  /// Human-readable name shown in the dialog title.
  final String slotDisplayName;

  const SlotCcAssignDialog({
    super.key,
    required this.slotId,
    required this.pluginId,
    required this.slotDisplayName,
  });

  @override
  State<SlotCcAssignDialog> createState() => _SlotCcAssignDialogState();
}

class _SlotCcAssignDialogState extends State<SlotCcAssignDialog> {
  late final CcMappingService _ccService;
  late final List<CcParamEntry> _params;

  /// The param key currently in learn mode, or null.
  String? _learningParamKey;

  /// Listener for CC learn mode.
  void Function()? _learnListener;

  @override
  void initState() {
    super.initState();
    _ccService = context.read<CcMappingService>();
    _params = CcParamRegistry.forPluginId(widget.pluginId) ?? [];
  }

  @override
  void dispose() {
    _stopLearn();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text('CC Assign \u2014 ${widget.slotDisplayName}'),
      content: SizedBox(
        width: 360,
        child: ValueListenableBuilder<List<CcMapping>>(
          valueListenable: _ccService.mappingsNotifier,
          builder: (context, mappings, _) {
            if (_params.isEmpty) {
              return const Text('No CC-controllable parameters for this slot.',
                  style: TextStyle(color: Colors.grey));
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final param in _params)
                  _buildParamRow(param, mappings, l10n),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
      ],
    );
  }

  /// One row per parameter: name, current CC assignment (if any), learn/remove.
  Widget _buildParamRow(
    CcParamEntry param,
    List<CcMapping> allMappings,
    AppLocalizations l10n,
  ) {
    // Find any existing mapping for this slot + paramKey.
    final existing = _findMapping(allMappings, param.paramKey);
    final isLearning = _learningParamKey == param.paramKey;
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(param.displayName,
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(param.defaultMode.name,
          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      trailing: isLearning
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('Move a CC knob\u2026',
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.primary)),
              ],
            )
          : existing != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      label: Text('CC ${existing.incomingCc}',
                          style: const TextStyle(fontSize: 11)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => _removeMapping(existing),
                    ),
                    const SizedBox(width: 4),
                    _learnButton(param, l10n),
                  ],
                )
              : _learnButton(param, l10n),
      onTap: isLearning ? _stopLearn : () => _startLearn(param.paramKey),
    );
  }

  Widget _learnButton(CcParamEntry param, AppLocalizations l10n) {
    return TextButton.icon(
      onPressed: () => _startLearn(param.paramKey),
      icon: const Icon(Icons.sensors, size: 16),
      label: const Text('Learn', style: TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  // ── CC learn mode ──────────────────────────────────────────────────────

  void _startLearn(String paramKey) {
    _stopLearn();
    setState(() => _learningParamKey = paramKey);
    _learnListener = () {
      final event = _ccService.lastEventNotifier.value;
      if (event == null || event.type != 'CC') return;
      _assignCc(paramKey, event.data1);
      _stopLearn();
    };
    _ccService.lastEventNotifier.addListener(_learnListener!);
  }

  void _stopLearn() {
    if (_learnListener != null) {
      _ccService.lastEventNotifier.removeListener(_learnListener!);
      _learnListener = null;
    }
    if (mounted) setState(() => _learningParamKey = null);
  }

  // ── Mapping CRUD ───────────────────────────────────────────────────────

  void _assignCc(String paramKey, int ccNumber) {
    // Remove any existing mapping for this slot + paramKey.
    final existing = _findMapping(
        _ccService.mappingsNotifier.value, paramKey);
    if (existing != null) _ccService.removeMapping(existing);

    // Find the mode from the registry.
    final entry = CcParamRegistry.findParam(widget.pluginId, paramKey);
    final mode = entry?.defaultMode ?? CcParamMode.absolute;

    _ccService.addMapping(CcMapping(
      incomingCc: ccNumber,
      target: SlotParamTarget(
        slotId: widget.slotId,
        paramKey: paramKey,
        mode: mode,
      ),
    ));
    context.read<RackState>().markDirty();
  }

  void _removeMapping(CcMapping mapping) {
    _ccService.removeMapping(mapping);
    context.read<RackState>().markDirty();
  }

  /// Finds the first mapping that targets this slot + paramKey.
  CcMapping? _findMapping(List<CcMapping> mappings, String paramKey) {
    for (final m in mappings) {
      final t = m.target;
      if (t is SlotParamTarget &&
          t.slotId == widget.slotId &&
          t.paramKey == paramKey) {
        return m;
      }
    }
    return null;
  }
}
