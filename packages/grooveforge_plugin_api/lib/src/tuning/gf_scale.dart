import 'dart:typed_data';

/// One degree of a [GFScale], expressed as a keyboard key plus a detuning.
///
/// A degree answers two separate questions that 12-tone-equal-temperament
/// (12-TET) normally conflates:
///
///   - **Which key do I press?** → [semitone], the number of keyboard
///     semitones above the scale's root. The 3rd degree of a maqam Rast sits
///     on the E key even though it does not sound like a Western E.
///   - **What pitch does that key sound?** → [cents], the deviation from the
///     12-TET pitch of that key. 100 cents = one equal-tempered semitone, so
///     a quarter-tone is 50 cents and the syntonic comma is about 21.5 cents.
///
/// Splitting the two is what lets the same data structure describe a plain
/// major scale ([cents] all zero), an Arabic maqam (a couple of −50 values),
/// an Indian raga in just intonation (every degree slightly off), and a
/// historical temperament (all twelve keys retuned).
class GFScaleDegree {
  /// Keyboard semitones above the scale root — which key the degree lives on.
  ///
  /// In [GFScaleMapping.pitchClass] scales this is a real keyboard offset in
  /// the range 0–11. In [GFScaleMapping.linear] scales it is simply the
  /// degree's index in the scale, because there successive degrees occupy
  /// successive keys by construction.
  final int semitone;

  /// Deviation in cents from the 12-TET pitch of [semitone].
  ///
  /// Positive sharpens, negative flattens. −50 is the quarter-flat of Arabic
  /// practice; −13.7 is the just major third; +3.9 is the Pythagorean whole
  /// tone. Zero means the degree is a plain equal-tempered key.
  final double cents;

  /// Whether the snap stage may move a note onto this degree.
  ///
  /// An inactive ("muted") degree still sounds, and still carries its own
  /// tuning — the key is playable and retuned. It is simply not a destination
  /// the snap stage will pull a wrong note towards.
  ///
  /// This is what separates *muting* a degree from *removing* it: removing
  /// leaves the key chromatic and out of the scale, while muting keeps its
  /// colour available to the fingers and out of the way of the quantiser.
  /// Adding a quarter-tone next to the flat fifth of a blues scale to lean on
  /// during a solo — without having every nearby note snap onto it — is
  /// exactly this distinction.
  final bool active;

  /// Creates a degree on key [semitone], detuned by [cents] (default: none).
  const GFScaleDegree(this.semitone, [this.cents = 0.0, this.active = true]);

  /// A copy of this degree with individual fields replaced.
  GFScaleDegree copyWith({int? semitone, double? cents, bool? active}) =>
      GFScaleDegree(
        semitone ?? this.semitone,
        cents ?? this.cents,
        active ?? this.active,
      );

  /// Absolute pitch of this degree above the root, in cents.
  ///
  /// This is the value a tuning theorist would quote: 0 for the tonic, 350
  /// for the Rast third, 386.3 for a just major third.
  double get centsFromRoot => semitone * 100.0 + cents;

  /// True when the degree sounds exactly as an equal-tempered piano would.
  bool get isTempered => cents == 0.0;

  @override
  String toString() => 'GFScaleDegree($semitone'
      '${cents == 0 ? '' : ', ${cents.toStringAsFixed(1)}c'}'
      '${active ? '' : ', muted'})';
}

/// How a [GFScale]'s degrees are laid out across the keyboard.
enum GFScaleMapping {
  /// Each degree keeps its own keyboard key, and the pattern repeats every
  /// 12 keys — the familiar layout.
  ///
  /// A seven-note scale therefore leaves five keys unused; those are the keys
  /// the Xen module greys out and snaps away from. This is right for anything
  /// that a Western musician would still call "a scale in a key": modes,
  /// maqamat, ragas, historical temperaments, pelog.
  pitchClass,

  /// Successive degrees occupy successive keys, and the pattern repeats every
  /// [GFScale.degrees].length keys.
  ///
  /// Needed when the scale's steps are not multiples of a semitone and there
  /// is no sensible key to assign each degree to — the Javanese slendro, whose
  /// five roughly-equal steps of 240 cents cannot be spelled on a piano at
  /// all. The cost is that the keyboard's own octave no longer matches the
  /// scale's: with a five-note linear scale, five keys make one period.
  ///
  /// Every key belongs to the scale, so there is nothing to snap or grey out.
  linear,
}

