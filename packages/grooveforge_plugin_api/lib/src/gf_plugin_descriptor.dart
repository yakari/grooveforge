import 'gf_plugin_type.dart';

// ─────────────────────────────────────────────────────────────
//  Enums
// ─────────────────────────────────────────────────────────────

/// Visual type of a parameter control in the generated plugin UI.
enum GFControlType {
  /// Rotary knob (maps to RotaryKnob).
  knob,

  /// Vertical or horizontal fader (maps to GFSlider).
  slider,

  /// Stereo VU meter that monitors a DSP node output port.
  vumeter,

  /// Illuminated LED toggle (on/off boolean parameter).
  toggle,

  /// Segmented multi-option selector (enum/discrete parameter).
  selector,

  /// Momentary push button that triggers a named action.
  button,
}

/// Size hint for generated controls.
enum GFControlSize { small, medium, large }

/// Layout strategy for the auto-generated plugin UI panel.
enum GFUiLayout {
  /// All controls in a single horizontal row (compact rack view).
  row,

  /// Controls arranged in a grid (more parameters / wider panels).
  grid,
}

// ─────────────────────────────────────────────────────────────
//  Parameter descriptor
// ─────────────────────────────────────────────────────────────

/// Type of a descriptor parameter value.
enum GFDescriptorParamType {
  /// Continuous float in [min, max] — shown as knob or slider.
  float,

  /// Boolean (0.0 = off, 1.0 = on) — shown as toggle button.
  toggle,

  /// Discrete integer index into an [options] list — shown as selector.
  selector,
}

/// A single automatable parameter declared in a `.gfpd` file.
///
/// The [id] is the string key used inside the descriptor (e.g. `"room_size"`).
/// The [paramId] is the integer index used by [GFPlugin.getParameter] /
/// [GFPlugin.setParameter] and stored in the `.gf` project file.
class GFDescriptorParameter {
  /// Internal string key — used in graph `params` bindings and UI `param` refs.
  final String id;

  /// Integer index for [GFPlugin.getParameter] / [GFPlugin.setParameter].
  final int paramId;

  /// Human-readable name shown in the generated UI.
  final String name;

  /// Minimum raw (un-normalised) value. Used for UI range display.
  final double min;

  /// Maximum raw (un-normalised) value.
  final double max;

  /// Default raw value. Must lie within [[min], [max]].
  final double defaultValue;

  /// Optional unit label (e.g. `"Hz"`, `"ms"`, `"dB"`, `"%"`).
  final String unit;

  /// How the parameter is edited in the UI.
  final GFDescriptorParamType type;

  /// Non-empty only when [type] is [GFDescriptorParamType.selector].
  /// Each string is a display label for one discrete value.
  final List<String> options;

  const GFDescriptorParameter({
    required this.id,
    required this.paramId,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unit = '',
    this.type = GFDescriptorParamType.float,
    this.options = const [],
  });
}

// ─────────────────────────────────────────────────────────────
//  DSP graph descriptor
// ─────────────────────────────────────────────────────────────

/// A binding that ties a DSP node's internal parameter to a value source.
///
/// Use [GFParamRefBinding] to link a node param to a plugin parameter (UI
/// controlled). Use [GFConstantBinding] for fixed values that never change.
sealed class GFNodeParamBinding {
  const GFNodeParamBinding();
}

/// Binds a DSP node parameter to a plugin parameter identified by [paramId].
///
/// When the user moves a knob or slider, the engine calls
/// [GFDspNode.setParam] on the node with the new normalised value.
class GFParamRefBinding extends GFNodeParamBinding {
  /// The [GFDescriptorParameter.id] of the plugin parameter to follow.
  final String paramId;
  const GFParamRefBinding(this.paramId);
}

/// Binds a DSP node parameter to a constant value baked at load time.
class GFConstantBinding extends GFNodeParamBinding {
  /// Normalised value in [0.0, 1.0].
  final double value;
  const GFConstantBinding(this.value);
}

