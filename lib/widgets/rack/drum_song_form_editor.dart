import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/drum_generator_plugin_instance.dart';
import '../../models/drum_pattern_data.dart';
import '../../models/drum_song_form.dart';
import '../../services/drum_arranger.dart';
import '../../services/drum_form_arranger.dart';
import '../../services/drum_generator_engine.dart';
import '../../services/transport_engine.dart';

// ── Design tokens (shared with the drum slot) ─────────────────────────────────

const _kBg = Color(0xFF15151F);
const _kPanel = Color(0xFF1C1C2A);
const _kBorder = Color(0xFF2A2A3F);
const _kAccent = Colors.orangeAccent;
const _kMuted = Colors.white54;

/// Size of a block tile. Fixed, so lighting the block being played never
/// moves anything around it.
const _kBlockWidth = 92.0;
const _kBlockHeight = 66.0;

/// Stands in for a slot's play position before its session exists.
final ValueNotifier<DrumFormPosition?> _noPosition = ValueNotifier(null);

/// Below this width the blocks scroll sideways on one line; above, they
/// wrap onto several lines.
const _kWrapBreakpoint = 500.0;

/// The colour of each kind of block, so a song's shape reads at a glance.
Color blockColor(DrumBlockKind kind) => switch (kind) {
      DrumBlockKind.intro => const Color(0xFF7D8597),
      DrumBlockKind.verse => const Color(0xFF4F8EF7),
      DrumBlockKind.chorus => const Color(0xFFFF9F43),
      DrumBlockKind.bridge => const Color(0xFFA777E3),
      DrumBlockKind.breakdown => const Color(0xFFEF5D6C),
      DrumBlockKind.ending => const Color(0xFF3CC4B4),
    };

/// The localized name of a block kind.
String blockKindLabel(AppLocalizations l10n, DrumBlockKind kind) =>
    switch (kind) {
      DrumBlockKind.intro => l10n.drumFormKindIntro,
      DrumBlockKind.verse => l10n.drumFormKindVerse,
      DrumBlockKind.chorus => l10n.drumFormKindChorus,
      DrumBlockKind.bridge => l10n.drumFormKindBridge,
      DrumBlockKind.breakdown => l10n.drumFormKindBreak,
      DrumBlockKind.ending => l10n.drumFormKindEnding,
    };

// ── Editor ────────────────────────────────────────────────────────────────────

/// The song-form card of the drum generator slot: a row of coloured blocks
/// (intro, verse, chorus, bridge, break, ending) that the drummer plays one
/// after the other.
///
/// Tapping a block opens its settings below the row; a long press drags it
/// to another place. While the transport plays, the block being played is
/// outlined and its bar meter fills. Only those parts rebuild, and every
/// element keeps its size, so nothing on screen moves during playback.
class DrumSongFormEditor extends StatefulWidget {
  /// The drum slot whose form is edited.
  final DrumGeneratorPluginInstance plugin;

  const DrumSongFormEditor({super.key, required this.plugin});

  @override
  State<DrumSongFormEditor> createState() => _DrumSongFormEditorState();
}

class _DrumSongFormEditorState extends State<DrumSongFormEditor> {
  /// Index of the block whose settings are open, or -1.
  int _selected = -1;

  DrumSongForm get _form => widget.plugin.songForm;

  /// Stores [form] through the engine, which reschedules the coming bars
  /// and saves the project.
  void _apply(DrumSongForm form, {int? select}) {
    context.read<DrumGeneratorEngine>().setSongForm(widget.plugin.id, form);
    setState(() {
      _selected = select ?? _selected;
      if (_selected >= form.blocks.length) _selected = -1;
    });
  }