/// Cultural / theoretical family a [GFScale] belongs to.
///
/// Purely an organisational axis — it drives the tab grouping in the Xen
/// module's scale grid and carries no musical behaviour.
enum GFScaleFamily {
  /// Western modes, pentatonics and blues — all plain 12-TET.
  western,

  /// Arabic maqamat and Turkish makamlar. Note that several (Hijaz, Kurd,
  /// Nahawand) are fully equal-tempered: the family is a modal system, not a
  /// synonym for "microtonal".
  maqam,

  /// North Indian ragas, tuned from the just-intonation shruti values.
  raga,

  /// Chinese, Japanese and Korean scales.
  farEast,

  /// Javanese and Balinese gamelan tunings.
  gamelan,

  /// Scales from the Celtic instrumental traditions.
  celtic,

  /// Equal divisions of the octave (or of another interval), harmonic-series
  /// scales, and other constructed tunings that belong to no tradition.
  ///
  /// Most of these divide the octave into more than twelve steps, so they use
  /// [GFScaleMapping.linear] and spread one octave across more than twelve
  /// keys.
  experimental,

  /// Scales the player built or imported themselves.
  ///
  /// The only family whose members are not compile-time constants, and the
  /// only one exempt from the catalogue's "a degree stays near its key"
  /// invariant — pulling a key far from its nominal pitch is the whole point
  /// of a hand-made scale.
  custom,

  /// Full twelve-note tunings of the keyboard itself — just intonation,
  /// Pythagorean, meantone, well temperaments. Unlike the other families
  /// these define every key, so nothing is ever out of scale.
  temperament,
}

/// A scale defined as a set of degrees, each with its own tuning.
///
/// This is the single data structure behind both halves of the Xen module:
///
///   - [pitchClassesFor] feeds the **snap** stage and the greyed-out keys on
///     the virtual piano — it answers "which keys belong to this scale?".
///   - [tuningOffsetsFor] feeds the **tune** stage — a 128-entry table of cent
///     deviations handed to FluidSynth's MIDI Tuning Standard support, which
///     answers "and what does each of those keys actually sound like?".
///
/// A scale is root-agnostic: the degrees are relative to a tonic that the
/// player picks at performance time, so both accessors take a root.
class GFScale {
  /// Stable identifier, also the stem of the localisation key.
  ///
  /// The app looks up `scaleName<id>` in the ARB files and falls back to
  /// [name] when no translation exists. Never change an id once shipped —
  /// saved projects store it verbatim.
  final String id;

  /// Canonical name in its usual transliteration ("Rast", "Hirajoshi").
  ///
  /// Used as the fallback label and in debug output. Proper nouns are meant to
  /// stay untranslated; only the generic Western names ("Major", "Blues") get
  /// an ARB translation.
  final String name;

  /// Which tab of the scale grid this scale appears under.
  final GFScaleFamily family;

  /// The degrees, in ascending order starting at the tonic.
  ///
  /// The first degree is always the tonic itself (semitone 0, 0 cents).
  final List<GFScaleDegree> degrees;

  /// How [degrees] are spread across the keyboard.
  final GFScaleMapping mapping;

  /// Size of one repetition of the scale, in cents.
  ///
  /// 1200 (a plain octave) for everything except non-octave tunings. Only
  /// consulted for [GFScaleMapping.linear] scales; pitch-class scales repeat
  /// every 12 keys by definition.
  final double periodCents;

  /// A short note on where the tuning numbers come from.
  ///
  /// Shown in the module's info panel. Matters more than it looks: several of
  /// these traditions have no single authoritative tuning, and saying so is
  /// more honest than presenting an average as a standard.
  final String provenance;

  const GFScale({
    required this.id,
    required this.name,
    required this.family,
    required this.degrees,
    required this.provenance,
    this.mapping = GFScaleMapping.pitchClass,
    this.periodCents = 1200.0,
  });

