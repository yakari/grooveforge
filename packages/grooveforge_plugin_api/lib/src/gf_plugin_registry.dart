import 'gf_plugin.dart';
import 'gf_instrument_plugin.dart';
import 'gf_effect_plugin.dart';
import 'gf_midi_fx_plugin.dart';

/// Central registry for all GFPA plugins available in the current app instance.
///
/// Built-in plugins (GrooveForge Keyboard, Vocoder, Jam Mode) are registered
/// at startup. Third-party plugins add themselves via their Flutter plugin
/// entrypoint using [register].
class GFPluginRegistry {
  GFPluginRegistry._();

  static final GFPluginRegistry instance = GFPluginRegistry._();

  final List<GFPlugin> _plugins = [];

  /// Register [plugin].
  ///
  /// When a plugin with the same [GFPlugin.pluginId] is already registered,
  /// it is kept and [plugin] is ignored, unless [replace] is true: then
  /// [plugin] takes its place. Replacing is how an edited `.gfpd` file is
  /// loaded again without restarting the app.
  void register(GFPlugin plugin, {bool replace = false}) {
    final index = _plugins.indexWhere((p) => p.pluginId == plugin.pluginId);
    if (index < 0) {
      _plugins.add(plugin);
    } else if (replace) {
      _plugins[index] = plugin;
    }
  }

  /// Remove the plugin with [pluginId] from the registry.
  void unregister(String pluginId) =>
      _plugins.removeWhere((p) => p.pluginId == pluginId);

  List<GFPlugin> get all => List.unmodifiable(_plugins);

  List<GFInstrumentPlugin> get instruments =>
      _plugins.whereType<GFInstrumentPlugin>().toList();

  List<GFEffectPlugin> get effects =>
      _plugins.whereType<GFEffectPlugin>().toList();

  List<GFMidiFxPlugin> get midiFx =>
      _plugins.whereType<GFMidiFxPlugin>().toList();

  GFPlugin? findById(String pluginId) {
    try {
      return _plugins.firstWhere((p) => p.pluginId == pluginId);
    } catch (_) {
      return null;
    }
  }
}
