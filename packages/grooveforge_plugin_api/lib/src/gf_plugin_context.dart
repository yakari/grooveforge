import 'gf_transport_context.dart';
import 'midi/gf_midi_node.dart';

/// Host context injected into a plugin at [GFPlugin.initialize] time.
///
/// [sampleRate] and [maxFramesPerBlock] are fixed for the lifetime of the
/// plugin instance.
///
/// [transport] is a one-shot snapshot used only during initialisation (for
/// initial BPM / time-signature values). For real-time BPM-synced DSP (e.g.
/// auto-wah, synced delay, chorus rate) use [transportProvider] instead — the
/// host updates this callback before every audio block so it always returns the
/// current transport state without any heap allocation.
class GFPluginContext {
  final int sampleRate;
  final int maxFramesPerBlock;

  /// One-shot transport snapshot available at initialisation time.
  final GFTransportContext transport;

  /// Optional live transport provider for real-time BPM/position access.
  ///
  /// Plugins that need the current BPM or playback position on every block
  /// (BPM-synced LFOs, tap-tempo effects, beat-quantised delays) should call
  /// this getter at the top of [GFEffectPlugin.processBlock] rather than
  /// caching [transport].
  ///
  /// The host guarantees this callback is safe to call from the audio thread
  /// and returns a pre-allocated, non-allocating snapshot.
  final GFTransportContext Function()? transportProvider;

  const GFPluginContext({
    required this.sampleRate,
    required this.maxFramesPerBlock,
    this.transport = GFTransportContext.stopped,
    this.transportProvider,
  });
}

/// Extended host context for [GFMidiFxPlugin] initialization.
///
/// Carries the same fields as [GFPluginContext] plus the MIDI-specific
/// [midiNodeContext] required by [GFMidiDescriptorPlugin] to wire host
/// callbacks (scale provider, source channel) into its [GFMidiNode]s.
///
/// The host constructs this instead of a plain [GFPluginContext] whenever it
/// initialises a slot whose plugin type is [GFPluginType.midiFx].
class GFMidiPluginContext extends GFPluginContext {
  /// Host context forwarded verbatim to each [GFMidiNode.initialize] call.
  final GFMidiNodeContext midiNodeContext;

  const GFMidiPluginContext({
    required super.sampleRate,
    required super.maxFramesPerBlock,
    super.transport = GFTransportContext.stopped,
    super.transportProvider,
    required this.midiNodeContext,
  });
}