  // ── Properties ─────────────────────────────────────────────────────────────

  /// Number of degrees per repetition (5 for a pentatonic, 7 for a maqam, 12
  /// for a temperament).
  int get degreeCount => degrees.length;

  /// True when at least one degree sounds different from an equal-tempered
  /// piano — i.e. when the **tune** stage has anything to do.
  ///
  /// Used to badge the scale button in the UI, so a player can tell at a
  /// glance that Hijaz is a 12-TET mode while Rast is not.
  bool get isMicrotonal => degrees.any((d) => !d.isTempered);

  /// Number of keyboard keys one repetition of the scale spans.
  ///
  /// 12 for pitch-class scales; the degree count for linear ones.
  int get keysPerPeriod =>
      mapping == GFScaleMapping.pitchClass ? 12 : degrees.length;

  /// True when every key of the keyboard belongs to the scale, so there is
  /// nothing to snap and nothing to grey out.
  ///
  /// Holds for temperaments (all twelve degrees present) and for every linear
  /// scale (successive keys are successive degrees by construction).
  bool get coversEveryKey =>
      mapping == GFScaleMapping.linear || activeDegreeCount >= 12;

  /// How many degrees the snap stage can land on.
  int get activeDegreeCount => degrees.where((d) => d.active).length;

  /// True when at least one degree is muted — playable and tuned, but not a
  /// snap destination.
  bool get hasMutedDegrees => degrees.any((d) => !d.active);

  // ── Snapping / display ─────────────────────────────────────────────────────

  /// The pitch classes (0 = C … 11 = B) this scale allows when rooted on
  /// [rootPc], or `null` when every key is in scale.
  ///
  /// A `null` result is the same "no constraint" signal the virtual piano and
  /// Jam Mode already use for `validPitchClasses`, so it can be handed
  /// straight through to either.
  Set<int>? pitchClassesFor(int rootPc) {
    if (coversEveryKey) return null;
    final root = _wrap12(rootPc);
    // Muted degrees are deliberately absent: the key stays playable and
    // retuned, but the snap stage will not pull anything onto it.
    return degrees
        .where((d) => d.active)
        .map((d) => (root + d.semitone) % 12)
        .toSet();
  }

  /// Cent deviations keyed by pitch class, for drawing "↑12¢" style markers
  /// on the virtual piano. Empty for linear scales, where a per-pitch-class
  /// value is meaningless because the same key means different degrees in
  /// different registers.
  Map<int, double> centsByPitchClassFor(int rootPc) {
    if (mapping == GFScaleMapping.linear) return const {};
    final root = _wrap12(rootPc);
    return {
      for (final d in degrees)
        if (!d.isTempered) (root + d.semitone) % 12: d.cents,
    };
  }

  // ── Tuning table ───────────────────────────────────────────────────────────

  /// Builds the 128-entry cent-deviation table for this scale rooted on
  /// [rootPc], ready to hand to `AudioInputFFI.keyboardSetKeyTuning`.
  ///
  /// Entry *k* is how far MIDI key *k* should sound from its 12-TET pitch.
  /// Keys that do not belong to the scale keep a deviation of 0 — they stay
  /// chromatic, so that switching the **snap** stage off leaves the player a
  /// usable (if unidiomatic) chromatic keyboard rather than a scrambled one.
  ///
  /// Deviations are clamped so the resulting absolute pitch stays inside
  /// FluidSynth's valid 0–12700 cent window; only the extreme registers of a
  /// wide linear scale can reach that limit.
  Float64List tuningOffsetsFor(int rootPc) {
    final table = Float64List(128);
    final root = _wrap12(rootPc);
    if (mapping == GFScaleMapping.pitchClass) {
      _fillPitchClassTable(table, root);
    } else {
      _fillLinearTable(table, root);
    }
    return table;
  }

  /// Pitch-class layout: one deviation per key of the octave, repeated.
  void _fillPitchClassTable(Float64List table, int root) {
    // Pre-resolve the twelve possible deviations once, then stamp the pattern
    // across the keyboard — cheaper and clearer than searching the degree
    // list 128 times.
    final byPc = List<double>.filled(12, 0.0);
    for (final d in degrees) {
      byPc[d.semitone % 12] = d.cents;
    }
    for (var key = 0; key < 128; key++) {
      final offsetFromRoot = _wrap12(key - root);
      table[key] = _clampToAudibleRange(key, byPc[offsetFromRoot]);
    }
  }

