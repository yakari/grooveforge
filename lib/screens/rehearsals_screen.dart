import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../services/rehearsal_library.dart';
import 'rehearsal_screen.dart';

/// Localized label for an instrument id from [kInstruments].
///
/// Kept as a switch over the id rather than a field on the model so the model
/// stays presentation-free — CLAUDE.md Rule 4 forbids calling `.toString()` on
/// a domain object for display.
String instrumentLabel(AppLocalizations l10n, String id) => switch (id) {
      'vocals' => l10n.instrumentVocals,
      'guitar' => l10n.instrumentGuitar,
      'electricGuitar' => l10n.instrumentElectricGuitar,
      'bassGuitar' => l10n.instrumentBassGuitar,
      'drums' => l10n.instrumentDrums,
      'keyboard' => l10n.instrumentKeyboard,
      'synth' => l10n.instrumentSynth,
      'violin' => l10n.instrumentViolin,
      'saxophone' => l10n.instrumentSaxophone,
      'trumpet' => l10n.instrumentTrumpet,
      'percussion' => l10n.instrumentPercussion,
      _ => l10n.instrumentOther,
    };

/// An icon standing in for an instrument, so a lane is recognisable at a
/// glance rather than only by reading its label.
IconData instrumentIcon(String id) => switch (id) {
      'vocals' => Icons.mic_none,
      'guitar' || 'electricGuitar' => Icons.music_note,
      'bassGuitar' => Icons.graphic_eq,
      'drums' || 'percussion' => Icons.album,
      'keyboard' || 'synth' => Icons.piano,
      'violin' => Icons.queue_music,
      'saxophone' || 'trumpet' => Icons.audiotrack,
      _ => Icons.library_music,
    };

/// The rehearsal library: every tune this device knows about.
class RehearsalsScreen extends StatefulWidget {
  const RehearsalsScreen({super.key});

  @override
  State<RehearsalsScreen> createState() => _RehearsalsScreenState();
}