  void _toggleEnabled(bool on) {
    // The first time the form is turned on, start from a real song shape
    // rather than an empty row.
    final form = on && _form.blocks.isEmpty
        ? DrumSongForm.starter
        : _form.copyWith(enabled: on);
    _apply(form, select: -1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final engine = context.read<DrumGeneratorEngine>();
    final pattern = engine.patternFor(widget.plugin.id);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(l10n),
          if (!_form.enabled)
            Text(l10n.drumFormOffHint,
                style: const TextStyle(fontSize: 12, color: _kMuted))
          else
            ..._body(l10n, engine, pattern),
        ],
      ),
    );
  }

  Widget _header(AppLocalizations l10n) {
    return Row(
      children: [
        Switch(
          value: _form.enabled,
          activeThumbColor: _kAccent,
          onChanged: _toggleEnabled,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(l10n.drumFormTitle,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
        if (_form.enabled) _TemplateMenu(onPicked: (t) => _apply(
            DrumSongForm.fromTemplate(t), select: -1)),
      ],
    );
  }

  List<Widget> _body(
    AppLocalizations l10n,
    DrumGeneratorEngine engine,
    DrumPatternData? pattern,
  ) {
    final position = engine.formPositionFor(widget.plugin.id) ?? _noPosition;
    return [
      const SizedBox(height: 6),
      _BlockRow(
        form: _form,
        pattern: pattern,
        selected: _selected,
        position: position,
        onTap: (i) => setState(() => _selected = _selected == i ? -1 : i),
        onMove: (from, to) => _apply(_form.withMoved(from, to), select: -1),
        onAdd: (kind) => _apply(_form.withAdded(kind), select: -1),
      ),
      if (_selected >= 0 && _selected < _form.blocks.length) ...[
        const SizedBox(height: 8),
        _BlockSheet(
          index: _selected,
          form: _form,
          pattern: pattern,
          onChanged: (form, select) => _apply(form, select: select),
          onClose: () => setState(() => _selected = -1),
        ),
      ],
      const SizedBox(height: 8),
      _StatusLine(
        form: _form,
        pattern: pattern,
        config: widget.plugin.structureConfig,
        position: position,
      ),
      const SizedBox(height: 2),
      Text(
        _form.blocks.isEmpty
            ? l10n.drumFormEmpty
            : (_form.hasEnding ? l10n.drumFormStops : l10n.drumFormLoops),
        style: const TextStyle(fontSize: 11.5, color: _kMuted),
      ),
    ];
  }
}

// ── Templates ─────────────────────────────────────────────────────────────────

/// The "Templates" button: fills the form with a ready-made song shape.
class _TemplateMenu extends StatelessWidget {
  final ValueChanged<DrumSongTemplate> onPicked;

  const _TemplateMenu({required this.onPicked});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final labels = {
      DrumSongTemplate.pop: l10n.drumFormTemplatePop,
      DrumSongTemplate.rock: l10n.drumFormTemplateRock,
      DrumSongTemplate.blues: l10n.drumFormTemplateBlues,
      DrumSongTemplate.jam: l10n.drumFormTemplateJam,
    };
    return PopupMenuButton<DrumSongTemplate>(
      tooltip: l10n.drumFormTemplatesHint,
      color: _kPanel,
      onSelected: onPicked,
      itemBuilder: (_) => [
        for (final e in labels.entries)
          PopupMenuItem(
            value: e.key,
            child: Text(e.value,
                style: const TextStyle(fontSize: 13, color: Colors.white)),
          ),
      ],
      child: _Pill(label: l10n.drumFormTemplates),
    );
  }
}

/// A small rounded outlined label, used as a button face.
class _Pill extends StatelessWidget {
  final String label;

  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kBorder),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12.5, color: Colors.white)),
    );
  }
}

// ── Block row ─────────────────────────────────────────────────────────────────

