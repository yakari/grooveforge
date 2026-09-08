/// Chord symbols: reading what a musician writes on a chart, and working out
/// which notes it means.
///
/// Kept free of Flutter and of the rehearsal model so it can be used anywhere:
/// the chord grid needs it to validate and display, and a keyboard overlay or
/// a guitar chart would need the notes it produces. That second use is the
/// reason this parses rather than merely checks — a symbol stored as text
/// alone could never light up a fretboard.
library;

/// How a chord's basic triad is built.
enum ChordTriad {
  major,
  minor,
  diminished,
  augmented,
  suspendedSecond,
  suspendedFourth,

  /// A bare fifth: root and fifth, no third. Written `C5`.
  power,
}

/// Which seventh, if any, sits on top of the triad.
enum ChordSeventh {
  none,

  /// Ten semitones — the seventh of a dominant or minor seventh chord.
  minor,

  /// Eleven semitones, written `maj7`, `M7` or `Δ`.
  major,

  /// Nine semitones, only found on a diminished chord.
  diminished,
}

/// One chord symbol, parsed.
///
/// Holds both what was written and what it means. The text is kept because a
/// chart should show what the player typed — `Cmaj7` and `CM7` are the same
/// chord and different handwriting — while the intervals are what any future
/// keyboard or fretboard display would draw.
class ChordSymbol {
  const ChordSymbol({
    required this.text,
    required this.rootName,
    required this.rootPitchClass,
    required this.triad,
    required this.seventh,
    required this.intervals,
    this.bassName,
    this.bassPitchClass,
  });

  /// The symbol as written, trimmed. Never rewritten into a canonical form:
  /// a chart is somebody's handwriting.
  final String text;

  /// Root as spelled, e.g. `Ab` — not respelled as `G#`. Which of the two a
  /// player wrote says something about the key they are thinking in.
  final String rootName;

  /// Root as a pitch class, 0 = C.
  final int rootPitchClass;

  final ChordTriad triad;
  final ChordSeventh seventh;

  /// Semitones above the root, always including 0.
  ///
  /// Everything the symbol asks for: the triad, the seventh, extensions and
  /// alterations. Not voiced and not octave-aware — that is a decision for
  /// whatever draws it.
  final Set<int> intervals;

  /// Bass note when the symbol names one, as in `Am/B`.
  final String? bassName;
  final int? bassPitchClass;

  /// Pitch classes the chord contains, bass included.
  Set<int> get pitchClasses => {
        for (final i in intervals) (rootPitchClass + i) % 12,
        if (bassPitchClass != null) bassPitchClass!,
      };

  /// The symbol with real accidental signs, for display.
  ///
  /// `Bb` reads as a word; `B♭` reads as a chord. Only the accidentals change,
  /// so `maj7` and `sus4` stay as the player wrote them.
  String get display => _prettyAccidentals(text);

  @override
  String toString() => text;

  // ── Parsing ───────────────────────────────────────────────────────────────

  /// Reads a chord symbol, or returns null if it is not one.
  ///
  /// Deliberately forgiving about *style* and strict about *structure*. A root
  /// note is required and has to be real; after that, `maj7`, `M7`, `Δ7` and
  /// `Ma7` are all accepted because all four turn up on real charts. What is
  /// refused is a symbol whose root cannot be read, because that is the part a
  /// keyboard or a fretboard cannot guess at.
  static ChordSymbol? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    // Accidental signs are normalised to ASCII for parsing; display puts them
    // back. Nobody types ♯ on a phone, but a paste from elsewhere might.
    final work = text.replaceAll('♯', '#').replaceAll('♭', 'b');

    final root = _readNote(work, 0);
    if (root == null) return null;

    var rest = work.substring(root.length);

    // A slash means a bass note — unless what follows is a number, in which
    // case it is an added tone: `C6/9` is a sixth chord with a ninth, not a C6
    // over a ninth. Splitting on the *last* slash that is followed by a note
    // keeps `Am(M7)/B` working too.
    String? bassText;
    final slash = rest.lastIndexOf('/');
    if (slash >= 0) {
      final after = rest.substring(slash + 1);
      final bassNote = _readNote(after, 0);
      if (bassNote != null && bassNote.length == after.length) {
        bassText = after;
        rest = rest.substring(0, slash);
      }
    }

    // Parentheses only group; `Am(M7)` and `AmM7` are the same chord.
    rest = rest.replaceAll('(', '').replaceAll(')', '').replaceAll(' ', '');

    final built = _readQuality(rest);
    if (built == null) return null;

    final bass = bassText == null ? null : _noteToPitchClass(bassText);
    return ChordSymbol(
      text: text,
      rootName: _prettyCaseNote(work.substring(0, root.length)),
      rootPitchClass: root.pitchClass,
      triad: built.triad,
      seventh: built.seventh,
      intervals: built.intervals,
      bassName: bassText == null ? null : _prettyCaseNote(bassText),
      bassPitchClass: bass,
    );
  }

  /// Whether [input] reads as a chord. Cheaper to say than to explain.
  static bool isValid(String input) => parse(input) != null;
}

