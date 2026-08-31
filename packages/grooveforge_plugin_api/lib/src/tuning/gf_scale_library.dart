import 'gf_scale.dart';

/// The built-in catalogue of scales and tunings shipped with the Xen module.
///
/// Every entry is a `static const`, so the whole catalogue is compile-time
/// data with no initialisation cost and no risk of a scale being mutated at
/// runtime. [all] is the ordered list the UI walks to build its scale grid.
///
/// **On the cent values.** Three different kinds of number appear below and
/// they should not be confused:
///
///   - **Exactly 0** — the degree is a plain equal-tempered key. Whole
///     families are like this (the Western modes, several maqamat), and that
///     is a musical fact, not a placeholder.
///   - **Round quarter-tones (±50)** — the 24-tone idealisation used to notate
///     Arabic practice. Real performers place these notes by ear and by
///     region; ±50 is the written convention, not a measurement.
///   - **Irrational-looking values (−13.686, +3.910, −15.094)** — derived from
///     frequency ratios or from an equal division of the octave. −13.686 is
///     the just major third 5/4, +3.910 the Pythagorean whole tone 9/8,
///     −15.094 the 17-comma third of Turkish theory (53 equal divisions).
///     They are given to three decimals because a rounding error of a cent is
///     audible as beating when two such notes are held together.
///
/// Where a tradition has no single authoritative tuning — gamelan above all —
/// the [GFScale.provenance] field says so rather than dressing an average up
/// as a standard.
class GFScaleLibrary {
  GFScaleLibrary._();

  // ═══ Western — plain 12-TET ════════════════════════════════════════════════
  //
  // Every cents value here is 0: these scales choose which keys to use, not
  // how those keys sound. They exist in the catalogue so that the Xen module's
  // snap stage alone reproduces everything Jam Mode already does.

