import 'package:flutter/material.dart';

import '../../models/vst3_plugin_instance.dart';
import '../../l10n/app_localizations.dart';

/// Rack slot body for an external [Vst3PluginInstance].
///
/// On desktop (Linux/macOS/Windows) this will eventually show VST3 parameter
/// controls (Phase 2). For now and on mobile, it renders an informational
/// placeholder.
class Vst3SlotUI extends StatelessWidget {
  final Vst3PluginInstance plugin;

  const Vst3SlotUI({super.key, required this.plugin});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const Icon(Icons.extension_off, color: Colors.white38, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plugin.pluginName,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.rackPluginUnavailableOnMobile,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
