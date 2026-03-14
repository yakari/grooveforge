import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/gfpa_plugin_instance.dart';
import '../../plugins/gf_stylophone_plugin.dart';
import '../../services/audio_engine.dart';
import '../../services/rack_state.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Rack-slot body for the GFPA Stylophone plugin.
///
/// Renders a horizontal chromatic key strip (2 octaves = 25 keys) that the
/// user plays by touching or sliding, mimicking the feel of pressing a metal
/// stylus against the Stylophone's printed keyboard.
///
/// Monophony is enforced here: when the touch slides from one key to the
/// next, [AudioEngine.stopNote] is called on the previous key before
/// [AudioEngine.playNote] is called on the new one.
///
/// The octave shift (−2 to +2) is stored in [GFpaPluginInstance.state] for
/// project persistence and kept in sync with [GFStyloPhonePlugin] in the
/// [GFPluginRegistry].
class GFpaStyloPhoneSlotUI extends StatefulWidget {
  const GFpaStyloPhoneSlotUI({super.key, required this.plugin});

  final GFpaPluginInstance plugin;

  @override
  State<GFpaStyloPhoneSlotUI> createState() => _GFpaStyloPhoneSlotUIState();
}

class _GFpaStyloPhoneSlotUIState extends State<GFpaStyloPhoneSlotUI> {
  /// Index (0-based) of the currently sounding key, or -1 when silent.
  int _activeKeyIndex = -1;

  /// Number of chromatic keys shown: 2 octaves + top C = 25 notes.
  static const int _numKeys = 25;

  // ─── State helpers ────────────────────────────────────────────────────────

  /// Current octave shift from [GFpaPluginInstance.state], defaulting to 0.
  int get _octaveShift =>
      (widget.plugin.state['octaveShift'] as num?)?.toInt() ?? 0;

  /// Lowest MIDI note on the strip given the current octave shift.
  ///
  /// The strip always starts at C; C3 (MIDI 48) is the no-shift baseline.
  int get _baseNote => (48 + _octaveShift * 12).clamp(0, 108);

  /// MIDI note for key [index] (0 = lowest, 24 = highest).
  int _keyToNote(int index) => (_baseNote + index).clamp(0, 127);

  // ─── Octave shift ─────────────────────────────────────────────────────────

  /// Increments or decrements the octave shift and persists it.
  ///
  /// Updates both [GFpaPluginInstance.state] (for project save) and the
  /// [GFStyloPhonePlugin] instance in the registry (for parameter reads).
  void _changeOctave(int delta, RackState rack) {
    final newShift = (_octaveShift + delta).clamp(-2, 2);
    widget.plugin.state['octaveShift'] = newShift;

    // Mirror into the registry plugin so getParameter stays consistent.
    final registryPlugin = GFPluginRegistry.instance
        .findById('com.grooveforge.stylophone') as GFStyloPhonePlugin?;
    registryPlugin?.setParameter(
        GFStyloPhonePlugin.paramOctave, (newShift + 2) / 4.0);

    // Notify rack so autosave picks up the new state.
    rack.notifyListeners();
    setState(() {});
  }

  // ─── Note events ──────────────────────────────────────────────────────────

  /// Converts a horizontal pointer position to a key index.
  int _xToKeyIndex(double x, double totalWidth) {
    final keyWidth = totalWidth / _numKeys;
    return (x / keyWidth).floor().clamp(0, _numKeys - 1);
  }

  /// Starts or slides to a key, enforcing monophony.
  void _pressKey(int keyIndex, AudioEngine engine, int channelIndex) {
    if (keyIndex == _activeKeyIndex) return; // same key — nothing to do

    // Stop the previous note before starting the new one (monophonic legato).
    if (_activeKeyIndex >= 0) {
      engine.stopNote(
          channel: channelIndex, key: _keyToNote(_activeKeyIndex));
    }

    engine.playNote(
        channel: channelIndex, key: _keyToNote(keyIndex), velocity: 100);
    setState(() => _activeKeyIndex = keyIndex);
  }

  /// Releases the currently sounding key.
  void _releaseKey(AudioEngine engine, int channelIndex) {
    if (_activeKeyIndex < 0) return;
    engine.stopNote(channel: channelIndex, key: _keyToNote(_activeKeyIndex));
    setState(() => _activeKeyIndex = -1);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final engine = context.read<AudioEngine>();
    final rack = context.read<RackState>();
    // MIDI channels are 1-indexed; the engine expects 0-indexed.
    final channelIndex = (widget.plugin.midiChannel - 1).clamp(0, 15);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Octave controls ──────────────────────────────────────────────
          _OctaveRow(
            octaveShift: _octaveShift,
            onDecrement: () => _changeOctave(-1, rack),
            onIncrement: () => _changeOctave(+1, rack),
          ),
          const SizedBox(height: 6),

          // ── Key strip ────────────────────────────────────────────────────
          SizedBox(
            height: 64,
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final totalWidth = constraints.maxWidth;
                return Listener(
                  // Use raw pointer events so both taps and slides are captured
                  // without gesture arena conflicts.
                  onPointerDown: (e) => _pressKey(
                      _xToKeyIndex(e.localPosition.dx, totalWidth),
                      engine,
                      channelIndex),
                  onPointerMove: (e) => _pressKey(
                      _xToKeyIndex(e.localPosition.dx, totalWidth),
                      engine,
                      channelIndex),
                  onPointerUp: (_) => _releaseKey(engine, channelIndex),
                  onPointerCancel: (_) => _releaseKey(engine, channelIndex),
                  child: _StyloPhoneStripPainter(
                    numKeys: _numKeys,
                    activeKeyIndex: _activeKeyIndex,
                    baseNote: _baseNote,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Octave row ───────────────────────────────────────────────────────────────

/// A compact row with decrement / increment buttons and a centred label
/// showing the current octave shift ("OCT -1", "OCT 0", "OCT +2", …).
class _OctaveRow extends StatelessWidget {
  final int octaveShift;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _OctaveRow({
    required this.octaveShift,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    // Format the octave shift with a leading + sign for positive values.
    final label =
        'OCT ${octaveShift >= 0 ? '+' : ''}$octaveShift';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _OctaveButton(
          icon: Icons.remove,
          enabled: octaveShift > -2,
          onPressed: onDecrement,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white54,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 6),
        _OctaveButton(
          icon: Icons.add,
          enabled: octaveShift < 2,
          onPressed: onIncrement,
        ),
      ],
    );
  }
}

/// A small round button used for octave up / down.
class _OctaveButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _OctaveButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
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
        child: Icon(icon, size: 14),
      ),
    );
  }
}