/// The blocks of the form, then the "+" button.
///
/// Phone width: one line that scrolls sideways. Wider: the blocks wrap onto
/// several lines. Either way a long press drags a block onto another one to
/// take its place.
class _BlockRow extends StatelessWidget {
  final DrumSongForm form;
  final DrumPatternData? pattern;
  final int selected;
  final ValueListenable<DrumFormPosition?> position;
  final ValueChanged<int> onTap;
  final void Function(int from, int to) onMove;
  final ValueChanged<DrumBlockKind> onAdd;

  const _BlockRow({
    required this.form,
    required this.pattern,
    required this.selected,
    required this.position,
    required this.onTap,
    required this.onMove,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (var i = 0; i < form.blocks.length; i++) _draggable(i),
      _AddButton(form: form, onAdd: onAdd),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth >= _kWrapBreakpoint) {
        return Wrap(spacing: 8, runSpacing: 8, children: tiles);
      }
      return SizedBox(
        height: _kBlockHeight + 4,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: tiles.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => tiles[i],
        ),
      );
    });
  }

  /// Block [i] as a drag source and a drop target. The ending never moves.
  Widget _draggable(int i) {
    final block = form.blocks[i];
    final tile = _BlockTile(
      index: i,
      block: block,
      bars: pattern == null ? block.bars : DrumFormArranger.blockBars(block, pattern!),
      selected: i == selected,
      position: position,
      onTap: () => onTap(i),
    );
    final target = DragTarget<int>(
      onWillAcceptWithDetails: (d) => d.data != i,
      onAcceptWithDetails: (d) => onMove(d.data, i),
      builder: (context, candidates, _) => Opacity(
        opacity: candidates.isEmpty ? 1 : 0.6,
        child: tile,
      ),
    );
    if (block.kind == DrumBlockKind.ending) return target;
    return LongPressDraggable<int>(
      data: i,
      feedback: Material(color: Colors.transparent, child: tile),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: target,
    );
  }
}

/// One block: its name, length, end tag (FILL or STOP) and a meter with one
/// tick per bar, lit up to the bar being played.
class _BlockTile extends StatelessWidget {
  final int index;
  final DrumSongBlock block;
  final int bars;
  final bool selected;
  final ValueListenable<DrumFormPosition?> position;
  final VoidCallback onTap;

