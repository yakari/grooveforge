import 'plugin_instance.dart';

/// Discriminates a VST3 plugin by its audio bus configuration.
///
/// VST3 plugins declare audio I/O buses in their factory descriptor.
/// GrooveForge uses this to decide which rack slot UI to render and which
/// back-panel jacks to expose.
///
///   - [instrument] — 0 audio inputs + ≥1 audio outputs (synthesizers, samplers).
///     Receives MIDI and produces audio from scratch.
///   - [effect]     — ≥1 audio inputs + ≥1 audio outputs (reverb, EQ, compressor…).
///     Processes an incoming audio stream and returns a modified stream.
///   - [analyzer]   — ≥1 audio inputs + 0 audio outputs (spectrum display, metering).
///     Reads audio for visualisation without producing output.
enum Vst3PluginType { instrument, effect, analyzer }

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

  /// Absolute path to the .vst3 bundle/file on disk.
  final String path;

  /// Human-readable plugin name as reported by the VST3 factory.
  String pluginName;

  /// Saved parameter values keyed by parameter ID.
  Map<int, double> parameters;

  /// Whether this plugin is an instrument, effect, or analyzer.
  ///
  /// Determines the rack slot UI ([Vst3SlotUI] vs [Vst3EffectSlotUI]),
  /// the back-panel jack layout, and whether a MIDI channel is assigned.
  /// Effect and analyzer slots use [midiChannel] == 0 (no MIDI routing).
  final Vst3PluginType pluginType;

  Vst3PluginInstance({
    required this.id,
    required this.midiChannel,
    required this.path,
    required this.pluginName,
    Map<int, double>? parameters,
    this.pluginType = Vst3PluginType.instrument,
  }) : parameters = parameters ?? {};

  @override
  String get displayName => pluginName;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'vst3',
    'midiChannel': midiChannel,
    'path': path,
    'name': pluginName,
    'pluginType': pluginType.name,
    'state': {
      'parameters': parameters.map(
        (k, v) => MapEntry(k.toString(), v),
      ),
    },
  };

  Vst3PluginInstance copyWith({
    String? id,
    int? midiChannel,
    String? path,
    String? pluginName,
    Map<int, double>? parameters,
    Vst3PluginType? pluginType,
  }) => Vst3PluginInstance(
    id: id ?? this.id,
    midiChannel: midiChannel ?? this.midiChannel,
    path: path ?? this.path,
    pluginName: pluginName ?? this.pluginName,
    parameters: parameters ?? Map.of(this.parameters),
    pluginType: pluginType ?? this.pluginType,
  );

  factory Vst3PluginInstance.fromJson(Map<String, dynamic> json) {
    final state = (json['state'] as Map<String, dynamic>?) ?? {};
    final rawParams = (state['parameters'] as Map<String, dynamic>?) ?? {};
    final params = rawParams.map(
      (k, v) => MapEntry(int.parse(k), (v as num).toDouble()),
    );

    // Parse pluginType with backward-compat fallback to instrument.
    final typeStr = json['pluginType'] as String?;
    final pluginType = Vst3PluginType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => Vst3PluginType.instrument,
    );

    return Vst3PluginInstance(
      id: json['id'] as String,
      midiChannel: (json['midiChannel'] as num?)?.toInt() ?? 1,
      path: json['path'] as String? ?? '',
      pluginName: json['name'] as String? ?? 'Unknown VST3',
      parameters: params,
      pluginType: pluginType,
    );
  }
}
