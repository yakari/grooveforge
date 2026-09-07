import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../services/file_picker_service.dart';
import '../services/rehearsal_engine.dart';
import '../services/rehearsal_library.dart';
import 'master_align_screen.dart';
import 'rehearsals_screen.dart' show instrumentIcon, instrumentLabel;

/// One rehearsal: transport on top, a lane per part below.
///
/// The lane list scrolls rather than being squeezed to fit (decision D14) —
/// mute and gain are occasional actions, not performance controls, so a
/// seven-piece band does not need to fit one phone screen. The transport and
/// the bar counter stay pinned, because those are read while playing.
class RehearsalScreen extends StatefulWidget {
  const RehearsalScreen({super.key, required this.rehearsalId});

  final String rehearsalId;

  @override
  State<RehearsalScreen> createState() => _RehearsalScreenState();
}

class _RehearsalScreenState extends State<RehearsalScreen> {
  RehearsalEngine? _engine;
  Rehearsal? _rehearsal;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final library = context.read<RehearsalLibrary>();
    final engine = context.read<RehearsalEngine>();
    final rehearsal =
        library.rehearsals.where((r) => r.id == widget.rehearsalId).firstOrNull;
    if (rehearsal == null) return;
    await engine.open(rehearsal);
    if (!mounted) return;
    setState(() {
      _engine = engine;
      _rehearsal = rehearsal;
    });
  }

  @override
  void dispose() {
    // Read from the field rather than the context: dispose runs after the
    // element is unmounted, so context.read would throw.
    _engine?.close();
    super.dispose();
  }

  /// Picks a music file and imports it as the master track.
  Future<void> _importMaster() async {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    if (rehearsal == null) return;

    // The extensions the bundled decoders handle. Anything else is refused by
    // the importer with a message rather than half-decoded into noise; the
    // formats that need the platform's own extractor (AAC, M4A, video
    // containers) are not offered yet — see REHEARSALS.md §7.1.
    final path = await FilePickerService.pickFile(
      context: context,
      allowedExtensions: const ['mp3', 'wav', 'flac'],
      dialogTitle: l10n.masterImport,
    );
    if (path == null || !mounted) return;

    setState(() => _importing = true);
    final library = context.read<RehearsalLibrary>();
    final engine = context.read<RehearsalEngine>();
    // Decoding is proportional to the file's length and blocks; the spinner is
    // there because a four-minute master is not instant on a phone.
    final master = await library.importMaster(rehearsal, path);
    if (!mounted) return;
    setState(() => _importing = false);

    if (master == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.masterImportFailed)),
      );
      return;
    }
    await engine.reloadTracks();
    if (!mounted) return;
    // Straight into alignment: an unaligned master is not much use, and this
    // is the one moment the player knows what they just imported.
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MasterAlignScreen(engine: engine, rehearsal: rehearsal),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _removeMaster() async {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    final master = rehearsal?.master;
    if (rehearsal == null || master == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.masterRemoveConfirm(master.sourceName)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.rehearsalCancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.rehearsalDelete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<RehearsalLibrary>().removeMaster(rehearsal);
    if (!mounted) return;
    await context.read<RehearsalEngine>().reloadTracks();
    if (mounted) setState(() {});
  }

  Future<void> _addPart() async {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    if (rehearsal == null) return;

    final instrument = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.rehearsalAddPart),
        children: [
          for (final id in kInstruments)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, id),
              child: Row(
                children: [
                  Icon(instrumentIcon(id), size: 20),
                  const SizedBox(width: 12),
                  Text(instrumentLabel(l10n, id)),
                ],
              ),
            ),
        ],
      ),
    );
    if (instrument == null || !mounted) return;

    final library = context.read<RehearsalLibrary>();
    final engine = context.read<RehearsalEngine>();
    final selfId = engine.localState.selfMemberId ??
        (rehearsal.members.isNotEmpty ? rehearsal.members.first.id : '');
    await library.addPart(rehearsal, memberId: selfId, instrument: instrument);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;

    return Scaffold(
      appBar: AppBar(title: Text(rehearsal?.title ?? l10n.rehearsalsTitle)),
      floatingActionButton: rehearsal == null
          ? null
          : FloatingActionButton.small(
              onPressed: _addPart,
              tooltip: l10n.rehearsalAddPart,
              child: const Icon(Icons.add),
            ),
      body: rehearsal == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: Consumer<RehearsalEngine>(
                builder: (context, engine, _) => Column(
                  children: [
                    _TransportBar(engine: engine, rehearsal: rehearsal),
                    const Divider(height: 1),
                    if (engine.localState.compensationFrames == 0)
                      _CompensationWarning(),
                    if (_importing) const LinearProgressIndicator(),
                    _MasterRow(
                      engine: engine,
                      rehearsal: rehearsal,
                      importing: _importing,
                      onImport: _importMaster,
                      onRemove: _removeMaster,
                      onAlign: () async {
                        await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => MasterAlignScreen(
                              engine: engine, rehearsal: rehearsal),
                        ));
                        if (mounted) setState(() {});
                      },
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                        itemCount: rehearsal.parts.length,
                        itemBuilder: (_, i) => _PartLane(
                          engine: engine,
                          rehearsal: rehearsal,
                          part: rehearsal.parts[i],
                          onChanged: () => setState(() {}),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Shown when no latency measurement exists on this device.
///
/// Recording without one produces a take that sits behind the beat by the
/// device's round trip — around 30 ms on a phone, which is audible. Better to
/// say so before the player records than to leave them wondering why their
/// part drags.
class _CompensationWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 18, color: theme.colorScheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.rehearsalNoCompensation,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// Transport, bar counter and metronome toggle.
class _TransportBar extends StatelessWidget {
  const _TransportBar({required this.engine, required this.rehearsal});

  final RehearsalEngine engine;
  final Rehearsal rehearsal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final running = engine.isRunning;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          IconButton.filled(
            onPressed: running ? engine.stop : engine.play,
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
            tooltip: running ? l10n.rehearsalStop : l10n.rehearsalPlay,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  engine.isCountingIn
                      ? l10n.rehearsalCountingIn
                      : l10n.rehearsalBarBeat(engine.currentBar, engine.currentBeat),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: engine.isCountingIn
                        ? theme.colorScheme.tertiary
                        : null,
                  ),
                ),
                Text(
                  '${l10n.rehearsalBpmValue(rehearsal.bpm.toStringAsFixed(0))}'
                  '   ·   '
                  '${l10n.rehearsalMeter(rehearsal.beatsPerBar, rehearsal.beatUnit)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          // The visual metronome matters more than usual here: the audience is
          // often on headphones in a quiet room.
          _BeatLamp(engine: engine, rehearsal: rehearsal),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () =>
                engine.setMetronome(!engine.localState.metronomeEnabled),
            tooltip: l10n.rehearsalMetronome,
            icon: Icon(engine.localState.metronomeEnabled
                ? Icons.volume_up
                : Icons.volume_off),
            color: engine.localState.metronomeEnabled
                ? theme.colorScheme.primary
                : null,
          ),
        ],
      ),
    );
  }
}