  /// Ionian — the major scale.
  static const major = GFScale(
    id: 'major',
    name: 'Major',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(11),
    ],
  );

  /// Aeolian — the natural minor scale.
  static const naturalMinor = GFScale(
    id: 'naturalMinor',
    name: 'Natural Minor',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(10),
    ],
  );

  /// Natural minor with a raised leading tone — the augmented second between
  /// the 6th and 7th degrees is what gives it its characteristic pull.
  static const harmonicMinor = GFScale(
    id: 'harmonicMinor',
    name: 'Harmonic Minor',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(11),
    ],
  );

  /// Ascending melodic minor (jazz minor) — raised 6th and 7th.
  static const melodicMinor = GFScale(
    id: 'melodicMinor',
    name: 'Melodic Minor',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(11),
    ],
  );

  /// Major pentatonic — the major scale minus its two semitone steps.
  static const majorPentatonic = GFScale(
    id: 'majorPentatonic',
    name: 'Major Pentatonic',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4), GFScaleDegree(7),
      GFScaleDegree(9),
    ],
  );

  /// Minor pentatonic — the backbone of blues and rock lead playing.
  static const minorPentatonic = GFScale(
    id: 'minorPentatonic',
    name: 'Minor Pentatonic',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(3), GFScaleDegree(5), GFScaleDegree(7),
      GFScaleDegree(10),
    ],
  );

  /// Minor pentatonic plus the flat fifth — the "blue note" hexatonic.
  static const blues = GFScale(
    id: 'blues',
    name: 'Blues',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(3), GFScaleDegree(5), GFScaleDegree(6),
      GFScaleDegree(7), GFScaleDegree(10),
    ],
  );

  /// Major pentatonic with an added minor third — the major-blues hexatonic
  /// GrooveForge's Jam Mode has always used for its "Rock" setting.
  static const rock = GFScale(
    id: 'rock',
    name: 'Rock',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(4),
      GFScaleDegree(7), GFScaleDegree(9),
    ],
  );

  /// Dorian — minor with a natural 6th.
  static const dorian = GFScale(
    id: 'dorian',
    name: 'Dorian',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(10),
    ],
  );

  /// Phrygian — minor with a flat 2nd.
  static const phrygian = GFScale(
    id: 'phrygian',
    name: 'Phrygian',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(10),
    ],
  );

  /// Lydian — major with a raised 4th.
  static const lydian = GFScale(
    id: 'lydian',
    name: 'Lydian',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4), GFScaleDegree(6),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(11),
    ],
  );

  /// Mixolydian — major with a flat 7th.
  static const mixolydian = GFScale(
    id: 'mixolydian',
    name: 'Mixolydian',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(10),
    ],
  );

  /// Locrian — the diminished mode.
  static const locrian = GFScale(
    id: 'locrian',
    name: 'Locrian',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(6), GFScaleDegree(8), GFScaleDegree(10),
    ],
  );

  /// Phrygian dominant — the 5th mode of harmonic minor. GrooveForge's Jam
  /// Mode ships this as "Oriental"; it is the equal-tempered shorthand a
  /// Western ear reaches for when imitating maqam Hijaz.
  static const phrygianDominant = GFScale(
    id: 'phrygianDominant',
    name: 'Phrygian Dominant',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(4), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(10),
    ],
  );

  /// Whole-tone — six equal steps, no leading tone anywhere.
  static const wholeTone = GFScale(
    id: 'wholeTone',
    name: 'Whole Tone',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4), GFScaleDegree(6),
      GFScaleDegree(8), GFScaleDegree(10),
    ],
  );

  /// Half-whole diminished — the octatonic scale, matching the interval set
  /// Jam Mode already uses for its "Diminished" setting.
  static const diminished = GFScale(
    id: 'diminished',
    name: 'Diminished',
    family: GFScaleFamily.western,
    provenance: '12-TET',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(3), GFScaleDegree(4),
      GFScaleDegree(6), GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(10),
    ],
  );

  // ═══ Maqam — Arabic and Turkish ════════════════════════════════════════════
  //
  // The Arabic entries use the 24-tone convention: a "half-flat" degree sits
  // 50 cents below the equal-tempered key it is written on. That convention
  // notates the practice; it does not measure it. A Cairo ensemble and an
  // Aleppo ensemble will place the Rast third differently, and both will be
  // somewhere near, but rarely exactly on, 350 cents.
  //
  // Note how many maqamat below have no detuning at all. A maqam is a modal
  // system — a set of tetrachords plus a typical melodic path — and
  // quarter-tones are one feature of some of them, not the definition.

  /// Maqam Rast — the central maqam of Arabic music. Half-flat 3rd and 7th.
  static const maqamRast = GFScale(
    id: 'maqamRast',
    name: 'Rast',
    family: GFScaleFamily.maqam,
    provenance: '24-tone Arabic convention (half-flats at −50 cents)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4, -50.0),
      GFScaleDegree(5), GFScaleDegree(7), GFScaleDegree(9),
      GFScaleDegree(11, -50.0),
    ],
  );

  /// Maqam Bayati — half-flat 2nd. The everyday maqam of Levantine song.
  static const maqamBayati = GFScale(
    id: 'maqamBayati',
    name: 'Bayati',
    family: GFScaleFamily.maqam,
    provenance: '24-tone Arabic convention (half-flats at −50 cents)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, -50.0), GFScaleDegree(3),
      GFScaleDegree(5), GFScaleDegree(7), GFScaleDegree(8),
      GFScaleDegree(10),
    ],
  );

  /// Maqam Hijaz — the augmented second between the 2nd and 3rd degrees.
  /// Fully equal-tempered: nothing here needs retuning.
  static const maqamHijaz = GFScale(
    id: 'maqamHijaz',
    name: 'Hijaz',
    family: GFScaleFamily.maqam,
    provenance: 'Equal-tempered maqam — no quarter-tones',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(4), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(10),
    ],
  );

  /// Maqam Saba — half-flat 2nd and a diminished 4th, giving it the narrow,
  /// unresolved character it is known for.
  static const maqamSaba = GFScale(
    id: 'maqamSaba',
    name: 'Saba',
    family: GFScaleFamily.maqam,
    provenance: '24-tone Arabic convention (half-flats at −50 cents)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, -50.0), GFScaleDegree(3),
      GFScaleDegree(4), GFScaleDegree(7), GFScaleDegree(8),
      GFScaleDegree(10),
    ],
  );

  /// Maqam Nahawand — interval-for-interval the Western natural minor.
  static const maqamNahawand = GFScale(
    id: 'maqamNahawand',
    name: 'Nahawand',
    family: GFScaleFamily.maqam,
    provenance: 'Equal-tempered maqam — no quarter-tones',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(10),
    ],
  );

  /// Maqam Kurd — interval-for-interval the Phrygian mode.
  static const maqamKurd = GFScale(
    id: 'maqamKurd',
    name: 'Kurd',
    family: GFScaleFamily.maqam,
    provenance: 'Equal-tempered maqam — no quarter-tones',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(10),
    ],
  );

  /// Maqam Ajam — interval-for-interval the major scale.
  static const maqamAjam = GFScale(
    id: 'maqamAjam',
    name: 'Ajam',
    family: GFScaleFamily.maqam,
    provenance: 'Equal-tempered maqam — no quarter-tones',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(11),
    ],
  );

  /// Makam Rast in the Turkish Arel-Ezgi-Uzdilek system, which divides the
  /// octave into 53 Holdrian commas of 22.641 cents each.
  ///
  /// The degree sizes are 9, 8, 5, 9, 9, 8, 5 commas, which lands almost
  /// exactly on Pythagorean intervals — a very different sound from the
  /// Arabic Rast above, and the reason both are worth having side by side.
  static const makamRastTurkish = GFScale(
    id: 'makamRastTurkish',
    name: 'Rast (Turkish)',
    family: GFScaleFamily.maqam,
    provenance: 'Arel-Ezgi-Uzdilek, 53 Holdrian commas of 22.641 cents',
    degrees: [
      GFScaleDegree(0),
      GFScaleDegree(2, 3.774),    //  9 commas = 203.774
      GFScaleDegree(4, -15.094),  // 17 commas = 384.906
      GFScaleDegree(5, -1.887),   // 22 commas = 498.113
      GFScaleDegree(7, 1.887),    // 31 commas = 701.887
      GFScaleDegree(9, 5.660),    // 40 commas = 905.660
      GFScaleDegree(11, -13.208), // 48 commas = 1086.792
    ],
  );

  // ═══ Raga — North Indian, just intonation ═════════════════════════════════
  //
  // Tuned from the shruti ratios rather than from equal temperament. The
  // recurring values below are the same handful of intervals throughout:
  //
  //   komal re   256/243 →   90.225   (semitone 1, −9.775)
  //   shuddha re     9/8 →  203.910   (semitone 2, +3.910)
  //   komal ga     32/27 →  294.135   (semitone 3, −5.865)
  //   shuddha ga     5/4 →  386.314   (semitone 4, −13.686)
  //   shuddha ma     4/3 →  498.045   (semitone 5, −1.955)
  //   tivra ma     45/32 →  590.224   (semitone 6, −9.776)
  //   pancham        3/2 →  701.955   (semitone 7, +1.955)
  //   komal dha   128/81 →  792.180   (semitone 8, −7.820)
  //   shuddha dha  27/16 →  905.865   (semitone 9, +5.865)
  //   komal ni      16/9 →  996.090   (semitone 10, −3.910)
  //   shuddha ni    15/8 → 1088.269   (semitone 11, −11.731)
  //
  // These are the ascending (aroha) forms only. A raga is not a scale — it
  // also carries a descending form, characteristic phrases and ornaments that
  // no tuning table can express. What the Xen module gives you is the
  // intonation, which is the part a keyboard can honestly reproduce.

  /// Raga Bhairav — a morning raga; komal re and komal dha.
  static const ragaBhairav = GFScale(
    id: 'ragaBhairav',
    name: 'Bhairav',
    family: GFScaleFamily.raga,
    provenance: 'Just intonation from the shruti ratios (ascending form)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -9.775), GFScaleDegree(4, -13.686),
      GFScaleDegree(5, -1.955), GFScaleDegree(7, 1.955),
      GFScaleDegree(8, -7.820), GFScaleDegree(11, -11.731),
    ],
  );

  /// Raga Yaman — an evening raga built on tivra ma; the Lydian of India.
  static const ragaYaman = GFScale(
    id: 'ragaYaman',
    name: 'Yaman',
    family: GFScaleFamily.raga,
    provenance: 'Just intonation from the shruti ratios (ascending form)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(4, -13.686),
      GFScaleDegree(6, -9.776), GFScaleDegree(7, 1.955),
      GFScaleDegree(9, 5.865), GFScaleDegree(11, -11.731),
    ],
  );

  /// Raga Bhairavi — all four komal degrees; the Phrygian of India.
  static const ragaBhairavi = GFScale(
    id: 'ragaBhairavi',
    name: 'Bhairavi',
    family: GFScaleFamily.raga,
    provenance: 'Just intonation from the shruti ratios (ascending form)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -9.775), GFScaleDegree(3, -5.865),
      GFScaleDegree(5, -1.955), GFScaleDegree(7, 1.955),
      GFScaleDegree(8, -7.820), GFScaleDegree(10, -3.910),
    ],
  );

  /// Raga Todi — komal re, komal ga, tivra ma, komal dha.
  static const ragaTodi = GFScale(
    id: 'ragaTodi',
    name: 'Todi',
    family: GFScaleFamily.raga,
    provenance: 'Just intonation from the shruti ratios (ascending form)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -9.775), GFScaleDegree(3, -5.865),
      GFScaleDegree(6, -9.776), GFScaleDegree(7, 1.955),
      GFScaleDegree(8, -7.820), GFScaleDegree(11, -11.731),
    ],
  );

  /// Raga Marwa — komal re over a major third and tivra ma, with pancham
  /// typically omitted in performance.
  static const ragaMarwa = GFScale(
    id: 'ragaMarwa',
    name: 'Marwa',
    family: GFScaleFamily.raga,
    provenance: 'Just intonation from the shruti ratios (ascending form)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -9.775), GFScaleDegree(4, -13.686),
      GFScaleDegree(6, -9.776), GFScaleDegree(7, 1.955),
      GFScaleDegree(9, 5.865), GFScaleDegree(11, -11.731),
    ],
  );

  /// Raga Kafi — the Dorian of India, in just intonation.
  static const ragaKafi = GFScale(
    id: 'ragaKafi',
    name: 'Kafi',
    family: GFScaleFamily.raga,
    provenance: 'Just intonation from the shruti ratios (ascending form)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(3, -5.865),
      GFScaleDegree(5, -1.955), GFScaleDegree(7, 1.955),
      GFScaleDegree(9, 5.865), GFScaleDegree(10, -3.910),
    ],
  );

  // ═══ Far East — China, Japan, Korea ═══════════════════════════════════════

  /// Chinese gong pentatonic tuned by the sanfen sunyi (三分損益) cycle of
  /// fifths — the Pythagorean pentatonic, and the oldest documented tuning
  /// procedure in the catalogue.
  static const gongPentatonic = GFScale(
    id: 'gongPentatonic',
    name: 'Gong',
    family: GFScaleFamily.farEast,
    provenance: 'Sanfen sunyi cycle of fifths (Pythagorean)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(4, 7.820),
      GFScaleDegree(7, 1.955), GFScaleDegree(9, 5.865),
    ],
  );

  /// Hirajōshi — the standard koto tuning, in its usual Western notation.
  ///
  /// Left equal-tempered on purpose: koto tuning is set by moving the bridges
  /// and varies by piece and school, so there is no single set of deviations
  /// that would be more truthful than none.
  static const hirajoshi = GFScale(
    id: 'hirajoshi',
    name: 'Hirajoshi',
    family: GFScaleFamily.farEast,
    provenance: 'Koto tuning, equal-tempered notation',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(7),
      GFScaleDegree(8),
    ],
  );

  /// In sen — the shakuhachi / shamisen pentatonic, semitone above the tonic.
  static const inSen = GFScale(
    id: 'inSen',
    name: 'In Sen',
    family: GFScaleFamily.farEast,
    provenance: 'Japanese in scale, equal-tempered notation',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(5), GFScaleDegree(7),
      GFScaleDegree(10),
    ],
  );

  /// Yo — the anhemitonic Japanese pentatonic of folk song and gagaku.
  static const yo = GFScale(
    id: 'yo',
    name: 'Yo',
    family: GFScaleFamily.farEast,
    provenance: 'Japanese yo scale, equal-tempered notation',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(5), GFScaleDegree(7),
      GFScaleDegree(9),
    ],
  );

  /// Pyeongjo — the "calm" Korean court mode, tuned by fifths like the
  /// Chinese system it descends from.
  static const pyeongjo = GFScale(
    id: 'pyeongjo',
    name: 'Pyeongjo',
    family: GFScaleFamily.farEast,
    provenance: 'Korean jeongak, Pythagorean cycle of fifths',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(5, -1.955),
      GFScaleDegree(7, 1.955), GFScaleDegree(9, 5.865),
    ],
  );

  /// Gyemyeonjo — the plaintive Korean counterpart to [pyeongjo].
  static const gyemyeonjo = GFScale(
    id: 'gyemyeonjo',
    name: 'Gyemyeonjo',
    family: GFScaleFamily.farEast,
    provenance: 'Korean jeongak, Pythagorean cycle of fifths',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(3, -5.865), GFScaleDegree(5, -1.955),
      GFScaleDegree(7, 1.955), GFScaleDegree(10, -3.910),
    ],
  );

  // ═══ Celtic ═══════════════════════════════════════════════════════════════

  /// The Great Highland Bagpipe scale.
  ///
  /// Famously not equal-tempered: the chanter is bored to a near-just
  /// mixolydian, which is why a pipe band sounds in tune with itself and
  /// distinctly out of tune with a piano. The 3rd is a just 5/4 and the flat
  /// 7th a just 16/9 — both audibly low against equal temperament.
  static const highlandPipe = GFScale(
    id: 'highlandPipe',
    name: 'Highland Pipe',
    family: GFScaleFamily.celtic,
    provenance: 'Near-just chanter scale (9/8, 5/4, 4/3, 3/2, 27/16, 16/9)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(4, -13.686),
      GFScaleDegree(5, -1.955), GFScaleDegree(7, 1.955),
      GFScaleDegree(9, 5.865), GFScaleDegree(10, -3.910),
    ],
  );

  // ═══ Gamelan ══════════════════════════════════════════════════════════════
  //
  // Nothing in this family is standardised, and that is not a gap in the data:
  // each gamelan is tuned as a set, by ear, and two gamelans in the same
  // village will differ by tens of cents. The values below are averages and
  // should be read as "a plausible gamelan", never as "the" tuning.

  /// Slendro — five roughly equal steps, modelled here as an exact five-fold
  /// division of the octave.
  ///
  /// The only scale in the catalogue that uses [GFScaleMapping.linear]: a
  /// 240-cent step lands nowhere near any piano key, so the degrees are laid
  /// out one per successive key instead. Five keys therefore make one octave,
  /// and the keyboard's own black/white pattern stops meaning anything.
  static const slendro = GFScale(
    id: 'slendro',
    name: 'Slendro',
    family: GFScaleFamily.gamelan,
    provenance: 'Idealised 5-fold equal division; real gamelans vary widely',
    mapping: GFScaleMapping.linear,
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, 140.0), GFScaleDegree(2, 280.0),
      GFScaleDegree(3, 420.0), GFScaleDegree(4, 560.0),
    ],
  );

  /// Pelog — seven uneven steps. Kept on the pitch-class layout because its
  /// degrees, unlike slendro's, do fall near enough to keyboard keys to stay
  /// playable.
  static const pelog = GFScale(
    id: 'pelog',
    name: 'Pelog',
    family: GFScaleFamily.gamelan,
    provenance: 'Averaged Javanese pelog; every gamelan differs',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, 20.0), GFScaleDegree(3, -30.0),
      GFScaleDegree(5, 40.0), GFScaleDegree(7, -30.0),
      GFScaleDegree(8, -15.0), GFScaleDegree(10, -50.0),
    ],
  );

  // ═══ Temperaments — all twelve keys retuned ═══════════════════════════════
  //
  // These differ from every family above: they define all twelve degrees, so
  // no key is ever out of scale and the snap stage has nothing to do. Select
  // one to retune the whole keyboard and keep playing chromatically.

  /// Five-limit just intonation on the tonic — beatless thirds and fifths in
  /// the home key, and progressively worse ones as you modulate away from it.
  static const justIntonation = GFScale(
    id: 'justIntonation',
    name: 'Just Intonation',
    family: GFScaleFamily.temperament,
    provenance: 'Five-limit ratios: 16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, '
        '8/5, 5/3, 9/5, 15/8',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, 11.731), GFScaleDegree(2, 3.910),
      GFScaleDegree(3, 15.641), GFScaleDegree(4, -13.686),
      GFScaleDegree(5, -1.955), GFScaleDegree(6, -9.776),
      GFScaleDegree(7, 1.955), GFScaleDegree(8, 13.686),
      GFScaleDegree(9, -15.641), GFScaleDegree(10, 17.596),
      GFScaleDegree(11, -11.731),
    ],
  );

  /// Pythagorean tuning — twelve pure fifths chained from E flat to G sharp,
  /// leaving the wolf fifth between G sharp and E flat.
  static const pythagorean = GFScale(
    id: 'pythagorean',
    name: 'Pythagorean',
    family: GFScaleFamily.temperament,
    provenance: 'Chain of pure 3/2 fifths, E♭–G♯; wolf between G♯ and E♭',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, 13.685), GFScaleDegree(2, 3.910),
      GFScaleDegree(3, -5.865), GFScaleDegree(4, 7.820),
      GFScaleDegree(5, -1.955), GFScaleDegree(6, 11.730),
      GFScaleDegree(7, 1.955), GFScaleDegree(8, 15.640),
      GFScaleDegree(9, 5.865), GFScaleDegree(10, -3.910),
      GFScaleDegree(11, 9.775),
    ],
  );

  /// Quarter-comma meantone — the Renaissance keyboard tuning. Every major
  /// third is pure; the price is the badly out-of-tune wolf fifth on G sharp.
  static const meantone = GFScale(
    id: 'meantone',
    name: 'Quarter-comma Meantone',
    family: GFScaleFamily.temperament,
    provenance: 'Fifths narrowed by 1/4 syntonic comma (696.578 cents)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -23.951), GFScaleDegree(2, -6.843),
      GFScaleDegree(3, 10.265), GFScaleDegree(4, -13.686),
      GFScaleDegree(5, 3.422), GFScaleDegree(6, -20.529),
      GFScaleDegree(7, -3.422), GFScaleDegree(8, -27.373),
      GFScaleDegree(9, -10.265), GFScaleDegree(10, 6.843),
      GFScaleDegree(11, -17.108),
    ],
  );

  /// Werckmeister III — the best-known Baroque well temperament. Every key is
  /// playable, and each one has its own colour, which is the point.
  static const werckmeisterIII = GFScale(
    id: 'werckmeisterIII',
    name: 'Werckmeister III',
    family: GFScaleFamily.temperament,
    provenance: 'Werckmeister 1691, four fifths narrowed by 1/4 Pythagorean '
        'comma',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -9.775), GFScaleDegree(2, -7.820),
      GFScaleDegree(3, -5.865), GFScaleDegree(4, -9.775),
      GFScaleDegree(5, -1.955), GFScaleDegree(6, -11.730),
      GFScaleDegree(7, -3.910), GFScaleDegree(8, -7.820),
      GFScaleDegree(9, -11.730), GFScaleDegree(10, -3.910),
      GFScaleDegree(11, -7.820),
    ],
  );

  // ═══ Catalogue ════════════════════════════════════════════════════════════

  /// Every built-in scale, in the order the UI presents them.
  ///
  /// Grouped by family so the scale grid can be built by a single pass with
  /// a tab break wherever [GFScale.family] changes.
  static const List<GFScale> all = [
    // Western
    major, naturalMinor, harmonicMinor, melodicMinor,
    majorPentatonic, minorPentatonic, blues, rock,
    dorian, phrygian, lydian, mixolydian, locrian,
    phrygianDominant, wholeTone, diminished,
    // Maqam
    maqamRast, maqamBayati, maqamHijaz, maqamSaba,
    maqamNahawand, maqamKurd, maqamAjam, makamRastTurkish,
    // Raga
    ragaBhairav, ragaYaman, ragaBhairavi, ragaTodi, ragaMarwa, ragaKafi,
    // Far East
    gongPentatonic, hirajoshi, inSen, yo, pyeongjo, gyemyeonjo,
    // Celtic
    highlandPipe,
    // Gamelan
    slendro, pelog,
    // Temperaments
    justIntonation, pythagorean, meantone, werckmeisterIII,
  ];

  /// The scales of one [family], in catalogue order.
  static List<GFScale> byFamily(GFScaleFamily family) =>
      all.where((s) => s.family == family).toList(growable: false);

  /// Looks a scale up by its [GFScale.id], or returns null when unknown.
  ///
  /// Returning null rather than throwing matters for project loading: a `.gf`
  /// file saved by a newer build may name a scale this build has never heard
  /// of, and the right response is to fall back to a default, not to refuse
  /// the whole project.
  static GFScale? byId(String id) {
    for (final scale in all) {
      if (scale.id == id) return scale;
    }
    return null;
  }

  /// The default scale used when none is selected or a saved id is unknown.
  static const GFScale fallback = major;
}
