import 'cc_mapping_service.dart';

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

  const CcParamEntry({
    required this.paramKey,
    required this.displayName,
    this.gfpaParamId,
    required this.defaultMode,
    this.cycleCount,
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

  /// Auto-Wah (`com.grooveforge.wah`).
  static const List<CcParamEntry> wah = [
    ..._commonEffectParams,
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

  // ── Instruments ────────────────────────────────────────────────────────

  /// GF Keyboard — slot-addressed so the user can control a specific keyboard.
  static const List<CcParamEntry> gfKeyboard = [
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
    // MIDI FX
    'com.grooveforge.arpeggiator': arpeggiator,
    'com.grooveforge.chord': chordExpand,
    'com.grooveforge.transposer': transposer,
    'com.grooveforge.velocity_curve': velocityCurve,
    'com.grooveforge.gate': gate,
    'com.grooveforge.harmonizer': harmonizer,
    'com.grooveforge.jammode': jamMode,
    // Instruments
    'com.grooveforge.vocoder': vocoder,
    // GF Keyboard uses a special key (not a pluginId)
    '_gf_keyboard': gfKeyboard,
  };
}