/// A lamp that flashes on the beat, brighter on the downbeat.
class _BeatLamp extends StatelessWidget {
  const _BeatLamp({required this.engine, required this.rehearsal});

  final RehearsalEngine engine;
  final Rehearsal rehearsal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fpb = engine.framesPerBeat;
    var lit = 0.0;
    if (engine.isRunning && fpb > 0) {
      var into = engine.positionFrames % fpb;
      if (into < 0) into += fpb;
      // Lit for the first eighth of the beat, then dark — long enough to read
      // in peripheral vision, short enough to be unambiguous.
      lit = into < fpb ~/ 8 ? 1.0 : 0.0;
    }
    final downbeat = engine.currentBeat == 1;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Color.lerp(
          theme.colorScheme.surfaceContainerHighest,
          downbeat ? theme.colorScheme.primary : theme.colorScheme.secondary,
          lit,
        ),
      ),
    );
  }
}

/// One part: who plays it, its meter, mute, gain and record button.
class _PartLane extends StatelessWidget {
  const _PartLane({
    required this.engine,
    required this.rehearsal,
    required this.part,
    required this.onChanged,
  });

  final RehearsalEngine engine;
  final Rehearsal rehearsal;
  final RehearsalPart part;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final member = rehearsal.members
        .where((m) => m.id == part.memberId)
        .firstOrNull;
    final take = part.take;
    final isRecordingThis = engine.recordingPart?.id == part.id;
    final muted = engine.localState.isMuted(part.id);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(instrumentIcon(part.instrument),
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member?.displayName.isNotEmpty == true
                            ? member!.displayName
                            : instrumentLabel(l10n, part.instrument),
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        take == null
                            ? l10n.rehearsalNotRecorded
                            : '${instrumentLabel(l10n, part.instrument)}'
                                '   ·   '
                                '${l10n.rehearsalTakeLength((take.duration.inMilliseconds / 1000).toStringAsFixed(1))}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: take == null
                      ? null
                      : () => engine.setMuted(part, !muted),
                  tooltip: l10n.rehearsalMute,
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  color: muted ? theme.colorScheme.error : null,
                ),
                IconButton.filledTonal(
                  onPressed: () async {
                    if (engine.isRunning) {
                      await engine.stop();
                    } else {
                      await engine.record(part);
                    }
                    onChanged();
                  },
                  tooltip: take == null
                      ? l10n.rehearsalRecord
                      : l10n.rehearsalRerecord,
                  icon: Icon(
                    isRecordingThis ? Icons.stop : Icons.fiber_manual_record,
                    color: isRecordingThis ? null : theme.colorScheme.error,
                  ),
                ),
              ],
            ),
            if (take != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const SizedBox(width: 30),
                  Expanded(
                    child: Slider(
                      value: engine.localState.gainFor(part.id).clamp(0.0, 2.0),
                      max: 2.0,
                      divisions: 40,
                      onChanged: (v) => engine.setGain(part, v),
                    ),
                  ),
                ],
              ),
            ],
            if (isRecordingThis)
              LinearProgressIndicator(
                value: engine.inputPeak.clamp(0.0, 1.0),
                minHeight: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: theme.colorScheme.error,
              ),
          ],
        ),
      ),
    );
  }
}

