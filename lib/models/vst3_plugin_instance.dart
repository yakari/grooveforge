import 'plugin_instance.dart';
import 'plugin_role.dart';

/// Represents an external VST3 plugin loaded from disk.
///
/// VST3 hosting is desktop-only (Linux, macOS, Windows). On Android and iOS
/// this type will still deserialise from .gf files but will render a
/// "plugin unavailable on this platform" placeholder in the rack UI.
class Vst3PluginInstance implements PluginInstance {
  @override
  final String id;

  @override
  int midiChannel;

  @override
  PluginRole role;

  /// Absolute path to the .vst3 bundle/file on disk.
  final String path;

  /// Human-readable plugin name as reported by the VST3 factory.
  String pluginName;

  /// Saved parameter values keyed by parameter ID.
  Map<int, double> parameters;

  Vst3PluginInstance({
    required this.id,
    required this.midiChannel,
    required this.role,
    required this.path,
    required this.pluginName,
    Map<int, double>? parameters,
  }) : parameters = parameters ?? {};

  @override
  String get displayName => pluginName;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'vst3',
    'midiChannel': midiChannel,
    'role': role.name,
    'path': path,
    'name': pluginName,
    'state': {
      'parameters': parameters.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
    },
  };

  factory Vst3PluginInstance.fromJson(Map<String, dynamic> json) {
    final state = (json['state'] as Map<String, dynamic>?) ?? {};
    final rawParams = (state['parameters'] as Map<String, dynamic>?) ?? {};
    final params = rawParams.map(
      (k, v) => MapEntry(int.parse(k), (v as num).toDouble()),
    );

    return Vst3PluginInstance(
      id: json['id'] as String,
      midiChannel: (json['midiChannel'] as num?)?.toInt() ?? 1,
      role: PluginRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => PluginRole.slave,
      ),
      path: json['path'] as String? ?? '',
      pluginName: json['name'] as String? ?? 'Unknown VST3',
      parameters: params,
    );
  }
}
