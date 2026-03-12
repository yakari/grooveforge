import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/audio_graph_connection.dart';
import '../models/audio_port_id.dart';

/// Directed audio graph that records **MIDI and Audio** signal routing
/// between rack slots.
///
/// Each rack slot is an implicit node in this graph. Connections are directed
/// edges from an output port on one slot to a compatible input port on another.
///
/// **Data connections** (chord/scale Jam Mode routing) are NOT stored here —
/// they are derived from [RackState]'s `masterSlotId` / `targetSlotIds` fields
/// and rendered as cables in the patch view on top of this graph.
///
/// Typical usage:
/// ```dart
/// final graph = context.read<AudioGraph>();
/// graph.connect('slot-0', AudioPortId.audioOutL, 'slot-1', AudioPortId.audioInL);
/// ```
///
/// The graph fires [notifyListeners] on every mutation, allowing widgets to
/// rebuild via [Consumer<AudioGraph>].
class AudioGraph extends ChangeNotifier {
  final List<AudioGraphConnection> _connections = [];

  /// All current MIDI and Audio connections in the graph.
  List<AudioGraphConnection> get connections =>
      UnmodifiableListView(_connections);

  // ── Mutation ─────────────────────────────────────────────────────────────

  /// Adds a directed connection from [fromPort] on [fromSlotId] to [toPort]
  /// on [toSlotId].
  ///
  /// Validation performed before adding:
  ///   1. Port compatibility (enforced by [AudioGraphConnection.create]).
  ///   2. No duplicate edge (same endpoints).
  ///   3. No cycle (DFS reachability check).
  ///
  /// Throws [ArgumentError] if any validation fails.
  void connect(
    String fromSlotId,
    AudioPortId fromPort,
    String toSlotId,
    AudioPortId toPort,
  ) {
    // [AudioGraphConnection.create] validates port types and data-port guard.
    final connection = AudioGraphConnection.create(
      fromSlotId: fromSlotId,
      fromPort: fromPort,
      toSlotId: toSlotId,
      toPort: toPort,
    );

    // Guard: reject duplicate edges.
    if (_connections.any((c) => c.id == connection.id)) {
      throw ArgumentError('Connection already exists: ${connection.id}');
    }

    // Guard: reject cycles in the directed graph.
    if (wouldCreateCycle(fromSlotId, toSlotId)) {
      throw ArgumentError(
        'Cycle detected: connecting $fromSlotId → $toSlotId would '
        'create a feedback loop.',
      );
    }

    _connections.add(connection);
    notifyListeners();
  }

  /// Removes the connection with the given [connectionId].
  ///
  /// Does nothing if no matching connection is found.
  void disconnect(String connectionId) {
    final before = _connections.length;
    _connections.removeWhere((c) => c.id == connectionId);
    if (_connections.length != before) notifyListeners();
  }

  /// Removes all connections that involve [slotId] as either source or
  /// destination. Called by [RackState] whenever a slot is deleted so that
  /// dangling cables are cleaned up automatically.
  void onSlotRemoved(String slotId) {
    final before = _connections.length;
    _connections.removeWhere(
      (c) => c.fromSlotId == slotId || c.toSlotId == slotId,
    );
    if (_connections.length != before) notifyListeners();
  }

  /// Removes all connections and resets the graph to an empty state.
  void clear() {
    if (_connections.isEmpty) return;
    _connections.clear();
    notifyListeners();
  }

  // ── Query helpers ─────────────────────────────────────────────────────────

  /// All connections whose source is [slotId].
  List<AudioGraphConnection> connectionsFrom(String slotId) =>
      _connections.where((c) => c.fromSlotId == slotId).toList();

  /// All connections whose destination is [slotId].
  List<AudioGraphConnection> connectionsTo(String slotId) =>
      _connections.where((c) => c.toSlotId == slotId).toList();

  // ── Cycle detection (DFS) ─────────────────────────────────────────────────

  /// Returns true if adding the edge [fromSlotId] → [toSlotId] would
  /// introduce a cycle in the directed graph.
  ///
  /// Uses a depth-first search starting from [toSlotId]: if [fromSlotId]
  /// is reachable by following existing outgoing edges, a cycle would form.
  bool wouldCreateCycle(String fromSlotId, String toSlotId) {
    // Build an adjacency map from existing connections only.
    // Each slot maps to the set of slots it feeds into.
    final adjacency = <String, Set<String>>{};
    for (final c in _connections) {
      adjacency.putIfAbsent(c.fromSlotId, () => {}).add(c.toSlotId);
    }

    // DFS from [toSlotId] to see if [fromSlotId] is reachable.
    final visited = <String>{};
    final stack = [toSlotId];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node == fromSlotId) return true; // cycle found
      if (visited.add(node)) {
        stack.addAll(adjacency[node] ?? {});
      }
    }
    return false;
  }

  // ── Topological order (Kahn's algorithm) ──────────────────────────────────

  /// Returns [allSlotIds] in topological processing order based on the
  /// current MIDI/Audio connections.
  ///
  /// Slots with no incoming connections are processed first; slots whose
  /// inputs depend on another slot's output come later.
  ///
  /// Used by Phase 5.4 (native audio graph execution) to determine the
  /// order in which the ALSA callback should process plugins.
  ///
  /// Any slot not involved in any connection retains its original order
  /// relative to other unconnected slots.
  List<String> topologicalOrder(List<String> allSlotIds) {
    // Count incoming edges per slot.
    final inDegree = {for (final id in allSlotIds) id: 0};
    final adjacency = <String, List<String>>{
      for (final id in allSlotIds) id: [],
    };

    for (final c in _connections) {
      if (!inDegree.containsKey(c.fromSlotId) ||
          !inDegree.containsKey(c.toSlotId)) {
        continue; // skip stale connections referencing removed slots
      }
      adjacency[c.fromSlotId]!.add(c.toSlotId);
      inDegree[c.toSlotId] = (inDegree[c.toSlotId] ?? 0) + 1;
    }

    // Kahn's algorithm: start with zero-in-degree nodes.
    final queue = Queue<String>()
      ..addAll(allSlotIds.where((id) => inDegree[id] == 0));
    final result = <String>[];

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      result.add(node);
      for (final neighbour in adjacency[node]!) {
        inDegree[neighbour] = inDegree[neighbour]! - 1;
        if (inDegree[neighbour] == 0) queue.add(neighbour);
      }
    }

    // If result length differs from input, a cycle existed (shouldn't happen
    // given our cycle-detection guard, but handle gracefully).
    if (result.length != allSlotIds.length) {
      debugPrint(
        'AudioGraph.topologicalOrder: cycle detected despite guard — '
        'returning original order.',
      );
      return allSlotIds;
    }
    return result;
  }

  // ── JSON persistence ───────────────────────────────────────────────────────

  /// Serialises all connections to a JSON-compatible map for .gf project files.
  Map<String, dynamic> toJson() => {
        'connections': _connections.map((c) => c.toJson()).toList(),
      };

  /// Restores connections from a JSON map read from a .gf project file.
  ///
  /// Must be called AFTER [RackState.loadFromJson] so that slot IDs referenced
  /// by the connections already exist.
  void loadFromJson(Map<String, dynamic> json) {
    _connections.clear();
    final list = json['connections'] as List<dynamic>? ?? [];
    for (final item in list) {
      try {
        _connections.add(
          AudioGraphConnection.fromJson(item as Map<String, dynamic>),
        );
      } catch (e) {
        debugPrint('AudioGraph.loadFromJson: skipping malformed connection — $e');
      }
    }
    notifyListeners();
  }
}