/// A single node in the `.gfpd` DSP graph.
///
/// [type] names a built-in DSP algorithm (e.g. `"freeverb"`, `"wah_filter"`,
/// `"delay"`). The node library is registered in [GFDspNodeRegistry].
/// [params] maps node-internal parameter names (e.g. `"roomSize"`) to their
/// value sources ([GFParamRefBinding] or [GFConstantBinding]).
class GFDescriptorNode {
  /// Unique identifier within the graph (e.g. `"reverb"`, `"lfo1"`).
  final String id;

  /// Built-in node type key (e.g. `"freeverb"`, `"wet_dry"`, `"gain"`).
  final String type;

  /// Parameter bindings: node_param_name → binding.
  final Map<String, GFNodeParamBinding> params;

  const GFDescriptorNode({
    required this.id,
    required this.type,
    this.params = const {},
  });
}

/// A directed audio connection between two ports in the DSP graph.
///
/// Audio flows from [fromNode].[fromPort] to [toNode].[toPort].
/// Port names are node-specific (e.g. `"out"`, `"in"`, `"sidechain"`).
class GFDescriptorConnection {
  final String fromNode;

  /// Output port name on [fromNode] (most nodes use `"out"`).
  final String fromPort;

  final String toNode;

  /// Input port name on [toNode] (most nodes use `"in"`).
  final String toPort;

  const GFDescriptorConnection({
    required this.fromNode,
    required this.fromPort,
    required this.toNode,
    required this.toPort,
  });
}

// ─────────────────────────────────────────────────────────────
//  MIDI graph descriptor
// ─────────────────────────────────────────────────────────────

/// A single node in the `.gfpd` MIDI processing chain.
///
/// Analogous to [GFDescriptorNode] for the audio graph. [type] names a
/// built-in MIDI algorithm (e.g. `"transpose"`, `"harmonize"`, `"gate"`).
/// The available types are registered in [GFMidiNodeRegistry].
///
/// [params] maps node-internal parameter names to their value sources.
/// Same binding rules as audio DSP nodes ([GFParamRefBinding] /
/// [GFConstantBinding]).
class GFDescriptorMidiNode {
  /// Unique identifier within the MIDI chain (e.g. `"harmonizer1"`).
  final String id;

  /// Built-in MIDI node type key (e.g. `"transpose"`, `"harmonize"`).
  final String type;

  /// Parameter bindings: node_param_name → binding.
  final Map<String, GFNodeParamBinding> params;

  const GFDescriptorMidiNode({
    required this.id,
    required this.type,
    this.params = const {},
  });
}

// ─────────────────────────────────────────────────────────────
//  UI descriptor
// ─────────────────────────────────────────────────────────────

/// One control in the auto-generated plugin UI panel.
class GFDescriptorControl {
  /// Which widget type to render.
  final GFControlType type;

  /// [GFDescriptorParameter.id] this control reads/writes.
  /// Null for [GFControlType.vumeter] and [GFControlType.button].
  final String? paramId;

  /// For [GFControlType.vumeter]: the [GFDescriptorNode.id] whose output
  /// amplitude this meter monitors.
  final String? sourceNodeId;

  /// Optional label override. If null, the parameter name is used.
  final String? label;

  /// Size hint for the rendered widget.
  final GFControlSize size;

  /// For [GFControlType.button]: the action key to fire (e.g. `"reset"`).
  final String? action;

  const GFDescriptorControl({
    required this.type,
    this.paramId,
    this.sourceNodeId,
    this.label,
    this.size = GFControlSize.medium,
    this.action,
  });
}

/// A named group of controls for the responsive plugin UI (Phase 10).
///
/// When a `.gfpd` file declares a `groups:` block, the generated UI renders
/// controls in labelled sections rather than a single flat list. On narrow
/// screens (< 600 px) each group becomes a collapsible [ExpansionTile]; on
/// wider screens all groups display simultaneously as labelled columns.
///
/// If no `groups:` block is present in the `.gfpd`, all controls fall into
/// one implicit un-labelled group and the layout degrades gracefully to the
/// previous flat behaviour.
class GFDescriptorControlGroup {
  /// Display label shown as the group heading (e.g. `"Reverb"`, `"Gate"`).
  final String label;

