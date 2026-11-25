import 'dart:math';

import '../models/drum_generator_plugin_instance.dart';
import '../models/drum_pattern_data.dart';

/// What the drum generator plays in one bar: which section, which bar of it,
/// and how.
///
/// Produced by [DrumArranger.planBar]. Pure data, so the same bar always gets
/// the same plan however many times it is scheduled.
class DrumBarPlan {
  /// Section to play: `'intro'`, `'groove'`, `'fill'` or `'break'`.
  final String section;

  /// Bar number within the current run of [section], from 0. A two-bar
  /// `sequence` section uses it to play its bars in order.
  final int barInSection;

  /// Seed for picking the variation of a `loop` section. Constant for a
  /// whole phrase, so the drummer keeps one idea until the next fill.
  final int variationSeed;

  /// Whether a crash cymbal lands on this bar, on top of [section].
  final bool crash;

  /// Multiplier on every hit's velocity (1.0 = as written). Below 1.0 at the
  /// start of a phrase when "dynamic build" is on, so the phrase grows.
  final double velocityScale;

  /// Index of the phrase this bar belongs to (count-in bars are -1).
  final int phraseIndex;

  const DrumBarPlan({
    required this.section,
    required this.barInSection,
    required this.variationSeed,
    required this.crash,
    required this.velocityScale,
    required this.phraseIndex,
  });
}

/// Decides, bar by bar, how a drum pattern is arranged over time.
///
/// Drummers think in phrases of 4, 8 or 16 bars, not in single bars. Within a
/// phrase they keep one groove, end it with a fill, and land the next phrase
/// with a crash. A break (the band drops out, or the drums thin down) starts a
/// phrase rather than interrupting one.
///
/// The arranger works the same way:
/// - the phrase length comes from the fill setting (8 bars when fills are
///   off, so the groove still changes from time to time);
/// - the groove variation is chosen at the start of each phrase and held to
///   its end;
/// - the fill takes the last bar(s) of the phrase;
/// - a break, when one is drawn for this phrase, takes its first bar(s);
/// - the crash lands on the first bar after a count-in, a fill or a break.
///
/// Everything is derived from the bar number and a per-play [seed], with no
/// state carried from one bar to the next. The engine schedules bars ahead of
/// time and may schedule the same bar again after a setting changes; a pure
/// function gives the same answer both times.
class DrumArranger {
  DrumArranger._();

  /// Phrase length used when fills are off.
  static const int defaultPhraseBars = 8;

  /// Phrase lengths drawn from when the fill setting is "random".
  static const List<int> randomPhraseBars = [8, 12, 16];

  /// Chance that a phrase opens with a break, per break setting. A phrase is
  /// usually 8 bars, so "rare" is about one break every 40 bars.
  static const Map<DrumBreakFrequency, double> breakChance = {
    DrumBreakFrequency.none: 0.0,
    DrumBreakFrequency.rare: 0.2,
    DrumBreakFrequency.occasional: 0.4,
    DrumBreakFrequency.frequent: 0.8,
  };

  /// Velocity at the start of a phrase when "dynamic build" is on. The
  /// phrase rises from here to full velocity on its last groove bar.
  static const double buildStartScale = 0.85;

  /// Plans bar [bar] (0 = the first bar after play was pressed, count-in
  /// included) of [pattern] under [config]. [seed] changes on every play so
  /// that two takes do not sound identical.
  static DrumBarPlan planBar({
    required int bar,
    required DrumStructureConfig config,
    required DrumPatternData pattern,
    required int seed,
  }) {
    final introBars = introBarCount(config, pattern);
    if (bar < introBars) {
      return DrumBarPlan(
        section: 'intro',
        barInSection: bar,
        variationSeed: seed,
        crash: false,
        velocityScale: 1.0,
        phraseIndex: -1,
      );
    }
    final rel = bar - introBars;
    final phrase = _phraseAt(rel, config, seed);
    return _planInPhrase(
      pos: rel - phrase.start,
      length: phrase.length,
      index: phrase.index,
      afterCountIn: introBars > 0,
      config: config,
      pattern: pattern,
      seed: seed,
    );
  }

  /// Number of count-in bars before the groove. Zero when the pattern has no
  /// `intro` section to play them with.
  static int introBarCount(DrumStructureConfig config, DrumPatternData pattern) {
    if (!pattern.sections.containsKey('intro')) return 0;
    switch (config.introType) {
      case DrumIntroType.none:
        return 0;
      case DrumIntroType.countIn1:
      case DrumIntroType.chopsticks:
        return 1;
      case DrumIntroType.countIn2:
        return 2;
    }
  }

