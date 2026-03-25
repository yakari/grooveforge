/// The timing feel of a drum pattern.
///
/// Determines the default swing ratio and may also imply systematic
/// microtiming offsets (e.g. "laid back" pushes every beat slightly behind
/// the grid to give a relaxed, hip-hop feel).
enum DrumFeel {
  /// Perfectly on-the-grid — no swing, no timing push or pull.
  straight,

  /// Slightly behind the beat: notes land a hair late, giving a relaxed feel.
  /// Swing ratio stays at 0.5 (triplet timing is not applied).
  laidBack,

  /// Slightly ahead of the beat: notes land a hair early — tight, energetic.
  pushed,

  /// Light swing: even subdivisions are delayed by ~16 % of a beat.
  /// Typical of light shuffle or country patterns.
  swingLight,

  /// Hard swing: triplet feel (67 % delay on even 8th-note subdivisions).
  /// Standard jazz and blues swing feel.
  swingHard,
}

/// Extension on [DrumFeel] that exposes the default swing ratio as a double.
///
/// The swing ratio represents how much the *even* 16th-note steps are delayed
/// relative to a perfectly even 16th-note grid.
///
/// - `0.5` = perfectly straight (even grid, no swing).
/// - `0.58` = light shuffle.
/// - `0.67` = jazz triplet (classic swing).
extension DrumFeelSwing on DrumFeel {
  /// Returns the default swing ratio for this feel.
  ///
  /// [laidBack] and [pushed] modify *timing offset* rather than swing ratio
  /// so their ratio stays at 0.5.  The offset is applied per-instrument via
  /// [DrumInstrumentDef.rush].
  double get defaultSwingRatio {
    switch (this) {
      case DrumFeel.straight:
        return 0.5;
      case DrumFeel.laidBack:
        return 0.5; // offset handled by instrument rush, not global swing
      case DrumFeel.pushed:
        return 0.5;
      case DrumFeel.swingLight:
        return 0.58;
      case DrumFeel.swingHard:
        return 0.67;
    }
  }
}

/// How variations within a section are selected on each repetition.
enum DrumSectionKind {
  /// One variation is chosen at random (weighted) on each repeat of the section.
  loop,

  /// Variations are played in order, one per bar, cycling with modulo.
  ///
  /// Used for patterns where each bar has a distinct rhythmic identity
  /// (e.g. Breton An Dro four-bar phrase).
  sequence,

  /// A metronome-style count-in rather than a musical section.
  ///
  /// The engine generates `hits` evenly-spaced rimshot notes instead of
  /// reading a step grid.
  countIn,
}

/// Configuration for a single drum instrument within a pattern.
///
/// All timing fields are measured in **beats** (quarter notes), regardless
/// of the pattern's time signature.
class DrumInstrumentDef {
  /// GM MIDI note number (35–81) for this drum instrument.
  final int note;

  /// Base MIDI velocity for a strong (`X`) hit.  Medium/soft/ghost hits
  /// are scaled from this value.
  final int baseVelocity;

  /// Maximum random ±velocity added on top of [baseVelocity] for humanisation.
  final int velocityRange;

  /// Maximum random ±timing offset in beats per hit (microtiming jitter).
  /// Typical value: 0.01–0.03.
  final double timingJitter;

  /// Systematic timing offset in beats (positive = early/rush, negative = drag).
  /// Used to give specific instruments a characteristic feel (e.g. rim shot
  /// slightly ahead of snare).
  final double rush;

  /// How long (in beats) to hold each note before sending note-off.
  ///
  /// Drums don't sustain, but some GM synths ignore short note-offs — keeping
  /// a small duration (0.08–0.25 beats) avoids silencing the natural decay.
  final double durationBeats;

  /// Constructs a [DrumInstrumentDef].
  const DrumInstrumentDef({
    required this.note,
    this.baseVelocity = 100,
    this.velocityRange = 15,
    this.timingJitter = 0.02,
    this.rush = 0.0,
    this.durationBeats = 0.1,
  });
}

/// One variation within a drum section.
///
/// A variation is a concrete rhythmic realisation of a section — e.g. a
/// "main groove" vs an "alt groove" with a different hi-hat pattern.
///
/// For `loop` sections the engine picks a variation randomly (weighted) on
/// each bar; for `sequence` sections it uses [barSequence] instead.
class DrumVariation {
  /// Human-readable name for the variation (used for debugging and logging).
  final String name;

  /// Probability weight used for random selection.  Higher values make this
  /// variation more likely to be chosen.
  final int weight;

