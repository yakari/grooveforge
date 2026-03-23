import 'package:yaml/yaml.dart';
import 'gf_plugin.dart';
import 'gf_plugin_descriptor.dart';
import 'gf_plugin_type.dart';
import 'gf_descriptor_plugin.dart';
import 'gf_plugin_registry.dart';
import 'dsp/gf_dsp_node.dart';
import 'dsp/gf_dsp_gain.dart';
import 'dsp/gf_dsp_wet_dry.dart';
import 'dsp/gf_dsp_freeverb.dart';
import 'dsp/gf_dsp_biquad_filter.dart';
import 'dsp/gf_dsp_delay.dart';
import 'dsp/gf_dsp_wah_filter.dart';
import 'dsp/gf_dsp_compressor.dart';
import 'dsp/gf_dsp_chorus.dart';
import 'midi/gf_midi_node.dart';
import 'midi/gf_midi_descriptor_plugin.dart';
import 'midi/gf_midi_nodes_builtin.dart';

/// Parses `.gfpd` YAML content into [GFPluginDescriptor] objects and registers
/// the resulting [GFDescriptorPlugin] instances in [GFPluginRegistry].
///
/// ## Usage
///
/// At app startup, call [GFDescriptorLoader.registerBuiltinNodes] once to
/// populate the [GFDspNodeRegistry], then call [loadAndRegister] for each
/// `.gfpd` asset or user file you want to make available.
///
/// ```dart
/// await GFDescriptorLoader.registerBuiltinNodes();
///
/// // Load bundled assets.
/// for (final asset in bundledPluginAssets) {
///   final yaml = await rootBundle.loadString(asset);
///   GFDescriptorLoader.loadAndRegister(yaml);
/// }
/// ```
class GFDescriptorLoader {
  GFDescriptorLoader._();

  // ── Built-in node registration ─────────────────────────────────────────────

  /// Register all built-in DSP node factories in [GFDspNodeRegistry].
  ///
  /// Must be called once before any `.gfpd` effect file is loaded.
  static void registerBuiltinNodes() {
    final reg = GFDspNodeRegistry.instance;
    // Simple utility nodes.
    reg.register('gain', (id) => GFDspGainNode(id));
    reg.register('wet_dry', (id) => GFDspWetDryNode(id));
    // Musical effect nodes.
    reg.register('freeverb', (id) => GFDspFreeverbNode(id));
    reg.register('biquad_filter', (id) => GFDspBiquadFilterNode(id));
    reg.register('delay', (id) => GFDspDelayNode(id));
    reg.register('wah_filter', (id) => GFDspWahFilterNode(id));
    reg.register('compressor', (id) => GFDspCompressorNode(id));
    reg.register('chorus', (id) => GFDspChorusNode(id));
  }

  /// Register all built-in MIDI node factories in [GFMidiNodeRegistry].
  ///
  /// Must be called once before any `.gfpd` midi_fx file is loaded.
  static void registerBuiltinMidiNodes() {
    final reg = GFMidiNodeRegistry.instance;
    reg.register('transpose', (id) => TransposeNode(id));
    reg.register('gate', (id) => GateNode(id));
    reg.register('harmonize', (id) => HarmonizeNode(id));
    reg.register('chord_expand', (id) => ChordExpandNode(id));
    reg.register('arpeggiate', (id) => ArpeggiateNode(id));
    reg.register('velocity_curve', (id) => VelocityCurveNode(id));
  }

  // ── Parse + register ───────────────────────────────────────────────────────

  /// Parse a `.gfpd` YAML string and register the resulting plugin.
  ///
  /// Returns the created [GFPlugin] on success ([GFDescriptorPlugin] for
  /// `type: effect` / `instrument`, [GFMidiDescriptorPlugin] for
  /// `type: midi_fx`), or null if the YAML is invalid.
  ///
  /// The plugin is automatically added to [GFPluginRegistry] so it appears in
  /// [AddPluginSheet] and can be loaded from a `.gf` project file.
  static GFPlugin? loadAndRegister(String yamlContent) {
    final descriptor = parse(yamlContent);
    if (descriptor == null) return null;

    final GFPlugin plugin;
    if (descriptor.type == GFPluginType.midiFx) {
      plugin = GFMidiDescriptorPlugin(descriptor);
    } else {
      plugin = GFDescriptorPlugin(descriptor);
    }
    GFPluginRegistry.instance.register(plugin);
    return plugin;
  }

  // ── Parse only ─────────────────────────────────────────────────────────────

