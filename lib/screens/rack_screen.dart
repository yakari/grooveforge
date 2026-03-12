import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/vst3_plugin_instance.dart';
import '../services/audio_engine.dart';
import '../services/cc_mapping_service.dart';
import '../services/midi_service.dart';
import '../services/project_service.dart';
import '../services/rack_state.dart';
import '../services/vst_host_service.dart';
import '../services/transport_engine.dart';
import '../widgets/add_plugin_sheet.dart';
import '../widgets/rack_slot_widget.dart';
import '../widgets/transport_bar.dart';
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
  // GlobalKeys per slot id, used by ensureVisible in auto-scroll.
  final Map<String, GlobalKey> _slotKeys = {};

  @override
  void initState() {
    super.initState();
    debugPrint('RackScreen: initState START');
    final midiService = context.read<MidiService>();
    final engine = context.read<AudioEngine>();
    final ccMappingService = context.read<CcMappingService>();

    engine.ccMappingService = ccMappingService;
    midiService.onMidiDataReceived = (packet) {
      // If a VST3 slot owns this MIDI channel, send only to the VST3 plugin
      // and skip FluidSynth entirely — otherwise the soundfont plays in parallel.
      if (!_routeMidiToVst3Plugins(packet)) {
        engine.processMidiPacket(packet);
      }
    };

    ccMappingService.lastEventNotifier.addListener(() {
      final event = ccMappingService.lastEventNotifier.value;
      if (event != null && mounted) _handleAutoScroll(event.channel);
    });

    _toastListener = () {
      final msg = engine.toastNotifier.value;
      if (msg != null && mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
        );
      }
    };
        engine.toastNotifier.addListener(_toastListener!);

    _newDeviceSubscription = midiService.onNewDeviceDetected.listen((device) {
      if (mounted) _showNewDeviceModal(device);
    });

    // Auto-show welcome guide for new versions.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion =
          '${packageInfo.version}+${packageInfo.buildNumber}';
      if (engine.lastSeenVersion.value != currentVersion) {
        if (mounted) {
          _showUserGuide();
          engine.markWelcomeAsSeen(currentVersion);
        }
      }
    });
    debugPrint('RackScreen: initState END');
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

  /// Routes incoming MIDI messages to VST3 rack slots on the matching channel.
  ///
  /// Returns `true` if at least one VST3 slot claims the incoming MIDI channel,
  /// which tells the caller to skip FluidSynth for this packet.
  bool _routeMidiToVst3Plugins(MidiPacket packet) {
    if (packet.data.isEmpty) return false;
    final statusByte = packet.data[0];
    final midiChannel = (statusByte & 0x0F) + 1; // 0-based → 1-based

    final rack = context.read<RackState>();
    final vst3Slots = rack.plugins
        .whereType<Vst3PluginInstance>()
        .where((p) => p.midiChannel == midiChannel)
        .toList();

    if (vst3Slots.isEmpty) return false;

    // Forward note-on/off to each VST3 plugin on this channel.
    final command = statusByte & 0xF0;
    if ((command == 0x90 || command == 0x80) && packet.data.length >= 2) {
      final vstSvc = context.read<VstHostService>();
      final note = packet.data[1];
      final velocity = packet.data.length >= 3 ? packet.data[2] : 0;

      for (final plugin in vst3Slots) {
        if (command == 0x90 && velocity > 0) {
          vstSvc.noteOn(plugin.id, 0, note, velocity / 127.0);
        } else {
          vstSvc.noteOff(plugin.id, 0, note);
        }
      }
    }

    // Return true for any MIDI status on a VST3 channel so FluidSynth is skipped.
    return true;
  }

  void _handleAutoScroll(int channel) {
    final engine = context.read<AudioEngine>();
    if (!engine.autoScrollEnabled.value) return;
    if (!_scrollController.hasClients) return;

    final rack = context.read<RackState>();
    final slotIndex = rack.plugins.indexWhere(
      (p) => p.midiChannel - 1 == channel,
    );
    if (slotIndex == -1) return;

    // Slots now have variable height; scroll to the registered key if possible.
    final key = _slotKeys[rack.plugins[slotIndex].id];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        alignment: 0.1,
      );
    }
  }

  // ─── Project I/O ────────────────────────────────────────────────────────────

  Future<void> _openProject() async {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();
    final engine = context.read<AudioEngine>();
    final transport = context.read<TransportEngine>();
    final service = context.read<ProjectService>();

    final path = await service.openProject(rack, engine, transport);
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
    final transport = context.read<TransportEngine>();
    final service = context.read<ProjectService>();

    final path = await service.saveProjectAs(rack, engine, transport);
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
    debugPrint('RackScreen: build START');
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
      body: OrientationBuilder(
        builder: (context, orientation) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final isMobileLandscape = orientation == Orientation.landscape &&
                  constraints.maxHeight < 480;
              return Padding(
                padding: const EdgeInsets.all(2.0),
                child: Column(
                  children: [
                    const TransportBar(),
                    Expanded(
                      child: _RackList(
                        scrollController: _scrollController,
                        isMobileLandscape: isMobileLandscape,
                        slotKeys: _slotKeys,
                      ),
                    ),
                  ],
                ),
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
  final Map<String, GlobalKey> slotKeys;

  const _RackList({
    required this.scrollController,
    required this.isMobileLandscape,
    required this.slotKeys,
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

            if (rack.plugins.isEmpty) {
              return Center(
                child: Text(
                  AppLocalizations.of(context)!.rackAddPlugin,
                  style: const TextStyle(color: Colors.white38),
                ),
              );
            }

            // Piano height: fixed size that works well across screen sizes.
            // Landscape mobile gets a shorter piano to preserve vertical space.
            final pianoHeight = isMobileLandscape ? 90.0 : 140.0;

            return ReorderableListView.builder(
              scrollController: scrollController,
              buildDefaultDragHandles: false,
              physics: interacting
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 88),
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
                debugPrint('RackList: building item $index for plugin ${plugin.id}');
                final slotKey =
                    slotKeys.putIfAbsent(plugin.id, () => GlobalKey());
                return KeyedSubtree(
                  key: ValueKey(plugin.id),
                  child: RackSlotWidget(
                    key: slotKey,
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
  }
}
