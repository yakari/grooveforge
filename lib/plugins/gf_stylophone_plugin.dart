import 'dart:typed_data';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

import '../services/audio_input_ffi.dart';

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

  /// Vibrato LFO depth.
  ///
  /// Normalized [0.0, 1.0]: 0.0 = no vibrato, 1.0 = ±0.5 semitone at 5.5 Hz.
  static const int paramVibrato = 2;

  /// Square-wave duty cycle (pulse width).
  ///
  /// Normalized [0.0, 1.0] maps to [0.1, 0.9]. Default 0.5 = standard 50%.
  /// Lower values (0.125) give the classic NES/Game Boy pulse timbre.
  static const int paramDutyCycle = 3;

  /// White noise blend level.
  ///
  /// Already normalized [0.0, 1.0]: 0 = pure tone, 1 = full white noise.
  static const int paramNoiseMix = 4;

  /// Bit-crusher resolution.
  ///
  /// Normalized [0.0, 1.0] maps to integer bit depth {2, 4, 6, 8, 16}.
  /// Default 1.0 = 16-bit (off). Lower values produce lo-fi crunch.
  static const int paramBitDepth = 5;

  /// Sub-oscillator mix level.
  ///
  /// Already normalized [0.0, 1.0]: 0 = no sub, 1 = maximum sub level.
  static const int paramSubMix = 6;

  /// Sub-oscillator octave offset.
  ///
  /// Normalized [0.0, 1.0] maps to {1, 2}: 0.0 = -1 octave, 1.0 = -2 octaves.
  static const int paramSubOctave = 7;

  // ─── Internal state ───────────────────────────────────────────────────────

  /// Octave offset in full octaves: -2 means two octaves down, +2 two up.
  int _octaveShift = 0;

  /// Active waveform index: 0=Square, 1=Sawtooth, 2=Sine, 3=Triangle.
  int _waveform = 0;

  /// Vibrato LFO depth [0.0, 1.0]. 0.0 = clean tone, 1.0 = full tape-wobble.
  double _vibrato = 0.0;

  /// Square-wave duty cycle [0.1, 0.9]. 0.5 = standard 50% square.
  double _dutyCycle = 0.5;

  /// White noise blend [0.0, 1.0]. 0 = pure tone.
  double _noiseMix = 0.0;

  /// Bit-crusher resolution: 2, 4, 6, 8, or 16 (off).
  int _bitDepth = 16;

  /// Sub-oscillator mix [0.0, 1.0]. 0 = no sub.
  double _subMix = 0.0;

  /// Sub-oscillator octave: 1 = -1 oct, 2 = -2 oct.
  int _subOctave = 1;

  /// Chiptune arp enabled flag.
  bool _chipArpEnabled = false;

  /// Chiptune arp chord type index: 0=off, 1=maj, 2=min, 3=dim, 4=maj7,
  /// 5=min7, 6=dom7, 7=oct, 8=fifth.
  int _chipArpChord = 1;

  /// Chiptune arp rate: 50 (PAL) or 60 (NTSC) Hz.
  double _chipArpRate = 60.0;

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
        GFPluginParameter(
          id: paramVibrato,
          name: 'Vibrato',
          // 0.0 = off, 1.0 = full ±0.5 semitone wobble.
          min: 0,
          max: 1,
          defaultValue: 0.0,
        ),
        GFPluginParameter(
          id: paramDutyCycle,
          name: 'Duty Cycle',
          // Normalized [0, 1] maps to [0.1, 0.9].
          min: 0.1,
          max: 0.9,
          defaultValue: 0.5,
        ),
        GFPluginParameter(
          id: paramNoiseMix,
          name: 'Noise Mix',
          min: 0,
          max: 1,
          defaultValue: 0.0,
        ),
        GFPluginParameter(
          id: paramBitDepth,
          name: 'Bit Depth',
          min: 2,
          max: 16,
          defaultValue: 1.0, // normalized: 1.0 = 16 (off)
        ),
        GFPluginParameter(
          id: paramSubMix,
          name: 'Sub Mix',
          min: 0,
          max: 1,
          defaultValue: 0.0,
        ),
        GFPluginParameter(
          id: paramSubOctave,
          name: 'Sub Octave',
          min: 1,
          max: 2,
          defaultValue: 0.0, // normalized: 0.0 = 1 (-1 oct)
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
      case paramVibrato:
        return _vibrato;
      case paramDutyCycle:
        // Already in [0.1, 0.9] — normalize to [0.0, 1.0] for generic UI.
        return (_dutyCycle - 0.1) / 0.8;
      case paramNoiseMix:
        return _noiseMix;
      case paramBitDepth:
        // Map {2,4,6,8,16} → [0.0, 1.0]. 16 = 1.0.
        return (_bitDepth - 2) / 14.0;
      case paramSubMix:
        return _subMix;
      case paramSubOctave:
        // Map {1, 2} → [0.0, 1.0].
        return (_subOctave - 1).toDouble();
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
      case paramVibrato:
        _vibrato = normalizedValue.clamp(0.0, 1.0);
      case paramDutyCycle:
        // Map [0.0, 1.0] → [0.1, 0.9].
        _dutyCycle = (0.1 + normalizedValue * 0.8).clamp(0.1, 0.9);
      case paramNoiseMix:
        _noiseMix = normalizedValue.clamp(0.0, 1.0);
      case paramBitDepth:
        // Map [0.0, 1.0] → {2, 4, 6, 8, 16} — snap to nearest valid value.
        _bitDepth = (2 + (normalizedValue * 14).round()).clamp(2, 16);
      case paramSubMix:
        _subMix = normalizedValue.clamp(0.0, 1.0);
      case paramSubOctave:
        // Map [0.0, 1.0] → {1, 2}.
        _subOctave = (1 + normalizedValue.round()).clamp(1, 2);
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

  /// Current vibrato depth [0.0, 1.0].
  double get vibrato => _vibrato;

  /// Current duty cycle [0.1, 0.9] for direct UI reads.
  double get dutyCycle => _dutyCycle;

  /// Current noise blend [0.0, 1.0] for direct UI reads.
  double get noiseMix => _noiseMix;

  /// Current bit-crusher depth (2–16) for direct UI reads.
  int get bitDepth => _bitDepth;

  /// Current sub-oscillator mix [0.0, 1.0] for direct UI reads.
  double get subMix => _subMix;

  /// Current sub-oscillator octave (1 or 2) for direct UI reads.
  int get subOctave => _subOctave;

  /// Whether the chiptune arp is enabled.
  bool get chipArpEnabled => _chipArpEnabled;

  /// Current chiptune arp chord type index.
  int get chipArpChord => _chipArpChord;

  /// Current chiptune arp rate in Hz.
  double get chipArpRate => _chipArpRate;

  /// Semitone offset patterns for each chord type.
  ///
  /// Index 0 is unused (off). Indices 1–8 are preset chords. Index 9 is
  /// "custom" — the pattern is built dynamically from held MIDI notes.
  static const List<List<int>> chipArpPatterns = [
    [],               // 0 — off
    [0, 4, 7],        // 1 — Major
    [0, 3, 7],        // 2 — Minor
    [0, 3, 6],        // 3 — Diminished
    [0, 4, 7, 11],    // 4 — Major 7th
    [0, 3, 7, 10],    // 5 — Minor 7th
    [0, 4, 7, 10],    // 6 — Dominant 7th
    [0, 12],          // 7 — Octave
    [0, 7],           // 8 — Fifth
    [],               // 9 — Custom (from held notes)
  ];

  /// Number of preset chord types (excluding "custom").
  static const int chipArpPresetCount = 8;

  /// Index for the custom chord arp mode.
  static const int chipArpCustomIndex = 9;

  // ─── State serialization ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> getState() => {
        'octaveShift': _octaveShift,
        'waveform': _waveform,
        'vibrato': _vibrato,
        'dutyCycle': _dutyCycle,
        'noiseMix': _noiseMix,
        'bitDepth': _bitDepth,
        'subMix': _subMix,
        'subOctave': _subOctave,
        'chipArpEnabled': _chipArpEnabled,
        'chipArpChord': _chipArpChord,
        'chipArpRate': _chipArpRate,
      };

  @override
  void loadState(Map<String, dynamic> state) {
    _octaveShift =
        (state['octaveShift'] as num?)?.toInt().clamp(-2, 2) ?? 0;
    _waveform =
        (state['waveform'] as num?)?.toInt().clamp(0, 3) ?? 0;
    _vibrato =
        (state['vibrato'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;
    _dutyCycle =
        (state['dutyCycle'] as num?)?.toDouble().clamp(0.1, 0.9) ?? 0.5;
    _noiseMix =
        (state['noiseMix'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;
    _bitDepth =
        (state['bitDepth'] as num?)?.toInt().clamp(2, 16) ?? 16;
    _subMix =
        (state['subMix'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 0.0;
    _subOctave =
        (state['subOctave'] as num?)?.toInt().clamp(1, 2) ?? 1;
    _chipArpEnabled = (state['chipArpEnabled'] as bool?) ?? false;
    _chipArpChord =
        (state['chipArpChord'] as num?)?.toInt().clamp(0, chipArpCustomIndex) ?? 1;
    _chipArpRate =
        (state['chipArpRate'] as num?)?.toDouble().clamp(20.0, 120.0) ?? 60.0;
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> initialize(GFPluginContext context) async {}

  @override
  Future<void> dispose() async {}

  // ─── Held-note tracking ────────────────────────────────────────────────
  //
  // The stylophone oscillator is monophonic — only one pitch sounds at a
  // time.  But we need to track ALL held notes so that:
  //   (a) releasing a non-last note doesn't silence the oscillator,
  //   (b) in custom-arp mode, all held notes define the arp pattern.
  //
  // [AudioEngine.playNote] / [stopNote] call [trackNoteOn] / [trackNoteOff]
  // on every note event targeting the stylophone channel.

  /// MIDI notes currently held down (by touch, MIDI controller, or MIDI FX).
  final Set<int> _heldNotes = {};

  /// True when at least one note is held.
  bool get hasHeldNotes => _heldNotes.isNotEmpty;

  /// Called by [AudioEngine.playNote] for every note-on on the stylophone
  /// channel.  Adds [note] to the held set and, when the custom chord arp
  /// is active, rebuilds the native arp pattern.
  void trackNoteOn(int note) {
    _heldNotes.add(note);
    if (_chipArpEnabled && _chipArpChord == chipArpCustomIndex) {
      _pushCustomArpPattern();
    }
  }

  /// Called by [AudioEngine.stopNote] for every note-off on the stylophone
  /// channel.  Removes [note] from the held set and updates the custom arp
  /// pattern if applicable.
  ///
  /// Returns `true` when the released note was the **last** held note —
  /// the caller should silence the oscillator.  Returns `false` when other
  /// notes are still held — the oscillator must keep sounding.
  bool trackNoteOff(int note) {
    _heldNotes.remove(note);
    if (_heldNotes.isEmpty) return true;
    // Still notes held — update custom arp pattern if needed.
    if (_chipArpEnabled && _chipArpChord == chipArpCustomIndex) {
      _pushCustomArpPattern();
    }
    return false;
  }

  /// Rebuilds the native C arp pattern from the currently held notes.
  ///
  /// The lowest held note becomes the base (offset 0); all other notes are
  /// expressed as semitone offsets above it, sorted ascending.
  void _pushCustomArpPattern() {
    if (_heldNotes.isEmpty) return;
    final sorted = _heldNotes.toList()..sort();
    final base = sorted.first;
    final offsets = sorted.map((n) => n - base).toList();
    AudioInputFFI().styloSetChipArpBaseNote(base);
    AudioInputFFI().styloSetChipArpPattern(offsets);
  }

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
