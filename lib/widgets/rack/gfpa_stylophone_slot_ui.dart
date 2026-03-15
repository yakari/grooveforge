import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/audio_port_id.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../models/looper_plugin_instance.dart';
import '../../models/vst3_plugin_instance.dart';
import '../../plugins/gf_stylophone_plugin.dart';
import '../../services/audio_engine.dart';
import '../../services/audio_graph.dart';
import '../../services/audio_input_ffi.dart';
import '../../services/looper_engine.dart';
import '../../services/rack_state.dart';
import '../../services/vst_host_service.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Rack-slot body for the GFPA Stylophone plugin.
///
/// Renders a horizontal chromatic key strip (2 octaves = 25 keys) that the
/// user plays by touching or sliding, mimicking the feel of pressing a metal
/// stylus against the Stylophone's printed keyboard.
///
/// Monophony is enforced here: when the touch slides from one key to the next,
/// [AudioInputFFI.styloNoteOn] is called with the new frequency.  Because the
/// native C oscillator preserves phase across frequency changes, the legato
/// transition is click-free.
///
/// A waveform selector row (SQR / SAW / SIN / TRI) is displayed between the
/// octave controls and the key strip.
///
/// **MIDI OUT**: every key press dispatches a MIDI note-on (and every release
/// a note-off) to all slots connected via the back-panel MIDI OUT jack.  This
/// lets the Stylophone drive a GF Keyboard, VST3, or MIDI Looper slot.  When
/// the MUTE toggle is on the native C synthesiser is silenced while MIDI
/// events continue to flow.
///
/// The octave shift (−2 to +2), waveform (0–3), vibrato, and mute flag are
/// stored in [GFpaPluginInstance.state] for project persistence and kept in
/// sync with [GFStyloPhonePlugin] in the [GFPluginRegistry].
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

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Start the native C oscillator for this slot.
    AudioInputFFI().styloStart();
    // Sync waveform if it was persisted from a previous session.
    final saved = _waveform;
    if (saved != 0) {
      AudioInputFFI().styloSetWaveform(saved);
    }
    // Sync vibrato if it was persisted from a previous session.
    final savedVib = _vibrato;
    if (savedVib > 0.0) AudioInputFFI().styloSetVibrato(savedVib);
  }

  @override
  void dispose() {
    // Silence and stop the native device before releasing resources.
    AudioInputFFI().styloNoteOff();
    AudioInputFFI().styloStop();
    super.dispose();
  }

  // ─── State helpers ────────────────────────────────────────────────────────

  /// Current octave shift from [GFpaPluginInstance.state], defaulting to 0.
  int get _octaveShift =>
      (widget.plugin.state['octaveShift'] as num?)?.toInt() ?? 0;

  /// Current waveform index from [GFpaPluginInstance.state], defaulting to 0.
  int get _waveform =>
      (widget.plugin.state['waveform'] as num?)?.toInt().clamp(0, 3) ?? 0;

  /// Current vibrato depth from [GFpaPluginInstance.state], defaulting to 0.0.
  double get _vibrato =>
      (widget.plugin.state['vibrato'] as num?)?.toDouble().clamp(0.0, 1.0) ??
      0.0;

  /// Lowest MIDI note on the strip given the current octave shift.
  ///
  /// The strip always starts at C; C3 (MIDI 48) is the no-shift baseline.
  int get _baseNote => (48 + _octaveShift * 12).clamp(0, 108);

  /// MIDI note for key [index] (0 = lowest, 24 = highest).
  int _keyToNote(int index) => (_baseNote + index).clamp(0, 127);

  /// Converts a MIDI note number to frequency in Hz.
  ///
  /// Uses the standard equal-temperament formula: A4 = 440 Hz, MIDI 69.
  double _keyToHz(int keyIndex) =>
      440.0 * pow(2.0, (_keyToNote(keyIndex) - 69.0) / 12.0).toDouble();

  /// Whether the native C synthesiser is muted (MIDI OUT continues to flow).
  bool get _muteSound =>
      (widget.plugin.state['muteSound'] as bool?) ?? false;

  // ─── MIDI OUT dispatch ────────────────────────────────────────────────────

  /// Sends a MIDI note-on to every slot connected to this plugin's MIDI OUT
  /// jack.  Mirrors the routing logic of [_RackSlotWidget._dispatchMidiNoteOn]
  /// so Looper, VST3, and FluidSynth targets are all handled correctly.
  void _dispatchNoteOn(BuildContext context, int note) {
    final cables = context
        .read<AudioGraph>()
        .connectionsFrom(widget.plugin.id)
        .where((c) => c.fromPort == AudioPortId.midiOut)
        .toList();
    if (cables.isEmpty) return;

    // Channel index: GFpaPluginInstance stores 1-indexed MIDI channel.
    final ch = (widget.plugin.midiChannel - 1).clamp(0, 15);
    final status = 0x90 | (ch & 0x0F);
    final engine = context.read<AudioEngine>();

    for (final cable in cables) {
      final target = context
          .read<RackState>()
          .plugins
          .where((p) => p.id == cable.toSlotId)
          .firstOrNull;
      if (target == null) continue;

      if (target is LooperPluginInstance) {
        context.read<LooperEngine>().feedMidiEvent(target.id, status, note, 100);
        continue;
      }

      final targetCh = (target.midiChannel - 1).clamp(0, 15);
      if (target is Vst3PluginInstance) {
        context.read<VstHostService>().noteOn(target.id, 0, note, 1.0);
        engine.noteOnUiOnly(channel: targetCh, key: note);
      } else {
        engine.playNote(channel: targetCh, key: note, velocity: 100);
      }
    }
  }

  /// Sends a MIDI note-off to every slot connected to this plugin's MIDI OUT
  /// jack.  Mirrors [_dispatchNoteOn].
  void _dispatchNoteOff(BuildContext context, int note) {
    final cables = context
        .read<AudioGraph>()
        .connectionsFrom(widget.plugin.id)
        .where((c) => c.fromPort == AudioPortId.midiOut)
        .toList();
    if (cables.isEmpty) return;

    final ch = (widget.plugin.midiChannel - 1).clamp(0, 15);
    final status = 0x80 | (ch & 0x0F);
    final engine = context.read<AudioEngine>();

    for (final cable in cables) {
      final target = context
          .read<RackState>()
          .plugins
          .where((p) => p.id == cable.toSlotId)
          .firstOrNull;
      if (target == null) continue;

      if (target is LooperPluginInstance) {
        context.read<LooperEngine>().feedMidiEvent(target.id, status, note, 0);
        continue;
      }

      final targetCh = (target.midiChannel - 1).clamp(0, 15);
      if (target is Vst3PluginInstance) {
        context.read<VstHostService>().noteOff(target.id, 0, note);
        engine.noteOffUiOnly(channel: targetCh, key: note);
      } else {
        engine.stopNote(channel: targetCh, key: note);
      }
    }
  }

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
    rack.markDirty();
    setState(() {});
  }

  /// Changes the oscillator waveform and persists the selection.
  ///
  /// Updates slot state, the native C oscillator, and the registry plugin.
  void _changeWaveform(int waveform, RackState rack) {
    widget.plugin.state['waveform'] = waveform;
    // Propagate to native synth immediately (no latency).
    AudioInputFFI().styloSetWaveform(waveform);
    // Mirror into the registry plugin so getParameter stays consistent.
    final registryPlugin = GFPluginRegistry.instance
        .findById('com.grooveforge.stylophone') as GFStyloPhonePlugin?;
    registryPlugin?.setParameter(
        GFStyloPhonePlugin.paramWaveform, waveform / 3.0);
    rack.markDirty();
    setState(() {});
  }

  /// Toggles the native synthesiser mute flag.
  ///
  /// When muted, key presses still dispatch MIDI OUT events so connected
  /// instruments (GFK, VST3, etc.) continue to respond, but the built-in C
  /// oscillator is silenced.
  void _toggleMute(RackState rack) {
    widget.plugin.state['muteSound'] = !_muteSound;
    // If currently playing, silence the native oscillator immediately.
    if (_muteSound && _activeKeyIndex >= 0) AudioInputFFI().styloNoteOff();
    rack.markDirty();
    setState(() {});
  }

  /// Toggles vibrato between off (0.0) and on (0.7).
  ///
  /// A depth of 0.7 gives a noticeable but musically tasteful tape-wobble
  /// without over-modulating the pitch.
  void _toggleVibrato(RackState rack) {
    final newVal = _vibrato > 0.0 ? 0.0 : 0.7;
    widget.plugin.state['vibrato'] = newVal;
    AudioInputFFI().styloSetVibrato(newVal);
    // Mirror into the registry plugin so getParameter stays consistent.
    final reg = GFPluginRegistry.instance
        .findById('com.grooveforge.stylophone') as GFStyloPhonePlugin?;
    reg?.setParameter(GFStyloPhonePlugin.paramVibrato, newVal);
    rack.markDirty();
    setState(() {});
  }

  // ─── Note events ──────────────────────────────────────────────────────────

  /// Converts a horizontal pointer position to a key index.
  int _xToKeyIndex(double x, double totalWidth) {
    final keyWidth = totalWidth / _numKeys;
    return (x / keyWidth).floor().clamp(0, _numKeys - 1);
  }

  /// Starts or slides to a key, enforcing monophony.
  ///
  /// Phase is preserved in the native synth so sliding between keys is
  /// click-free (no pop at transitions).
  ///
  /// Also dispatches a MIDI note-on (and note-off for the previous key) to
  /// any slots wired to the MIDI OUT jack.  Native audio is skipped when the
  /// MUTE toggle is on.
  void _pressKey(int keyIndex, BuildContext ctx) {
    if (keyIndex == _activeKeyIndex) return; // same key — nothing to do

    final note = _keyToNote(keyIndex);
    final prevNote = _activeKeyIndex >= 0 ? _keyToNote(_activeKeyIndex) : -1;

    // Native sound — skipped when muted.
    if (!_muteSound) AudioInputFFI().styloNoteOn(_keyToHz(keyIndex));

    // MIDI OUT: release previous note then press new one.
    if (prevNote >= 0) _dispatchNoteOff(ctx, prevNote);
    _dispatchNoteOn(ctx, note);

    setState(() => _activeKeyIndex = keyIndex);
  }

  /// Releases the currently sounding key.
  ///
  /// Silences native audio (unless muted) and sends a MIDI note-off to any
  /// connected MIDI OUT targets.
  void _releaseKey(BuildContext ctx) {
    if (_activeKeyIndex < 0) return;
    final note = _keyToNote(_activeKeyIndex);
    if (!_muteSound) AudioInputFFI().styloNoteOff();
    _dispatchNoteOff(ctx, note);
    setState(() => _activeKeyIndex = -1);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Octave controls ──────────────────────────────────────────────
          _OctaveRow(
            octaveShift: _octaveShift,
            onDecrement: () => _changeOctave(-1, rack),
            onIncrement: () => _changeOctave(1, rack),
          ),
          const SizedBox(height: 6),

          // ── Waveform selector ────────────────────────────────────────────
          _WaveformRow(
            currentWaveform: _waveform,
            onWaveformSelected: (w) => _changeWaveform(w, rack),
            l10n: l10n,
          ),
          const SizedBox(height: 4),

          // ── Vibrato + Mute toggles ───────────────────────────────────────
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _VibratoRow(
                vibratoOn: _vibrato > 0.0,
                onToggle: () => _toggleVibrato(rack),
              ),
              const SizedBox(width: 4),
              // MUTE silences the native synth while MIDI OUT keeps flowing.
              _ModeButton(
                label: l10n.midiMuteOwnSound,
                selected: _muteSound,
                onTap: () => _toggleMute(rack),
              ),
            ],
          ),
          const SizedBox(height: 4),

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
                      _xToKeyIndex(e.localPosition.dx, totalWidth), ctx),
                  onPointerMove: (e) => _pressKey(
                      _xToKeyIndex(e.localPosition.dx, totalWidth), ctx),
                  onPointerUp: (_) => _releaseKey(ctx),
                  onPointerCancel: (_) => _releaseKey(ctx),
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

