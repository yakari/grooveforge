import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/vst3_plugin_instance.dart';
import '../../services/rack_state.dart';
import '../../services/vst_host_service.dart';
import '../rotary_knob.dart';

/// Rack slot body for an external [Vst3PluginInstance].
///
/// On desktop shows a compact status row + editor button + parameter category
/// chips. Tapping a category opens a modal grid of knobs for that group.
///
/// On mobile or when the path is empty it shows a placeholder card.
class Vst3SlotUI extends StatelessWidget {
  final Vst3PluginInstance plugin;

  const Vst3SlotUI({super.key, required this.plugin});

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop || plugin.path.isEmpty) {
      return _UnavailablePlaceholder(plugin: plugin);
    }
    return _Vst3PluginPanel(plugin: plugin);
  }
}

// ─── Desktop plugin panel ─────────────────────────────────────────────────────

class _Vst3PluginPanel extends StatefulWidget {
  final Vst3PluginInstance plugin;
  const _Vst3PluginPanel({required this.plugin});

  @override
  State<_Vst3PluginPanel> createState() => _Vst3PluginPanelState();
}

class _Vst3PluginPanelState extends State<_Vst3PluginPanel> {
  /// unitId → list of params in that group
  Map<int, List<VstParamInfo>> _groups = {};
  /// unitId → display name
  Map<int, String> _unitNames = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadParams());
  }

  @override
  void didUpdateWidget(_Vst3PluginPanel old) {
    super.didUpdateWidget(old);
    if (old.plugin.id != widget.plugin.id ||
        old.plugin.path != widget.plugin.path) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadParams());
    }
  }

  void _loadParams() {
    if (!mounted) return;
    final vstSvc = context.read<VstHostService>();
    final params = vstSvc.getParameters(widget.plugin.id);
    final unitNames = vstSvc.getUnitNames(widget.plugin.id);

    // Group parameters by unitId.
    final groups = <int, List<VstParamInfo>>{};
    for (final p in params) {
      groups.putIfAbsent(p.unitId, () => []).add(p);
    }

    setState(() {
      _groups = groups;
      _unitNames = unitNames;
      _loaded = true;
    });
  }

  void _openCategoryModal(BuildContext ctx, int unitId, List<VstParamInfo> params) {
    final name = _unitNames[unitId] ?? (unitId == -1 ? 'Parameters' : 'Group $unitId');
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ParamCategoryModal(
        categoryName: name,
        params: params,
        plugin: widget.plugin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusRow(plugin: widget.plugin),
          const SizedBox(height: 4),
          _EditorButton(plugin: widget.plugin),
          const SizedBox(height: 6),
          if (!_loaded)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_groups.isEmpty)
            _NoParamsHint(pluginName: widget.plugin.pluginName)
          else
            _CategoryChips(
              groups: _groups,
              unitNames: _unitNames,
              onTap: (uid) => _openCategoryModal(context, uid, _groups[uid]!),
            ),
        ],
      ),
    );
  }
}

// ─── Category chips ───────────────────────────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final Map<int, List<VstParamInfo>> groups;
  final Map<int, String> unitNames;
  final void Function(int unitId) onTap;

  const _CategoryChips({
    required this.groups,
    required this.unitNames,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final entries = groups.entries.toList()
      ..sort((a, b) {
        // Put the root unit (-1) last, sort others alphabetically.
        if (a.key == -1) return 1;
        if (b.key == -1) return -1;
        final na = unitNames[a.key] ?? '';
        final nb = unitNames[b.key] ?? '';
        return na.compareTo(nb);
      });

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries.map((e) {
        final name = unitNames[e.key] ?? (e.key == -1 ? 'Params' : 'Group ${e.key}');
        final count = e.value.length;
        return ActionChip(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: Colors.tealAccent.withValues(alpha: 0.08),
          side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.3)),
          avatar: const Icon(Icons.tune, size: 13, color: Colors.tealAccent),
          label: Text(
            '$name ($count)',
            style: const TextStyle(
              color: Colors.tealAccent,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          onPressed: () => onTap(e.key),
        );
      }).toList(),
    );
  }
}

// ─── Sub-group detection ──────────────────────────────────────────────────────
//
// Analyses parameter title patterns to build a two-level hierarchy.
//
// Strategy (tried in order, first match wins):
//   1. Two-word prefix  e.g. "Channel 1 CC 5" → sub-group "Channel 1"
//   2. One-word prefix  e.g. "VCO Type"       → sub-group "VCO"
//   3. No sub-grouping  (fall back to search + pagination)
//
// A candidate prefix is accepted only when:
//   • It produces 2–64 distinct sub-groups
//   • No single sub-group contains more than 80 % of all params
//     (otherwise the grouping is not useful)
//   • Every individual sub-group has ≤ _kPageSize params
//     OR it further reduces compared to the full list.
class _SubGroupDetector {
  static const int _kMinGroupCount = 2;
  static const int _kMaxGroupCount = 64;

