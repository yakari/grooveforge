import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gfpa_plugin_instance.dart';
import '../../services/audio_engine.dart';
import '../channel/channel_patch_info.dart';
import '../channel/vocoder_level_meters.dart';

/// Compact rack-slot body for a standalone GFPA Vocoder slot.
///
/// Mirrors the integrated vocoder panel that appears inside a
/// [GrooveForgeKeyboardSlotUI] when its channel is set to vocoder mode:
/// level meters on the left, four parameter knobs in the centre, and the
/// carrier-waveform 2×2 button grid on the right — all in one horizontal
/// row inside a dark orange-bordered container.
///
/// Parameter changes are written directly to [AudioEngine] notifiers (same
/// path as [VocoderSliders]/[VocoderButtons]). Project persistence is handled
/// by [ProjectService.autosave], which calls [RackState.snapshotGfpaVocoderParams]
/// before writing the .gf file.
class GFpaVocoderSlotUI extends StatelessWidget {
  const GFpaVocoderSlotUI({super.key, required this.plugin});

  final GFpaPluginInstance plugin;

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black26,
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // ── Level meters ──────────────────────────────────────────
            const Expanded(child: VocoderLevelMeters()),
            const SizedBox(width: 8),
            _Divider(height: 40),
            const SizedBox(width: 8),

            // ── Parameter knobs (Noise / Speed / Bandwidth / Gate) ────
            Expanded(
              flex: 3,
              child: VocoderSliders(
                engine: engine,
                // channelIndex is only used for ValueKey uniqueness.
                channelIndex: plugin.midiChannel,
              ),
            ),
            const SizedBox(width: 8),
            _Divider(height: 40),
            const SizedBox(width: 8),

            // ── Carrier waveform 2×2 grid ─────────────────────────────
            VocoderButtons(engine: engine),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: height,
    color: Colors.orange.withValues(alpha: 0.3),
  );
}
