import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../services/rack_state.dart';
import '../services/vst_host_service.dart';

/// Bottom sheet that lets the user choose which plugin type to add to the rack.
///
/// Always available:
///   • GrooveForge Keyboard (built-in synth/vocoder)
///
/// Desktop only (Linux / macOS / Windows):
///   • Browse VST3 Plugin… — folder picker or pick from installed list
void showAddPluginSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => const _AddPluginSheetContent(),
  );
}

class _AddPluginSheetContent extends StatefulWidget {
  const _AddPluginSheetContent();

  @override
  State<_AddPluginSheetContent> createState() => _AddPluginSheetContentState();
}

class _AddPluginSheetContentState extends State<_AddPluginSheetContent> {
  bool _loading = false;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  // ─── Internal loader ──────────────────────────────────────────────────────

  /// Resolves the `.vst3` bundle directory from any path the user might give:
  /// - If [rawPath] already ends with `.vst3` and is a directory → use as-is.
  /// - If [rawPath] is inside a `.vst3` bundle → walk up until we find it.
  /// Returns null if no `.vst3` ancestor is found.
  String? _resolveBundlePath(String rawPath) {
    // Direct bundle dir
    if (rawPath.endsWith('.vst3') &&
        FileSystemEntity.isDirectorySync(rawPath)) {
      return rawPath;
    }
    // Walk up from any file inside the bundle
    var dir = File(rawPath).parent;
    while (dir.path != dir.parent.path) {
      if (dir.path.endsWith('.vst3')) return dir.path;
      dir = dir.parent;
    }
    return null;
  }

  Future<void> _loadAndAdd(BuildContext context, String bundlePath) async {
    final rack = context.read<RackState>();
    final vstSvc = context.read<VstHostService>();
    final l10n = AppLocalizations.of(context)!;

    final ch = rack.nextAvailableMidiChannel();
    if (ch == -1) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All 16 MIDI channels are already in use.')),
      );
      return;
    }

    setState(() => _loading = true);

    await vstSvc.initialize();
    final slotId = rack.generateSlotId();
    final instance = await vstSvc.loadPlugin(bundlePath, slotId);

    setState(() => _loading = false);

    if (!context.mounted) return;

    if (instance != null) {
      rack.addPlugin(instance.copyWith(midiChannel: ch));
      vstSvc.startAudio();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.vst3LoadFailed)),
      );
    }
  }

  // ─── Browse for .vst3 folder ──────────────────────────────────────────────

  Future<void> _browseVst3Folder(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    // Use directory picker — .vst3 bundles are directories on Linux/macOS.
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.vst3BrowseTitle,
    );
    if (selected == null) return;

    final bundlePath = _resolveBundlePath(selected);
    if (bundlePath == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.vst3NotABundle)),
      );
      return;
    }

    if (!context.mounted) return;
    Navigator.pop(context);
    await _loadAndAdd(context, bundlePath);
  }

  // ─── Pick from installed plugins ──────────────────────────────────────────

  Future<void> _pickFromInstalled(BuildContext context) async {
    final vstSvc = context.read<VstHostService>();
    await vstSvc.initialize();

    final found = await vstSvc.scanPluginPaths(VstHostService.defaultSearchPaths);

    if (!context.mounted) return;

    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.vst3ScanNoneFound)),
      );
      return;
    }

    // Show a dialog listing the found .vst3 bundles.
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _InstalledPluginsDialog(paths: found),
    );
    if (picked == null || !context.mounted) return;

    Navigator.pop(context);
    await _loadAndAdd(context, picked);
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

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

            // ── Built-in keyboard
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

            // ── Vocoder (GFPA instrument)
            _PluginTile(
              icon: Icons.mic,
              iconColor: Colors.cyanAccent,
              title: l10n.rackAddVocoder,
              subtitle: l10n.rackAddVocoderSubtitle,
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
                  GFpaPluginInstance(
                    id: rack.generateSlotId(),
                    pluginId: 'com.grooveforge.vocoder',
                    midiChannel: ch,
                  ),
                );
              },
            ),

            // ── Jam Mode (GFPA MIDI FX)
            _PluginTile(
              icon: Icons.link,
              iconColor: Colors.amberAccent,
              title: l10n.rackAddJamMode,
              subtitle: l10n.rackAddJamModeSubtitle,
              onTap: () {
                Navigator.pop(context);
                rack.addPlugin(
                  GFpaPluginInstance(
                    id: rack.generateSlotId(),
                    pluginId: 'com.grooveforge.jammode',
                    midiChannel: 0,
                  ),
                );
              },
            ),

            // ── VST3 (desktop only)
            if (_isDesktop) ...[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Loading VST3 plugin…'),
                    ],
                  ),
                )
              else ...[
                _PluginTile(
                  icon: Icons.folder_open,
                  iconColor: Colors.tealAccent,
                  title: l10n.vst3BrowseTitle,
                  subtitle: l10n.vst3BrowseSubtitle,
                  onTap: () => _browseVst3Folder(context),
                ),
                _PluginTile(
                  icon: Icons.extension,
                  iconColor: Colors.amber,
                  title: l10n.vst3PickInstalledTitle,
                  subtitle: l10n.vst3PickInstalledSubtitle,
                  onTap: () => _pickFromInstalled(context),
                ),
              ],
            ],

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─── Installed plugins picker dialog ─────────────────────────────────────────

class _InstalledPluginsDialog extends StatelessWidget {
  final List<String> paths;

  const _InstalledPluginsDialog({required this.paths});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.vst3PickInstalledTitle),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 400,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: paths.length,
          itemBuilder: (ctx, i) {
            final path = paths[i];
            final name = path.split('/').last.replaceAll('.vst3', '');
            final dir = path.substring(0, path.lastIndexOf('/'));
            return ListTile(
              leading: const Icon(Icons.extension, color: Colors.tealAccent),
              title: Text(name),
              subtitle: Text(
                dir,
                style: const TextStyle(fontSize: 11, color: Colors.white38),
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => Navigator.pop(context, path),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(l10n.cancelButton),
        ),
      ],
    );
  }
}

// ─── Shared tile widget ───────────────────────────────────────────────────────

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
