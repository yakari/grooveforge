import '../models/drum_pattern_data.dart';

/// Singleton registry that holds all known [DrumPatternData] objects.
///
/// Bundled `.gfdrum` patterns are loaded at app startup by `main.dart` and
/// registered here.  User-loaded custom patterns are also registered for
/// the duration of the session.
///
/// The registry is intentionally simple: no change notifications are needed
/// because patterns are registered before the UI renders.
class DrumPatternRegistry {
  /// The single shared instance.
  static final instance = DrumPatternRegistry._();

  /// Private constructor — use [instance].
  DrumPatternRegistry._();

  /// Internal storage: pattern id → pattern data.
  final Map<String, DrumPatternData> _patterns = {};

  /// Registers [pattern] under its [DrumPatternData.id].
  ///
  /// Overwrites any previously registered pattern with the same id.
  void register(DrumPatternData pattern) => _patterns[pattern.id] = pattern;

  /// Looks up a pattern by [id], returning null if not found.
  DrumPatternData? find(String id) => _patterns[id];

  /// Returns an unmodifiable view of all registered patterns.
  List<DrumPatternData> get all =>
      List.unmodifiable(_patterns.values.toList());

  /// Returns all patterns belonging to [family] (e.g. `'rock'`, `'jazz'`).
  List<DrumPatternData> byFamily(String family) =>
      all.where((p) => p.family == family).toList();

  /// Returns the sorted list of distinct family names.
  List<String> get families {
    final result = all.map((p) => p.family).toSet().toList();
    result.sort();
    return result;
  }
}
