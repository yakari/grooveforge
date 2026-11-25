import 'package:yaml/yaml.dart';
import 'gf_localized_text.dart';
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
    reg.register('microtone', (id) => MicrotoneNode(id));
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
  ///
  /// With [replace], a plugin already registered under the same id is
  /// replaced (see [GFPluginRegistry.register]).
  static GFPlugin? loadAndRegister(String yamlContent, {bool replace = false}) {
    final descriptor = parse(yamlContent);
    if (descriptor == null) return null;

    final GFPlugin plugin;
    if (descriptor.type == GFPluginType.midiFx) {
      plugin = GFMidiDescriptorPlugin(descriptor);
    } else {
      plugin = GFDescriptorPlugin(descriptor);
    }
    GFPluginRegistry.instance.register(plugin, replace: replace);
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
      return _parseDescriptor(doc, yamlContent);
    } catch (e) {
      // Using print here is intentional: this is a developer-facing diagnostic
      // that runs at startup outside the audio thread.
      // ignore: avoid_print
      print('[GFDescriptorLoader] Failed to parse .gfpd: $e');
      return null;
    }
  }

  // ── Internal parsing helpers ───────────────────────────────────────────────

  static GFPluginDescriptor _parseDescriptor(YamlMap doc, String source) {
    final id = _str(doc, 'id');
    final (name, localizedName) = _text(doc, 'name');
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
      source: source,
      localizedName: localizedName,
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
      final (opts, localizedOpts) = _parseOptions(m['options']);
      final (name, localizedName) = _text(m, 'name');
      // `display:` opts the parameter into a numeric readout under its
      // control. Unknown values fall back to no readout rather than
      // failing the load, so a descriptor written against a newer spec
      // still opens.
      final display = switch (_str(m, 'display', fallback: '')) {
        'integer' => GFParamDisplay.integer,
        'interval' => GFParamDisplay.interval,
        'value' => GFParamDisplay.value,
        _ => GFParamDisplay.none,
      };
      return GFDescriptorParameter(
        id: _str(m, 'id'),
        paramId: _int(m, 'paramId'),
        name: name,
        localizedName: localizedName,
        min: _double(m, 'min'),
        max: _double(m, 'max'),
        defaultValue: _double(m, 'default'),
        unit: _str(m, 'unit', fallback: ''),
        type: type,
        options: opts,
        localizedOptions: localizedOpts,
        display: display,
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

    final layout = switch (_str(raw, 'layout', fallback: 'row')) {
      'grid' => GFUiLayout.grid,
      'lanes' => GFUiLayout.lanes,
      _ => GFUiLayout.row,
    };
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
      final (label, localizedLabel) = _text(m, 'label');
      return GFDescriptorControlGroup(
        label: label,
        localizedLabel: localizedLabel,
        controls: _parseControls(m['controls']),
        activeWhen: _parseActiveWhen(m['activeWhen']),
      );
    }).toList(growable: false);
  }

  /// Parse a group's optional `activeWhen: { param: <id>, atLeast: <n> }`.
  ///
  /// Anything malformed yields null, which means "always active" — a
  /// descriptor with a typo renders a live control rather than one
  /// permanently greyed out with no way to tell why.
  static GFGroupActiveWhen? _parseActiveWhen(dynamic raw) {
    if (raw is! YamlMap) return null;
    final paramId = _str(raw, 'param');
    if (paramId.isEmpty) return null;
    return GFGroupActiveWhen(
      paramId: paramId,
      atLeast: _double(raw, 'atLeast'),
    );
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
        'interval' => GFControlType.interval,
        _ => GFControlType.knob,
      };
      final sizeStr = _str(m, 'size', fallback: 'medium');
      final size = switch (sizeStr) {
        'small' => GFControlSize.small,
        'large' => GFControlSize.large,
        _ => GFControlSize.medium,
      };
      // A missing label stays null so the control falls back to its
      // parameter's name; an empty `(String, null)` would hide that name.
      final hasLabel = m['label'] != null;
      final (label, localizedLabel) = _text(m, 'label');
      return GFDescriptorControl(
        type: controlType,
        paramId: m['param']?.toString(),
        sourceNodeId: m['source']?.toString(),
        label: hasLabel ? label : null,
        localizedLabel: localizedLabel,
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

  /// Reads a user-visible text field that may be written either as a plain
  /// string or as a language map (`{en: "Gate", fr: "Porte"}`).
  ///
  /// Returns the default text (English, else the first language given) for
  /// the descriptor's plain `String` field, plus the full map when one was
  /// written. A plain string returns a null map, so descriptors that never
  /// use the map form are built exactly as before.
  static (String, GFLocalizedText?) _text(YamlMap m, String key) =>
      _textOf(m[key]);

  /// [_text] for a bare YAML value rather than a map entry.
  static (String, GFLocalizedText?) _textOf(dynamic raw) {
    if (raw is! YamlMap) return (raw?.toString() ?? '', null);
    final localized = GFLocalizedText({
      for (final entry in raw.entries)
        entry.key.toString(): entry.value?.toString() ?? '',
    });
    return (localized.defaultText, localized);
  }

  /// Parses a selector's `options:` list, where each entry may be a plain
  /// string or a language map.
  ///
  /// The localized list is null unless at least one entry is a map; a plain
  /// entry in a mixed list is kept under `en` so every option has a slot.
  static (List<String>, List<GFLocalizedText>?) _parseOptions(dynamic raw) {
    if (raw is! YamlList) return (const <String>[], null);
    final plain = <String>[];
    final localized = <GFLocalizedText>[];
    var anyLocalized = false;
    for (final item in raw) {
      final (text, map) = _textOf(item);
      plain.add(text);
      localized.add(map ?? GFLocalizedText({'en': text}));
      if (map != null) anyLocalized = true;
    }
    return (
      List.unmodifiable(plain),
      anyLocalized ? List.unmodifiable(localized) : null,
    );
  }

  static String _str(YamlMap m, String key, {String fallback = ''}) =>
      m[key]?.toString() ?? fallback;

  static int _int(YamlMap m, String key, {int fallback = 0}) =>
      (m[key] as num?)?.toInt() ?? fallback;

  static double _double(YamlMap m, String key, {double fallback = 0.0}) =>
      (m[key] as num?)?.toDouble() ?? fallback;
}
