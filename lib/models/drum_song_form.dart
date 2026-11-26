/// The kind of a block in a drum song form: which part of the song it is.
///
/// A song form ("grille" in French) is the shape of a song, such as
/// verse 8, chorus 8, bridge 4, chorus 8. The drum generator plays a
/// different groove variation for each kind of block, so the chorus
/// sounds bigger than the verse.
enum DrumBlockKind {
  /// The opening of the song: the lightest variation, no crash on its start.
  intro,

  /// A verse: the main groove of the style.
  verse,

  /// A chorus: the busiest groove of the style.
  chorus,

  /// A bridge: a third groove, different from verse and chorus.
  bridge,

  /// A break: the band drops out. The style's `break` section, or a single
  /// hit on beat 1 followed by silence.
  breakdown,

  /// The end of the song: the style's `ending` section, then the drums stop.
  ending,
}

/// One block of a [DrumSongForm]: a part of the song and its length.
class DrumSongBlock {
  /// Which part of the song this block is.
  final DrumBlockKind kind;

  /// Length in bars. Ignored for [DrumBlockKind.ending], whose length is the
  /// style's `ending` section.
  final int bars;

  /// Whether the last bar of the block is a fill, leading into the next
  /// block. Ignored for [DrumBlockKind.ending], which brings its own ending.
  final bool fillAtEnd;

  /// Name of the groove variation to play, or null to let the generator
  /// choose one from the block's kind (see [DrumArranger]).
  final String? variation;

  /// For [DrumBlockKind.ending]: whether the transport stops when the block
  /// is over, which also stops the looper and the other modules.
  final bool stopTransport;

  /// Shortest and longest block a user can set, in bars.
  static const int minBars = 1;
  static const int maxBars = 32;

  /// Constructs a [DrumSongBlock].
  const DrumSongBlock({
    required this.kind,
    this.bars = 8,
    this.fillAtEnd = true,
    this.variation,
    this.stopTransport = true,
  });

  /// A copy with the given fields replaced. Pass [clearVariation] to go back
  /// to the automatic choice, since a null [variation] means "unchanged".
  DrumSongBlock copyWith({
    DrumBlockKind? kind,
    int? bars,
    bool? fillAtEnd,
    String? variation,
    bool clearVariation = false,
    bool? stopTransport,
  }) {
    return DrumSongBlock(
      kind: kind ?? this.kind,
      bars: bars ?? this.bars,
      fillAtEnd: fillAtEnd ?? this.fillAtEnd,
      variation: clearVariation ? null : (variation ?? this.variation),
      stopTransport: stopTransport ?? this.stopTransport,
    );
  }

  /// Serialises this block to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'bars': bars,
        'fillAtEnd': fillAtEnd,
        if (variation != null) 'variation': variation,
        if (kind == DrumBlockKind.ending) 'stopTransport': stopTransport,
      };

  /// Reads a block saved by [toJson]. An unknown kind reads as a verse, so a
  /// project saved by a newer version still opens.
  factory DrumSongBlock.fromJson(Map<String, dynamic> json) {
    final name = json['kind'] as String?;
    return DrumSongBlock(
      kind: DrumBlockKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => DrumBlockKind.verse,
      ),
      bars: ((json['bars'] as num?)?.toInt() ?? 8)
          .clamp(minBars, maxBars),
      fillAtEnd: (json['fillAtEnd'] as bool?) ?? true,
      variation: json['variation'] as String?,
      stopTransport: (json['stopTransport'] as bool?) ?? true,
    );
  }
}

/// Ready-made song forms offered by the "Templates" button, so a beginner
/// starts from a real song shape and edits it.
enum DrumSongTemplate {
  /// Verse, chorus, verse, chorus, bridge, chorus, ending.
  pop,

  /// Intro, verse, chorus, verse, chorus, ending.
  rock,

  /// Three 12-bar choruses, then the ending.
  blues,

  /// One verse that loops, for jamming.
  jam,
}

/// The shape of a song, played by the drum generator block after block.
///
/// Belongs to the slot, so it is saved with the project and kept when the
/// style changes. With [enabled] false the generator plays in phrases, as it
/// does without a form. A form loops unless it ends with an
/// [DrumBlockKind.ending] block; there is at most one, always last.
class DrumSongForm {
  /// Whether the drum generator follows this form.
  final bool enabled;

  /// The blocks, in playing order.
  final List<DrumSongBlock> blocks;

  /// Constructs a [DrumSongForm].
  const DrumSongForm({this.enabled = false, this.blocks = const []});

  /// The form a slot starts with when the user first turns it on.
  static DrumSongForm get starter => fromTemplate(DrumSongTemplate.pop);

