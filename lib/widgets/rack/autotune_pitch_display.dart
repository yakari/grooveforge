import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/autotune_pitch.dart';

// ─── Design tokens ───────────────────────────────────────────────────────────
//
// The amber LCD every GrooveForge panel uses, with a green "in tune" and a
// hot pink "being yanked" so the correction reads from across a room.

const _kLcdBg = Color(0xFF080808);
const _kLcdBorder = Color(0xFF2C2C2C);
const _kLcdAmber = Color(0xFFFFAD2A);
const _kInTune = Color(0xFF00E56A);
const _kYanked = Color(0xFFFF4FA3);

/// How often the display asks the DSP what it hears. Thirty times a second
/// follows a sung line smoothly without spending a frame's work on FFI.
const _kPollInterval = Duration(milliseconds: 33);

/// Within this many cents of the target the needle shows green: close
/// enough that a listener hears the note as in tune.
const _kInTuneCents = 10;

/// Live readout for the Autotune panel: the note being sung, how far off it
/// is, and the note it is being tuned to.
///
/// Without it the effect is a black box — a correction that does nothing
/// looks exactly the same whether the singer is already in tune, the tracker
/// is not hearing a note, or the input is not patched at all. It is also the
/// fun part: watching the needle get dragged to the centre.
///
/// [read] is polled while the widget is mounted; it is a callback rather
/// than a direct call into the audio service so the display can be tested
/// with scripted readings.
class AutotunePitchDisplay extends StatefulWidget {
  const AutotunePitchDisplay({
    super.key,
    required this.read,
    this.solfege = false,
    this.scalePatched = false,
  });

  /// Returns what the effect hears right now.
  final AutotunePitch Function() read;

  /// Name notes Do-Ré-Mi rather than C-D-E.
  final bool solfege;

  /// Whether a scale cable is overriding the panel's own Key and Scale —
  /// shown as a caption, since the dimmed selectors alone do not say why.
  final bool scalePatched;

  @override
  State<AutotunePitchDisplay> createState() => _AutotunePitchDisplayState();
}

class _AutotunePitchDisplayState extends State<AutotunePitchDisplay> {
  Timer? _timer;
  AutotunePitch _pitch = AutotunePitch.silent;

  @override
  void initState() {
    super.initState();
    _pitch = widget.read();
    _timer = Timer.periodic(_kPollInterval, (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Reads the DSP and rebuilds only when something changed, so a silent
  /// input costs no frames.
  void _poll() {
    final next = widget.read();
    if (next == _pitch || !mounted) return;
    setState(() => _pitch = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Tooltip(
      message: l10n.autotuneDisplayTooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _kLcdBg,
          border: Border.all(color: _kLcdBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _pitch.isVoiced ? _buildVoiced(l10n) : _buildListening(l10n),
            if (widget.scalePatched) _buildPatchedCaption(l10n),
          ],
        ),
      ),
    );
  }

  /// Nothing pitched coming in: say so, rather than freezing the last note.
  Widget _buildListening(AppLocalizations l10n) {
    return SizedBox(
      height: 34,
      child: Center(
        child: Text(
          l10n.autotuneListening,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
        ),
      ),
    );
  }

  /// `[A3 +30¢]  ────●──|────  [→ A3]`
  Widget _buildVoiced(AppLocalizations l10n) {
    final cents = _pitch.centsOffTarget ?? 0;
    final color = cents.abs() <= _kInTuneCents ? _kInTune : _kYanked;
    final heard = autotuneNoteName(_pitch.inputNote!.round(),
        solfege: widget.solfege);
    final target =
        autotuneNoteName(_pitch.targetNote!, solfege: widget.solfege);

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          _NoteLabel(
            note: heard,
            detail: l10n.autotuneCents(_signed(cents)),
            color: _kLcdAmber,
          ),
          const SizedBox(width: 10),
          Expanded(child: _CentsNeedle(cents: cents, color: color)),
          const SizedBox(width: 10),
          _NoteLabel(note: target, detail: '→', color: color),
        ],
      ),
    );
  }

  Widget _buildPatchedCaption(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        l10n.autotuneScalePatched,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFAA44FF), fontSize: 10),
      ),
    );
  }

  /// `+30` / `-12` / `0` — the sign is part of the information.
  static String _signed(int value) => value > 0 ? '+$value' : '$value';
}

/// A note name in large LCD type with a small caption under it.
class _NoteLabel extends StatelessWidget {
  const _NoteLabel({
    required this.note,
    required this.detail,
    required this.color,
  });

  final String note;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            note,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            detail,
            maxLines: 1,
            style: TextStyle(color: color.withValues(alpha: 0.7), fontSize: 9),
          ),
        ],
      ),
    );
  }
}

/// A horizontal tuner needle spanning a semitone: half a semitone flat at the
/// left edge, half sharp at the right, the target in the middle.
class _CentsNeedle extends StatelessWidget {
  const _CentsNeedle({required this.cents, required this.color});

  /// Signed distance from the target. Clamped to the visible ±50.
  final int cents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // -50..+50 cents mapped to -1..+1 for Align.
    final x = (cents.clamp(-50, 50)) / 50.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(height: 2, color: Colors.white12),
        Container(width: 2, height: 18, color: Colors.white38),
        Align(
          alignment: Alignment(x, 0),
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }
}
