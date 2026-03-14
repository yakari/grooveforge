import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/loop_track.dart';
import '../../models/looper_plugin_instance.dart';
import '../../services/looper_engine.dart';
import '../../services/rack_state.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────

const _kBg = Color(0xFF15151F);
const _kPanel = Color(0xFF1C1C2A);
const _kBorder = Color(0xFF2A2A3F);
const _kRecColor = Color(0xFFE53935);       // red — record
const _kPlayColor = Color(0xFF43A047);      // green — play
const _kOdColor = Color(0xFFFF6F00);        // amber — overdub
const _kArmedColor = Color(0xFFFFB300);     // yellow — armed
const _kLcdBg = Color(0xFF0D1117);          // LCD background
const _kLcdText = Color(0xFF56E39F);        // LCD green text

// ── Main widget ───────────────────────────────────────────────────────────────

/// Front-panel UI body for a [LooperPluginInstance] rack slot.
///
/// Renders hardware-style looper controls:
/// - Transport strip: REC / PLAY / STOP / CLEAR buttons + state LCD.
/// - Track list: one row per [LoopTrack] with chord-grid, mute, reverse, speed.
/// - Pin toggle: pins this slot below the transport bar.
///
/// The widget creates a looper session on first render (if one does not already
/// exist) so that slots restored from project files are immediately usable.
class LooperSlotUI extends StatefulWidget {
  final LooperPluginInstance plugin;

  const LooperSlotUI({super.key, required this.plugin});

  @override
  State<LooperSlotUI> createState() => _LooperSlotUIState();
}

class _LooperSlotUIState extends State<LooperSlotUI> {
  @override
  void initState() {
    super.initState();
    // Ensure a session exists for this slot (handles project-file restore).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<LooperEngine>().ensureSession(widget.plugin.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final engine = context.watch<LooperEngine>();
    final session = engine.session(widget.plugin.id);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Transport strip (LOOP / STOP / CLEAR + state LCD + Q chip) ───
          _TransportStrip(
            slotId: widget.plugin.id,
            state: session?.state ?? LooperState.idle,
            hasContent: session?.tracks
                    .any((t) =>
                        t.lengthInBeats != null && t.events.isNotEmpty) ??
                false,
            quantize: session?.quantize ?? LoopQuantize.off,
            engine: engine,
            l10n: l10n,
          ),

          // ── Track list ──────────────────────────────────────────────────────
          if (session != null && session.tracks.isNotEmpty) ...[
            const Divider(height: 1, color: _kBorder),
            _TrackList(
              slotId: widget.plugin.id,
              tracks: session.tracks,
              engine: engine,
              l10n: l10n,
            ),
          ],

          // ── Pin toggle ──────────────────────────────────────────────────────
          const Divider(height: 1, color: _kBorder),
          _PinToggle(plugin: widget.plugin, l10n: l10n),
        ],
      ),
    );
  }
}

// ── Transport strip ───────────────────────────────────────────────────────────

/// The main control row: LOOP button · STOP · CLEAR + state LCD.
///
/// The LOOP button is the single-action control, mirroring a hardware looper
/// pedal.  Its icon and colour reflect the *next* action:
///
/// | State              | Icon         | Colour  | Press effect          |
/// |--------------------|--------------|---------|------------------------|
/// | idle               | ● record     | red     | arm / start recording  |
/// | armed              | ● record     | yellow  | cancel arm             |
/// | recording          | ■ stop       | red     | stop → waitingForBar   |
/// | waitingForBar      | ■ stop       | yellow  | cancel → idle          |
/// | playing            | ◎ layers     | amber   | queue overdub          |
/// | waitingForOverdub  | ◎ layers     | amber   | cancel overdub queue   |
/// | overdubbing        | ■ stop       | amber   | stop overdub → playing |
class _TransportStrip extends StatelessWidget {
  final String slotId;
  final LooperState state;

  /// True when the session has at least one completed, non-empty track.
  /// Used to show a play button instead of a record button when idle with
  /// existing content (e.g. after stop or after a project reload).
  final bool hasContent;

  /// Slot-level quantize grid: applies to every new recording pass.
  final LoopQuantize quantize;

  final LooperEngine engine;
  final AppLocalizations l10n;