  /// Returns the best sub-group map, or empty if flat layout is fine.
  static Map<String, List<VstParamInfo>> detect(List<VstParamInfo> params) {
    if (params.length <= _kPageSize) return {};

    for (final prefixWords in [2, 1]) {
      final groups = _groupByPrefix(params, prefixWords);
      if (_isUseful(groups, params.length)) return groups;
    }
    return {};
  }

  static Map<String, List<VstParamInfo>> _groupByPrefix(
      List<VstParamInfo> params, int words) {
    final groups = <String, List<VstParamInfo>>{};
    for (final p in params) {
      final tokens = p.title.trim().split(RegExp(r'[\s\-_/]+'));
      final key = tokens.take(words).join(' ');
      groups.putIfAbsent(key, () => []).add(p);
    }
    return groups;
  }

  static bool _isUseful(
      Map<String, List<VstParamInfo>> groups, int total) {
    if (groups.length < _kMinGroupCount) return false;
    if (groups.length > _kMaxGroupCount) return false;
    final maxGroup = groups.values.fold(0, (m, v) => math.max(m, v.length));
    // Reject if one group contains almost everything (not a useful split).
    if (maxGroup >= total * 0.8) return false;
    return true;
  }
}

// ─── Parameter category modal (knobs) ────────────────────────────────────────

const int _kPageSize = 24;

class _ParamCategoryModal extends StatefulWidget {
  final String categoryName;
  final List<VstParamInfo> params;
  final Vst3PluginInstance plugin;

  const _ParamCategoryModal({
    required this.categoryName,
    required this.params,
    required this.plugin,
  });

  @override
  State<_ParamCategoryModal> createState() => _ParamCategoryModalState();
}

class _ParamCategoryModalState extends State<_ParamCategoryModal> {
  late Map<int, double> _values;

  // Sub-group detection results.
  Map<String, List<VstParamInfo>> _subGroups = {};
  List<String> _subGroupKeys = [];
  String? _selectedSubGroup; // null = all / no sub-groups

  // Search + pagination.
  final _searchCtrl = TextEditingController();
  String _searchText = '';
  int _page = 0;

  @override
  void initState() {
    super.initState();
    final vstSvc = context.read<VstHostService>();
    _values = {
      for (final p in widget.params)
        p.id: widget.plugin.parameters[p.id] ??
            vstSvc.getParameter(widget.plugin.id, p.id),
    };

    _subGroups = _SubGroupDetector.detect(widget.params);
    if (_subGroups.isNotEmpty) {
      _subGroupKeys = _subGroups.keys.toList()..sort();
      _selectedSubGroup = _subGroupKeys.first;
    }

    _searchCtrl.addListener(() {
      setState(() {
        _searchText = _searchCtrl.text.toLowerCase();
        _page = 0;
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setParam(int paramId, double value) {
    final vstSvc = context.read<VstHostService>();
    final rack = context.read<RackState>();
    vstSvc.setParameter(widget.plugin.id, paramId, value);
    rack.setVst3Parameter(widget.plugin.id, paramId, value);
    setState(() => _values[paramId] = value);
  }

  List<VstParamInfo> get _currentParams {
    // Start from sub-group or all params.
    final base = _subGroups.isNotEmpty && _selectedSubGroup != null
        ? (_subGroups[_selectedSubGroup] ?? widget.params)
        : widget.params;
    // Apply text search.
    if (_searchText.isEmpty) return base;
    return base
        .where((p) => p.title.toLowerCase().contains(_searchText))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _currentParams;
    final totalPages = (filtered.length / _kPageSize).ceil();
    final safePage = _page.clamp(0, math.max(0, totalPages - 1)).toInt();
    final pageItems = filtered.skip(safePage * _kPageSize).take(_kPageSize).toList();

    final maxH = MediaQuery.of(context).size.height * 0.75;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ───────────────────────────────────────────────────
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),

          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.tealAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.categoryName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${filtered.length} / ${widget.params.length}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Sub-group dropdown (only when auto-detected) ───────────────────
          if (_subGroups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.layers, size: 14, color: Colors.white38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedSubGroup,
                      dropdownColor: Colors.grey[850],
                      isDense: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white10,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      items: [
                        // "All" option
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            'All groups (${widget.params.length})',
                            style: const TextStyle(color: Colors.white54),
                          ),
                        ),
                        ..._subGroupKeys.map(
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Text(
                              '$k  (${_subGroups[k]!.length})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() { _selectedSubGroup = v; _page = 0; }),
                    ),
                  ),
                ],
              ),
            ),

          if (_subGroups.isNotEmpty) const SizedBox(height: 8),

          // ── Search bar ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search parameters…',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon:
                    const Icon(Icons.search, color: Colors.white38, size: 18),
                suffixIcon: _searchText.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: Colors.white38, size: 16),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white10),