// ─── Notes ───────────────────────────────────────────────────────────────────

/// Semitone of each natural note above C.
const Map<String, int> _naturals = {
  'C': 0,
  'D': 2,
  'E': 4,
  'F': 5,
  'G': 7,
  'A': 9,
  'B': 11,
};

class _Note {
  const _Note(this.pitchClass, this.length);
  final int pitchClass;
  final int length;
}

/// Reads a note name at [at]: a letter and any accidentals after it.
///
/// Double accidentals are accepted because `Fbb` and `G##` do occur, rare as
/// they are, and refusing them would be refusing correct notation.
_Note? _readNote(String s, int at) {
  if (at >= s.length) return null;
  final letter = s[at].toUpperCase();
  final natural = _naturals[letter];
  if (natural == null) return null;

  var pc = natural;
  var i = at + 1;
  while (i < s.length && (s[i] == '#' || s[i] == 'b')) {
    // A lower-case b is only an accidental where a note has already been read,
    // which is exactly here — `Bb` is B flat, and the leading B was consumed
    // above.
    pc += s[i] == '#' ? 1 : -1;
    i++;
  }
  return _Note((pc % 12 + 12) % 12, i - at);
}

int? _noteToPitchClass(String s) => _readNote(s, 0)?.pitchClass;

/// Capitalises the letter and leaves the accidentals alone.
String _prettyCaseNote(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Swaps ASCII accidentals for real ones, but only where they are accidentals.
///
/// The `b` in `Bb` is a flat; the `b` in `b5` is too; the one in `sus` is not
/// a note at all. Only a `b` or `#` that follows a note letter or a degree
/// number is a sign.
String _prettyAccidentals(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if ((c == 'b' || c == '#') && i > 0) {
      final prev = s[i - 1];
      final afterNote = _naturals.containsKey(prev.toUpperCase());
      final afterDigit = prev.compareTo('0') >= 0 && prev.compareTo('9') <= 0;
      // `b5` and `b9` are alterations written *before* the degree, so look
      // ahead as well.
      final beforeDigit = i + 1 < s.length &&
          s[i + 1].compareTo('0') >= 0 &&
          s[i + 1].compareTo('9') <= 0;
      if (afterNote || afterDigit || beforeDigit) {
        out.write(c == 'b' ? '♭' : '♯');
        continue;
      }
    }
    out.write(c);
  }
  return out.toString();
}

// ─── Quality ─────────────────────────────────────────────────────────────────

class _Built {
  _Built(this.triad, this.seventh, this.intervals);
  final ChordTriad triad;
  final ChordSeventh seventh;
  final Set<int> intervals;
}