  const _TransportStrip({
    required this.slotId,
    required this.state,
    required this.hasContent,
    required this.quantize,
    required this.engine,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final (loopIcon, loopColor, loopActive, loopTooltip) = _loopButtonProps();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Single LOOP button — the only recording/playback control.
          _TransportButton(
            icon: loopIcon,
            color: loopColor,
            active: loopActive,
            tooltip: loopTooltip,
            onTap: () => engine.looperButtonPress(slotId),
          ),
          const SizedBox(width: 6),

          // STOP — always available; stops playback without clearing tracks.
          _TransportButton(
            icon: Icons.stop,
            color: Colors.white70,
            active: false,
            tooltip: l10n.looperStop,
            onTap: () => engine.stop(slotId),
          ),
          const SizedBox(width: 6),

          // CLEAR — erases all tracks and resets to idle.
          _TransportButton(
            icon: Icons.delete_outline,
            color: Colors.white54,
            active: false,
            tooltip: l10n.looperClear,
            onTap: () => engine.clearAll(slotId),
          ),
          const SizedBox(width: 10),

          // Quantize chip — slot-level grid applied to every new recording pass.
          _QuantizeChip(
            slotId: slotId,
            quantize: quantize,
            engine: engine,
            l10n: l10n,
          ),

          const Spacer(),

          // State LCD badge.
          _StateLcd(state: state, l10n: l10n),
        ],
      ),
    );
  }

  /// Returns (icon, color, active, tooltip) for the LOOP button given [state].
  ///
  /// Icon intent: shows what pressing the button will DO next.
  ///   ● record     — press to start recording
  ///   ► play       — press to stop recording and begin playback
  ///   ◎ overdub    — press to queue (or cancel) an overdub layer
  ///   ■ stop       — press to abort the current overdub early
  (IconData, Color, bool, String) _loopButtonProps() => switch (state) {
        // Idle: two sub-cases based on whether tracks exist.
        //   • No tracks → record button (red): press to start recording.
        //   • Has tracks → play button (green): press to resume at bar 1.
        LooperState.idle => hasContent
            ? (Icons.play_circle, _kPlayColor, false, l10n.looperPlay)
            : (
                Icons.fiber_manual_record,
                _kRecColor,
                false,
                l10n.looperRecord,
              ),
        // Armed, waiting for transport — press to cancel.
        LooperState.armed => (
            Icons.fiber_manual_record,
            _kArmedColor,
            true,
            l10n.looperRecord,
          ),
        // Recording — press to stop recording and start playback.
        // play_circle communicates the outcome (playback will begin).
        LooperState.recording => (
            Icons.play_circle,
            _kRecColor,
            true,
            l10n.looperPlay,
          ),
        // First recording done; syncing to bar 1 — same icon, armed colour.
        LooperState.waitingForBar => (
            Icons.play_circle,
            _kArmedColor,
            true,
            l10n.looperPlay,
          ),
        // Playing cleanly — press to queue an overdub at next loop end.
        LooperState.playing => (
            Icons.layers,
            _kOdColor,
            false,
            l10n.looperOverdub,
          ),
        // Overdub queued, still playing — press to cancel the queue.
        LooperState.waitingForOverdub => (
            Icons.layers,
            _kOdColor,
            true,
            l10n.looperOverdub,
          ),
        // Overdubbing — press to abort early (auto-stops at loop end anyway).
        LooperState.overdubbing => (
            Icons.stop,
            _kOdColor,
            true,
            l10n.looperStop,
          ),
      };
}

// ── Transport button ──────────────────────────────────────────────────────────

/// A single square transport button with glow when active.
class _TransportButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  const _TransportButton({
    required this.icon,
    required this.color,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: 0.22)
                : _kPanel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? color : _kBorder,
              width: active ? 1.5 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Icon(icon, size: 18, color: active ? color : Colors.white60),
        ),
      ),
    );
  }
}

// ── State LCD ─────────────────────────────────────────────────────────────────

/// LCD-style badge showing the current looper state text.
class _StateLcd extends StatelessWidget {
  final LooperState state;
  final AppLocalizations l10n;

