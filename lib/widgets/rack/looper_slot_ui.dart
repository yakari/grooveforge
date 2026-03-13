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
          // ── Transport strip (REC / PLAY / STOP / CLEAR + state LCD) ────────
          _TransportStrip(
            slotId: widget.plugin.id,
            state: session?.state ?? LooperState.idle,
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

/// The main control row: REC · PLAY · STOP · CLEAR + state LCD badge.
class _TransportStrip extends StatelessWidget {
  final String slotId;
  final LooperState state;
  final LooperEngine engine;
  final AppLocalizations l10n;

  const _TransportStrip({
    required this.slotId,
    required this.state,
    required this.engine,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // REC button — first recording pass only (not shown when playing).
          // Pressing it while idle/armed starts a new first-pass recording.
          // Pressing while recording stops and begins playback.
          _TransportButton(
            icon: Icons.fiber_manual_record,
            color: _kRecColor,
            active: state == LooperState.recording ||
                state == LooperState.armed,
            tooltip: l10n.looperRecord,
            onTap: state == LooperState.playing ||
                    state == LooperState.overdubbing
                ? () {} // disabled during play/OD — use OD button instead
                : () => engine.toggleRecord(slotId),
          ),
          const SizedBox(width: 6),

          // PLAY button — toggles playback.
          _TransportButton(
            icon: Icons.play_arrow,
            color: _kPlayColor,
            active: state == LooperState.playing ||
                state == LooperState.overdubbing ||
                state == LooperState.waitingForBar,
            tooltip: l10n.looperPlay,
            onTap: () => engine.togglePlay(slotId),
          ),
          const SizedBox(width: 6),

          // OVERDUB button — amber, enabled only when a loop is playing.
          // Starts a new layer recording on top of the existing playback.
          _TransportButton(
            icon: Icons.layers,
            color: _kOdColor,
            active: state == LooperState.overdubbing,
            tooltip: l10n.looperOverdub,
            onTap: state == LooperState.playing ||
                    state == LooperState.overdubbing
                ? () => engine.toggleRecord(slotId)
                : () {}, // no-op when idle — must be playing first
          ),
          const SizedBox(width: 6),

          // STOP — always available, neutral colour.
          _TransportButton(
            icon: Icons.stop,
            color: Colors.white54,
            active: false,
            tooltip: l10n.looperStop,
            onTap: () => engine.stop(slotId),
          ),
          const SizedBox(width: 6),

          // CLEAR — erases all tracks.
          _TransportButton(
            icon: Icons.delete_outline,
            color: Colors.white38,
            active: false,
            tooltip: l10n.looperClear,
            onTap: () => engine.clearAll(slotId),
          ),

          const Spacer(),

          // State LCD badge.
          _StateLcd(state: state, l10n: l10n),
        ],
      ),
    );
  }
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
          child: Icon(icon, size: 18, color: active ? color : Colors.white38),
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
        LooperState.idle => ('IDLE', Colors.white24),
        LooperState.armed => (l10n.looperArmed.toUpperCase(), _kArmedColor),
        LooperState.recording => (l10n.looperRecord.toUpperCase(), _kRecColor),
        LooperState.waitingForBar =>
          (l10n.looperWaitingForBar.toUpperCase(), _kArmedColor),
        LooperState.playing => (l10n.looperPlay.toUpperCase(), _kPlayColor),
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
                color: track.muted ? Colors.white24 : Colors.white54,
                fontSize: 10,
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
        style: const TextStyle(color: Colors.white24, fontSize: 10),
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
            : Colors.white24;

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
              fontSize: 9,
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
          child: const Icon(Icons.close, size: 14, color: Colors.white24),
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
                color: active ? activeColor : Colors.white24,
                fontSize: 9,
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
            color: active ? _kLcdText : Colors.white24,
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
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
              color: plugin.pinned ? _kLcdText : Colors.white24,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.looperPinBelow,
              style: TextStyle(
                color: plugin.pinned ? _kLcdText : Colors.white38,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
