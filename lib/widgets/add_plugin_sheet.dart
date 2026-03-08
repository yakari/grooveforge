import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/vst3_plugin_instance.dart';
import '../services/rack_state.dart';

/// Bottom sheet that lets the user choose which plugin type to add to the rack.
///
/// Always available:
///   • GrooveForge Keyboard (built-in synth/vocoder)
///
/// Desktop only (Linux / macOS / Windows):
///   • Browse VST3 Plugin… (Phase 2 — currently a stub showing "coming soon")
void showAddPluginSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _AddPluginSheetContent(),
  );
}

class _AddPluginSheetContent extends StatelessWidget {
  const _AddPluginSheetContent();

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              l10n.rackAddPlugin,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            _PluginTile(
              icon: Icons.piano,
              iconColor: Colors.deepPurpleAccent,
              title: l10n.rackAddGrooveForgeKeyboard,
              subtitle: l10n.rackAddGrooveForgeKeyboardSubtitle,
              onTap: () {
                Navigator.pop(context);
                final ch = rack.nextAvailableMidiChannel();
                if (ch == -1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('All 16 MIDI channels are already in use.'),
                    ),
                  );
                  return;
                }
                rack.addPlugin(
                  GrooveForgeKeyboardPlugin(
                    id: rack.generateSlotId(),
                    midiChannel: ch,
                  ),
                );
              },
            ),
            if (_isDesktop)
              _PluginTile(
                icon: Icons.extension,
                iconColor: Colors.tealAccent,
                title: l10n.rackAddVst3,
                subtitle: l10n.rackAddVst3Subtitle,
                onTap: () {
                  Navigator.pop(context);
                  // Phase 2: launch VST3 file picker and load via VstHostService.
                  // For now, insert a placeholder instance.
                  final ch = rack.nextAvailableMidiChannel();
                  if (ch == -1) return;
                  rack.addPlugin(
                    Vst3PluginInstance(
                      id: rack.generateSlotId(),
                      midiChannel: ch,
                      path: '',
                      pluginName: 'VST3 Plugin (coming in v2.1)',
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PluginTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PluginTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: iconColor.withValues(alpha: 0.15),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      onTap: onTap,
    );
  }
}
