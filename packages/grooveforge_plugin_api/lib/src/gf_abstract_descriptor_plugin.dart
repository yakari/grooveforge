import 'gf_plugin.dart';
import 'gf_plugin_descriptor.dart';

/// Common interface for all descriptor-backed plugins (audio effects and
/// MIDI FX) that expose a [GFPluginDescriptor] to the UI layer.
///
/// [GFDescriptorPlugin] and [GFMidiDescriptorPlugin] both implement this
/// interface, allowing [GFDescriptorPluginUI] to render controls for both
/// without depending on the concrete DSP or MIDI processing class.
abstract class GFAbstractDescriptorPlugin extends GFPlugin {
  /// The descriptor that defines parameters, nodes, and UI layout.
  GFPluginDescriptor get descriptor;
}