  /// Parse a `.gfpd` YAML string into a [GFPluginDescriptor].
  ///
  /// Returns null and prints a diagnostic if parsing fails.
  static GFPluginDescriptor? parse(String yamlContent) {
    try {
      final doc = loadYaml(yamlContent);
      if (doc is! YamlMap) return null;
      return _parseDescriptor(doc);
    } catch (e) {
      // Using print here is intentional: this is a developer-facing diagnostic
      // that runs at startup outside the audio thread.
      // ignore: avoid_print
      print('[GFDescriptorLoader] Failed to parse .gfpd: $e');
      return null;
    }
  }

  // ── Internal parsing helpers ───────────────────────────────────────────────

  static GFPluginDescriptor _parseDescriptor(YamlMap doc) {
    final id = _str(doc, 'id');
    final name = _str(doc, 'name');
    final version = _str(doc, 'version');
    final typeStr = _str(doc, 'type');
    final specVersion = _str(doc, 'spec', fallback: '1.0');

    final type = _parsePluginType(typeStr);
    final parameters = _parseParameters(doc['parameters']);
    final (nodes, connections) = _parseGraph(doc['graph']);
    final midiNodes = _parseMidiNodes(doc['midi_nodes']);
    final (uiLayout, controls, groups) = _parseUi(doc['ui']);

    return GFPluginDescriptor(
      specVersion: specVersion,
      id: id,
      name: name,
      version: version,
      type: type,
      parameters: parameters,
      nodes: nodes,
      connections: connections,
      midiNodes: midiNodes,
      uiLayout: uiLayout,
      controls: controls,
      groups: groups,
    );
  }

  // ── Parameters ────────────────────────────────────────────────────────────

  static List<GFDescriptorParameter> _parseParameters(dynamic raw) {
    if (raw is! YamlList) return const [];
    return raw.map<GFDescriptorParameter>((item) {
      final m = item as YamlMap;
      final typeStr = _str(m, 'type', fallback: 'float');
      final type = switch (typeStr) {
        'toggle' => GFDescriptorParamType.toggle,
        'selector' => GFDescriptorParamType.selector,
        _ => GFDescriptorParamType.float,
      };
      final opts = (m['options'] as YamlList?)
              ?.map((e) => e.toString())
              .toList(growable: false) ??
          const <String>[];
      return GFDescriptorParameter(
        id: _str(m, 'id'),
        paramId: _int(m, 'paramId'),
        name: _str(m, 'name'),
        min: _double(m, 'min'),
        max: _double(m, 'max'),
        defaultValue: _double(m, 'default'),
        unit: _str(m, 'unit', fallback: ''),
        type: type,
        options: opts,
      );
    }).toList(growable: false);
  }

  // ── Graph ─────────────────────────────────────────────────────────────────

  static (List<GFDescriptorNode>, List<GFDescriptorConnection>) _parseGraph(
    dynamic raw,
  ) {
    if (raw is! YamlMap) return (const [], const []);

    final nodes = _parseNodes(raw['nodes']);
    final conns = _parseConnections(raw['connections']);
    return (nodes, conns);
  }

  static List<GFDescriptorNode> _parseNodes(dynamic raw) {
    if (raw is! YamlList) return const [];
    return raw.map<GFDescriptorNode>((item) {
      final m = item as YamlMap;
      final params = _parseNodeParams(m['params']);
      return GFDescriptorNode(
        id: _str(m, 'id'),
        type: _str(m, 'type'),
        params: params,
      );
    }).toList(growable: false);
  }