// ─── Waveform selector row ─────────────────────────────────────────────────────

/// A row of four pill-shaped toggle buttons for selecting the Stylophone waveform.
///
/// Labels are localised short abbreviations: SQR / SAW / SIN / TRI.
/// The active waveform is highlighted in the same purple accent as the
/// Theremin mode toggle, keeping the visual language consistent.
class _WaveformRow extends StatelessWidget {
  final int currentWaveform;
  final ValueChanged<int> onWaveformSelected;
  final AppLocalizations l10n;

  const _WaveformRow({
    required this.currentWaveform,
    required this.onWaveformSelected,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    // Map waveform index → localised label.
    final labels = [
      l10n.styloWaveformSquare,
      l10n.styloWaveformSawtooth,
      l10n.styloWaveformSine,
      l10n.styloWaveformTriangle,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _ModeButton(
            label: labels[i],
            selected: currentWaveform == i,
            onTap: () => onWaveformSelected(i),
          ),
        ],
      ],
    );
  }
}

// ─── Mode toggle button (shared visual language with Theremin) ────────────────

/// A small pill-shaped toggle button used in the waveform selector row.
///
/// When [selected] is true the button is highlighted in purple.
/// Mirrors the visual style of the Theremin PAD/CAM mode buttons.
class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? Colors.purpleAccent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? Colors.purpleAccent.withValues(alpha: 0.65)
                : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: selected ? Colors.purpleAccent : Colors.white54,
          ),
        ),
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
    final label = 'OCT ${octaveShift >= 0 ? '+' : ''}$octaveShift';

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

// ─── Vibrato toggle row ───────────────────────────────────────────────────────

/// A compact row with a single VIB toggle button for the stylophone.
///
/// When active, a 5.5 Hz vibrato LFO wobbles the pitch by ±0.5 semitone,
/// reproducing the tape-wobble effect of vintage Stylophones.
class _VibratoRow extends StatelessWidget {
  final bool vibratoOn;
  final VoidCallback onToggle;

  const _VibratoRow({required this.vibratoOn, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: vibratoOn
                  ? Colors.purpleAccent.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: vibratoOn
                    ? Colors.purpleAccent.withValues(alpha: 0.65)
                    : Colors.white24,
              ),
            ),
            child: Text(
              'VIB',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
                color: vibratoOn ? Colors.purpleAccent : Colors.white38,
              ),
            ),
          ),
        ),
      ],
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
