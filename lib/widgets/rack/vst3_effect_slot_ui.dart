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

/// Rack slot body for a VST3 **effect** plugin ([Vst3PluginType.effect]).
///
/// Distinct from [Vst3SlotUI] (instrument) in several ways:
///   - No MIDI channel badge — effects process audio, not note streams.
///   - No virtual piano.
///   - Shows an effect-type chip (Reverb / Compressor / EQ / Delay / …) in the
///     status row, auto-detected from the plugin name.
///   - Uses a purple/violet accent to distinguish effects from teal instruments.
///
/// On mobile or when the path is empty, falls back to [_UnavailableEffectPlaceholder].
class Vst3EffectSlotUI extends StatelessWidget {
  final Vst3PluginInstance plugin;

  const Vst3EffectSlotUI({super.key, required this.plugin});

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop || plugin.path.isEmpty) {
      return _UnavailableEffectPlaceholder(plugin: plugin);
    }
    return _EffectPanel(plugin: plugin);
  }
}

// ─── Effect type detection ────────────────────────────────────────────────────

/// Returns a localised effect-category label derived from the plugin name.
///
/// Uses keyword matching — plugins are not required to conform to any naming
/// convention, so this is heuristic. The order matters: more specific terms
/// (e.g. "compressor") are checked before generic ones (e.g. "comp").
String _effectTypeLabel(String pluginName, AppLocalizations l10n) {
  final lower = pluginName.toLowerCase();
  if (_matchesAny(lower, ['reverb', 'hall', 'room', 'convolution'])) {
    return l10n.vst3EffectTypeReverb;
  }
  if (_matchesAny(lower, ['compressor', 'comp', 'limiter', 'peak', 'rms'])) {
    return l10n.vst3EffectTypeCompressor;
  }
  if (_matchesAny(lower, ['eq', 'equalizer', 'equaliser', 'filter', 'parametric'])) {
    return l10n.vst3EffectTypeEq;
  }
  if (_matchesAny(lower, ['delay', 'echo', 'tape'])) {
    return l10n.vst3EffectTypeDelay;
  }
  if (_matchesAny(lower, ['chorus', 'flanger', 'phaser', 'tremolo', 'vibrato', 'modulation'])) {
    return l10n.vst3EffectTypeModulation;
  }
  if (_matchesAny(lower, ['distortion', 'overdrive', 'drive', 'fuzz', 'saturation', 'sat', 'amp'])) {
    return l10n.vst3EffectTypeDistortion;
  }
  if (_matchesAny(lower, ['gate', 'expander', 'dynamics', 'transient'])) {
    return l10n.vst3EffectTypeDynamics;
  }
  return l10n.vst3EffectTypeFx;
}

bool _matchesAny(String text, List<String> keywords) =>
    keywords.any(text.contains);

// ─── Accent colour ────────────────────────────────────────────────────────────

/// Purple accent used throughout the effect slot UI.
///
/// Distinguishes effect slots (purple) from instrument slots (teal) at a glance.
const Color _kEffectAccent = Color(0xFFBB86FC); // Material purple 200

// ─── Desktop effect panel ─────────────────────────────────────────────────────

class _EffectPanel extends StatefulWidget {
  final Vst3PluginInstance plugin;
  const _EffectPanel({required this.plugin});

  @override
  State<_EffectPanel> createState() => _EffectPanelState();
}

class _EffectPanelState extends State<_EffectPanel> {
  /// Display-name → list of params in that group.
  Map<String, List<VstParamInfo>> _groups = {};
  bool _loaded = false;
  final ValueNotifier<bool> _isCollapsed = ValueNotifier(true);

