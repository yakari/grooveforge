import 'dart:math' as math;

import 'gf_scale.dart';

/// Outcome of reading a Scala `.scl` file.
///
/// A result object rather than an exception because import is a user action on
/// a file the app did not write: "line 7 is not a pitch" is something to show
/// the player, not something to crash on.
class GFScalaImportResult {
  /// The imported scale, or null when [error] explains why there is none.
  final GFScale? scale;

  /// Why the import failed, in plain English. Null on success.
  final String? error;

  const GFScalaImportResult.success(GFScale this.scale) : error = null;
  const GFScalaImportResult.failure(String this.error) : scale = null;

  bool get isSuccess => scale != null;
}

/// Reads the Scala `.scl` tuning format.
///
/// **The format**, which is plain text and older than most of what reads it:
///
/// ```
/// ! meanquar.scl
/// !
/// 1/4-comma meantone scale
///  12
/// !
///  76.04900
///  193.15686
///  ...
///  2/1
/// ```
///
/// - Lines beginning with `!` are comments and are skipped entirely.
/// - The first surviving line is the description.
/// - The second is the number of pitches that follow.
/// - Each remaining line is one pitch **above the tonic**. A value containing a
///   dot is in cents; anything else is a frequency ratio (`3/2`, or a bare
///   integer meaning `n/1`). Text after the value is a comment.
///
/// Two things routinely surprise people reading their first `.scl`:
///
/// - **The tonic is not listed.** A twelve-note scale has twelve lines, and
///   they are degrees 1 through 12, not 0 through 11.
/// - **The last line is the period**, not a degree — the interval at which the
///   scale repeats. Usually `2/1`, an octave; `3/1` for Bohlen-Pierce. This is
///   what lets non-octave scales survive the round trip.
///
/// **Keyboard layout.** A scale of twelve degrees or fewer is laid out the
/// familiar way, one degree per key of the octave, leaving unused keys — the
/// same layout a maqam uses. Beyond twelve there is no key to assign each
/// degree to, so degrees take successive keys and one period spans as many
/// keys as the scale has degrees. A scale that would collide two degrees onto
/// the same key falls back to the linear layout too.
///
/// **What is lost.** `.scl` has no notion of a degree being present but
/// excluded from snapping, so an imported scale has every degree active. The
/// custom-scale editor can then mute individual keys.
class GFScalaFile {
  GFScalaFile._();

  /// Parses [contents] into a scale identified by [id].
  ///
  /// [fallbackName] is used when the file's description line is blank, which
  /// is common in machine-generated files — pass the filename.
  static GFScalaImportResult parse(
    String contents, {
    required String id,
    String fallbackName = 'Imported scale',
  }) {
    final lines = _significantLines(contents);
    if (lines.length < 2) {
      return const GFScalaImportResult.failure(
        'Not a Scala file: expected a description line and a note count.',
      );
    }

    final description = lines[0].trim();
    final declaredCount = int.tryParse(lines[1].trim());
    if (declaredCount == null || declaredCount < 1) {
      return GFScalaImportResult.failure(
        'Expected a note count on line 2, found "${lines[1].trim()}".',
      );
    }

    final pitchLines = lines.skip(2).toList();
    if (pitchLines.length < declaredCount) {
      return GFScalaImportResult.failure(
        'File declares $declaredCount notes but contains '
        '${pitchLines.length}.',
      );
    }

    // Degrees above the tonic, in cents. The tonic itself is implicit.
    final pitches = <double>[];
    for (var i = 0; i < declaredCount; i++) {
      final cents = _parsePitch(pitchLines[i]);
      if (cents == null) {
        return GFScalaImportResult.failure(
          'Line ${i + 3} is not a pitch: "${pitchLines[i].trim()}".',
        );
      }
      pitches.add(cents);
    }

    // The last entry is the repeat interval, not a degree.
    final periodCents = pitches.removeLast();
    if (periodCents <= 0) {
      return const GFScalaImportResult.failure(
        'The repeat interval must be greater than zero.',
      );
    }

    // Degrees, tonic first.
    final degreeCents = <double>[0.0, ...pitches];
    if (degreeCents.any((c) => c < 0)) {
      return const GFScalaImportResult.failure(
        'Degrees below the tonic are not supported.',
      );
    }

    final name = description.isEmpty ? fallbackName : description;
    final degrees = _layOut(degreeCents);

    return GFScalaImportResult.success(
      GFScale(
        id: id,
        name: name,
        family: GFScaleFamily.custom,
        provenance: 'Imported from Scala (.scl)',
        mapping: degrees.mapping,
        periodCents: periodCents,
        degrees: degrees.degrees,
      ),
    );
  }

  // ── Writing ────────────────────────────────────────────────────────────────