  /// Linear layout: successive keys walk successive degrees, and each
  /// completed period adds the gap between the scale's period and the
  /// keyboard span it consumes.
  ///
  /// For a five-note slendro the scale climbs 1200 cents while the keyboard
  /// only climbs 500, so every period adds another 700 cents of stretch.
  void _fillLinearTable(Float64List table, int root) {
    final n = degrees.length;
    final stretchPerPeriod = periodCents - n * 100.0;
    // The tonic is anchored on the middle-octave key of the chosen root, so a
    // linear scale always starts sounding in tune with the rest of the rack.
    final rootKey = 60 + root;
    for (var key = 0; key < 128; key++) {
      final rel = key - rootKey;
      // Floored division/modulo: `rel` is negative below the anchor, and
      // Dart's `%` on ints already returns a non-negative result there, but
      // `~/` truncates towards zero — so derive the period index from the
      // remainder instead of dividing directly.
      final index = rel % n;
      final period = (rel - index) ~/ n;
      final offset = degrees[index].cents + period * stretchPerPeriod;
      table[key] = _clampToAudibleRange(key, offset);
    }
  }

  /// Keeps `key * 100 + offset` inside FluidSynth's 0–12700 cent window.
  double _clampToAudibleRange(int key, double offset) {
    final absolute = key * 100.0 + offset;
    if (absolute < 0.0) return -key * 100.0;
    if (absolute > 12700.0) return 12700.0 - key * 100.0;
    return offset;
  }

  /// Non-negative modulo 12 — `%` on a negative int already behaves this way
  /// in Dart, but stating it once keeps the call sites readable.
  static int _wrap12(int v) => v % 12;

  // ── Serialisation ──────────────────────────────────────────────────────────

  /// Serialises this scale, for a custom scale stored in a project file or in
  /// the user's scale library.
  ///
  /// Built-in scales are never serialised this way — a saved project only
  /// stores their [id] and looks them up again — so the format only has to be
  /// stable for user-made scales.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'family': family.name,
        'mapping': mapping.name,
        'periodCents': periodCents,
        'provenance': provenance,
        'degrees': [
          for (final d in degrees)
            {
              'semitone': d.semitone,
              'cents': d.cents,
              // Omitted when true so hand-written files stay readable and
              // every pre-existing payload keeps meaning "active".
              if (!d.active) 'active': false,
            },
        ],
      };

  /// Rebuilds a scale from [json], or returns null when the payload is
  /// unusable.
  ///
  /// Returns null rather than throwing: a scale file may have been hand-edited
  /// or written by a newer build, and the right response is to skip that one
  /// scale, not to fail loading the project or the whole library.
  static GFScale? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;

    final rawDegrees = json['degrees'];
    if (rawDegrees is! List || rawDegrees.isEmpty) return null;

    final degrees = <GFScaleDegree>[];
    for (final entry in rawDegrees) {
      if (entry is! Map) return null;
      final semitone = (entry['semitone'] as num?)?.toInt();
      final cents = (entry['cents'] as num?)?.toDouble();
      if (semitone == null || cents == null) return null;
      degrees.add(GFScaleDegree(semitone, cents, entry['active'] as bool? ?? true));
    }

    return GFScale(
      id: id,
      name: name,
      family: GFScaleFamily.values.firstWhere(
        (f) => f.name == json['family'],
        orElse: () => GFScaleFamily.custom,
      ),
      mapping: GFScaleMapping.values.firstWhere(
        (m) => m.name == json['mapping'],
        orElse: () => GFScaleMapping.pitchClass,
      ),
      periodCents: (json['periodCents'] as num?)?.toDouble() ?? 1200.0,
      provenance: json['provenance'] as String? ?? '',
      degrees: degrees,
    );
  }

  @override
  String toString() => 'GFScale($id, ${degrees.length} degrees'
      '${isMicrotonal ? ', microtonal' : ''})';
}
