import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../../services/file_picker_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/audio_port_id.dart';
import '../../models/vst3_plugin_instance.dart';
import '../../services/audio_graph.dart';
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
  /// Display-name → list of params in that group.
  /// Built from IUnitInfo units; large single-unit groups are further split
  /// by parameter-name prefix analysis so plugins like Aeolus (everything in
  /// Root Unit) still get meaningful category chips.
  Map<String, List<VstParamInfo>> _groups = {};
  bool _loaded = false;
  final ValueNotifier<bool> _isCollapsed = ValueNotifier(true);

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

  // How many params a unit must have before we try to split it by name.
  static const int _kSplitThreshold = 48;

  void _loadParams() {
    if (!mounted) return;
    final vstSvc = context.read<VstHostService>();
    final params = vstSvc.getParameters(widget.plugin.id);
    final unitNames = vstSvc.getUnitNames(widget.plugin.id);

    // Step 1: group by unitId.
    final byUnit = <int, List<VstParamInfo>>{};
    for (final p in params) {
      byUnit.putIfAbsent(p.unitId, () => []).add(p);
    }

    // Step 2: build named groups.  For large groups (plugins that put
    // everything in Root Unit, like Aeolus) run name-prefix analysis and
    // expand into multiple chips.  This runs at the chip level so the
    // modal receives a usefully-scoped list from the start.
    final multipleRealUnits = byUnit.length > 1;
    final named = <String, List<VstParamInfo>>{};

    for (final entry in byUnit.entries) {
      final uid = entry.key;
      final list = entry.value;
      final unitName = unitNames[uid] ??
          (uid <= 0 ? 'Parameters' : 'Group $uid');

      if (list.length > _kSplitThreshold) {
        final sub = _SubGroupDetector.detect(list);
        if (sub.isNotEmpty) {
          // Prefix the sub-group name with the unit name only when there are
          // multiple real units so the chip labels remain readable.
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

  void _openCategoryModal(BuildContext ctx, String name, List<VstParamInfo> params) {
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
          else ...[
            const SizedBox(height: 8),
            _CollapsibleParamsHeader(isCollapsed: _isCollapsed),
            ValueListenableBuilder<bool>(
              valueListenable: _isCollapsed,
              builder: (context, collapsed, _) {
                if (collapsed) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _CategoryChips(
                    groups: _groups,
                    onTap: (name) => _openCategoryModal(context, name, _groups[name]!),
                  ),
                );
              },
            ),
          ],

          // ── FX Inserts shortcut (instrument VST3 only) ─────────────────
          // Shows a collapsible list of VST3 effect slots wired to this
          // instrument's audio outputs, with a + button to quickly add one.
          const SizedBox(height: 8),
          _FxInsertsSection(instrumentPlugin: widget.plugin),
        ],
      ),
    );
  }
}

// ─── FX Inserts section ───────────────────────────────────────────────────────

/// Expandable "FX Inserts" section shown at the bottom of an instrument VST3 slot.
///
/// Reads the [AudioGraph] to discover which VST3 effect slots are currently
/// connected to this instrument's [AudioPortId.audioOutL] jack. The list is
/// syntactic sugar — cables still appear in the patch view and can be managed
/// there. The + button browses for an effect, adds it as a top-level rack slot,
/// and auto-wires [audioOutL/R] → [audioInL/R].
class _FxInsertsSection extends StatefulWidget {
  final Vst3PluginInstance instrumentPlugin;

  const _FxInsertsSection({required this.instrumentPlugin});

  @override
  State<_FxInsertsSection> createState() => _FxInsertsSectionState();
}

