import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/virtual_piano_plugin.dart';

/// Front-panel body for a [VirtualPianoPlugin] rack slot.
///
/// The slot's main UI is the on-screen piano keyboard rendered by
/// [RackSlotWidget] (via [_showPiano]). This body adds a subtle info row
/// reminding the user that the keyboard's notes are routed via the MIDI OUT
/// jack visible in the patch view — not through the built-in FluidSynth
/// engine of a regular Keyboard slot.
class VirtualPianoSlotUI extends StatelessWidget {
  /// The plugin instance backing this slot.
  final VirtualPianoPlugin plugin;

  const VirtualPianoSlotUI({super.key, required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.cable_outlined, size: 14, color: Colors.white38),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.virtualPianoSlotHint,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