  const _BlockTile({
    required this.index,
    required this.block,
    required this.bars,
    required this.selected,
    required this.position,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = blockColor(block.kind);
    final tag = block.kind == DrumBlockKind.ending
        ? (block.stopTransport ? l10n.drumFormTagStop : null)
        : (block.fillAtEnd ? l10n.drumFormTagFill : null);
    return ValueListenableBuilder<DrumFormPosition?>(
      valueListenable: position,
      builder: (context, pos, _) {
        final playing = pos != null && pos.block == index;
        return GestureDetector(
          onTap: onTap,
          child: Container(
            width: _kBlockWidth,
            height: _kBlockHeight,
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withValues(alpha: 0.16), _kBg),
              borderRadius: BorderRadius.circular(10),
              // Same width lit or not: only the colour changes.
              border: Border.all(
                width: 2,
                color: selected
                    ? Colors.white
                    : (playing ? color : color.withValues(alpha: 0.5)),
              ),
            ),
            child: Stack(children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // One line each, whatever the language: a wrapped name
                  // would push the bar meter out of the fixed-size tile.
                  Text(blockKindLabel(l10n, block.kind),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                  Text(l10n.drumFormBarCount(bars),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(fontSize: 12, color: _kMuted)),
                  const Spacer(),
                  _BarMeter(
                    bars: bars,
                    lit: playing ? pos.bar + 1 : 0,
                    lastIsFill: block.fillAtEnd &&
                        block.kind != DrumBlockKind.ending,
                    color: color,
                  ),
                ],
              ),
              if (tag != null)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Text(tag,
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// A row of [bars] ticks; the first [lit] are bright. The last tick is a
/// little brighter when the block ends with a fill.
class _BarMeter extends StatelessWidget {
  final int bars;
  final int lit;
  final bool lastIsFill;
  final Color color;

  const _BarMeter({
    required this.bars,
    required this.lit,
    required this.lastIsFill,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: Row(children: [
        for (var j = 0; j < bars; j++) ...[
          if (j > 0) const SizedBox(width: 2),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: j < lit
                    ? color
                    : color.withValues(
                        alpha: lastIsFill && j == bars - 1 ? 0.55 : 0.25),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// The "+" button, with a menu of block kinds. The ending is offered only
/// while the form has none.
class _AddButton extends StatelessWidget {
  final DrumSongForm form;
  final ValueChanged<DrumBlockKind> onAdd;

  const _AddButton({required this.form, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopupMenuButton<DrumBlockKind>(
      tooltip: l10n.drumFormAddBlock,
      color: _kPanel,
      onSelected: onAdd,
      itemBuilder: (_) => [
        for (final kind in DrumBlockKind.values)
          if (kind != DrumBlockKind.ending || !form.hasEnding)
            PopupMenuItem(
              value: kind,
              child: Row(children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: blockColor(kind),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Text(blockKindLabel(l10n, kind),
                    style: const TextStyle(fontSize: 13, color: Colors.white)),
              ]),
            ),
      ],
      child: Container(
        width: 52,
        height: _kBlockHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kBorder, width: 1.5),
        ),
        child: const Icon(Icons.add, color: _kMuted),
      ),
    );
  }
}

// ── Block settings ────────────────────────────────────────────────────────────

/// Settings of the selected block: kind, length, fill, groove variation (or,
/// for the ending, whether the transport stops), and the move / duplicate /
/// delete buttons.
class _BlockSheet extends StatelessWidget {
  final int index;
  final DrumSongForm form;
  final DrumPatternData? pattern;
  final void Function(DrumSongForm form, int? select) onChanged;
  final VoidCallback onClose;

  const _BlockSheet({
    required this.index,
    required this.form,
    required this.pattern,
    required this.onChanged,
    required this.onClose,
  });

  DrumSongBlock get _block => form.blocks[index];

  void _set(DrumSongBlock block) => onChanged(form.withReplaced(index, block), null);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEnding = _block.kind == DrumBlockKind.ending;
    final hint = _hint(l10n);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                l10n.drumFormBlockTitle(index + 1, blockKindLabel(l10n, _block.kind)),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
            TextButton(onPressed: onClose, child: Text(l10n.drumFormClose)),
          ]),
          if (!isEnding) ...[
            _label(l10n.drumFormType),
            _kindChips(l10n),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 18,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: isEnding ? [_stopSwitch(l10n)] : _blockFields(l10n),
          ),
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint, style: const TextStyle(fontSize: 12, color: _kMuted)),
          ],
          const SizedBox(height: 8),
          _actions(l10n, isEnding),
          if (!isEnding) ...[
            const SizedBox(height: 6),
            Text(l10n.drumFormDragHint,
                style: const TextStyle(fontSize: 11.5, color: _kMuted)),
          ],
        ],
      ),
    );
  }

  String? _hint(AppLocalizations l10n) => switch (_block.kind) {
        DrumBlockKind.intro => l10n.drumFormHintIntro,
        DrumBlockKind.breakdown => l10n.drumFormHintBreak,
        DrumBlockKind.ending => l10n.drumFormHintEnding,
        _ => null,
      };

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: const TextStyle(fontSize: 11.5, color: _kMuted)),
      );