class _FxInsertsSectionState extends State<_FxInsertsSection> {
  bool _expanded = false;
  bool _loading = false;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns the effect slots wired to this instrument's audio outputs.
  ///
  /// Looks at all connections where [fromSlotId] == this instrument and
  /// [fromPort] is [AudioPortId.audioOutL], then finds the rack slot for
  /// each target that is a VST3 effect.
  List<Vst3PluginInstance> _connectedEffects(
      AudioGraph graph, RackState rack) {
    final outCables = graph
        .connectionsFrom(widget.instrumentPlugin.id)
        .where((c) => c.fromPort == AudioPortId.audioOutL);

    return outCables
        .map((c) => rack.plugins
            .whereType<Vst3PluginInstance>()
            .where((p) =>
                p.id == c.toSlotId &&
                p.pluginType == Vst3PluginType.effect)
            .firstOrNull)
        .whereType<Vst3PluginInstance>()
        .toList();
  }

  /// Resolves the `.vst3` bundle directory from any path the picker gives us.
  ///
  /// Handles both direct bundle selection and picking a file inside the bundle.
  String? _resolveBundlePath(String rawPath) {
    if (rawPath.endsWith('.vst3') &&
        FileSystemEntity.isDirectorySync(rawPath)) {
      return rawPath;
    }
    var dir = File(rawPath).parent;
    while (dir.path != dir.parent.path) {
      if (dir.path.endsWith('.vst3')) return dir.path;
      dir = dir.parent;
    }
    return null;
  }

  /// Browses for a .vst3 effect, loads it, adds it to the rack, and
  /// automatically wires audioOutL/R from this instrument to audioInL/R of
  /// the new effect slot.
  Future<void> _addEffect(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final vstSvc = context.read<VstHostService>();
    final rack = context.read<RackState>();
    final graph = context.read<AudioGraph>();

    final selected = await FilePickerService.pickDirectory(
      context: context,
      dialogTitle: l10n.vst3BrowseEffectTitle,
    );
    if (selected == null) return;

    final bundlePath = _resolveBundlePath(selected);
    if (bundlePath == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.vst3NotABundle)),
      );
      return;
    }

    setState(() => _loading = true);
    await vstSvc.initialize();
    final slotId = rack.generateSlotId();
    final instance = await vstSvc.loadPlugin(
      bundlePath,
      slotId,
      pluginType: Vst3PluginType.effect,
    );
    setState(() => _loading = false);

    if (!context.mounted) return;

    if (instance == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.vst3LoadFailed)),
      );
      return;
    }

    // Add effect slot to the rack right after this instrument slot.
    rack.addPlugin(instance);
    vstSvc.startAudio();

    // Auto-wire: instrument audioOutL/R → effect audioInL/R.
    graph.connect(
      widget.instrumentPlugin.id,
      AudioPortId.audioOutL,
      slotId,
      AudioPortId.audioInL,
    );
    graph.connect(
      widget.instrumentPlugin.id,
      AudioPortId.audioOutR,
      slotId,
      AudioPortId.audioInR,
    );

    // Sync native audio routing so the effect is active immediately.
    // `keyboardSfIds` is required on Android so audio looper bus routing
    // survives this rebuild (see `RackState.buildKeyboardSfIds`).
    vstSvc.syncAudioRouting(
      graph,
      rack.plugins,
      keyboardSfIds: rack.buildKeyboardSfIds(),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isDesktop) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final graph = context.watch<AudioGraph>();
    final rack = context.read<RackState>();
    final effects = _connectedEffects(graph, rack);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Collapsible header chip ────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.deepPurple.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 14,
                  color: Colors.deepPurpleAccent,
                ),
                const SizedBox(width: 4),
                Text(
                  '${l10n.vst3FxInserts} (${effects.length})',
                  style: const TextStyle(
                    color: Colors.deepPurpleAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Expanded section ───────────────────────────────────────────────
        if (_expanded) ...[
          const SizedBox(height: 6),
          if (effects.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                l10n.vst3FxNoEffects,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                ),
              ),
            )
          else
            ...effects.map((fx) => _InsertEffectRow(effect: fx)),
          const SizedBox(height: 4),
          // ── + button to add a new effect ─────────────────────────────
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            SizedBox(
              height: 26,
              child: OutlinedButton.icon(
                onPressed: () => _addEffect(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.deepPurpleAccent,
                  side: BorderSide(
                      color: Colors.deepPurple.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 11),
                ),
                icon: const Icon(Icons.add, size: 13),
                label: Text(l10n.vst3FxAddEffect),
              ),
            ),
        ],
      ],
    );
  }
}

