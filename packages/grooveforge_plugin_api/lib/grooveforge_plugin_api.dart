/// GrooveForge Plugin API (GFPA)
///
/// Import this library to implement a GFPA plugin:
///
/// ```dart
/// import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
///
/// class MyReverbPlugin implements GFEffectPlugin {
///   @override String get pluginId => 'com.example.myreverb';
///   // ...
/// }
/// ```
library;

export 'src/gf_plugin_type.dart';
export 'src/gf_plugin_parameter.dart';
export 'src/gf_transport_context.dart';
export 'src/gf_plugin_context.dart';
export 'src/gf_plugin.dart';
export 'src/gf_instrument_plugin.dart';
export 'src/gf_effect_plugin.dart';
export 'src/gf_midi_event.dart';
export 'src/gf_midi_fx_plugin.dart';
export 'src/gf_plugin_registry.dart';
