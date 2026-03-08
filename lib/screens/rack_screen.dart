import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import '../services/audio_engine.dart';
import '../services/cc_mapping_service.dart';
import '../services/midi_service.dart';
import '../services/project_service.dart';
import '../services/rack_state.dart';
import '../widgets/add_plugin_sheet.dart';
import '../widgets/jam_session_widget.dart';
import '../widgets/rack_slot_widget.dart';
import '../widgets/user_guide_modal.dart';
import 'preferences_screen.dart';

/// The main screen of GrooveForge v2: a reorderable plugin rack.
///
/// Replaces [SynthesizerScreen]. Each row in the list is a [RackSlotWidget]
/// backed by a [PluginInstance]. The app bar provides project file I/O
/// (open / save / new). A FAB adds new plugin slots.
class RackScreen extends StatefulWidget {
  const RackScreen({super.key});

  @override
  State<RackScreen> createState() => _RackScreenState();
}

class _RackScreenState extends State<RackScreen> {
  void Function()? _toastListener;
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<MidiDevice>? _newDeviceSubscription;
  String? _currentProjectPath;

  @override
  void initState() {
    super.initState();
    final midiService = context.read<MidiService>();
    final audioEngine = context.read<AudioEngine>();
    final ccMappingService = context.read<CcMappingService>();

    audioEngine.ccMappingService = ccMappingService;
    midiService.onMidiDataReceived = (packet) {
      audioEngine.processMidiPacket(packet);
    };

    ccMappingService.lastEventNotifier.addListener(() {
      final event = ccMappingService.lastEventNotifier.value;
      if (event != null && mounted) _handleAutoScroll(event.channel);
    });

    _toastListener = () {
      final msg = audioEngine.toastNotifier.value;
      if (msg != null && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
    };
    audioEngine.toastNotifier.addListener(_toastListener!);

    _newDeviceSubscription = midiService.onNewDeviceDetected.listen((device) {
      if (mounted) _showNewDeviceModal(device);
    });

    // Auto-show welcome guide for new versions.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion =
          '${packageInfo.version}+${packageInfo.buildNumber}';
      if (audioEngine.lastSeenVersion.value != currentVersion) {
        if (mounted) {
          _showUserGuide();
          audioEngine.markWelcomeAsSeen(currentVersion);
        }
      }
    });
  }

  @override
  void dispose() {
    _newDeviceSubscription?.cancel();
    if (_toastListener != null) {
      context.read<AudioEngine>().toastNotifier.removeListener(_toastListener!);
    }
    _scrollController.dispose();
    super.dispose();
  }

  // ─── Auto-scroll ────────────────────────────────────────────────────────────

  void _handleAutoScroll(int channel) {
    final engine = context.read<AudioEngine>();
    if (!engine.autoScrollEnabled.value) return;
    if (!_scrollController.hasClients) return;

    final rack = context.read<RackState>();
    final slotIndex = rack.plugins.indexWhere(
      (p) => p.midiChannel - 1 == channel,
    );
    if (slotIndex == -1) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final itemHeight = (viewportHeight - 16) / 2;
    final targetOffset = slotIndex * itemHeight;
    final currentPosition = _scrollController.offset;

    if (targetOffset < currentPosition) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else if (targetOffset + itemHeight > currentPosition + viewportHeight) {
      _scrollController.animateTo(
        targetOffset - viewportHeight + itemHeight,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ─── Project I/O ────────────────────────────────────────────────────────────

  Future<void> _openProject() async {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();
    final engine = context.read<AudioEngine>();
    final service = ProjectService();

    final path = await service.openProject(rack, engine);
    if (path != null && mounted) {
      setState(() => _currentProjectPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.rackProjectOpened)),
      );
    }
  }

  Future<void> _saveProjectAs() async {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();
    final engine = context.read<AudioEngine>();
    final service = ProjectService();

    final path = await service.saveProjectAs(rack, engine);
    if (path != null && mounted) {
      setState(() => _currentProjectPath = path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.rackProjectSaved)),
      );
    }
  }

  Future<void> _newProject() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(l10n.rackNewProject,
            style: const TextStyle(color: Colors.white)),
        content: Text(l10n.rackNewProjectConfirm,
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.rackNewProjectButton),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<RackState>().initDefaults();
      setState(() => _currentProjectPath = null);
    }
  }

  // ─── Dialogs ────────────────────────────────────────────────────────────────

  void _showNewDeviceModal(MidiDevice device) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.midiNewDeviceDetected),
        content: Text(l10n.midiConnectNewDevicePrompt(device.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.actionIgnore),
          ),
          ElevatedButton(
            onPressed: () {
              context.read<MidiService>().connect(device);
              Navigator.pop(ctx);
            },
            child: Text(l10n.actionConnect),
          ),
        ],
      ),
    );
  }

  void _showUserGuide() {
    showDialog(context: context, builder: (_) => const UserGuideModal());
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentProjectPath != null
            ? _currentProjectPath!.split('/').last
            : l10n.rackTitle),
        elevation: 2,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.folder_open),
            tooltip: l10n.rackOpenProject,
            onSelected: (value) async {
              switch (value) {
                case 'open':
                  await _openProject();
                case 'save':
                  await _saveProjectAs();
                case 'new':
                  await _newProject();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'open',
                child: ListTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(l10n.rackOpenProject),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: Text(l10n.rackSaveProjectAs),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: 'new',
                child: ListTile(
                  leading: const Icon(Icons.add_box_outlined),
                  title: Text(l10n.rackNewProject),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: l10n.synthTooltipUserGuide,
            onPressed: _showUserGuide,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: l10n.synthTooltipSettings,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PreferencesScreen()),
            ),
          ),
        ],
      ),
      body: Consumer<AudioEngine>(
        builder: (context, audioEngine, _) {
          return ValueListenableBuilder<ScaleLockMode>(
            valueListenable: audioEngine.lockModePreference,
            builder: (context, lockMode, _) {
                  return OrientationBuilder(
                    builder: (context, orientation) {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final isLandscape =
                              orientation == Orientation.landscape;
                          final isMobileLandscape =
                              isLandscape && constraints.maxHeight < 480;
                          final showJamUI = lockMode == ScaleLockMode.jam;

                      final mainContent = _RackList(
                        scrollController: _scrollController,
                        isMobileLandscape: isMobileLandscape,
                      );

                      if (showJamUI) {
                        if (isMobileLandscape) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const JamSessionWidget(forceVertical: true),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: mainContent,
                                ),
                              ),
                            ],
                          );
                        } else {
                          return Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: Column(
                              children: [
                                const JamSessionWidget(forceVertical: false),
                                const SizedBox(height: 2),
                                Expanded(child: mainContent),
                              ],
                            ),
                          );
                        }
                      }

                      return Padding(
                        padding: const EdgeInsets.all(2.0),
                        child: mainContent,
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddPluginSheet(context),
        tooltip: AppLocalizations.of(context)!.rackAddPlugin,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ─── Reorderable rack list ────────────────────────────────────────────────────

class _RackList extends StatelessWidget {
  final ScrollController scrollController;
  final bool isMobileLandscape;

  const _RackList({
    required this.scrollController,
    required this.isMobileLandscape,
  });

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();

    return Consumer<RackState>(
      builder: (context, rack, _) {
        return ListenableBuilder(
          listenable: engine.isGestureInProgress,
          builder: (context, _) {
            final interacting = engine.isGestureInProgress.value;

            return LayoutBuilder(
              builder: (context, constraints) {
                // Each slot takes half the available height in portrait;
                // full height in mobile landscape (one slot fills the screen).
                final slotHeight = isMobileLandscape
                    ? constraints.maxHeight - 8
                    : (constraints.maxHeight - 16) / 2;

                // The piano section is ~40% of the slot height.
                final pianoHeight = (slotHeight * 0.42).clamp(80.0, 260.0);

                if (rack.plugins.isEmpty) {
                  return Center(
                    child: Text(
                      AppLocalizations.of(context)!.rackAddPlugin,
                      style: const TextStyle(color: Colors.white38),
                    ),
                  );
                }

                return ReorderableListView.builder(
                  scrollController: scrollController,
                  physics: interacting
                      ? const NeverScrollableScrollPhysics()
                      : const AlwaysScrollableScrollPhysics(),
                  itemCount: rack.plugins.length,
                  onReorder: rack.reorderPlugins,
                  proxyDecorator: (child, index, animation) => Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.transparent,
                    child: child,
                  ),
                  itemBuilder: (context, index) {
                    final plugin = rack.plugins[index];
                    return SizedBox(
                      key: ValueKey(plugin.id),
                      height: slotHeight,
                      child: RackSlotWidget(
                        plugin: plugin,
                        pianoHeight: pianoHeight,
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
