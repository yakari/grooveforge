import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'cc_mapping_service.dart';

class CcPreferencesScreen extends StatelessWidget {
  const CcPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ccService = context.read<CcMappingService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('CC Mapping Preferences'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildLastReceivedCard(ccService),
            const SizedBox(height: 24),
            const Text('Active Mappings', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: _buildMappingsList(ccService),
            ),
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

  Widget _buildLastReceivedCard(CcMappingService ccService) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Icon(Icons.monitor_heart, size: 48, color: Colors.teal),
            const SizedBox(height: 16),
            ValueListenableBuilder<int?>(
              valueListenable: ccService.lastReceivedCcNotifier,
              builder: (context, cc, _) {
                return ValueListenableBuilder<int?>(
                  valueListenable: ccService.lastReceivedValueNotifier,
                  builder: (context, value, _) {
                    if (cc == null) {
                      return const Text('Waiting for incoming CC...', style: TextStyle(fontSize: 18));
                    }
                    return Text(
                      'Last Received CC: $cc (Value: $value)',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Move a slider or knob on your MIDI hardware controller to instantly identify its internal CC number here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMappingsList(CcMappingService ccService) {
    return ValueListenableBuilder<Map<int, int>>(
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
        
        final entries = mappings.entries.toList();
        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.swap_horiz, color: Colors.blueAccent),
                title: Text('Hardware CC ${entry.key} ➔ Mapped to CC ${entry.value}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  onPressed: () => ccService.removeMapping(entry.key),
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
    final targetController = TextEditingController();

    // If we have a last received CC, prefill the incoming field with it
    if (ccService.lastReceivedCcNotifier.value != null) {
      incomingController.text = ccService.lastReceivedCcNotifier.value.toString();
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New CC Mapping'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: incomingController,
                decoration: const InputDecoration(labelText: 'Incoming Hardware CC (e.g., 20)'),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: targetController,
                decoration: const InputDecoration(labelText: 'Target General MIDI CC (e.g., 74)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final incoming = int.tryParse(incomingController.text);
                final target = int.tryParse(targetController.text);
                if (incoming != null && target != null) {
                  ccService.saveMapping(incoming, target);
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Save Override'),
            ),
          ],
        );
      },
    );
  }
}
