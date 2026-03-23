import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart'
    show GFEffectPlugin, GFPluginRegistry;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/audio_port_id.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../models/grooveforge_keyboard_plugin.dart';
import '../../models/looper_plugin_instance.dart';
import '../../models/plugin_instance.dart';
import '../../models/vst3_plugin_instance.dart'; // Vst3PluginInstance, Vst3PluginType
import '../../services/audio_graph.dart';
import '../../services/patch_drag_controller.dart';

/// The "back panel" view of a rack slot shown when the patch view is active.
///
/// Lays jacks out horizontally across the full panel width, grouped by signal
/// family (MIDI / Audio / Data) in side-by-side sections. This mirrors the
/// aesthetic of a real hardware rack (e.g. Reason/Rack Extension style).
///
/// Each jack's [GlobalKey] points to the 24×24 circle widget so that
/// [PatchCableOverlay] can compute exact jack-centre positions for bezier
/// cable routing, and [_handleDragEnd] uses the same region as the drop zone.
class SlotBackPanelWidget extends StatelessWidget {
  final PluginInstance plugin;

  /// Jack GlobalKeys keyed by "$slotId:${portId.name}".
  /// Each key is attached to the 24×24 circle [SizedBox] so cable endpoints
  /// land precisely on the jack hole.
  final Map<String, GlobalKey> jackKeys;

  final VoidCallback onFlipToFront;

  const SlotBackPanelWidget({
    super.key,
    required this.plugin,
    required this.jackKeys,
    required this.onFlipToFront,
  });

  // ── Port layout per plugin type ──────────────────────────────────────────

  List<AudioPortId> _portsFor(PluginInstance plugin) {
    if (plugin is LooperPluginInstance) {
      // The looper accepts MIDI IN (to record) and emits MIDI OUT (to replay
      // recorded events to connected instrument / Jam Mode slots).
      return [
        AudioPortId.midiIn,   // records MIDI from connected source
        AudioPortId.midiOut,  // replays recorded MIDI to connected targets
      ];
    }

    if (plugin is GrooveForgeKeyboardPlugin) {
      return [
        AudioPortId.midiIn,
        AudioPortId.midiOut,   // MIDI notes flow out to Jam Mode for scale locking
        AudioPortId.audioOutL,
        AudioPortId.audioOutR,
        AudioPortId.sendOut,
        AudioPortId.chordOut,  // chord data → Jam Mode chordIn
        AudioPortId.scaleIn,   // scale data ← Jam Mode scaleOut
      ];
    }

    if (plugin is GFpaPluginInstance) {
      if (plugin.pluginId == 'com.grooveforge.vocoder') {
        return [
          AudioPortId.midiIn,
          AudioPortId.midiOut,   // MIDI notes flow out to MIDI FX plugins
          AudioPortId.audioInL,
          AudioPortId.audioInR,
          AudioPortId.audioOutL,
          AudioPortId.audioOutR,
          AudioPortId.scaleIn,   // scale data ← Jam Mode scaleOut
        ];
      }
      if (plugin.pluginId == 'com.grooveforge.jammode') {
        return [
          AudioPortId.midiIn,
          AudioPortId.midiOut,
          AudioPortId.chordIn,
          AudioPortId.scaleOut,
        ];
      }
      // Theremin and Stylophone expose a MIDI OUT jack so they can drive
      // connected instruments (GFK, VST3, etc.) as expressive MIDI controllers.
      if (plugin.pluginId == 'com.grooveforge.stylophone' ||
          plugin.pluginId == 'com.grooveforge.theremin') {
        return [
          AudioPortId.midiIn,
          AudioPortId.midiOut,
          AudioPortId.audioOutL,
          AudioPortId.audioOutR,
        ];
      }
      // Look up the plugin type from the registry. Descriptor-based effect
      // plugins (GFEffectPlugin) process audio: they need stereo IN + OUT and
      // no MIDI jack. Unknown or unregistered plugins fall back to instrument
      // layout (MIDI IN + audio OUT) to match the pre-existing behaviour.
      final registered = GFPluginRegistry.instance.findById(plugin.pluginId);
      if (registered is GFEffectPlugin) {
        return [
          AudioPortId.audioInL,
          AudioPortId.audioInR,
          AudioPortId.audioOutL,
          AudioPortId.audioOutR,
        ];
      }
      return [
        AudioPortId.midiIn,
        AudioPortId.audioOutL,
        AudioPortId.audioOutR,
      ];
    }

    if (plugin is Vst3PluginInstance) {
      // Effect and analyzer plugins process audio — no MIDI IN/OUT jack.
      // Instruments receive MIDI note streams — expose MIDI IN.
      if (plugin.pluginType == Vst3PluginType.effect ||
          plugin.pluginType == Vst3PluginType.analyzer) {
        return [
          AudioPortId.audioInL,
          AudioPortId.audioInR,
          AudioPortId.audioOutL,
          AudioPortId.audioOutR,
          AudioPortId.sendOut,
          AudioPortId.returnIn,
        ];
      }
      return [
        AudioPortId.midiIn,
        AudioPortId.audioInL,
        AudioPortId.audioInR,
        AudioPortId.audioOutL,
        AudioPortId.audioOutR,
        AudioPortId.sendOut,
      ];
    }

    return [AudioPortId.midiIn, AudioPortId.audioOutL, AudioPortId.audioOutR];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ports = _portsFor(plugin);

    final midiPorts = ports.where(_isMidiPort).toList();
    final audioPorts = ports.where(_isAudioPort).toList();
    final dataPorts = ports.where((p) => p.isDataPort).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF12121E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF333355), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header: slot name + [FACE] button ──────────────────────────
            _BackPanelHeader(
              displayName: plugin.displayName,
              onFlipToFront: onFlipToFront,
              l10n: l10n,
            ),
            const SizedBox(height: 2),
            const Divider(height: 1, color: Color(0xFF2A2A44)),
            const SizedBox(height: 10),

