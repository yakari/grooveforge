import '../audio/audio_source_descriptor.dart';
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

  /// One bar of sticks clicked together, before the groove. The number of
  /// clicks is the pattern's own (the `hits` of its `intro` section), so a
  /// waltz counts three.
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

  /// Phrases of 8, 12 or 16 bars, drawn at random, each ending in a fill.
  random,
}

/// Extension on [DrumFillFrequency] to convert the enum into a bar interval.
extension DrumFillFrequencyBars on DrumFillFrequency {
  /// Returns the fill period in bars, or -1 for [DrumFillFrequency.off],
  /// or 0 for [DrumFillFrequency.random] (see [DrumArranger.phraseLength]).
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
        return 0; // the arranger draws 8, 12 or 16 per phrase
    }
  }
}

/// How often a phrase opens with the pattern's `break` section (the band
/// drops out, or the drums thin down) instead of the groove.
///
/// Breaks land only at the start of a phrase, right after a fill, never in
/// the middle of one. See [DrumArranger.breakChance] for the odds.
enum DrumBreakFrequency {
  /// No breaks — the groove plays continuously.
  none,

  /// About one phrase in five.
  rare,

  /// About two phrases in five.
  occasional,

  /// Most phrases.
  frequent,
}

/// Per-slot structure configuration for [DrumGeneratorPluginInstance].
///
/// Controls the macro-level arrangement: count-ins, fills, breaks, and
/// whether a crash cymbal lands after each fill resolution. The arranger
/// ([DrumArranger]) turns it into a plan for each bar.
class DrumStructureConfig {
  /// Which count-in style to play before bar 0.
  final DrumIntroType introType;

  /// How frequently fill bars are inserted.
  final DrumFillFrequency fillFrequency;

  /// How frequently break bars are inserted.
  final DrumBreakFrequency breakFrequency;

  /// When true, a crash cymbal lands on the first beat after a count-in, a
  /// fill or a break.
  final bool crashAfterFill;

  /// When true, each phrase starts a little softer and rises to full
  /// velocity before its fill, as a drummer builds towards the next section.
  final bool dynamicBuild;

  /// Constructs a [DrumStructureConfig] with sensible defaults.
  const DrumStructureConfig({
    this.introType = DrumIntroType.chopsticks,
    this.fillFrequency = DrumFillFrequency.every8,
    this.breakFrequency = DrumBreakFrequency.none,
    this.crashAfterFill = true,
    this.dynamicBuild = true,
  });

  /// A copy with the given fields replaced.
  DrumStructureConfig copyWith({
    DrumIntroType? introType,
    DrumFillFrequency? fillFrequency,
    DrumBreakFrequency? breakFrequency,
    bool? crashAfterFill,
    bool? dynamicBuild,
  }) {
    return DrumStructureConfig(
      introType: introType ?? this.introType,
      fillFrequency: fillFrequency ?? this.fillFrequency,
      breakFrequency: breakFrequency ?? this.breakFrequency,
      crashAfterFill: crashAfterFill ?? this.crashAfterFill,
      dynamicBuild: dynamicBuild ?? this.dynamicBuild,
    );
  }

  /// Serialises this config to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'introType': introType.name,
        'fillFrequency': fillFrequency.name,
        'breakFrequency': breakFrequency.name,
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
class DrumGeneratorPluginInstance
    with AudioSourcePlugin
    implements PluginInstance {
  @override
  AudioSourceDescriptor describeAudioSource() => const AudioSourceDescriptor(
        kind: AudioSourceKind.drumGenerator,
      );

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

  /// Text of the user-loaded `.gfdrum` file, saved in the project.
  ///
  /// The path alone is not enough: the file may have moved, and on Android
  /// the picker often hands back a temporary copy that is gone by the next
  /// launch. Keeping the text makes the project play the same pattern
  /// wherever it is opened.
  String? customPatternYaml;

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
    this.customPatternYaml,
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
        if (customPatternYaml != null) 'customPatternYaml': customPatternYaml,
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
      customPatternYaml: json['customPatternYaml'] as String?,
      swingOverride: (json['swingOverride'] as num?)?.toDouble(),
      humanizationAmount:
          (json['humanizationAmount'] as num?)?.toDouble() ?? 0.7,
      isActive: (json['isActive'] as bool?) ?? false,
      structureConfig:
          cfgJson != null ? DrumStructureConfig.fromJson(cfgJson) : null,
    );
  }
}
