import 'package:flutter/material.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'gf_parameter_knob.dart';

/// Renders every parameter of [plugin] as a [GFParameterKnob] in a
/// [Wrap] layout.
///
/// This is the zero-boilerplate option for plugin UIs: drop a single
/// `GFParameterGrid(plugin: myPlugin)` and all parameters are
/// immediately editable.
///
/// For finer control (custom ordering, icons, hiding parameters) use
/// [GFParameterKnob] directly.
///
/// State management notes:
/// - The widget tracks parameter values locally via `setState` so drags
///   feel instant.
/// - If the plugin's values are changed externally (e.g. `loadState`
///   after a project open) wrap this widget in a `StatefulWidget` /
///   `ListenableBuilder` that rebuilds the grid; each knob will then
///   receive its updated `normalizedValue`.
/// - [onParameterChanged] is called after every [GFPlugin.setParameter]
///   invocation and is a good hook for autosave / ChangeNotifier signals.
class GFParameterGrid extends StatefulWidget {
  const GFParameterGrid({
    super.key,
    required this.plugin,
    this.knobSize = 50.0,
    this.isCompact = false,
    this.spacing = 8.0,
    this.runSpacing = 12.0,
    this.parameterIcons = const {},
    this.excludedParameterIds = const {},
    this.onParameterChanged,
  });

  final GFPlugin plugin;

  /// Size in logical pixels for each knob.  Defaults to 50.
  final double knobSize;

  /// When true, knobs show only an icon below them (no label text).
  final bool isCompact;

  /// Horizontal space between knobs.
  final double spacing;

  /// Vertical space between knob rows.
  final double runSpacing;

  /// Optional icons per parameter id.
  /// Example: `{ GFVocoderPlugin.paramNoiseMix: Icons.graphic_eq }`
  final Map<int, IconData> parameterIcons;

  /// Parameter ids to omit from the grid.  Useful when a parameter is
  /// rendered elsewhere in the UI (e.g. a chip selector for discrete values).
  final Set<int> excludedParameterIds;

  /// Called after every [GFPlugin.setParameter] call, useful for
  /// triggering autosave or propagating changes to a ChangeNotifier.
  final VoidCallback? onParameterChanged;

  @override
  State<GFParameterGrid> createState() => _GFParameterGridState();
}

class _GFParameterGridState extends State<GFParameterGrid> {
  void _handleChanged(int paramId, double normalized) {
    setState(() {});
    widget.plugin.setParameter(paramId, normalized);
    widget.onParameterChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final params = widget.plugin.parameters
        .where((p) => !widget.excludedParameterIds.contains(p.id))
        .toList();
    if (params.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: widget.spacing,
      runSpacing: widget.runSpacing,
      children: [
        for (final param in params)
          GFParameterKnob(
            parameter: param,
            normalizedValue: widget.plugin.getParameter(param.id),
            onChanged: (v) => _handleChanged(param.id, v),
            size: widget.knobSize,
            isCompact: widget.isCompact,
            icon: widget.parameterIcons[param.id],
          ),
      ],
    );
  }
}
