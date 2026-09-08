import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../services/file_picker_service.dart';
import '../services/platform_media_decoder.dart';
import '../services/rehearsal_engine.dart';
import '../services/rehearsal_library.dart';
import '../services/rehearsal_protocol.dart';
import '../services/rehearsal_sync_service.dart';
import 'master_align_screen.dart';
import 'nearby_screen.dart';
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
  RehearsalSyncService? _sync;
  Rehearsal? _rehearsal;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    // Everything is read from the context up front, before the first await:
    // afterwards the element may be gone and reading it is a bug the analyzer
    // rightly refuses.
    final library = context.read<RehearsalLibrary>();
    final engine = context.read<RehearsalEngine>();
    final sync = context.read<RehearsalSyncService>();
    _sync = sync;

    final rehearsal =
        library.rehearsals.where((r) => r.id == widget.rehearsalId).firstOrNull;
    if (rehearsal == null) return;
    await engine.open(rehearsal);

    // A finished take goes out immediately rather than waiting for the next
    // poll — the player has just stopped and is looking up at the room.
    engine.onTakeCommitted = () {
      sync.syncNow();
      if (mounted) setState(() {});
    };
    // A part that arrives from someone else has to be opened by the engine, or
    // it appears in the lane and plays nothing.
    sync.onAudioReceived = () async {
      await engine.reloadTracks();
      if (mounted) setState(() {});
    };
    if (!mounted) return;
    setState(() {
      _engine = engine;
      _rehearsal = rehearsal;
    });
    await _goLive(rehearsal);
  }

  /// Joins the room: makes this device reachable and starts looking for the
  /// others.
  ///
  /// Being in a rehearsal is what makes you reachable — not tapping share.
  /// Two people opening the same tune should find each other, and they cannot
  /// if both are only listening.
  Future<void> _goLive(Rehearsal rehearsal) async {
    final library = context.read<RehearsalLibrary>();
    final local = await library.loadLocalState(rehearsal.id);
    if (!mounted) return;

    final sync = context.read<RehearsalSyncService>();
    // A remembered address, for a network where discovery does not work. It
    // goes stale once the peer restarts sharing, so it is only ever a fallback.
    sync.fallbackTicket = local.lastTicketUri == null
        ? null
        : JoinTicket.parse(local.lastTicketUri!);
    await sync.goLive(rehearsal);
  }

  @override
  void dispose() {
    // Read from the fields rather than the context: dispose runs after the
    // element is unmounted, so context.read would throw.
    _engine?.onTakeCommitted = null;
    _sync?.onAudioReceived = null;
    _engine?.close();
    // Leaving the rehearsal ends the session — both halves of it. Hosting
    // outlives the Nearby screen precisely so it can end here instead.
    // Leaving the rehearsal leaves the room: no longer reachable, no longer
    // looking.
    _sync?.goOffline();
    super.dispose();
  }

  /// Picks a music file and imports it as the master track.
  Future<void> _importMaster() async {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    if (rehearsal == null) return;

    // Everything this platform can decode: the three bundled formats
    // everywhere, plus whatever the platform's own codecs add. The picker
    // greys out the rest, so a file that cannot be imported cannot be chosen.
    final path = await FilePickerService.pickFile(
      context: context,
      allowedExtensions: PlatformMediaDecoder.pickableExtensions,
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

  /// Re-reads this rehearsal from the library and reloads the engine.
  ///
  /// Anything that replaces the library's objects — a sync, most obviously —
  /// leaves [_rehearsal] pointing at a document that no longer reflects disk.
  Future<void> _refresh() async {
    final library = context.read<RehearsalLibrary>();
    final fresh =
        library.rehearsals.where((r) => r.id == widget.rehearsalId).firstOrNull;
    if (fresh == null || !mounted) return;
    setState(() => _rehearsal = fresh);
    final engine = context.read<RehearsalEngine>();
    // The engine also holds the old object, so it is reopened rather than just
    // asked to reload its tracks.
    await engine.open(fresh);
    if (mounted) setState(() {});
  }

  /// Deletes this device's own take, after confirming.
  Future<void> _deleteTake(RehearsalPart part) async {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    if (rehearsal == null || part.take == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.rehearsalDeleteTakeConfirm(
            instrumentLabel(l10n, part.instrument))),
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

    await context.read<RehearsalLibrary>().deleteTake(rehearsal, part);
    if (!mounted) return;
    await context.read<RehearsalEngine>().reloadTracks();
    if (mounted) setState(() {});
  }

  /// Removes one of this device's own parts entirely.
  Future<void> _removePart(RehearsalPart part) async {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    if (rehearsal == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.rehearsalRemovePartConfirm(
            instrumentLabel(l10n, part.instrument))),
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

    await context.read<RehearsalLibrary>().deletePart(rehearsal, part);
    if (!mounted) return;
    await context.read<RehearsalEngine>().reloadTracks();
    // Push it, so the part disappears for the others rather than waiting to be
    // re-added by the next sync with someone who still has it.
    if (mounted) await context.read<RehearsalSyncService>().syncNow();
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
    final selfId = engine.localState.selfMemberId;
    // No identity means this device joined before it was asked who it is.
    // Falling back to the first member would attribute the part to whoever
    // shared the tune, which is exactly the bug this replaced.
    if (selfId == null) return;
    await library.addPart(rehearsal, memberId: selfId, instrument: instrument);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;

    return Scaffold(
      appBar: AppBar(
        title: Text(rehearsal?.title ?? l10n.rehearsalsTitle),
        actions: [
          if (rehearsal != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l10n.nearbyTitle,
              onPressed: () async {
                // Sharing opens a socket and the engine holds the audio
                // devices; stopping the transport first keeps the two from
                // competing for attention while a peer syncs.
                await context.read<RehearsalEngine>().stop();
                if (!context.mounted) return;
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NearbyScreen(rehearsal: rehearsal),
                ));
                if (!context.mounted) return;
                // A sync reloads the library, which builds *new* Rehearsal
                // objects — the one this screen is holding is stale, and would
                // keep showing the parts and master from before the sync. Look
                // it up again by id before touching the engine.
                await _refresh();
              },
            ),
        ],
      ),
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
              child: Consumer2<RehearsalEngine, RehearsalSyncService>(
                builder: (context, engine, sync, _) => Column(
                  children: [
                    _TransportBar(engine: engine, rehearsal: rehearsal),
                    if (sync.isLive || sync.isHosting)
                      _LiveBar(
                        sync: sync,
                        rehearsalId: rehearsal.id,
                        onRefresh: () async {
                          await sync.syncNow();
                          await _refresh();
                        },
                      ),
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
                          onDelete: () => _deleteTake(rehearsal.parts[i]),
                          onRemovePart: () =>
                              _removePart(rehearsal.parts[i]),
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
    required this.onDelete,
    required this.onRemovePart,
  });

  final RehearsalEngine engine;
  final Rehearsal rehearsal;
  final RehearsalPart part;
  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final VoidCallback onRemovePart;

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
    // You record your own part and nobody else's. Someone else's take is
    // theirs: overwriting it from here would destroy their work and, because
    // the merge keeps the highest revision, would win on their device too.
    final isMine = part.isOwnedBy(engine.localState.selfMemberId);

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
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              member?.displayName.isNotEmpty == true
                                  ? member!.displayName
                                  : instrumentLabel(l10n, part.instrument),
                              style: theme.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 8),
                            // A quiet badge, so "why can I not record that
                            // one?" answers itself rather than looking like a
                            // control that failed to appear.
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                l10n.rehearsalYourPart,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color:
                                        theme.colorScheme.onPrimaryContainer),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        take == null
                            ? (isMine
                                ? l10n.rehearsalNotRecorded
                                : '${instrumentLabel(l10n, part.instrument)}'
                                    '   ·   '
                                    '${l10n.rehearsalNotRecorded}')
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
                if (isMine)
                  PopupMenuButton<String>(
                    enabled: !engine.isRunning,
                    tooltip: l10n.rehearsalPartActions,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) =>
                        value == 'take' ? onDelete() : onRemovePart(),
                    itemBuilder: (_) => [
                      // Two destructive actions that are easy to confuse, so
                      // they are named rather than offered as two similar
                      // icons: one keeps the lane, the other does not.
                      if (take != null)
                        PopupMenuItem(
                          value: 'take',
                          child: ListTile(
                            leading: const Icon(Icons.backspace_outlined),
                            title: Text(l10n.rehearsalDeleteTake),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ),
                      PopupMenuItem(
                        value: 'part',
                        child: ListTile(
                          leading: const Icon(Icons.delete_outline),
                          title: Text(l10n.rehearsalRemovePart),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                if (isMine)
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

/// A quiet strip saying the room is connected, and how many are in it.
///
/// Deliberately small: it matters while a band is working together, and should
/// disappear from attention the rest of the time.
class _LiveBar extends StatelessWidget {
  const _LiveBar({
    required this.sync,
    required this.rehearsalId,
    required this.onRefresh,
  });

  final RehearsalSyncService sync;
  final String rehearsalId;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(sync.isBusy ? Icons.sync : Icons.wifi_tethering,
              size: 16, color: theme.colorScheme.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Devices visible on the network, not connections made. The
              // latter counts one per sync and reads as a room filling up
              // with people who are not there.
              switch (sync.visibleDeviceCount(rehearsalId)) {
                0 => l10n.liveConnected,
                final n => l10n.nearbyPeers(n),
              },
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            tooltip: l10n.liveRefresh,
            icon: Icon(Icons.refresh,
                size: 18, color: theme.colorScheme.onPrimaryContainer),
          ),
        ],
      ),
    );
  }
}
