import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/transport_engine.dart';
import '../l10n/app_localizations.dart';

/// A widget that displays global transport controls: Play/Stop, BPM, Tap Tempo.
class TransportBar extends StatelessWidget {
  const TransportBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black45,
      child: Consumer<TransportEngine>(
        builder: (context, transport, child) {
          final isPlaying = transport.isPlaying;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Play/Stop button
              IconButton(
                icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                color: isPlaying ? Colors.redAccent : Colors.greenAccent,
                tooltip: isPlaying ? l10n.transportStop : l10n.transportPlay,
                iconSize: 32,
                onPressed: () {
                  if (isPlaying) {
                    transport.stop();
                  } else {
                    transport.play();
                  }
                },
              ),
              const SizedBox(width: 16),

              // BPM display and input
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showBpmDialog(context, transport),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          transport.bpm.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          l10n.transportBpm,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),

              // Tap Tempo button
              ElevatedButton(
                onPressed: () => transport.tapTempo(),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  l10n.transportTapTempo.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),

              // Time Signature indicator
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${transport.timeSigNumerator} / ${transport.timeSigDenominator}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    l10n.transportTimeSignature,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBpmDialog(BuildContext context, TransportEngine transport) {
    final TextEditingController controller = TextEditingController(
      text: transport.bpm.toStringAsFixed(1),
    );
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.transportBpm),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. 120.0',
            suffixText: l10n.transportBpm,
          ),
          onSubmitted: (value) {
            _updateBpm(ctx, transport, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () {
              _updateBpm(ctx, transport, controller.text);
            },
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
  }

  void _updateBpm(BuildContext context, TransportEngine transport, String value) {
    // Replace commas with dots for locales that use comma as decimal separator
    final normalizedValue = value.replaceAll(',', '.');
    final bpm = double.tryParse(normalizedValue);
    if (bpm != null && bpm > 0) {
      transport.bpm = bpm;
    }
    Navigator.pop(context);
  }
}
