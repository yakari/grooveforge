import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../services/transport_engine.dart';
import '../l10n/app_localizations.dart';

/// Transport bar with play/stop, BPM (tap-to-type, scroll-wheel, ± hold-to-repeat),
/// tap-tempo, time signature, a visual beat-pulse LED, and an audible metronome toggle.
class TransportBar extends StatefulWidget {
  const TransportBar({super.key});

  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _beatAnim;
  TransportEngine? _transport;
  bool _isDownbeat = false;

  /// Active repeat timer for the ± nudge buttons.
  Timer? _nudgeTimer;

  @override
  void initState() {
    super.initState();
    _beatAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transport = context.read<TransportEngine>();
      _transport!.beatCount.addListener(_onBeat);
    });
  }

  @override
  void dispose() {
    _nudgeTimer?.cancel();
    _transport?.beatCount.removeListener(_onBeat);
    _beatAnim.dispose();
    super.dispose();
  }

  void _onBeat() {
    final transport = _transport;
    if (transport == null) return;
    final beat = transport.beatCount.value;
    setState(() {
      // beat 1 is the immediate downbeat fired at play-start; subsequent
      // downbeats land at 1 + k*timeSigNumerator, so the check is (beat-1)%n==0.
      _isDownbeat = (beat - 1) % transport.timeSigNumerator == 0;
    });
    _beatAnim.forward(from: 0.0);
  }

  // ── BPM nudge helpers ────────────────────────────────────────────────────

  void _nudgeBpm(TransportEngine transport, double delta) {
    transport.bpm = (transport.bpm + delta).clamp(20.0, 300.0);
  }

  /// Fires a nudge immediately, then repeats after a 400 ms delay at 80 ms intervals.
  void _startNudge(TransportEngine transport, double delta) {
    _stopNudge();
    _nudgeBpm(transport, delta);
    _nudgeTimer = Timer(const Duration(milliseconds: 400), () {
      _nudgeTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        _nudgeBpm(transport, delta);
      });
    });
  }

  void _stopNudge() {
    _nudgeTimer?.cancel();
    _nudgeTimer = null;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black45,
      child: Consumer<TransportEngine>(
        builder: (context, transport, child) {
          final isPlaying = transport.isPlaying;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Beat-pulse LED
              AnimatedBuilder(
                animation: _beatAnim,
                builder: (context0, child0) {
                  final t = _beatAnim.value;
                  final targetColor =
                      _isDownbeat ? Colors.redAccent : Colors.amberAccent;
                  final color =
                      Color.lerp(targetColor, Colors.grey[800], t)!;
                  final scale = 1.0 + 0.35 * (1.0 - t);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPlaying ? color : Colors.grey[800],
                        boxShadow: isPlaying && t < 0.5
                            ? [
                                BoxShadow(
                                  color: (_isDownbeat
                                          ? Colors.redAccent
                                          : Colors.amberAccent)
                                      .withValues(
                                          alpha: (1.0 - t * 2).clamp(0, 1)),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),

              // Play/Stop button
              IconButton(
                icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                color: isPlaying ? Colors.redAccent : Colors.greenAccent,
                tooltip:
                    isPlaying ? l10n.transportStop : l10n.transportPlay,
                iconSize: 32,
                onPressed: () {
                  if (isPlaying) {
                    transport.stop();
                  } else {
                    transport.play();
                  }
                },
              ),
              const SizedBox(width: 8),

              // BPM nudge −, BPM display (scroll + tap-to-type), BPM nudge +
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NudgeButton(
                    icon: Icons.remove,
                    onStart: () => _startNudge(transport, -1.0),
                    onStop: _stopNudge,
                  ),
                  Listener(
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        // Scroll up (dy < 0) → increase BPM; scroll down → decrease.
                        final delta = event.scrollDelta.dy > 0 ? -1.0 : 1.0;
                        _nudgeBpm(transport, delta);
                      }
                    },
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showBpmDialog(context, transport),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${transport.bpm.round()}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                l10n.transportBpm,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _NudgeButton(
                    icon: Icons.add,
                    onStart: () => _startNudge(transport, 1.0),
                    onStop: _stopNudge,
                  ),
                ],
              ),
              const Spacer(),

              // Tap Tempo button
              ElevatedButton(
                onPressed: () => transport.tapTempo(),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  l10n.transportTapTempo.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),

              // Time Signature — tap to change
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showTimeSigDialog(context, transport),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${transport.timeSigNumerator} / ${transport.timeSigDenominator}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          l10n.transportTimeSignature,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Metronome toggle
              Tooltip(
                message: l10n.transportMetronome,
                child: IconButton(
                  icon: Icon(
                    transport.metronomeEnabled
                        ? Icons.music_note
                        : Icons.music_off,
                  ),
                  color: transport.metronomeEnabled
                      ? Colors.amberAccent
                      : Colors.grey,
                  iconSize: 22,
                  onPressed: () {
                    transport.metronomeEnabled = !transport.metronomeEnabled;
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTimeSigDialog(BuildContext context, TransportEngine transport) {
    showDialog(
      context: context,
      builder: (ctx) => _TimeSigDialog(transport: transport),
    );
  }

  void _showBpmDialog(BuildContext context, TransportEngine transport) {
    final TextEditingController controller = TextEditingController(
      text: '${transport.bpm.round()}',
    );
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.transportBpm),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'e.g. 120',
            suffixText: l10n.transportBpm,
          ),
          onSubmitted: (value) {
            _updateBpm(ctx, transport, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelButton),
          ),
          ElevatedButton(
            onPressed: () {
              _updateBpm(ctx, transport, controller.text);
            },
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
  }

  void _updateBpm(
      BuildContext context, TransportEngine transport, String value) {
    final normalizedValue = value.replaceAll(',', '.');
    final bpm = double.tryParse(normalizedValue);
    if (bpm != null && bpm > 0) {
      transport.bpm = bpm.roundToDouble();
    }
    Navigator.pop(context);
  }
}

// ── Time Signature Dialog ────────────────────────────────────────────────────

class _TimeSigDialog extends StatefulWidget {
  const _TimeSigDialog({required this.transport});
  final TransportEngine transport;

  @override
  State<_TimeSigDialog> createState() => _TimeSigDialogState();
}

class _TimeSigDialogState extends State<_TimeSigDialog> {
  late int _num;
  late int _den;

  static const _presets = [
    (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4),
    (3, 8), (5, 8), (6, 8), (7, 8), (9, 8), (12, 8),
  ];

  static const _validDens = [2, 4, 8, 16];

  @override
  void initState() {
    super.initState();
    _num = widget.transport.timeSigNumerator;
    _den = widget.transport.timeSigDenominator;
  }

  void _apply(int num, int den) {
    setState(() {
      _num = num;
      _den = den;
    });
    widget.transport.timeSigNumerator = num;
    widget.transport.timeSigDenominator = den;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.transportTimeSignature),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Common presets ──────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((p) {
                final selected = _num == p.$1 && _den == p.$2;
                return ChoiceChip(
                  label: Text('${p.$1}/${p.$2}'),
                  selected: selected,
                  onSelected: (_) {
                    _apply(p.$1, p.$2);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
            const Divider(height: 28),

            // ── Custom picker ───────────────────────────────────────────
            Text(
              l10n.transportTimeSigCustom,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Numerator stepper (1–16)
                _ValueStepper(
                  value: _num,
                  label: l10n.transportTimeSigNumerator,
                  onDecrement:
                      _num > 1 ? () => _apply(_num - 1, _den) : null,
                  onIncrement:
                      _num < 16 ? () => _apply(_num + 1, _den) : null,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '/',
                    style: TextStyle(fontSize: 28, color: Colors.white70),
                  ),
                ),
                // Denominator cycles through [2, 4, 8, 16]
                _ValueStepper(
                  value: _den,
                  label: l10n.transportTimeSigDenominator,
                  onDecrement: () {
                    final i = _validDens.indexOf(_den);
                    if (i > 0) _apply(_num, _validDens[i - 1]);
                  },
                  onIncrement: () {
                    final i = _validDens.indexOf(_den);
                    if (i < _validDens.length - 1) {
                      _apply(_num, _validDens[i + 1]);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.actionDone),
        ),
      ],
    );
  }
}

/// A labelled value with − / + arrow buttons.
class _ValueStepper extends StatelessWidget {
  const _ValueStepper({
    required this.value,
    required this.label,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int value;
  final String label;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onDecrement,
              iconSize: 22,
              color: onDecrement != null ? Colors.white70 : Colors.white24,
            ),
            SizedBox(
              width: 36,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: onIncrement,
              iconSize: 22,
              color: onIncrement != null ? Colors.white70 : Colors.white24,
            ),
          ],
        ),
        Text(
          label,
          style:
              const TextStyle(fontSize: 10, color: Colors.white54),
        ),
      ],
    );
  }
}

/// Small icon button with hold-to-repeat behaviour.
/// [onStart] is called when the press begins; [onStop] when it ends.
class _NudgeButton extends StatelessWidget {
  const _NudgeButton({
    required this.icon,
    required this.onStart,
    required this.onStop,
  });

  final IconData icon;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => onStart(),
      onTapUp: (_) => onStop(),
      onTapCancel: onStop,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: Colors.white70),
      ),
    );
  }
}
