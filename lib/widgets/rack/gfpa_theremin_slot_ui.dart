import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gfpa_plugin_instance.dart';
import '../../plugins/gf_theremin_plugin.dart';
import '../../services/audio_engine.dart';
import '../../services/rack_state.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Rack-slot body for the GFPA Theremin plugin.
///
/// Displays a large dark touch pad that the user plays by pressing and
/// dragging a finger — mimicking the hands-near-antenna gesture of a real
/// theremin:
///
///   • Vertical axis → pitch (bottom = [baseNote], top = highest note in range).
///   • Horizontal axis → volume (CC 7: left = quiet, right = loud).
///
/// A glowing orb follows the touch point for haptic and visual feedback.
/// Releasing the finger silences the instrument and restores full volume.
///
/// Base note and range are adjusted via small +/− buttons beside the pad.
/// Changes are persisted in [GFpaPluginInstance.state] for project save/load.
class GFpaThereminSlotUI extends StatefulWidget {
  const GFpaThereminSlotUI({super.key, required this.plugin});

  final GFpaPluginInstance plugin;

  @override
  State<GFpaThereminSlotUI> createState() => _GFpaThereminSlotUIState();
}

class _GFpaThereminSlotUIState extends State<GFpaThereminSlotUI> {
  /// Current orb position in local pad coordinates; null when silent.
  Offset? _orbPosition;

  /// MIDI note currently sounding (-1 = silent).
  int _activeNote = -1;

  // ─── State helpers ────────────────────────────────────────────────────────

  /// Lowest MIDI note from persistent slot state (defaults to C3 = 48).
  int get _baseNote =>
      (widget.plugin.state['baseNote'] as num?)?.toInt()?.clamp(36, 72) ?? 48;

  /// Pitch range in octaves from persistent slot state (defaults to 2).
  int get _rangeOctaves =>
      (widget.plugin.state['rangeOctaves'] as num?)?.toInt()?.clamp(1, 4) ?? 2;

  // ─── Parameter controls ───────────────────────────────────────────────────

  /// Changes [_baseNote] by [delta] semitones (in 12-semitone steps = 1 octave).
  void _changeBaseNote(int delta, RackState rack) {
    final newBase = (_baseNote + delta * 12).clamp(36, 72);
    widget.plugin.state['baseNote'] = newBase;
    _syncToRegistry();
    rack.notifyListeners();
    setState(() {});
  }

  /// Changes [_rangeOctaves] by [delta] (1 to 4 octaves).
  void _changeRange(int delta, RackState rack) {
    final newRange = (_rangeOctaves + delta).clamp(1, 4);
    widget.plugin.state['rangeOctaves'] = newRange;
    _syncToRegistry();
    rack.notifyListeners();
    setState(() {});
  }

  /// Mirrors slot state into the [GFThereminPlugin] registry instance so
  /// [getParameter] stays consistent with what is shown on screen.
  void _syncToRegistry() {
    final plugin = GFPluginRegistry.instance
        .findById('com.grooveforge.theremin') as GFThereminPlugin?;
    if (plugin == null) return;
    plugin.setParameter(
        GFThereminPlugin.paramBaseNote, (_baseNote - 36) / 36.0);
    plugin.setParameter(
        GFThereminPlugin.paramRange, (_rangeOctaves - 1) / 3.0);
  }

  // ─── Pitch / volume mapping ───────────────────────────────────────────────

  /// Converts a vertical pointer position to the nearest MIDI note.
  ///
  /// Y = 0 (top of pad) → highest note; Y = height (bottom) → lowest note.
  /// This matches the theremin convention where raising the hand raises pitch.
  int _yToNote(double y, double height) {
    // t ∈ [0, 1]: 0 = bottom (low), 1 = top (high).
    final t = 1.0 - (y / height).clamp(0.0, 1.0);
    final semitones = (t * _rangeOctaves * 12).round();
    return (_baseNote + semitones).clamp(0, 127);
  }