  /// Finds the phrase that contains groove bar [rel] (0 = first bar after
  /// the count-in) by walking the phrases from the start. Phrases can differ
  /// in length when fills are random, so the start cannot be computed by a
  /// division.
  static ({int index, int start, int length}) _phraseAt(
    int rel,
    DrumStructureConfig config,
    int seed,
  ) {
    var start = 0;
    var index = 0;
    while (true) {
      final length = phraseLength(config, seed, index);
      if (rel < start + length) {
        return (index: index, start: start, length: length);
      }
      start += length;
      index++;
    }
  }

  /// Length in bars of phrase [index].
  static int phraseLength(DrumStructureConfig config, int seed, int index) {
    switch (config.fillFrequency) {
      case DrumFillFrequency.off:
        return defaultPhraseBars;
      case DrumFillFrequency.random:
        final rng = Random(_mix(seed, index, 11));
        return randomPhraseBars[rng.nextInt(randomPhraseBars.length)];
      case DrumFillFrequency.every4:
      case DrumFillFrequency.every8:
      case DrumFillFrequency.every16:
        return config.fillFrequency.bars;
    }
  }

  /// Plans bar [pos] of phrase [index], which is [length] bars long.
  static DrumBarPlan _planInPhrase({
    required int pos,
    required int length,
    required int index,
    required bool afterCountIn,
    required DrumStructureConfig config,
    required DrumPatternData pattern,
    required int seed,
  }) {
    final fillBars = _fillBars(config, pattern, length);
    final breakBars = _breakBars(config, pattern, length, fillBars, seed, index);
    final grooveBars = length - fillBars - breakBars;

    // Where a crash lands: the downbeat that ends a count-in, a fill (the
    // previous phrase's), or a break. Not on a break's own first bar: a break
    // is the band dropping out, and a crash there would fill the hole.
    final landing = breakBars > 0
        ? pos == breakBars
        : pos == 0 && (index > 0 ? fillBars > 0 : afterCountIn);
    final crash = landing &&
        config.crashAfterFill &&
        pattern.sections.containsKey('crash');

    if (pos < breakBars) {
      return DrumBarPlan(
        section: 'break',
        barInSection: pos,
        variationSeed: _mix(seed, index, 3),
        crash: false,
        velocityScale: 1.0,
        phraseIndex: index,
      );
    }
    if (pos >= length - fillBars) {
      return DrumBarPlan(
        section: 'fill',
        barInSection: pos - (length - fillBars),
        variationSeed: _mix(seed, index, 2),
        crash: false,
        velocityScale: 1.0,
        phraseIndex: index,
      );
    }
    final barInGroove = pos - breakBars;
    return DrumBarPlan(
      section: 'groove',
      barInSection: barInGroove,
      variationSeed: _mix(seed, index, 1),
      crash: crash,
      velocityScale: _buildScale(config, barInGroove, grooveBars),
      phraseIndex: index,
    );
  }

  /// Bars of fill at the end of a phrase of [length] bars: the fill
  /// section's own length, leaving at least one bar of groove.
  static int _fillBars(
    DrumStructureConfig config,
    DrumPatternData pattern,
    int length,
  ) {
    if (config.fillFrequency == DrumFillFrequency.off) return 0;
    final fill = pattern.sections['fill'];
    if (fill == null) return 0;
    return fill.bars.clamp(1, length - 1);
  }

  /// Bars of break at the start of phrase [index], or 0 when this phrase has
  /// none. The first phrase never opens with a break: the groove has to be
  /// heard before it can drop out.
  static int _breakBars(
    DrumStructureConfig config,
    DrumPatternData pattern,
    int length,
    int fillBars,
    int seed,
    int index,
  ) {
    if (index == 0) return 0;
    final brk = pattern.sections['break'];
    if (brk == null) return 0;
    final chance = breakChance[config.breakFrequency] ?? 0.0;
    if (chance <= 0) return 0;
    if (Random(_mix(seed, index, 5)).nextDouble() >= chance) return 0;
    // Keep at least one bar of groove between the break and the fill.
    final room = length - fillBars - 1;
    if (room < 1) return 0;
    return brk.bars.clamp(1, room);
  }

  /// Velocity multiplier for groove bar [barInGroove] of [grooveBars], when
  /// "dynamic build" is on: a straight rise from [buildStartScale] to 1.0.
  static double _buildScale(
    DrumStructureConfig config,
    int barInGroove,
    int grooveBars,
  ) {
    if (!config.dynamicBuild || grooveBars < 2) return 1.0;
    final t = barInGroove / (grooveBars - 1);
    return buildStartScale + (1.0 - buildStartScale) * t;
  }

  /// Combines the per-play seed, a phrase index and a purpose tag into one
  /// seed, so the groove, fill and break of a phrase draw independently.
  static int _mix(int seed, int index, int tag) =>
      (seed * 1000003 + index * 7919 + tag * 104729) & 0x7fffffff;
}
