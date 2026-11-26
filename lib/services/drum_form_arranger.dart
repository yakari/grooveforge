import 'dart:math';

import '../models/drum_generator_plugin_instance.dart';
import '../models/drum_pattern_data.dart';
import '../models/drum_song_form.dart';
import 'drum_arranger.dart';

/// Where a bar falls in a song form: which block, which bar of it, and how
/// many times the form has looped before it.
typedef DrumFormSpot = ({int block, int bar, int pass});

/// Arranges the drum generator bar by bar along a [DrumSongForm].
///
/// The user lays out the song as blocks (intro, verse, chorus, bridge,
/// break, ending). For each bar this works out what the drummer plays:
/// - each block holds one groove variation for its whole length, chosen
///   from the block's kind (see [autoVariation]) or forced by the user;
/// - the last bar of a block is a fill when the block asks for one, and a
///   block longer than the fill setting's phrase gets fills inside it too;
/// - a crash lands on the first bar after a fill, a break or the count-in;
/// - a break plays the style's `break` section, or one hit on beat 1 and
///   then silence when the style has none;
/// - the ending plays the style's `ending` section, or a fill and a final
///   hit, and the drums then stay silent.
///
/// Like [DrumArranger], everything is a pure function of the bar number,
/// so a bar scheduled twice is planned the same way both times.
class DrumFormArranger {
  DrumFormArranger._();

  /// Length of the ending block when the style has no `ending` section: a
  /// fill, then the final hit.
  static const int fallbackEndingBars = 2;

  /// Bars the ending block lasts with [pattern]: its `ending` section.
  static int endingBars(DrumPatternData pattern) =>
      pattern.sections['ending']?.bars.clamp(1, DrumSongBlock.maxBars) ??
      fallbackEndingBars;

  /// Bars [block] lasts with [pattern].
  static int blockBars(DrumSongBlock block, DrumPatternData pattern) =>
      block.kind == DrumBlockKind.ending ? endingBars(pattern) : block.bars;

  /// Total length of one pass through [form], in bars.
  static int formBars(DrumSongForm form, DrumPatternData pattern) =>
      form.blocks.fold(0, (sum, b) => sum + blockBars(b, pattern));

  /// Finds bar [rel] (0 = first bar after the count-in) in [form]. Returns
  /// null before the form starts and after its ending; a form without an
  /// ending loops forever.
  static DrumFormSpot? locate(
    int rel,
    DrumSongForm form,
    DrumPatternData pattern,
  ) {
    final total = formBars(form, pattern);
    if (rel < 0 || total <= 0) return null;
    if (form.hasEnding && rel >= total) return null;
    var pos = rel % total;
    for (var i = 0; i < form.blocks.length; i++) {
      final length = blockBars(form.blocks[i], pattern);
      if (pos < length) return (block: i, bar: pos, pass: rel ~/ total);
      pos -= length;
    }
    return null; // unreachable: pos < total
  }

  /// Plans bar [rel] of [form]. [afterCountIn] tells whether a count-in
  /// came before the form, so its first bar lands with a crash.
  static DrumBarPlan planBar({
    required int rel,
    required bool afterCountIn,
    required DrumSongForm form,
    required DrumStructureConfig config,
    required DrumPatternData pattern,
    required int seed,
  }) {
    final spot = locate(rel, form, pattern);
    if (spot == null) return _silent;
    final block = form.blocks[spot.block];
    final length = blockBars(block, pattern);
    final occurrence = spot.pass * form.blocks.length + spot.block;
    final part = _partAt(block, spot.bar, length, config, pattern);
    final isGroove = part.section == 'groove';

    return DrumBarPlan(
      section: part.section,
      barInSection: part.barInSection,
      variationSeed: DrumArranger.mix(seed, occurrence * 64 + spot.bar, 2),
      crash: isGroove &&
          block.kind != DrumBlockKind.intro &&
          _landsAfterTransition(rel, afterCountIn, form, config, pattern),
      velocityScale: isGroove
          ? DrumArranger.buildScale(config, spot.bar,
              length - _endFillBars(block, length, pattern))
          : 1.0,
      phraseIndex: occurrence,
      blockIndex: spot.block,
      barInBlock: spot.bar,
      variation: isGroove ? _variationFor(block, pattern) : null,
    );
  }

