import 'dart:typed_data';
import '../gf_plugin_descriptor.dart';
import '../gf_transport_context.dart';
import 'gf_dsp_node.dart';

/// Audio signal graph that executes a chain of [GFDspNode]s.
///
/// The graph is built once from a [GFPluginDescriptor] by [GFDescriptorPlugin]
/// during [initialize]. At runtime, [processBlock] routes stereo PCM buffers
/// through all nodes in topological order.
///
/// **Design principles**
/// - All [Float32List] buffers are pre-allocated in [initialize]. [processBlock]
///   performs zero heap allocation.
/// - The special `audio_in` node exposes the plugin's input signal to the graph.
///   The special `audio_out` node's output becomes the plugin's output signal.
/// - Parameters are propagated by storing a flat map of normalised values that
///   each node reads whenever [_applyParams] is called (once per block, before
///   node execution).
class GFDspGraph {
  // ── Ordered nodes ──────────────────────────────────────────────────────────

  /// Nodes in topological execution order (source → sink).
  final List<GFDspNode> _nodes = [];

  /// For each node: list of (inputPortName, upstreamNode, upstreamPortName).
  final List<List<_Wire>> _wires = [];

  // ── Parameter state ────────────────────────────────────────────────────────

  /// Normalised parameter values [0.0, 1.0] keyed by [GFDescriptorParameter.id].
  final Map<String, double> _paramValues = {};

  /// Which node params should be updated when a plugin param changes.
  /// Key: plugin-param id. Value: list of (node, node-param-name).
  final Map<String, List<(GFDspNode, String)>> _paramBindings = {};

  // ── Audio I/O nodes ────────────────────────────────────────────────────────

  late _AudioInNode _audioIn;
  late _AudioOutNode _audioOut;

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Build the graph from [descriptor], instantiating nodes via [registry].
  ///
  /// Returns false if any node type is unknown in [registry].
  bool build(GFPluginDescriptor descriptor, GFDspNodeRegistry registry) {
    _nodes.clear();
    _wires.clear();
    _paramValues.clear();
    _paramBindings.clear();

    // Index nodes by id for connection wiring.
    final nodeById = <String, GFDspNode>{};

    // Create all nodes.
    for (final nd in descriptor.nodes) {
      GFDspNode? node;
      if (nd.type == 'audio_in') {
        _audioIn = _AudioInNode(nd.id);
        node = _audioIn;
      } else if (nd.type == 'audio_out') {
        _audioOut = _AudioOutNode(nd.id);
        node = _audioOut;
      } else {
        node = registry.create(nd.type, nd.id);
        if (node == null) return false; // unknown node type
      }
      nodeById[nd.id] = node;
      _nodes.add(node);
      _wires.add([]); // wire list for this node (filled below)
    }

    // Build wire index (connection → wire).
    for (final conn in descriptor.connections) {
      final toNode = nodeById[conn.toNode];
      final fromNode = nodeById[conn.fromNode];
      if (toNode == null || fromNode == null) continue;

      final toIndex = _nodes.indexOf(toNode);
      if (toIndex < 0) continue;

      _wires[toIndex].add(_Wire(
        inputPort: conn.toPort,
        sourceNode: fromNode,
        sourcePort: conn.fromPort,
      ));
    }

    // Build parameter bindings and seed default values.
    for (final param in descriptor.parameters) {
      // Normalised default = (raw - min) / (max - min), clamped to [0,1].
      final range = param.max - param.min;
      final normalised =
          range == 0 ? 0.0 : ((param.defaultValue - param.min) / range).clamp(0.0, 1.0);
      _paramValues[param.id] = normalised;
    }

    for (final nd in descriptor.nodes) {
      final node = nodeById[nd.id];
      if (node == null) continue;
      for (final entry in nd.params.entries) {
        final binding = entry.value;
        if (binding is GFParamRefBinding) {
          _paramBindings.putIfAbsent(binding.paramId, () => []).add((node, entry.key));
        } else if (binding is GFConstantBinding) {
          // Apply constant immediately — it never changes.
          node.setParam(entry.key, binding.value);
        }
      }
    }

    return true;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Pre-allocate all node buffers. Call after [build] and before [processBlock].
  void initialize(int sampleRate, int maxFrames) {
    for (final node in _nodes) {
      node.initialize(sampleRate, maxFrames);
    }
    // Seed all nodes with their default parameter values.
    _flushParams();
  }

  /// Release resources held by all nodes.
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    _nodes.clear();
    _wires.clear();
  }

  // ── Parameter updates ──────────────────────────────────────────────────────

  /// Update the normalised value of a plugin parameter by its string [id].
  ///
  /// All DSP nodes bound to this parameter are notified immediately.
  void setParam(String paramId, double normalizedValue) {
    _paramValues[paramId] = normalizedValue;
    final bindings = _paramBindings[paramId];
    if (bindings == null) return;
    for (final (node, nodePName) in bindings) {
      node.setParam(nodePName, normalizedValue);
    }
  }

