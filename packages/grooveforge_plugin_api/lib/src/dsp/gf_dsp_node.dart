import 'dart:typed_data';
import '../gf_transport_context.dart';

/// Abstract base class for all built-in DSP processing nodes.
///
/// A node is a stateful audio processor with named input and output ports.
/// Each port carries a stereo pair of [Float32List] buffers (L + R channels).
///
/// **Thread safety**: [processBlock] is called on the audio thread. [setParam]
/// may be called from the UI thread; each concrete implementation must use
/// atomic reads (e.g. reading a [double] is naturally atomic on 64-bit Dart)
/// or double-buffer techniques to avoid races.
///
/// **Zero allocation rule**: [initialize] may allocate freely. [processBlock]
/// and [setParam] must not allocate any heap objects (no Lists, no closures,
/// no string operations).
abstract class GFDspNode {
  /// Unique node identifier within the graph (from the `.gfpd` `id:` field).
  final String nodeId;

  GFDspNode(this.nodeId);

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Called once before the first [processBlock].
  ///
  /// Implementations must pre-allocate every buffer they need here. After
  /// this call no further heap allocation is permitted on the audio path.
  void initialize(int sampleRate, int maxFrames);

  /// Called when the plugin slot is removed or the app exits.
  void dispose() {}

  // ── Parameters ─────────────────────────────────────────────────────────────

  /// Set an internal node parameter by name.
  ///
  /// [paramName] is the node-internal key (e.g. `"roomSize"`, `"rate"`).
  /// [normalizedValue] is always in [0.0, 1.0]; the node converts to its
  /// internal range.
  ///
  /// Safe to call from the UI thread while [processBlock] runs on the audio
  /// thread (reads/writes of individual Dart `double` fields are atomic on
  /// 64-bit platforms).
  void setParam(String paramName, double normalizedValue);

  // ── Port discovery ─────────────────────────────────────────────────────────

  /// Names of stereo input ports (e.g. `["in"]`, `["in", "sidechain"]`).
  List<String> get inputPortNames;

  /// Names of stereo output ports (e.g. `["out"]`).
  List<String> get outputPortNames;

  // ── Buffer access ──────────────────────────────────────────────────────────

  /// Return the pre-allocated left-channel output buffer for [portName].
  Float32List outputL(String portName);

  /// Return the pre-allocated right-channel output buffer for [portName].
  Float32List outputR(String portName);

  // ── Processing ─────────────────────────────────────────────────────────────

  /// Process [frameCount] stereo frames.
  ///
  /// [inputs] maps each declared input port name to its (L, R) buffer pair,
  /// already filled by an upstream node. The implementation writes its result
  /// into its pre-allocated output buffers, accessible via [outputL]/[outputR].
  ///
  /// [transport] is the current host transport snapshot — use it for
  /// BPM-synced rates, beat-quantised delays, etc.
  void processBlock(
    Map<String, (Float32List, Float32List)> inputs,
    int frameCount,
    GFTransportContext transport,
  );
}

/// A registry of node factory functions keyed by node type name.
///
/// The engine uses this registry to instantiate nodes from a [GFPluginDescriptor]
/// at load time. Built-in nodes are registered once at app startup by calling
/// [GFDspNodeRegistry.register]. Third-party node types can also register here.
class GFDspNodeRegistry {
  GFDspNodeRegistry._();

  static final GFDspNodeRegistry instance = GFDspNodeRegistry._();

  final Map<String, GFDspNode Function(String nodeId)> _factories = {};

  /// Register a factory for [typeName] (e.g. `"freeverb"`, `"delay"`).
  void register(String typeName, GFDspNode Function(String nodeId) factory) {
    _factories[typeName] = factory;
  }

  /// Create a node instance of [typeName] with [nodeId], or null if unknown.
  GFDspNode? create(String typeName, String nodeId) {
    return _factories[typeName]?.call(nodeId);
  }

  /// Whether [typeName] has a registered factory.
  bool has(String typeName) => _factories.containsKey(typeName);
}