  const _StateLcd({required this.state, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _labelAndColor(state, l10n);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _kLcdBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  /// Maps [LooperState] to a display label and accent colour.
  (String, Color) _labelAndColor(LooperState state, AppLocalizations l10n) =>
      switch (state) {
        LooperState.idle => ('IDLE', Colors.white54),
        LooperState.armed => (l10n.looperArmed.toUpperCase(), _kArmedColor),
        LooperState.recording => (l10n.looperRecord.toUpperCase(), _kRecColor),
        LooperState.waitingForBar =>
          (l10n.looperWaitingForBar.toUpperCase(), _kArmedColor),
        LooperState.playing => (l10n.looperPlay.toUpperCase(), _kPlayColor),
        LooperState.waitingForOverdub =>
          (l10n.looperWaitingForOverdub.toUpperCase(), _kOdColor),
        LooperState.overdubbing =>
          (l10n.looperOverdub.toUpperCase(), _kOdColor),
      };
}

// ── Track list ────────────────────────────────────────────────────────────────

/// Renders one [_TrackRow] per [LoopTrack] in the session.
class _TrackList extends StatelessWidget {
  final String slotId;
  final List<LoopTrack> tracks;
  final LooperEngine engine;
  final AppLocalizations l10n;

  const _TrackList({
    required this.slotId,
    required this.tracks,
    required this.engine,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < tracks.length; i++)
          _TrackRow(
            slotId: slotId,
            track: tracks[i],
            index: i,
            engine: engine,
            l10n: l10n,
          ),
      ],
    );
  }
}

// ── Track row ─────────────────────────────────────────────────────────────────

/// One recorded loop track: label + chord grid + mute/reverse/speed/delete.
class _TrackRow extends StatelessWidget {
  final String slotId;
  final LoopTrack track;
  final int index;
  final LooperEngine engine;
  final AppLocalizations l10n;

  const _TrackRow({
    required this.slotId,
    required this.track,
    required this.index,
    required this.engine,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _kBorder, width: 0.5)),
      ),
      child: Row(
        children: [
          // Track label.
          SizedBox(
            width: 52,
            child: Text(
              l10n.looperTrack(index + 1),
              style: TextStyle(
                color: track.muted ? Colors.white38 : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),

          // Chord grid — scrollable horizontally.
          Expanded(
            child: _ChordGrid(
              track: track,
              l10n: l10n,
              currentBar: engine.currentPlaybackBarForTrack(slotId, track),
            ),
          ),

          const SizedBox(width: 6),

          // Controls strip: mute · reverse · speed · delete.
          _TrackControls(
            slotId: slotId,
            track: track,
            engine: engine,
            l10n: l10n,
          ),
        ],
      ),
    );
  }
}

// ── Chord grid ────────────────────────────────────────────────────────────────

/// A horizontally scrollable row of bar cells, each showing the chord detected
/// during recording for that bar (or "—" if none was identified).
///
/// When [currentBar] is non-null the matching cell is highlighted with a green
/// glow to indicate the loop's current playback position.
class _ChordGrid extends StatelessWidget {
  final LoopTrack track;
  final AppLocalizations l10n;

  /// 0-based index of the bar currently being played back, or null when not
  /// playing (idle / recording without playback).
  final int? currentBar;

  const _ChordGrid({
    required this.track,
    required this.l10n,
    this.currentBar,
  });

  @override
  Widget build(BuildContext context) {
    final bars = track.chordPerBar;

    // During recording, the chordPerBar may be empty. Show a placeholder.
    if (bars.isEmpty) {
      return Text(
        track.lengthInBeats == null ? '…' : l10n.looperNoChord,
        style: const TextStyle(color: Colors.white38, fontSize: 10),
      );
    }

    final maxBar = bars.keys.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 22,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: maxBar + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 2),
        itemBuilder: (ctx, bar) {
          final chord = bars[bar];
          return _BarCell(
            barIndex: bar,
            chord: chord,
            l10n: l10n,
            isPlaying: bar == currentBar,
          );
        },
      ),
    );
  }
}

/// A single bar cell in the chord grid.
///
/// When [isPlaying] is true the cell is highlighted with a green glow to
/// indicate the loop's current playback position.
class _BarCell extends StatelessWidget {
  final int barIndex;
  final String? chord;
  final AppLocalizations l10n;

  /// Whether the looper's playhead is currently inside this bar.
  final bool isPlaying;

