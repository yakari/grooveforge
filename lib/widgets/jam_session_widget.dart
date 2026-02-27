import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grooveforge/services/audio_engine.dart';

class JamSessionWidget extends StatelessWidget {
  final bool? forceVertical;
  const JamSessionWidget({super.key, this.forceVertical});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<AudioEngine>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final isNarrow = MediaQuery.of(context).size.width < 800;

    // Use forced orientation if provided, otherwise fallback to responsive logic
    final useVertical = forceVertical ?? (isLandscape && isNarrow);

    if (useVertical) {
      return _buildVerticalSidebar(context, engine);
    } else {
      return _buildHorizontalHeader(context, engine);
    }
  }

  Widget _buildHorizontalHeader(BuildContext context, AudioEngine engine) {
    return Align(
      alignment: Alignment.center,
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildStartStopButton(engine),
              _buildMasterDropdown(engine),
              _buildSlavesSection(context, engine),
              _buildScaleDropdown(engine),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalSidebar(BuildContext context, AudioEngine engine) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Container(
        width: 110,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.deepPurple.withValues(alpha: 0.15),
              Colors.blue.withValues(alpha: 0.15),
            ],
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildStartStopButton(engine, isVertical: true),
            const Divider(height: 32, indent: 12, endIndent: 12),
            _buildMasterDropdown(engine, isVertical: true),
            const SizedBox(height: 16),
            _buildSlavesSection(context, engine, isVertical: true),
            const Spacer(),
            _buildScaleDropdown(engine, isVertical: true),
            const SizedBox(height: 12),
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
            elevation: isVertical ? 2 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(isVertical ? 12 : 8),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isVertical ? 12 : 12,
              vertical: isVertical ? 16 : 8,
            ),
          ),
          icon: Icon(
            enabled ? Icons.stop : Icons.play_arrow,
            size: isVertical ? 18 : 18,
          ),
          label: Text(
            enabled ? 'STOP' : 'JAM',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: isVertical ? 12 : 13,
              letterSpacing: isVertical ? 1.0 : null,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMasterDropdown(AudioEngine engine, {bool isVertical = false}) {
    return ValueListenableBuilder<int>(
      valueListenable: engine.jamMasterChannel,
      builder: (context, master, _) {
        final dropdown = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isVertical)
              const Icon(Icons.star, color: Colors.amber, size: 14),
            const SizedBox(width: 4),
            DropdownButton<int>(
              value: master,
              underline: const SizedBox(),
              style:
                  isVertical
                      ? const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      )
                      : const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                      ),
              items: List.generate(
                16,
                (i) => DropdownMenuItem(
                  value: i,
                  child: Text(isVertical ? '${i + 1}' : 'CH ${i + 1}'),
                ),
              ),
              onChanged: (val) {
                if (val != null) engine.jamMasterChannel.value = val;
              },
            ),
          ],
        );

        return _buildLabeledControl('Master', dropdown, isVertical: isVertical);
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
        final content = InkWell(
          onTap: () => _showSlaveSelectDialog(context, engine),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 10,
              vertical: isVertical ? 6 : 4,
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.blueAccent.withValues(alpha: 0.3),
              ),
              borderRadius: BorderRadius.circular(8),
              color: Colors.blueAccent.withValues(alpha: 0.05),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.link, size: 16, color: Colors.blueAccent),
                const SizedBox(width: 4),
                Text(
                  '${slaves.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (!isVertical) const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        );

        return _buildLabeledControl('Slaves', content, isVertical: isVertical);
      },
    );
  }

  Widget _buildScaleDropdown(AudioEngine engine, {bool isVertical = false}) {
    return ValueListenableBuilder<ScaleType>(
      valueListenable: engine.jamScaleType,
      builder: (context, scale, _) {
        final dropdown = DropdownButton<ScaleType>(
          value: scale,
          underline: const SizedBox(),
          isExpanded: isVertical,
          alignment: isVertical ? Alignment.center : Alignment.centerLeft,
          dropdownColor: Theme.of(context).cardColor,
          icon: isVertical ? const SizedBox() : null,
          items:
              ScaleType.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      alignment:
                          isVertical ? Alignment.center : Alignment.centerLeft,
                      child: Text(
                        s.name.toUpperCase(),
                        textAlign:
                            isVertical ? TextAlign.center : TextAlign.start,
                        style: TextStyle(
                          fontSize: isVertical ? 10 : 12,
                          fontWeight: FontWeight.bold,
                          color: isVertical ? null : Colors.blueAccent,
                        ),
                      ),
                    ),
                  )
                  .toList(),
          onChanged: (val) {
            if (val != null) engine.jamScaleType.value = val;
          },
        );

        return _buildLabeledControl('Scale', dropdown, isVertical: isVertical);
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

  Widget _buildLabeledControl(
    String label,
    Widget control, {
    required bool isVertical,
  }) {
    if (isVertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildLabel(label), control],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${label.toUpperCase()}:',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.blueAccent.withValues(alpha: 0.6),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        control,
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: Colors.blueAccent.withValues(alpha: 0.7),
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
