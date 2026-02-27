import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grooveforge/services/audio_engine.dart';

class JamSessionWidget extends StatelessWidget {
  const JamSessionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isNarrow = MediaQuery.of(context).size.width < 800;

    // Pins to sidebar in narrow landscape or top in portrait
    if (isLandscape && isNarrow) {
      return _buildVerticalSidebar(context, engine);
    } else {
      return _buildHorizontalHeader(context, engine);
    }
  }

  Widget _buildHorizontalHeader(BuildContext context, AudioEngine engine) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              Colors.deepPurple.withValues(alpha: 0.1),
              Colors.blue.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            _buildStartStopButton(engine),
            _buildMasterDropdown(engine),
            _buildSlavesSection(context, engine),
            _buildScaleDropdown(engine),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalSidebar(BuildContext context, AudioEngine engine) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(right: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 120,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.deepPurple.withValues(alpha: 0.1),
              Colors.blue.withValues(alpha: 0.1),
            ],
          ),
        ),
        child: Column(
          children: [
            const Text(
              'JAM',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            _buildStartStopButton(engine, isVertical: true),
            const Divider(height: 32),
            const Text(
              'MASTER',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
            _buildMasterDropdown(engine, isVertical: true),
            const SizedBox(height: 16),
            const Text(
              'SLAVES',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
            _buildSlavesSection(context, engine, isVertical: true),
            const SizedBox(height: 16),
            const Text(
              'SCALE',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
            _buildScaleDropdown(engine, isVertical: true),
          ],
        ),
      ),
    );
  }

  Widget _buildStartStopButton(AudioEngine engine, {bool isVertical = false}) {
    return ValueListenableBuilder<bool>(
      valueListenable: engine.jamEnabled,
      builder: (context, enabled, _) {
        return ElevatedButton.icon(
          onPressed: () {
            engine.jamEnabled.value = !engine.jamEnabled.value;
            engine.toastNotifier.value =
                'Jam Mode: ${engine.jamEnabled.value ? "STARTED" : "STOPPED"}';
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: enabled ? Colors.redAccent : Colors.greenAccent,
            foregroundColor: Colors.black87,
            padding: EdgeInsets.symmetric(
              horizontal: isVertical ? 8 : 16,
              vertical: 12,
            ),
          ),
          icon: Icon(enabled ? Icons.stop : Icons.play_arrow, size: 20),
          label: Text(
            enabled ? 'STOP' : 'JAM',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }

  Widget _buildMasterDropdown(AudioEngine engine, {bool isVertical = false}) {
    return ValueListenableBuilder<int>(
      valueListenable: engine.jamMasterChannel,
      builder: (context, master, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isVertical)
              const Icon(Icons.star, color: Colors.amber, size: 16),
            if (!isVertical) const SizedBox(width: 4),
            DropdownButton<int>(
              value: master,
              underline: const SizedBox(),
              items: List.generate(
                16,
                (i) => DropdownMenuItem(value: i, child: Text('CH ${i + 1}')),
              ),
              onChanged: (val) {
                if (val != null) engine.jamMasterChannel.value = val;
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildSlavesSection(
    BuildContext context,
    AudioEngine engine, {
    bool isVertical = false,
  }) {
    return ValueListenableBuilder<Set<int>>(
      valueListenable: engine.jamSlaveChannels,
      builder: (context, slaves, _) {
        return InkWell(
          onTap: () => _showSlaveSelectDialog(context, engine),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link, size: 16, color: Colors.blueAccent),
                const SizedBox(width: 4),
                Text(
                  isVertical ? '${slaves.length}' : '${slaves.length} Slaves',
                  style: const TextStyle(fontSize: 12),
                ),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildScaleDropdown(AudioEngine engine, {bool isVertical = false}) {
    return ValueListenableBuilder<ScaleType>(
      valueListenable: engine.jamScaleType,
      builder: (context, scale, _) {
        return DropdownButton<ScaleType>(
          value: scale,
          underline: const SizedBox(),
          icon: isVertical ? const SizedBox() : null,
          items:
              ScaleType.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        s.name.toUpperCase(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (val) {
            if (val != null) engine.jamScaleType.value = val;
          },
        );
      },
    );
  }

  void _showSlaveSelectDialog(BuildContext context, AudioEngine engine) {
    Set<int> tempSlaves = Set.from(engine.jamSlaveChannels.value);
    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Select Slave Channels'),
                content: SizedBox(
                  width: 300,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(16, (i) {
                      bool isMaster = i == engine.jamMasterChannel.value;
                      bool isSelected = tempSlaves.contains(i);
                      return FilterChip(
                        label: Text('CH ${i + 1}'),
                        selected: isSelected,
                        onSelected:
                            isMaster
                                ? null
                                : (val) {
                                  setDialogState(() {
                                    if (val) {
                                      tempSlaves.add(i);
                                    } else {
                                      tempSlaves.remove(i);
                                    }
                                  });
                                },
                        selectedColor: Colors.blueAccent.withValues(alpha: 0.3),
                      );
                    }),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      engine.jamSlaveChannels.value = tempSlaves;
                      Navigator.pop(context);
                    },
                    child: const Text('SAVE'),
                  ),
                ],
              );
            },
          ),
    );
  }
}