  /// Controls that belong to this group, in display order.
  final List<GFDescriptorControl> controls;

  const GFDescriptorControlGroup({
    required this.label,
    required this.controls,
  });
}

// ─────────────────────────────────────────────────────────────
//  Top-level plugin descriptor
// ─────────────────────────────────────────────────────────────

/// Immutable Dart model of a `.gfpd` plugin descriptor file.
///
/// A `.gfpd` file is a YAML document that fully describes a GFPA plugin:
/// its metadata, the DSP signal graph (which built-in processing blocks to
/// use and how to chain them), its automatable parameters, and the UI layout
/// (which controls to render in the rack slot panel).
///
/// Plugin developers write `.gfpd` files; GrooveForge reads them at startup
/// via [GFDescriptorLoader] and registers the resulting [GFDescriptorPlugin]
/// instances in [GFPluginRegistry].
///
/// Example `.gfpd` (YAML):
/// ```yaml
/// spec: "1.0"
/// id: "com.mycompany.myreverb"
/// name: "My Reverb"
/// version: "1.0.0"
/// type: effect
///
/// parameters:
///   - id: mix   paramId: 0   name: "Mix"   min: 0.0   max: 100.0   default: 50.0   unit: "%"
///
/// graph:
///   nodes:
///     - id: in    type: audio_in
///     - id: rev   type: freeverb
///     - id: out   type: audio_out
///   connections:
///     - from: in.out   to: rev.in
///     - from: rev.out  to: out.in
///
/// ui:
///   layout: row
///   controls:
///     - type: knob     param: mix
///     - type: vumeter  source: out
/// ```
class GFPluginDescriptor {
  /// `.gfpd` spec version (currently `"1.0"`).
  final String specVersion;

  /// Reverse-DNS plugin identifier (globally unique, stable across versions).
  final String id;

  /// Human-readable plugin name.
  final String name;

  /// Semantic version string.
  final String version;

  /// Whether the plugin is an effect, instrument, MIDI FX, or analyser.
  final GFPluginType type;

  /// All automatable parameters exposed by this plugin.
  final List<GFDescriptorParameter> parameters;

  /// DSP processing nodes (empty for `type: midi_fx` plugins).
  final List<GFDescriptorNode> nodes;

  /// Audio connections between node ports (empty for `type: midi_fx` plugins).
  final List<GFDescriptorConnection> connections;

  /// MIDI processing nodes in execution order (empty for `type: effect` plugins).
  ///
  /// For `type: midi_fx` plugins the chain is linear: events flow from index 0
  /// to the last node, with each node's output feeding the next node's input.
  final List<GFDescriptorMidiNode> midiNodes;

  /// How controls are arranged in the auto-generated rack slot UI.
  final GFUiLayout uiLayout;

  /// Controls rendered in the rack slot panel (flat list, no grouping).
  ///
  /// When [groups] is non-empty, individual [controls] are embedded inside
  /// groups and this field should be treated as empty by the UI renderer.
  final List<GFDescriptorControl> controls;

  /// Grouped controls for the responsive Phase 10 UI.
  ///
  /// If empty, the UI falls back to the flat [controls] list with the legacy
  /// row/grid layout. If non-empty, each [GFDescriptorControlGroup] renders
  /// as a labelled section (tab on wide screens, collapsible on narrow screens).
  final List<GFDescriptorControlGroup> groups;

  const GFPluginDescriptor({
    required this.specVersion,
    required this.id,
    required this.name,
    required this.version,
    required this.type,
    required this.parameters,
    required this.nodes,
    required this.connections,
    this.midiNodes = const [],
    required this.uiLayout,
    required this.controls,
    this.groups = const [],
  });

  /// Look up a parameter descriptor by its string [id].
  GFDescriptorParameter? paramById(String id) {
    for (final p in parameters) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Look up a parameter descriptor by its integer [paramId].
  GFDescriptorParameter? paramByIndex(int paramId) {
    for (final p in parameters) {
      if (p.paramId == paramId) return p;
    }
    return null;
  }
}
