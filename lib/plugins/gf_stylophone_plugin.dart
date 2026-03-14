import 'dart:typed_data';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// The GrooveForge Stylophone — a GFPA monophonic instrument plugin.
///
/// Mimics the classic Dubreq Stylophone: a palm-held instrument played by
/// pressing a metal stylus against a printed chromatic keyboard strip. The
/// slot UI ([GFpaStyloPhoneSlotUI]) renders the strip and routes all note
/// events directly to [AudioEngine.playNote] / [AudioEngine.stopNote], so
/// this class is a thin state holder only.
///
/// Audio is produced by FluidSynth on the MIDI channel assigned to this
/// rack slot — the same path as the built-in GrooveForge Keyboard.
///
/// Monophonic constraint is enforced in the slot UI: only one note can sound
/// at a time. When the stylus slides to a new key, the previous note is
/// silenced before the new one starts.
class GFStyloPhonePlugin implements GFInstrumentPlugin {
  GFStyloPhonePlugin();

  // ─── Parameter IDs ────────────────────────────────────────────────────────

  /// Octave shift applied to every MIDI note before sending to FluidSynth.
  ///
  /// Normalized [0.0, 1.0] maps to integer offset {-2, -1, 0, +1, +2}.
  /// Default 0.5 = no shift (octave 0).
  static const int paramOctave = 0;

  // ─── Internal state ───────────────────────────────────────────────────────

  /// Octave offset in full octaves: -2 means two octaves down, +2 two up.
  int _octaveShift = 0;

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
      ];

  // ─── Parameter access ─────────────────────────────────────────────────────

  @override
  double getParameter(int paramId) {
    // Map _octaveShift ∈ {-2..+2} → normalized [0.0, 1.0].
    if (paramId == paramOctave) return (_octaveShift + 2) / 4.0;
    return 0.0;
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    if (paramId == paramOctave) {
      // Map [0.0, 1.0] → {0, 1, 2, 3, 4} → offset {-2, -1, 0, +1, +2}.
      _octaveShift = (normalizedValue * 4).round().clamp(0, 4) - 2;
    }
  }

  // ─── Computed helpers ─────────────────────────────────────────────────────

  /// Lowest MIDI note displayed on the key strip.
  ///
  /// The strip always starts at C; C3 (MIDI 48) is the baseline that shifts
  /// with [_octaveShift]. Clamped to keep the strip within playable range.
  int get baseNote => (48 + _octaveShift * 12).clamp(0, 108);

  /// Current octave shift value in [-2, +2] for direct UI reads.
  int get octaveShift => _octaveShift;

  // ─── State serialization ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> getState() => {'octaveShift': _octaveShift};

  @override
  void loadState(Map<String, dynamic> state) {
    _octaveShift =
        (state['octaveShift'] as num?)?.toInt()?.clamp(-2, 2) ?? 0;
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> initialize(GFPluginContext context) async {}

  @override
  Future<void> dispose() async {}

  // ─── MIDI (no-op — audio routed via AudioEngine in the slot UI) ───────────

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
    // Audio is produced by FluidSynth via AudioEngine.playNote / stopNote,
    // called from GFpaStyloPhoneSlotUI. No Dart-side DSP is performed here.
  }
}
