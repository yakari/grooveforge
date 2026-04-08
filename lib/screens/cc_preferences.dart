import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/models/grooveforge_keyboard_plugin.dart';
import 'package:grooveforge/models/plugin_instance.dart';
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
        l10n.ccSwapDisplayLabel(_slotDisplayName(rack, slotIdA), _slotDisplayName(rack, slotIdB)),
      TransportTarget(:final action) => _transportLabel(action, l10n),
      GlobalTarget(:final action) => _globalLabel(action, l10n),
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
        swapCables ? l10n.ccSwapCablesYes : l10n.ccSwapCablesNo,
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

  /// Human-readable display name for a rack slot, disambiguated with MIDI
  /// channel and rack position so identical plugin names are distinguishable.
  String _slotDisplayName(RackState rack, String slotId) {
    final plugins = rack.plugins;
    for (int i = 0; i < plugins.length; i++) {
      if (plugins[i].id != slotId) continue;
      final p = plugins[i];
      final ch = p.midiChannel > 0 ? 'Ch ${p.midiChannel}' : null;
      final suffix = ch != null ? ' ($ch, #${i + 1})' : ' (#${i + 1})';
      return '${p.displayName}$suffix';
    }
    return slotId;
  }

  String _transportLabel(TransportAction action, [AppLocalizations? l10n]) =>
      switch (action) {
        TransportAction.playStop => l10n?.ccTransportPlayStop ?? 'Play / Stop',
        TransportAction.tapTempo => l10n?.ccTransportTapTempo ?? 'Tap Tempo',
        TransportAction.metronomeToggle =>
          l10n?.ccTransportMetronomeToggle ?? 'Metronome Toggle',
      };

  String _globalLabel(GlobalAction action, [AppLocalizations? l10n]) =>
      switch (action) {
        GlobalAction.systemVolume =>
          l10n?.ccGlobalSystemVolume ?? 'System Volume',
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
                decoration: InputDecoration(labelText: l10n.ccCategoryTargetLabel),
                initialValue: _category,
                isExpanded: true,
                items: [
                  DropdownMenuItem(
                      value: _TargetCategory.gmCc,
                      child: Text(l10n.ccCategoryGmCc)),
                  DropdownMenuItem(
                      value: _TargetCategory.instruments,
                      child: Text(l10n.ccCategoryInstruments)),
                  DropdownMenuItem(
                      value: _TargetCategory.audioEffects,
                      child: Text(l10n.ccCategoryAudioEffects)),
                  DropdownMenuItem(
                      value: _TargetCategory.midiFx,
                      child: Text(l10n.ccCategoryMidiFx)),
                  DropdownMenuItem(
                      value: _TargetCategory.looper,
                      child: Text(l10n.ccCategoryLooper)),
                  DropdownMenuItem(
                      value: _TargetCategory.transport,
                      child: Text(l10n.ccCategoryTransport)),
                  DropdownMenuItem(
                      value: _TargetCategory.global,
                      child: Text(l10n.ccCategoryGlobal)),
                  DropdownMenuItem(
                      value: _TargetCategory.macros,
                      child: Text(l10n.ccCategoryChannelSwap)),
                ],
                onChanged: (val) => setState(() {
                  _category = val;
                  _selectedSlotId = null;
                  _selectedParamKey = null;
                  // Reset system action to the first valid entry for the
                  // selected category so the dropdown never receives an
                  // initialValue that doesn't match any item.
                  if (val == _TargetCategory.looper) {
                    _systemAction = _looperActions.keys.first;
                  }
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
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(AppLocalizations.of(context)!.ccNoSlotsOfType,
            style: const TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Slot dropdown.
        DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: AppLocalizations.of(context)!.ccSlotPickerLabel),
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
      decoration: InputDecoration(labelText: AppLocalizations.of(context)!.ccParamPickerLabel),
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
          // Clamp to a valid entry so the dropdown never receives a value
          // absent from the items list.
          initialValue: actions.containsKey(_systemAction)
              ? _systemAction
              : actions.keys.first,
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
    final l10n = AppLocalizations.of(context)!;
    return DropdownButtonFormField<TransportAction>(
      decoration: InputDecoration(labelText: l10n.ccActionPickerLabel),
      initialValue: _transportAction,
      isExpanded: true,
      items: [
        DropdownMenuItem(
            value: TransportAction.playStop,
            child: Text(l10n.ccTransportPlayStop)),
        DropdownMenuItem(
            value: TransportAction.tapTempo,
            child: Text(l10n.ccTransportTapTempo)),
        DropdownMenuItem(
            value: TransportAction.metronomeToggle,
            child: Text(l10n.ccTransportMetronomeToggle)),
      ],
      onChanged: (val) =>
          setState(() => _transportAction = val ?? TransportAction.playStop),
    );
  }

  Widget _buildGlobalPicker() {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(l10n.ccGlobalSystemVolumeHint,
          style: const TextStyle(color: Colors.grey)),
    );
  }

  Widget _buildSwapPicker(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final instruments = _instrumentSlots;
    if (instruments.length < 2) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(l10n.ccSwapNeedTwoSlots,
            style: const TextStyle(color: Colors.grey)),
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
          decoration: InputDecoration(labelText: l10n.ccSwapInstrumentA),
          initialValue: _swapSlotA,
          isExpanded: true,
          items: items,
          onChanged: (val) => setState(() => _swapSlotA = val),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: l10n.ccSwapInstrumentB),
          initialValue: _swapSlotB,
          isExpanded: true,
          items: items,
          onChanged: (val) => setState(() => _swapSlotB = val),
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.ccSwapCablesLabel,
              style: const TextStyle(fontSize: 13)),
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

  /// Builds a display name that disambiguates duplicate plugin names by
  /// appending the MIDI channel and rack position (1-based).
  /// Example: "GF Keyboard (Ch 1, #1)" vs "GF Keyboard (Ch 2, #3)".
  String _disambiguatedName(PluginInstance p, int position) {
    final ch = p.midiChannel > 0 ? 'Ch ${p.midiChannel}' : null;
    final suffix = ch != null ? ' ($ch, #$position)' : ' (#$position)';
    return '${p.displayName}$suffix';
  }

  /// Returns instrument slots (GF Keyboard + Vocoder) with their CC params.
  List<_SlotInfo> get _instrumentSlots {
    final rack = context.read<RackState>();
    final result = <_SlotInfo>[];
    for (int i = 0; i < rack.plugins.length; i++) {
      final p = rack.plugins[i];
      if (p is GrooveForgeKeyboardPlugin) {
        result.add(_SlotInfo(
          slotId: p.id,
          displayName: _disambiguatedName(p, i + 1),
          params: CcParamRegistry.forPluginId('_gf_keyboard') ?? [],
        ));
      } else if (p is GFpaPluginInstance &&
          p.pluginId == 'com.grooveforge.vocoder') {
        result.add(_SlotInfo(
          slotId: p.id,
          displayName: _disambiguatedName(p, i + 1),
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
    for (int i = 0; i < rack.plugins.length; i++) {
      final p = rack.plugins[i];
      if (p is GFpaPluginInstance && pluginIds.contains(p.pluginId)) {
        final params = CcParamRegistry.forPluginId(p.pluginId);
        if (params != null && params.isNotEmpty) {
          result.add(_SlotInfo(
            slotId: p.id,
            displayName: _disambiguatedName(p, i + 1),
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
