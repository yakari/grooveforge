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
    return ValueListenableBuilder<Map<int, CcMapping>>(
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

        final entries = mappings.values.toList();
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final mapping = entries[index];

            String targetName =
                CcMappingService.standardGmCcs[mapping.targetCc] ??
                AppLocalizations.of(
                  context,
                )!.ccUnknownSequence(mapping.targetCc);

            String channelStr;
            if (mapping.targetChannel == -1) {
              channelStr = AppLocalizations.of(context)!.ccRoutingAllChannels;
            } else if (mapping.targetChannel == -2) {
              channelStr =
                  AppLocalizations.of(context)!.ccRoutingSameAsIncoming;
            } else {
              channelStr = AppLocalizations.of(
                context,
              )!.ccRoutingChannel(mapping.targetChannel + 1);
            }

            return Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.blueAccent),
                title: Text(
                  AppLocalizations.of(
                    context,
                  )!.ccMappingHardwareToTarget(mapping.incomingCc, targetName),
                ),
                subtitle: Text(
                  AppLocalizations.of(context)!.ccMappingRouting(channelStr),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => ccService.removeMapping(mapping.incomingCc),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddMappingDialog(BuildContext context, CcMappingService ccService) {
    final incomingController = TextEditingController();

    int targetCc = 74; // default to filter cutoff (frequent target)
    int targetChannel = -2; // default to Same Channel

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
                        if (val != null) setState(() => targetCc = val);
                      },
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText:
                            AppLocalizations.of(context)!.ccTargetChannelLabel,
                      ),
                      initialValue: targetChannel,
                      items: channelItems,
                      onChanged: (val) {
                        if (val != null) setState(() => targetChannel = val);
                      },
                    ),
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
                      final mapping = CcMapping(
                        incomingCc: incoming,
                        targetCc: targetCc,
                        targetChannel: targetChannel,
                      );
                      ccService.saveMapping(mapping);
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
