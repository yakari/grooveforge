import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

import '../models/gm_instruments.dart';
import 'cc_mapping_service.dart';

/// One selectable value for a [CcParamMode.direct] mapping.
///
/// Turns "pad 3 recalls maqam Rast" into data the preferences UI can list and
/// the mapping can persist.
class CcDirectChoice {
  /// Stored in [SlotParamTarget.directValue] — a stable id, never an index.
  final String value;

  /// Label shown in the target picker.
  final String label;

  const CcDirectChoice({required this.value, required this.label});
}

/// Describes one CC-controllable parameter on a plugin type.
///
/// Used by the CC preferences UI to build the hierarchical target picker,
/// and by [RackState] to dispatch incoming CC values to the correct handler.
class CcParamEntry {
  /// Unique key used in [SlotParamTarget.paramKey] (e.g. "bypass", "mix").
  final String paramKey;

  /// Human-readable label (used in UI; not an l10n key for now).
  final String displayName;

  /// GFPA parameter ID for [GFPlugin.setParameter] / [GFPlugin.getParameter].
  /// Null for meta-keys handled specially (bypass, next_patch, waveform, etc.).
  final int? gfpaParamId;

  /// Default CC-to-parameter mapping mode.
  final CcParamMode defaultMode;

  /// Number of discrete values for [CcParamMode.cycle] mode.
  /// Null for absolute and toggle modes.
  final int? cycleCount;

  /// Builds the choices offered for a [CcParamMode.direct] mapping.
  ///
  /// A function rather than a list because the choices come from a runtime
  /// catalogue (the scale library) that cannot be spelled out in a `const`
  /// entry. Null for every other mode.
  final List<CcDirectChoice> Function()? directChoices;

  const CcParamEntry({
    required this.paramKey,
    required this.displayName,
    this.gfpaParamId,
    required this.defaultMode,
    this.cycleCount,
    this.directChoices,
  });
}

/// Static registry of CC-controllable parameters per plugin type.
///
/// NOT embedded in `.gfpd` descriptors — this is a curated Dart-side list
/// that determines which parameters appear in the CC preferences target picker
/// and how incoming CC values are dispatched.
///
/// To add CC support for a new parameter:
/// 1. Add a [CcParamEntry] to the appropriate list below.
/// 2. If the parameter needs special handling (not a standard GFPA param),
///    add a case in [RackState._handleSlotParamCc].
class CcParamRegistry {
  CcParamRegistry._();

  // ── Riff guitar ────────────────────────────────────────────────────────

