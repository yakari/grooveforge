import 'grooveforge_keyboard_plugin.dart';
import 'gfpa_plugin_instance.dart';
import 'vst3_plugin_instance.dart';

/// Abstract base for every slot that can live in the GrooveForge rack.
///
/// Concrete subtypes:
///   - [GrooveForgeKeyboardPlugin] — built-in keyboard / vocoder (legacy model)
///   - [Vst3PluginInstance]        — external VST3 plugin (desktop only)
///   - [GFpaPluginInstance]        — GFPA plugin (all platforms, Phase 3+)
abstract class PluginInstance {
  String get id;

  /// MIDI channel (1–16) for instrument slots.
  /// 0 = no MIDI channel for [GFpaPluginInstance] effect / MIDI FX slots.
  int get midiChannel;
  set midiChannel(int v);

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
      case 'gfpa':
        return GFpaPluginInstance.fromJson(json);
      default:
        throw ArgumentError('Unknown plugin type: $type');
    }
  }
}
