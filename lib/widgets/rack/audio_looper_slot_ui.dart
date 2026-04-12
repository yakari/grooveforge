import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/audio_looper_plugin_instance.dart';
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
    final engine = context.read<AudioLooperEngine>();
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
        Text(_memoryLabel(clip),
            style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ],
    );
  }

  String _memoryLabel(AudioLooperClip? clip) {
    if (clip == null) return '';
    final bytes = clip.lengthFrames * 2 * 4;
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