  /// The plan of a bar after the ending: nothing plays.
  static const DrumBarPlan _silent = DrumBarPlan(
    section: DrumBarPlan.silence,
    barInSection: 0,
    variationSeed: 0,
    crash: false,
    velocityScale: 1.0,
    phraseIndex: -1,
  );

  /// The section bar [bar] of [block] plays, and which bar of it.
  static ({String section, int barInSection}) _partAt(
    DrumSongBlock block,
    int bar,
    int length,
    DrumStructureConfig config,
    DrumPatternData pattern,
  ) {
    switch (block.kind) {
      case DrumBlockKind.ending:
        return _endingPart(bar, pattern);
      case DrumBlockKind.breakdown:
        return _breakPart(block, bar, length, pattern);
      case DrumBlockKind.intro:
      case DrumBlockKind.verse:
      case DrumBlockKind.chorus:
      case DrumBlockKind.bridge:
        final fill = _fillBarAt(block, bar, length, config, pattern);
        return fill != null
            ? (section: 'fill', barInSection: fill)
            : (section: 'groove', barInSection: bar);
    }
  }

  /// The ending: the style's own `ending` section, or else a fill followed
  /// by a single hit on beat 1.
  static ({String section, int barInSection}) _endingPart(
    int bar,
    DrumPatternData pattern,
  ) {
    if (pattern.sections.containsKey('ending')) {
      return (section: 'ending', barInSection: bar);
    }
    if (bar == 0 && pattern.sections.containsKey('fill')) {
      return (section: 'fill', barInSection: 0);
    }
    return (section: bar == fallbackEndingBars - 1 ? DrumBarPlan.drop : DrumBarPlan.silence, barInSection: 0);
  }

  /// A break: the band drops out. The style's `break` section when it has
  /// one; otherwise one hit on beat 1, then silence. With "fill at the end"
  /// its last bar(s) are a fill, the drummer's pickup into the next block.
  static ({String section, int barInSection}) _breakPart(
    DrumSongBlock block,
    int bar,
    int length,
    DrumPatternData pattern,
  ) {
    final fillBars = _endFillBars(block, length, pattern);
    if (bar >= length - fillBars) {
      return (section: 'fill', barInSection: bar - (length - fillBars));
    }
    if (pattern.sections.containsKey('break')) {
      return (section: 'break', barInSection: bar);
    }
    return (section: bar == 0 ? DrumBarPlan.drop : DrumBarPlan.silence, barInSection: 0);
  }

  /// Bars of fill closing [block]: the fill section's own length, leaving at
  /// least one bar of the block before it. Zero when the block asks for no
  /// fill, is a single bar, or the style has no fill.
  static int _endFillBars(
    DrumSongBlock block,
    int length,
    DrumPatternData pattern,
  ) {
    if (!block.fillAtEnd || block.kind == DrumBlockKind.ending) return 0;
    final fill = pattern.sections['fill'];
    if (fill == null || length < 2) return 0;
    return fill.bars.clamp(1, length - 1);
  }

