/// GrooveForge Plugin API (GFPA)
///
/// Import this library to implement a GFPA plugin in Dart or to load `.gfpd`
/// descriptor files:
///
/// ```dart
/// import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
///
/// // Option A — hand-coded Dart plugin:
/// class MyReverbPlugin implements GFEffectPlugin { ... }
///
/// // Option B — descriptor-driven plugin (no DSP code needed):
/// GFDescriptorLoader.registerBuiltinNodes();
/// GFDescriptorLoader.loadAndRegister(yamlString);
/// ```
library;

// ── Core interfaces ───────────────────────────────────────────────────────────
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

// ── Plugin descriptor system (.gfpd) ─────────────────────────────────────────
export 'src/gf_plugin_descriptor.dart';
export 'src/gf_abstract_descriptor_plugin.dart';
export 'src/gf_descriptor_plugin.dart';
export 'src/gf_descriptor_loader.dart';

// ── DSP node infrastructure (for third-party node implementations) ────────────
export 'src/dsp/gf_dsp_node.dart';
export 'src/dsp/gf_dsp_graph.dart';

// ── Built-in DSP node implementations ────────────────────────────────────────
export 'src/dsp/gf_dsp_gain.dart';
export 'src/dsp/gf_dsp_wet_dry.dart';
export 'src/dsp/gf_dsp_freeverb.dart';
export 'src/dsp/gf_dsp_biquad_filter.dart';
export 'src/dsp/gf_dsp_delay.dart';
export 'src/dsp/gf_dsp_wah_filter.dart';
export 'src/dsp/gf_dsp_compressor.dart';
export 'src/dsp/gf_dsp_chorus.dart';

// ── MIDI node infrastructure ──────────────────────────────────────────────────
export 'src/midi/gf_midi_node.dart';
export 'src/midi/gf_midi_graph.dart';
export 'src/midi/gf_midi_descriptor_plugin.dart';

// ── Built-in MIDI node implementations ───────────────────────────────────────
export 'src/midi/gf_midi_nodes_builtin.dart';
