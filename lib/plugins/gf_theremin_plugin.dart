import 'dart:typed_data';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// The GrooveForge Theremin — a GFPA touch-controlled instrument plugin.
///
/// Emulates the eerie, pitch-wavering theremin: the player's finger position
/// on the pad controls pitch (vertical axis) and volume (horizontal axis)
/// without pressing any discrete key.  Monophonic: only one note sounds at a
/// time.
///
/// All touch handling and audio routing are performed by [GFpaThereminSlotUI].
/// This class holds parameter state only:
///   • [paramBaseNote] — lowest MIDI note reachable at the bottom of the pad.
///   • [paramRange]    — pitch range (1–4 octaves) covered by the pad height.
///   • [paramVibrato]  — 6.5 Hz vibrato LFO depth (0 = off, 1 = full).
///
/// Audio is produced by a native C sine oscillator with smooth portamento
/// and vibrato running in its own miniaudio device, independent of FluidSynth.
class GFThereminPlugin implements GFInstrumentPlugin {
  GFThereminPlugin();

  // ─── Parameter IDs ────────────────────────────────────────────────────────

  /// Lowest MIDI note reachable when the finger is at the bottom of the pad.
  ///
  /// Normalized [0.0, 1.0] → integer MIDI note [36 (C2), 72 (C5)].
  /// Default ≈ 0.33 → MIDI 48 (C3).
  static const int paramBaseNote = 0;

  /// Pitch range in octaves covered by the full vertical travel of the pad.
  ///
  /// Normalized [0.0, 1.0] → {1, 2, 3, 4} octaves = {12, 24, 36, 48} semitones.
  /// Default ≈ 0.33 → 2 octaves.
  static const int paramRange = 1;

  /// Vibrato LFO depth applied by the native C synth's 6.5 Hz oscillator.
  ///
  /// Already normalized [0.0, 1.0]: 0 = no vibrato, 1 = ±0.5 semitone.
  /// Default 0.0 = no vibrato.
  static const int paramVibrato = 2;

  // ─── Internal state ───────────────────────────────────────────────────────

  /// Lowest MIDI note (bottom of the pad).
  int _baseNote = 48; // C3

  /// Pitch range in octaves (1–4).
  int _rangeOctaves = 2;

  /// Vibrato depth [0.0, 1.0] (0 = off, 1 = full ±0.5 st modulation).
  double _vibrato = 0.0;

  // ─── GFPlugin identity ────────────────────────────────────────────────────

  @override
  String get pluginId => 'com.grooveforge.theremin';

  @override
  String get name => 'Theremin';

  @override
  String get version => '1.0.0';

  @override
  GFPluginType get type => GFPluginType.instrument;

  @override
  List<GFPluginParameter> get parameters => const [
        GFPluginParameter(
          id: paramBaseNote,
          name: 'Base Note',
          min: 36,
          max: 72,
          defaultValue: 0.33,
          unitLabel: 'MIDI',
        ),
        GFPluginParameter(
          id: paramRange,
          name: 'Range',
          min: 1,
          max: 4,
          defaultValue: 0.33,
          unitLabel: 'oct',
        ),
        GFPluginParameter(
          id: paramVibrato,
          name: 'Vibrato',
          min: 0,
          max: 1,
          defaultValue: 0.0,
        ),
      ];

  // ─── Parameter access ─────────────────────────────────────────────────────

  @override
  double getParameter(int paramId) {
    switch (paramId) {
      case paramBaseNote:
        // Map [36, 72] → [0.0, 1.0].
        return (_baseNote - 36) / 36.0;
      case paramRange:
        // Map {1, 2, 3, 4} → [0.0, 0.33, 0.67, 1.0].
        return (_rangeOctaves - 1) / 3.0;
      case paramVibrato:
        // Already normalised [0.0, 1.0].
        return _vibrato;
      default:
        return 0.0;
    }
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    switch (paramId) {
      case paramBaseNote:
        // Map [0.0, 1.0] → MIDI note [36, 72] in semitone steps.
        _baseNote = (36 + (normalizedValue * 36).round()).clamp(36, 72);
      case paramRange:
        // Map [0.0, 1.0] → {1, 2, 3, 4}.
        _rangeOctaves = (1 + (normalizedValue * 3).round()).clamp(1, 4);
      case paramVibrato:
        // Depth is already normalised — clamp for safety.
        _vibrato = normalizedValue.clamp(0.0, 1.0);
    }
  }

  // ─── Computed helpers for the slot UI ─────────────────────────────────────

  /// Lowest MIDI note (bottom of the pad), for direct UI reads.
  int get baseNote => _baseNote;

  /// Pitch range in octaves (1–4), for direct UI reads.
  int get rangeOctaves => _rangeOctaves;

  /// Current vibrato depth [0.0, 1.0], for direct UI reads.
  double get vibrato => _vibrato;

  // ─── State serialization ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> getState() => {
        'baseNote': _baseNote,
        'rangeOctaves': _rangeOctaves,
        'vibrato': _vibrato,
      };

  @override
  void loadState(Map<String, dynamic> state) {
    _baseNote =
        (state['baseNote'] as num?)?.toInt().clamp(36, 72) ?? 48;
    _rangeOctaves =
        (state['rangeOctaves'] as num?)?.toInt().clamp(1, 4) ?? 2;
    _vibrato =
        (state['vibrato'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> initialize(GFPluginContext context) async {}

  @override
  Future<void> dispose() async {}

  // ─── MIDI (no-op — audio routed via native C synth in the slot UI) ────────

  @override
  void noteOn(int channel, int note, int velocity) {}

  @override
  void noteOff(int channel, int note) {}

  @override
  void pitchBend(int channel, double semitones) {}

  @override
  void controlChange(int channel, int cc, int value) {}

  @override
  void processBlock(Float32List outL, Float32List outR, int frameCount) {
    // Audio is produced by the native C theremin oscillator (sine + 3rd harmonic,
    // with portamento and vibrato LFO) running in its own miniaudio device.
    // No Dart-side DSP is performed here.
  }
}
