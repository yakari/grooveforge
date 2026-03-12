import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'rotary_knob.dart';

/// A [RotaryKnob] bound to a [GFPluginParameter].
///
/// [normalizedValue] and [onChanged] operate on the 0–1 range that
/// [GFPlugin.getParameter] / [GFPlugin.setParameter] use.  The widget
/// converts internally to the parameter's raw [min]/[max] range for
/// rendering so the knob arc fills correctly.
class GFParameterKnob extends StatelessWidget {
  const GFParameterKnob({
    super.key,
    required this.parameter,
    required this.normalizedValue,
    required this.onChanged,
    this.size = 50.0,
    this.isCompact = false,
    this.icon,
  });

  final GFPluginParameter parameter;

  /// 0.0 – 1.0 (as returned by [GFPlugin.getParameter]).
  final double normalizedValue;

  /// Called with a 0.0 – 1.0 value when the user drags the knob.
  final ValueChanged<double> onChanged;

  final double size;
  final bool isCompact;

  /// Optional icon shown below the knob (passes through to [RotaryKnob]).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final range = parameter.max - parameter.min;
    final rawValue = (normalizedValue * range + parameter.min).clamp(
      parameter.min,
      parameter.max,
    );

    return RotaryKnob(
      value: rawValue,
      min: parameter.min,
      max: parameter.max,
      label: parameter.unitLabel.isNotEmpty
          ? '${parameter.name} (${parameter.unitLabel})'
          : parameter.name,
      icon: icon,
      size: size,
      isCompact: isCompact,
      onChanged: (raw) {
        final normalized =
            range == 0 ? 0.0 : ((raw - parameter.min) / range).clamp(0.0, 1.0);
        onChanged(normalized);
      },
    );
  }
}
