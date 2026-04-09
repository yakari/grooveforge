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
///
/// Renders hardware-style audio looper controls:
/// - Waveform display with playback head indicator.
/// - Transport strip: ARM / PLAY / STOP / OVERDUB / CLEAR / REVERSE buttons.
/// - Volume slider.
/// - Status indicator (idle / armed / recording / playing / overdubbing).
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
    // Ensure a native clip is allocated for this slot.
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
          // ── Waveform display ────────────────────────────────────────
          _WaveformDisplay(clip: clip, slotId: widget.plugin.id),
          const SizedBox(height: 8),
          // ── Transport controls ──────────────────────────────────────
          _TransportStrip(clip: clip, slotId: widget.plugin.id),
          const SizedBox(height: 6),
          // ── Volume + status ─────────────────────────────────────────
          _VolumeRow(clip: clip, slotId: widget.plugin.id),
        ],
      ),
    );
  }
}

// ── Waveform display ──────────────────────────────────────────────────────────

/// Draws a simplified waveform (RMS envelope) from the native clip buffer
/// with a playback head indicator overlay.
class _WaveformDisplay extends StatelessWidget {
  final AudioLooperClip? clip;
  final String slotId;

  const _WaveformDisplay({required this.clip, required this.slotId});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: _kWaveBg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _kBorder, width: 0.5),
      ),
      child: clip == null || clip!.lengthFrames == 0
          ? const Center(
              child: Text('No audio recorded',
                  style: TextStyle(color: Colors.grey, fontSize: 11)))
          : CustomPaint(
              painter: _WaveformPainter(clip: clip!),
              size: Size.infinite,
            ),
    );
  }
}

/// CustomPainter that draws an RMS waveform from native PCM data.
///
/// Decimates the clip into ~300 RMS bins for display, avoiding per-sample
/// iteration at full resolution.  The playback head is drawn as a thin
/// vertical white line.
class _WaveformPainter extends CustomPainter {
  final AudioLooperClip clip;

  _WaveformPainter({required this.clip});

  @override
  void paint(Canvas canvas, Size size) {
    final length = clip.lengthFrames;
    if (length == 0) return;

    // ── Draw waveform RMS envelope ─────────────────────────────────
    final host =
        // ignore: depend_on_referenced_packages
        _getNativeDataPointers();
    if (host == null) return;
    final (dataL, dataR) = host;

    final bins = math.min(size.width.toInt(), 300);
    final samplesPerBin = length / bins;
    final wavePaint = Paint()
      ..color = _kWaveColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.fill;

    final midY = size.height / 2;

    for (int b = 0; b < bins; b++) {
      final start = (b * samplesPerBin).toInt();
      final end = math.min(((b + 1) * samplesPerBin).toInt(), length);
      if (start >= end) continue;

      // Compute RMS for this bin.
      double sumSq = 0;
      for (int i = start; i < end; i++) {
        final l = dataL[i];
        final r = dataR[i];
        sumSq += (l * l + r * r) * 0.5;
      }
      final rms = math.sqrt(sumSq / (end - start));

      // Map RMS to height (clamp at 1.0 for normalised audio).
      final h = (rms.clamp(0.0, 1.0) * midY).toDouble();
      final x = b * size.width / bins;
      final w = math.max(size.width / bins - 0.5, 1.0);

      canvas.drawRect(
        Rect.fromCenter(center: Offset(x + w / 2, midY), width: w, height: h * 2),
        wavePaint,
      );
    }

    // ── Draw playback head ─────────────────────────────────────────
    if (clip.state == AudioLooperState.playing ||
        clip.state == AudioLooperState.overdubbing) {
      final headX = clip.progress * size.width;
      final headPaint = Paint()
        ..color = _kHeadColor
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(headX, 0), Offset(headX, size.height), headPaint);
    }

