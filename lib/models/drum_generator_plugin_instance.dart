import 'plugin_instance.dart';

/// How the drum generator introduces itself before the first bar.
///
/// Used in [DrumStructureConfig] to choose the count-in behaviour.
enum DrumIntroType {
  /// No introduction — the groove starts immediately on bar 1.
  none,

  /// A single-bar metronome count-in (4 rimshots at 4/4, or matching time sig).
  countIn1,

  /// A two-bar metronome count-in.
  countIn2,

  /// Four rimshots on beats 1–4 (the traditional "chopsticks" count-in).
  /// Plays on the virtual bar −1 before bar 0.
  chopsticks,
}

/// How often fill bars are inserted into the groove.
///
/// Fills add rhythmic complexity and tension, typically before a new section.
enum DrumFillFrequency {
  /// No fills — the groove loops without interruption.
  off,

  /// Insert a fill every 4 bars.
  every4,

  /// Insert a fill every 8 bars (a common default for most genres).
  every8,

  /// Insert a fill every 16 bars.
  every16,

  /// Random placement: the engine picks a fill interval between 8 and 24 bars.
  random,
}

/// Extension on [DrumFillFrequency] to convert the enum into a bar interval.
extension DrumFillFrequencyBars on DrumFillFrequency {
  /// Returns the fill period in bars, or -1 for [DrumFillFrequency.off],
  /// or 0 for [DrumFillFrequency.random] (caller handles random selection).
  int get bars {
    switch (this) {
      case DrumFillFrequency.off:
        return -1;
      case DrumFillFrequency.every4:
        return 4;
      case DrumFillFrequency.every8:
        return 8;
      case DrumFillFrequency.every16:
        return 16;
      case DrumFillFrequency.random:
        return 0; // caller seeded random picks a value between 8 and 24
    }
  }
}

/// How often the engine inserts sparse or silent break bars.
///
/// Breaks provide dramatic tension before fills and reintroductions.
enum DrumBreakFrequency {
  /// No breaks — the groove plays continuously.
  none,

  /// Breaks occur infrequently (roughly every 32–48 bars, random).
  rare,

  /// Breaks occur regularly (roughly every 16–24 bars, random).
  occasional,

  /// Breaks occur often (roughly every 8–12 bars, random).
  frequent,
}

/// Per-slot structure configuration for [DrumGeneratorPluginInstance].
///
/// Controls the macro-level arrangement: count-ins, fills, breaks, and
/// whether a crash cymbal lands after each fill resolution.
class DrumStructureConfig {
  /// Which count-in style to play before bar 0.
  final DrumIntroType introType;

  /// How frequently fill bars are inserted.
  final DrumFillFrequency fillFrequency;

  /// How frequently break bars are inserted.
  final DrumBreakFrequency breakFrequency;

  /// Length of a break in bars (1 or 2).
  final int breakLengthBars;

  /// When true, a crash cymbal accent lands on beat 1 after every fill bar.
  final bool crashAfterFill;

  /// When true, the engine gradually increases velocity/density over 8 bars,
  /// simulating a live drummer building intensity.
  final bool dynamicBuild;

  /// Constructs a [DrumStructureConfig] with sensible defaults.
  const DrumStructureConfig({
    this.introType = DrumIntroType.chopsticks,
    this.fillFrequency = DrumFillFrequency.every8,
    this.breakFrequency = DrumBreakFrequency.none,
    this.breakLengthBars = 1,
    this.crashAfterFill = true,
    this.dynamicBuild = true,
  });

  /// Serialises this config to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'introType': introType.name,
        'fillFrequency': fillFrequency.name,
        'breakFrequency': breakFrequency.name,
        'breakLengthBars': breakLengthBars,
        'crashAfterFill': crashAfterFill,
        'dynamicBuild': dynamicBuild,
      };

  /// Reconstructs a [DrumStructureConfig] from its serialised map.
  factory DrumStructureConfig.fromJson(Map<String, dynamic> json) {
    return DrumStructureConfig(
      introType: _parseEnum(
        DrumIntroType.values,
        json['introType'] as String?,
        DrumIntroType.chopsticks,
      ),
      fillFrequency: _parseEnum(
        DrumFillFrequency.values,
        json['fillFrequency'] as String?,
        DrumFillFrequency.every8,
      ),
      breakFrequency: _parseEnum(
        DrumBreakFrequency.values,
        json['breakFrequency'] as String?,
        DrumBreakFrequency.none,
      ),
      breakLengthBars: (json['breakLengthBars'] as num?)?.toInt() ?? 1,
      crashAfterFill: (json['crashAfterFill'] as bool?) ?? true,
      dynamicBuild: (json['dynamicBuild'] as bool?) ?? true,
    );
  }

  /// Helper: find an enum value by [name], returning [fallback] if not found.
  static T _parseEnum<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    if (name == null) return fallback;
    return values.firstWhere((v) => v.name == name, orElse: () => fallback);
  }
}