  /// One chip per kind except the ending, which is added with "+" only.
  Widget _kindChips(AppLocalizations l10n) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final kind in DrumBlockKind.values)
        if (kind != DrumBlockKind.ending)
          ChoiceChip(
            label: Text(blockKindLabel(l10n, kind)),
            selected: kind == _block.kind,
            selectedColor: blockColor(kind).withValues(alpha: 0.35),
            backgroundColor: _kPanel,
            labelStyle: const TextStyle(fontSize: 12.5, color: Colors.white),
            side: BorderSide(color: blockColor(kind).withValues(alpha: 0.6)),
            showCheckmark: false,
            onSelected: (_) =>
                _set(_block.copyWith(kind: kind, clearVariation: true)),
          ),
    ]);
  }

  List<Widget> _blockFields(AppLocalizations l10n) {
    final groove = pattern?.sections['groove'];
    final auto = groove == null
        ? null
        : DrumFormArranger.autoVariation(groove, _block.kind);
    return [
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _label(l10n.drumFormBars),
        _BarsStepper(
          value: _block.bars,
          onChanged: (v) => _set(_block.copyWith(bars: v)),
        ),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _label(l10n.drumFormFillAtEnd),
        Switch(
          value: _block.fillAtEnd,
          activeThumbColor: _kAccent,
          onChanged: (v) => _set(_block.copyWith(fillAtEnd: v)),
        ),
      ]),
      // A break plays the style's break, and a sequence groove plays its
      // bars in order: neither has a groove variation to pick.
      if (auto != null && _block.kind != DrumBlockKind.breakdown)
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _label(l10n.drumFormVariation),
          _variationDropdown(l10n, groove!, auto),
        ]),
    ];
  }

  Widget _variationDropdown(
    AppLocalizations l10n,
    DrumSection groove,
    String auto,
  ) {
    final names = groove.variations.map((v) => v.name).toList();
    final current = names.contains(_block.variation) ? _block.variation : null;
    return DropdownButton<String?>(
      value: current,
      dropdownColor: _kPanel,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      underline: Container(height: 1, color: _kBorder),
      items: [
        DropdownMenuItem(value: null, child: Text(l10n.drumFormVariationAuto(auto))),
        for (final name in names) DropdownMenuItem(value: name, child: Text(name)),
      ],
      onChanged: (v) => _set(v == null
          ? _block.copyWith(clearVariation: true)
          : _block.copyWith(variation: v)),
    );
  }

  Widget _stopSwitch(AppLocalizations l10n) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      _label(l10n.drumFormStopTransport),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Switch(
          value: _block.stopTransport,
          activeThumbColor: _kAccent,
          onChanged: (v) => _set(_block.copyWith(stopTransport: v)),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(l10n.drumFormStopTransportHint,
              style: const TextStyle(fontSize: 12, color: _kMuted)),
        ),
      ]),
    ]);
  }

  /// Move earlier / later, duplicate, delete. The ending can only be
  /// deleted: it stays last and there is only one.
  Widget _actions(AppLocalizations l10n, bool isEnding) {
    final lastMovable = form.blocks.length - (form.hasEnding ? 2 : 1);
    return Wrap(spacing: 6, runSpacing: 6, children: [
      if (!isEnding) ...[
        _action(Icons.arrow_back, l10n.drumFormMoveEarlier,
            index > 0 ? () => onChanged(form.withMoved(index, index - 1), index - 1) : null),
        _action(Icons.arrow_forward, l10n.drumFormMoveLater,
            index < lastMovable ? () => onChanged(form.withMoved(index, index + 1), index + 1) : null),
        _action(Icons.copy, l10n.drumFormDuplicate,
            () => onChanged(form.withDuplicated(index), index + 1)),
      ],
      _action(Icons.delete_outline, l10n.drumFormDelete,
          () => onChanged(form.withRemoved(index), -1),
          danger: true),
    ]);
  }

  Widget _action(IconData icon, String label, VoidCallback? onPressed,
      {bool danger = false}) {
    final color = danger ? const Color(0xFFEF5D6C) : Colors.white;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: const BorderSide(color: _kBorder),
        textStyle: const TextStyle(fontSize: 12.5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// − value + buttons for a block's length in bars.
class _BarsStepper extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _BarsStepper({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _button(Icons.remove,
          value > DrumSongBlock.minBars ? () => onChanged(value - 1) : null),
      SizedBox(
        width: 34,
        child: Text('$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFeatures: [FontFeature.tabularFigures()])),
      ),
      _button(Icons.add,
          value < DrumSongBlock.maxBars ? () => onChanged(value + 1) : null),
    ]);
  }

  Widget _button(IconData icon, VoidCallback? onPressed) => IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: Colors.white,
        style: IconButton.styleFrom(
          side: const BorderSide(color: _kBorder),
          backgroundColor: _kPanel,
        ),
        visualDensity: VisualDensity.compact,
      );
}

