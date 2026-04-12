import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/audio_graph_connection.dart';
import '../../models/audio_looper_plugin_instance.dart';
import '../../models/audio_port_id.dart';
import '../../models/drum_generator_plugin_instance.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../models/grooveforge_keyboard_plugin.dart';
import '../../models/plugin_instance.dart';
import '../../models/vst3_plugin_instance.dart';
import '../../services/audio_graph.dart';
import '../../services/audio_looper_engine.dart';
import '../../services/rack_state.dart';
import '../../services/vst_host_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kBg = Color(0xFF15151F);
const _kBorder = Color(0xFF2A2A3F);
const _kRecColor = Color(0xFFE53935);
const _kPlayColor = Color(0xFF43A047);
const _kOdColor = Color(0xFFFF6F00);
const _kArmedColor = Color(0xFFFFB300);
const _kWaveColor = Color(0xFF42A5F5);
const _kWaveBg = Color(0xFF0D1117);
const _kHeadColor = Color(0xFFFFFFFF);

// ── Main widget ───────────────────────────────────────────────────────────────

/// Front-panel UI body for an [AudioLooperPluginInstance] rack slot.
class AudioLooperSlotUI extends StatefulWidget {
  final AudioLooperPluginInstance plugin;
  const AudioLooperSlotUI({super.key, required this.plugin});

  @override
  State<AudioLooperSlotUI> createState() => _AudioLooperSlotUIState();
}

class _AudioLooperSlotUIState extends State<AudioLooperSlotUI> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final engine = context.read<AudioLooperEngine>();

      // If there's pending metadata from a project load (native clips couldn't
      // be created earlier because the JACK host wasn't ready), finalize now.
      if (engine.hasPendingLoad) {
        await engine.finalizeLoad();
      }

      // Ensure a native clip exists for this slot (covers the "freshly added"
      // case where there's no pending load).
      if (!engine.clips.containsKey(widget.plugin.id)) {
        engine.createClip(widget.plugin.id);
      }

      // Trigger a routing rebuild so syncAudioRouting wires the render sources
      // for any cables already connected to this looper (persisted project).
      //
      // `keyboardSfIds` must be passed explicitly — on Android the audio
      // looper's cabled-input routing depends on this map to resolve
      // upstream keyboard slots to their Oboe bus IDs. Omitting it records
      // silence from any keyboard cabled to this slot.
      if (!mounted) return;
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
  Widget build(BuildContext context) {
    final engine = context.watch<AudioLooperEngine>();
    final clip = engine.clips[widget.plugin.id];

    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        border: Border(top: BorderSide(color: _kBorder, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SourceSelector(looperSlotId: widget.plugin.id),
          const SizedBox(height: 6),
          _WaveformDisplay(clip: clip),
          const SizedBox(height: 8),
          _TransportStrip(clip: clip, slotId: widget.plugin.id),
          const SizedBox(height: 6),
          _VolumeRow(clip: clip, slotId: widget.plugin.id),
        ],
      ),
    );
  }
}

// ── Waveform display ──────────────────────────────────────────────────────────

class _WaveformDisplay extends StatefulWidget {
  final AudioLooperClip? clip;
  const _WaveformDisplay({required this.clip});

  @override
  State<_WaveformDisplay> createState() => _WaveformDisplayState();
}