// ─── Key strip widget ─────────────────────────────────────────────────────────

/// Draws the Stylophone's chromatic key strip using a [CustomPainter].
///
/// All [numKeys] chromatic keys are the same width (unlike a piano keyboard).
/// Natural notes (C, D, E, F, G, A, B) are rendered in silvery grey; sharps
/// (C♯, D♯, F♯, G♯, A♯) in dark gunmetal. The active key glows amber/gold.
/// Note names are shown at the bottom of each natural-note key.
class _StyloPhoneStripPainter extends StatelessWidget {
  final int numKeys;
  final int activeKeyIndex;
  final int baseNote;

  const _StyloPhoneStripPainter({
    required this.numKeys,
    required this.activeKeyIndex,
    required this.baseNote,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _StripPainter(
          numKeys: numKeys,
          activeKeyIndex: activeKeyIndex,
          baseNote: baseNote,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Low-level [CustomPainter] that draws each chromatic key as a rectangle.
class _StripPainter extends CustomPainter {
  final int numKeys;
  final int activeKeyIndex;
  final int baseNote;

  // Which pitch classes are "sharps" (black-key equivalents).
  // Index by pitchClass (0=C … 11=B).
  static const List<bool> _isSharp = [
    false, true, false, true, false,
    false, true, false, true, false, true, false,
  ];

  // Note names for labels (using unicode sharp ♯ for readability).
  static const List<String> _noteNames = [
    'C', 'C♯', 'D', 'D♯', 'E',
    'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B',
  ];

  const _StripPainter({
    required this.numKeys,
    required this.activeKeyIndex,
    required this.baseNote,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final keyWidth = size.width / numKeys;

    // Background: brushed-metal dark gradient behind all keys.
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4A4A4A), Color(0xFF1E1E1E)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
      bgPaint,
    );

    // Draw each key.
    for (int i = 0; i < numKeys; i++) {
      _drawKey(canvas, i, keyWidth, size.height);
    }
  }

  /// Draws one key at index [i].
  void _drawKey(Canvas canvas, int i, double keyWidth, double height) {
    final midiNote = baseNote + i;
    final pitchClass = midiNote % 12;
    final sharp = _isSharp[pitchClass];
    final active = i == activeKeyIndex;

    // Key bounding rect with a 1 px gap between adjacent keys.
    final rect = Rect.fromLTWH(
      i * keyWidth + 1,
      4,
      keyWidth - 2,
      height - 8,
    );

    // Colour: amber when active, silver for naturals, gunmetal for sharps.
    Color keyColor;
    if (active) {
      keyColor = const Color(0xFFFFAA00);
    } else if (sharp) {
      keyColor = const Color(0xFF383838);
    } else {
      keyColor = const Color(0xFFAAAAAA);
    }

    final keyPaint = Paint()..color = keyColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      keyPaint,
    );

    // Subtle gloss highlight on natural keys (top strip).
    if (!active && !sharp) {
      final glossPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.25);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top, rect.width, 6),
          const Radius.circular(3),
        ),
        glossPaint,
      );
    }

    // Active glow: orange halo behind the active key.
    if (active) {
      final glowPaint = Paint()
        ..color = const Color(0xFFFFAA00).withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), const Radius.circular(5)),
        glowPaint,
      );
    }

    // Label: note name at the bottom of each natural note and the active key.
    if (!sharp || active) {
      _drawLabel(canvas, rect, midiNote, active, sharp);
    }
  }

  /// Draws the note name label (e.g. "C3") centred at the bottom of a key.
  void _drawLabel(
    Canvas canvas,
    Rect keyRect,
    int midiNote,
    bool active,
    bool sharp,
  ) {
    final octave = (midiNote ~/ 12) - 1; // standard MIDI octave convention
    final name = '${_noteNames[midiNote % 12]}$octave';

    final textPainter = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          // Active: dark text on gold key; natural: dark; sharp: white.
          color: active
              ? Colors.black87
              : (sharp ? Colors.white70 : Colors.black54),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: keyRect.width);

    textPainter.paint(
      canvas,
      Offset(
        keyRect.left + (keyRect.width - textPainter.width) / 2,
        keyRect.bottom - textPainter.height - 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.activeKeyIndex != activeKeyIndex ||
      old.baseNote != baseNote ||
      old.numKeys != numKeys;
}