  /// Parse the `params:` map for a node.
  ///
  /// Each entry is either `{ param: "param_id" }` (reference) or
  /// `{ value: 0.5 }` (constant).
  static Map<String, GFNodeParamBinding> _parseNodeParams(dynamic raw) {
    if (raw is! YamlMap) return const {};
    final result = <String, GFNodeParamBinding>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final binding = entry.value;
      if (binding is YamlMap) {
        if (binding.containsKey('param')) {
          result[key] = GFParamRefBinding(binding['param'].toString());
        } else if (binding.containsKey('value')) {
          result[key] = GFConstantBinding(
            (binding['value'] as num).toDouble(),
          );
        }
      }
    }
    return result;
  }

  static List<GFDescriptorConnection> _parseConnections(dynamic raw) {
    if (raw is! YamlList) return const [];
    final result = <GFDescriptorConnection>[];
    for (final item in raw) {
      final m = item as YamlMap;
      final from = _str(m, 'from'); // "nodeId.portName"
      final toDynamic = m['to'];

      // `to:` can be a single string or a list of strings.
      final toTargets = toDynamic is YamlList
          ? toDynamic.map((e) => e.toString()).toList()
          : [toDynamic.toString()];

      final fromParts = from.split('.');
      final fromNode = fromParts[0];
      final fromPort = fromParts.length > 1 ? fromParts[1] : 'out';

      for (final to in toTargets) {
        final toParts = to.split('.');
        final toNode = toParts[0];
        final toPort = toParts.length > 1 ? toParts[1] : 'in';
        result.add(GFDescriptorConnection(
          fromNode: fromNode,
          fromPort: fromPort,
          toNode: toNode,
          toPort: toPort,
        ));
      }
    }
    return result;
  }

  // ── MIDI nodes ────────────────────────────────────────────────────────────

  /// Parse the top-level `midi_nodes:` list into [GFDescriptorMidiNode]s.
  ///
  /// The list order is the execution order of the linear MIDI chain.
  static List<GFDescriptorMidiNode> _parseMidiNodes(dynamic raw) {
    if (raw is! YamlList) return const [];
    return raw.map<GFDescriptorMidiNode>((item) {
      final m = item as YamlMap;
      final params = _parseNodeParams(m['params']);
      return GFDescriptorMidiNode(
        id: _str(m, 'id'),
        type: _str(m, 'type'),
        params: params,
      );
    }).toList(growable: false);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  static (GFUiLayout, List<GFDescriptorControl>, List<GFDescriptorControlGroup>)
      _parseUi(dynamic raw) {
    if (raw is! YamlMap) return (GFUiLayout.row, const [], const []);

    final layoutStr = _str(raw, 'layout', fallback: 'row');
    final layout = layoutStr == 'grid' ? GFUiLayout.grid : GFUiLayout.row;
    final controls = _parseControls(raw['controls']);
    final groups = _parseGroups(raw['groups']);
    return (layout, controls, groups);
  }

  /// Parse the `groups:` list into [GFDescriptorControlGroup]s.
  ///
  /// Each group has a `label:` string and a `controls:` list (same format as
  /// the top-level `ui: controls:` list). When groups are present the flat
  /// `controls:` list should be omitted from the `.gfpd` file.
  static List<GFDescriptorControlGroup> _parseGroups(dynamic raw) {
    if (raw is! YamlList) return const [];
    return raw.map<GFDescriptorControlGroup>((item) {
      final m = item as YamlMap;
      return GFDescriptorControlGroup(
        label: _str(m, 'label'),
        controls: _parseControls(m['controls']),
      );
    }).toList(growable: false);
  }

  static List<GFDescriptorControl> _parseControls(dynamic raw) {
    if (raw is! YamlList) return const [];
    return raw.map<GFDescriptorControl>((item) {
      final m = item as YamlMap;
      final typeStr = _str(m, 'type');
      final controlType = switch (typeStr) {
        'slider' => GFControlType.slider,
        'vumeter' => GFControlType.vumeter,
        'toggle' => GFControlType.toggle,
        'selector' => GFControlType.selector,
        'button' => GFControlType.button,
        _ => GFControlType.knob,
      };
      final sizeStr = _str(m, 'size', fallback: 'medium');
      final size = switch (sizeStr) {
        'small' => GFControlSize.small,
        'large' => GFControlSize.large,
        _ => GFControlSize.medium,
      };
      return GFDescriptorControl(
        type: controlType,
        paramId: m['param']?.toString(),
        sourceNodeId: m['source']?.toString(),
        label: m['label']?.toString(),
        size: size,
        action: m['action']?.toString(),
      );
    }).toList(growable: false);
  }

  // ── Type helpers ──────────────────────────────────────────────────────────

  static GFPluginType _parsePluginType(String s) => switch (s) {
        'instrument' => GFPluginType.instrument,
        // Accept both `midi_fx` (canonical, underscore) and `midifx` (legacy).
        'midi_fx' || 'midifx' => GFPluginType.midiFx,
        'analyzer' => GFPluginType.analyzer,
        _ => GFPluginType.effect,
      };

  static String _str(YamlMap m, String key, {String fallback = ''}) =>
      m[key]?.toString() ?? fallback;

  static int _int(YamlMap m, String key, {int fallback = 0}) =>
      (m[key] as num?)?.toInt() ?? fallback;

  static double _double(YamlMap m, String key, {double fallback = 0.0}) =>
      (m[key] as num?)?.toDouble() ?? fallback;
}