class _WaveformDisplayState extends State<_WaveformDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  bool get _isRecording {
    final st = widget.clip?.state;
    return st == AudioLooperState.recording ||
           st == AudioLooperState.armed ||
           st == AudioLooperState.stopping;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final hasWaveform = clip != null && clip.waveformRms.isNotEmpty;
    final noSource = clip != null &&
        clip.lengthFrames == 0 &&
        clip.state == AudioLooperState.idle;
    final l10n = AppLocalizations.of(context)!;
    final placeholder = _isRecording
        ? l10n.audioLooperWaveformRecording
        : noSource
            ? l10n.audioLooperWaveformCableInstrument
            : l10n.audioLooperWaveformEmpty;

    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final recAlpha = _isRecording ? 0.08 + _pulseCtrl.value * 0.12 : 0.0;
        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: Color.lerp(_kWaveBg, _kRecColor, recAlpha)!,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: _isRecording
                  ? _kRecColor.withValues(alpha: 0.4 + _pulseCtrl.value * 0.3)
                  : _kBorder,
              width: _isRecording ? 1.0 : 0.5,
            ),
          ),
          child: hasWaveform
              ? CustomPaint(
                  painter: _WaveformPainter(clip: clip),
                  size: Size.infinite,
                )
              : Center(
                  child: Text(
                    placeholder,
                    style: TextStyle(
                      color: _isRecording ? _kRecColor : Colors.grey,
                      fontSize: 11,
                      fontWeight: _isRecording ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Draws an RMS waveform from native PCM data with playback head overlay.
class _WaveformPainter extends CustomPainter {
  final AudioLooperClip clip;
  _WaveformPainter({required this.clip});

  @override
  void paint(Canvas canvas, Size size) {
    final length = clip.lengthFrames;

    // ── Waveform (from pre-computed RMS cache — no FFI access) ─────────
    if (clip.waveformRms.isNotEmpty) {
      _paintWaveform(canvas, size, clip.waveformRms);
    }

    // ── Playback head ──────────────────────────────────────────────────
    if (length > 0 &&
        (clip.state == AudioLooperState.playing ||
         clip.state == AudioLooperState.overdubbing)) {
      final headX = clip.progress * size.width;
      canvas.drawLine(
        Offset(headX, 0), Offset(headX, size.height),
        Paint()..color = _kHeadColor..strokeWidth = 1.5,
      );
    }

    // ── Recording progress ─────────────────────────────────────────────
    if ((clip.state == AudioLooperState.recording ||
         clip.state == AudioLooperState.stopping) &&
        clip.capacityFrames > 0) {
      final recX = clip.lengthFrames / clip.capacityFrames * size.width;
      canvas.drawLine(
        Offset(recX, 0), Offset(recX, size.height),
        Paint()..color = _kRecColor.withValues(alpha: 0.5)..strokeWidth = 2,
      );
    }
  }

  /// Draws the waveform from the pre-computed RMS cache (no FFI access).
  void _paintWaveform(Canvas canvas, Size size, List<double> rms) {
    final bins = rms.length;
    if (bins == 0) return;
    final wavePaint = Paint()
      ..color = _kWaveColor
      ..style = PaintingStyle.fill;
    final midY = size.height / 2;
    final binWidth = size.width / bins;

    for (int b = 0; b < bins; b++) {
      final h = (rms[b].clamp(0.0, 1.0) * midY).toDouble();
      final x = b * binWidth;
      final w = math.max(binWidth - 0.5, 1.0);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x + w / 2, midY), width: w, height: h * 2),
        wavePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => true;
}

// ── Transport strip ───────────────────────────────────────────────────────────

class _TransportStrip extends StatelessWidget {
  final AudioLooperClip? clip;
  final String slotId;
  const _TransportStrip({required this.clip, required this.slotId});

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioLooperEngine>();
    final l10n = AppLocalizations.of(context)!;
    final state = clip?.state ?? AudioLooperState.idle;
    final hasAudio = (clip?.lengthFrames ?? 0) > 0;

    // Single loop button props.
    final (loopIcon, loopColor, loopActive, loopTooltip) =
        _loopButtonProps(state, hasAudio, l10n);

    return Row(
      children: [
        // ── Single loop button (large) ───────────────────────────
        _ControlButton(
          icon: loopIcon,
          color: loopColor,
          active: loopActive,
          onPressed: () => engine.looperButtonPress(slotId),
          tooltip: loopTooltip,
          large: true,
        ),
        const SizedBox(width: 8),
        // ── Stop ─────────────────────────────────────────────────
        _ControlButton(
          icon: Icons.stop,
          color: Colors.grey,
          active: false,
          onPressed: state != AudioLooperState.idle
              ? () => engine.stop(slotId)
              : null,
          tooltip: l10n.audioLooperTooltipStop,
        ),
        const SizedBox(width: 4),
        // ── Reverse ──────────────────────────────────────────────
        _ControlButton(
          icon: Icons.swap_horiz,
          color: (clip?.reversed ?? false) ? _kWaveColor : Colors.grey,
          active: clip?.reversed ?? false,
          onPressed: hasAudio ? () => engine.toggleReversed(slotId) : null,
          tooltip: l10n.audioLooperTooltipReverse,
        ),
        const SizedBox(width: 4),
        // ── Bar sync toggle ──────────────────────────────────────
        _ControlButton(
          icon: Icons.timer,
          color: (clip?.barSyncEnabled ?? true) ? _kArmedColor : Colors.grey,
          active: clip?.barSyncEnabled ?? true,
          onPressed: () => engine.toggleBarSync(slotId),
          tooltip: (clip?.barSyncEnabled ?? true)
              ? l10n.audioLooperTooltipBarSyncOn
              : l10n.audioLooperTooltipBarSyncOff,
        ),
        const Spacer(),
        // ── Status ───────────────────────────────────────────────
        _StatusChip(state: state),
        const SizedBox(width: 8),
        // ── Clear ────────────────────────────────────────────────
        _ControlButton(
          icon: Icons.delete_outline,
          color: Colors.redAccent,
          active: false,
          onPressed: hasAudio ? () => engine.clear(slotId) : null,
          tooltip: l10n.audioLooperTooltipClear,
        ),
      ],
    );
  }

  /// Returns (icon, color, isActive, tooltip) for the single loop button.
  ///
  /// The tooltip branches on both the current [state] and whether the clip
  /// has any recorded audio — the "idle" state has two meanings: "empty,
  /// press to record" and "has content, press to play". [l10n] is threaded
  /// in rather than fetched per call so the compiler keeps one lookup for
  /// the whole switch.
  (IconData, Color, bool, String) _loopButtonProps(
    AudioLooperState state,
    bool hasAudio,
    AppLocalizations l10n,
  ) =>
      switch (state) {
        AudioLooperState.idle when !hasAudio => (
            Icons.fiber_manual_record,
            _kRecColor,
            false,
            l10n.audioLooperTooltipRecord,
          ),
        AudioLooperState.idle => (
            Icons.play_arrow,
            _kPlayColor,
            false,
            l10n.audioLooperTooltipPlay,
          ),
        AudioLooperState.armed => (
            Icons.fiber_manual_record,
            _kArmedColor,
            true,
            l10n.audioLooperTooltipCancel,
          ),
        AudioLooperState.recording => (
            Icons.play_arrow,
            _kRecColor,
            true,
            l10n.audioLooperTooltipStopRecordingAndPlay,
          ),
        AudioLooperState.stopping => (
            Icons.hourglass_top,
            _kArmedColor,
            true,
            l10n.audioLooperTooltipPaddingToBar,
          ),
        AudioLooperState.playing => (
            Icons.layers,
            _kPlayColor,
            true,
            l10n.audioLooperTooltipOverdub,
          ),
        AudioLooperState.overdubbing => (
            Icons.play_arrow,
            _kOdColor,
            true,
            l10n.audioLooperTooltipStopOverdub,
          ),
      };
}

// ── Volume row ────────────────────────────────────────────────────────────────

class _VolumeRow extends StatelessWidget {
  final AudioLooperClip? clip;
  final String slotId;
  const _VolumeRow({required this.clip, required this.slotId});

  @override
  Widget build(BuildContext context) {
    // Watch (not read) — total pool memory changes when clips are
    // created/destroyed, and the label tint depends on a ratio over the
    // whole engine, not just this clip.
    final engine = context.watch<AudioLooperEngine>();
    final vol = clip?.volume ?? 1.0;
    final duration = clip?.durationSeconds ?? 0.0;

    return Row(
      children: [
        const Icon(Icons.volume_up, size: 14, color: Colors.grey),
        Expanded(
          child: Slider(
            value: vol,
            onChanged: (v) => engine.setVolume(slotId, v),
            activeColor: _kWaveColor,
            inactiveColor: _kBorder,
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            duration > 0 ? '${duration.toStringAsFixed(1)}s' : '--',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          _memoryLabel(clip),
          style: TextStyle(
            color: _memoryLabelColor(engine.memoryUsedRatio),
            fontSize: 10,
            fontWeight: engine.memoryUsedRatio >= 0.9
                ? FontWeight.w600
                : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  String _memoryLabel(AudioLooperClip? clip) {
    if (clip == null) return '';
    final bytes = clip.lengthFrames * 2 * 4;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Picks a colour for the per-clip memory label based on the total pool
  /// usage ratio. Warning tinting kicks in well before the hard cap so the
  /// user has time to react:
  ///   - < 0.75 → grey (normal)
  ///   - 0.75 – 0.9 → amber (approaching cap)
  ///   - ≥ 0.9 → red (at/over cap)
  Color _memoryLabelColor(double ratio) {
    if (ratio >= 0.9) return Colors.redAccent;
    if (ratio >= 0.75) return _kArmedColor; // amber accent reused from transport
    return Colors.grey;
  }
}

// ── Reusable control button ───────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback? onPressed;
  final String tooltip;
  final bool large;

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.active,
    required this.onPressed,
    required this.tooltip,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final size = large ? 26.0 : 20.0;
    final pad = large ? 8.0 : 6.0;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Icon(icon, size: size,
                color: onPressed != null ? color : color.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final AudioLooperState state;
  const _StatusChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final (label, color) = switch (state) {
      AudioLooperState.idle => (l10n.audioLooperStatusIdle, Colors.grey),
      AudioLooperState.armed => (l10n.audioLooperStatusArmed, _kArmedColor),
      AudioLooperState.recording => (l10n.audioLooperStatusRecording, _kRecColor),
      AudioLooperState.playing => (l10n.audioLooperStatusPlaying, _kPlayColor),
      AudioLooperState.overdubbing => (l10n.audioLooperStatusOverdubbing, _kOdColor),
      AudioLooperState.stopping => (l10n.audioLooperStatusStopping, _kArmedColor),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.5),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Source selector ──────────────────────────────────────────────────────────

/// Compact "Source" row shown above the waveform.
///
/// Gives users a quick way to pick which instrument gets recorded into this
/// audio looper slot — a front-end affordance for what would otherwise
/// require flipping to the back panel and drawing a cable manually.
///
/// The selector does NOT maintain its own state: the current source is
/// derived from the [AudioGraph] every rebuild. If the user has hand-wired
/// multiple cables to this looper from the back panel, the label shows
/// "Multiple (N)" so the state is never misleading.
///
/// Picking an item rewrites the cables:
///   - **None** → disconnect every audio cable terminating at this looper.
///   - **Slot** → disconnect every audio cable terminating at this looper,
///     then connect `<slot>.audioOutL → looper.audioInL` and
///     `<slot>.audioOutR → looper.audioInR`.
///
/// **Master mix** capture is deferred to a future milestone — it requires a
/// new native routing kind (the audio looper clip would need to read the
/// final master mix buffer instead of a per-slot dry buffer), which is not
/// yet implemented on any of the three backends.
class _SourceSelector extends StatelessWidget {
  final String looperSlotId;
  const _SourceSelector({required this.looperSlotId});

  @override
  Widget build(BuildContext context) {
    // Watch both: the graph for cable topology, the rack for slot identity.
    final graph = context.watch<AudioGraph>();
    final rack = context.watch<RackState>();
    final l10n = AppLocalizations.of(context)!;

    final audioSources = _collectAudioSources(rack.plugins);
    final currentCables = _currentAudioInputCables(graph);
    final label = _currentLabel(currentCables, audioSources, l10n);

    return Row(
      children: [
        Icon(Icons.input, size: 14, color: Colors.grey.shade400),
        const SizedBox(width: 6),
        Text(
          l10n.audioLooperSourceLabel,
          style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PopupMenuButton<String?>(
            tooltip: l10n.audioLooperSourceTooltip,
            onSelected: (selectedSlotId) => _applySelection(
              graph,
              rack,
              selectedSlotId,
            ),
            itemBuilder: (context) => <PopupMenuEntry<String?>>[
              PopupMenuItem<String?>(
                value: null,
                child: Text(l10n.audioLooperSourceNone),
              ),
              if (audioSources.isNotEmpty) const PopupMenuDivider(),
              for (final source in audioSources)
                PopupMenuItem<String?>(
                  value: source.id,
                  child: Text(_labelFor(source, rack.plugins)),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _kWaveBg,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ),
                  Icon(Icons.arrow_drop_down,
                      size: 16, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Enumerates every plugin in the rack that produces stereo audio output
  /// and therefore makes sense as an audio looper source — keyboards, drum
  /// generators, theremin/stylophone/vocoder, GFPA audio effects, and VST3
  /// slots. The looper itself is excluded to prevent self-cabling (the
  /// graph cycle check would reject it anyway, but filtering up front keeps
  /// the dropdown uncluttered).
  List<PluginInstance> _collectAudioSources(List<PluginInstance> plugins) {
    final result = <PluginInstance>[];
    for (final p in plugins) {
      if (p.id == looperSlotId) continue;
      if (p is AudioLooperPluginInstance) continue;
      if (_producesAudio(p)) result.add(p);
    }
    return result;
  }

  /// Returns true if [plugin] exposes an `audioOutL` port on its back panel
  /// — matching the logic in [slot_back_panel_widget.dart]. Kept in sync
  /// manually; a mismatch just means a slot type is missing from the
  /// dropdown, not a crash.
  bool _producesAudio(PluginInstance plugin) {
    if (plugin is GrooveForgeKeyboardPlugin) return true;
    if (plugin is DrumGeneratorPluginInstance) return true;
    if (plugin is Vst3PluginInstance) return true;
    if (plugin is GFpaPluginInstance) {
      // Jam Mode and bare MIDI FX plugins don't produce audio.
      const audioPluginIds = {
        'com.grooveforge.vocoder',
        'com.grooveforge.theremin',
        'com.grooveforge.stylophone',
      };
      if (audioPluginIds.contains(plugin.pluginId)) return true;
      // Any GFPA audio-effect descriptor (reverb, delay, EQ, …) also has
      // stereo audio out. We can't easily tell from Dart-side whether a
      // given pluginId is an effect vs MIDI FX without touching the
      // registry, so we fall back to a conservative heuristic: anything
      // that is NOT a known MIDI-FX plugin is assumed to pass audio.
      const midiFxPluginIds = {
        'com.grooveforge.jammode',
        'com.grooveforge.arpeggiator',
        'com.grooveforge.chord',
        'com.grooveforge.transposer',
        'com.grooveforge.velocity_curve',
        'com.grooveforge.gate',
        'com.grooveforge.harmonizer',
      };
      return !midiFxPluginIds.contains(plugin.pluginId);
    }
    return false;
  }

  /// Lists every audio cable terminating at this looper's audioInL or
  /// audioInR. Used both for the current-source label and for the
  /// disconnect-everything pass during selection.
  List<AudioGraphConnection> _currentAudioInputCables(AudioGraph graph) {
    return graph.connections
        .where((c) =>
            c.toSlotId == looperSlotId &&
            (c.toPort == AudioPortId.audioInL ||
                c.toPort == AudioPortId.audioInR))
        .toList();
  }

  /// Derives the label shown inside the dropdown button from the current
  /// cable state:
  ///   - 0 audio cables → "None"
  ///   - ≥1 distinct source slots → the single source's display name, OR
  ///     "Multiple (N)" if there are two or more distinct upstream slots.
  ///     Two cables from the same slot (L + R stereo pair) count as one
  ///     source and show the slot's name.
  String _currentLabel(
    List<AudioGraphConnection> cables,
    List<PluginInstance> sources,
    AppLocalizations l10n,
  ) {
    if (cables.isEmpty) return l10n.audioLooperSourceNone;
    final distinctSourceIds = cables.map((c) => c.fromSlotId).toSet();
    if (distinctSourceIds.length == 1) {
      final sourceId = distinctSourceIds.first;
      final source = sources.where((p) => p.id == sourceId).firstOrNull;
      if (source != null) return _labelFor(source, sources);
      // Source exists in the graph but not in our "audio producers" list —
      // probably a slot that was removed or a type we don't recognise.
      // Fall through to a generic label.
      return l10n.audioLooperSourceUnknown;
    }
    return l10n.audioLooperSourceMultiple(distinctSourceIds.length);
  }

  /// Builds a human-readable label for a source slot, disambiguating
  /// duplicate plugin types by appending a numeric index (1-based) counted
  /// over slots of the same class in display order.
  String _labelFor(PluginInstance source, List<PluginInstance> allPlugins) {
    // If multiple slots share the same displayName, append an index so the
    // dropdown can distinguish "GrooveForge Keyboard" #1 from #2.
    final siblings = allPlugins
        .where((p) => p.displayName == source.displayName)
        .toList();
    if (siblings.length <= 1) return source.displayName;
    final idx = siblings.indexOf(source) + 1;
    return '${source.displayName} $idx';
  }

  /// Applies a selection from the dropdown: disconnect every existing
  /// audio cable targeting this looper, then (for a non-null target)
  /// connect the selected source's stereo outputs to the looper's stereo
  /// inputs.  The routing sync is fired implicitly by `AudioGraph`'s
  /// `notifyListeners` call, which `RackState._onAudioGraphChanged` hooks.
  void _applySelection(
    AudioGraph graph,
    RackState rack,
    String? selectedSlotId,
  ) {
    // Disconnect everything first so picking the same slot twice is a no-op
    // on the second call (and so switching between slots produces exactly
    // one effective source).
    for (final cable in _currentAudioInputCables(graph)) {
      graph.disconnect(cable.id);
    }
    if (selectedSlotId == null) return;

    // Validate the chosen slot still exists — the list could be stale if a
    // rebuild fired between `itemBuilder` and `onSelected`.
    final source =
        rack.plugins.where((p) => p.id == selectedSlotId).firstOrNull;
    if (source == null) return;

    try {
      graph.connect(
        source.id,
        AudioPortId.audioOutL,
        looperSlotId,
        AudioPortId.audioInL,
      );
      graph.connect(
        source.id,
        AudioPortId.audioOutR,
        looperSlotId,
        AudioPortId.audioInR,
      );
    } on ArgumentError catch (e) {
      // Cycle rejection or duplicate edge — AudioGraph.connect throws. The
      // dropdown filter should prevent this (we exclude the looper itself),
      // but a race between rack mutations and menu selection could still
      // produce one. Swallow rather than crash the UI.
      debugPrint('_SourceSelector: connect failed — $e');
    }
  }
}