  /// If bar [bar] of a groove block is a fill, the bar within that fill;
  /// otherwise null.
  ///
  /// Two kinds of fill: the one closing the block, and the ones inside a
  /// block longer than the fill setting's phrase (16 bars with "fill every
  /// 8" gets one after bar 8), so a long block still breathes.
  static int? _fillBarAt(
    DrumSongBlock block,
    int bar,
    int length,
    DrumStructureConfig config,
    DrumPatternData pattern,
  ) {
    final fill = pattern.sections['fill'];
    if (fill == null) return null;
    final endFill = _endFillBars(block, length, pattern);
    if (endFill > 0 && bar >= length - endFill) {
      return bar - (length - endFill);
    }
    final phrase = _innerPhraseBars(config);
    if (phrase <= 0) return null;
    // Last bar of the inner phrase this bar belongs to.
    final phraseEnd = (bar ~/ phrase + 1) * phrase - 1;
    if (phraseEnd >= length - 1 - endFill) return null; // the block's own end
    final fillBars = min(fill.bars, phrase - 1);
    if (fillBars < 1 || bar <= phraseEnd - fillBars) return null;
    return bar - (phraseEnd - fillBars + 1);
  }

  /// Phrase length for fills inside a long block, from the fill setting.
  /// "Random" uses 8 bars here: inside a song form the blocks already set
  /// the shape, so a steady inner phrase sounds more natural.
  static int _innerPhraseBars(DrumStructureConfig config) =>
      switch (config.fillFrequency) {
        DrumFillFrequency.off => 0,
        DrumFillFrequency.random => 8,
        _ => config.fillFrequency.bars,
      };

  /// Whether bar [rel] comes right after a fill, a break or the count-in,
  /// where a drummer lands with a crash.
  static bool _landsAfterTransition(
    int rel,
    bool afterCountIn,
    DrumSongForm form,
    DrumStructureConfig config,
    DrumPatternData pattern,
  ) {
    if (!config.crashAfterFill || !pattern.sections.containsKey('crash')) {
      return false;
    }
    if (rel == 0) return afterCountIn;
    final prev = locate(rel - 1, form, pattern);
    if (prev == null) return false;
    final block = form.blocks[prev.block];
    final length = blockBars(block, pattern);
    final part = _partAt(block, prev.bar, length, config, pattern);
    return part.section != 'groove';
  }

  /// The groove variation [block] plays: the one the user forced, when the
  /// style has it, or else [autoVariation].
  static String? _variationFor(DrumSongBlock block, DrumPatternData pattern) {
    final groove = pattern.sections['groove'];
    if (groove == null) return null;
    final forced = block.variation;
    if (forced != null && groove.variations.any((v) => v.name == forced)) {
      return forced;
    }
    return autoVariation(groove, block.kind);
  }

  /// The groove variation a block of [kind] plays when the user leaves it on
  /// "Auto", or null when [groove] has nothing to choose from (a `sequence`
  /// groove plays its bars in order whatever the block).
  ///
  /// A variation tagged with the matching `role:` wins. Without one:
  /// - verse: the most likely variation (highest weight), the style's main
  ///   groove;
  /// - chorus: the busiest one (most hits), for a lift;
  /// - intro: the lightest one;
  /// - bridge: one that is neither the verse's nor the chorus's, for
  ///   contrast.
  static String? autoVariation(DrumSection groove, DrumBlockKind kind) {
    if (groove.kind != DrumSectionKind.loop) return null;
    final vars = groove.variations;
    if (vars.isEmpty) return null;
    for (final v in vars) {
      if (v.role == kind.name) return v.name;
    }
    switch (kind) {
      case DrumBlockKind.verse:
      case DrumBlockKind.breakdown:
      case DrumBlockKind.ending:
        return vars.reduce((a, b) => b.weight > a.weight ? b : a).name;
      case DrumBlockKind.chorus:
        return vars.reduce((a, b) => b.hitCount > a.hitCount ? b : a).name;
      case DrumBlockKind.intro:
        return vars.reduce((a, b) => b.hitCount < a.hitCount ? b : a).name;
      case DrumBlockKind.bridge:
        final taken = {
          autoVariation(groove, DrumBlockKind.verse),
          autoVariation(groove, DrumBlockKind.chorus),
        };
        return vars
            .firstWhere((v) => !taken.contains(v.name), orElse: () => vars.last)
            .name;
    }
  }
}