/// The imported recording: import it, align it, mix it, or remove it.
///
/// Sits above the part lanes rather than among them because it is not a part —
/// it belongs to the rehearsal, nobody records over it, and it does not count
/// towards how much of the tune the band has laid down.
class _MasterRow extends StatelessWidget {
  const _MasterRow({
    required this.engine,
    required this.rehearsal,
    required this.importing,
    required this.onImport,
    required this.onRemove,
    required this.onAlign,
  });

  final RehearsalEngine engine;
  final Rehearsal rehearsal;
  final bool importing;
  final VoidCallback onImport;
  final VoidCallback onRemove;
  final VoidCallback onAlign;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final master = rehearsal.master;

    if (master == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: OutlinedButton.icon(
          onPressed: importing ? null : onImport,
          icon: const Icon(Icons.library_music_outlined, size: 18),
          label: Text(importing ? l10n.masterImporting : l10n.masterImport),
        ),
      );
    }

    final muted = engine.isMasterMuted;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.album_outlined,
                    size: 20, color: theme.colorScheme.tertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(master.sourceName.isEmpty
                          ? l10n.masterTitle
                          : master.sourceName,
                          style: theme.textTheme.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(
                        l10n.masterDownbeatAt(_fmt(master.offset)),
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => engine.setMasterMuted(!muted),
                  tooltip: l10n.rehearsalMute,
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  color: muted ? theme.colorScheme.error : null,
                ),
                IconButton(
                  onPressed: onAlign,
                  tooltip: l10n.masterAlign,
                  icon: const Icon(Icons.straighten),
                ),
                IconButton(
                  onPressed: onRemove,
                  tooltip: l10n.masterRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 30),
                Expanded(
                  child: Slider(
                    value: engine.masterGain.clamp(0.0, 2.0),
                    max: 2.0,
                    divisions: 40,
                    onChanged: engine.setMasterGain,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// mm:ss.cc — the same shape the alignment screen uses.
  static String _fmt(Duration d) {
    final s = d.inSeconds;
    final cs = (d.inMilliseconds % 1000) ~/ 10;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}'
        '.${cs.toString().padLeft(2, '0')}';
  }
}
