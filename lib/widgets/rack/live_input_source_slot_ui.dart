import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/live_input_source_plugin_instance.dart';
import '../../services/audio_graph.dart';
import '../../services/live_input_source_engine.dart';
import '../../services/rack_state.dart';
import '../../services/vst_host_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kBg = Color(0xFF15151F);
const _kBorder = Color(0xFF2A2A3F);
const _kAccent = Color(0xFF42A5F5);
const _kMeterBg = Color(0xFF0D1117);
const _kMeterFill = Color(0xFF66BB6A);

/// Front-panel UI body for a [LiveInputSourcePluginInstance] rack slot.
///
/// Responsive layout (per Rule 1):
///   - Wide (≥ 900 px): device picker row on top, gain + meter side-by-side.
///   - Narrow: everything stacked.
///
/// Session 1 UI only — no live audio yet. The meter renders a static
/// "no signal" indicator until the native capture path lands in Session 2.
class LiveInputSourceSlotUI extends StatefulWidget {
  final LiveInputSourcePluginInstance plugin;
  const LiveInputSourceSlotUI({super.key, required this.plugin});

  @override
  State<LiveInputSourceSlotUI> createState() => _LiveInputSourceSlotUIState();
}

class _LiveInputSourceSlotUIState extends State<LiveInputSourceSlotUI> {
  /// Cached engine reference captured when the element first attaches to
  /// the tree. Using `context.read` inside [dispose] is forbidden — the
  /// element is already inactive by then, which trips the framework
  /// assertion `element._lifecycleState == _ElementLifecycle.inactive`.
  /// Caching here lets [dispose] detach without touching the context.
  LiveInputSourceEngine? _engine;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _engine ??= context.read<LiveInputSourceEngine>();
  }

  @override
  void initState() {
    super.initState();
    // Deferred one frame so the provider tree is guaranteed to be
    // available. Attaching the slot starts the shared miniaudio capture
    // device (if needed) and kicks off the 30 Hz peak meter poll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _engine!.attachSlot(widget.plugin);

      // Trigger a routing rebuild so `syncAudioRouting` picks up any
      // cables already connected to this slot when it was restored
      // from a .gf project (mirrors the audio looper's slot UI).
      final rackState = context.read<RackState>();
      final graph = context.read<AudioGraph>();
      VstHostService.instance.syncAudioRouting(
        graph,
        rackState.plugins,
        keyboardSfIds: rackState.buildKeyboardSfIds(),
      );
    });
  }

  @override
  void dispose() {
    // Detach via the cached engine reference — stops the meter timer
    // once this is the last Live Input slot. Capture itself is shared
    // with the vocoder and is not stopped here.
    _engine?.detachSlot(widget.plugin.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<LiveInputSourceEngine>();

    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return wide ? _buildWide(engine) : _buildNarrow(engine);
        },
      ),
    );
  }

  // ── Layout variants ─────────────────────────────────────────────────────

  Widget _buildWide(LiveInputSourceEngine engine) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeviceRow(plugin: widget.plugin, engine: engine),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _GainSlider(plugin: widget.plugin, engine: engine)),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: _LevelMeter(slotId: widget.plugin.id, engine: engine),
            ),
            const SizedBox(width: 12),
            _MonitorMuteToggle(plugin: widget.plugin, engine: engine),
          ],
        ),
      ],
    );
  }

  Widget _buildNarrow(LiveInputSourceEngine engine) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeviceRow(plugin: widget.plugin, engine: engine),
        const SizedBox(height: 8),
        _LevelMeter(slotId: widget.plugin.id, engine: engine),
        const SizedBox(height: 8),
        _GainSlider(plugin: widget.plugin, engine: engine),
        const SizedBox(height: 4),
        _MonitorMuteToggle(plugin: widget.plugin, engine: engine),
      ],
    );
  }
}

// ── Device + channel-pair selection row ───────────────────────────────────────

