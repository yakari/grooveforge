import 'dart:typed_data';
import 'gf_effect_plugin.dart';
import 'gf_plugin_context.dart';
import 'gf_plugin_parameter.dart';
import 'gf_plugin_type.dart';
import 'gf_transport_context.dart';
import 'gf_plugin_descriptor.dart';
import 'dsp/gf_dsp_graph.dart';
import 'dsp/gf_dsp_node.dart';

/// A [GFEffectPlugin] whose signal processing is defined by a [GFPluginDescriptor].
///
/// Instead of hand-coding DSP, a [GFDescriptorPlugin] reads a `.gfpd`
/// descriptor at load time, builds a [GFDspGraph] from the declared node
/// graph, and routes parameter changes from the UI to the correct DSP nodes.
///
/// **Thread safety**: [processBlock] and [updateTransport] are called on the
/// audio thread. [setParameter] and [getParameter] may be called from the UI
/// thread. Individual Dart `double` field reads/writes are atomic on 64-bit
/// platforms, so the pattern is safe without explicit locking.
class GFDescriptorPlugin extends GFEffectPlugin {
  final GFPluginDescriptor _descriptor;
  final GFDspGraph _graph = GFDspGraph();

  /// Normalised parameter values [0.0, 1.0] indexed by [GFPluginParameter.id].
  final List<double> _paramValues;

  /// Latest transport context, updated by [updateTransport] before each block.
  GFTransportContext _transport = GFTransportContext.stopped;

  GFDescriptorPlugin(this._descriptor)
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
  GFPluginType get type => _descriptor.type;

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
    // Forward to graph using the descriptor's string id for the binding lookup.
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
    // Build the node graph from the descriptor.
    final ok = _graph.build(_descriptor, GFDspNodeRegistry.instance);
    if (!ok) {
      throw StateError(
        'GFDescriptorPlugin(${_descriptor.id}): unknown DSP node type in graph.',
      );
    }
    _graph.initialize(context.sampleRate, context.maxFramesPerBlock);

    // Seed transport from the initial context snapshot.
    _transport = context.transport;
  }

  @override
  Future<void> dispose() async {
    _graph.dispose();
  }

  // ── GFEffectPlugin audio processing ───────────────────────────────────────

  @override
  void processBlock(
    Float32List inL,
    Float32List inR,
    Float32List outL,
    Float32List outR,
    int frameCount,
  ) {
    _graph.processBlock(inL, inR, outL, outR, frameCount, _transport);
  }

  // ── Transport update (called by the rack engine before each block) ─────────

  /// Update the transport snapshot used for BPM-synced DSP.
  ///
  /// The rack engine must call this before every [processBlock] call whenever
  /// the transport state changes (BPM change, play/stop, position seek).
  void updateTransport(GFTransportContext transport) {
    _transport = transport;
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

  /// Expose the descriptor for UI generation.
  GFPluginDescriptor get descriptor => _descriptor;
}