  /// Riff (`com.grooveforge.riff`). Everything a guitarist's hands do while
  /// playing, so a pedal, a ribbon or a pad can do it: the palm mute and
  /// the pick position are the expressive ones, worth a continuous control;
  /// the pickup selector steps on each press, as a guitar's switch does.
  /// "Mute" is the slot's bypass, which silences an instrument.
  static const List<CcParamEntry> riff = [
    CcParamEntry(
      paramKey: 'bypass',
      displayName: 'Mute',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'palm_mute',
      displayName: 'Palm mute',
      gfpaParamId: 0,
      defaultMode: CcParamMode.absolute,
    ),
    // The same palm mute on a button: each press switches it off, or back to
    // the amount the knob was at (full when never set). The entry above stays
    // for a pedal that rocks the palm on and off the strings.
    CcParamEntry(
      paramKey: 'palm_mute_switch',
      displayName: 'Palm mute on/off',
      gfpaParamId: 0,
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'pick_pos',
      displayName: 'Pick position',
      gfpaParamId: 1,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'attack',
      displayName: 'Attack',
      gfpaParamId: 2,
      defaultMode: CcParamMode.absolute,
    ),
    // A switch: each press flips it, whatever value the pad sends. Holding a
    // pad was not an option: some controllers (the Alesis Vortex) send the
    // same value, 0, on press and on release. A pad that does send 127 while
    // held can use MIDI CC 68, the standard legato pedal, with no mapping.
    CcParamEntry(
      paramKey: 'legato',
      displayName: 'Legato on/off (hammer-on / pull-off)',
      gfpaParamId: 9,
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'legato_overlap',
      displayName: 'Overlap legato on/off',
      gfpaParamId: 10,
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'pickup',
      displayName: 'Pickup',
      gfpaParamId: 3,
      defaultMode: CcParamMode.cycle,
      cycleCount: 4,
    ),
    CcParamEntry(
      paramKey: 'pickup_type',
      displayName: 'Pickup type',
      gfpaParamId: 4,
      defaultMode: CcParamMode.cycle,
      cycleCount: 2,
    ),
    CcParamEntry(
      paramKey: 'tone',
      displayName: 'Tone',
      gfpaParamId: 5,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'sustain',
      displayName: 'Sustain',
      gfpaParamId: 6,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'level',
      displayName: 'Level',
      gfpaParamId: 8,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  // ── Audio effects ──────────────────────────────────────────────────────

  /// Parameters shared by all audio effect plugins.
  static const List<CcParamEntry> _commonEffectParams = [
    CcParamEntry(
      paramKey: 'bypass',
      displayName: 'Bypass',
      defaultMode: CcParamMode.toggle,
    ),
  ];

  /// Plate Reverb (`com.grooveforge.reverb`).
  static const List<CcParamEntry> reverb = [
    ..._commonEffectParams,
    CcParamEntry(
      paramKey: 'mix',
      displayName: 'Mix',
      gfpaParamId: 3,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Ping-Pong Delay (`com.grooveforge.delay`).
  static const List<CcParamEntry> delay = [
    ..._commonEffectParams,
    CcParamEntry(
      paramKey: 'mix',
      displayName: 'Mix',
      gfpaParamId: 4,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'time',
      displayName: 'Time',
      gfpaParamId: 0,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'bpm_sync',
      displayName: 'BPM Sync',
      gfpaParamId: 2,
      defaultMode: CcParamMode.toggle,
    ),
  ];

  /// 4-Band EQ (`com.grooveforge.eq`).
  static const List<CcParamEntry> eq = [
    ..._commonEffectParams,
  ];

  /// Compressor (`com.grooveforge.compressor`).
  static const List<CcParamEntry> compressor = [
    ..._commonEffectParams,
    CcParamEntry(
      paramKey: 'threshold',
      displayName: 'Threshold',
      gfpaParamId: 0,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Chorus / Flanger (`com.grooveforge.chorus`).
  static const List<CcParamEntry> chorus = [
    ..._commonEffectParams,
    CcParamEntry(
      paramKey: 'mix',
      displayName: 'Mix',
      gfpaParamId: 6,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'rate',
      displayName: 'Rate',
      gfpaParamId: 0,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Autotune (`com.grooveforge.autotune`). Strength and Retune are the two
  /// worth riding live: a pedal from natural to robot is the classic move.
  static const List<CcParamEntry> autotune = [
    ..._commonEffectParams,
    CcParamEntry(
      paramKey: 'strength',
      displayName: 'Strength',
      gfpaParamId: 2,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'retune',
      displayName: 'Retune',
      gfpaParamId: 3,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'mix',
      displayName: 'Mix',
      gfpaParamId: 7,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Amp (`com.grooveforge.amp`). The three section switches are what a
  /// guitarist puts under their feet: kick the drive in for a solo, drop the
  /// cab when running into a real speaker. They are two-state selectors, so
  /// [CcParamMode.cycle] with two steps flips them on each press, whatever
  /// value the button sends. Drive, Gain and Level are the knobs worth riding.
  static const List<CcParamEntry> amp = [
    ..._commonEffectParams,
    CcParamEntry(
      paramKey: 'drive_on',
      displayName: 'Drive on/off',
      gfpaParamId: 0,
      defaultMode: CcParamMode.cycle,
      cycleCount: 2,
    ),
    CcParamEntry(
      paramKey: 'amp_on',
      displayName: 'Amp on/off',
      gfpaParamId: 4,
      defaultMode: CcParamMode.cycle,
      cycleCount: 2,
    ),
    CcParamEntry(
      paramKey: 'cab_on',
      displayName: 'Cab on/off',
      gfpaParamId: 10,
      defaultMode: CcParamMode.cycle,
      cycleCount: 2,
    ),
    CcParamEntry(
      paramKey: 'drive_mode',
      displayName: 'Drive type',
      gfpaParamId: 1,
      defaultMode: CcParamMode.cycle,
      cycleCount: 2,
    ),
    CcParamEntry(
      paramKey: 'drive',
      displayName: 'Drive',
      gfpaParamId: 2,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'gain',
      displayName: 'Gain',
      gfpaParamId: 6,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'level',
      displayName: 'Level',
      gfpaParamId: 12,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Wah (`com.grooveforge.wah`). Pedal is the one to put under a foot: in
  /// manual mode it is the wah itself. Mode flips between that and the LFO.
  static const List<CcParamEntry> wah = [
    ..._commonEffectParams,
    CcParamEntry(
      paramKey: 'pedal',
      displayName: 'Pedal',
      gfpaParamId: 9,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'mode',
      displayName: 'Mode',
      gfpaParamId: 8,
      defaultMode: CcParamMode.cycle,
      cycleCount: 2,
    ),
    CcParamEntry(
      paramKey: 'center',
      displayName: 'Center',
      gfpaParamId: 0,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'depth',
      displayName: 'Depth',
      gfpaParamId: 3,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  // ── MIDI FX ────────────────────────────────────────────────────────────

  /// Parameters shared by all MIDI FX plugins.
  static const List<CcParamEntry> _commonMidiFxParams = [
    CcParamEntry(
      paramKey: 'bypass',
      displayName: 'Bypass',
      defaultMode: CcParamMode.toggle,
    ),
  ];

  /// Arpeggiator (`com.grooveforge.arpeggiator`).
  static const List<CcParamEntry> arpeggiator = [
    ..._commonMidiFxParams,
    CcParamEntry(
      paramKey: 'pattern',
      displayName: 'Pattern',
      gfpaParamId: 0,
      defaultMode: CcParamMode.cycle,
      cycleCount: 6,
    ),
    CcParamEntry(
      paramKey: 'division',
      displayName: 'Division',
      gfpaParamId: 1,
      defaultMode: CcParamMode.cycle,
      cycleCount: 9,
    ),
  ];

  /// Chord Expand (`com.grooveforge.chord`).
  static const List<CcParamEntry> chordExpand = [
    ..._commonMidiFxParams,
    CcParamEntry(
      paramKey: 'chord_type',
      displayName: 'Chord Type',
      gfpaParamId: 0,
      defaultMode: CcParamMode.cycle,
      cycleCount: 11,
    ),
  ];

  /// Transposer (`com.grooveforge.transposer`).
  static const List<CcParamEntry> transposer = [
    ..._commonMidiFxParams,
    CcParamEntry(
      paramKey: 'semitones',
      displayName: 'Semitones',
      gfpaParamId: 0,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Velocity Curve (`com.grooveforge.velocity_curve`).
  static const List<CcParamEntry> velocityCurve = [
    ..._commonMidiFxParams,
    CcParamEntry(
      paramKey: 'amount',
      displayName: 'Amount',
      gfpaParamId: 1,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Gate (`com.grooveforge.gate`).
  static const List<CcParamEntry> gate = [
    ..._commonMidiFxParams,
  ];

  /// Harmonizer (`com.grooveforge.harmonizer`).
  static const List<CcParamEntry> harmonizer = [
    ..._commonMidiFxParams,
  ];

  /// Jam Mode (`com.grooveforge.jammode`).
  static const List<CcParamEntry> jamMode = [
    CcParamEntry(
      paramKey: 'bypass',
      displayName: 'Toggle On/Off',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'scale_type',
      displayName: 'Scale Type',
      gfpaParamId: 0,
      defaultMode: CcParamMode.cycle,
      cycleCount: 14,
    ),
    CcParamEntry(
      paramKey: 'detection_mode',
      displayName: 'Detection Mode',
      gfpaParamId: 1,
      defaultMode: CcParamMode.cycle,
      cycleCount: 2,
    ),
  ];

  /// Every scale in the library, as recall choices for a pad bank.
  static List<CcDirectChoice> xenScaleChoices() => GFScaleLibrary.all
      .map((s) => CcDirectChoice(value: s.id, label: s.name))
      .toList(growable: false);

  /// The twelve tonics, as recall choices.
  static List<CcDirectChoice> xenRootChoices() => const [
        CcDirectChoice(value: '0', label: 'C'),
        CcDirectChoice(value: '1', label: 'C#'),
        CcDirectChoice(value: '2', label: 'D'),
        CcDirectChoice(value: '3', label: 'D#'),
        CcDirectChoice(value: '4', label: 'E'),
        CcDirectChoice(value: '5', label: 'F'),
        CcDirectChoice(value: '6', label: 'F#'),
        CcDirectChoice(value: '7', label: 'G'),
        CcDirectChoice(value: '8', label: 'G#'),
        CcDirectChoice(value: '9', label: 'A'),
        CcDirectChoice(value: '10', label: 'A#'),
        CcDirectChoice(value: '11', label: 'B'),
      ];

  /// Xen (`com.grooveforge.xen`).
  ///
  /// Built for a pad bank: `scale` in [CcParamMode.direct] gives one pad per
  /// scale, so a player can jump straight from a raga to a maqam mid-piece,
  /// and several pads can each hold their own scale.
  ///
  /// `next_scale` remains for players with one spare button rather than a
  /// grid, but it steps within the current family — stepping the whole
  /// catalogue would be a walk of forty-odd scales, which is no use on stage.
  static const List<CcParamEntry> xen = [
    CcParamEntry(
      paramKey: 'bypass',
      displayName: 'Toggle On/Off',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'scale',
      displayName: 'Recall Scale',
      defaultMode: CcParamMode.direct,
      directChoices: xenScaleChoices,
    ),
    CcParamEntry(
      paramKey: 'root',
      displayName: 'Recall Root',
      defaultMode: CcParamMode.direct,
      directChoices: xenRootChoices,
    ),
    CcParamEntry(
      paramKey: 'next_scale',
      displayName: 'Next Scale (in family)',
      defaultMode: CcParamMode.cycle,
    ),
    CcParamEntry(
      paramKey: 'snap',
      displayName: 'Snap On/Off',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'tune',
      displayName: 'Tune On/Off',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'latch_root',
      displayName: 'Latch Root from Held Notes',
      defaultMode: CcParamMode.cycle,
    ),
  ];

  // ── Instruments ────────────────────────────────────────────────────────

  /// Every General MIDI instrument, as recall choices for CC direct mapping.
  ///
  /// Only the fallback: a keyboard slot running a custom .sf2 has its own
  /// preset list, which [RackState.ccDirectChoicesFor] substitutes.
  static List<CcDirectChoice> gfKeyboardPatchChoices() =>
      patchChoicesFrom(GmInstruments.list);

  /// Turns a program → name table into recall choices labelled "005 - Name",
  /// sorted by program number. The stored value is the bare program number.
  static List<CcDirectChoice> patchChoicesFrom(Map<int, String> programNames) {
    final programs = programNames.keys.toList()..sort();
    return [
      for (final p in programs)
        CcDirectChoice(
          value: p.toString(),
          label: '${p.toString().padLeft(3, '0')} - ${programNames[p]}',
        ),
    ];
  }

  /// GF Keyboard — slot-addressed so the user can control a specific keyboard.
  static const List<CcParamEntry> gfKeyboard = [
    CcParamEntry(
      paramKey: 'select_patch',
      displayName: 'Select Patch',
      defaultMode: CcParamMode.direct,
      directChoices: gfKeyboardPatchChoices,
    ),
    CcParamEntry(
      paramKey: 'absolute_patch',
      displayName: 'Patch (knob)',
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'next_patch',
      displayName: 'Next Patch',
      defaultMode: CcParamMode.cycle,
    ),
    CcParamEntry(
      paramKey: 'prev_patch',
      displayName: 'Previous Patch',
      defaultMode: CcParamMode.cycle,
    ),
    CcParamEntry(
      paramKey: 'next_soundfont',
      displayName: 'Next Soundfont',
      defaultMode: CcParamMode.cycle,
    ),
    CcParamEntry(
      paramKey: 'prev_soundfont',
      displayName: 'Previous Soundfont',
      defaultMode: CcParamMode.cycle,
    ),
    CcParamEntry(
      paramKey: 'volume',
      displayName: 'Volume',
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Vocoder (`com.grooveforge.vocoder`).
  static const List<CcParamEntry> vocoder = [
    CcParamEntry(
      paramKey: 'waveform',
      displayName: 'Waveform',
      gfpaParamId: 0,
      defaultMode: CcParamMode.cycle,
      cycleCount: 4,
    ),
    CcParamEntry(
      paramKey: 'noise_mix',
      displayName: 'Noise Mix',
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'env_release',
      displayName: 'Envelope Release',
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'bandwidth',
      displayName: 'Bandwidth',
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'gate_threshold',
      displayName: 'Gate Threshold',
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'input_gain',
      displayName: 'Input Gain',
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'volume',
      displayName: 'Volume',
      defaultMode: CcParamMode.absolute,
    ),
  ];

  // ── Other instruments ───────────────────────────────────────────────────

  /// Theremin (`com.grooveforge.theremin`).
  static const List<CcParamEntry> theremin = [
    CcParamEntry(
      paramKey: 'vibrato',
      displayName: 'Vibrato Depth',
      gfpaParamId: 2,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'base_note',
      displayName: 'Base Note',
      gfpaParamId: 0,
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'range',
      displayName: 'Range (octaves)',
      gfpaParamId: 1,
      defaultMode: CcParamMode.absolute,
    ),
  ];

  /// Stylophone — chiptune arp toggle, chord cycling, and rate toggle.
  static const List<CcParamEntry> stylophone = [
    CcParamEntry(
      paramKey: 'chipArpEnabled',
      displayName: 'Chiptune Arp On/Off',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'chipArpChord',
      displayName: 'Chiptune Arp Chord',
      defaultMode: CcParamMode.cycle,
      cycleCount: 9,
    ),
    CcParamEntry(
      paramKey: 'chipArpRate',
      displayName: 'Arp Rate (PAL/NTSC)',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'waveform',
      displayName: 'Waveform',
      defaultMode: CcParamMode.cycle,
      cycleCount: 4,
    ),
    CcParamEntry(
      paramKey: 'vibrato',
      displayName: 'Vibrato',
      defaultMode: CcParamMode.toggle,
    ),
  ];

  /// Drum Generator — start/stop, swing, humanization, and pattern cycling.
  static const List<CcParamEntry> drumGenerator = [
    CcParamEntry(
      paramKey: 'toggle_active',
      displayName: 'Start / Stop',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'swing',
      displayName: 'Swing',
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'humanization',
      displayName: 'Human Feel',
      defaultMode: CcParamMode.absolute,
    ),
    CcParamEntry(
      paramKey: 'next_pattern',
      displayName: 'Next Pattern',
      defaultMode: CcParamMode.cycle,
    ),
    CcParamEntry(
      paramKey: 'prev_pattern',
      displayName: 'Previous Pattern',
      defaultMode: CcParamMode.cycle,
    ),
  ];

  // ── Looper ─────────────────────────────────────────────────────────────

  /// MIDI Looper — loop button and stop mapped as CC-triggered actions.
  static const List<CcParamEntry> looper = [
    CcParamEntry(
      paramKey: 'loop_button',
      displayName: 'Loop Button (Record/Play/Overdub)',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'stop',
      displayName: 'Stop',
      defaultMode: CcParamMode.toggle,
    ),
  ];

  // ── Audio Looper ──────────────────────────────────────────────────────

  /// Audio Looper — loop button (arm/record/play/overdub cycle) and stop,
  /// mirroring the MIDI looper CC surface but routed to
  /// [AudioLooperEngine] instead.
  static const List<CcParamEntry> audioLooper = [
    CcParamEntry(
      paramKey: 'loop_button',
      displayName: 'Loop Button (Arm/Record/Play/Overdub)',
      defaultMode: CcParamMode.toggle,
    ),
    CcParamEntry(
      paramKey: 'stop',
      displayName: 'Stop',
      defaultMode: CcParamMode.toggle,
    ),
  ];

  // ── Lookup ─────────────────────────────────────────────────────────────

  /// Returns the curated parameter list for a given plugin ID.
  ///
  /// Returns null for plugin types that have no CC-controllable parameters
  /// (e.g. unknown or future plugins).
  static List<CcParamEntry>? forPluginId(String pluginId) {
    return _registry[pluginId];
  }

  /// Finds a specific [CcParamEntry] by plugin ID and param key.
  ///
  /// Returns null if the plugin or param is not in the registry.
  static CcParamEntry? findParam(String pluginId, String paramKey) {
    final params = _registry[pluginId];
    if (params == null) return null;
    for (final p in params) {
      if (p.paramKey == paramKey) return p;
    }
    return null;
  }

  /// Master lookup table: plugin ID → curated parameter list.
  static const Map<String, List<CcParamEntry>> _registry = {
    // Audio effects
    'com.grooveforge.reverb': reverb,
    'com.grooveforge.delay': delay,
    'com.grooveforge.eq': eq,
    'com.grooveforge.compressor': compressor,
    'com.grooveforge.chorus': chorus,
    'com.grooveforge.wah': wah,
    'com.grooveforge.autotune': autotune,
    'com.grooveforge.amp': amp,
    // MIDI FX
    'com.grooveforge.arpeggiator': arpeggiator,
    'com.grooveforge.chord': chordExpand,
    'com.grooveforge.transposer': transposer,
    'com.grooveforge.velocity_curve': velocityCurve,
    'com.grooveforge.gate': gate,
    'com.grooveforge.harmonizer': harmonizer,
    'com.grooveforge.jammode': jamMode,
    'com.grooveforge.xen': xen,
    // Instruments
    'com.grooveforge.vocoder': vocoder,
    'com.grooveforge.theremin': theremin,
    'com.grooveforge.stylophone': stylophone,
    'com.grooveforge.riff': riff,
    // GF Keyboard, Drum Generator, Looper use special keys (not pluginIds)
    '_gf_keyboard': gfKeyboard,
    '_drum_generator': drumGenerator,
    '_looper': looper,
    '_audio_looper': audioLooper,
  };
}
