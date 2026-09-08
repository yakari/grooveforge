import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/chord_symbol.dart';
import '../models/rehearsal.dart';

/// The tune's form: one cell per bar, the current one lit.
///
/// Two shapes, one widget. Collapsed it is a single line that scrolls itself
/// to keep up with the transport — what a player glances at while playing.
/// Expanded it is the whole chart, wrapped, and every bar can be edited.
///
/// Chords are stored as the text somebody typed and validated through
/// [ChordSymbol], which is also what would drive a keyboard or a fretboard
/// later. Nothing here rewrites what was written.
class ChordGrid extends StatefulWidget {
  const ChordGrid({
    super.key,
    required this.rehearsal,
    required this.currentBar,
    required this.isRunning,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
  });

  final Rehearsal rehearsal;

  /// One-based, as the transport counts. Zero when stopped.
  final int currentBar;

  final bool isRunning;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// Called with the new form whenever the chart is edited.
  final void Function(List<RehearsalBar>) onChanged;

  @override
  State<ChordGrid> createState() => _ChordGridState();
}

class _ChordGridState extends State<ChordGrid> {
  final _scroll = ScrollController();

  /// Set once the player scrolls the collapsed line by hand.
  ///
  /// Following the transport is helpful right up to the moment somebody wants
  /// to look somewhere else, and a strip that keeps yanking itself back is
  /// worse than one that never moved.
  bool _userScrolled = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChordGrid old) {
    super.didUpdateWidget(old);
    // Starting the transport is a fresh intention: follow again.
    if (widget.isRunning && !old.isRunning) _userScrolled = false;
    if (widget.currentBar != old.currentBar) _followTransport();
  }

  /// Keeps the playing bar on screen while collapsed.
  void _followTransport() {
    if (widget.expanded || _userScrolled || !widget.isRunning) return;
    if (!_scroll.hasClients) return;
    final bar = widget.currentBar - 1;
    if (bar < 0 || bar >= _bars.length) return;
    // One bar of lead-in, because a player reads ahead: a strip that centres
    // the bar being played shows the past as prominently as the future.
    final target = (_offsetOf(bar > 0 ? bar - 1 : 0))
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Width of a bar cell holding [division] chords.
  ///
  /// A bar of four needs more room than a bar of one. Giving every bar the
  /// same width made a four-chord bar scale its text down to nothing —
  /// `Em7#5 B69 GmM7 C6/9` in the space of a single chord is not readable,
  /// which defeats the point of a chart.
  static double _widthFor(int division) => 84.0 + 52.0 * (division - 1);

  /// Where a bar starts along the strip, in pixels.
  double _offsetOf(int index) {
    var x = 0.0;
    for (var i = 0; i < index && i < _bars.length; i++) {
      x += _widthFor(_bars[i].division);
    }
    return x;
  }

  List<RehearsalBar> get _bars => widget.rehearsal.chords;

  void _edit(int index) async {
    final updated = await showDialog<RehearsalBar>(
      context: context,
      builder: (_) => _BarEditor(
        bar: _bars[index],
        barNumber: index + 1,
        beatsPerBar: widget.rehearsal.beatsPerBar,
      ),
    );
    if (updated == null) return;
    final next = [for (final b in _bars) b.copy()];
    next[index] = updated;
    widget.onChanged(next);
  }

  void _addBar() {
    // A new bar inherits the division of the one before it: a chart written in
    // halves stays in halves without being asked again every bar.
    final division = _bars.isEmpty ? 1 : _bars.last.division;
    widget.onChanged([
      for (final b in _bars) b.copy(),
      RehearsalBar(slots: List<String?>.filled(division, null)),
    ]);
  }

  void _removeBar(int index) {
    final next = [for (final b in _bars) b.copy()]..removeAt(index);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    if (_bars.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addBar,
            icon: const Icon(Icons.grid_on, size: 18),
            label: Text(l10n.rehearsalChordGridEmpty),
          ),
        ),
      );
    }

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.expanded) _expandedChart(theme) else _collapsedStrip(),
          _toolbar(l10n, theme),
        ],
      ),
    );
  }

  /// One line, scrolling itself, showing as many bars as the screen allows.
  Widget _collapsedStrip() {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (n) {
        if (n.dragDetails != null) _userScrolled = true;
        return false;
      },
      child: SizedBox(
        height: 46,
        child: ListView.builder(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          // One past the end: the last cell adds a bar. Collapsed is the
          // state the grid spends most of its life in, and writing a chart
          // should not mean unfolding it first.
          itemCount: _bars.length + 1,
          itemBuilder: (_, i) {
            if (i == _bars.length) {
              return SizedBox(
                width: 56,
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: OutlinedButton(
                    onPressed: _addBar,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Icon(Icons.add, size: 18),
                  ),
                ),
              );
            }
            return SizedBox(
              width: _widthFor(_bars[i].division),
              child: _BarCell(
                bar: _bars[i],
                number: i + 1,
                playing: widget.currentBar == i + 1,
                compact: true,
                onTap: () => _edit(i),
              ),
            );
          },
        ),
      ),
    );
  }

  /// The whole chart, as many bars per row as fit.
  Widget _expandedChart(ThemeData theme) {
    return ConstrainedBox(
      // Capped so a long form cannot push the transport and the lanes off the
      // screen; past this it scrolls within itself.
      constraints: const BoxConstraints(maxHeight: 260),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              children: [
                for (var i = 0; i < _bars.length; i++)
                  SizedBox(
                    // Never wider than the row, so a bar of four on a narrow
                    // screen takes a line to itself rather than overflowing.
                    width: _widthFor(_bars[i].division)
                        .clamp(0.0, constraints.maxWidth),
                    height: 56,
                    child: _BarCell(
                      bar: _bars[i],
                      number: i + 1,
                      playing: widget.currentBar == i + 1,
                      compact: false,
                      onTap: () => _edit(i),
                      onLongPress: () => _removeBar(i),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _toolbar(AppLocalizations l10n, ThemeData theme) {
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: widget.onToggleExpanded,
          tooltip: widget.expanded
              ? l10n.rehearsalChordCollapse
              : l10n.rehearsalChordExpand,
          icon: Icon(
            widget.expanded ? Icons.unfold_less : Icons.unfold_more,
            size: 18,
          ),
        ),
        Text(
          // A count, not a position: "Bar 4" and "4 bars" are different
          // things and the ordinal string said the wrong one.
          l10n.rehearsalChordBarCount(_bars.length),
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: _addBar,
          tooltip: l10n.rehearsalChordAddBar,
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    );
  }
}

/// One bar: its chords, and whether it is the one being played.
class _BarCell extends StatelessWidget {
  const _BarCell({
    required this.bar,
    required this.number,
    required this.playing,
    required this.compact,
    required this.onTap,
    this.onLongPress,
  });

  final RehearsalBar bar;
  final int number;
  final bool playing;
  final bool compact;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: playing
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                for (var i = 0; i < bar.slots.length; i++) ...[
                  if (i > 0)
                    // A hairline between beats. Without it a bar of four reads
                    // as one long word.
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  Expanded(
                    child: Center(
                      child: Text(
                        // An empty slot is a continuation, which a chart draws
                        // as a stroke rather than as nothing — the difference
                        // between "hold" and "we never wrote it".
                        _label(bar.slots[i]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        // One size for every chord in the bar, rather than a
                        // box that scales each to its own width: independent
                        // scaling made a long symbol tiny beside a short one,
                        // and neither was readable.
                        style: (compact
                                ? theme.textTheme.bodyMedium
                                : theme.textTheme.titleMedium)
                            ?.copyWith(
                          color: playing
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What to draw in a slot: the chord, a continuation stroke, or nothing.
  String _label(String? slot) {
    if (slot == null || slot.isEmpty) return bar.isEmpty ? '·' : '/';
    return ChordSymbol.parse(slot)?.display ?? slot;
  }
}

/// Raises the letters that are always note names, and leaves the rest alone.
///
/// A chord symbol is upper case exactly where a note is named — its root, and
/// the bass after a slash — and lower case almost everywhere else: `m`, `sus`,
/// `dim`, `add`. A keyboard set to capitalise every character makes the common
/// case impossible to type.
class _ChordCasing extends TextInputFormatter {
  const _ChordCasing();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue previous,
    TextEditingValue next,
  ) {
    final chars = next.text.split('');
    for (var i = 0; i < chars.length; i++) {
      final isRoot = i == 0;
      final isBass = i > 0 && chars[i - 1] == '/';
      if (isRoot || isBass) chars[i] = chars[i].toUpperCase();
    }
    // The length never changes, so the caret and any selection stay put.
    return next.copyWith(text: chars.join());
  }
}

/// The casing rule, for tests. See [_ChordCasing].
const TextInputFormatter chordCasingForTesting = _ChordCasing();

/// Writes the chords of one bar.
class _BarEditor extends StatefulWidget {
  const _BarEditor({
    required this.bar,
    required this.barNumber,
    required this.beatsPerBar,
  });

  final RehearsalBar bar;
  final int barNumber;
  final int beatsPerBar;

  @override
  State<_BarEditor> createState() => _BarEditorState();
}

class _BarEditorState extends State<_BarEditor> {
  late RehearsalBar _bar = widget.bar.copy();
  late List<TextEditingController> _fields = _controllersFor(_bar);

  List<TextEditingController> _controllersFor(RehearsalBar bar) => [
        for (final slot in bar.slots)
          TextEditingController(text: slot ?? ''),
      ];

  /// Divisions a bar of this metre can be written in.
  ///
  /// Divisors of the beat count, so every slot lands on a beat. A chord
  /// between beats is not something a chart notates or a player could read.
  List<int> get _divisions {
    final beats = widget.beatsPerBar;
    return [
      for (var d = 1; d <= beats; d++)
        if (beats % d == 0) d,
    ];
  }

  void _setDivision(int division) {
    setState(() {
      _commit();
      _bar = _bar.withDivision(division);
      for (final c in _fields) {
        c.dispose();
      }
      _fields = _controllersFor(_bar);
    });
  }

  /// Copies what is typed into the bar.
  void _commit() {
    for (var i = 0; i < _fields.length && i < _bar.slots.length; i++) {
      final text = _fields[i].text.trim();
      _bar.slots[i] = text.isEmpty ? null : text;
    }
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(l10n.rehearsalChordBar(widget.barNumber)),
      // Scrollable and capped: four chord fields plus a software keyboard is
      // taller than a phone, and a dialog that overflows loses its buttons.
      content: SizedBox(
        width: 420,
        height: (MediaQuery.of(context).size.height * 0.4).clamp(160.0, 380.0),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_divisions.length > 1) ...[
              Text(l10n.rehearsalChordSlots,
                  style: theme.textTheme.labelSmall),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: [
                  for (final d in _divisions)
                    ButtonSegment(value: d, label: Text('$d')),
                ],
                selected: {_bar.division},
                showSelectedIcon: false,
                onSelectionChanged: (v) => _setDivision(v.first),
              ),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < _fields.length; i++) ...[
              TextField(
                controller: _fields[i],
                autofocus: i == 0,
                decoration: InputDecoration(
                  labelText: _fields.length == 1
                      ? l10n.rehearsalChordGrid
                      // Which beat this slot falls on, so a four-slot bar
                      // reads as beats rather than as boxes.
                      : '${1 + i * widget.beatsPerBar ~/ _fields.length}',
                  hintText: i == 0 ? l10n.rehearsalChordHint : null,
                  // Nothing is rejected while typing — a half-finished chord
                  // is not a mistake — but a symbol nobody could read is
                  // pointed out before it goes onto the chart.
                  errorText: _fields[i].text.trim().isNotEmpty &&
                          !ChordSymbol.isValid(_fields[i].text.trim())
                      ? l10n.rehearsalChordInvalid
                      : null,
                ),
                // Not `characters`, which forced every letter upper case and
                // made `Abm7sus4` all but untypable. Only the positions that
                // are always a note name are raised: the root, and whatever
                // follows a slash, so `C/G` needs no shift key either.
                textCapitalization: TextCapitalization.none,
                inputFormatters: const [_ChordCasing()],
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
            ],
          ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.rehearsalCancel),
        ),
        FilledButton(
          onPressed: () {
            _commit();
            Navigator.pop(context, _bar);
          },
          child: Text(l10n.rehearsalChordSave),
        ),
      ],
    );
  }
}