class _RehearsalsScreenState extends State<RehearsalsScreen> {
  @override
  void initState() {
    super.initState();
    // The library reads the filesystem, so it is loaded once on first build
    // rather than in the provider's constructor, which runs before the app has
    // a documents directory on some platforms.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final library = context.read<RehearsalLibrary>();
      if (!library.isLoaded) library.load();
    });
  }

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<_CreateResult>(
      context: context,
      builder: (_) => const _CreateRehearsalDialog(),
    );
    if (result == null || !mounted) return;

    final library = context.read<RehearsalLibrary>();
    final rehearsal = await library.create(
      title: result.title.trim().isEmpty ? l10n.rehearsalCreateTitle : result.title,
      memberName: result.memberName,
      instrument: result.instrument,
      bpm: result.bpm,
      beatsPerBar: result.beatsPerBar,
      countInBars: result.countInBars,
    );
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RehearsalScreen(rehearsalId: rehearsal.id),
    ));
  }

  Future<void> _confirmDelete(Rehearsal rehearsal) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.rehearsalDeleteConfirm(rehearsal.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.rehearsalCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.rehearsalDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<RehearsalLibrary>().delete(rehearsal.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final library = context.watch<RehearsalLibrary>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.rehearsalsTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(l10n.rehearsalsNew),
      ),
      body: SafeArea(
        top: false,
        child: library.rehearsals.isEmpty
            ? _EmptyState(loaded: library.isLoaded)
            : LayoutBuilder(
                builder: (context, constraints) {
                  // One column on a phone; a grid once there is room, so a
                  // laptop does not show a single 1600 px-wide card.
                  final columns = constraints.maxWidth >= 1280
                      ? 3
                      : constraints.maxWidth >= 800
                          ? 2
                          : 1;
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 132,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: library.rehearsals.length,
                    itemBuilder: (_, i) {
                      final r = library.rehearsals[i];
                      return _RehearsalCard(
                        rehearsal: r,
                        onOpen: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RehearsalScreen(rehearsalId: r.id),
                          ),
                        ),
                        onDelete: () => _confirmDelete(r),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.loaded});

  final bool loaded;

  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups_outlined,
                  size: 64, color: theme.colorScheme.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(l10n.rehearsalsEmpty, style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                l10n.rehearsalsEmptyHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One rehearsal in the library.
class _RehearsalCard extends StatelessWidget {
  const _RehearsalCard({
    required this.rehearsal,
    required this.onOpen,
    required this.onDelete,
  });

  final Rehearsal rehearsal;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  /// A stable hue per rehearsal, derived from its id, so a card is
  /// recognisable before its title has been read.
  Color _accent(BuildContext context) {
    var hash = 0;
    for (final c in rehearsal.id.codeUnits) {
      hash = (hash * 31 + c) & 0x7FFFFFFF;
    }
    return HSLColor.fromAHSL(1.0, (hash % 360).toDouble(), 0.55, 0.55).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final accent = _accent(context);
    final done = rehearsal.recordedPartCount;
    final total = rehearsal.parts.length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Row(
          children: [
            Container(width: 6, height: double.infinity, color: accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      rehearsal.title,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.rehearsalBpmValue(rehearsal.bpm.toStringAsFixed(0))}'
                      '   ·   '
                      '${l10n.rehearsalMeter(rehearsal.beatsPerBar, rehearsal.beatUnit)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: total == 0 ? 0 : done / total,
                            strokeWidth: 3,
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation(accent),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            l10n.rehearsalPartsProgress(done, total),
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: l10n.rehearsalDelete,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// What the create dialog returns.
class _CreateResult {
  _CreateResult(this.title, this.memberName, this.instrument, this.bpm,
      this.beatsPerBar, this.countInBars);

  final String title;
  final String memberName;
  final String instrument;
  final double bpm;
  final int beatsPerBar;
  final int countInBars;
}

class _CreateRehearsalDialog extends StatefulWidget {
  const _CreateRehearsalDialog();

  @override
  State<_CreateRehearsalDialog> createState() => _CreateRehearsalDialogState();
}

class _CreateRehearsalDialogState extends State<_CreateRehearsalDialog> {
  final _title = TextEditingController();
  final _name = TextEditingController();
  String _instrument = 'guitar';
  double _bpm = 120;
  int _beatsPerBar = 4;
  int _countInBars = 2;

  @override
  void dispose() {
    _title.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.rehearsalCreateTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.rehearsalFieldTitle,
                  hintText: l10n.rehearsalFieldTitleHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration:
                    InputDecoration(labelText: l10n.rehearsalFieldYourName),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _instrument,
                decoration:
                    InputDecoration(labelText: l10n.rehearsalFieldInstrument),
                items: [
                  for (final id in kInstruments)
                    DropdownMenuItem(
                      value: id,
                      child: Text(instrumentLabel(l10n, id)),
                    ),
                ],
                onChanged: (v) => setState(() => _instrument = v ?? 'other'),
              ),
              const SizedBox(height: 16),
              Text('${l10n.rehearsalFieldTempo}: '
                  '${l10n.rehearsalBpmValue(_bpm.toStringAsFixed(0))}'),
              Slider(
                value: _bpm,
                min: 40,
                max: 240,
                divisions: 200,
                onChanged: (v) => setState(() => _bpm = v),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _beatsPerBar,
                      decoration: InputDecoration(
                          labelText: l10n.rehearsalFieldTimeSignature),
                      items: [
                        for (final n in [2, 3, 4, 5, 6, 7])
                          DropdownMenuItem(
                            value: n,
                            child: Text(l10n.rehearsalMeter(n, 4)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _beatsPerBar = v ?? 4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _countInBars,
                      decoration:
                          InputDecoration(labelText: l10n.rehearsalFieldCountIn),
                      items: [
                        DropdownMenuItem(
                            value: 0, child: Text(l10n.rehearsalCountInNone)),
                        for (final n in [1, 2, 4])
                          DropdownMenuItem(
                            value: n,
                            child: Text(l10n.rehearsalCountInBars(n)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _countInBars = v ?? 2),
                    ),
                  ),
                ],
              ),
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
          onPressed: () => Navigator.pop(
            context,
            _CreateResult(_title.text, _name.text, _instrument, _bpm,
                _beatsPerBar, _countInBars),
          ),
          child: Text(l10n.rehearsalCreate),
        ),
      ],
    );
  }
}