/// Turns everything after the root into a set of intervals.
///
/// Works through the symbol left to right, longest match first, because `m7`
/// must not be read as `m` followed by a stray `7` and `maj7` must not be read
/// as `ma` — matching the longest token at each step is what keeps those
/// apart without a grammar.
_Built? _readQuality(String s) {
  var triad = ChordTriad.major;
  var seventh = ChordSeventh.none;
  final extras = <int>{};
  final removed = <int>{};

  var i = 0;
  // A symbol names its triad once. `C+-` is augmented *and* minor, which is
  // not a chord — without this the second token quietly wins and a typo turns
  // into a plausible-looking chord nobody meant.
  var triadNamed = false;

  // Minor has to be recognised before anything else, because `m` also starts
  // `maj`. Checking `maj`/`ma`/`M` first and only then a bare `m` settles it.
  // Tokens are tried longest-first below, which is what keeps `maj` from
  // being read as `m` and `sus4` from being read as `sus`.
  bool startsWith(String token) => s.startsWith(token, i);

  while (i < s.length) {
    // Major seventh, in its four spellings.
    if (startsWith('maj') || startsWith('Maj') || startsWith('MAJ')) {
      i += 3;
      seventh = _maybeSeventh(s, i, ChordSeventh.major, seventh);
      continue;
    }
    if (startsWith('M') && !startsWith('Mm')) {
      i += 1;
      seventh = _maybeSeventh(s, i, ChordSeventh.major, seventh);
      continue;
    }
    if (startsWith('Δ')) {
      i += 1;
      seventh = ChordSeventh.major;
      continue;
    }

    if (startsWith('min')) {
      i += 3;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.minor;
      continue;
    }
    if (startsWith('m') || startsWith('-')) {
      i += 1;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.minor;
      continue;
    }

    if (startsWith('dim')) {
      i += 3;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.diminished;
      continue;
    }
    if (startsWith('°') || startsWith('o')) {
      i += 1;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.diminished;
      continue;
    }
    if (startsWith('ø')) {
      // Half-diminished: a diminished triad with a *minor* seventh.
      i += 1;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.diminished;
      seventh = ChordSeventh.minor;
      continue;
    }
    if (startsWith('aug')) {
      i += 3;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.augmented;
      continue;
    }
    if (startsWith('+')) {
      i += 1;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.augmented;
      continue;
    }
    if (startsWith('sus2')) {
      i += 4;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.suspendedSecond;
      continue;
    }
    if (startsWith('sus4')) {
      i += 4;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.suspendedFourth;
      continue;
    }
    if (startsWith('sus')) {
      // A bare `sus` means sus4; that is the convention, not a guess.
      i += 3;
      if (triadNamed) return null;
      triadNamed = true;
      triad = ChordTriad.suspendedFourth;
      continue;
    }

    if (startsWith('add')) {
      i += 3;
      final degree = _readDegree(s, i);
      if (degree == null) return null;
      extras.add(_degreeToSemitones(degree.value, 0));
      i += degree.length;
      continue;
    }
    if (startsWith('no')) {
      i += 2;
      final degree = _readDegree(s, i);
      if (degree == null) return null;
      removed.add(_degreeToSemitones(degree.value, 0));
      i += degree.length;
      continue;
    }

    // An alteration written before its degree: b5, #9, b13.
    if (s[i] == 'b' || s[i] == '#') {
      final shift = s[i] == 'b' ? -1 : 1;
      final degree = _readDegree(s, i + 1);
      if (degree == null) return null;
      final natural = _degreeToSemitones(degree.value, 0);
      removed.add(natural);
      extras.add(natural + shift);
      i += 1 + degree.length;
      continue;
    }

    // A bare number: the chord's extension, or a sixth, or a power chord.
    final degree = _readDegree(s, i);
    if (degree != null) {
      i += degree.length;
      switch (degree.value) {
        case 5:
          triad = ChordTriad.power;
        case 6:
          extras.add(9);
          // `6/9` — the slash here joins two added tones and is not a bass.
          if (i + 1 < s.length && s[i] == '/' && s[i + 1] == '9') {
            extras.add(14);
            i += 2;
          }
        case 7:
          if (triad == ChordTriad.diminished && seventh == ChordSeventh.none) {
            seventh = ChordSeventh.diminished;
          } else if (seventh == ChordSeventh.none) {
            seventh = ChordSeventh.minor;
          }
        case 9:
          if (seventh == ChordSeventh.none) seventh = ChordSeventh.minor;
          extras.add(14);
        case 11:
          if (seventh == ChordSeventh.none) seventh = ChordSeventh.minor;
          extras..add(14)..add(17);
        case 13:
          if (seventh == ChordSeventh.none) seventh = ChordSeventh.minor;
          extras..add(14)..add(17)..add(21);
        default:
          return null; // 2, 4, 8, 10, 12 … are not chord qualities
      }
      continue;
    }

    // Anything else is not a chord symbol. Refusing here is the point: a
    // fretboard cannot draw what nobody could read.
    return null;
  }

  // A bare root is a major triad: an empty suffix is a perfectly good symbol.
  final intervals = <int>{..._triadIntervals(triad)};
  switch (seventh) {
    case ChordSeventh.none:
      break;
    case ChordSeventh.minor:
      intervals.add(10);
    case ChordSeventh.major:
      intervals.add(11);
    case ChordSeventh.diminished:
      intervals.add(9);
  }
  intervals.addAll(extras);
  intervals.removeAll(removed.where((d) => d != 0));
  intervals.add(0);
  return _Built(triad, seventh, intervals);
}

/// Reads a `7` immediately after a major-seventh marker.
///
/// `CM7` and `Cmaj7` name the seventh explicitly; `CM` and `Cmaj` are just a
/// major triad and must not gain one.
ChordSeventh _maybeSeventh(
    String s, int at, ChordSeventh ifPresent, ChordSeventh current) {
  if (at < s.length && s[at] == '7') return ifPresent;
  if (at < s.length && (s[at] == '9' || s[at] == '1')) return ifPresent;
  return current;
}

class _Degree {
  const _Degree(this.value, this.length);
  final int value;
  final int length;
}

/// Reads a chord degree — 5, 6, 7, 9, 11, 13 — at [at].
_Degree? _readDegree(String s, int at) {
  if (at >= s.length) return null;
  for (final two in const ['11', '13']) {
    if (s.startsWith(two, at)) return _Degree(int.parse(two), 2);
  }
  final c = s[at];
  if (c.compareTo('0') >= 0 && c.compareTo('9') <= 0) {
    return _Degree(int.parse(c), 1);
  }
  return null;
}

/// Semitones above the root for a written degree, before alteration.
int _degreeToSemitones(int degree, int shift) => switch (degree) {
      2 => 2,
      3 => 4,
      4 => 5,
      5 => 7,
      6 => 9,
      7 => 10,
      9 => 14,
      11 => 17,
      13 => 21,
      _ => 0,
    } + shift;

Set<int> _triadIntervals(ChordTriad triad) => switch (triad) {
      ChordTriad.major => {0, 4, 7},
      ChordTriad.minor => {0, 3, 7},
      ChordTriad.diminished => {0, 3, 6},
      ChordTriad.augmented => {0, 4, 8},
      ChordTriad.suspendedSecond => {0, 2, 7},
      ChordTriad.suspendedFourth => {0, 5, 7},
      ChordTriad.power => {0, 7},
    };