class _DeviceRow extends StatelessWidget {
  final LiveInputSourcePluginInstance plugin;
  final LiveInputSourceEngine engine;
  const _DeviceRow({required this.plugin, required this.engine});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final devices = engine.devices;

    // When no device is available yet, show a disabled placeholder with
    // the localized "no device" string instead of an empty dropdown.
    if (devices.isEmpty) {
      return Row(
        children: [
          const Icon(Icons.mic_off, size: 16, color: Colors.white38),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.liveInputNoDevice,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            color: Colors.white54,
            tooltip: l10n.liveInputRefreshDevices,
            onPressed: engine.refreshDevices,
          ),
        ],
      );
    }

    // Resolve the currently-selected device by *index* — on Android the
    // same display name can recur (e.g. multiple built-in mics), so the
    // device index is the only unique key available. Fall back to the
    // first entry if the persisted deviceId no longer matches anything.
    LiveInputDevice selected = devices.first;
    for (final d in devices) {
      if ('${d.index}' == plugin.deviceId) {
        selected = d;
        break;
      }
    }

    return Row(
      children: [
        const Icon(Icons.mic, size: 16, color: _kAccent),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isExpanded: true,
              value: selected.index,
              dropdownColor: _kBg,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              items: [
                for (final d in devices)
                  DropdownMenuItem(value: d.index, child: Text(d.name)),
              ],
              onChanged: (value) {
                if (value != null) engine.selectDevice(plugin, '$value');
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Channel-pair selector — a small subset for now. Multi-channel
        // interfaces will grow this list in Session 2 once the native
        // side reports per-device channel counts.
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: plugin.channelPair,
            dropdownColor: _kBg,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            items: const [
              DropdownMenuItem(value: '1+2', child: Text('1+2')),
              DropdownMenuItem(value: '1', child: Text('L')),
              DropdownMenuItem(value: '2', child: Text('R')),
            ],
            onChanged: (value) {
              if (value != null) engine.setChannelPair(plugin, value);
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          color: Colors.white54,
          tooltip: l10n.liveInputRefreshDevices,
          onPressed: engine.refreshDevices,
        ),
      ],
    );
  }
}

// ── Gain slider ───────────────────────────────────────────────────────────────

class _GainSlider extends StatelessWidget {
  final LiveInputSourcePluginInstance plugin;
  final LiveInputSourceEngine engine;
  const _GainSlider({required this.plugin, required this.engine});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            l10n.liveInputGainLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ),
        Expanded(
          child: Slider(
            min: -24.0,
            max: 24.0,
            value: plugin.gainDb,
            activeColor: _kAccent,
            onChanged: (v) => engine.setGainDb(plugin, v),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            '${plugin.gainDb.toStringAsFixed(1)} dB',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ── Level meter (static placeholder in Session 1) ─────────────────────────────

class _LevelMeter extends StatelessWidget {
  final String slotId;
  final LiveInputSourceEngine engine;
  const _LevelMeter({required this.slotId, required this.engine});

  @override
  Widget build(BuildContext context) {
    final peakDb = engine.peakDbFor(slotId);
    // Map −60..0 dB → 0..1 for the bar width.
    final level = peakDb.isFinite
        ? ((peakDb + 60.0) / 60.0).clamp(0.0, 1.0)
        : 0.0;
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: _kMeterBg,
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: level,
        child: Container(color: _kMeterFill),
      ),
    );
  }
}

// ── Monitor-mute toggle ───────────────────────────────────────────────────────

class _MonitorMuteToggle extends StatelessWidget {
  final LiveInputSourcePluginInstance plugin;
  final LiveInputSourceEngine engine;
  const _MonitorMuteToggle({required this.plugin, required this.engine});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.liveInputMonitorMute,
      child: IconButton(
        icon: Icon(
          plugin.monitorMute ? Icons.headphones : Icons.volume_up,
          size: 18,
          color: plugin.monitorMute ? Colors.white38 : _kAccent,
        ),
        onPressed: () =>
            engine.setMonitorMute(plugin, !plugin.monitorMute),
      ),
    );
  }
}