  /// Step grids keyed by instrument name.
  ///
  /// Each value is a string of [DrumPatternData.resolution] characters:
  /// - `X` = strong hit (~base velocity)
  /// - `x` = medium hit (~75 % of base)
  /// - `o` = soft hit (~55 % of base)
  /// - `g` = ghost note (~28 % of base)
  /// - `.` = rest (no note)
  ///
  /// Used for `loop` sections.  Null for `sequence` sections.
  final Map<String, String> stepGrids;

  /// Ordered list of per-bar step grids for `sequence` sections.
  ///
  /// Each element maps instrument name → step grid string for one bar.
  /// The engine cycles through these with `absoluteBar % barSequence.length`.
  /// Null for `loop` sections (use [stepGrids] instead).
  final List<Map<String, String>>? barSequence;

  /// Constructs a [DrumVariation].
  const DrumVariation({
    required this.name,
    this.weight = 1,
    this.stepGrids = const {},
    this.barSequence,
  });
}

/// One named section within a drum pattern (groove, fill, break, crash, intro).
///
/// The engine uses [kind] to determine whether to pick a random variation
/// (loop) or play bars in order (sequence/countIn).
class DrumSection {
  /// Length in bars for a single pass through this section.
  final int bars;

  /// How the section selects its variation on each repeat.
  final DrumSectionKind kind;

  /// For [DrumSectionKind.countIn]: how many evenly-spaced hits to generate.
  final int? countInHits;

  /// For [DrumSectionKind.countIn]: the MIDI note number for the count-in hits.
  final int? countInNote;

  /// Available variations for this section.
  ///
  /// For `loop` sections: one is chosen randomly each time.
  /// For `sequence` sections: use the single variation's [DrumVariation.barSequence].
  final List<DrumVariation> variations;

  /// Constructs a [DrumSection].
  const DrumSection({
    required this.bars,
    this.kind = DrumSectionKind.loop,
    this.countInHits,
    this.countInNote,
    required this.variations,
  });
}

/// Global humanisation defaults for a pattern.
///
/// Each instrument can also carry its own [DrumInstrumentDef] timing and
/// velocity fields; the engine blends them with these global values.
class DrumHumanizationDef {
  /// Maximum random ±timing offset in beats (applied globally to all hits).
  final double timingJitter;

  /// Maximum random ±velocity added to all hits.
  final double velocityJitter;

  /// Slow sinusoidal drift applied to overall energy level (0 = none, 1 = max).
  final double velocityDrift;

  /// Constructs a [DrumHumanizationDef].
  const DrumHumanizationDef({
    this.timingJitter = 0.015,
    this.velocityJitter = 12,
    this.velocityDrift = 0.05,
  });
}

/// Complete parsed representation of a `.gfdrum` pattern file.
///
/// Produced by [DrumPatternParser] and stored in [DrumPatternRegistry].
/// The engine reads this to schedule MIDI events.
class DrumPatternData {
  /// Unique identifier derived from the `.gfdrum` filename stem
  /// (e.g. `'rock_basic'`).
  final String id;

  /// Display name shown in the UI style picker (e.g. `'Classic Rock'`).
  final String name;

  /// Style family grouping for the style picker (e.g. `'rock'`, `'jazz'`).
  final String family;

  /// Time signature as `(numerator, denominator)`.
  ///
  /// For 4/4 this is `(4, 4)`; for 6/8 this is `(6, 8)`.
  final (int, int) timeSignature;

  /// Number of steps per bar.
  ///
  /// For 4/4 at 16th-note resolution this is 16.
  /// For 6/8 at 12-step resolution this is 12.
  final int resolution;

  /// The timing feel of this pattern.
  final DrumFeel feel;

  /// Named instrument definitions, keyed by the instrument names used in
  /// step grids (e.g. `'kick'`, `'snare'`, `'hihat'`).
  final Map<String, DrumInstrumentDef> instruments;

  /// Global humanisation settings for this pattern.
  final DrumHumanizationDef humanization;

  /// Named sections of the pattern.
  ///
  /// Keys: `'groove'`, `'fill'`, `'break'`, `'crash'`, `'intro'`.
  /// Not all keys are required; the engine falls back to groove if a
  /// section is absent.
  final Map<String, DrumSection> sections;

  /// Constructs a [DrumPatternData].
  const DrumPatternData({
    required this.id,
    required this.name,
    required this.family,
    required this.timeSignature,
    required this.resolution,
    required this.feel,
    required this.instruments,
    required this.humanization,
    required this.sections,
  });

  /// Convenience accessor: time signature numerator (beats per bar).
  int get timeSigNumerator => timeSignature.$1;

  /// Convenience accessor: time signature denominator (beat unit).
  int get timeSigDenominator => timeSignature.$2;
}