/// One row in the FX inserts list showing the effect name and a remove-cable button.
///
/// Removing the cable disconnects the audioOutL/R → audioInL/R connections but
/// keeps the effect slot in the rack (it can still be reached via patch view).
class _InsertEffectRow extends StatelessWidget {
  final Vst3PluginInstance effect;

  const _InsertEffectRow({required this.effect});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.deepPurple.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_fix_high, size: 12,
                color: Colors.deepPurpleAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                effect.pluginName,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Disconnect button — removes the cables but leaves the rack slot.
            GestureDetector(
              onTap: () => _disconnect(context),
              child: const Icon(Icons.link_off, size: 14, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  /// Removes the audioOutL/R → audioInL/R cables between the parent instrument
  /// and this effect slot. The effect slot itself stays in the rack.
  void _disconnect(BuildContext context) {
    final graph = context.read<AudioGraph>();
    final vstSvc = context.read<VstHostService>();
    final rack = context.read<RackState>();

    // Find the parent instrument (the slot whose audioOutL connects here).
    final parentCable = graph.connections
        .where((c) =>
            c.toSlotId == effect.id &&
            c.toPort == AudioPortId.audioInL)
        .firstOrNull;
    if (parentCable == null) return;

    // Disconnect both stereo cables by their connection IDs.
    graph.disconnect(parentCable.id);
    final rightCable = graph.connections.where((c) =>
        c.fromSlotId == parentCable.fromSlotId &&
        c.toSlotId == effect.id &&
        c.toPort == AudioPortId.audioInR).firstOrNull;
    if (rightCable != null) graph.disconnect(rightCable.id);
    vstSvc.syncAudioRouting(
      graph,
      rack.plugins,
      keyboardSfIds: rack.buildKeyboardSfIds(),
    );
  }
}

class _CollapsibleParamsHeader extends StatelessWidget {
  final ValueNotifier<bool> isCollapsed;
  const _CollapsibleParamsHeader({required this.isCollapsed});

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
              builder: (context, collapsed, _) => Icon(
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

class _CategoryChips extends StatelessWidget {
  final Map<String, List<VstParamInfo>> groups;
  final void Function(String name) onTap;

  const _CategoryChips({
    required this.groups,
    required this.onTap,
  });

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
          backgroundColor: Colors.tealAccent.withValues(alpha: 0.08),
          side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.3)),
          avatar: const Icon(Icons.tune, size: 13, color: Colors.tealAccent),
          label: Text(
            '${e.key} (${e.value.length})',
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
//   1. Three-word prefix  e.g. "MIDI CC 0|5" → sub-group "MIDI CC 0"
//   2. Two-word prefix    e.g. "Channel 1 CC 5" → sub-group "Channel 1"
//   3. One-word prefix    e.g. "VCO Type" → sub-group "VCO"
//   4. No sub-grouping    (fall back to search + pagination)
//
// Separators recognised: whitespace, hyphen, underscore, slash, pipe (|).
// Pipe is important for "MIDI CC 0|0" which should group as "MIDI CC 0".
//
// A candidate prefix is accepted only when:
//   • It produces 2–64 distinct sub-groups
//   • No single sub-group contains more than 80 % of all params
class _SubGroupDetector {
  static const int _kMinGroupCount = 2;
  static const int _kMaxGroupCount = 64;
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.vst3EditorOpenFailed),
        duration: const Duration(seconds: 8),
      ));
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