  /// Get the normalised value of a plugin parameter by its string [id].
  double getParam(String paramId) => _paramValues[paramId] ?? 0.0;

  // ── Processing ─────────────────────────────────────────────────────────────

  /// Route [frameCount] stereo frames through the graph.
  ///
  /// The caller writes the plugin's input into [inL]/[inR] before calling this
  /// method. After the call, [outL]/[outR] contain the processed output.
  void processBlock(
    Float32List inL,
    Float32List inR,
    Float32List outL,
    Float32List outR,
    int frameCount,
    GFTransportContext transport,
  ) {
    // Feed input to the audio_in node.
    _audioIn.supply(inL, inR);

    // Execute nodes in order. For each node, collect its inputs from the
    // output buffers of already-executed upstream nodes.
    for (var i = 0; i < _nodes.length; i++) {
      final node = _nodes[i];
      final inputs = _buildInputMap(i, frameCount);
      node.processBlock(inputs, frameCount, transport);
    }

    // Copy audio_out node output to the plugin's output buffers.
    final aoL = _audioOut.outputL('out');
    final aoR = _audioOut.outputR('out');
    outL.setRange(0, frameCount, aoL);
    outR.setRange(0, frameCount, aoR);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Build the input map for node at [nodeIndex] from upstream output buffers.
  Map<String, (Float32List, Float32List)> _buildInputMap(
    int nodeIndex,
    int frameCount,
  ) {
    final map = <String, (Float32List, Float32List)>{};
    for (final wire in _wires[nodeIndex]) {
      map[wire.inputPort] = (
        wire.sourceNode.outputL(wire.sourcePort),
        wire.sourceNode.outputR(wire.sourcePort),
      );
    }
    return map;
  }

  /// Push all current parameter values to their bound nodes.
  void _flushParams() {
    for (final entry in _paramValues.entries) {
      final bindings = _paramBindings[entry.key];
      if (bindings == null) continue;
      for (final (node, nodePName) in bindings) {
        node.setParam(nodePName, entry.value);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Internal wiring record
// ─────────────────────────────────────────────────────────────────────────────

/// Describes one audio wire: data flows from [sourceNode].[sourcePort] into a
/// downstream node's [inputPort].
class _Wire {
  final String inputPort;
  final GFDspNode sourceNode;
  final String sourcePort;

  const _Wire({
    required this.inputPort,
    required this.sourceNode,
    required this.sourcePort,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
//  Built-in pass-through nodes for graph I/O
// ─────────────────────────────────────────────────────────────────────────────

/// The `audio_in` node — exposes the plugin's incoming audio to the graph.
///
/// Before each block, the graph calls [supply] with the plugin's input buffers.
/// Downstream nodes read from the `"out"` port.
class _AudioInNode extends GFDspNode {
  late Float32List _outL;
  late Float32List _outR;

  _AudioInNode(super.nodeId);

  @override
  List<String> get inputPortNames => const [];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
  }

  /// Called by [GFDspGraph.processBlock] to inject external audio.
  void supply(Float32List l, Float32List r) {
    _outL = l; // share the caller's buffer — no copy needed
    _outR = r;
  }

  @override
  Float32List outputL(String portName) => _outL;

  @override
  Float32List outputR(String portName) => _outR;

  @override
  void setParam(String paramName, double normalizedValue) {}

  @override
  void processBlock(
    Map<String, (Float32List, Float32List)> inputs,
    int frameCount,
    GFTransportContext transport,
  ) {
    // No processing — the buffers are already set by supply().
  }
}

/// The `audio_out` node — collects the graph's final output.
///
/// It simply copies its `"in"` port straight to its `"out"` port so downstream
/// callers can read the result via [outputL]/[outputR].
class _AudioOutNode extends GFDspNode {
  late Float32List _outL;
  late Float32List _outR;

  _AudioOutNode(super.nodeId);

  @override
  List<String> get inputPortNames => const ['in'];

  @override
  List<String> get outputPortNames => const ['out'];

  @override
  void initialize(int sampleRate, int maxFrames) {
    _outL = Float32List(maxFrames);
    _outR = Float32List(maxFrames);
  }

  @override
  Float32List outputL(String portName) => _outL;

  @override
  Float32List outputR(String portName) => _outR;

  @override
  void setParam(String paramName, double normalizedValue) {}

  @override
  void processBlock(
    Map<String, (Float32List, Float32List)> inputs,
    int frameCount,
    GFTransportContext transport,
  ) {
    final src = inputs['in'];
    if (src == null) return;
    final (srcL, srcR) = src;
    _outL.setRange(0, frameCount, srcL);
    _outR.setRange(0, frameCount, srcR);
  }
}
