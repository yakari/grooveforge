import '../gf_midi_event.dart';
import '../gf_transport_context.dart';

/// Host context injected into every [GFMidiNode] at [GFMidiNode.initialize].
///
/// Provides the node with read-only access to host state that would be
/// inappropriate to hard-code inside a plugin (e.g. the active scale). Using
/// a context object keeps [GFMidiNode] subclasses fully host-independent.
class GFMidiNodeContext {
  /// The rack channel index that feeds events into this MIDI FX chain.
  ///
  /// Nodes that need to emit MIDI on the same channel use this index to stamp
  /// the correct channel nibble onto outgoing events.
  final int sourceChannelIndex;

  /// Optional callback that returns the set of allowed pitch-classes (0–11)
  /// currently active on the host's Jam Mode scale.
  ///
  /// Returns `null` when Jam Mode is off, indicating all 12 pitch-classes are
  /// valid. Nodes that perform pitch quantisation (harmoniser, arpeggiator)
  /// call this once per event, never store the result — the set changes
  /// whenever the user switches scale.
  ///
  /// **Thread safety**: the callback reads a [ValueNotifier] value, which is
  /// written only from the UI thread. On 64-bit Dart, pointer reads are atomic,
  /// so calling this from the audio thread is safe.
  final Set<int>? Function() scaleProvider;

  const GFMidiNodeContext({
    required this.sourceChannelIndex,
    required this.scaleProvider,
  });
}

/// Abstract base class for all MIDI processing nodes.
///
/// A [GFMidiNode] is the MIDI equivalent of a [GFDspNode]: a stateful processor
/// that sits in a linear chain and transforms a list of [TimestampedMidiEvent]s.
///
/// Unlike the audio graph (which is a DAG with named ports), the MIDI chain is
/// strictly linear — each node's output feeds directly into the next node's
/// input. There are no named ports.
///
/// **Design principles**
/// - [initialize] receives a [GFMidiNodeContext] that exposes host callbacks.
///   Nodes store the context for use in [processMidi].
/// - [setParam] may be called at any time from the UI thread.
/// - [processMidi] is called per-block and must not block or allocate
///   long-lived objects.
/// - [tick] is an optional hook for time-driven nodes (e.g. arpeggiators) that
///   need to generate events independently of incoming MIDI. The default
///   implementation is a no-op.
abstract class GFMidiNode {
  /// Unique node identifier within the graph (from the `.gfpd` `id:` field).
  final String nodeId;

  GFMidiNode(this.nodeId);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Called once before the first [processMidi] call.
  ///
  /// Store [context] for use during processing. Perform any one-time setup
  /// (e.g. pre-building lookup tables) here.
  void initialize(GFMidiNodeContext context);

  /// Called when the plugin slot is removed or the app exits.
  ///
  /// Release any resources acquired in [initialize]. The default is a no-op.
  void dispose() {}

  // ── Parameters ─────────────────────────────────────────────────────────────

  /// Set an internal node parameter by name.
  ///
  /// [paramName] is the node-internal key as declared in the `.gfpd` `params:`
  /// block (e.g. `"semitones"`, `"minVelocity"`).
  /// [normalizedValue] is always in [0.0, 1.0]; the node converts to its
  /// own internal range in [processMidi].
  void setParam(String paramName, double normalizedValue);

  // ── Processing ─────────────────────────────────────────────────────────────

  /// Transform [events] for the current block and return the result.
  ///
  /// The returned list becomes the input to the next node in the chain.
  /// Implementations may add, remove, or modify events. The order within the
  /// returned list should be non-decreasing by [TimestampedMidiEvent.ppqPosition].
  ///
  /// [transport] carries BPM, play state, and beat position — use it for
  /// beat-quantised operations (e.g. arpeggiator step timing).
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  );

  /// Called once per block by [GFMidiGraph] to allow time-driven event
  /// generation even when [events] is empty.
  ///
  /// Time-driven nodes (e.g. arpeggiators) override this to push autonomously
  /// generated events into their output queue. The default implementation is a
  /// no-op — nodes that only react to incoming events can ignore it.
  List<TimestampedMidiEvent> tick(GFTransportContext transport) => const [];
}

/// A registry of factory functions for [GFMidiNode] types.
///
/// Mirrors [GFDspNodeRegistry] exactly, but for MIDI nodes. Built-in node
/// types are registered once at app startup via [GFDescriptorLoader.registerBuiltinMidiNodes].
/// Third-party node types can also call [register] before loading a `.gfpd` file.
class GFMidiNodeRegistry {
  GFMidiNodeRegistry._();

  /// The singleton registry instance.
  static final GFMidiNodeRegistry instance = GFMidiNodeRegistry._();

  final Map<String, GFMidiNode Function(String nodeId)> _factories = {};

  /// Register a factory for [typeName] (e.g. `"transpose"`, `"harmonize"`).
  ///
  /// Overwrites any previously registered factory for the same [typeName].
  void register(
    String typeName,
    GFMidiNode Function(String nodeId) factory,
  ) {
    _factories[typeName] = factory;
  }

  /// Create a [GFMidiNode] instance of [typeName] with [nodeId].
  ///
  /// Returns `null` if [typeName] has no registered factory.
  GFMidiNode? create(String typeName, String nodeId) {
    return _factories[typeName]?.call(nodeId);
  }

  /// Whether [typeName] has a registered factory.
  bool has(String typeName) => _factories.containsKey(typeName);
}
