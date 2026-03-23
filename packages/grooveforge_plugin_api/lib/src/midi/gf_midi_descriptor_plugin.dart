import '../gf_abstract_descriptor_plugin.dart';
import '../gf_midi_event.dart';
import '../gf_midi_fx_plugin.dart';
import '../gf_plugin_context.dart';
import '../gf_plugin_parameter.dart';
import '../gf_plugin_type.dart';
import '../gf_plugin_descriptor.dart';
import '../gf_transport_context.dart';
import 'gf_midi_graph.dart';
import 'gf_midi_node.dart';

/// A [GFMidiFxPlugin] whose MIDI processing is defined by a [GFPluginDescriptor].
///
/// Mirrors [GFDescriptorPlugin] for the MIDI domain: instead of hand-coding
/// event transforms, a [GFMidiDescriptorPlugin] reads a `.gfpd` descriptor at
/// load time, builds a [GFMidiGraph] from the declared `midi_nodes:` list, and
/// routes parameter changes from the UI to the correct [GFMidiNode]s.
///
/// **Lifecycle**
/// 1. Construct: `GFMidiDescriptorPlugin(descriptor)`
/// 2. Initialize: `plugin.initialize(GFMidiPluginContext(…))` — builds the
///    graph and injects the host [GFMidiNodeContext] into every node.
/// 3. Per-block: `plugin.processMidi(events, transport)`
/// 4. Teardown: `plugin.dispose()`
///
/// **Host requirement**: [initialize] must receive a [GFMidiPluginContext]
/// (not a plain [GFPluginContext]). A [StateError] is thrown otherwise.
class GFMidiDescriptorPlugin extends GFMidiFxPlugin
    implements GFAbstractDescriptorPlugin {
  final GFPluginDescriptor _descriptor;
  final GFMidiGraph _graph = GFMidiGraph();

  /// Normalised parameter values [0.0, 1.0] indexed by parameter list position.
  final List<double> _paramValues;

  GFMidiDescriptorPlugin(this._descriptor)
    : _paramValues = List<double>.generate(
        _descriptor.parameters.length,
        (i) {
          final p = _descriptor.parameters[i];
          final range = p.max - p.min;
          return range == 0
              ? 0.0
              : ((p.defaultValue - p.min) / range).clamp(0.0, 1.0);
        },
      );

  // ── GFPlugin identity ──────────────────────────────────────────────────────

  @override
  String get pluginId => _descriptor.id;

  @override
  String get name => _descriptor.name;

  @override
  String get version => _descriptor.version;

  @override
  GFPluginType get type => GFPluginType.midiFx;

  // ── GFPlugin parameters ────────────────────────────────────────────────────

  @override
  List<GFPluginParameter> get parameters => _descriptor.parameters
      .map(
        (p) => GFPluginParameter(
          id: p.paramId,
          name: p.name,
          min: p.min,
          max: p.max,
          defaultValue: (p.defaultValue - p.min) /
              (p.max == p.min ? 1.0 : p.max - p.min),
          unitLabel: p.unit,
        ),
      )
      .toList(growable: false);

  @override
  double getParameter(int paramId) {
    final idx = _indexForParamId(paramId);
    return idx >= 0 ? _paramValues[idx] : 0.0;
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    final idx = _indexForParamId(paramId);
    if (idx < 0) return;
    _paramValues[idx] = normalizedValue.clamp(0.0, 1.0);
    // Forward to the graph using the descriptor's string id for binding lookup.
    _graph.setParam(_descriptor.parameters[idx].id, normalizedValue);
  }

  // ── GFPlugin state serialisation ───────────────────────────────────────────

  @override
  Map<String, dynamic> getState() {
    final map = <String, dynamic>{};
    for (var i = 0; i < _descriptor.parameters.length; i++) {
      map[_descriptor.parameters[i].id] = _paramValues[i];
    }
    return map;
  }

  @override
  void loadState(Map<String, dynamic> state) {
    for (var i = 0; i < _descriptor.parameters.length; i++) {
      final key = _descriptor.parameters[i].id;
      if (state.containsKey(key)) {
        final v = (state[key] as num?)?.toDouble() ?? _paramValues[i];
        _paramValues[i] = v.clamp(0.0, 1.0);
        _graph.setParam(key, _paramValues[i]);
      }
    }
  }

  // ── GFPlugin lifecycle ─────────────────────────────────────────────────────

  @override
  Future<void> initialize(GFPluginContext context) async {
    // Require the host to provide the MIDI-specific context subclass.
    if (context is! GFMidiPluginContext) {
      throw StateError(
        'GFMidiDescriptorPlugin(${_descriptor.id}): '
        'initialize() requires a GFMidiPluginContext.',
      );
    }

    // Build the MIDI node chain from the descriptor's midi_nodes list.
    final ok = _graph.build(_descriptor, GFMidiNodeRegistry.instance);
    if (!ok) {
      throw StateError(
        'GFMidiDescriptorPlugin(${_descriptor.id}): '
        'unknown MIDI node type in midi_nodes list.',
      );
    }

    // Inject host callbacks (scaleProvider, channel index) into each node.
    _graph.initialize(context.midiNodeContext);
  }

  @override
  Future<void> dispose() async {
    _graph.dispose();
  }

  // ── GFMidiFxPlugin MIDI processing ────────────────────────────────────────

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    return _graph.processMidi(events, transport);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Returns the index into [_paramValues] for a given integer [paramId], or
  /// -1 if not found.
  int _indexForParamId(int paramId) {
    for (var i = 0; i < _descriptor.parameters.length; i++) {
      if (_descriptor.parameters[i].paramId == paramId) return i;
    }
    return -1;
  }

  /// Expose the descriptor for UI generation (used by the rack slot UI).
  @override
  GFPluginDescriptor get descriptor => _descriptor;
}
