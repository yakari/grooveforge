import 'gf_transport_context.dart';

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
