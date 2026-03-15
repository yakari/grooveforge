import 'dart:typed_data';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// The GrooveForge Stylophone — a GFPA monophonic instrument plugin.
///
/// Mimics the classic Dubreq Stylophone: a palm-held instrument played by
/// pressing a metal stylus against a printed chromatic keyboard strip. The
/// slot UI ([GFpaStyloPhoneSlotUI]) renders the strip and routes all note
/// events directly to the native C synthesiser via AudioInputFFI.
///
/// Audio is produced by a native C oscillator (square/sawtooth/sine/triangle)
/// running in its own miniaudio device, independent of FluidSynth.
///
/// Monophonic constraint is enforced in the slot UI: only one note can sound
/// at a time.  When the stylus slides to a new key, the frequency updates
/// immediately (phase is preserved for click-free legato).
class GFStyloPhonePlugin implements GFInstrumentPlugin {
  GFStyloPhonePlugin();

  // ─── Parameter IDs ────────────────────────────────────────────────────────

  /// Octave shift applied to every note frequency before sending to the synth.
  ///
  /// Normalized [0.0, 1.0] maps to integer offset {-2, -1, 0, +1, +2}.
  /// Default 0.5 = no shift (octave 0).
  static const int paramOctave = 0;

  /// Oscillator waveform selector.
  ///
  /// Normalized [0.0, 1.0] maps to {0=Square, 1=Sawtooth, 2=Sine, 3=Triangle}.
  /// Default 0.0 = Square (classic Stylophone buzz).
  static const int paramWaveform = 1;

  // ─── Internal state ───────────────────────────────────────────────────────

  /// Octave offset in full octaves: -2 means two octaves down, +2 two up.
  int _octaveShift = 0;

  /// Active waveform index: 0=Square, 1=Sawtooth, 2=Sine, 3=Triangle.
  int _waveform = 0;

  // ─── GFPlugin identity ────────────────────────────────────────────────────

  @override
  String get pluginId => 'com.grooveforge.stylophone';

  @override
  String get name => 'Stylophone';

  @override
  String get version => '1.0.0';

  @override
  GFPluginType get type => GFPluginType.instrument;

  @override
  List<GFPluginParameter> get parameters => const [
        GFPluginParameter(
          id: paramOctave,
          name: 'Octave',
          // Display range in actual octaves; UI uses +/- buttons.
          min: -2,
          max: 2,
          // 0.5 maps to shift = 0 (centre of the [-2, +2] range).
          defaultValue: 0.5,
        ),
        GFPluginParameter(
          id: paramWaveform,
          name: 'Waveform',
          // 0=Square, 1=Sawtooth, 2=Sine, 3=Triangle (normalised [0,1]).
          min: 0,
          max: 3,
          defaultValue: 0.0,
        ),
      ];

  // ─── Parameter access ─────────────────────────────────────────────────────

  @override
  double getParameter(int paramId) {
    switch (paramId) {
      case paramOctave:
        // Map _octaveShift ∈ {-2..+2} → normalized [0.0, 1.0].
        return (_octaveShift + 2) / 4.0;
      case paramWaveform:
        // Map {0, 1, 2, 3} → [0.0, 0.333, 0.667, 1.0].
        return _waveform / 3.0;
      default:
        return 0.0;
    }
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    switch (paramId) {
      case paramOctave:
        // Map [0.0, 1.0] → {0, 1, 2, 3, 4} → offset {-2, -1, 0, +1, +2}.
        _octaveShift = (normalizedValue * 4).round().clamp(0, 4) - 2;
      case paramWaveform:
        // Map [0.0, 1.0] → {0, 1, 2, 3}.
        _waveform = (normalizedValue * 3).round().clamp(0, 3);
    }
  }

  // ─── Computed helpers ─────────────────────────────────────────────────────

  /// Lowest MIDI note displayed on the key strip.
  ///
  /// The strip always starts at C; C3 (MIDI 48) is the baseline that shifts
  /// with [_octaveShift].  Clamped to keep the strip within playable range.
  int get baseNote => (48 + _octaveShift * 12).clamp(0, 108);

  /// Current octave shift value in [-2, +2] for direct UI reads.
  int get octaveShift => _octaveShift;

  /// Current waveform index (0=Square, 1=Sawtooth, 2=Sine, 3=Triangle).
  int get waveform => _waveform;

  // ─── State serialization ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> getState() => {
        'octaveShift': _octaveShift,
        'waveform': _waveform,
      };

  @override
  void loadState(Map<String, dynamic> state) {
    _octaveShift =
        (state['octaveShift'] as num?)?.toInt().clamp(-2, 2) ?? 0;
    _waveform =
        (state['waveform'] as num?)?.toInt().clamp(0, 3) ?? 0;
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
    // Audio is produced by the native C Stylophone oscillator (square/saw/sine/
    // triangle) running in its own miniaudio device, started from the slot UI.
    // No Dart-side DSP is performed here.
  }
}
