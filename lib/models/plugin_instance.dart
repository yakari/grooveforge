import 'plugin_role.dart';
import 'grooveforge_keyboard_plugin.dart';
import 'vst3_plugin_instance.dart';

/// Abstract base for every slot that can live in the GrooveForge rack.
///
/// Concrete subtypes: [GrooveForgeKeyboardPlugin], [Vst3PluginInstance].
abstract class PluginInstance {
  String get id;
  int get midiChannel; // 1-16, user-facing
  set midiChannel(int v);
  PluginRole get role;
  set role(PluginRole v);

  /// Human-readable name shown in the rack slot header.
  String get displayName;

  /// Serialise this instance to a JSON-compatible map (for .gf project files).
  Map<String, dynamic> toJson();

  /// Reconstruct a [PluginInstance] from its serialised representation.
  static PluginInstance fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    switch (type) {
      case 'grooveforge_keyboard':
        return GrooveForgeKeyboardPlugin.fromJson(json);
      case 'vst3':
        return Vst3PluginInstance.fromJson(json);
      default:
        throw ArgumentError('Unknown plugin type: $type');
    }
  }
}