  /// Builds the form of [template], turned on.
  static DrumSongForm fromTemplate(DrumSongTemplate template) {
    const v = DrumBlockKind.verse;
    const c = DrumBlockKind.chorus;
    const end = DrumSongBlock(kind: DrumBlockKind.ending);
    final blocks = switch (template) {
      DrumSongTemplate.pop => const [
          DrumSongBlock(kind: v),
          DrumSongBlock(kind: c),
          DrumSongBlock(kind: v),
          DrumSongBlock(kind: c),
          DrumSongBlock(kind: DrumBlockKind.bridge, bars: 4),
          DrumSongBlock(kind: c),
          end,
        ],
      DrumSongTemplate.rock => const [
          DrumSongBlock(kind: DrumBlockKind.intro, bars: 4),
          DrumSongBlock(kind: v),
          DrumSongBlock(kind: c),
          DrumSongBlock(kind: v),
          DrumSongBlock(kind: c),
          end,
        ],
      DrumSongTemplate.blues => const [
          DrumSongBlock(kind: v, bars: 12),
          DrumSongBlock(kind: v, bars: 12),
          DrumSongBlock(kind: v, bars: 12),
          end,
        ],
      DrumSongTemplate.jam => const [DrumSongBlock(kind: v)],
    };
    return DrumSongForm(enabled: true, blocks: blocks);
  }

  /// Whether the form ends with an ending block, so it stops instead of
  /// looping.
  bool get hasEnding =>
      blocks.isNotEmpty && blocks.last.kind == DrumBlockKind.ending;

  /// Whether the generator should follow the form.
  bool get isActive => enabled && blocks.isNotEmpty;

  /// A copy with the given fields replaced.
  DrumSongForm copyWith({bool? enabled, List<DrumSongBlock>? blocks}) =>
      DrumSongForm(
        enabled: enabled ?? this.enabled,
        blocks: blocks ?? this.blocks,
      );

  /// Adds a block of [kind]. A new block goes before the ending, and a
  /// second ending is ignored.
  DrumSongForm withAdded(DrumBlockKind kind) {
    if (kind == DrumBlockKind.ending) {
      if (hasEnding) return this;
      return copyWith(blocks: [...blocks, const DrumSongBlock(kind: DrumBlockKind.ending)]);
    }
    final block = DrumSongBlock(kind: kind, bars: defaultBars(kind));
    final at = hasEnding ? blocks.length - 1 : blocks.length;
    return copyWith(blocks: [...blocks]..insert(at, block));
  }

  /// Length a new block of [kind] starts with.
  static int defaultBars(DrumBlockKind kind) => switch (kind) {
        DrumBlockKind.intro => 4,
        DrumBlockKind.breakdown => 2,
        _ => 8,
      };

  /// Replaces the block at [index].
  DrumSongForm withReplaced(int index, DrumSongBlock block) =>
      copyWith(blocks: [...blocks]..[index] = block);

  /// Removes the block at [index].
  DrumSongForm withRemoved(int index) =>
      copyWith(blocks: [...blocks]..removeAt(index));

  /// Inserts a copy of the block at [index] right after it. The ending is
  /// never duplicated.
  DrumSongForm withDuplicated(int index) {
    if (blocks[index].kind == DrumBlockKind.ending) return this;
    return copyWith(blocks: [...blocks]..insert(index + 1, blocks[index]));
  }

  /// Moves the block at [from] to position [to] (in the list without it).
  /// The ending stays last: nothing moves onto or past it.
  DrumSongForm withMoved(int from, int to) {
    if (blocks[from].kind == DrumBlockKind.ending) return this;
    final list = [...blocks];
    final block = list.removeAt(from);
    final last = hasEnding ? list.length - 1 : list.length;
    list.insert(to.clamp(0, last), block);
    return copyWith(blocks: list);
  }

  /// Serialises this form to a JSON-compatible map.
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'blocks': [for (final b in blocks) b.toJson()],
      };

  /// Reads a form saved by [toJson]. Any ending that is not last is
  /// dropped, so the form keeps its rule of one ending, at the end.
  factory DrumSongForm.fromJson(Map<String, dynamic> json) {
    final raw = (json['blocks'] as List?) ?? const [];
    final blocks = [
      for (final b in raw)
        if (b is Map) DrumSongBlock.fromJson(b.cast<String, dynamic>()),
    ];
    final cleaned = [
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].kind != DrumBlockKind.ending || i == blocks.length - 1)
          blocks[i],
    ];
    return DrumSongForm(
      enabled: (json['enabled'] as bool?) ?? false,
      blocks: cleaned,
    );
  }
}
