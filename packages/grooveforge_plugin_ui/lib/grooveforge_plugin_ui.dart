/// GrooveForge Plugin UI
///
/// Flutter widget components for building GFPA plugin interfaces.
///
/// Includes:
/// - [RotaryKnob] — metallic rotary knob with orange glow indicator
/// - [GFParameterKnob] — [RotaryKnob] bound to a [GFPluginParameter]
/// - [GFParameterGrid] — auto-grid of [GFParameterKnob] widgets
/// - [GFSlider] — vertical/horizontal fader
/// - [GFVuMeter] — animated stereo VU meter with peak hold
/// - [GFToggleButton] — illuminated LED stomp-box toggle
/// - [GFOptionSelector] — segmented multi-option selector
/// - [GFDescriptorPluginUI] — auto-generates a full plugin panel from a `.gfpd` descriptor
library;

export 'src/rotary_knob.dart';
export 'src/gf_parameter_knob.dart';
export 'src/gf_parameter_grid.dart';
export 'src/gf_slider.dart';
export 'src/gf_vu_meter.dart';
export 'src/gf_toggle_button.dart';
export 'src/gf_option_selector.dart';
export 'src/gf_descriptor_plugin_ui.dart';
