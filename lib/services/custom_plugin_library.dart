import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What happened when a `.gfpd` file was installed.
enum GfpdInstallStatus {
  /// The plugin is registered and saved in the library.
  installed,

  /// The file is not a valid plugin descriptor.
  invalid,

  /// The file uses an id reserved for the plugins that ship with the app.
  reservedId,
}

/// The user's own `.gfpd` plugins, kept from one launch to the next.
///
/// **Why plugins live in two places.** Like a custom scale (see
/// `CustomScaleLibrary`), a user plugin is both a reusable tool and part of
/// the projects that use it, so it is stored twice:
///
///   - here, in [SharedPreferences], so it stays in the `+` menu after a
///     restart;
///   - inside each rack slot that uses it
///     (`GFpaPluginInstance.descriptorSource`), so a project opened on another
///     machine, or after the plugin was removed from the menu, still plays.
///
/// Installing a file whose id is already installed replaces the old version:
/// that is how an edited file is reloaded without restarting the app.
class CustomPluginLibrary {
  CustomPluginLibrary._();

  /// The library shared by the whole app.
  static final CustomPluginLibrary instance = CustomPluginLibrary._();

  /// Ids starting with this belong to the plugins that ship with the app. A
  /// user file may not use them: the bundled plugins' native sound is chosen
  /// by id, so a lookalike would take their place with a different panel.
  static const String reservedIdPrefix = 'com.grooveforge.';

  /// SharedPreferences key holding a JSON object, plugin id → `.gfpd` text.
  static const String _prefsKey = 'custom_gfpd_plugins';

  SharedPreferences? _prefs;

  /// `.gfpd` text of every installed plugin, by plugin id, oldest first.
  final Map<String, String> _sources = {};

  /// Whether [pluginId] is reserved for a bundled plugin.
  static bool isReserved(String pluginId) =>
      pluginId.startsWith(reservedIdPrefix);

  /// The installed plugins, oldest first, for the `+` menu.
  List<GFPlugin> get plugins => [
        for (final id in _sources.keys)
          if (GFPluginRegistry.instance.findById(id) case final GFPlugin p) p,
      ];

  /// Loads the library and registers every plugin it holds.
  ///
  /// An entry that no longer parses is skipped rather than aborting the load:
  /// one broken file must not cost the user the rest of their plugins.
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    _sources
      ..clear()
      ..addAll(_decode(_prefs!.getString(_prefsKey)));
    for (final source in _sources.values) {
      GFDescriptorLoader.loadAndRegister(source, replace: true);
    }
  }

  /// Installs the plugin described by [source], the text of a `.gfpd` file.
  ///
  /// Returns the status and, when installed, the registered plugin. A plugin
  /// already installed under the same id is replaced; the rack must then
  /// rebuild the slots that use it (`RackState.reloadDescriptorSlots`).
  Future<({GfpdInstallStatus status, GFPlugin? plugin})> install(
    String source,
  ) async {
    final descriptor = GFDescriptorLoader.parse(source);
    // The parser fills missing fields with defaults, so any YAML map parses;
    // without an id there is nothing to register it under.
    if (descriptor == null || descriptor.id.trim().isEmpty) {
      return (status: GfpdInstallStatus.invalid, plugin: null);
    }
    if (isReserved(descriptor.id)) {
      return (status: GfpdInstallStatus.reservedId, plugin: null);
    }
    final plugin = GFDescriptorLoader.loadAndRegister(source, replace: true);
    if (plugin == null) {
      return (status: GfpdInstallStatus.invalid, plugin: null);
    }
    _sources[descriptor.id] = source;
    await _save();
    return (status: GfpdInstallStatus.installed, plugin: plugin);
  }

  /// Removes the plugin [pluginId] from the `+` menu.
  ///
  /// It stays registered for the rest of this run, so slots already in the
  /// rack keep playing, and projects that use it carry their own copy.
  Future<void> remove(String pluginId) async {
    if (_sources.remove(pluginId) == null) return;
    await _save();
  }

  Future<void> _save() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_prefsKey, jsonEncode(_sources));
    } catch (e) {
      // The plugin still works for this run; only the menu entry is lost.
      debugPrint('CustomPluginLibrary: cannot save — $e');
    }
  }

  Map<String, String> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (_) {
      // Corrupt preferences: start empty rather than refusing to launch.
      return const {};
    }
  }

  /// Forgets everything without touching storage, for tests.
  @visibleForTesting
  void debugReset() {
    _sources.clear();
    _prefs = null;
  }
}
