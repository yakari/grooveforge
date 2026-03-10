import 'gf_plugin_type.dart';
import 'gf_plugin_parameter.dart';
import 'gf_plugin_context.dart';

/// Base interface for all GFPA plugins.
///
/// Concrete subtypes:
///   - [GFInstrumentPlugin] — MIDI → audio
///   - [GFEffectPlugin]    — audio → audio
///   - [GFMidiFxPlugin]    — MIDI → MIDI
///   - [GFAnalyzerPlugin]  — audio → visual data
abstract class GFPlugin {
  /// Reverse-DNS identifier, e.g. `"com.grooveforge.vocoder"`.
  /// Must be globally unique and stable across versions.
  String get pluginId;

  String get name;
  String get version;
  GFPluginType get type;

  /// All automatable parameters exposed by this plugin.
  List<GFPluginParameter> get parameters;

  /// Return the current normalised value [0.0, 1.0] for [paramId].
  double getParameter(int paramId);

  /// Set the normalised value [0.0, 1.0] for [paramId].
  void setParameter(int paramId, double normalizedValue);

  /// Return the full plugin state as a JSON-compatible map for .gf serialisation.
  Map<String, dynamic> getState();

  /// Restore state from a previously serialised map.
  void loadState(Map<String, dynamic> state);

  /// Called once before the plugin produces any audio or MIDI.
  Future<void> initialize(GFPluginContext context);

  /// Called when the plugin slot is removed or the app exits.
  Future<void> dispose();
}
