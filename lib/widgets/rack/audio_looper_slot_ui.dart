import 'dart:ffi' hide Size;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/audio_looper_plugin_instance.dart';
import '../../services/audio_looper_engine.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AudioLooperEngine>().createClip(widget.plugin.id);
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

class _WaveformDisplay extends StatelessWidget {
  final AudioLooperClip? clip;
  const _WaveformDisplay({required this.clip});

  @override
  Widget build(BuildContext context) {
    final hasAudio = (clip?.lengthFrames ?? 0) > 0;
    final noSource = clip != null && !hasAudio &&
        clip!.state == AudioLooperState.idle;

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: _kWaveBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: !hasAudio
          ? Center(
              child: Text(
                noSource ? 'Cable an instrument to Audio IN' : 'No audio recorded',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            )
          : CustomPaint(
              painter: _WaveformPainter(clip: clip!),
              size: Size.infinite,
            ),
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
    if (length == 0) return;

    final ptrs = _getNativeDataPointers();
    if (ptrs == null) return;
    final (dataL, dataR) = ptrs;

    final bins = math.min(size.width.toInt(), 300);
    final samplesPerBin = length / bins;
    final wavePaint = Paint()
      ..color = _kWaveColor
      ..style = PaintingStyle.fill;
    final midY = size.height / 2;

    for (int b = 0; b < bins; b++) {
      final start = (b * samplesPerBin).toInt();
      final end = math.min(((b + 1) * samplesPerBin).toInt(), length);
      if (start >= end) continue;
      double sumSq = 0;
      for (int i = start; i < end; i++) {
        final l = dataL[i];
        final r = dataR[i];
        sumSq += (l * l + r * r) * 0.5;
      }
      final rms = math.sqrt(sumSq / (end - start));
      final h = (rms.clamp(0.0, 1.0) * midY).toDouble();
      final x = b * size.width / bins;
      final w = math.max(size.width / bins - 0.5, 1.0);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x + w / 2, midY), width: w, height: h * 2),
        wavePaint,
      );
    }

    // Playback head.
    if (clip.state == AudioLooperState.playing ||
        clip.state == AudioLooperState.overdubbing) {
      final headX = clip.progress * size.width;
      canvas.drawLine(
        Offset(headX, 0), Offset(headX, size.height),
        Paint()..color = _kHeadColor..strokeWidth = 1.5,
      );
    }

    // Recording progress.
    if (clip.state == AudioLooperState.recording && clip.capacityFrames > 0) {
      final recX = clip.lengthFrames / clip.capacityFrames * size.width;
      canvas.drawLine(
        Offset(recX, 0), Offset(recX, size.height),
        Paint()..color = _kRecColor.withValues(alpha: 0.5)..strokeWidth = 2,
      );
    }
  }

  (Pointer<Float>, Pointer<Float>)? _getNativeDataPointers() {
    final host = VstHostService.instance.host;
    if (host == null) return null;
    final dataL = host.getAudioLooperDataL(clip.nativeIdx);
    final dataR = host.getAudioLooperDataR(clip.nativeIdx);
    if (dataL == nullptr || dataR == nullptr) return null;
    return (dataL, dataR);
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
    final state = clip?.state ?? AudioLooperState.idle;
    final hasAudio = (clip?.lengthFrames ?? 0) > 0;

    // Single loop button props.
    final (loopIcon, loopColor, loopActive, loopTooltip) = _loopButtonProps(state, hasAudio);

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
          tooltip: 'Stop',
        ),
        const SizedBox(width: 4),
        // ── Reverse ──────────────────────────────────────────────
        _ControlButton(
          icon: Icons.swap_horiz,
          color: (clip?.reversed ?? false) ? _kWaveColor : Colors.grey,
          active: clip?.reversed ?? false,
          onPressed: hasAudio ? () => engine.toggleReversed(slotId) : null,
          tooltip: 'Reverse',
        ),
        const SizedBox(width: 4),
        // ── Bar sync toggle ──────────────────────────────────────
        _ControlButton(
          icon: Icons.timer,
          color: (clip?.barSyncEnabled ?? true) ? _kArmedColor : Colors.grey,
          active: clip?.barSyncEnabled ?? true,
          onPressed: () => engine.toggleBarSync(slotId),
          tooltip: (clip?.barSyncEnabled ?? true)
              ? 'Bar sync: ON' : 'Bar sync: OFF',
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
          tooltip: 'Clear',
        ),
      ],
    );
  }

  /// Returns (icon, color, isActive, tooltip) for the single loop button.
  (IconData, Color, bool, String) _loopButtonProps(AudioLooperState state, bool hasAudio) =>
      switch (state) {
        AudioLooperState.idle when !hasAudio =>
          (Icons.fiber_manual_record, _kRecColor, false, 'Record'),
        AudioLooperState.idle =>
          (Icons.play_arrow, _kPlayColor, false, 'Play'),
        AudioLooperState.armed =>
          (Icons.fiber_manual_record, _kArmedColor, true, 'Cancel'),
        AudioLooperState.recording =>
          (Icons.play_arrow, _kRecColor, true, 'Stop recording & play'),
        AudioLooperState.playing =>
          (Icons.layers, _kPlayColor, true, 'Overdub'),
        AudioLooperState.overdubbing =>
          (Icons.play_arrow, _kOdColor, true, 'Stop overdub'),
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
    final (label, color) = switch (state) {
      AudioLooperState.idle => ('IDLE', Colors.grey),
      AudioLooperState.armed => ('ARMED', _kArmedColor),
      AudioLooperState.recording => ('REC', _kRecColor),
      AudioLooperState.playing => ('PLAY', _kPlayColor),
      AudioLooperState.overdubbing => ('ODUB', _kOdColor),
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
