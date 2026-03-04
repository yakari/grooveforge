/// Defines how notes and chord roots should be displayed in the UI.
enum NotationFormat {
  /// Standard western notation (e.g., C, D, E).
  standard,

  /// Solfege notation, common in Romance languages (e.g., Do, Ré, Mi).
  solfege,
}

/// An advanced utility to parse a set of active MIDI notes into rich human-readable chord names.
///
/// **Algorithm Overview:**
/// 1. Converts physical MIDI notes into a 12-bit "Pitch Class" mask (0-11).
/// 2. Iterates through every pressed note, treating it as a potential Root.
/// 3. Rotates the 12-bit mask so the potential Root sits at position 0.
/// 4. Compares the rotated mask against known bitmask templates (`_coreTemplates`).
/// 5. Scores matches based on tightest fit, explaining the most notes, and valid extensions (9/11/13).
/// 6. Returns the highest-scoring [ChordMatch], or null if no valid chord is found.
class ChordDetector {
  /// Bitmask templates for core chord shapes, relative to the root (bit 0 = Root).
  /// For example, a Major Triad (Root, M3, P5 = intervals 0, 4, 7) is represented
  /// in binary as 10010001, which is 0x091 in hex.
  static const Map<String, int> _coreTemplates = {
    // Triads
    '': 0x091, // Major: R(0), M3(4), P5(7) -> 10010001
    'm': 0x089, // Minor: R(0), m3(3), P5(7) -> 10001001
    'dim': 0x049, // Diminished: R(0), m3(3), b5(6) -> 01001001
    'aug': 0x111, // Augmented: R(0), M3(4), #5(8) -> 100010001
    'sus2': 0x085, // Sus2: R(0), M2(2), P5(7) -> 10000101
    'sus4': 0x0A1, // Sus4: R(0), P4(5), P5(7) -> 10100001
    '5': 0x081, // Power: R(0), P5(7) -> 10000001
    // 6ths
    '6': 0x291, // Major 6: R(0), M3(4), P5(7), M6(9) -> 1010010001
    'm6': 0x289, // Minor 6: R(0), m3(3), P5(7), M6(9) -> 1010001001
    // 7ths
    '7': 0x491, // Dominant 7: R(0), M3(4), P5(7), m7(10) -> 10010010001
    'maj7': 0x891, // Major 7: R(0), M3(4), P5(7), M7(11) -> 100010010001
    'm7': 0x489, // Minor 7: R(0), m3(3), P5(7), m7(10) -> 10010001001
    'mMaj7': 0x889, // Minor-Major 7: R(0), m3(3), P5(7), M7(11) -> 100010001001
    'm7b5': 0x449, // Half-Diminished: R(0), m3(3), b5(6), m7(10) -> 10001001001
    'dim7': 0x249, // Diminished 7: R(0), m3(3), b5(6), d7/M6(9) -> 1001001001
    // Sus 7ths
    '7sus4': 0x4A1, // 7sus4: R(0), P4(5), P5(7), m7(10) -> 10010100001
  };

  /// Associates basic chord templates with their most common implied 7-note diatonic scale.
  /// Bitmask representation of the scale relative to the root.
  static const Map<String, int> _templateToScale = {
    // Ionian: 0, 2, 4, 5, 7, 9, 11 -> 101010110101
    '': 0xAB5,
    'maj7': 0xAB5,
    '6': 0xAB5,
    'sus2': 0xAB5,
    'sus4': 0xAB5,
    '5': 0xAB5,
    // Dorian: 0, 2, 3, 5, 7, 9, 10 -> 011010101101
    // Aeolian: 0, 2, 3, 5, 7, 8, 10 -> 0x5AD
    'm': 0x5AD, 'm7': 0x5AD, 'm6': 0x6AD,
    // Mixolydian: 0, 2, 4, 5, 7, 9, 10 -> 011010110101
    '7': 0x6B5, '7sus4': 0x6B5,
    // Harmonic Minor: 0, 2, 3, 5, 7, 8, 11 -> 100110101101
    'mMaj7': 0x9AD,
    // Locrian: 0, 1, 3, 5, 6, 8, 10 -> 010101101011
    'dim': 0x56B,
    'm7b5': 0x56B,
    'dim7': 0x56B, // Dim7 isn't strictly Locrian but Locrian is a safe fallback
    // Whole Tone (or Lydian Augmented): 0, 2, 4, 6, 8, 10 -> 010101010101
    'aug': 0x555,
  };

  /// The standard western chromatic scale
  static const List<String> _standardNames = [
    'C',
    'C#',
    'D',
    'Eb',
    'E',
    'F',
    'F#',
    'G',
    'Ab',
    'A',
    'Bb',
    'B',
  ];