    // ── Draw recording progress ────────────────────────────────────
    if (clip.state == AudioLooperState.recording && clip.capacityFrames > 0) {
      final recX = clip.lengthFrames / clip.capacityFrames * size.width;
      final recPaint = Paint()
        ..color = _kRecColor.withValues(alpha: 0.5)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(recX, 0), Offset(recX, size.height), recPaint);
    }
  }

  /// Reads native data pointers from VstHostService.
  /// Returns null if the host or data is unavailable.
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

    return Row(
      children: [
        // ── ARM / REC ────────────────────────────────────────────
        _ControlButton(
          icon: Icons.fiber_manual_record,
          color: state == AudioLooperState.armed
              ? _kArmedColor
              : state == AudioLooperState.recording
                  ? _kRecColor
                  : Colors.grey,
          active: state == AudioLooperState.armed ||
              state == AudioLooperState.recording,
          onPressed: () {
            if (state == AudioLooperState.idle) {
              engine.arm(slotId);
            } else if (state == AudioLooperState.recording) {
              engine.stop(slotId);
              // After stopping recording, auto-play.
              Future.delayed(const Duration(milliseconds: 50), () {
                engine.play(slotId);
              });
            }
          },
          tooltip: state == AudioLooperState.recording ? 'Stop' : 'Record',
        ),
        const SizedBox(width: 4),
        // ── PLAY / STOP ──────────────────────────────────────────
        _ControlButton(
          icon: state == AudioLooperState.playing ||
                  state == AudioLooperState.overdubbing
              ? Icons.stop
              : Icons.play_arrow,
          color: state == AudioLooperState.playing
              ? _kPlayColor
              : state == AudioLooperState.overdubbing
                  ? _kOdColor
                  : Colors.grey,
          active: state == AudioLooperState.playing ||
              state == AudioLooperState.overdubbing,
          onPressed: hasAudio
              ? () {
                  if (state == AudioLooperState.playing ||
                      state == AudioLooperState.overdubbing) {
                    engine.stop(slotId);
                  } else {
                    engine.play(slotId);
                  }
                }
              : null,
          tooltip: state == AudioLooperState.playing ? 'Stop' : 'Play',
        ),
        const SizedBox(width: 4),
        // ── OVERDUB ──────────────────────────────────────────────
        _ControlButton(
          icon: Icons.layers,
          color:
              state == AudioLooperState.overdubbing ? _kOdColor : Colors.grey,
          active: state == AudioLooperState.overdubbing,
          onPressed: hasAudio
              ? () {
                  if (state == AudioLooperState.overdubbing) {
                    engine.play(slotId); // back to play
                  } else if (state == AudioLooperState.playing) {
                    engine.overdub(slotId);
                  }
                }
              : null,
          tooltip: 'Overdub',
        ),
        const SizedBox(width: 4),
        // ── REVERSE ──────────────────────────────────────────────
        _ControlButton(
          icon: Icons.swap_horiz,
          color: (clip?.reversed ?? false) ? _kWaveColor : Colors.grey,
          active: clip?.reversed ?? false,
          onPressed:
              hasAudio ? () => engine.toggleReversed(slotId) : null,
          tooltip: 'Reverse',
        ),
        const Spacer(),
        // ── Status label ─────────────────────────────────────────
        _StatusChip(state: state),
        const SizedBox(width: 8),
        // ── CLEAR ────────────────────────────────────────────────
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
            min: 0.0,
            max: 1.0,
            onChanged: (v) => engine.setVolume(slotId, v),
            activeColor: _kWaveColor,
            inactiveColor: _kBorder,
          ),
        ),
        // Duration display.
        SizedBox(
          width: 50,
          child: Text(
            duration > 0 ? '${duration.toStringAsFixed(1)}s' : '--',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: 4),
        // Memory badge.
        Text(
          _memoryLabel(clip),
          style: const TextStyle(color: Colors.grey, fontSize: 10),
        ),
      ],
    );
  }

  /// Formats the clip's buffer memory usage as a compact label.
  String _memoryLabel(AudioLooperClip? clip) {
    if (clip == null) return '';
    final bytes = clip.lengthFrames * 2 * 4; // stereo float32
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

  const _ControlButton({
    required this.icon,
    required this.color,
    required this.active,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? color.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 20, color: onPressed != null ? color : color.withValues(alpha: 0.3)),
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
