/// A single automatable parameter exposed by a GFPA plugin.
///
/// All values are normalised to [0.0, 1.0] at the API boundary. The plugin
/// implementation is responsible for mapping normalised values to its internal
/// range using [min] and [max] as hints for UI display.
class GFPluginParameter {
  final int id;
  final String name;

  /// Minimum raw (un-normalised) value — used for display only.
  final double min;

  /// Maximum raw (un-normalised) value — used for display only.
  final double max;

  /// Default normalised value in [0.0, 1.0].
  final double defaultValue;

  /// Unit string shown next to the value in the UI (e.g. "ms", "dB", "Hz").
  final String unitLabel;

  const GFPluginParameter({
    required this.id,
    required this.name,
    required this.min,
    required this.max,
    required this.defaultValue,
    this.unitLabel = '',
  });
}
