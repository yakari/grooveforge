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

  /// The param currently in learn mode, or null.
  ///
  /// A direct-mode parameter is learned per *value* — "Rast on this pad" and
  /// "Yaman on that one" are two independent mappings — so the identity of
  /// what is being learned is the pair, not the param alone.
  String? _learningParamKey;
  String? _learningDirectValue;

  bool _isLearning(String paramKey, [String? directValue]) =>
      _learningParamKey == paramKey && _learningDirectValue == directValue;

  /// Listener for CC learn mode.
  void Function()? _learnListener;

  @override
  void initState() {
    super.initState();
    _ccService = context.read<CcMappingService>();
    _params = CcParamRegistry.forPluginId(widget.pluginId) ?? const [];
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
        // Clamped rather than fixed: the list grows with every scale bound to
        // a pad, and 360 dp is wider than a phone dialog can afford.
        width: (MediaQuery.of(context).size.width - 96).clamp(240.0, 380.0),
        child: ValueListenableBuilder<List<CcMapping>>(
          valueListenable: _ccService.mappingsNotifier,
          builder: (context, mappings, _) {
            if (_params.isEmpty) {
              return const Text('No CC-controllable parameters for this slot.',
                  style: TextStyle(color: Colors.grey));
            }
            // Height-capped and scrollable for the same reason.
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(child: _paramList(mappings, l10n)),
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

  Widget _paramList(List<CcMapping> mappings, AppLocalizations l10n) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final param in _params)
                  if (param.defaultMode == CcParamMode.direct)
                    _buildDirectParamGroup(param, mappings, l10n)
                  else
                    _buildParamRow(param, mappings, l10n),
              ],
            );
  }

  /// A direct-mode parameter, rendered as one row per assigned value.
  ///
  /// "Next scale" is unusable with a catalogue this size — reaching the
  /// fortieth scale means thirty-nine taps and no way back. What a pad bank
  /// wants is one pad per scale, each jumping straight to it, and that means
  /// the assignment is per *value*: several mappings for the same parameter,
  /// each on its own CC.
  Widget _buildDirectParamGroup(
    CcParamEntry param,
    List<CcMapping> allMappings,
    AppLocalizations l10n,
  ) {
    final choices = param.directChoices?.call() ?? const <CcDirectChoice>[];
    final assigned = _findDirectMappings(allMappings, param.paramKey);
    final theme = Theme.of(context);

    String labelFor(String value) {
      for (final c in choices) {
        if (c.value == value) return c.label;
      }
      // The choice is gone — a deleted custom scale. Showing the raw id tells
      // the player which mapping to repair; showing nothing would not.
      return value;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 2),
          child: Text(
            param.displayName,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        if (assigned.isEmpty && _learningParamKey != param.paramKey)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              l10n.ccAssignNoValues,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ),
        for (final mapping in assigned)
          _directValueRow(
            param,
            mapping,
            labelFor((mapping.target as SlotParamTarget).directValue ?? ''),
            l10n,
          ),
        // Learning a value that has no mapping yet.
        if (_learningParamKey == param.paramKey &&
            _learningDirectValue != null &&
            !assigned.any((m) =>
                (m.target as SlotParamTarget).directValue ==
                _learningDirectValue))
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(labelFor(_learningDirectValue!),
                style: const TextStyle(fontSize: 12)),
            trailing: _learnIndicator(theme),
            onTap: _stopLearn,
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: _AddValueButton(
            label: l10n.ccAssignAddValue,
            choices: choices,
            alreadyAssigned: {
              for (final m in assigned)
                (m.target as SlotParamTarget).directValue,
            },
            onPick: (value) => _startLearn(param.paramKey, value),
          ),
        ),
      ],
    );
  }

  /// One assigned value: its label, its CC chip, and a re-learn button.
  Widget _directValueRow(
    CcParamEntry param,
    CcMapping mapping,
    String label,
    AppLocalizations l10n,
  ) {
    final value = (mapping.target as SlotParamTarget).directValue;
    final learning = _isLearning(param.paramKey, value);
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(label, style: const TextStyle(fontSize: 12)),
      trailing: learning
          ? _learnIndicator(theme)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Chip(
                  label: Text('CC ${mapping.incomingCc}',
                      style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeMapping(mapping),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _startLearn(param.paramKey, value),
                  icon: const Icon(Icons.sensors, size: 16),
                  label: const Text('Learn', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
      onTap: learning ? _stopLearn : () => _startLearn(param.paramKey, value),
    );
  }

  Widget _learnIndicator(ThemeData theme) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Move a CC knob\u2026',
              style:
                  TextStyle(fontSize: 11, color: theme.colorScheme.primary)),
        ],
      );

  /// Every mapping this slot has for a direct-mode [paramKey], in CC order.
  List<CcMapping> _findDirectMappings(
    List<CcMapping> mappings,
    String paramKey,
  ) {
    final out = mappings.where((m) {
      final t = m.target;
      return t is SlotParamTarget &&
          t.slotId == widget.slotId &&
          t.paramKey == paramKey &&
          t.directValue != null;
    }).toList()
      ..sort((a, b) => a.incomingCc.compareTo(b.incomingCc));
    return out;
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

  void _startLearn(String paramKey, [String? directValue]) {
    _stopLearn();
    setState(() {
      _learningParamKey = paramKey;
      _learningDirectValue = directValue;
    });
    _learnListener = () {
      final event = _ccService.lastEventNotifier.value;
      if (event == null || event.type != 'CC') return;
      _assignCc(paramKey, event.data1, directValue: directValue);
      _stopLearn();
    };
    _ccService.lastEventNotifier.addListener(_learnListener!);
  }

  void _stopLearn() {
    if (_learnListener != null) {
      _ccService.lastEventNotifier.removeListener(_learnListener!);
      _learnListener = null;
    }
    if (mounted) {
      setState(() {
        _learningParamKey = null;
        _learningDirectValue = null;
      });
    }
  }

  // ── Mapping CRUD ───────────────────────────────────────────────────────

  void _assignCc(String paramKey, int ccNumber, {String? directValue}) {
    // Replace only the mapping being re-learned. For a direct parameter that
    // means the one bound to this same value — rebinding Rast to another pad
    // must leave the pad holding Yaman alone.
    final existing = directValue == null
        ? _findMapping(_ccService.mappingsNotifier.value, paramKey)
        : _findDirectMappings(_ccService.mappingsNotifier.value, paramKey)
            .where((m) =>
                (m.target as SlotParamTarget).directValue == directValue)
            .firstOrNull;
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
        directValue: directValue,
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

/// Picks which value to bind next — the scale a pad should recall.
///
/// Values already on a pad are struck through rather than hidden, so the list
/// stays a stable map of the catalogue instead of shifting under the finger
/// as pads get assigned.
class _AddValueButton extends StatelessWidget {
  const _AddValueButton({
    required this.label,
    required this.choices,
    required this.alreadyAssigned,
    required this.onPick,
  });

  final String label;
  final List<CcDirectChoice> choices;
  final Set<String?> alreadyAssigned;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '',
      constraints: const BoxConstraints(maxHeight: 420, minWidth: 220),
      itemBuilder: (context) => [
        for (final choice in choices)
          PopupMenuItem(
            value: choice.value,
            height: 34,
            child: Text(
              choice.label,
              style: TextStyle(
                fontSize: 12,
                color: alreadyAssigned.contains(choice.value)
                    ? Colors.grey
                    : null,
              ),
            ),
          ),
      ],
      onSelected: onPick,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 15),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
