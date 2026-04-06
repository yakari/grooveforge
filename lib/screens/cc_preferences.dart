import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';

/// Screen for configuring advanced MIDI Control Change (CC) mappings.
///
/// Allows the user to map hardware MIDI knobs/sliders to internal application features
/// (like changing the Jam Mode scale) or specific General MIDI Effects (like Filter Cutoff).
/// It features a live MIDI event monitor to help users identify the CC number of their hardware controls.
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

  /// Builds the top card that displays the most recent incoming MIDI event.
  ///
  /// This acts as a diagnostic tool, allowing users to physically move a slider
  /// on their MIDI controller and instantly see which CC number it transmits,
  /// simplifying the mapping process.
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

                String eventText;
                if (event.type == 'CC') {
                  eventText = AppLocalizations.of(
                    context,
                  )!.ccLastEventCC(event.data1, event.data2);
                } else {
                  eventText = AppLocalizations.of(
                    context,
                  )!.ccLastEventNote(event.type, event.data1, event.data2);
                }

                return Column(
                  children: [
                    Text(
                      eventText,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppLocalizations.of(
                        context,
                      )!.ccReceivedOnChannel(event.channel + 1),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.blueAccent,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.ccInstructions,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                leading: const Icon(Icons.swap_horiz, color: Colors.blueAccent),
                title: Text(_mappingTitle(context, mapping)),
                subtitle: Text(_mappingSubtitle(context, mapping)),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => ccService.removeMapping(mapping),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Returns the main label for a mapping list tile.
  ///
  /// Dispatches on the sealed [CcMappingTarget] type to produce a human-
  /// readable description of what the mapping does.
  String _mappingTitle(BuildContext context, CcMapping mapping) {
    final l10n = AppLocalizations.of(context)!;
    final targetName = switch (mapping.target) {
      GmCcTarget(:final targetCc) =>
        CcMappingService.standardGmCcs[targetCc] ??
            l10n.ccUnknownSequence(targetCc),
      SystemTarget(:final actionCode) =>
        CcMappingService.standardGmCcs[actionCode] ??
            l10n.ccUnknownSequence(actionCode),
      SlotParamTarget(:final slotId, :final paramKey) =>
        '$paramKey on $slotId',
      SwapTarget(:final slotIdA, :final slotIdB) =>
        'Swap $slotIdA \u2194 $slotIdB',
      TransportTarget(:final action) => 'Transport: ${action.name}',
      GlobalTarget(:final action) => 'Global: ${action.name}',
    };
    return l10n.ccMappingHardwareToTarget(mapping.incomingCc, targetName);
  }

  /// Returns the subtitle for a mapping list tile.
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

  /// Subtitle for legacy system actions — handles mute, looper, and standard routing.
  String _systemSubtitle(BuildContext context, int actionCode,
      int targetChannel, Set<int>? muteChannels) {
    final l10n = AppLocalizations.of(context)!;
    if (CcMappingService.isMuteAction(actionCode)) {
      if (muteChannels == null || muteChannels.isEmpty) {
        return l10n.ccMuteNoChannels;
      }
      final sorted = muteChannels.toList()..sort();
      final label = sorted.map((ch) => (ch + 1).toString()).join(', ');
      return l10n.ccMuteChannelsSummary(label);
    }
    if (CcMappingService.isLooperAction(actionCode)) return '';
    return l10n.ccMappingRouting(_channelLabel(context, targetChannel));
  }

  /// Converts a [targetChannel] value to a human-readable string.
  String _channelLabel(BuildContext context, int targetChannel) {
    if (targetChannel == -1) {
      return AppLocalizations.of(context)!.ccRoutingAllChannels;
    }
    if (targetChannel == -2) {
      return AppLocalizations.of(context)!.ccRoutingSameAsIncoming;
    }
    return AppLocalizations.of(
      context,
    )!.ccRoutingChannel(targetChannel + 1);
  }

  void _showAddMappingDialog(BuildContext context, CcMappingService ccService) {
    final incomingController = TextEditingController();

    int targetCc = 74; // default to filter cutoff (frequent target)
    int targetChannel = -2; // default to Same Channel
    // Channels selected for the mute action (0-based, matching ChannelState indices).
    Set<int> muteChannels = {};

    final lastEvent = ccService.lastEventNotifier.value;
    if (lastEvent != null && lastEvent.type == 'CC') {
      incomingController.text = lastEvent.data1.toString();
    }

    final List<DropdownMenuItem<int>> channelItems = [
      DropdownMenuItem(
        value: -2,
        child: Text(AppLocalizations.of(context)!.ccRoutingSameAsIncoming),
      ),
      DropdownMenuItem(
        value: -1,
        child: Text(AppLocalizations.of(context)!.ccRoutingAllChannels),
      ),
    ];
    for (int i = 0; i < 16; i++) {
      channelItems.add(
        DropdownMenuItem(
          value: i,
          child: Text(AppLocalizations.of(context)!.ccRoutingChannel(i + 1)),
        ),
      );
    }

    final List<DropdownMenuItem<int>> ccItems = [];
    for (int i = 0; i <= 127; i++) {
      if (CcMappingService.standardGmCcs.containsKey(i)) {
        String name = CcMappingService.standardGmCcs[i]!;
        ccItems.add(
          DropdownMenuItem(
            value: i,
            child: Text(
              AppLocalizations.of(context)!.ccTargetEffectFormat(name, i),
            ),
          ),
        );
      }
    }
    CcMappingService.standardGmCcs.forEach((key, name) {
      if (key >= 1000) {
        ccItems.add(DropdownMenuItem(value: key, child: Text(name)));
      }
    });

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            final isLooper = CcMappingService.isLooperAction(targetCc);
            final isMute = CcMappingService.isMuteAction(targetCc);
            // Channel routing is only meaningful for standard (non-system) CCs.
            final showChannelRouting = !isLooper && !isMute;

            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.ccNewMappingTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: incomingController,
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context)!.ccIncomingLabel,
                      ),
                      keyboardType: TextInputType.number,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context)!.ccTargetEffectLabel,
                      ),
                      initialValue: targetCc,
                      isExpanded: true,
                      items: ccItems,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            targetCc = val;
                            // Reset mute-channel selection on action change.
                            if (!CcMappingService.isMuteAction(val)) {
                              muteChannels = {};
                            }
                          });
                        }
                      },
                    ),
                    if (showChannelRouting) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        decoration: InputDecoration(
                          labelText: AppLocalizations.of(
                            context,
                          )!.ccTargetChannelLabel,
                        ),
                        initialValue: targetChannel,
                        items: channelItems,
                        onChanged: (val) {
                          if (val != null) setState(() => targetChannel = val);
                        },
                      ),
                    ],
                    if (isMute) ...[
                      const SizedBox(height: 16),
                      _MuteChannelSelector(
                        selected: muteChannels,
                        onChanged: (updated) =>
                            setState(() => muteChannels = updated),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(AppLocalizations.of(context)!.actionCancel),
                ),
                ElevatedButton(
                  onPressed: () {
                    final incoming = int.tryParse(incomingController.text);
                    if (incoming != null) {
                      // Build the appropriate target type based on the
                      // selected targetCc value.
                      final CcMappingTarget target;
                      if (targetCc >= 1000) {
                        target = SystemTarget(
                          actionCode: targetCc,
                          targetChannel: targetChannel,
                          muteChannels:
                              isMute && muteChannels.isNotEmpty
                                  ? muteChannels
                                  : null,
                        );
                      } else {
                        target = GmCcTarget(
                          targetCc: targetCc,
                          targetChannel: targetChannel,
                        );
                      }
                      ccService.addMapping(
                        CcMapping(incomingCc: incoming, target: target),
                      );
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Text(AppLocalizations.of(context)!.ccSaveBinding),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A checkboxes widget for selecting which MIDI channels (1-16) are targeted
/// by the mute/unmute action (system action 1014).
///
/// Channels are displayed in a 4×4 grid so they fit compactly in the dialog.
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
        // 4 columns × 4 rows = 16 channels
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
                title: Text('Ch ${i + 1}', style: const TextStyle(fontSize: 12)),
                value: isChecked,
                onChanged: (_) {
                  final updated = Set<int>.from(selected);
                  if (isChecked) {
                    updated.remove(i);
                  } else {
                    updated.add(i);
                  }
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