  const _BarCell({
    required this.barIndex,
    required this.chord,
    required this.l10n,
    this.isPlaying = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasChord = chord != null && chord!.isNotEmpty;

    // Playhead highlight takes priority over the chord colour so the active
    // bar is always immediately visible regardless of chord presence.
    final borderColor = isPlaying
        ? _kLcdText
        : hasChord
            ? _kPlayColor.withValues(alpha: 0.4)
            : _kBorder;
    final bgColor = isPlaying
        ? _kLcdText.withValues(alpha: 0.18)
        : hasChord
            ? _kPlayColor.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.03);
    final textColor = isPlaying
        ? _kLcdText
        : hasChord
            ? _kPlayColor
            : Colors.white38;

    return Tooltip(
      message: l10n.looperBar(barIndex + 1),
      child: Container(
        constraints: const BoxConstraints(minWidth: 32),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: isPlaying ? 1.5 : 1.0),
          boxShadow: isPlaying
              ? [
                  BoxShadow(
                    color: _kLcdText.withValues(alpha: 0.35),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            hasChord ? chord! : l10n.looperNoChord,
            style: TextStyle(
              color: textColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Track controls ────────────────────────────────────────────────────────────

/// Compact strip: mute toggle, reverse toggle, speed chips, delete.
class _TrackControls extends StatelessWidget {
  final String slotId;
  final LoopTrack track;
  final LooperEngine engine;
  final AppLocalizations l10n;

  const _TrackControls({
    required this.slotId,
    required this.track,
    required this.engine,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mute.
        _MiniToggle(
          label: 'M',
          active: track.muted,
          activeColor: Colors.orangeAccent,
          tooltip: l10n.looperMute,
          onTap: () => engine.toggleMute(slotId, track.id),
        ),
        const SizedBox(width: 3),

        // Reverse.
        _MiniToggle(
          label: 'R',
          active: track.reversed,
          activeColor: Colors.purpleAccent,
          tooltip: l10n.looperReverse,
          onTap: () => engine.toggleReverse(slotId, track.id),
        ),
        const SizedBox(width: 6),

        // Speed chips.
        _SpeedChips(slotId: slotId, track: track, engine: engine, l10n: l10n),
        const SizedBox(width: 6),

        // Delete track.
        GestureDetector(
          onTap: () => engine.removeTrack(slotId, track.id),
          child: const Icon(Icons.close, size: 14, color: Colors.white38),
        ),
      ],
    );
  }
}

/// A tiny square toggle chip labelled with a single letter (M or R).
class _MiniToggle extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final String tooltip;
  final VoidCallback onTap;

  const _MiniToggle({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.2) : _kPanel,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? activeColor : _kBorder,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: active ? activeColor : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three speed chips: ½× / 1× / 2×. Highlights the active one.
class _SpeedChips extends StatelessWidget {
  final String slotId;
  final LoopTrack track;
  final LooperEngine engine;
  final AppLocalizations l10n;

  const _SpeedChips({
    required this.slotId,
    required this.track,
    required this.engine,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SpeedChip(
          label: l10n.looperHalfSpeed,
          speed: LoopTrackSpeed.half,
          current: track.speed,
          onTap: () => engine.setSpeed(slotId, track.id, LoopTrackSpeed.half),
        ),
        _SpeedChip(
          label: l10n.looperNormalSpeed,
          speed: LoopTrackSpeed.normal,
          current: track.speed,
          onTap: () =>
              engine.setSpeed(slotId, track.id, LoopTrackSpeed.normal),
        ),
        _SpeedChip(
          label: l10n.looperDoubleSpeed,
          speed: LoopTrackSpeed.double_,
          current: track.speed,
          onTap: () =>
              engine.setSpeed(slotId, track.id, LoopTrackSpeed.double_),
        ),
      ],
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final String label;
  final LoopTrackSpeed speed;
  final LoopTrackSpeed current;
  final VoidCallback onTap;

  const _SpeedChip({
    required this.label,
    required this.speed,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = speed == current;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: active ? _kLcdText.withValues(alpha: 0.15) : _kPanel,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? _kLcdText.withValues(alpha: 0.6) : _kBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? _kLcdText : Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Quantize chip ─────────────────────────────────────────────────────────────

/// Slot-level quantize chip shown in the transport strip.
///
/// Tapping cycles the slot's recording-quantize grid through the
/// [LoopQuantize] sequence: off → 1/4 → 1/8 → 1/16 → 1/32 → off → …
///
/// The selected grid is applied to **every new recording pass** for this slot
/// (first-pass and overdubs).  Snapping happens at record-stop time, so the
/// user sets this once before recording and the notes are committed to the
/// nearest grid line when they press stop.
///
/// When [LoopQuantize.off] the chip is dimmed (no snapping).  Otherwise it
/// glows amber to indicate that the next recording pass will be quantized.
class _QuantizeChip extends StatelessWidget {
  final String slotId;
  final LoopQuantize quantize;
  final LooperEngine engine;
  final AppLocalizations l10n;

  const _QuantizeChip({
    required this.slotId,
    required this.quantize,
    required this.engine,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final active = quantize != LoopQuantize.off;
    const activeColor = _kOdColor;

    return Tooltip(
      message: '${l10n.looperQuantize}: ${quantize.label}',
      child: GestureDetector(
        onTap: () => engine.setQuantize(slotId, quantize.next),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.18) : _kPanel,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? activeColor.withValues(alpha: 0.7) : _kBorder,
            ),
          ),
          child: Text(
            'Q:${quantize.label}',
            style: TextStyle(
              color: active ? activeColor : Colors.white60,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Pinned looper bar ─────────────────────────────────────────────────────────

/// A compact one-liner control strip rendered just below the transport bar
/// for every [LooperPluginInstance] that has `pinned == true`.
///
/// It surfaces the three most important looper actions (LOOP / STOP / CLEAR),
/// the quantize chip, and the state LCD — all on a single row — so the user
/// can control the looper without scrolling to its rack slot.
///
/// Place this widget between [TransportBar] and the rack list in the screen
/// scaffold.
class PinnedLooperBar extends StatelessWidget {
  const PinnedLooperBar({super.key});

  @override
  Widget build(BuildContext context) {
    final rack = context.watch<RackState>();
    final engine = context.watch<LooperEngine>();
    final l10n = AppLocalizations.of(context)!;

    // Collect all pinned looper slots.
    final pinned = rack.plugins
        .whereType<LooperPluginInstance>()
        .where((p) => p.pinned)
        .toList();

    if (pinned.isEmpty) return const SizedBox.shrink();

    return Container(
      color: _kBg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: _kBorder),
          for (final plugin in pinned)
            _PinnedLooperRow(
              plugin: plugin,
              engine: engine,
              l10n: l10n,
            ),
        ],
      ),
    );
  }
}

/// One compact row inside [PinnedLooperBar] for a single looper slot.
///
/// Shows: slot name · LOOP · STOP · CLEAR · Q chip · state LCD.
class _PinnedLooperRow extends StatelessWidget {
  final LooperPluginInstance plugin;
  final LooperEngine engine;
  final AppLocalizations l10n;

  const _PinnedLooperRow({
    required this.plugin,
    required this.engine,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final session = engine.session(plugin.id);
    final state = session?.state ?? LooperState.idle;
    final hasContent = session?.tracks
            .any((t) => t.lengthInBeats != null && t.events.isNotEmpty) ??
        false;
    final quantize = session?.quantize ?? LoopQuantize.off;

    // Reuse the same button-property logic from _TransportStrip.
    final strip = _TransportStrip(
      slotId: plugin.id,
      state: state,
      hasContent: hasContent,
      quantize: quantize,
      engine: engine,
      l10n: l10n,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // Slot name label — identifies which looper this row controls.
          Text(
            plugin.displayName,
            style: const TextStyle(
              color: _kLcdText,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 10),
          const VerticalDivider(width: 1, color: _kBorder),
          const SizedBox(width: 10),

          // Compact transport controls — identical behaviour to the full slot.
          Expanded(child: strip),
        ],
      ),
    );
  }
}

// ── Pin toggle ────────────────────────────────────────────────────────────────

/// A small row that toggles whether this looper slot is pinned below
/// the transport bar (like the Jam Mode quick-access panel).
class _PinToggle extends StatelessWidget {
  final LooperPluginInstance plugin;
  final AppLocalizations l10n;

  const _PinToggle({required this.plugin, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final rack = context.read<RackState>();

    return GestureDetector(
      onTap: () => rack.toggleLooperPinned(plugin.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            Icon(
              plugin.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 13,
              color: plugin.pinned ? _kLcdText : Colors.white38,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.looperPinBelow,
              style: TextStyle(
                color: plugin.pinned ? _kLcdText : Colors.white54,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
