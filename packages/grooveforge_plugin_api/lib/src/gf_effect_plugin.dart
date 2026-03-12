import 'dart:typed_data';
import 'gf_plugin.dart';
import 'gf_plugin_type.dart';

/// A GFPA plugin that processes an audio stream.
///
/// Examples: reverb, EQ, compressor, delay, chorus.
abstract class GFEffectPlugin extends GFPlugin {
  @override
  GFPluginType get type => GFPluginType.effect;

  /// Process [frameCount] stereo frames from [inL]/[inR] into [outL]/[outR].
  ///
  /// May be called on a dedicated audio thread. Implementations must be
  /// thread-safe with respect to [setParameter] calls from the UI thread —
  /// use atomic reads or a double-buffer scheme for parameter values.
  void processBlock(
    Float32List inL,
    Float32List inR,
    Float32List outL,
    Float32List outR,
    int frameCount,
  );
}