  /// Writes [scale] as a Scala `.scl` file.
  ///
  /// Nothing has to be recomputed to do this: [GFScaleDegree.centsFromRoot] is
  /// already the distance from the tonic that the format asks for, because a
  /// degree stores its key and its deviation separately and their sum is the
  /// absolute pitch.
  ///
  /// Follows the format's two conventions: the tonic is not written, and the
  /// last line is the repeat interval rather than a degree — so a scale of *n*
  /// degrees produces *n* lines.
  ///
  /// **What survives the round trip and what does not.** Every pitch is
  /// preserved exactly. The *keyboard layout* is not, because `.scl` has no
  /// way to say which key a degree belongs to: re-importing places degrees
  /// back on the nearest key, which recovers the original layout for a scale
  /// whose degrees sit near distinct keys (a maqam, a temperament) but not for
  /// one that crowds several degrees into a single semitone — those come back
  /// on the linear layout, sounding identical and fingered differently. Export
  /// to share a tuning with other microtonal software; keep the JSON export
  /// for a faithful round trip.
  static String export(GFScale scale) {
    final buffer = StringBuffer()
      ..writeln('! ${scale.id}.scl')
      ..writeln('!')
      ..writeln(scale.name.isEmpty ? 'Untitled scale' : scale.name);

    final degrees = _exportableDegrees(scale);
    buffer
      ..writeln(' ${degrees.length + 1}')
      ..writeln('!');

    for (final cents in degrees) {
      buffer.writeln(' ${_formatCents(cents)}');
    }
    // The repeat interval closes the file.
    buffer.writeln(' ${_formatCents(scale.periodCents)}');

    if (scale.provenance.isNotEmpty) {
      buffer
        ..writeln('!')
        ..writeln('! ${scale.provenance}');
    }
    return buffer.toString();
  }

  /// The degrees above the tonic, ascending, ready to be written.
  ///
  /// Drops the tonic (implicit in the format) and anything at or beyond the
  /// period, and sorts — a hand-made scale can legitimately place its degrees
  /// out of pitch order across the keyboard, but a `.scl` file that does so is
  /// malformed.
  static List<double> _exportableDegrees(GFScale scale) {
    final cents = scale.degrees
        .map((d) => d.centsFromRoot)
        .where((c) => c > 0.0 && c < scale.periodCents)
        .toList()
      ..sort();

    // Two degrees on the same pitch would be a duplicate line.
    final unique = <double>[];
    for (final c in cents) {
      if (unique.isEmpty || (c - unique.last).abs() > 0.0001) unique.add(c);
    }
    return unique;
  }

  /// Formats a value as cents.
  ///
  /// Always includes a decimal point: in `.scl` a dotted value means cents and
  /// an undotted one means a frequency ratio, so "1200" would be read as the
  /// ratio 1200/1 — ten and a half octaves up.
  static String _formatCents(double cents) {
    final text = cents.toStringAsFixed(6);
    return text.contains('.') ? text : '$text.000000';
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

  /// Chooses a keyboard layout for [degreeCents] and builds the degrees.
  ///
  /// Prefers the familiar one-degree-per-key layout, and falls back to linear
  /// when the scale cannot fit it — more than twelve degrees, or two degrees
  /// that would land on the same key.
  static ({GFScaleMapping mapping, List<GFScaleDegree> degrees}) _layOut(
    List<double> degreeCents,
  ) {
    if (degreeCents.length <= 12) {
      final semitones = degreeCents
          .map((c) => (c / 100.0).round().clamp(0, 11))
          .toList();
      final fits = semitones.toSet().length == semitones.length &&
          _isStrictlyAscending(semitones);
      if (fits) {
        return (
          mapping: GFScaleMapping.pitchClass,
          degrees: [
            for (var i = 0; i < degreeCents.length; i++)
              GFScaleDegree(semitones[i], degreeCents[i] - semitones[i] * 100.0),
          ],
        );
      }
    }

    // Linear: degree i takes key i, so its deviation is measured from i * 100.
    return (
      mapping: GFScaleMapping.linear,
      degrees: [
        for (var i = 0; i < degreeCents.length; i++)
          GFScaleDegree(i, degreeCents[i] - i * 100.0),
      ],
    );
  }

  static bool _isStrictlyAscending(List<int> values) {
    for (var i = 1; i < values.length; i++) {
      if (values[i] <= values[i - 1]) return false;
    }
    return true;
  }

  // ── Line parsing ───────────────────────────────────────────────────────────

  /// Strips comments and blank lines, preserving order.
  ///
  /// A blank description line is significant — it means "no name" — so only
  /// leading `!` comments and truly empty lines are dropped, and the
  /// description is allowed to be an empty string once found.
  static List<String> _significantLines(String contents) {
    final out = <String>[];
    var seenDescription = false;
    for (final raw in contents.split('\n')) {
      final line = raw.replaceAll('\r', '');
      if (line.trimLeft().startsWith('!')) continue;
      if (!seenDescription) {
        // The description is the first non-comment line, even if blank.
        out.add(line);
        seenDescription = true;
        continue;
      }
      if (line.trim().isEmpty) continue;
      out.add(line);
    }
    return out;
  }

  /// Parses one pitch line into cents, or null when it is not a pitch.
  ///
  /// A dot anywhere in the value means cents; otherwise it is a ratio. Trailing
  /// text is a comment and is ignored, which is how most real files annotate
  /// their degrees.
  static double? _parsePitch(String line) {
    final token = line.trim().split(RegExp(r'\s+')).first;
    if (token.isEmpty) return null;

    if (token.contains('.')) {
      return double.tryParse(token);
    }

    final parts = token.split('/');
    if (parts.length > 2) return null;
    final numerator = double.tryParse(parts[0]);
    final denominator = parts.length == 2 ? double.tryParse(parts[1]) : 1.0;
    if (numerator == null || denominator == null) return null;
    if (numerator <= 0 || denominator <= 0) return null;

    // Ratio → cents: 1200 × log2(n/d).
    return 1200.0 * (math.log(numerator / denominator) / math.ln2);
  }
}
