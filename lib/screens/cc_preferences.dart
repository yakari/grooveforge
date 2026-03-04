import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      appBar: AppBar(title: const Text('CC Mapping Preferences')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildLastReceivedCard(ccService),
            const SizedBox(height: 24),
            const Text(
              'Active Mappings',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildMappingsList(ccService)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddMappingDialog(context, ccService),
        icon: const Icon(Icons.add),
        label: const Text('Add Mapping'),
      ),
    );
  }

  /// Builds the top card that displays the most recent incoming MIDI event.
  ///
  /// This acts as a diagnostic tool, allowing users to physically move a slider
  /// on their MIDI controller and instantly see which CC number it transmits,
  /// simplifying the mapping process.
  Widget _buildLastReceivedCard(CcMappingService ccService) {
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
                  return const Text(
                    'Waiting for incoming MIDI events...',
                    style: TextStyle(fontSize: 18),
                  );
                }

                String eventText;
                if (event.type == 'CC') {
                  eventText = 'CC ${event.data1} (Value: ${event.data2})';
                } else {
                  eventText =
                      '${event.type} Note ${event.data1} (Velocity: ${event.data2})';
                }

                return Column(
                  children: [
                    Text(
                      'Last Event: $eventText',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Received on Channel ${event.channel + 1}',
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
            const Text(
              'Move a slider or play a note on your MIDI hardware controller to instantly identify its internal event data here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingsList(CcMappingService ccService) {
    return ValueListenableBuilder<Map<int, CcMapping>>(
      valueListenable: ccService.mappingsNotifier,
      builder: (context, mappings, _) {
        if (mappings.isEmpty) {
          return const Center(
            child: Text(
              'No custom mappings defined.\nClick below to add one.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey),
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
                'CC ${mapping.targetCc}';

            String channelStr;
            if (mapping.targetChannel == -1) {
              channelStr = 'All Channels';
            } else if (mapping.targetChannel == -2) {
              channelStr = 'Same as Incoming';
            } else {
              channelStr = 'Channel ${mapping.targetChannel + 1}';
            }

            return Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.blueAccent),
                title: Text(
                  'Hardware CC ${mapping.incomingCc} \u2794 Mapped to $targetName',
                ),
                subtitle: Text('Routing: $channelStr'),
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
      const DropdownMenuItem(value: -2, child: Text('Same as Incoming')),
      const DropdownMenuItem(value: -1, child: Text('All Channels')),
    ];
    for (int i = 0; i < 16; i++) {
      channelItems.add(
        DropdownMenuItem(value: i, child: Text('Channel ${i + 1}')),
      );
    }

    final List<DropdownMenuItem<int>> ccItems = [];
    for (int i = 0; i <= 127; i++) {
      if (CcMappingService.standardGmCcs.containsKey(i)) {
        String name = CcMappingService.standardGmCcs[i]!;
        ccItems.add(DropdownMenuItem(value: i, child: Text('$name (CC $i)')));
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
              title: const Text('New CC Mapping'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: incomingController,
                      decoration: const InputDecoration(
                        labelText: 'Incoming Hardware CC (e.g., 20)',
                      ),
                      keyboardType: TextInputType.number,
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      decoration: const InputDecoration(
                        labelText: 'Target GM Effect',
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
                      decoration: const InputDecoration(
                        labelText: 'Target Channel',
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
                  child: const Text('Cancel'),
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
                  child: const Text('Save Binding'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
