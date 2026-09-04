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


  /// Maqam Sikah — built on the half-flat third degree itself, so the tonic is
  /// a quarter-tone away from anything a piano can play.
  static const maqamSikah = GFScale(
    id: 'maqamSikah',
    name: 'Sikah',
    family: GFScaleFamily.maqam,
    provenance: '24-tone Arabic convention (half-flats at −50 cents)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, -50.0), GFScaleDegree(4, -50.0),
      GFScaleDegree(6, -50.0), GFScaleDegree(7), GFScaleDegree(9, -50.0),
      GFScaleDegree(11, -50.0),
    ],
  );

  /// Maqam Huzam — Sikah's trichord capped by a Hijaz tetrachord.
  static const maqamHuzam = GFScale(
    id: 'maqamHuzam',
    name: 'Huzam',
    family: GFScaleFamily.maqam,
    provenance: '24-tone Arabic convention (half-flats at −50 cents)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, -50.0), GFScaleDegree(3),
      GFScaleDegree(4), GFScaleDegree(7), GFScaleDegree(8),
      GFScaleDegree(11, -50.0),
    ],
  );

  /// Maqam Hijazkar — the double harmonic scale: two augmented seconds,
  /// symmetric around the fifth. Equal-tempered, and instantly recognisable.
  static const maqamHijazkar = GFScale(
    id: 'maqamHijazkar',
    name: 'Hijazkar',
    family: GFScaleFamily.maqam,
    provenance: 'Equal-tempered maqam — no quarter-tones',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(4), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(11),
    ],
  );

  /// Maqam Nikriz — a raised fourth over a minor third.
  static const maqamNikriz = GFScale(
    id: 'maqamNikriz',
    name: 'Nikriz',
    family: GFScaleFamily.maqam,
    provenance: 'Equal-tempered maqam — no quarter-tones',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(6),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(10),
    ],
  );

  /// Maqam Suznak — Rast below, Hijaz above.
  static const maqamSuznak = GFScale(
    id: 'maqamSuznak',
    name: 'Suznak',
    family: GFScaleFamily.maqam,
    provenance: '24-tone Arabic convention (half-flats at −50 cents)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4, -50.0),
      GFScaleDegree(5), GFScaleDegree(7), GFScaleDegree(8),
      GFScaleDegree(11),
    ],
  );

  /// Makam Uşşak — the Turkish neutral second.
  ///
  /// Its second degree sits 8 Holdrian commas up (181 cents), between a minor
  /// and a major second. That interval is the single most characteristic
  /// sound of Turkish makam, and no equal-tempered scale contains it.
  ///
  /// Built as the Uşşak tetrachord (8, 5, 9 commas) plus the Buselik
  /// pentachord (9, 4, 9, 9).
  static const makamUssak = GFScale(
    id: 'makamUssak',
    name: 'Uşşak (Turkish)',
    family: GFScaleFamily.maqam,
    provenance: 'Arel-Ezgi-Uzdilek: 8, 5, 9, 9, 4, 9, 9 Holdrian commas',
    degrees: [
      GFScaleDegree(0),
      GFScaleDegree(2, -18.9),   //  8 commas = 181.1
      GFScaleDegree(3, -5.7),    // 13 commas = 294.3
      GFScaleDegree(5, -1.9),    // 22 commas = 498.1
      GFScaleDegree(7, 1.9),     // 31 commas = 701.9
      GFScaleDegree(8, -7.5),    // 35 commas = 792.5
      GFScaleDegree(10, -3.8),   // 44 commas = 996.2
    ],
  );

  /// Makam Hüseyni — the Uşşak neutral second with a higher sixth.
  ///
  /// Hüseyni pentachord (8, 5, 9, 9) plus Uşşak tetrachord (8, 5, 9).
  static const makamHuseyni = GFScale(
    id: 'makamHuseyni',
    name: 'Hüseyni (Turkish)',
    family: GFScaleFamily.maqam,
    provenance: 'Arel-Ezgi-Uzdilek: 8, 5, 9, 9, 8, 5, 9 Holdrian commas',
    degrees: [
      GFScaleDegree(0),
      GFScaleDegree(2, -18.9),   //  8 commas = 181.1
      GFScaleDegree(3, -5.7),    // 13 commas = 294.3
      GFScaleDegree(5, -1.9),    // 22 commas = 498.1
      GFScaleDegree(7, 1.9),     // 31 commas = 701.9
      GFScaleDegree(9, -17.0),   // 39 commas = 883.0
      GFScaleDegree(10, -3.8),   // 44 commas = 996.2
    ],
  );

  // ═══ Persian — dastgāh ════════════════════════════════════════════════════
  //
  // The koron lowers a note by less than a semitone, and — unlike the Arabic
  // half-flat — it has no agreed size. Sources place it anywhere from 50 to 70
  // cents below the natural, performers place it by ear and by dastgāh, and
  // one authority notes only that no interval in the system falls under 90
  // cents. The −50 used here is the 24-tone notation convention, not a
  // measurement; the sound of the radif lives in how a player leans on these
  // degrees, which no tuning table can carry.

  /// Dastgāh-e Šur — the central mode of the Persian radif, with a koron
  /// second.
  static const dastgahShur = GFScale(
    id: 'dastgahShur',
    name: 'Šur',
    family: GFScaleFamily.persian,
    provenance: '24-tone notation convention; performed koron size varies',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, -50.0), GFScaleDegree(3),
      GFScaleDegree(5), GFScaleDegree(7), GFScaleDegree(8),
      GFScaleDegree(10),
    ],
  );

  /// Dastgāh-e Čahārgāh — an augmented second either side of the fifth, with
  /// korons: the most dramatic of the dastgāhs.
  static const dastgahChahargah = GFScale(
    id: 'dastgahChahargah',
    name: 'Čahārgāh',
    family: GFScaleFamily.persian,
    provenance: '24-tone notation convention; performed koron size varies',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(4), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(8), GFScaleDegree(11),
    ],
  );

  /// Dastgāh-e Segāh — rooted on a koron degree, so the tonic itself sits
  /// between two piano keys.
  static const dastgahSegah = GFScale(
    id: 'dastgahSegah',
    name: 'Segāh',
    family: GFScaleFamily.persian,
    provenance: '24-tone notation convention; performed koron size varies',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, -50.0), GFScaleDegree(3),
      GFScaleDegree(5), GFScaleDegree(7, -50.0), GFScaleDegree(8),
      GFScaleDegree(10),
    ],
  );

  /// Dastgāh-e Homāyun — Čahārgāh's intervals reordered around a minor tonic.
  static const dastgahHomayun = GFScale(
    id: 'dastgahHomayun',
    name: 'Homāyun',
    family: GFScaleFamily.persian,
    provenance: '24-tone notation convention; performed koron size varies',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, -50.0), GFScaleDegree(3),
      GFScaleDegree(5), GFScaleDegree(7), GFScaleDegree(8),
      GFScaleDegree(11),
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


  /// Raga Malkauns — a late-night pentatonic on komal ga, ma, komal dha and
  /// komal ni, with no fifth. Dark and immediately recognisable.
  static const ragaMalkauns = GFScale(
    id: 'ragaMalkauns',
    name: 'Malkauns',
    family: GFScaleFamily.raga,
    provenance: 'Just intonation from the shruti ratios (ascending form)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(3, -5.865), GFScaleDegree(5, -1.955),
      GFScaleDegree(8, -7.820), GFScaleDegree(10, -3.910),
    ],
  );

  /// Raga Darbari Kanada — its komal ga is sung deliberately flat and heavily
  /// oscillated; the fixed pitch here is the centre of that oscillation, not
  /// the note as performed.
  static const ragaDarbari = GFScale(
    id: 'ragaDarbari',
    name: 'Darbari Kanada',
    family: GFScaleFamily.raga,
    provenance: 'Shruti ratios; komal ga is oscillated in performance',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(3, -5.865),
      GFScaleDegree(5, -1.955), GFScaleDegree(7, 1.955),
      GFScaleDegree(8, -7.820), GFScaleDegree(10, -3.910),
    ],
  );

  /// Raga Bhimpalasi — an afternoon raga, Kafi with the second and sixth
  /// omitted in ascent.
  static const ragaBhimpalasi = GFScale(
    id: 'ragaBhimpalasi',
    name: 'Bhimpalasi',
    family: GFScaleFamily.raga,
    provenance: 'Just intonation from the shruti ratios (ascending form)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(3, -5.865), GFScaleDegree(5, -1.955),
      GFScaleDegree(7, 1.955), GFScaleDegree(10, -3.910),
    ],
  );

  /// Mayamalavagowla — the raga every Carnatic student learns first, chosen
  /// for teaching because its intervals are symmetric around the fifth.
  static const ragaMayamalavagowla = GFScale(
    id: 'ragaMayamalavagowla',
    name: 'Mayamalavagowla',
    family: GFScaleFamily.raga,
    provenance: 'Carnatic melakarta 15, just intonation',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -9.775), GFScaleDegree(4, -13.686),
      GFScaleDegree(5, -1.955), GFScaleDegree(7, 1.955),
      GFScaleDegree(8, -7.820), GFScaleDegree(11, -11.731),
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


  /// Shang — the second Chinese pentatonic mode, on the same cycle of fifths.
  static const shangPentatonic = GFScale(
    id: 'shangPentatonic',
    name: 'Shang',
    family: GFScaleFamily.farEast,
    provenance: 'Sanfen sunyi cycle of fifths (Pythagorean)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(5, -1.955),
      GFScaleDegree(7, 1.955), GFScaleDegree(10, -3.910),
    ],
  );

  /// Jue — the third Chinese mode, the darkest of the five.
  static const juePentatonic = GFScale(
    id: 'juePentatonic',
    name: 'Jue',
    family: GFScaleFamily.farEast,
    provenance: 'Sanfen sunyi cycle of fifths (Pythagorean)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(3, -5.865), GFScaleDegree(5, -1.955),
      GFScaleDegree(8, -7.820), GFScaleDegree(10, -3.910),
    ],
  );

  /// Zhi — the fourth Chinese mode.
  static const zhiPentatonic = GFScale(
    id: 'zhiPentatonic',
    name: 'Zhi',
    family: GFScaleFamily.farEast,
    provenance: 'Sanfen sunyi cycle of fifths (Pythagorean)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(5, -1.955),
      GFScaleDegree(7, 1.955), GFScaleDegree(9, 5.865),
    ],
  );

  /// Yu — the fifth Chinese mode, the minor-sounding one.
  static const yuPentatonic = GFScale(
    id: 'yuPentatonic',
    name: 'Yu',
    family: GFScaleFamily.farEast,
    provenance: 'Sanfen sunyi cycle of fifths (Pythagorean)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(3, -5.865), GFScaleDegree(5, -1.955),
      GFScaleDegree(7, 1.955), GFScaleDegree(10, -3.910),
    ],
  );

  /// Ryo — the bright heptatonic mode of Japanese gagaku.
  static const ryo = GFScale(
    id: 'ryo',
    name: 'Ryo',
    family: GFScaleFamily.farEast,
    provenance: 'Gagaku mode, equal-tempered notation',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(11),
    ],
  );

  /// Ritsu — the darker gagaku counterpart to [ryo].
  static const ritsu = GFScale(
    id: 'ritsu',
    name: 'Ritsu',
    family: GFScaleFamily.farEast,
    provenance: 'Gagaku mode, equal-tempered notation',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(3), GFScaleDegree(5),
      GFScaleDegree(7), GFScaleDegree(9), GFScaleDegree(10),
    ],
  );

  // ═══ Southeast Asia ═══════════════════════════════════════════════════════

  /// Thai classical tuning — seven near-equal steps of about 171 cents.
  ///
  /// The one traditional scale in the catalogue that is an equal division of
  /// the octave, and a happy accident for the keyboard: its seven degrees land
  /// on the seven white keys, each pulled up to 43 cents off. Play in C major
  /// and a piphat ensemble comes out.
  ///
  /// Real Thai ensembles are not exactly equal — the tuning is set by ear on
  /// fixed-pitch percussion — but 7-fold equality is the model the theory and
  /// the instrument makers work from.
  static final thai7Equal = _equalDivision(
    id: 'thai7Equal',
    name: 'Thai (7 equal)',
    provenance: 'Idealised 7-fold equal division, 171.4 cents per step',
    steps: 7,
    family: GFScaleFamily.southeastAsia,
  );

  // ═══ Africa ═══════════════════════════════════════════════════════════════
  //
  // Ethiopian qenet are pentatonic modes whose *degrees* are well documented
  // but whose intonation is not tempered in performance — a krar or a masenqo
  // is tuned by ear, and a singer bends between the degrees. What follows is
  // the pitch structure as it is written and taught, which is what a keyboard
  // can honestly offer; the inflections are the player's.

  /// Tizita — the qenet of nostalgia, and the most widely known.
  static const tizita = GFScale(
    id: 'tizita',
    name: 'Tizita',
    family: GFScaleFamily.africa,
    provenance: 'Ethiopian qenet; untempered in performance',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4), GFScaleDegree(7),
      GFScaleDegree(9),
    ],
  );

  /// Bati — the same five degrees heard from a different tonic, giving the
  /// major-pentatonic-with-a-flat-third colour of much Ethio-jazz.
  static const bati = GFScale(
    id: 'bati',
    name: 'Bati',
    family: GFScaleFamily.africa,
    provenance: 'Ethiopian qenet; untempered in performance',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(4), GFScaleDegree(5), GFScaleDegree(7),
      GFScaleDegree(11),
    ],
  );

  /// Ambassel — a semitone above the tonic, then a leap: the most angular of
  /// the four.
  static const ambassel = GFScale(
    id: 'ambassel',
    name: 'Ambassel',
    family: GFScaleFamily.africa,
    provenance: 'Ethiopian qenet; untempered in performance',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(5), GFScaleDegree(7),
      GFScaleDegree(8),
    ],
  );

  /// Anchihoye — the qenet most often described as having neutral degrees,
  /// notated here at their quarter-tone positions.
  static const anchihoye = GFScale(
    id: 'anchihoye',
    name: 'Anchihoye',
    family: GFScaleFamily.africa,
    provenance: 'Ethiopian qenet; neutral degrees at 24-tone positions',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1), GFScaleDegree(5), GFScaleDegree(6),
      GFScaleDegree(8, -50.0),
    ],
  );

  /// East African equipentatonic — the amadinda and embaire xylophones of
  /// Uganda, tuned to five near-equal steps of 240 cents.
  ///
  /// The same division as the Javanese slendro, arrived at independently on
  /// another continent — which is the point of having both.
  static final amadinda = _equalDivision(
    id: 'amadinda',
    name: 'Amadinda (5 equal)',
    provenance: 'Ganda xylophone tuning, idealised 5-fold equal division',
    steps: 5,
    family: GFScaleFamily.africa,
  );

  // ═══ Europe ═══════════════════════════════════════════════════════════════

  /// The Great Highland Bagpipe scale.
  ///
  /// Famously not equal-tempered: the chanter is bored to a near-just
  /// mixolydian, which is why a pipe band sounds in tune with itself and
  /// distinctly out of tune with a piano. The 3rd is a just 5/4 and the flat
  /// 7th a just 16/9 — both audibly low against equal temperament.
  static const highlandPipe = GFScale(
    id: 'highlandPipe',
    name: 'Highland Pipe',
    family: GFScaleFamily.europe,
    provenance: 'Near-just chanter scale (9/8, 5/4, 4/3, 3/2, 27/16, 16/9)',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, 3.910), GFScaleDegree(4, -13.686),
      GFScaleDegree(5, -1.955), GFScaleDegree(7, 1.955),
      GFScaleDegree(9, 5.865), GFScaleDegree(10, -3.910),
    ],
  );


  /// Hardanger fiddle — the Norwegian "blue" tuning.
  ///
  /// Measurements of hardingfele players consistently show a third and a sixth
  /// sitting between major and minor, and a fourth pulled high. The values
  /// below are a plausible centre of those measurements, not a standard: the
  /// instrument has no frets and every district plays it differently.
  static const hardingfele = GFScale(
    id: 'hardingfele',
    name: 'Hardingfele',
    family: GFScaleFamily.europe,
    provenance: 'Averaged Norwegian fiddle intonation; varies by district',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2), GFScaleDegree(4, -35.0),
      GFScaleDegree(5, 20.0), GFScaleDegree(7), GFScaleDegree(9, -35.0),
      GFScaleDegree(10),
    ],
  );

  /// Byzantine chant, soft chromatic genus.
  ///
  /// Greek Orthodox chant divides the octave into 72 parts, and its second
  /// mode uses a chromatic tetrachord noticeably softer than the augmented
  /// second a Western ear expects from Hijaz.
  static const byzantineSoftChromatic = GFScale(
    id: 'byzantineSoftChromatic',
    name: 'Byzantine (soft chromatic)',
    family: GFScaleFamily.europe,
    provenance: '72-division Byzantine theory, soft chromatic genus',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, 33.0), GFScaleDegree(3, 33.0),
      GFScaleDegree(5), GFScaleDegree(7), GFScaleDegree(8, 33.0),
      GFScaleDegree(10, 33.0),
    ],
  );

  /// Byzantine chant, hard chromatic genus — the wide augmented second of the
  /// sixth mode.
  static const byzantineHardChromatic = GFScale(
    id: 'byzantineHardChromatic',
    name: 'Byzantine (hard chromatic)',
    family: GFScaleFamily.europe,
    provenance: '72-division Byzantine theory, hard chromatic genus',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -17.0), GFScaleDegree(4, 17.0),
      GFScaleDegree(5), GFScaleDegree(7), GFScaleDegree(8, -17.0),
      GFScaleDegree(11, 17.0),
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


  /// Pelog barang — the pelog degrees heard from a different tonic, the second
  /// of the two pathet a Javanese gamelan plays in.
  static const pelogBarang = GFScale(
    id: 'pelogBarang',
    name: 'Pelog Barang',
    family: GFScaleFamily.gamelan,
    provenance: 'Averaged Javanese pelog barang; every gamelan differs',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(2, -30.0), GFScaleDegree(4, 40.0),
      GFScaleDegree(6, -30.0), GFScaleDegree(7, -15.0),
      GFScaleDegree(9, -50.0), GFScaleDegree(11, 20.0),
    ],
  );

  /// Pelog selisir — the five-tone Balinese subset, the tuning of a gong kebyar
  /// and the sound most listeners mean by "gamelan".
  static const pelogSelisir = GFScale(
    id: 'pelogSelisir',
    name: 'Pelog Selisir',
    family: GFScaleFamily.gamelan,
    provenance: 'Averaged Balinese selisir; every gamelan differs',
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, 20.0), GFScaleDegree(3, -30.0),
      GFScaleDegree(7, -30.0), GFScaleDegree(8, -15.0),
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

  // ═══ Experimental — constructed tunings ═══════════════════════════════════
  //
  // These belong to no tradition: they are the result of dividing an interval
  // into equal parts, or of following the harmonic series. Most divide the
  // octave into more than twelve steps, which no keyboard can spell — they use
  // the linear layout, so one octave spans as many keys as the scale has
  // degrees and the black/white pattern stops meaning anything.

  /// Builds an equal division of [periodCents] into [steps] parts, laid out
  /// one degree per key.
  ///
  /// Written as a factory rather than a literal because a 31-note table typed
  /// out by hand is a table with a typo in it. Degree *i* sounds at
  /// `i * periodCents / steps` while the keyboard writes it at `i * 100`, so
  /// the deviation is the difference.
  static GFScale _equalDivision({
    required String id,
    required String name,
    required String provenance,
    required int steps,
    double periodCents = 1200.0,
    GFScaleFamily family = GFScaleFamily.experimental,
  }) {
    final stepCents = periodCents / steps;
    return GFScale(
      id: id,
      name: name,
      family: family,
      provenance: provenance,
      mapping: GFScaleMapping.linear,
      periodCents: periodCents,
      degrees: [
        for (var i = 0; i < steps; i++)
          GFScaleDegree(i, i * stepCents - i * 100.0),
      ],
    );
  }

  /// 24 equal divisions of the octave — quarter-tones.
  ///
  /// The system King Gizzard's refretted guitars play in: every equal-tempered
  /// semitone is split in two. Two keyboard octaves cover one sounding octave.
  static final quarterTone24Edo = _equalDivision(
    id: 'edo24',
    name: '24-EDO (quarter-tone)',
    provenance: '24 equal divisions of the octave, 50 cents apart',
    steps: 24,
  );

  /// 19 equal divisions of the octave.
  ///
  /// Close to quarter-comma meantone, with a distinct sharp and flat for every
  /// accidental — C sharp and D flat are different notes.
  static final edo19 = _equalDivision(
    id: 'edo19',
    name: '19-EDO',
    provenance: '19 equal divisions of the octave, 63.16 cents apart',
    steps: 19,
  );

  /// 31 equal divisions of the octave.
  ///
  /// Huygens' division: near-just major thirds and a usable harmonic seventh,
  /// the classical answer to what meantone was approximating.
  static final edo31 = _equalDivision(
    id: 'edo31',
    name: '31-EDO',
    provenance: '31 equal divisions of the octave, 38.71 cents apart',
    steps: 31,
  );

  /// Bohlen-Pierce — 13 equal divisions of the tritave (3:1), not the octave.
  ///
  /// The one scale in the catalogue with no octave at all: doubling a
  /// frequency lands between two degrees. Built on odd harmonics, so it
  /// consonates against odd-harmonic timbres (clarinets) and fights
  /// everything else.
  static final bohlenPierce = _equalDivision(
    id: 'bohlenPierce',
    name: 'Bohlen-Pierce',
    provenance: '13 equal divisions of the 3:1 tritave — no octave',
    steps: 13,
    periodCents: 1901.955,
  );

  /// Harmonics 8 through 16 of the natural series.
  ///
  /// What a brass instrument plays without valves in its top register. Sounds
  /// like a major scale with the fourth pulled sharp (harmonic 11) and the
  /// seventh flat (harmonic 7's octave, harmonic 14).
  static const harmonicSeries = GFScale(
    id: 'harmonicSeries',
    name: 'Harmonic Series 8-16',
    family: GFScaleFamily.experimental,
    provenance: 'Harmonics 8-16: 9/8, 5/4, 11/8, 3/2, 13/8, 7/4, 15/8',
    degrees: [
      GFScaleDegree(0),
      GFScaleDegree(2, 3.910),    //  9/8  = 203.910
      GFScaleDegree(4, -13.686),  //  5/4  = 386.314
      GFScaleDegree(6, -48.682),  // 11/8  = 551.318
      GFScaleDegree(7, 1.955),    //  3/2  = 701.955
      GFScaleDegree(8, 40.528),   // 13/8  = 840.528
      GFScaleDegree(10, -31.174), //  7/4  = 968.826
      GFScaleDegree(11, -11.731), // 15/8  = 1088.269
    ],
  );

  /// Four quarter-tone steps, then the rest of the octave untouched.
  ///
  /// A demonstration of what the pitch-class layout can do that a tradition
  /// never asks for: the first four keys are compressed into a single
  /// semitone's worth of pitch, leaving a wide gap before the fifth degree.
  /// The third key is pulled a whole semitone below where it is written —
  /// which is exactly why the catalogue's "a degree stays near its key" check
  /// does not apply to this family.
  static const quarterToneCluster = GFScale(
    id: 'quarterToneCluster',
    name: 'Quarter-tone Cluster',
    family: GFScaleFamily.experimental,
    provenance: 'Four keys at 0, 50, 100 and 150 cents, then the octave '
        'resumes',
    degrees: [
      GFScaleDegree(0),
      GFScaleDegree(1, -50.0),   // sounds 50
      GFScaleDegree(2, -100.0),  // sounds 100
      GFScaleDegree(3, -150.0),  // sounds 150
      GFScaleDegree(4),
      GFScaleDegree(5),
      GFScaleDegree(7),
      GFScaleDegree(9),
      GFScaleDegree(11),
    ],
  );


  /// 17 equal divisions of the octave.
  ///
  /// The tuning The Mercury Tree play in — microtonal math rock built entirely
  /// on it. Its fifth is wider than a just one, which tilts every chord.
  static final edo17 = _equalDivision(
    id: 'edo17',
    name: '17-EDO',
    provenance: '17 equal divisions of the octave, 70.59 cents apart',
    steps: 17,
  );

  /// 22 equal divisions of the octave — the xenharmonic scene's workhorse,
  /// used by Sevish and Brendan Byrnes.
  static final edo22 = _equalDivision(
    id: 'edo22',
    name: '22-EDO',
    provenance: '22 equal divisions of the octave, 54.55 cents apart',
    steps: 22,
  );

  /// 15 equal divisions of the octave.
  static final edo15 = _equalDivision(
    id: 'edo15',
    name: '15-EDO',
    provenance: '15 equal divisions of the octave, 80 cents apart',
    steps: 15,
  );

  /// 13 equal divisions of the octave — no usable fifth at all, which is why
  /// it sounds like nothing else.
  static final edo13 = _equalDivision(
    id: 'edo13',
    name: '13-EDO',
    provenance: '13 equal divisions of the octave, 92.31 cents apart',
    steps: 13,
  );

  /// 16 equal divisions of the octave, home of the mavila temperament, where
  /// major and minor swap places.
  static final edo16 = _equalDivision(
    id: 'edo16',
    name: '16-EDO',
    provenance: '16 equal divisions of the octave, 75 cents apart',
    steps: 16,
  );

  /// Blackwood's decatonic — ten notes of 15-EDO in a 1, 2, 1, 2… pattern.
  ///
  /// Easley Blackwood wrote a full etude on it. Unlike a raw EDO this is a
  /// scale you can actually compose in: the alternating step sizes give it a
  /// tonic and a shape.
  static const blackwoodDecatonic = GFScale(
    id: 'blackwoodDecatonic',
    name: 'Blackwood Decatonic',
    family: GFScaleFamily.experimental,
    provenance: 'Ten notes of 15-EDO, alternating 80 and 160 cent steps',
    mapping: GFScaleMapping.linear,
    degrees: [
      GFScaleDegree(0), GFScaleDegree(1, -20.0), GFScaleDegree(2, 40.0),
      GFScaleDegree(3, 20.0), GFScaleDegree(4, 80.0), GFScaleDegree(5, 60.0),
      GFScaleDegree(6, 120.0), GFScaleDegree(7, 100.0),
      GFScaleDegree(8, 160.0), GFScaleDegree(9, 140.0),
    ],
  );

  /// Carlos Alpha — Wendy Carlos's division of a perfect fifth into nine, with
  /// no octave anywhere.
  ///
  /// Repeating an interval that is not the octave means the pitch never comes
  /// back to itself: doubling a frequency lands between two degrees. Carlos
  /// designed it to hold major and minor thirds more purely than any octave
  /// division can.
  static final carlosAlpha = _equalDivision(
    id: 'carlosAlpha',
    name: 'Carlos Alpha',
    provenance: 'Wendy Carlos: steps of 78.0 cents, no octave',
    steps: 9,
    periodCents: 702.0,
  );

  /// Carlos Beta — the same idea with the fifth split eleven ways.
  static final carlosBeta = _equalDivision(
    id: 'carlosBeta',
    name: 'Carlos Beta',
    provenance: 'Wendy Carlos: steps of 63.8 cents, no octave',
    steps: 11,
    periodCents: 702.0,
  );

  /// Carlos Gamma — twenty steps to the fifth, so fine that triads are nearly
  /// beatless.
  static final carlosGamma = _equalDivision(
    id: 'carlosGamma',
    name: 'Carlos Gamma',
    provenance: 'Wendy Carlos: steps of 35.1 cents, no octave',
    steps: 20,
    periodCents: 702.0,
  );

  /// Bohlen-Pierce Lambda — the nine-note scale composers actually write in,
  /// drawn from the thirteen steps of [bohlenPierce].
  static const bohlenPierceLambda = GFScale(
    id: 'bohlenPierceLambda',
    name: 'Bohlen-Pierce Lambda',
    family: GFScaleFamily.experimental,
    provenance: 'Steps 0, 1, 3, 4, 6, 7, 9, 10, 12 of 13-tone Bohlen-Pierce',
    mapping: GFScaleMapping.linear,
    periodCents: 1901.955,
    degrees: [
      GFScaleDegree(0),
      GFScaleDegree(1, 46.3),    //  1 step  = 146.3
      GFScaleDegree(2, 238.9),   //  3 steps = 438.9
      GFScaleDegree(3, 285.2),   //  4 steps = 585.2
      GFScaleDegree(4, 477.8),   //  6 steps = 877.8
      GFScaleDegree(5, 524.1),   //  7 steps = 1024.1
      GFScaleDegree(6, 716.7),   //  9 steps = 1316.7
      GFScaleDegree(7, 763.0),   // 10 steps = 1463.0
      GFScaleDegree(8, 955.7),   // 12 steps = 1755.7
    ],
  );

  /// Subharmonic series 16 down to 8 — the mirror of [harmonicSeries].
  ///
  /// Where the harmonic series is built from a fundamental upward, this one
  /// divides downward. Partch called the two otonality and utonality; the
  /// undertone version sounds markedly darker for reasons that have more to do
  /// with how the ear finds a root than with the intervals themselves.
  static const subharmonicSeries = GFScale(
    id: 'subharmonicSeries',
    name: 'Subharmonic Series 16-8',
    family: GFScaleFamily.experimental,
    provenance: 'Undertones 16-8: 16/15, 8/7, 16/13, 4/3, 16/11, 8/5, 16/9',
    degrees: [
      GFScaleDegree(0),
      GFScaleDegree(1, 11.731),   // 16/15 = 111.731
      GFScaleDegree(2, 31.174),   //  8/7  = 231.174
      GFScaleDegree(4, -40.528),  // 16/13 = 359.472
      GFScaleDegree(5, -1.955),   //  4/3  = 498.045
      GFScaleDegree(6, 48.682),   // 16/11 = 648.682
      GFScaleDegree(8, 13.686),   //  8/5  = 813.686
      GFScaleDegree(10, -3.910),  // 16/9  = 996.090
    ],
  );

  // ═══ Catalogue ════════════════════════════════════════════════════════════

  /// Every built-in scale, in the order the UI presents them.
  ///
  /// Grouped by family so the scale grid can be built by a single pass with
  /// a tab break wherever [GFScale.family] changes.
  ///
  /// `final` rather than `const` because the equal divisions are generated by
  /// [_equalDivision] — a 31-note table typed out by hand is a table with a
  /// typo in it.
  static final List<GFScale> all = [
    // Western
    major, naturalMinor, harmonicMinor, melodicMinor,
    majorPentatonic, minorPentatonic, blues, rock,
    dorian, phrygian, lydian, mixolydian, locrian,
    phrygianDominant, wholeTone, diminished,
    // Maqam
    maqamRast, maqamBayati, maqamHijaz, maqamSaba,
    maqamNahawand, maqamKurd, maqamAjam, maqamSikah, maqamHuzam,
    maqamHijazkar, maqamNikriz, maqamSuznak,
    makamRastTurkish, makamUssak, makamHuseyni,
    // Persian
    dastgahShur, dastgahChahargah, dastgahSegah, dastgahHomayun,
    // Raga
    ragaBhairav, ragaYaman, ragaBhairavi, ragaTodi, ragaMarwa, ragaKafi,
    ragaMalkauns, ragaDarbari, ragaBhimpalasi, ragaMayamalavagowla,
    // Far East
    gongPentatonic, shangPentatonic, juePentatonic, zhiPentatonic,
    yuPentatonic, hirajoshi, inSen, yo, ryo, ritsu, pyeongjo, gyemyeonjo,
    // Southeast Asia
    thai7Equal,
    // Gamelan
    slendro, pelog, pelogBarang, pelogSelisir,
    // Africa
    tizita, bati, ambassel, anchihoye, amadinda,
    // Europe
    highlandPipe, hardingfele,
    byzantineSoftChromatic, byzantineHardChromatic,
    // Temperaments
    justIntonation, pythagorean, meantone, werckmeisterIII,
    // Experimental — last, matching the family tab order.
    quarterTone24Edo, edo19, edo31, edo17, edo22, edo15, edo13, edo16,
    blackwoodDecatonic, bohlenPierce, bohlenPierceLambda,
    carlosAlpha, carlosBeta, carlosGamma,
    harmonicSeries, subharmonicSeries, quarterToneCluster,
  ];

  // ── Custom scales ─────────────────────────────────────────────────────────
  //
  // Player-made and imported scales live in a runtime registry rather than in
  // [all], which stays a pure compile-time catalogue. Keeping one lookup point
  // ([byId]) is what matters: a saved project names a scale by id and must not
  // have to know whether it was shipped or hand-made.

  static final Map<String, GFScale> _custom = {};

  /// Registers a custom scale, replacing any earlier one with the same id.
  ///
  /// Called both when the player's library is loaded and when a project brings
  /// its own copy of a scale — a project is self-contained, so opening one on
  /// a machine that has never seen that scale still plays it correctly.
  static void registerCustom(GFScale scale) {
    _custom[scale.id] = scale;
  }

  /// Forgets a custom scale. No-op for built-in ids.
  static void unregisterCustom(String id) {
    _custom.remove(id);
  }

  /// Drops every registered custom scale — for tests and project switches.
  static void clearCustom() {
    _custom.clear();
  }

  /// Every registered custom scale, in registration order.
  static List<GFScale> get customScales =>
      List<GFScale>.unmodifiable(_custom.values);

  // ── Lookup ─────────────────────────────────────────────────────────────

  /// The scales of one [family], in catalogue order.
  ///
  /// [GFScaleFamily.custom] returns the runtime registry instead of the
  /// catalogue, so the module's scale grid can render every family the same
  /// way without special-casing.
  static List<GFScale> byFamily(GFScaleFamily family) {
    if (family == GFScaleFamily.custom) return customScales;
    return all.where((s) => s.family == family).toList(growable: false);
  }

  /// Looks a scale up by its [GFScale.id], built-in or custom, or returns null
  /// when unknown.
  ///
  /// Returning null rather than throwing matters for project loading: a `.gf`
  /// file saved by a newer build may name a scale this build has never heard
  /// of, and the right response is to fall back to a default, not to refuse
  /// the whole project.
  static GFScale? byId(String id) {
    for (final scale in all) {
      if (scale.id == id) return scale;
    }
    return _custom[id];
  }

  /// The default scale used when none is selected or a saved id is unknown.
  static const GFScale fallback = major;
}