  /// The solfege scale
  static const List<String> _solfegeNames = [
    'Do ',
    'Do# ',
    'Ré ',
    'Mib ',
    'Mi ',
    'Fa ',
    'Fa# ',
    'Sol ',
    'Lab ',
    'La ',
    'Sib ',
    'Si ',
  ];

  /// Evaluates a set of active MIDI notes to find the most mathematically probable chord.
  ///
  /// Uses a bitmask pattern-matching algorithm to identify the root, quality, and extensions.
  /// Returns a [ChordMatch] containing the formatted string and implied scale, or null
  /// if the input contains fewer than 3 notes or resolves to no known harmonic structure.
  static ChordMatch? identifyChord(
    Set<int> activeNotes, {
    NotationFormat format = NotationFormat.standard,
  }) {
    if (activeNotes.length < 3) return null; // Need at least a triad

    List<String> noteNames =
        format == NotationFormat.solfege ? _solfegeNames : _standardNames;

    // 1. Identify the absolute lowest note (Bass note) for inversions / slash chords
    int minNote = activeNotes.reduce((a, b) => a < b ? a : b);
    int bassPc = minNote % 12;

    // 2. Reduce all notes to a 12-bit input mask representing pitch classes present
    int inputMask = 0;
    for (int note in activeNotes) {
      inputMask |= (1 << (note % 12));
    }

    _ScoredMatch? bestMatch;

    // 3. Test every present note as a potential Root.
    for (int rootPc = 0; rootPc < 12; rootPc++) {
      // If this potential root isn't even in our active notes, skip it.
      if ((inputMask & (1 << rootPc)) == 0) continue;

      // Rotate the 12-bit input mask so that the root sits at bit zero (interval 0).
      int relativeMask = _rotateMaskToRoot(inputMask, rootPc);

      // 4. Test against our core templates.
      for (var entry in _coreTemplates.entries) {
        String suffix = entry.key;
        int templateMask = entry.value;

        // Check if the relative input contains all the required bits for this template.
        // Also allow the 5th (bit 7) to be optional for 7th chords/triads.
        int requiredMask = templateMask;

        // Loosen requirement for P5 if it's a 7th chord or we have extensions taking up space
        bool is7thFamily = suffix.contains('7') || suffix.contains('6');
        if (is7thFamily) {
          requiredMask &= ~(1 << 7); // Strip P5 from requirements
        }

        if ((relativeMask & requiredMask) == requiredMask) {
          // It's a match! Now see what intervals are left over as extensions.
          int extraMask = relativeMask & ~templateMask;

          List<String> extensions = [];

          // Parse extensions
          if ((extraMask & (1 << 2)) != 0) extensions.add('9');
          if ((extraMask & (1 << 5)) != 0) extensions.add('11');
          if ((extraMask & (1 << 9)) != 0) extensions.add('13');

          // Parse Alterations
          if ((extraMask & (1 << 1)) != 0) extensions.add('b9');
          if ((extraMask & (1 << 3)) != 0) extensions.add('#9');
          if ((extraMask & (1 << 6)) != 0 &&
              !suffix.contains('dim') &&
              !suffix.contains('b5')) {
            extensions.add('#11');
          }
          if ((extraMask & (1 << 8)) != 0 &&
              !suffix.contains('aug') &&
              !suffix.contains('m6')) {
            extensions.add('b13');
          }

          // Score the match
          int score = 0;

          int numExtraTones = _popCount(extraMask);

          // Number of valid notes explained by the template (if they exist in the input)
          int explainedNotes = _popCount(relativeMask & templateMask);
          score +=
              explainedNotes * 10; // Heavily reward explaining notes natively

          if (rootPc == bassPc) {
            score += 5; // Bonus for root position
          }

          // Valid extensions mask: 9(bit 2) | 11(bit 5) | 13(bit 9) | b9(bit 1) | #9(bit 3) | #11(bit 6) | b13(bit 8)
          int validExtMask =
              (1 << 2) |
              (1 << 5) |
              (1 << 9) |
              (1 << 1) |
              (1 << 3) |
              (1 << 6) |
              (1 << 8);
          if (!is7thFamily) {
            // Only allow add9 for simple triads to avoid crazy extra matches
            validExtMask = (1 << 2);
          }

          int invalidExtraTones = extraMask & ~validExtMask;

          // Penalize strictly invalid tones heavily
          score -= _popCount(invalidExtraTones) * 20;

          // Reward valid extensions
          int validExtensions = extraMask & validExtMask;
          score += _popCount(validExtensions) * 4;

          if (templateMask == requiredMask && numExtraTones == 0) {
            score += 15; // Perfect tight match
          }

          if (!is7thFamily) {
            // If it's a basic triad template but we have extensions,
            // format it as "add9" instead of just "9".
            for (int i = 0; i < extensions.length; i++) {
              if (extensions[i] == '9' || extensions[i] == '11') {
                extensions[i] = 'add${extensions[i]}';
              }
            }
          }

          // Build string
          String chordName = '${noteNames[rootPc]}$suffix';
          if (extensions.isNotEmpty) {
            chordName += '(${extensions.join(',')})';
          }

          // Append inversion slash bass if needed
          if (rootPc != bassPc) {
            chordName += '/${noteNames[bassPc]}';
          }

          if (bestMatch == null || score > bestMatch.score) {
            // Derive Scale
            int scaleMask =
                _templateToScale[suffix] ??
                _templateToScale['']!; // Default to Ionian if unknown

            // Integrate explicit extensions/alterations from the user into the scale
            scaleMask |= extraMask;

            // Shift scale back from relative root to absolute pitch classes
            Set<int> absoluteScalePcs = {};
            for (int i = 0; i < 12; i++) {
              if ((scaleMask & (1 << i)) != 0) {
                absoluteScalePcs.add((rootPc + i) % 12);
              }
            }

            // Ensure bass note is in the scale just in case
            absoluteScalePcs.add(bassPc);

            bool isMinor =
                (templateMask & (1 << 3)) != 0 || suffix.contains('m');
            bestMatch = _ScoredMatch(
              chordName,
              score,
              absoluteScalePcs,
              rootPc,
              isMinor,
              suffix: suffix,
              extensionsMask: extraMask,
            );
          }
        }
      }
    }

    if (bestMatch == null) return null;
    return ChordMatch(
      bestMatch.chordName,
      bestMatch.scalePitchClasses,
      bestMatch.rootPc,
      bestMatch.isMinor,
      suffix: bestMatch.suffix,
      extensionsMask: bestMatch.extensionsMask,
    );
  }

