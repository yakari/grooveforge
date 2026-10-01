/// One take to clean, and what the canceller needs to do it.
///
/// In a file of its own for the same reason [StretchJob] is: both the native
/// renderer and its web stub name it, and neither should have to import the
/// other — nor should anything on the web side reach a library that imports
/// `dart:ffi`.
class CleanJob {
  const CleanJob({
    required this.takePath,
    required this.referencePath,
    required this.outputPath,
    required this.expectedDelayFrames,
  });

  /// The take as recorded, with the speaker bleeding into it.
  final String takePath;

  /// The copy of what the speaker was playing, captured alongside it.
  final String referencePath;

  /// Where the cleaned version goes. Never the take: the original is kept
  /// until the result has been looked at.
  final String outputPath;

  /// This route's measured round trip, the same figure the take was
  /// compensated by.
  ///
  /// Not optional in practice. The canceller can find the delay by correlating
  /// the two files, but that needs the bleed to stand clear of everything else
  /// in the take — a player only a few dB above it is enough to hide it, which
  /// is every take anyone actually performed on.
  final int expectedDelayFrames;
}

/// What a clean produced.
class CleanResult {
  const CleanResult({required this.ok, required this.reductionDb});

  final bool ok;

  /// Energy removed from the blocks that carried bleed, in dB.
  ///
  /// Reads low on a take with someone playing on it even when the cancellation
  /// worked well, because the performance dominates what is left. Useful for
  /// telling "it ran" from "it found nothing"; not a quality score to show
  /// anyone.
  final double reductionDb;

  static const CleanResult failed =
      CleanResult(ok: false, reductionDb: 0);
}
