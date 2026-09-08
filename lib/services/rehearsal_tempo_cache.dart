import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'audio_input_ffi.dart';

/// One file to render, and what to render it into.
///
/// Passed to a background isolate, so it holds nothing but strings and
/// numbers — a `Rehearsal` would not survive the crossing.
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

/// Renders takes at a practice tempo, and remembers what it rendered.
///
/// Stretching happens once per file per tempo, into a cache beside the takes,
/// rather than in the audio callback. Six tracks each running an FFT per block
/// is exactly the dropout risk the audio rules exist to prevent, and the device
/// most likely to be in a school rehearsal is the one least able to afford it.
/// Waiting two seconds after moving a slider is a far better outcome than a
/// crackle in the middle of someone's part.
///
/// The engine then plays a rendered file through the ordinary disk-streaming
/// path, knowing nothing about tempo at all.
class RehearsalTempoCache {
  /// Directory name inside a rehearsal's folder.
  ///
  /// Everything here is derived and disposable: deleting it costs a re-render
  /// and nothing else, which is what makes it safe to clear whenever the tempo
  /// moves.
  static const String dirName = 'tempo';

  /// Ratios closer to 1 than this are treated as no change at all.
  ///
  /// Rendering a file to play it back essentially unaltered spends seconds to
  /// achieve nothing, and passing audio through a vocoder is never quite
  /// lossless.
  static const double _unitTolerance = 0.001;

  /// Whether [ratio] is far enough from 1 to be worth rendering.
  static bool needsRender(double ratio) =>
      (ratio - 1.0).abs() > _unitTolerance;

  /// Name a rendered file is stored under.
  ///
  /// The ratio is part of the name so a stale render can never be mistaken for
  /// a current one — the failure that would produce is a track playing at the
  /// wrong length against a correct grid, which sounds like the app is broken
  /// rather than like a cache miss.
  static String fileNameFor(String sourceName, double ratio) {
    final tag = (ratio * 10000).round();
    return '$tag-$sourceName';
  }

  /// Runs [jobs], skipping any whose output is already there.
  ///
  /// Off the UI thread: a three-minute take takes seconds to render, and doing
  /// it inline would freeze the screen at exactly the moment the user is
  /// waiting to hear the result.
  Future<void> render(List<StretchJob> jobs) async {
    final todo = <StretchJob>[];
    for (final job in jobs) {
      final out = File(job.destination);
      // Zero length means an interrupted render: the file exists and plays
      // nothing, which is worse than not having it.
      if (await out.exists() && await out.length() > 0) continue;
      todo.add(job);
    }
    if (todo.isEmpty) return;
    await Isolate.run(() => _renderAll(todo));
  }

  /// Removes everything in [dir] that is not named in [keep].
  ///
  /// Called after a render rather than before: the files being replaced may
  /// still be open in the engine, and a track whose file vanishes underneath
  /// it is a worse failure than a few seconds of extra disk use.
  Future<void> sweep(Directory dir, Set<String> keep) async {
    if (!await dir.exists()) return;
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (keep.contains(name)) continue;
      try {
        await entry.delete();
      } catch (e) {
        // A file still held open by the engine will go on the next sweep.
        debugPrint('RehearsalTempoCache: could not remove $name — $e');
      }
    }
  }
}

/// Renders every job in turn. Runs in a background isolate.
///
/// Top-level rather than a method because an isolate entry point cannot close
/// over `this`.
void _renderAll(List<StretchJob> jobs) {
  final ffi = AudioInputFFI();
  for (final job in jobs) {
    final rc = ffi.stretchFile(job.source, job.destination, job.ratio);
    if (rc != 0) {
      debugPrint('RehearsalTempoCache: render failed ($rc) for ${job.source}');
    }
  }
}