          // ── Knob grid ────────────────────────────────────────────────────
          Flexible(
            child: pageItems.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'No parameters match.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 110,
                      mainAxisExtent: 108,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: pageItems.length,
                    itemBuilder: (_, i) {
                      final p = pageItems[i];
                      return _KnobTile(
                        info: p,
                        value: _values[p.id] ?? 0.0,
                        onChanged: (v) => _setParam(p.id, v),
                      );
                    },
                  ),
          ),

          // ── Pagination ────────────────────────────────────────────────────
          if (totalPages > 1)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    color: safePage > 0 ? Colors.white70 : Colors.white24,
                    onPressed: safePage > 0
                        ? () => setState(() => _page = safePage - 1)
                        : null,
                  ),
                  Text(
                    '${safePage + 1} / $totalPages',
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: safePage < totalPages - 1
                        ? Colors.white70
                        : Colors.white24,
                    onPressed: safePage < totalPages - 1
                        ? () => setState(() => _page = safePage + 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Individual knob tile ─────────────────────────────────────────────────────

class _KnobTile extends StatelessWidget {
  final VstParamInfo info;
  final double value;
  final ValueChanged<double> onChanged;

  const _KnobTile({
    required this.info,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // VST3 params are already normalized [0, 1]; RotaryKnob's min/max defaults
    // match, so onChanged receives the normalized value directly.
    final label = info.units.isEmpty
        ? info.title
        : '${info.title} (${info.units})';
    return RotaryKnob(
      value: value,
      label: label,
      onChanged: onChanged,
      size: 52,
      isCompact: true,
    );
  }
}

// ─── Status row ───────────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final Vst3PluginInstance plugin;
  const _StatusRow({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final vstSvc = context.read<VstHostService>();
    final isLoaded = vstSvc.isSupported;

    return Row(
      children: [
        Icon(
          isLoaded ? Icons.check_circle_outline : Icons.error_outline,
          size: 14,
          color: isLoaded ? Colors.tealAccent : Colors.redAccent,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            plugin.path,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.tealAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.piano, size: 11, color: Colors.tealAccent),
              SizedBox(width: 4),
              Text(
                'MIDI IN',
                style: TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── No-parameters hint ───────────────────────────────────────────────────────

class _NoParamsHint extends StatelessWidget {
  final String pluginName;
  const _NoParamsHint({required this.pluginName});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: Colors.white38),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No automatable parameters found.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '$pluginName does not expose parameters via IEditController.',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Editor window button ─────────────────────────────────────────────────────

class _EditorButton extends StatefulWidget {
  final Vst3PluginInstance plugin;
  const _EditorButton({required this.plugin});

  @override
  State<_EditorButton> createState() => _EditorButtonState();
}

class _EditorButtonState extends State<_EditorButton> {
  bool _open = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Poll native state every 500 ms so we detect when the user closes the
    // X11 window via the title-bar close button.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final vstSvc = context.read<VstHostService>();
      final nowOpen = vstSvc.isEditorOpen(widget.plugin.id);
      if (nowOpen != _open) setState(() => _open = nowOpen);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _toggle() {
    final vstSvc = context.read<VstHostService>();
    if (_open) {
      vstSvc.closeEditor(widget.plugin.id);
      setState(() => _open = false);
    } else {
      final ok = vstSvc.openEditor(
        widget.plugin.id,
        title: widget.plugin.pluginName,
      );
      if (ok) setState(() => _open = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Vst3SlotUI._isDesktop) return const SizedBox.shrink();

    return SizedBox(
      height: 30,
      child: OutlinedButton.icon(
        onPressed: _toggle,
        style: OutlinedButton.styleFrom(
          foregroundColor: _open ? Colors.orangeAccent : Colors.tealAccent,
          side: BorderSide(
            color: (_open ? Colors.orangeAccent : Colors.tealAccent)
                .withValues(alpha: 0.6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 11),
        ),
        icon: Icon(_open ? Icons.close : Icons.open_in_new, size: 14),
        label: Text(_open ? 'Close Plugin UI' : 'Show Plugin UI'),
      ),
    );
  }
}

// ─── Mobile / empty-path placeholder ─────────────────────────────────────────

class _UnavailablePlaceholder extends StatelessWidget {
  final Vst3PluginInstance plugin;
  const _UnavailablePlaceholder({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(Icons.extension_off, color: Colors.white38, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.pluginName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  plugin.path.isEmpty
                      ? l10n.vst3NotLoaded
                      : l10n.rackPluginUnavailableOnMobile,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