            // ── Jack sections laid out horizontally like a hardware rack ───
            // MIDI and DATA sections are fixed-width; AUDIO takes remaining space.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (midiPorts.isNotEmpty) ...[
                  _JackSection(
                    label: 'MIDI',
                    ports: midiPorts,
                    plugin: plugin,
                    jackKeys: jackKeys,
                    l10n: l10n,
                  ),
                  if (audioPorts.isNotEmpty || dataPorts.isNotEmpty)
                    _sectionDivider(),
                ],
                if (audioPorts.isNotEmpty) ...[
                  Expanded(
                    child: _JackSection(
                      label: 'AUDIO',
                      ports: audioPorts,
                      plugin: plugin,
                      jackKeys: jackKeys,
                      l10n: l10n,
                      spreadEvenly: true,
                    ),
                  ),
                  if (dataPorts.isNotEmpty) _sectionDivider(),
                ],
                if (dataPorts.isNotEmpty)
                  _JackSection(
                    label: 'DATA',
                    ports: dataPorts,
                    plugin: plugin,
                    jackKeys: jackKeys,
                    l10n: l10n,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A thin vertical separator between jack family sections.
  Widget _sectionDivider() => Container(
        width: 1,
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: const Color(0xFF2A2A44),
      );

  static bool _isMidiPort(AudioPortId p) =>
      p == AudioPortId.midiIn || p == AudioPortId.midiOut;

  static bool _isAudioPort(AudioPortId p) =>
      p == AudioPortId.audioInL ||
      p == AudioPortId.audioInR ||
      p == AudioPortId.audioOutL ||
      p == AudioPortId.audioOutR ||
      p == AudioPortId.sendOut ||
      p == AudioPortId.returnIn;
}

// ── Header ────────────────────────────────────────────────────────────────────

class _BackPanelHeader extends StatelessWidget {
  final String displayName;
  final VoidCallback onFlipToFront;
  final AppLocalizations l10n;

