import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The player's library of hand-made and imported scales.
///
/// **Why scales live in two places.** A custom scale is both a reusable asset
/// and part of a specific piece, so it is stored twice:
///
///   - here, in [SharedPreferences], so it is available in every project on
///     this machine;
///   - inside the Xen slot's own state in the `.gf` file, so a project opened
///     on a machine that has never seen that scale still plays it correctly.
///
/// Duplication is the point. A project that loses its tuning because it was
/// opened on the wrong laptop is the kind of failure that only shows up at
/// rehearsal, and only the second copy prevents it.
///
/// Both paths funnel into [GFScaleLibrary.registerCustom], so the rest of the
/// app resolves every scale — shipped, saved or imported — through one lookup.
class CustomScaleLibrary extends ChangeNotifier {
  CustomScaleLibrary();

  /// SharedPreferences key holding a JSON array of scale objects.
  static const String _prefsKey = 'xen_custom_scales';

  SharedPreferences? _prefs;

  final List<GFScale> _scales = [];

  /// The player's scales, most recently saved last.
  List<GFScale> get scales => List<GFScale>.unmodifiable(_scales);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Loads the library and registers every scale it holds.
  ///
  /// A scale that fails to parse is skipped rather than aborting the load: one
  /// hand-edited entry must not cost the player the rest of their library.
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_prefsKey);
    _scales.clear();
    if (raw != null && raw.isNotEmpty) {
      _scales.addAll(_decode(raw));
    }
    for (final scale in _scales) {
      GFScaleLibrary.registerCustom(scale);
    }
    notifyListeners();
  }

  List<GFScale> _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final out = <GFScale>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        final scale = GFScale.fromJson(entry);
        if (scale != null) out.add(scale);
      }
      return out;
    } catch (_) {
      // Corrupt preferences: start empty rather than refusing to launch.
      return const [];
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────

  /// Adds [scale], or replaces the existing one with the same id.
  Future<void> save(GFScale scale) async {
    final index = _scales.indexWhere((s) => s.id == scale.id);
    if (index >= 0) {
      _scales[index] = scale;
    } else {
      _scales.add(scale);
    }
    GFScaleLibrary.registerCustom(scale);
    await _persist();
    notifyListeners();
  }

  /// Removes the scale with [id] from the library.
  ///
  /// It stays registered for the rest of the session: a Xen slot may be using
  /// it right now, and yanking the tuning out from under a sounding module
  /// would be worse than leaving a scale the player can no longer see in the
  /// list. Projects that reference it keep their own copy regardless.
  Future<void> delete(String id) async {
    _scales.removeWhere((s) => s.id == id);
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _prefsKey,
      jsonEncode([for (final s in _scales) s.toJson()]),
    );
  }

  // ── Import / export ────────────────────────────────────────────────────────

  /// Encodes [scale] as the JSON written by "export scale".
  ///
  /// A single object rather than an array: one file is one scale, which makes
  /// it obvious what is being shared and keeps the format trivially
  /// hand-editable.
  static String encodeForExport(GFScale scale) =>
      const JsonEncoder.withIndent('  ').convert(scale.toJson());

  /// Reads a scale exported by [encodeForExport].
  ///
  /// Returns null on anything unusable, so the caller can tell the player the
  /// file was not a scale instead of crashing on it.
  static GFScale? decodeExported(String contents) {
    try {
      final decoded = jsonDecode(contents);
      if (decoded is! Map<String, dynamic>) return null;
      return GFScale.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  /// Generates an id that no built-in or registered scale is using.
  ///
  /// Ids are what saved projects and CC pad mappings store, so a collision
  /// would silently repoint an existing mapping at the new scale.
  static String generateId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stem = slug.isEmpty ? 'scale' : slug;
    var candidate = 'custom-$stem';
    var suffix = 2;
    while (GFScaleLibrary.byId(candidate) != null) {
      candidate = 'custom-$stem-$suffix';
      suffix++;
    }
    return candidate;
  }
}
