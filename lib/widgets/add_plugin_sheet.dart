import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/grooveforge_keyboard_plugin.dart';
import '../models/looper_plugin_instance.dart';
import '../services/looper_engine.dart';
import '../services/rack_state.dart';
import '../services/vst_host_service.dart'; // re-exports Vst3PluginType

/// Bottom sheet that lets the user choose which plugin type to add to the rack.
///
/// Always available:
///   • GrooveForge Keyboard (built-in FluidSynth keyboard)
///
/// Desktop only (Linux / macOS / Windows):
///   • Browse VST3 Plugin… — folder picker or pick from installed list
void showAddPluginSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
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

  /// Loads and adds a VST3 plugin of the given [pluginType].
  // ── Descriptor plugin helpers ────────────────────────────────────────────

  /// Add a descriptor-backed plugin (identified by [pluginId]) to the rack.
  ///
  /// The plugin must already be registered in [GFPluginRegistry] (all bundled
  /// `.gfpd` plugins are loaded at app startup in `main.dart`). Descriptor
  /// plugins are audio effects — they use `midiChannel: 0` and need no MIDI
  /// channel allocation.
  void _addDescriptorPlugin(
    BuildContext context,
    RackState rack,
    String pluginId,
  ) {
    final registered = GFPluginRegistry.instance.findById(pluginId);
    if (registered == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Plugin not found: $pluginId')),
      );
      return;
    }
    Navigator.pop(context);
    rack.addPlugin(
      GFpaPluginInstance(
        id: rack.generateSlotId(),
        pluginId: pluginId,
        midiChannel: 0, // effects do not use MIDI channels
      ),
    );
  }

  /// Let the user pick a `.gfpd` file from device storage and add it to the
  /// rack. The file is parsed by [GFDescriptorLoader.loadAndRegister], which
  /// also adds it to [GFPluginRegistry] for future use in this session.
  Future<void> _loadGfpdFromFile(BuildContext context, RackState rack) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gfpd'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    try {
      final content = await File(path).readAsString();
      final plugin = GFDescriptorLoader.loadAndRegister(content);
      if (plugin == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to parse .gfpd file.')),
          );
        }
        return;
      }
      if (context.mounted) {
        Navigator.pop(context);
        rack.addPlugin(
          GFpaPluginInstance(
            id: rack.generateSlotId(),
            pluginId: plugin.pluginId,
            midiChannel: 0,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading file: $e')),
        );
      }
    }
  }

  ///
  /// Instrument plugins are assigned the next free MIDI channel.
  /// Effect plugins use midiChannel == 0 (no MIDI routing).
  Future<void> _loadAndAdd(
    BuildContext context,
    String bundlePath, {
    Vst3PluginType pluginType = Vst3PluginType.instrument,
  }) async {
    final rack = context.read<RackState>();
    final vstSvc = context.read<VstHostService>();
    final l10n = AppLocalizations.of(context)!;

    // Only instrument plugins need a MIDI channel.
    final int ch;
    if (pluginType == Vst3PluginType.instrument) {
      ch = rack.nextAvailableMidiChannel();
      if (ch == -1) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('All 16 MIDI channels are already in use.')),
        );
        return;
      }
    } else {
      ch = 0; // Effects process audio, no MIDI channel needed.
    }

    setState(() => _loading = true);

    await vstSvc.initialize();
    final slotId = rack.generateSlotId();
    final instance = await vstSvc.loadPlugin(
      bundlePath,
      slotId,
      pluginType: pluginType,
    );

    setState(() => _loading = false);

    if (!context.mounted) return;

    if (instance != null) {
      rack.addPlugin(pluginType == Vst3PluginType.instrument
          ? instance.copyWith(midiChannel: ch)
          : instance);
      vstSvc.startAudio();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.vst3LoadFailed)),
      );
    }
  }

  // ─── Browse for .vst3 folder ──────────────────────────────────────────────

  /// Opens a directory picker for the given [pluginType] and loads the bundle.
  Future<void> _browseVst3Folder(
      BuildContext context, Vst3PluginType pluginType) async {
    final l10n = AppLocalizations.of(context)!;

    final dialogTitle = pluginType == Vst3PluginType.effect
        ? l10n.vst3BrowseEffectTitle
        : l10n.vst3BrowseInstrumentTitle;

    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
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
    await _loadAndAdd(context, bundlePath, pluginType: pluginType);
  }

  // ─── Pick from installed plugins ──────────────────────────────────────────

  /// Shows the installed plugin picker for the given [pluginType].
  Future<void> _pickFromInstalled(
      BuildContext context, Vst3PluginType pluginType) async {
    final vstSvc = context.read<VstHostService>();
    await vstSvc.initialize();

    final found =
        await vstSvc.scanPluginPaths(VstHostService.defaultSearchPaths);

    if (!context.mounted) return;

    if (found.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.vst3ScanNoneFound)),
      );
      return;
    }

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _InstalledPluginsDialog(paths: found),
    );
    if (picked == null || !context.mounted) return;

    Navigator.pop(context);
    await _loadAndAdd(context, picked, pluginType: pluginType);
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();

    return SafeArea(
      child: ConstrainedBox(
        // isScrollControlled lets the sheet grow to full screen height; cap it
        // at 80% so it never fully obscures the rack behind it.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
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
                // Enforce single-instance limit: only one Jam Mode allowed.
                final hasJamMode = rack.plugins
                    .whereType<GFpaPluginInstance>()
                    .any((p) => p.pluginId == 'com.grooveforge.jammode');
                if (hasJamMode) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.addJamModeAlreadyExists)),
                  );
                  return;
                }
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

            // ── Stylophone (GFPA monophonic strip instrument)
            _PluginTile(
              icon: Icons.linear_scale,
              iconColor: Colors.blueGrey,
              title: l10n.rackAddStylophone,
              subtitle: l10n.rackAddStyloPhoneSubtitle,
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
                    pluginId: 'com.grooveforge.stylophone',
                    midiChannel: ch,
                  ),
                );
              },
            ),

            // ── Theremin (GFPA touch-controlled pitch & volume)
            _PluginTile(
              icon: Icons.sensors,
              iconColor: Colors.deepPurpleAccent,
              title: l10n.rackAddTheremin,
              subtitle: l10n.rackAddThereminSubtitle,
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
                    pluginId: 'com.grooveforge.theremin',
                    midiChannel: ch,
                  ),
                );
              },
            ),

            // ═══════════════════════════════════════════════════════════════
            // MIDI Looper
            // ═══════════════════════════════════════════════════════════════

            // ── MIDI Looper
            _PluginTile(
              icon: Icons.loop,
              iconColor: Colors.greenAccent,
              title: l10n.addLooper,
              subtitle: l10n.addLooperSubtitle,
              onTap: () {
                // Enforce single-instance limit: only one Looper allowed.
                final hasLooper =
                    rack.plugins.whereType<LooperPluginInstance>().isNotEmpty;
                if (hasLooper) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.addLooperAlreadyExists)),
                  );
                  return;
                }
                Navigator.pop(context);
                final slotId = rack.generateSlotId();
                final looper = LooperPluginInstance(id: slotId);
                rack.addPlugin(looper);
                // Register a session in the engine as soon as the slot is added.
                context.read<LooperEngine>().ensureSession(slotId);
              },
            ),

            // ═══════════════════════════════════════════════════════════════
            // Built-in GFPA Effects (.gfpd descriptor plugins — all platforms)
            // ═══════════════════════════════════════════════════════════════
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.rackAddEffectsSectionLabel,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),

            _PluginTile(
              icon: Icons.blur_on,
              iconColor: Colors.lightBlueAccent,
              title: l10n.rackAddReverb,
              subtitle: l10n.rackAddReverbSubtitle,
              onTap: () => _addDescriptorPlugin(
                context, rack, 'com.grooveforge.reverb',
              ),
            ),
            _PluginTile(
              icon: Icons.repeat,
              iconColor: Colors.tealAccent,
              title: l10n.rackAddDelay,
              subtitle: l10n.rackAddDelaySubtitle,
              onTap: () => _addDescriptorPlugin(
                context, rack, 'com.grooveforge.delay',
              ),
            ),
            _PluginTile(
              icon: Icons.graphic_eq,
              iconColor: Colors.orangeAccent,
              title: l10n.rackAddWah,
              subtitle: l10n.rackAddWahSubtitle,
              onTap: () => _addDescriptorPlugin(
                context, rack, 'com.grooveforge.wah',
              ),
            ),
            _PluginTile(
              icon: Icons.equalizer,
              iconColor: Colors.greenAccent,
              title: l10n.rackAddEq,
              subtitle: l10n.rackAddEqSubtitle,
              onTap: () => _addDescriptorPlugin(
                context, rack, 'com.grooveforge.eq',
              ),
            ),
            _PluginTile(
              icon: Icons.compress,
              iconColor: Colors.purpleAccent,
              title: l10n.rackAddCompressor,
              subtitle: l10n.rackAddCompressorSubtitle,
              onTap: () => _addDescriptorPlugin(
                context, rack, 'com.grooveforge.compressor',
              ),
            ),
            _PluginTile(
              icon: Icons.waves,
              iconColor: Colors.cyanAccent,
              title: l10n.rackAddChorus,
              subtitle: l10n.rackAddChorusSubtitle,
              onTap: () => _addDescriptorPlugin(
                context, rack, 'com.grooveforge.chorus',
              ),
            ),

            // ═══════════════════════════════════════════════════════════════
            // Built-in MIDI FX (.gfpd descriptor plugins — all platforms)
            // ═══════════════════════════════════════════════════════════════
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l10n.rackAddMidiFxSectionLabel,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
            ),
            _PluginTile(
              icon: Icons.music_note,
              iconColor: Colors.pinkAccent,
              title: l10n.rackAddHarmonizer,
              subtitle: l10n.rackAddHarmonizerSubtitle,
              onTap: () => _addDescriptorPlugin(
                context, rack, 'com.grooveforge.harmonizer',
              ),
            ),
            _PluginTile(
              icon: Icons.piano,
              iconColor: Colors.purpleAccent,
              title: l10n.rackAddChordExpand,
              subtitle: l10n.rackAddChordExpandSubtitle,
              onTap: () => _addDescriptorPlugin(
                context, rack, 'com.grooveforge.chord',
              ),
            ),

            // ── Load a custom .gfpd plugin from storage
            _PluginTile(
              icon: Icons.file_open,
              iconColor: Colors.white54,
              title: l10n.rackAddLoadGfpd,
              subtitle: l10n.rackAddLoadGfpdSubtitle,
              onTap: () => _loadGfpdFromFile(context, rack),
            ),

            // ── VST3 (desktop only) ─────────────────────────────────────
            // Instrument and effect are shown as separate tiles so the user
            // can declare intent upfront. The type is stored in the model
            // and drives the rack slot UI and back-panel jack layout.
            if (_isDesktop) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  l10n.rackAddVstSectionLabel,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
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
                // ── VST3 Instrument ──────────────────────────────────────
                _PluginTile(
                  icon: Icons.folder_open,
                  iconColor: Colors.tealAccent,
                  title: l10n.vst3BrowseInstrumentTitle,
                  subtitle: l10n.vst3BrowseInstrumentSubtitle,
                  onTap: () => _browseVst3Folder(
                      context, Vst3PluginType.instrument),
                ),
                _PluginTile(
                  icon: Icons.extension,
                  iconColor: Colors.amber,
                  title: l10n.vst3PickInstalledInstrumentTitle,
                  subtitle: l10n.vst3PickInstalledSubtitle,
                  onTap: () => _pickFromInstalled(
                      context, Vst3PluginType.instrument),
                ),
                // ── VST3 Effect ──────────────────────────────────────────
                _PluginTile(
                  icon: Icons.folder_open,
                  iconColor: const Color(0xFFBB86FC),
                  title: l10n.vst3BrowseEffectTitle,
                  subtitle: l10n.vst3BrowseEffectSubtitle,
                  onTap: () => _browseVst3Folder(
                      context, Vst3PluginType.effect),
                ),
                _PluginTile(
                  icon: Icons.auto_fix_high,
                  iconColor: Colors.deepPurpleAccent,
                  title: l10n.vst3PickInstalledEffectTitle,
                  subtitle: l10n.vst3PickInstalledSubtitle,
                  onTap: () => _pickFromInstalled(
                      context, Vst3PluginType.effect),
                ),
              ],
            ],

            const SizedBox(height: 8),
          ],
        ),
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