  const _BackPanelHeader({
    required this.displayName,
    required this.onFlipToFront,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            displayName.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFFAABBDD),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: onFlipToFront,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            '[${l10n.patchViewFrontButton}]',
            style: const TextStyle(
              color: Color(0xFF8899BB),
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Jack section ──────────────────────────────────────────────────────────────

/// A labelled group of jacks belonging to one signal family (MIDI / Audio / Data).
///
/// When [spreadEvenly] is true (used for the Audio section) jacks are
/// distributed across the available width with [MainAxisAlignment.spaceAround].
/// Otherwise they are laid out compactly from the left.
class _JackSection extends StatelessWidget {
  final String label;
  final List<AudioPortId> ports;
  final PluginInstance plugin;
  final Map<String, GlobalKey> jackKeys;
  final AppLocalizations l10n;
  final bool spreadEvenly;

  const _JackSection({
    required this.label,
    required this.ports,
    required this.plugin,
    required this.jackKeys,
    required this.l10n,
    this.spreadEvenly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Family label.
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8899BB),
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        // Jack row — spread or compact.
        Row(
          mainAxisAlignment: spreadEvenly
              ? MainAxisAlignment.spaceAround
              : MainAxisAlignment.start,
          mainAxisSize: spreadEvenly ? MainAxisSize.max : MainAxisSize.min,
          children: ports
              .map((port) => _JackWidget(
                    key: ValueKey('jack_${plugin.id}_${port.name}'),
                    slotId: plugin.id,
                    port: port,
                    jackKey: _circleKey(plugin.id, port, jackKeys),
                    l10n: l10n,
                  ))
              .toList(),
        ),
      ],
    );
  }

  /// Returns (or creates) the [GlobalKey] for the jack circle of [slotId]/[port].
  ///
  /// This key is placed on the 24×24 [SizedBox] that wraps the visible circle,
  /// so both cable endpoints and drop-zone detection use the exact jack position.
  static GlobalKey _circleKey(
    String slotId,
    AudioPortId port,
    Map<String, GlobalKey> jackKeys,
  ) {
    return jackKeys.putIfAbsent('$slotId:${port.name}', GlobalKey.new);
  }
}

// ── Jack widget ───────────────────────────────────────────────────────────────

/// A single virtual jack: coloured circle + label beneath.
///
/// The [jackKey] is assigned to the 24×24 [SizedBox] wrapping the circle,
/// NOT to the whole widget. This ensures [PatchCableOverlay] resolves cable
/// endpoints to the visual centre of the jack hole rather than the widget's
/// centre (which includes the label text below the circle).
class _JackWidget extends StatefulWidget {
  final String slotId;
  final AudioPortId port;

  /// Key placed on the 24×24 circle SizedBox — used by the cable overlay for
  /// precise jack-centre position lookups.
  final GlobalKey jackKey;

  final AppLocalizations l10n;

  const _JackWidget({
    super.key,
    required this.slotId,
    required this.port,
    required this.jackKey,
    required this.l10n,
  });

  @override
  State<_JackWidget> createState() => _JackWidgetState();
}

class _JackWidgetState extends State<_JackWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final graph = context.watch<AudioGraph>();
    final dragCtrl = context.watch<PatchDragController>();

    final isConnected = _isConnected(graph);
    final isDragActive = dragCtrl.isDragging;

    final isCompatible = isDragActive &&
        widget.port.isInput &&
        dragCtrl.fromPort!.compatibleWith(widget.port);

    // Start/stop the pulse animation for compatible input jacks during drag.
    if (isCompatible && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    } else if (!isCompatible && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }

    final isDimmed = isDragActive && !isCompatible && !widget.port.isOutput;

    return GestureDetector(
      onLongPressStart: widget.port.isOutput
          ? (details) => _startDrag(context, details.globalPosition)
          : null,
      child: Opacity(
        opacity: isDimmed ? 0.3 : 1.0,
        child: Padding(
          // Horizontal padding so adjacent jacks don't touch.
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Jack circle (24×24) — keyed so the cable overlay and drag
              // detection target the exact hole position.
              SizedBox(
                key: widget.jackKey,
                width: 24,
                height: 24,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context, child) => _JackCircle(
                    color: widget.port.color,
                    isConnected: isConnected,
                    pulseScale: isCompatible ? _pulseAnim.value : 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              // ── Port label beneath the circle.
              Text(
                widget.port.localizedLabel(widget.l10n),
                style: TextStyle(
                  color: widget.port.color.withValues(alpha: 0.90),
                  fontSize: 10,
                  letterSpacing: 0.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Returns true if this jack already has a cable in the audio graph.
  bool _isConnected(AudioGraph graph) {
    if (widget.port.isOutput) {
      return graph.connectionsFrom(widget.slotId)
          .any((c) => c.fromPort == widget.port);
    }
    return graph.connectionsTo(widget.slotId)
        .any((c) => c.toPort == widget.port);
  }

  void _startDrag(BuildContext context, Offset globalPosition) {
    context.read<PatchDragController>()
        .startDrag(widget.slotId, widget.port, globalPosition);
  }
}

// ── Jack circle painter ───────────────────────────────────────────────────────

/// Filled circle = connected, outlined ring = free.
class _JackCircle extends StatelessWidget {
  final Color color;
  final bool isConnected;
  final double pulseScale;

  const _JackCircle({
    required this.color,
    required this.isConnected,
    this.pulseScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: pulseScale,
      child: Container(
        decoration: isConnected
            ? BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              )
            : BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2),
                color: color.withValues(alpha: 0.08),
              ),
      ),
    );
  }
}
