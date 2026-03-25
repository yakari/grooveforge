import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import '../models/drum_pattern_data.dart';

/// Parses a YAML string (content of a `.gfdrum` file) into a [DrumPatternData].
///
/// The `.gfdrum` format is a human-authored YAML descriptor that describes
/// a complete drum pattern including instruments, sections, and humanisation
/// settings.  See `assets/drums/` for bundled examples.
///
/// Usage:
/// ```dart
/// final data = DrumPatternParser.parse(yamlContent, id: 'rock_basic');
/// ```
class DrumPatternParser {
  // Prevent instantiation — all methods are static.
  DrumPatternParser._();

  // ── Step grid velocity scalars ─────────────────────────────────────────────

  /// Maps step grid characters to a velocity fraction of [DrumInstrumentDef.baseVelocity].
  static const Map<String, double> _kVelocityScale = {
    'X': 1.00, // strong hit
    'x': 0.75, // medium hit
    'o': 0.55, // soft hit
    'g': 0.28, // ghost note
  };

  // ── Feel string mapping ────────────────────────────────────────────────────

  /// Maps the `feel` YAML string to the [DrumFeel] enum value.
  static const Map<String, DrumFeel> _kFeelMap = {
    'straight': DrumFeel.straight,
    'laid_back': DrumFeel.laidBack,
    'pushed': DrumFeel.pushed,
    'swing_light': DrumFeel.swingLight,
    'swing_hard': DrumFeel.swingHard,
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Parses [yaml] into a [DrumPatternData], assigning [id] as the pattern ID.
  ///
  /// Returns null and logs a warning if parsing fails for any reason.
  /// Never throws — callers can safely ignore a null result and continue
  /// loading other patterns.
  ///
  /// [id] should be the filename stem (e.g. `'rock_basic'` for
  /// `rock_basic.gfdrum`).
  static DrumPatternData? parse(String yaml, {required String id}) {
    try {
      final doc = loadYaml(yaml);
      if (doc is! YamlMap) {
        debugPrint('[DrumPatternParser] $id: root is not a map');
        return null;
      }
      return _parseRoot(doc, id);
    } catch (e, st) {
      debugPrint('[DrumPatternParser] $id: parse error — $e\n$st');
      return null;
    }
  }

  // ── Root document parsing ──────────────────────────────────────────────────

  /// Extracts all top-level fields from the YAML root map.
  static DrumPatternData _parseRoot(YamlMap doc, String id) {
    final name = _str(doc, 'name') ?? id;
    final family = _str(doc, 'family') ?? 'other';
    final feel = _kFeelMap[_str(doc, 'feel') ?? ''] ?? DrumFeel.straight;
    final timeSig = _parseTimeSignature(doc);
    final resolution = _int(doc, 'resolution') ?? 16;
    final instruments = _parseInstruments(doc);
    final humanization = _parseHumanization(doc);
    final sections = _parseSections(doc, instruments);

    return DrumPatternData(
      id: id,
      name: name,
      family: family,
      timeSignature: timeSig,
      resolution: resolution,
      feel: feel,
      instruments: instruments,
      humanization: humanization,
      sections: sections,
    );
  }

  // ── Time signature ─────────────────────────────────────────────────────────

  /// Reads `time_signature: [num, den]` and returns it as a record.
  static (int, int) _parseTimeSignature(YamlMap doc) {
    final ts = doc['time_signature'];
    if (ts is YamlList && ts.length >= 2) {
      final numerator = (ts[0] as num).toInt();
      final denominator = (ts[1] as num).toInt();
      return (numerator, denominator);
    }
    return (4, 4); // sensible default
  }

  // ── Instruments ────────────────────────────────────────────────────────────

  /// Parses the `instruments:` block into a name→[DrumInstrumentDef] map.
  static Map<String, DrumInstrumentDef> _parseInstruments(YamlMap doc) {
    final result = <String, DrumInstrumentDef>{};
    final raw = doc['instruments'];
    if (raw is! YamlMap) return result;

    for (final entry in raw.entries) {
      final name = entry.key as String;
      final def = _parseInstrumentDef(entry.value);
      if (def != null) result[name] = def;
    }
    return result;
  }

  /// Parses a single instrument definition map.
  static DrumInstrumentDef? _parseInstrumentDef(dynamic raw) {
    if (raw is! YamlMap) return null;
    final note = (raw['note'] as num?)?.toInt();
    if (note == null) return null;

    return DrumInstrumentDef(
      note: note,
      baseVelocity: (raw['base_velocity'] as num?)?.toInt() ?? 100,
      velocityRange: (raw['velocity_range'] as num?)?.toInt() ?? 15,
      timingJitter: (raw['timing_jitter'] as num?)?.toDouble() ?? 0.02,
      rush: (raw['rush'] as num?)?.toDouble() ?? 0.0,
      durationBeats: (raw['duration_beats'] as num?)?.toDouble() ?? 0.1,
    );
  }

  // ── Humanisation ──────────────────────────────────────────────────────────

  /// Parses the `humanization:` block.
  static DrumHumanizationDef _parseHumanization(YamlMap doc) {
    final raw = doc['humanization'];
    if (raw is! YamlMap) return const DrumHumanizationDef();

    return DrumHumanizationDef(
      timingJitter: (raw['timing_jitter'] as num?)?.toDouble() ?? 0.015,
      velocityJitter: (raw['velocity_jitter'] as num?)?.toDouble() ?? 12,
      velocityDrift: (raw['velocity_drift'] as num?)?.toDouble() ?? 0.05,
    );
  }

  // ── Sections ───────────────────────────────────────────────────────────────

  /// Parses the `sections:` block into a name→[DrumSection] map.
  static Map<String, DrumSection> _parseSections(
    YamlMap doc,
    Map<String, DrumInstrumentDef> instruments,
  ) {
    final result = <String, DrumSection>{};
    final raw = doc['sections'];
    if (raw is! YamlMap) return result;

    for (final entry in raw.entries) {
      final sectionName = entry.key as String;
      final section = _parseSection(
        entry.value,
        sectionName: sectionName,
        instruments: instruments,
      );
      if (section != null) result[sectionName] = section;
    }
    return result;
  }

  /// Parses a single section definition.
  static DrumSection? _parseSection(
    dynamic raw, {
    required String sectionName,
    required Map<String, DrumInstrumentDef> instruments,
  }) {
    if (raw is! YamlMap) return null;

    final typeStr = _str(raw, 'type') ?? 'loop';
    final bars = _int(raw, 'bars') ?? 1;

    // count_in sections use special hit-based generation, not step grids.
    if (typeStr == 'count_in') {
      return _parseCountInSection(raw, bars);
    }

    // sequence sections play bar_grids in order.
    if (typeStr == 'sequence') {
      return _parseSequenceSection(raw, bars, instruments);
    }

    // Default: loop section with random weighted variation selection.
    return _parseLoopSection(raw, bars, instruments);
  }

  /// Parses a count-in section from the `hits` and `note` fields.
  static DrumSection _parseCountInSection(YamlMap raw, int bars) {
    final hits = _int(raw, 'hits') ?? 4;
    final note = _int(raw, 'note') ?? 37; // GM rimshot default

    return DrumSection(
      bars: bars,
      kind: DrumSectionKind.countIn,
      countInHits: hits,
      countInNote: note,
      variations: const [],
    );
  }

  /// Parses a sequence section from `bar_grids` (list of per-bar grids).
  static DrumSection _parseSequenceSection(
    YamlMap raw,
    int bars,
    Map<String, DrumInstrumentDef> instruments,
  ) {
    final barGridsList = raw['bar_grids'];
    final List<Map<String, String>> barSequence = [];

    if (barGridsList is YamlList) {
      for (final barEntry in barGridsList) {
        if (barEntry is YamlMap) {
          final grid = <String, String>{};
          for (final kv in barEntry.entries) {
            final instrName = kv.key as String;
            final gridStr = kv.value?.toString() ?? '';
            if (instruments.containsKey(instrName) && gridStr.isNotEmpty) {
              grid[instrName] = gridStr;
            }
          }
          barSequence.add(grid);
        }
      }
    }

    // Wrap the bar sequence in a single variation so the engine can handle it.
    final variation = DrumVariation(
      name: 'sequence',
      weight: 1,
      barSequence: barSequence,
    );

    return DrumSection(
      bars: bars,
      kind: DrumSectionKind.sequence,
      variations: [variation],
    );
  }

  /// Parses a loop section from its `variations:` list.
  static DrumSection _parseLoopSection(
    YamlMap raw,
    int bars,
    Map<String, DrumInstrumentDef> instruments,
  ) {
    final varRaw = raw['variations'];
    final variations = <DrumVariation>[];

    if (varRaw is YamlList) {
      // Each entry in the list is a named variation with optional weight
      // and one grid entry per instrument.
      for (final varEntry in varRaw) {
        final v = _parseVariation(varEntry, instruments);
        if (v != null) variations.add(v);
      }
    } else {
      // Short-hand: no `variations:` wrapper — the raw map IS the single
      // variation (instrument grids at top level).
      final v = _parseVariationFromMap(raw, name: 'main', instruments: instruments);
      if (v != null) variations.add(v);
    }

    return DrumSection(
      bars: bars,
      kind: DrumSectionKind.loop,
      variations: variations.isEmpty
          ? [const DrumVariation(name: 'empty', weight: 1)]
          : variations,
    );
  }

  /// Parses a single variation entry from a YamlMap.
  static DrumVariation? _parseVariation(
    dynamic raw,
    Map<String, DrumInstrumentDef> instruments,
  ) {
    if (raw is! YamlMap) return null;
    final name = _str(raw, 'name') ?? 'unnamed';
    return _parseVariationFromMap(raw, name: name, instruments: instruments);
  }

  /// Extracts step grids from [raw], skipping non-instrument keys.
  static DrumVariation? _parseVariationFromMap(
    YamlMap raw, {
    required String name,
    required Map<String, DrumInstrumentDef> instruments,
  }) {
    final weight = _int(raw, 'weight') ?? 1;
    final grids = <String, String>{};

    for (final kv in raw.entries) {
      final key = kv.key as String;
      // Skip meta keys; only record instrument grid strings.
      if (key == 'name' || key == 'weight' || key == 'type' || key == 'bars') {
        continue;
      }
      if (!instruments.containsKey(key)) continue;
      final gridStr = kv.value?.toString() ?? '';
      if (gridStr.isNotEmpty) grids[key] = gridStr;
    }

    if (grids.isEmpty) return null;
    return DrumVariation(name: name, weight: weight, stepGrids: grids);
  }

  // ── YAML helpers ──────────────────────────────────────────────────────────

  /// Reads a string value from [map] at [key], returning null if absent.
  static String? _str(YamlMap map, String key) {
    final v = map[key];
    return v?.toString();
  }

  /// Reads an integer value from [map] at [key], returning null if absent.
  static int? _int(YamlMap map, String key) {
    final v = map[key];
    if (v is num) return v.toInt();
    return null;
  }

  // ── Public velocity helper ────────────────────────────────────────────────

  /// Converts a step-grid character to a velocity fraction.
  ///
  /// Returns 0.0 for rests (`.` or unknown characters), otherwise returns
  /// a value in `0.0–1.0` representing the fraction of [DrumInstrumentDef.baseVelocity].
  static double velocityScale(String char) => _kVelocityScale[char] ?? 0.0;
}