  /// Rotates a 12-bit pitch mask so the root rests at bit 0.
  /// Example: {C, E, G} with root=C -> bitmask 100010001 (intervals 0, 4, 7)
  static int _rotateMaskToRoot(int mask, int rootPc) {
    // Keep only lowest 12 bits
    mask &= 0xFFF;

    // Shift right to bring root to position 0
    int upper = mask >> rootPc;
    // The bits that wrapped around the octave shift left
    int lower = (mask << (12 - rootPc)) & 0xFFF;

    return upper | lower;
  }

  /// Standard Kernighan bit population count for small ints
  static int _popCount(int v) {
    int c = 0;
    for (; v > 0; c++) {
      v &= v - 1; // clear the least significant bit set
    }
    return c;
  }
}

/// Internal class used during the chord identification loop to track the highest-scoring candidate.
class _ScoredMatch {
  /// The formatted human-readable name of the chord.
  final String chordName;

  /// The mathematical score indicating how well the input notes fit this template.
  final int score;

  /// The set of pitch classes representing the implied scale for this chord.
  final Set<int> scalePitchClasses;

  /// The pitch class (0-11) identified as the mathematical root of the chord.
  final int rootPc;

  /// Whether the identified chord has a minor third.
  final bool isMinor;

  /// The template suffix matched (e.g., 'm7', 'maj7').
  final String suffix;

  /// Bitmask representing valid upper extensions beyond the core template (9th, 11th, etc.).
  final int extensionsMask;
  _ScoredMatch(
    this.chordName,
    this.score,
    this.scalePitchClasses,
    this.rootPc,
    this.isMinor, {
    required this.suffix,
    required this.extensionsMask,
  });
}

/// Represents a successfully identified chord structure and its musical implications.
class ChordMatch {
  /// The formatted human-readable name of the chord (e.g., "Cmaj7/G" or "La#m(add9)").
  final String name;

  /// The set of pitch classes (0-11) representing the natural scale implied by this chord.
  final Set<int> scalePitchClasses;

  /// The pitch class (0-11) corresponding to the root note of the chord.
  final int rootPc;

  /// True if the chord contains a minor third; false otherwise.
  final bool isMinor;

  /// The base suffix identified (e.g., '', 'm', 'maj7', 'dim').
  final String suffix;

  /// Active upper extensions identified during matching, stored as a bitmask relative to the root.
  final int extensionsMask;

  ChordMatch(
    this.name,
    this.scalePitchClasses,
    this.rootPc,
    this.isMinor, {
    this.suffix = '',
    this.extensionsMask = 0,
  });
}
