import '../gf_midi_event.dart';
import '../gf_plugin_descriptor.dart';
import '../gf_transport_context.dart';
import 'gf_midi_node.dart';

/// Linear MIDI processing chain that executes a sequence of [GFMidiNode]s.
///
/// The MIDI graph is intentionally simpler than the audio DSP graph: events
/// flow linearly from node 0 → node 1 → … → last node. There are no named
/// ports and no connection topology to resolve — the order in the descriptor's
/// `midi_nodes:` list is the execution order.
///
/// **Usage lifecycle**
/// ```
/// graph.build(descriptor, registry);   // instantiate nodes from descriptor
/// graph.initialize(context);           // inject host context, call each node's initialize()
/// events = graph.processMidi(events, transport);  // per-block call
/// graph.dispose();                     // on slot removal / app exit
/// ```
class GFMidiGraph {
  // ── Ordered nodes ──────────────────────────────────────────────────────────

  /// Nodes in execution order (source → sink).
  final List<GFMidiNode> _nodes = [];

  // ── Parameter state ────────────────────────────────────────────────────────

  /// Normalised parameter values [0.0, 1.0] keyed by [GFDescriptorParameter.id].
  final Map<String, double> _paramValues = {};

  /// Which node params should be updated when a plugin param changes.
  /// Key: plugin-param id. Value: list of (node, node-param-name).
  final Map<String, List<(GFMidiNode, String)>> _paramBindings = {};

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Instantiate nodes from [descriptor]'s `midiNodes` list.
  ///
  /// Returns `false` if any node type is not found in [registry], leaving the
  /// graph empty and unusable.
  bool build(GFPluginDescriptor descriptor, GFMidiNodeRegistry registry) {
    _nodes.clear();
    _paramValues.clear();
    _paramBindings.clear();

    // Create nodes in the order declared in the descriptor.
    // The list order is the execution order — no connection wiring needed.
    for (final nd in descriptor.midiNodes) {
      final node = registry.create(nd.type, nd.id);
      if (node == null) return false; // unknown node type

      _nodes.add(node);

      // Resolve parameter bindings for this node.
      for (final entry in nd.params.entries) {
        final binding = entry.value;
        if (binding is GFParamRefBinding) {
          // Bind the node param to a plugin parameter — updated at runtime.
          _paramBindings
              .putIfAbsent(binding.paramId, () => [])
              .add((node, entry.key));
        } else if (binding is GFConstantBinding) {
          // Constant binding: apply once now, never changes again.
          node.setParam(entry.key, binding.value);
        }
      }
    }

    // Seed the parameter map with normalised defaults from the descriptor.
    for (final param in descriptor.parameters) {
      final range = param.max - param.min;
      final normalised = range == 0
          ? 0.0
          : ((param.defaultValue - param.min) / range).clamp(0.0, 1.0);
      _paramValues[param.id] = normalised;
    }

    return true;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Inject [context] into all nodes and flush default parameter values.
  ///
  /// Call after [build] and before the first [processMidi].
  void initialize(GFMidiNodeContext context) {
    for (final node in _nodes) {
      node.initialize(context);
    }
    _flushParams();
  }

  /// Release resources held by all nodes.
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    _nodes.clear();
    _paramBindings.clear();
  }

  // ── Parameter updates ──────────────────────────────────────────────────────

  /// Update the normalised value of a plugin parameter by its string [id].
  ///
  /// All MIDI nodes bound to this parameter are notified immediately.
  void setParam(String paramId, double normalizedValue) {
    _paramValues[paramId] = normalizedValue;
    final bindings = _paramBindings[paramId];
    if (bindings == null) return;
    for (final (node, nodePName) in bindings) {
      node.setParam(nodePName, normalizedValue);
    }
  }

  /// Return the current normalised value for plugin parameter [paramId].
  double getParam(String paramId) => _paramValues[paramId] ?? 0.0;

  // ── Processing ─────────────────────────────────────────────────────────────

  /// Route [events] through the node chain and return the final output.
  ///
  /// Each node's output becomes the next node's input. [tick] is also called
  /// on every node so time-driven nodes (e.g. arpeggiators) can inject events
  /// even when [events] is empty.
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    var current = events;
    for (final node in _nodes) {
      // Allow time-driven nodes to generate autonomous events first.
      final ticked = node.tick(transport);
      if (ticked.isNotEmpty) {
        // Merge autonomous events with incoming events, preserving ppq order.
        current = _mergeEvents(current, ticked);
      }
      // Transform the merged event list through this node.
      current = node.processMidi(current, transport);
    }
    return current;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Push all current parameter values to their bound nodes.
  ///
  /// Called once in [initialize] so nodes start with the correct defaults.
  void _flushParams() {
    for (final entry in _paramValues.entries) {
      final bindings = _paramBindings[entry.key];
      if (bindings == null) continue;
      for (final (node, nodePName) in bindings) {
        node.setParam(nodePName, entry.value);
      }
    }
  }

  /// Merge two event lists into a single list sorted by ppqPosition.
  ///
  /// Both input lists are assumed to already be sorted. A simple merge-sort
  /// pass is O(n+m) — no heap allocation for the iterator itself (just
  /// indexed access on List, which is O(1)).
  List<TimestampedMidiEvent> _mergeEvents(
    List<TimestampedMidiEvent> a,
    List<TimestampedMidiEvent> b,
  ) {
    final result = <TimestampedMidiEvent>[];
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      if (a[i].ppqPosition <= b[j].ppqPosition) {
        result.add(a[i++]);
      } else {
        result.add(b[j++]);
      }
    }
    while (i < a.length) { result.add(a[i++]); }
    while (j < b.length) { result.add(b[j++]); }
    return result;
  }
}
