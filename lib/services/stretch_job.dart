/// One file to render at a new tempo, and where to put the result.
///
/// In a file of its own so both the native renderer and its web stub can name
/// it without either importing the other — and so nothing on the web side ever
/// has to reach a library that imports `dart:ffi`.
class StretchJob {
  const StretchJob({
    required this.source,
    required this.destination,
    required this.ratio,
  });

  /// The original recording. Always the original: rendering from an earlier
  /// render compounds the vocoder's artefacts with every tempo nudge, and a
  /// few adjustments are enough to hear it.
  final String source;

  final String destination;

  /// How much longer the result is. Above 1 is slower.
  final double ratio;
}