  /// Converts a horizontal pointer position to a CC 7 volume value (0–127).
  ///
  /// X = 0 (left) → silent; X = width (right) → full volume.
  int _xToVolume(double x, double width) =>
      ((x / width).clamp(0.0, 1.0) * 127).round();

  // ─── Touch handlers ───────────────────────────────────────────────────────

  /// Called on pointer-down and every pointer-move to update pitch + volume.
  void _onTouch(
      Offset position, Size padSize, AudioEngine engine, int channelIndex) {
    final newNote = _yToNote(position.dy, padSize.height);
    final volume = _xToVolume(position.dx, padSize.width);

    // Update volume via CC 7 (MIDI standard volume controller).
    engine.setControlChange(
        channel: channelIndex, controller: 7, value: volume);

    if (_activeNote == -1) {
      // First touch: start the note.
      engine.playNote(
          channel: channelIndex, key: newNote, velocity: 100);
      _activeNote = newNote;
    } else if (newNote != _activeNote) {
      // Pitch crossed a semitone boundary: legato transition.
      engine.stopNote(channel: channelIndex, key: _activeNote);
      engine.playNote(
          channel: channelIndex, key: newNote, velocity: 100);
      _activeNote = newNote;
    }

    setState(() => _orbPosition = position);
  }

  /// Called when the finger lifts: silence the note and restore full volume.
  void _onRelease(AudioEngine engine, int channelIndex) {
    if (_activeNote >= 0) {
      engine.stopNote(channel: channelIndex, key: _activeNote);
      _activeNote = -1;
    }
    // Restore full volume so subsequent slots are not left at partial volume.
    engine.setControlChange(
        channel: channelIndex, controller: 7, value: 127);
    setState(() => _orbPosition = null);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    final rack = context.read<RackState>();
    final channelIndex = (widget.plugin.midiChannel - 1).clamp(0, 15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Touch pad ───────────────────────────────────────────────────
          Expanded(
            child: SizedBox(
              height: 148,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final padSize = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return Listener(
                    // Raw pointer events avoid arena conflicts with rack scroll.
                    onPointerDown: (e) =>
                        _onTouch(e.localPosition, padSize, engine, channelIndex),
                    onPointerMove: (e) =>
                        _onTouch(e.localPosition, padSize, engine, channelIndex),
                    onPointerUp: (_) => _onRelease(engine, channelIndex),
                    onPointerCancel: (_) => _onRelease(engine, channelIndex),
                    child: _ThereminPad(
                      orbPosition: _orbPosition,
                      baseNote: _baseNote,
                      rangeOctaves: _rangeOctaves,
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(width: 8),

          // ── Controls sidebar ─────────────────────────────────────────────
          _ControlSidebar(
            baseNote: _baseNote,
            rangeOctaves: _rangeOctaves,
            onBaseNoteDecrement: () => _changeBaseNote(-1, rack),
            onBaseNoteIncrement: () => _changeBaseNote(+1, rack),
            onRangeDecrement: () => _changeRange(-1, rack),
            onRangeIncrement: () => _changeRange(+1, rack),
          ),
        ],
      ),
    );
  }
}

// ─── Touch pad ────────────────────────────────────────────────────────────────

/// The main theremin playing surface: a dark gradient pad with a floating
/// glowing orb that appears at the touch point.
class _ThereminPad extends StatelessWidget {
  final Offset? orbPosition;
  final int baseNote;
  final int rangeOctaves;

  const _ThereminPad({
    required this.orbPosition,
    required this.baseNote,
    required this.rangeOctaves,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ── Background gradient ──────────────────────────────────────────
          // Deep blue at the bottom (low pitch) → violet at the top (high pitch),
          // evoking the electromagnetic field around a real theremin antenna.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xFF050510),
                  Color(0xFF120A22),
                  Color(0xFF1E083A),
                ],
              ),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0xFF3A1A5A), width: 1),
              ),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),

          // ── Hint overlays ────────────────────────────────────────────────
          const Positioned(
            left: 8,
            top: 6,
            child: Text(
              '▲ High',
              style: TextStyle(color: Color(0x44FFFFFF), fontSize: 9),
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 6,
            child: Text(
              '▼ Low',
              style: TextStyle(color: Color(0x44FFFFFF), fontSize: 9),
            ),
          ),
          const Positioned(
            right: 8,
            bottom: 6,
            child: Text(
              'Vol ▶',
              style: TextStyle(color: Color(0x44FFFFFF), fontSize: 9),
            ),
          ),

          // ── Glowing orb ──────────────────────────────────────────────────
          // Appears only while the user is touching the pad; follows the
          // pointer exactly so players get immediate visual pitch feedback.
          if (orbPosition != null)
            Positioned(
              // Centre the 48 × 48 orb on the pointer.
              left: orbPosition!.dx - 24,
              top: orbPosition!.dy - 24,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Inner core: bright white-purple.
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.9),
                      Colors.purpleAccent.withValues(alpha: 0.7),
                      Colors.purpleAccent.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                  boxShadow: [
                    // Outer glow — wide spread for the theremin field effect.
                    BoxShadow(
                      color: Colors.purpleAccent.withValues(alpha: 0.6),
                      blurRadius: 32,
                      spreadRadius: 12,
                    ),
                    // Inner sharp glow for a bright core.
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Controls sidebar ─────────────────────────────────────────────────────────

/// Small vertical sidebar with +/− controls for base note and range.
///
/// Displayed to the right of the theremin pad so the controls are always
/// accessible without occluding the playing surface.
class _ControlSidebar extends StatelessWidget {
  final int baseNote;
  final int rangeOctaves;
  final VoidCallback onBaseNoteDecrement;
  final VoidCallback onBaseNoteIncrement;
  final VoidCallback onRangeDecrement;
  final VoidCallback onRangeIncrement;

  const _ControlSidebar({
    required this.baseNote,
    required this.rangeOctaves,
    required this.onBaseNoteDecrement,
    required this.onBaseNoteIncrement,
    required this.onRangeDecrement,
    required this.onRangeIncrement,
  });

  @override
  Widget build(BuildContext context) {
    // Note name for the base note label (e.g. C3, D♯4).
    const noteNames = [
      'C', 'C♯', 'D', 'D♯', 'E',
      'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B',
    ];
    final noteName =
        '${noteNames[baseNote % 12]}${(baseNote ~/ 12) - 1}';

    return SizedBox(
      width: 62,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Base note control.
          _SideControl(
            label: 'BASE',
            value: noteName,
            canDecrement: baseNote > 36,
            canIncrement: baseNote < 72,
            onDecrement: onBaseNoteDecrement,
            onIncrement: onBaseNoteIncrement,
          ),

          const SizedBox(height: 12),

          // Range control.
          _SideControl(
            label: 'RANGE',
            value: '${rangeOctaves}oct',
            canDecrement: rangeOctaves > 1,
            canIncrement: rangeOctaves < 4,
            onDecrement: onRangeDecrement,
            onIncrement: onRangeIncrement,
          ),
        ],
      ),
    );
  }
}

/// A labelled mini +/− control used in [_ControlSidebar].
class _SideControl extends StatelessWidget {
  final String label;
  final String value;
  final bool canDecrement;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _SideControl({
    required this.label,
    required this.value,
    required this.canDecrement,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniButton(
              icon: Icons.remove,
              enabled: canDecrement,
              onPressed: onDecrement,
            ),
            const SizedBox(width: 4),
            _MiniButton(
              icon: Icons.add,
              enabled: canIncrement,
              onPressed: onIncrement,
            ),
          ],
        ),
      ],
    );
  }
}

/// Tiny icon button used inside [_SideControl].
class _MiniButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _MiniButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: enabled
              ? Colors.white12
              : Colors.white.withValues(alpha: 0.04),
          foregroundColor: enabled ? Colors.white70 : Colors.white24,
          shape: const CircleBorder(),
          elevation: 0,
        ),
        onPressed: enabled ? onPressed : null,
        child: Icon(icon, size: 12),
      ),
    );
  }
}
