import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../l10n/app_localizations.dart';
import '../models/audio_port_id.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/virtual_piano_plugin.dart';
import '../models/vst3_plugin_instance.dart';
import '../services/audio_engine.dart';
import '../services/audio_graph.dart';
import '../services/cc_mapping_service.dart';
import '../services/midi_service.dart';
import '../services/patch_drag_controller.dart';
import '../services/project_service.dart';
import '../services/rack_state.dart';
import '../services/vst_host_service.dart';
import '../services/transport_engine.dart';
import '../widgets/add_plugin_sheet.dart';
import '../widgets/patch_cable_overlay.dart';
import '../widgets/rack/slot_back_panel_widget.dart';
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

  /// Controls whether the rack shows front panels (default) or back panels
  /// (patch view) for cable routing.
  final ValueNotifier<bool> _isPatchView = ValueNotifier(false);

  // GlobalKeys per slot id, used by ensureVisible in auto-scroll.
  final Map<String, GlobalKey> _slotKeys = {};

  /// GlobalKeys per jack, keyed by "$slotId:${portId.name}".
  /// Shared between [SlotBackPanelWidget] and [PatchCableOverlay] so the
  /// overlay can resolve jack screen positions for cable rendering.
  final Map<String, GlobalKey> _jackKeys = {};

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
    _isPatchView.dispose();
    super.dispose();
  }

  // ─── Auto-scroll ────────────────────────────────────────────────────────────

  /// Routes incoming MIDI messages to VST3 and [VirtualPianoPlugin] slots on
  /// the matching channel, bypassing FluidSynth.
  ///
  /// - **VST3 slots** receive note events directly via [VstHostService].
  /// - **Virtual Piano slots** act as cable-based MIDI sources: notes are
  ///   scale-snapped for the VP's channel, then forwarded to every slot wired
  ///   to its MIDI OUT jack in [AudioGraph]. This mirrors what [_RackSlotPiano]
  ///   does for on-screen key presses.
  ///
  /// Returns `true` when at least one VST3 or VP slot claims the channel so
  /// the caller can skip [AudioEngine.processMidiPacket] (which would route to
  /// FluidSynth and produce the wrong sound).
  bool _routeMidiToVst3Plugins(MidiPacket packet) {
    if (packet.data.isEmpty) return false;
    final statusByte = packet.data[0];
    final midiChannel = (statusByte & 0x0F) + 1; // 0-based → 1-based

    final rack = context.read<RackState>();
    final vst3Slots = rack.plugins
        .whereType<Vst3PluginInstance>()
        .where((p) => p.midiChannel == midiChannel)
        .toList();
    final vpSlots = rack.plugins
        .whereType<VirtualPianoPlugin>()
        .where((p) => p.midiChannel == midiChannel)
        .toList();

    if (vst3Slots.isEmpty && vpSlots.isEmpty) return false;

    final command = statusByte & 0xF0;
    if ((command == 0x90 || command == 0x80) && packet.data.length >= 2) {
      final vstSvc = context.read<VstHostService>();
      final note = packet.data[1];
      final velocity = packet.data.length >= 3 ? packet.data[2] : 0;
      final isNoteOn = command == 0x90 && velocity > 0;

      // ── Direct VST3 routing ──────────────────────────────────────────────
      for (final plugin in vst3Slots) {
        if (isNoteOn) {
          vstSvc.noteOn(plugin.id, 0, note, velocity / 127.0);
        } else {
          vstSvc.noteOff(plugin.id, 0, note);
        }
      }

      // ── Virtual Piano cable routing ──────────────────────────────────────
      if (vpSlots.isNotEmpty) {
        final engine = context.read<AudioEngine>();
        final audioGraph = context.read<AudioGraph>();
        for (final vp in vpSlots) {
          _routeExternalMidiThroughVp(
            vp: vp,
            note: note,
            velocity: velocity,
            isNoteOn: isNoteOn,
            engine: engine,
            audioGraph: audioGraph,
            vstSvc: vstSvc,
            rack: rack,
          );
        }
      }
    }

    return true;
  }

  /// Routes one external MIDI note event through a [VirtualPianoPlugin]'s
  /// MIDI OUT cable connections.
  ///
  /// Applies scale snapping for the VP's own channel (so Jam Mode affects
  /// external MIDI just as it does on-screen key presses), updates VP's visual
  /// key highlight, then dispatches the snapped note to each downstream slot.
  void _routeExternalMidiThroughVp({
    required VirtualPianoPlugin vp,
    required int note,
    required int velocity,
    required bool isNoteOn,
    required AudioEngine engine,
    required AudioGraph audioGraph,
    required VstHostService vstSvc,
    required RackState rack,
  }) {
    final vpCh = (vp.midiChannel - 1).clamp(0, 15);
    // Scale-snap the note using VP's channel state (Jam Mode / classic lock).
    final snapped = engine.snapNoteForChannel(vpCh, note);

    // Update VP's own key highlight.
    if (isNoteOn) {
      engine.noteOnUiOnly(channel: vpCh, key: note);
    } else {
      engine.noteOffUiOnly(channel: vpCh, key: note);
    }

    // Forward to each slot connected to VP's MIDI OUT jack.
    final cables = audioGraph
        .connectionsFrom(vp.id)
        .where((c) => c.fromPort == AudioPortId.midiOut);
    for (final cable in cables) {
      final target =
          rack.plugins.where((p) => p.id == cable.toSlotId).firstOrNull;
      if (target == null) continue;
      final targetCh = (target.midiChannel - 1).clamp(0, 15);
      if (isNoteOn) {
        if (target is Vst3PluginInstance) {
          vstSvc.noteOn(target.id, 0, snapped, velocity / 127.0);
          engine.noteOnUiOnly(channel: targetCh, key: snapped);
        } else {
          engine.playNote(channel: targetCh, key: snapped, velocity: velocity);
        }
      } else {
        if (target is Vst3PluginInstance) {
          vstSvc.noteOff(target.id, 0, snapped);
          engine.noteOffUiOnly(channel: targetCh, key: snapped);
        } else {
          engine.stopNote(channel: targetCh, key: snapped);
        }
      }
    }
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
    final audioGraph = context.read<AudioGraph>();
    final service = context.read<ProjectService>();

    final path = await service.openProject(rack, engine, transport, audioGraph);
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
    final audioGraph = context.read<AudioGraph>();
    final service = context.read<ProjectService>();

    final path =
        await service.saveProjectAs(rack, engine, transport, audioGraph);
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
      // Clear the audio graph before initialising defaults so stale cables
      // from the previous project don't linger in the patch view.
      context.read<AudioGraph>().clear();
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

  // ─── Drag-end handling (cable drop) ─────────────────────────────────────────

  /// Called when the pointer is released during a cable drag.
  ///
  /// Iterates all registered jack keys — which are keyed by the string
  /// `"$slotId:${portId.name}"` — to find a jack whose render box contains
  /// [globalPos]. If found and compatible with the drag source port, creates
  /// the appropriate connection (MIDI/Audio → AudioGraph, Data → RackState).
  void _handleDragEnd(Offset globalPos) {
    final dragCtrl = context.read<PatchDragController>();
    if (!dragCtrl.isDragging) return;

    final fromSlotId = dragCtrl.fromSlotId!;
    final fromPort = dragCtrl.fromPort!;
    final rack = context.read<RackState>();
    final graph = context.read<AudioGraph>();
    final l10n = AppLocalizations.of(context)!;

    // _jackKeys is Map<String, GlobalKey> where the String key encodes the
    // jack identity as "$slotId:${portId.name}".
    for (final entry in _jackKeys.entries) {
      final jackRenderObject = entry.value.currentContext?.findRenderObject();
      final box = jackRenderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;

      // Check if the pointer landed near this jack circle.
      // Inflate by 20 dp (≈ the jack diameter) for comfortable finger drops.
      final jackRect = box.localToGlobal(Offset.zero) & box.size;
      if (!jackRect.inflate(20).contains(globalPos)) continue;

      // Decode toSlotId and toPort from the map key string.
      // Key format: "$slotId:${portId.name}"
      final colonIdx = entry.key.lastIndexOf(':');
      if (colonIdx == -1) continue;
      final toSlotId = entry.key.substring(0, colonIdx);
      final portName = entry.key.substring(colonIdx + 1);

      AudioPortId toPort;
      try {
        toPort = AudioPortId.values.byName(portName);
      } catch (_) {
        continue;
      }

      // Port is incompatible: skip this jack and keep looking — the drop
      // position may overlap another (compatible) jack in the Wrap layout.
      if (!fromPort.compatibleWith(toPort)) continue;

      // Route to the appropriate service based on port family.
      if (fromPort.isDataPort) {
        _connectDataCable(fromSlotId, fromPort, toSlotId, toPort, rack);
      } else {
        _connectAudioMidiCable(
            fromSlotId, fromPort, toSlotId, toPort, graph, l10n);
      }
      break;
    }

    dragCtrl.endDrag();
  }

  /// Creates a MIDI or Audio cable by calling [AudioGraph.connect].
  void _connectAudioMidiCable(
    String fromSlotId,
    AudioPortId fromPort,
    String toSlotId,
    AudioPortId toPort,
    AudioGraph graph,
    AppLocalizations l10n,
  ) {
    try {
      graph.connect(fromSlotId, fromPort, toSlotId, toPort);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      final msg = e.message as String;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg.contains('ycle') ? l10n.connectionCycleError : msg,
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Routes a data cable drop to the appropriate [RackState] mutation.
  ///
  /// Data cables mirror the existing [GFpaPluginInstance.masterSlotId] and
  /// [GFpaPluginInstance.targetSlotIds] fields, keeping the patch view and
  /// the Jam Mode dropdowns in sync.
  void _connectDataCable(
    String fromSlotId,
    AudioPortId fromPort,
    String toSlotId,
    AudioPortId toPort,
    RackState rack,
  ) {
    if (fromPort == AudioPortId.chordOut && toPort == AudioPortId.chordIn) {
      // Chord cable: designate the keyboard as the Jam Mode master.
      rack.setJamModeMaster(toSlotId, fromSlotId);
    } else if (fromPort == AudioPortId.scaleOut &&
        toPort == AudioPortId.scaleIn) {
      // Scale cable: add this keyboard as a scale-locked target of the jam slot.
      rack.addJamModeTarget(fromSlotId, toSlotId);
    }
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
          // Patch view toggle — shown always, activates back-panel cable UI.
          ValueListenableBuilder<bool>(
            valueListenable: _isPatchView,
            builder: (ctx, isPatch, _) => IconButton(
              icon: Icon(
                isPatch ? Icons.view_agenda_outlined : Icons.cable_outlined,
              ),
              tooltip: l10n.patchViewToggleTooltip,
              onPressed: () => _isPatchView.value = !isPatch,
            ),
          ),
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
                      // ValueListenableBuilder so _RackList and the overlays
                      // rebuild when the patch view is toggled, without
                      // rebuilding the whole Scaffold.
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isPatchView,
                        builder: (ctx, isPatch, _) => Listener(
                          // Track pointer during cable drags.
                          onPointerMove: (e) {
                            if (isPatch) {
                              ctx
                                  .read<PatchDragController>()
                                  .updatePosition(e.position);
                            }
                          },
                          onPointerUp: (e) {
                            if (isPatch) _handleDragEnd(e.position);
                          },
                          child: Stack(
                            children: [
                              _RackList(
                                scrollController: _scrollController,
                                isMobileLandscape: isMobileLandscape,
                                slotKeys: _slotKeys,
                                jackKeys: _jackKeys,
                                isPatchView: isPatch,
                                onFlipToFront: () =>
                                    _isPatchView.value = false,
                              ),
                              // Cable overlays — only active in patch view
                              // so they never intercept front-panel touches
                              // (virtual piano keys, scroll, etc.).
                              if (isPatch) ...[
                                Consumer2<AudioGraph, RackState>(
                                  builder: (ctx2, graph, rack, child) =>
                                      PatchCableOverlay(
                                    graph: graph,
                                    rack: rack,
                                    jackKeys: _jackKeys,
                                  ),
                                ),
                                // Always in tree (not conditional on isDragging)
                                // so its RenderBox is ready the moment a drag
                                // begins. ListenableBuilder inside the widget
                                // drives repaints without an outer Consumer.
                                DragCableOverlay(
                                  controller:
                                      ctx.read<PatchDragController>(),
                                  jackKeys: _jackKeys,
                                ),
                              ],
                            ],
                          ),
                        ),
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

/// The scrollable list of rack slots — renders either front-panel
/// [RackSlotWidget]s or back-panel [SlotBackPanelWidget]s depending on
/// [isPatchView].
class _RackList extends StatelessWidget {
  final ScrollController scrollController;
  final bool isMobileLandscape;
  final Map<String, GlobalKey> slotKeys;

  /// Jack GlobalKeys shared with [PatchCableOverlay] for cable position lookup.
  final Map<String, GlobalKey> jackKeys;

  /// True when the patch (back-panel) view is active.
  final bool isPatchView;

  /// Called when the user taps [FRONT] on a back panel to flip back.
  final VoidCallback onFlipToFront;

  const _RackList({
    required this.scrollController,
    required this.isMobileLandscape,
    required this.slotKeys,
    required this.jackKeys,
    required this.isPatchView,
    required this.onFlipToFront,
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

            // In patch view use a plain ListView — no reorder needed and it
            // avoids gesture conflicts that ReorderableListView introduces
            // (long-press drag recognisers competing with jack long-presses).
            if (isPatchView) {
              return ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: rack.plugins.length,
                itemBuilder: (context, index) {
                  final plugin = rack.plugins[index];
                  return SlotBackPanelWidget(
                    key: ValueKey('back:${plugin.id}'),
                    plugin: plugin,
                    jackKeys: jackKeys,
                    onFlipToFront: onFlipToFront,
                  );
                },
              );
            }

            // Front-panel view: reorderable list with custom drag handles
            // (defined inside RackSlotWidget — buildDefaultDragHandles: false).
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
                debugPrint(
                    'RackList: building item $index for plugin ${plugin.id}');
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