// ── Status line ───────────────────────────────────────────────────────────────

/// One line under the blocks: the form's size and duration when stopped,
/// the block and bar being played when playing, and a tag (FILL, CRASH,
/// BREAK, END) for what the drummer does in this bar.
///
/// Fixed height, text cut with an ellipsis, and the tag keeps its place
/// even when empty, so this line never changes size during playback.
class _StatusLine extends StatelessWidget {
  final DrumSongForm form;
  final DrumPatternData? pattern;
  final DrumStructureConfig config;
  final ValueListenable<DrumFormPosition?> position;

  const _StatusLine({
    required this.form,
    required this.pattern,
    required this.config,
    required this.position,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bpm = context.select<TransportEngine, int>((t) => t.bpm.round());
    return SizedBox(
      height: 22,
      child: ValueListenableBuilder<DrumFormPosition?>(
        valueListenable: position,
        builder: (context, pos, _) {
          final event = pos == null ? null : _event(l10n, pos);
          return Row(children: [
            Expanded(
              child: Text(
                pos == null ? _summary(l10n, bpm) : _playing(l10n, pos),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.white70,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 56,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: event == null ? Colors.transparent : _kBorder,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(event ?? '',
                  style: const TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
            ),
          ]);
        },
      ),
    );
  }

  String _summary(AppLocalizations l10n, int bpm) {
    final bars = pattern == null
        ? form.blocks.fold(0, (s, b) => s + b.bars)
        : DrumFormArranger.formBars(form, pattern!);
    final beatsPerBar = pattern == null
        ? 4.0
        : pattern!.timeSigNumerator * 4.0 / pattern!.timeSigDenominator;
    final seconds = bpm <= 0 ? 0 : (bars * beatsPerBar * 60 / bpm).round();
    final duration =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return l10n.drumFormSummary(form.blocks.length, bars, duration, bpm);
  }

  String _playing(AppLocalizations l10n, DrumFormPosition pos) {
    if (pos.block >= form.blocks.length) return '';
    final block = form.blocks[pos.block];
    final bars = pattern == null
        ? block.bars
        : DrumFormArranger.blockBars(block, pattern!);
    return l10n.drumFormPlaying(pos.block + 1, form.blocks.length,
        blockKindLabel(l10n, block.kind), pos.bar + 1, bars);
  }

  /// What the drummer plays in the current bar, when it is not plain groove.
  String? _event(AppLocalizations l10n, DrumFormPosition pos) {
    final p = pattern;
    if (p == null || pos.block >= form.blocks.length) return null;
    var rel = pos.bar;
    for (var i = 0; i < pos.block; i++) {
      rel += DrumFormArranger.blockBars(form.blocks[i], p);
    }
    final plan = DrumFormArranger.planBar(
      rel: rel,
      afterCountIn: DrumArranger.introBarCount(config, p) > 0,
      form: form,
      config: config,
      pattern: p,
      seed: 0,
    );
    if (form.blocks[pos.block].kind == DrumBlockKind.ending) {
      return l10n.drumFormEventEnd;
    }
    return switch (plan.section) {
      'fill' => l10n.drumFormEventFill,
      'break' || DrumBarPlan.drop || DrumBarPlan.silence =>
        l10n.drumFormEventBreak,
      _ => plan.crash ? l10n.drumFormEventCrash : null,
    };
  }
}