/// Rack slot model for the Drum Track Generator.
///
/// Stores all configuration needed to describe a drum slot: MIDI channel,
/// pattern selection (builtin or custom file), swing and humanization
/// overrides, and structural arrangement config.
///
/// The engine ([DrumGeneratorEngine]) holds the runtime state and scheduling
/// for each slot; this model is purely data and survives project saves.
class DrumGeneratorPluginInstance implements PluginInstance {
  @override
  final String id;

  /// MIDI channel (1–16). Default 10 = GM drum channel.
  @override
  int midiChannel;

  /// Path to a custom .sf2 soundfont for this drum slot.
  /// Null = use the app-wide default soundfont.
  String? soundfontPath;

  /// ID of the currently active bundled pattern (e.g. `'rock_basic'`).
  /// Null when a custom `.gfdrum` file is loaded instead.
  String? builtinPatternId;

  /// Absolute path to a user-loaded `.gfdrum` file.
  /// Null when a bundled pattern is active.
  String? customPatternPath;

  /// Per-slot swing ratio override.
  ///
  /// `null` = use the pattern's built-in feel default.
  /// `0.5` = perfectly straight (no swing).
  /// `0.67` = jazz triplet swing.
  /// `0.75` = heavy swing.
  double? swingOverride;

  /// Amount of human-feel randomisation applied to timing and velocity.
  ///
  /// `0.0` = robotic/quantised — hits land exactly on the grid.
  /// `1.0` = full humanisation — timing jitter and velocity drift at maximum.
  double humanizationAmount;

  /// When true this slot is actively generating and scheduling MIDI hits.
  bool isActive;

  /// Arrangement structure config: count-ins, fills, breaks.
  DrumStructureConfig structureConfig;

  /// Constructs a [DrumGeneratorPluginInstance] with sane defaults.
  DrumGeneratorPluginInstance({
    required this.id,
    this.midiChannel = 10,
    this.soundfontPath,
    this.builtinPatternId,
    this.customPatternPath,
    this.swingOverride,
    this.humanizationAmount = 0.7,
    this.isActive = false,
    DrumStructureConfig? structureConfig,
  }) : structureConfig = structureConfig ?? const DrumStructureConfig();

  @override
  String get displayName => 'Drum Generator';

  // ── JSON persistence ───────────────────────────────────────────────────────

  @override
  Map<String, dynamic> toJson() => {
        'type': 'drum_generator',
        'id': id,
        'midiChannel': midiChannel,
        if (soundfontPath != null) 'soundfontPath': soundfontPath,
        if (builtinPatternId != null) 'builtinPatternId': builtinPatternId,
        if (customPatternPath != null) 'customPatternPath': customPatternPath,
        if (swingOverride != null) 'swingOverride': swingOverride,
        'humanizationAmount': humanizationAmount,
        'isActive': isActive,
        'structureConfig': structureConfig.toJson(),
      };

  /// Deserialises a [DrumGeneratorPluginInstance] from its JSON map.
  factory DrumGeneratorPluginInstance.fromJson(Map<String, dynamic> json) {
    final cfgJson = json['structureConfig'] as Map<String, dynamic>?;
    return DrumGeneratorPluginInstance(
      id: json['id'] as String,
      midiChannel: (json['midiChannel'] as num?)?.toInt() ?? 10,
      soundfontPath: json['soundfontPath'] as String?,
      builtinPatternId: json['builtinPatternId'] as String?,
      customPatternPath: json['customPatternPath'] as String?,
      swingOverride: (json['swingOverride'] as num?)?.toDouble(),
      humanizationAmount:
          (json['humanizationAmount'] as num?)?.toDouble() ?? 0.7,
      isActive: (json['isActive'] as bool?) ?? false,
      structureConfig:
          cfgJson != null ? DrumStructureConfig.fromJson(cfgJson) : null,
    );
  }
}