  // Same split threshold as Vst3SlotUI — prevents monolithic parameter lists.
  static const int _kSplitThreshold = 48;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadParams());
  }

  @override
  void didUpdateWidget(_EffectPanel old) {
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

    // Step 1: group by VST3 unit (IUnitInfo).
    final byUnit = <int, List<VstParamInfo>>{};
    for (final p in params) {
      byUnit.putIfAbsent(p.unitId, () => []).add(p);
    }

    // Step 2: build named groups, splitting oversized units by prefix.
    final multipleRealUnits = byUnit.length > 1;
    final named = <String, List<VstParamInfo>>{};

    for (final entry in byUnit.entries) {
      final uid = entry.key;
      final list = entry.value;
      final unitName = unitNames[uid] ??
          (uid <= 0 ? 'Parameters' : 'Group $uid');

      if (list.length > _kSplitThreshold) {
        final sub = _EffectSubGroupDetector.detect(list);
        if (sub.isNotEmpty) {
          for (final sg in sub.entries) {
            final chipName = multipleRealUnits
                ? '$unitName / ${sg.key}'
                : sg.key;
            named[chipName] = sg.value;
          }
          continue;
        }
      }
      named[unitName] = list;
    }

    setState(() {
      _groups = named;
      _loaded = true;
    });
  }

  void _openCategoryModal(
      BuildContext ctx, String name, List<VstParamInfo> params) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EffectParamModal(
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
          _EffectStatusRow(plugin: widget.plugin),
          const SizedBox(height: 4),
          _EffectEditorButton(plugin: widget.plugin),
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
            _EffectNoParamsHint(pluginName: widget.plugin.pluginName)
          else ...[
            const SizedBox(height: 8),
            _EffectCollapsibleHeader(isCollapsed: _isCollapsed),
            ValueListenableBuilder<bool>(
              valueListenable: _isCollapsed,
              builder: (context, collapsed, _) {
                if (collapsed) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _EffectCategoryChips(
                    groups: _groups,
                    onTap: (name) =>
                        _openCategoryModal(context, name, _groups[name]!),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Collapsible header ───────────────────────────────────────────────────────

class _EffectCollapsibleHeader extends StatelessWidget {
  final ValueNotifier<bool> isCollapsed;
  const _EffectCollapsibleHeader({required this.isCollapsed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => isCollapsed.value = !isCollapsed.value,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: isCollapsed,
              builder: (_, collapsed, _) => Icon(
                collapsed ? Icons.chevron_right : Icons.expand_more,
                size: 16,
                color: Colors.white38,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'PARAMETERS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Category chips ───────────────────────────────────────────────────────────

class _EffectCategoryChips extends StatelessWidget {
  final Map<String, List<VstParamInfo>> groups;
  final void Function(String name) onTap;

  const _EffectCategoryChips({required this.groups, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: entries.map((e) {
        return ActionChip(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: _kEffectAccent.withValues(alpha: 0.08),
          side: BorderSide(color: _kEffectAccent.withValues(alpha: 0.3)),
          avatar: Icon(Icons.auto_fix_high, size: 13, color: _kEffectAccent),
          label: Text(
            '${e.key} (${e.value.length})',
            style: TextStyle(
              color: _kEffectAccent,
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

// ─── Sub-group detection (identical strategy as Vst3SlotUI) ──────────────────

/// Analyses parameter title prefixes to split very large parameter lists into
/// manageable sub-groups. Uses word-prefix analysis with 2–64 group bounds.
class _EffectSubGroupDetector {
  static const int _kMinGroupCount = 2;
  static const int _kMaxGroupCount = 64;
  static const int _kPageSize = 24;
  static final _sep = RegExp(r'[\s\-_/|]+');

  /// Returns the best sub-group map, or empty if flat layout is fine.
  static Map<String, List<VstParamInfo>> detect(List<VstParamInfo> params) {
    if (params.length <= _kPageSize) return {};

    for (final prefixWords in [3, 2, 1]) {
      final groups = _groupByPrefix(params, prefixWords);
      if (_isUseful(groups, params.length)) return groups;
    }
    return {};
  }

  static Map<String, List<VstParamInfo>> _groupByPrefix(
      List<VstParamInfo> params, int words) {
    final groups = <String, List<VstParamInfo>>{};
    for (final p in params) {
      final tokens = p.title.trim().split(_sep);
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
    if (maxGroup >= total * 0.8) return false;
    return true;
  }
}

// ─── Parameter modal ──────────────────────────────────────────────────────────

const int _kEffectPageSize = 24;

/// Bottom sheet grid of knobs for one parameter category of an effect plugin.
///
/// Identical mechanics to [_ParamCategoryModal] in [Vst3SlotUI] but uses the
/// purple effect accent colour throughout.
class _EffectParamModal extends StatefulWidget {
  final String categoryName;
  final List<VstParamInfo> params;
  final Vst3PluginInstance plugin;

  const _EffectParamModal({
    required this.categoryName,
    required this.params,
    required this.plugin,
  });

  @override
  State<_EffectParamModal> createState() => _EffectParamModalState();
}

class _EffectParamModalState extends State<_EffectParamModal> {
  late Map<int, double> _values;
  Map<String, List<VstParamInfo>> _subGroups = {};
  List<String> _subGroupKeys = [];
  String? _selectedSubGroup;

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

    _subGroups = _EffectSubGroupDetector.detect(widget.params);
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
    final base = _subGroups.isNotEmpty && _selectedSubGroup != null
        ? (_subGroups[_selectedSubGroup] ?? widget.params)
        : widget.params;
    if (_searchText.isEmpty) return base;
    return base
        .where((p) => p.title.toLowerCase().contains(_searchText))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _currentParams;
    final totalPages = (filtered.length / _kEffectPageSize).ceil();
    final safePage = _page.clamp(0, math.max(0, totalPages - 1)).toInt();
    final pageItems =
        filtered.skip(safePage * _kEffectPageSize).take(_kEffectPageSize).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle ───────────────────────────────────────────────
          const SizedBox(height: 8),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),

          // ── Header ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.auto_fix_high, color: _kEffectAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.categoryName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold),
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

          // ── Sub-group dropdown ─────────────────────────────────────────
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

          // ── Search ────────────────────────────────────────────────────
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

          // ── Knob grid ─────────────────────────────────────────────────
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
                      return _EffectKnobTile(
                        info: p,
                        value: _values[p.id] ?? 0.0,
                        onChanged: (v) => _setParam(p.id, v),
                      );
                    },
                  ),
          ),

          // ── Pagination ────────────────────────────────────────────────
          if (totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
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

// ─── Knob tile ────────────────────────────────────────────────────────────────

/// A single knob cell in the parameter grid, styled with the purple effect accent.
class _EffectKnobTile extends StatelessWidget {
  final VstParamInfo info;
  final double value;
  final ValueChanged<double> onChanged;

  const _EffectKnobTile({
    required this.info,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
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

/// Shows the plugin path, load status, and an effect-type chip.
///
/// The effect-type chip (Reverb / Compressor / EQ …) replaces the MIDI IN chip
/// used by instrument slots — effects receive audio, not MIDI note streams.
class _EffectStatusRow extends StatelessWidget {
  final Vst3PluginInstance plugin;
  const _EffectStatusRow({required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vstSvc = context.read<VstHostService>();
    final isLoaded = vstSvc.isSupported;
    final effectLabel = _effectTypeLabel(plugin.pluginName, l10n);

    return Row(
      children: [
        Icon(
          isLoaded ? Icons.check_circle_outline : Icons.error_outline,
          size: 14,
          color: isLoaded ? _kEffectAccent : Colors.redAccent,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            plugin.path,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // ── Effect-type chip ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: _kEffectAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _kEffectAccent.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_fix_high, size: 11, color: _kEffectAccent),
              const SizedBox(width: 4),
              Text(
                effectLabel,
                style: TextStyle(
                  color: _kEffectAccent,
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

class _EffectNoParamsHint extends StatelessWidget {
  final String pluginName;
  const _EffectNoParamsHint({required this.pluginName});

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

// ─── Editor button ────────────────────────────────────────────────────────────

/// Toggle button to open / close the plugin's native GUI window.
///
/// Uses the purple effect accent when closed, orange when open — the orange
/// "active" state is shared with the instrument editor button so the state is
/// instantly recognisable regardless of slot type.
class _EffectEditorButton extends StatefulWidget {
  final Vst3PluginInstance plugin;
  const _EffectEditorButton({required this.plugin});

  @override
  State<_EffectEditorButton> createState() => _EffectEditorButtonState();
}

class _EffectEditorButtonState extends State<_EffectEditorButton> {
  bool _open = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    // Poll native state every 500 ms to detect window-close via the title bar.
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
      return;
    }
    final ok = vstSvc.openEditor(
      widget.plugin.id,
      title: widget.plugin.pluginName,
    );
    if (ok) {
      setState(() => _open = true);
    } else {
      // Editor failed to open — likely a GLX/XWayland conflict on Linux.
      // The native layer has already logged details; surface the hint to the user.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.vst3EditorOpenFailed),
        duration: const Duration(seconds: 8),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Vst3EffectSlotUI._isDesktop) return const SizedBox.shrink();

    final activeColor = _open ? Colors.orangeAccent : _kEffectAccent;

    return SizedBox(
      height: 30,
      child: OutlinedButton.icon(
        onPressed: _toggle,
        style: OutlinedButton.styleFrom(
          foregroundColor: activeColor,
          side: BorderSide(color: activeColor.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 11),
        ),
        icon: Icon(_open ? Icons.close : Icons.open_in_new, size: 14),
        label: Text(_open ? 'Close Plugin UI' : 'Show Plugin UI'),
      ),
    );
  }
}

// ─── Unavailable placeholder ──────────────────────────────────────────────────

/// Shown on mobile or when the .vst3 path is empty.
class _UnavailableEffectPlaceholder extends StatelessWidget {
  final Vst3PluginInstance plugin;
  const _UnavailableEffectPlaceholder({required this.plugin});

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
          Icon(Icons.auto_fix_high,
              color: _kEffectAccent.withValues(alpha: 0.5), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.pluginName,
                  style: const TextStyle(
                      color: Colors.white70, fontWeight: FontWeight.bold),
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
