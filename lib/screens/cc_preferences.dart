import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/models/grooveforge_keyboard_plugin.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/cc_param_registry.dart';
import 'package:grooveforge/services/rack_state.dart';

/// Screen for configuring MIDI Control Change (CC) mappings.
///
/// Supports the full sealed [CcMappingTarget] hierarchy: GM CC remapping,
/// legacy system actions, slot-addressed parameters, transport controls,
/// global actions (system volume), and channel-swap macros.
///
/// The "Add Mapping" dialog uses a hierarchical target picker:
/// Category → Slot → Parameter.
class CcPreferencesScreen extends StatelessWidget {
  const CcPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ccService = context.read<CcMappingService>();

    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.ccTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildLastReceivedCard(context, ccService),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.ccActiveMappings,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildMappingsList(context, ccService)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMappingDialog(context, ccService),
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.of(context)!.ccAddMapping),
      ),
    );
  }

  // ── MIDI monitor card ──────────────────────────────────────────────────

  Widget _buildLastReceivedCard(
    BuildContext context,
    CcMappingService ccService,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.monitor_heart, size: 48, color: Colors.teal),
            const SizedBox(height: 16),
            ValueListenableBuilder<MidiEventInfo?>(
              valueListenable: ccService.lastEventNotifier,
              builder: (context, event, _) {
                if (event == null) {
                  return Text(
                    AppLocalizations.of(context)!.ccWaitingForEvents,
                    style: const TextStyle(fontSize: 18),
                  );
                }
                final l10n = AppLocalizations.of(context)!;
                final eventText = event.type == 'CC'
                    ? l10n.ccLastEventCC(event.data1, event.data2)
                    : l10n.ccLastEventNote(event.type, event.data1, event.data2);
                return Column(
                  children: [
                    Text(eventText,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(l10n.ccReceivedOnChannel(event.channel + 1),
                        style: const TextStyle(
                            fontSize: 16, color: Colors.blueAccent)),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.ccInstructions,
              textAlign: TextAlign.center,
              style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mappings list ──────────────────────────────────────────────────────

  Widget _buildMappingsList(BuildContext context, CcMappingService ccService) {
    return ValueListenableBuilder<List<CcMapping>>(
      valueListenable: ccService.mappingsNotifier,
      builder: (context, mappings, _) {
        if (mappings.isEmpty) {
          return Center(
            child: Text(
              AppLocalizations.of(context)!.ccNoMappings,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }
        return ListView.builder(
          itemCount: mappings.length,
          itemBuilder: (context, index) {
            final mapping = mappings[index];
            return Card(
              child: ListTile(
                leading: Icon(_iconForTarget(mapping.target),
                    color: Colors.blueAccent),
                title: Text(_mappingTitle(context, mapping)),
                subtitle: Text(_mappingSubtitle(context, mapping)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () {
                    ccService.removeMapping(mapping);
                    _markDirty(context);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Returns an icon appropriate for the mapping target type.
  IconData _iconForTarget(CcMappingTarget target) => switch (target) {
        GmCcTarget() => Icons.swap_horiz,
        SystemTarget() => Icons.settings,
        SlotParamTarget() => Icons.tune,
        SwapTarget() => Icons.swap_calls,
        TransportTarget() => Icons.play_circle_outline,
        GlobalTarget() => Icons.volume_up,
      };

  String _mappingTitle(BuildContext context, CcMapping mapping) {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();
    final targetName = switch (mapping.target) {
      GmCcTarget(:final targetCc) =>
        CcMappingService.standardGmCcs[targetCc] ??
            l10n.ccUnknownSequence(targetCc),
      SystemTarget(:final actionCode) =>
        CcMappingService.standardGmCcs[actionCode] ??
            l10n.ccUnknownSequence(actionCode),
      SlotParamTarget(:final slotId, :final paramKey) =>
        '${_slotDisplayName(rack, slotId)} \u2192 $paramKey',
      SwapTarget(:final slotIdA, :final slotIdB) =>
        'Swap: ${_slotDisplayName(rack, slotIdA)} \u2194 ${_slotDisplayName(rack, slotIdB)}',
      TransportTarget(:final action) => _transportLabel(action),
      GlobalTarget(:final action) => _globalLabel(action),
    };
    return l10n.ccMappingHardwareToTarget(mapping.incomingCc, targetName);
  }

  String _mappingSubtitle(BuildContext context, CcMapping mapping) {
    final l10n = AppLocalizations.of(context)!;
    return switch (mapping.target) {
      GmCcTarget(:final targetChannel) =>
        l10n.ccMappingRouting(_channelLabel(context, targetChannel)),
      SystemTarget(:final actionCode, :final targetChannel,
            :final muteChannels) =>
        _systemSubtitle(context, actionCode, targetChannel, muteChannels),
      SlotParamTarget(:final mode) => mode.name,
      SwapTarget(:final swapCables) =>
        swapCables ? 'Channels + cables' : 'Channels only',
      TransportTarget() => '',
      GlobalTarget() => '',
    };
  }

  String _systemSubtitle(BuildContext context, int actionCode,
      int targetChannel, Set<int>? muteChannels) {
    final l10n = AppLocalizations.of(context)!;
    if (CcMappingService.isMuteAction(actionCode)) {
      if (muteChannels == null || muteChannels.isEmpty) return l10n.ccMuteNoChannels;
      final sorted = muteChannels.toList()..sort();
      return l10n.ccMuteChannelsSummary(
          sorted.map((ch) => (ch + 1).toString()).join(', '));
    }
    if (CcMappingService.isLooperAction(actionCode)) return '';
    return l10n.ccMappingRouting(_channelLabel(context, targetChannel));
  }

  String _channelLabel(BuildContext context, int targetChannel) {
    final l10n = AppLocalizations.of(context)!;
    if (targetChannel == -1) return l10n.ccRoutingAllChannels;
    if (targetChannel == -2) return l10n.ccRoutingSameAsIncoming;
    return l10n.ccRoutingChannel(targetChannel + 1);
  }

  /// Human-readable display name for a rack slot.
  String _slotDisplayName(RackState rack, String slotId) {
    final plugin = rack.plugins.where((p) => p.id == slotId).firstOrNull;
    if (plugin == null) return slotId;
    return plugin.displayName;
  }

  String _transportLabel(TransportAction action) => switch (action) {
        TransportAction.playStop => 'Play / Stop',
        TransportAction.tapTempo => 'Tap Tempo',
        TransportAction.metronomeToggle => 'Metronome Toggle',
      };

  String _globalLabel(GlobalAction action) => switch (action) {
        GlobalAction.systemVolume => 'System Volume',
      };

  void _markDirty(BuildContext context) {
    context.read<RackState>().markDirty();
  }

  // ── Add mapping dialog ─────────────────────────────────────────────────

  void _showAddMappingDialog(BuildContext context, CcMappingService ccService) {
    showDialog(
      context: context,
      builder: (_) => _AddMappingDialog(ccService: ccService),
    );
  }
}

// ── Target categories for the hierarchical picker ────────────────────────────

enum _TargetCategory {
  gmCc,
  instruments,
  audioEffects,
  midiFx,
  looper,
  transport,
  global,
  macros,
}

// ── Add mapping dialog (StatefulWidget) ──────────────────────────────────────

/// Multi-step dialog for creating a new CC mapping.
///
/// Step 1: Enter incoming CC number.
/// Step 2: Pick a target category.
/// Step 3: Pick a specific target (slot + parameter, or transport action, etc.).
class _AddMappingDialog extends StatefulWidget {
  final CcMappingService ccService;

  const _AddMappingDialog({required this.ccService});

  @override
  State<_AddMappingDialog> createState() => _AddMappingDialogState();
}

class _AddMappingDialogState extends State<_AddMappingDialog> {
  final _incomingController = TextEditingController();
  _TargetCategory? _category;
  // ── State for category-specific sub-pickers ────────────────────────────

  // GM CC
  int _gmTargetCc = 74;
  int _gmTargetChannel = -2;

  // System (legacy)
  int _systemAction = 1001;
  int _systemChannel = -2;
  Set<int> _muteChannels = {};

  // Slot param
  String? _selectedSlotId;
  String? _selectedParamKey;

  // Swap
  String? _swapSlotA;
  String? _swapSlotB;
  bool _swapCables = true;

  // Transport
  TransportAction _transportAction = TransportAction.playStop;

  @override
  void initState() {
    super.initState();
    final lastEvent = widget.ccService.lastEventNotifier.value;
    if (lastEvent != null && lastEvent.type == 'CC') {
      _incomingController.text = lastEvent.data1.toString();
    }
  }

  @override
  void dispose() {
    _incomingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(l10n.ccNewMappingTitle),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Incoming CC number ───────────────────────────────────
              TextField(
                controller: _incomingController,
                decoration: InputDecoration(labelText: l10n.ccIncomingLabel),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: 16),

              // ── Category picker ──────────────────────────────────────
              DropdownButtonFormField<_TargetCategory>(
                decoration: const InputDecoration(labelText: 'Target category'),
                initialValue: _category,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                      value: _TargetCategory.gmCc,
                      child: Text('Standard GM CC')),
                  DropdownMenuItem(
                      value: _TargetCategory.instruments,
                      child: Text('Instruments')),
                  DropdownMenuItem(
                      value: _TargetCategory.audioEffects,
                      child: Text('Audio Effects')),
                  DropdownMenuItem(
                      value: _TargetCategory.midiFx,
                      child: Text('MIDI FX')),
                  DropdownMenuItem(
                      value: _TargetCategory.looper,
                      child: Text('Looper')),
                  DropdownMenuItem(
                      value: _TargetCategory.transport,
                      child: Text('Transport')),
                  DropdownMenuItem(
                      value: _TargetCategory.global,
                      child: Text('Global')),
                  DropdownMenuItem(
                      value: _TargetCategory.macros,
                      child: Text('Macros')),
                ],
                onChanged: (val) => setState(() {
                  _category = val;
                  _selectedSlotId = null;
                  _selectedParamKey = null;
                }),
              ),
              const SizedBox(height: 16),

              // ── Category-specific sub-picker ─────────────────────────
              if (_category != null) _buildSubPicker(context),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionCancel),
        ),
        ElevatedButton(
          onPressed: _canSave ? () => _save(context) : null,
          child: Text(l10n.ccSaveBinding),
        ),
      ],
    );
  }

  bool get _canSave =>
      int.tryParse(_incomingController.text) != null && _buildTarget() != null;

  // ── Sub-pickers per category ───────────────────────────────────────────

  Widget _buildSubPicker(BuildContext context) {
    return switch (_category!) {
      _TargetCategory.gmCc => _buildGmCcPicker(context),
      _TargetCategory.instruments => _buildSlotParamPicker(context, _instrumentSlots),
      _TargetCategory.audioEffects => _buildSlotParamPicker(context, _audioEffectSlots),
      _TargetCategory.midiFx => _buildSlotParamPicker(context, _midiFxSlots),
      _TargetCategory.looper => _buildSystemPicker(context, _looperActions),
      _TargetCategory.transport => _buildTransportPicker(),
      _TargetCategory.global => _buildGlobalPicker(),
      _TargetCategory.macros => _buildSwapPicker(context),
    };
  }

  /// GM CC remapping: pick target CC + channel routing.
  Widget _buildGmCcPicker(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ccItems = <DropdownMenuItem<int>>[];
    for (int i = 0; i <= 127; i++) {
      if (CcMappingService.standardGmCcs.containsKey(i)) {
        ccItems.add(DropdownMenuItem(
            value: i,
            child: Text(l10n.ccTargetEffectFormat(
                CcMappingService.standardGmCcs[i]!, i))));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<int>(
          decoration: InputDecoration(labelText: l10n.ccTargetEffectLabel),
          initialValue: _gmTargetCc,
          isExpanded: true,
          items: ccItems,
          onChanged: (val) => setState(() => _gmTargetCc = val ?? 74),
        ),
        const SizedBox(height: 12),
        _buildChannelDropdown(
          l10n,
          _gmTargetChannel,
          (val) => setState(() => _gmTargetChannel = val),
        ),
      ],
    );
  }

  /// Slot parameter picker: slot dropdown + parameter dropdown.
  Widget _buildSlotParamPicker(
    BuildContext context,
    List<_SlotInfo> slots,
  ) {
    if (slots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('No slots of this type in the rack.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Slot dropdown.
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Slot'),
          initialValue: _selectedSlotId,
          isExpanded: true,
          items: slots
              .map((s) => DropdownMenuItem(
                  value: s.slotId, child: Text(s.displayName)))
              .toList(),
          onChanged: (val) => setState(() {
            _selectedSlotId = val;
            _selectedParamKey = null;
          }),
        ),
        if (_selectedSlotId != null) ...[
          const SizedBox(height: 12),
          // Parameter dropdown.
          _buildParamDropdown(slots),
        ],
      ],
    );
  }

  Widget _buildParamDropdown(List<_SlotInfo> slots) {
    final slot = slots.where((s) => s.slotId == _selectedSlotId).firstOrNull;
    if (slot == null) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(labelText: 'Parameter'),
      initialValue: _selectedParamKey,
      isExpanded: true,
      items: slot.params
          .map((p) => DropdownMenuItem(
              value: p.paramKey, child: Text(p.displayName)))
          .toList(),
      onChanged: (val) => setState(() => _selectedParamKey = val),
    );
  }

  /// Legacy system actions (looper).
  Widget _buildSystemPicker(
    BuildContext context,
    Map<int, String> actions,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<int>(
          decoration: InputDecoration(labelText: l10n.ccTargetEffectLabel),
          initialValue: _systemAction,
          isExpanded: true,
          items: actions.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: (val) => setState(() {
            _systemAction = val ?? 1009;
            if (!CcMappingService.isMuteAction(_systemAction)) {
              _muteChannels = {};
            }
          }),
        ),
        if (!CcMappingService.isLooperAction(_systemAction) &&
            !CcMappingService.isMuteAction(_systemAction)) ...[
          const SizedBox(height: 12),
          _buildChannelDropdown(
            l10n,
            _systemChannel,
            (val) => setState(() => _systemChannel = val),
          ),
        ],
        if (CcMappingService.isMuteAction(_systemAction)) ...[
          const SizedBox(height: 12),
          _MuteChannelSelector(
            selected: _muteChannels,
            onChanged: (val) => setState(() => _muteChannels = val),
          ),
        ],
      ],
    );
  }

  Widget _buildTransportPicker() {
    return DropdownButtonFormField<TransportAction>(
      decoration: const InputDecoration(labelText: 'Action'),
      initialValue: _transportAction,
      isExpanded: true,
      items: const [
        DropdownMenuItem(
            value: TransportAction.playStop, child: Text('Play / Stop')),
        DropdownMenuItem(
            value: TransportAction.tapTempo, child: Text('Tap Tempo')),
        DropdownMenuItem(
            value: TransportAction.metronomeToggle,
            child: Text('Metronome Toggle')),
      ],
      onChanged: (val) =>
          setState(() => _transportAction = val ?? TransportAction.playStop),
    );
  }

  Widget _buildGlobalPicker() {
    // Only system volume for now — show as a simple confirmation.
    return const Padding(
      padding: EdgeInsets.all(8),
      child: Text('CC 0-127 \u2192 System media volume (0-100%)',
          style: TextStyle(color: Colors.grey)),
    );
  }

  Widget _buildSwapPicker(BuildContext context) {
    final instruments = _instrumentSlots;
    if (instruments.length < 2) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('Need at least 2 instrument slots in the rack.',
            style: TextStyle(color: Colors.grey)),
      );
    }
    final items = instruments
        .map((s) =>
            DropdownMenuItem(value: s.slotId, child: Text(s.displayName)))
        .toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Instrument A'),
          initialValue: _swapSlotA,
          isExpanded: true,
          items: items,
          onChanged: (val) => setState(() => _swapSlotA = val),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(labelText: 'Instrument B'),
          initialValue: _swapSlotB,
          isExpanded: true,
          items: items,
          onChanged: (val) => setState(() => _swapSlotB = val),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Swap cables (effect chains, Jam Mode links)',
              style: TextStyle(fontSize: 13)),
          value: _swapCables,
          onChanged: (val) => setState(() => _swapCables = val ?? true),
        ),
      ],
    );
  }

  // ── Shared widgets ─────────────────────────────────────────────────────

  Widget _buildChannelDropdown(
    AppLocalizations l10n,
    int currentChannel,
    ValueChanged<int> onChanged,
  ) {
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(labelText: l10n.ccTargetChannelLabel),
      initialValue: currentChannel,
      items: [
        DropdownMenuItem(value: -2, child: Text(l10n.ccRoutingSameAsIncoming)),
        DropdownMenuItem(value: -1, child: Text(l10n.ccRoutingAllChannels)),
        for (int i = 0; i < 16; i++)
          DropdownMenuItem(value: i, child: Text(l10n.ccRoutingChannel(i + 1))),
      ],
      onChanged: (val) => onChanged(val ?? -2),
    );
  }

  // ── Slot helpers ───────────────────────────────────────────────────────

  /// Returns instrument slots (GF Keyboard + Vocoder) with their CC params.
  List<_SlotInfo> get _instrumentSlots {
    final rack = context.read<RackState>();
    final result = <_SlotInfo>[];
    for (final p in rack.plugins) {
      if (p is GrooveForgeKeyboardPlugin) {
        result.add(_SlotInfo(
          slotId: p.id,
          displayName: p.displayName,
          params: CcParamRegistry.forPluginId('_gf_keyboard') ?? [],
        ));
      } else if (p is GFpaPluginInstance &&
          p.pluginId == 'com.grooveforge.vocoder') {
        result.add(_SlotInfo(
          slotId: p.id,
          displayName: p.displayName,
          params: CcParamRegistry.forPluginId(p.pluginId) ?? [],
        ));
      }
    }
    return result;
  }

  /// Returns audio effect slots with their CC params.
  List<_SlotInfo> get _audioEffectSlots =>
      _gfpaSlotsWithParams(_audioEffectPluginIds);

  /// Returns MIDI FX slots with their CC params.
  List<_SlotInfo> get _midiFxSlots =>
      _gfpaSlotsWithParams(_midiFxPluginIds);

  List<_SlotInfo> _gfpaSlotsWithParams(Set<String> pluginIds) {
    final rack = context.read<RackState>();
    final result = <_SlotInfo>[];
    for (final p in rack.plugins) {
      if (p is GFpaPluginInstance && pluginIds.contains(p.pluginId)) {
        final params = CcParamRegistry.forPluginId(p.pluginId);
        if (params != null && params.isNotEmpty) {
          result.add(_SlotInfo(
            slotId: p.id,
            displayName: p.displayName,
            params: params,
          ));
        }
      }
    }
    return result;
  }

  static const _audioEffectPluginIds = {
    'com.grooveforge.reverb',
    'com.grooveforge.delay',
    'com.grooveforge.eq',
    'com.grooveforge.compressor',
    'com.grooveforge.chorus',
    'com.grooveforge.wah',
  };

  static const _midiFxPluginIds = {
    'com.grooveforge.arpeggiator',
    'com.grooveforge.chord',
    'com.grooveforge.transposer',
    'com.grooveforge.velocity_curve',
    'com.grooveforge.gate',
    'com.grooveforge.harmonizer',
    'com.grooveforge.jammode',
  };

  static const Map<int, String> _looperActions = {
    1009: '[Looper] Loop Button',
    1012: '[Looper] Stop',
  };

  // ── Build & save target ────────────────────────────────────────────────

  CcMappingTarget? _buildTarget() => switch (_category) {
        null => null,
        _TargetCategory.gmCc => GmCcTarget(
            targetCc: _gmTargetCc, targetChannel: _gmTargetChannel),
        _TargetCategory.looper => SystemTarget(
            actionCode: _systemAction, targetChannel: _systemChannel,
            muteChannels:
                CcMappingService.isMuteAction(_systemAction) && _muteChannels.isNotEmpty
                    ? _muteChannels : null),
        _TargetCategory.instruments ||
        _TargetCategory.audioEffects ||
        _TargetCategory.midiFx =>
          (_selectedSlotId != null && _selectedParamKey != null)
              ? SlotParamTarget(
                  slotId: _selectedSlotId!,
                  paramKey: _selectedParamKey!,
                  mode: _resolveMode(),
                )
              : null,
        _TargetCategory.transport =>
          TransportTarget(action: _transportAction),
        _TargetCategory.global =>
          const GlobalTarget(action: GlobalAction.systemVolume),
        _TargetCategory.macros =>
          (_swapSlotA != null && _swapSlotB != null && _swapSlotA != _swapSlotB)
              ? SwapTarget(
                  slotIdA: _swapSlotA!,
                  slotIdB: _swapSlotB!,
                  swapCables: _swapCables,
                )
              : null,
      };

  /// Resolves the CC param mode from the registry for the selected slot+param.
  CcParamMode _resolveMode() {
    if (_selectedSlotId == null || _selectedParamKey == null) {
      return CcParamMode.absolute;
    }
    final rack = context.read<RackState>();
    final plugin =
        rack.plugins.where((p) => p.id == _selectedSlotId).firstOrNull;
    final pluginId = (plugin is GFpaPluginInstance)
        ? plugin.pluginId
        : (plugin is GrooveForgeKeyboardPlugin)
            ? '_gf_keyboard'
            : null;
    if (pluginId == null) return CcParamMode.absolute;
    final entry = CcParamRegistry.findParam(pluginId, _selectedParamKey!);
    return entry?.defaultMode ?? CcParamMode.absolute;
  }

  void _save(BuildContext context) {
    final incoming = int.tryParse(_incomingController.text);
    final target = _buildTarget();
    if (incoming == null || target == null) return;
    widget.ccService.addMapping(CcMapping(incomingCc: incoming, target: target));
    // Mark project dirty so autosave captures the change.
    context.read<RackState>().markDirty();
    Navigator.pop(context);
  }
}

/// Info about a rack slot and its CC-controllable parameters.
class _SlotInfo {
  final String slotId;
  final String displayName;
  final List<CcParamEntry> params;

  const _SlotInfo({
    required this.slotId,
    required this.displayName,
    required this.params,
  });
}

// ── Mute channel selector (unchanged from original) ──────────────────────────

class _MuteChannelSelector extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  const _MuteChannelSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.ccMuteChannelsLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 0,
          children: List.generate(16, (i) {
            final isChecked = selected.contains(i);
            return SizedBox(
              width: 72,
              child: CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title:
                    Text('Ch ${i + 1}', style: const TextStyle(fontSize: 12)),
                value: isChecked,
                onChanged: (_) {
                  final updated = Set<int>.from(selected);
                  isChecked ? updated.remove(i) : updated.add(i);
                  onChanged(updated);
                },
              ),
            );
          }),
        ),
      ],
    );
  }
}
