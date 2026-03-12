import 'gf_transport_context.dart';

/// Host context injected into a plugin at [GFPlugin.initialize] time.
class GFPluginContext {
  final int sampleRate;
  final int maxFramesPerBlock;
  final GFTransportContext transport;

  const GFPluginContext({
    required this.sampleRate,
    required this.maxFramesPerBlock,
    this.transport = GFTransportContext.stopped,
  });
}
