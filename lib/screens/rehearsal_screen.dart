import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/rehearsal.dart';
import '../services/audio_route_service.dart';
import '../services/file_picker_service.dart';
import '../services/platform_media_decoder.dart';
import '../services/rehearsal_engine.dart';
import '../services/rehearsal_library.dart';
import '../services/rehearsal_protocol.dart';
import '../services/rehearsal_sync_service.dart';
import '../widgets/audio_settings_bar.dart';
import '../widgets/chord_grid.dart';
import '../widgets/rehearsal_identity_dialog.dart';
import 'latency_probe_screen.dart';
import 'rehearsal_documents_screen.dart';
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
  /// Whether the chart is showing every bar or just the line.
  bool _chartExpanded = false;

  /// Whether the audio settings strip is open, as on the rack.
  ///
  /// A notifier rather than plain state so the toggle in the transport can
  /// drive the strip without rebuilding the lane list underneath it — the same
  /// arrangement the rack uses.
  final ValueNotifier<bool> _audioBarVisible = ValueNotifier(false);

  /// Lanes showing their level slider.
  ///
  /// Held here rather than in the lane so it survives the list rebuilding,
  /// which it does on every transport tick.
  final Set<String> _expanded = {};

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
    sync.fallbackTicket =
        local.lastTicketUri == null
            ? null
            : JoinTicket.parse(local.lastTicketUri!);
    await sync.goLive(rehearsal);
  }

  @override
  void dispose() {
    _audioBarVisible.dispose();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.masterImportFailed)));
      return;
    }
    await engine.reloadTracks();
    if (!mounted) return;
    // Straight into alignment: an unaligned master is not much use, and this
    // is the one moment the player knows what they just imported.
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MasterAlignScreen(engine: engine, rehearsal: rehearsal),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _removeMaster() async {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    final master = rehearsal?.master;
    if (rehearsal == null || master == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            content: Text(l10n.masterRemoveConfirm(master.sourceName)),
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
      builder:
          (ctx) => AlertDialog(
            content: Text(
              l10n.rehearsalDeleteTakeConfirm(
                instrumentLabel(l10n, part.instrument),
              ),
            ),
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
      builder:
          (ctx) => AlertDialog(
            content: Text(
              l10n.rehearsalRemovePartConfirm(
                instrumentLabel(l10n, part.instrument),
              ),
            ),
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
      builder:
          (ctx) => SimpleDialog(
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
    // No identity: either this device joined before it was asked who it is, or
    // it was removed from the band while away and cleared its own id. Falling
    // back to the first member would attribute the part to whoever shared the
    // tune, which is exactly the bug this replaced — so ask instead.
    final selfId = engine.localState.selfMemberId ?? await _askWhoIsPlaying();
    if (selfId == null || !mounted) return;
    await library.addPart(rehearsal, memberId: selfId, instrument: instrument);
    if (mounted) setState(() {});
  }

  /// Gives this device a player of its own, and returns its member id.
  ///
  /// Reached when someone taps to add a part with no identity on file. That
  /// happens after being removed from the band: the tombstone reaches the
  /// removed device too and clears its id, which is right — but without this
  /// the device could sync forever and never record a note, because there is
  /// nobody for a part to belong to. Removal tidies the roster; it is not a
  /// ban, and coming back is how it stays that way.
  Future<String?> _askWhoIsPlaying() async {
    final rehearsal = _rehearsal;
    if (rehearsal == null) return null;

    final identity = await showDialog<RehearsalIdentity>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const RehearsalIdentityDialog(),
    );
    if (identity == null || !mounted) return null;

    final library = context.read<RehearsalLibrary>();
    final engine = context.read<RehearsalEngine>();
    // joinAsMember also writes the local state, which is what the engine is
    // holding — so it has to be told, or it would still think it is nobody.
    final part = await library.joinAsMember(rehearsal,
        name: identity.name, instrument: identity.instrument);
    await engine.reloadLocalState();
    return part.memberId;
  }

  /// Removes a player who is not coming back, and everything they own.
  ///
  /// For a stale identity: a device that was wiped or reinstalled joins again
  /// as a *new* member, and the old one stays in the band because members
  /// merge by union.
  ///
  /// The check that matters is presence, not agreement. Someone whose device
  /// is visible right now is here and can remove themselves; someone who is
  /// not may simply be at home, and waiting for a quorum would mean the band
  /// could only tidy up on the rare evening everybody happened to be online.
  Future<void> _removeMember(RehearsalPart part) async {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    if (rehearsal == null) return;
    final member =
        rehearsal.members.where((m) => m.id == part.memberId).firstOrNull;
    if (member == null) return;

    final recordings = rehearsal.parts
        .where((p) => p.memberId == member.id && p.take != null)
        .length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          l10n.rehearsalRemoveMemberConfirm(
            member.displayName.isEmpty
                ? instrumentLabel(l10n, member.instrument)
                : member.displayName,
            recordings,
          ),
        ),
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

    // Read before the gap: this context is not usable after an await, and the
    // services outlive the screen anyway.
    final library = context.read<RehearsalLibrary>();
    final engine = context.read<RehearsalEngine>();
    final sync = context.read<RehearsalSyncService>();

    await library.removeMember(rehearsal, member.id);
    await engine.reloadTracks();
    // Straight out to the room, so the others stop showing them without
    // waiting for the next poll.
    unawaited(sync.syncNow());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rehearsal = _rehearsal;
    // Only read here, for the warning below. The engine follows the route on
    // its own — writing to a notifier from inside another widget's build is
    // not something to rely on, and the compensation has to be right when
    // record is pressed regardless of what is on screen.
    final route = context.watch<AudioRouteService>().route;

    return Scaffold(
      appBar: AppBar(
        title: Text(rehearsal?.title ?? l10n.rehearsalsTitle),
        actions: [
          if (rehearsal != null)
            _SyncChip(
              rehearsalId: rehearsal.id,
              onRefresh: () async {
                await context.read<RehearsalSyncService>().syncNow();
                await _refresh();
              },
            ),
          if (rehearsal != null)
            IconButton(
              icon: const Icon(Icons.library_books_outlined),
              tooltip: l10n.rehearsalDocuments,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      RehearsalDocumentsScreen(rehearsalId: rehearsal.id),
                ),
              ),
            ),
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
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NearbyScreen(rehearsal: rehearsal),
                  ),
                );
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
      floatingActionButton:
          rehearsal == null
              ? null
              : FloatingActionButton.small(
                heroTag: 'rehearsal-fab',
                onPressed: _addPart,
                tooltip: l10n.rehearsalAddPart,
                child: const Icon(Icons.add),
              ),
      body:
          rehearsal == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                top: false,
                child: Consumer2<RehearsalEngine, RehearsalSyncService>(
                  builder: (context, engine, sync, _) {
                    // Computed once per build, not once per lane: it walks every
                    // part against every visible peer, and the lane builder runs
                    // for each row.
                    final pending = sync.partsAwaitingDelivery(rehearsal);
                  final missing = engine.partsMissingAudio;
                    return Column(
                      children: [
                        _TransportBar(
                      engine: engine,
                      rehearsal: rehearsal,
                      audioBarVisible: _audioBarVisible,
                    ),
                    // The same strip the rack has: microphone sensitivity and
                    // device, output device. A rehearsal needs those choices
                    // more than the rack does — the input is what is being
                    // recorded — and Preferences is a long way from the record
                    // button.
                    ValueListenableBuilder<bool>(
                      valueListenable: _audioBarVisible,
                      builder: (ctx, visible, _) => AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        child: visible
                            ? const AudioSettingsBar()
                            : const SizedBox.shrink(),
                      ),
                    ),
                        // Only when it is asking for something. Being
                        // connected is the normal state of a rehearsal, so a
                        // full-width strip saying so was permanently on and
                        // permanently ignored — two wrapped lines of a phone
                        // screen spent on "nothing is wrong". The quiet states
                        // moved to a chip in the app bar; what is left here is
                        // the one message worth interrupting for.
                        if (pending.isNotEmpty)
                          _LiveBar(
                            sync: sync,
                            rehearsalId: rehearsal.id,
                            pendingCount: pending.length,
                            onRefresh: () async {
                              await sync.syncNow();
                              await _refresh();
                            },
                          ),
                        const Divider(height: 1),
                        // Above the recordings, because it is what a player
                        // reads while playing; the lanes are what they touch
                        // between takes.
                        ChordGrid(
                          rehearsal: rehearsal,
                          currentBar:
                              engine.isRunning && !engine.isCountingIn
                                  ? engine.currentBar
                                  : 0,
                          isRunning: engine.isRunning,
                          expanded: _chartExpanded,
                          onToggleExpanded: () => setState(
                            () => _chartExpanded = !_chartExpanded,
                          ),
                          onChanged: engine.setChords,
                        ),
                        // Per route, not per device: a measurement taken on
                        // the speaker says nothing useful about a Bluetooth
                        // headset, which can be two hundred milliseconds away.
                        if (!engine.isRouteCalibrated &&
                            engine.compensationFrames == 0)
                          _CompensationWarning(route: route)
                        else if (!engine.isRouteCalibrated &&
                            route.kind != 'speaker')
                          _CompensationWarning(route: route),
                        if (_importing) const LinearProgressIndicator(),
                        _MasterRow(
                          engine: engine,
                          rehearsal: rehearsal,
                          importing: _importing,
                          onImport: _importMaster,
                          onRemove: _removeMaster,
                          onAlign: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder:
                                    (_) => MasterAlignScreen(
                                      engine: engine,
                                      rehearsal: rehearsal,
                                    ),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                        ),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 88),
                            itemCount: rehearsal.parts.length,
                            itemBuilder:
                                (_, i) => _PartLane(
                                  engine: engine,
                                  rehearsal: rehearsal,
                                  part: rehearsal.parts[i],
                                  online: sync.onlineDeviceIds(rehearsal.id),
                                  awaitingDelivery: pending.contains(
                                    rehearsal.parts[i].id,
                                  ),
                                  missingAudio: missing.contains(
                                    rehearsal.parts[i].id,
                                  ),
                                  expanded: _expanded.contains(
                                    rehearsal.parts[i].id,
                                  ),
                                  onToggleExpanded: () => setState(() {
                                    final id = rehearsal.parts[i].id;
                                    if (!_expanded.remove(id)) {
                                      _expanded.add(id);
                                    }
                                  }),
                                  onChanged: () => setState(() {}),
                                  onDelete:
                                      () => _deleteTake(rehearsal.parts[i]),
                                  onRemovePart:
                                      () => _removePart(rehearsal.parts[i]),
                                  onRemoveMember:
                                      () =>
                                          _removeMember(rehearsal.parts[i]),
                                ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
    );
  }
}

/// The pinned transport: play/stop, where the tune is, and the click.
///
/// Stays on screen while the lanes scroll (decision D14) — position and
/// transport are read while playing, everything else is an occasional action.
class _TransportBar extends StatelessWidget {
  const _TransportBar({
    required this.engine,
    required this.rehearsal,
    required this.audioBarVisible,
  });

  final RehearsalEngine engine;
  final Rehearsal rehearsal;

  /// Drives the audio settings strip below, as on the rack.
  final ValueNotifier<bool> audioBarVisible;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final running = engine.isRunning;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          IconButton.filled(
            onPressed: running ? engine.stop : engine.play,
            tooltip: running ? l10n.rehearsalStop : l10n.rehearsalPlay,
            icon: Icon(running ? Icons.stop : Icons.play_arrow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  engine.isCountingIn
                      ? l10n.rehearsalCountingIn
                      : l10n.rehearsalBarBeat(
                        engine.currentBar,
                        engine.currentBeat,
                      ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color:
                        engine.isCountingIn ? theme.colorScheme.tertiary : null,
                  ),
                ),
                // A chip, not a line of text with a small icon after it.
                // Tapping the tempo is how both speed controls are reached,
                // and nothing about plain grey text says so — it read as a
                // caption, which is why it could not be found.
                InkWell(
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) =>
                        _TempoSheet(engine: engine, rehearsal: rehearsal),
                  ),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 3, 6, 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.speed,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${l10n.rehearsalBpmValue(rehearsal.bpm.toStringAsFixed(0))}'
                          '   ·   '
                          '${l10n.rehearsalMeter(rehearsal.beatsPerBar, rehearsal.beatUnit)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (engine.practiceSpeed < 0.999) ...[
                          const SizedBox(width: 6),
                          // Shown only when it is not 1.0, because a badge
                          // that is always there stops being read — and
                          // playing at anything other than the tune's own
                          // tempo is exactly the state worth a reminder.
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              l10n.rehearsalPracticeSpeedValue(
                                (engine.practiceSpeed * 100).round(),
                              ),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ],
                        Icon(
                          Icons.arrow_drop_down,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Same chevron, same place, same meaning as on the rack.
          ValueListenableBuilder<bool>(
            valueListenable: audioBarVisible,
            builder: (ctx, visible, _) => Tooltip(
              message: l10n.audioSettingsBarToggleTooltip,
              child: IconButton(
                icon: Icon(
                  visible ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
                color: theme.colorScheme.onSurfaceVariant,
                onPressed: () => audioBarVisible.value = !visible,
              ),
            ),
          ),
          // The visual metronome matters more than usual here: the audience is
          // often on headphones in a quiet room.
          _BeatLamp(engine: engine, rehearsal: rehearsal),
          const SizedBox(width: 4),
          IconButton(
            onPressed:
                () => engine.setMetronome(!engine.localState.metronomeEnabled),
            tooltip: l10n.rehearsalMetronome,
            icon: Icon(
              engine.localState.metronomeEnabled
                  ? Icons.volume_up
                  : Icons.volume_off,
            ),
            color:
                engine.localState.metronomeEnabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

/// One dot per beat in the bar, with the current one lit.
///
/// A rehearsal is often played on headphones in a quiet room, where the click
/// is the only thing keeping everyone together — and someone who has muted it
/// still needs to see where the bar is. The downbeat is drawn larger so a
/// glance says *which* beat, not merely that something is moving.
class _BeatLamp extends StatelessWidget {
  const _BeatLamp({required this.engine, required this.rehearsal});

  final RehearsalEngine engine;
  final Rehearsal rehearsal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beats = rehearsal.beatsPerBar.clamp(1, 12);
    // Only while the transport is moving: a lit dot on a stopped tune reads as
    // "playing" out of the corner of an eye.
    final current = engine.isRunning ? engine.currentBeat : 0;
    // Counting in is a different thing from playing, and the whole point of
    // the count-in is knowing it is about to end.
    final colour =
        engine.isCountingIn ? theme.colorScheme.tertiary : theme.colorScheme.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int beat = 1; beat <= beats; beat++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: beat == 1 ? 9 : 6,
              height: beat == 1 ? 9 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: beat == current
                    ? colour
                    : theme.colorScheme.outlineVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// Who is in the room, as a chip in the app bar.
///
/// The design always called for this (§?: "a quiet chip in the app bar") and
/// the full-width strip was standing in for it. Being connected is the normal
/// state of a rehearsal, so a strip announcing it was on the whole time and
/// read none of the time, while costing two wrapped lines of a cover screen.
///
/// Tapping it syncs now, which is what the strip's refresh button did.
class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.rehearsalId, required this.onRefresh});

  final String rehearsalId;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final sync = context.watch<RehearsalSyncService>();
    final peers = sync.visibleDeviceCount(rehearsalId);

    // Nothing to report and nobody about: no chip at all. A rehearsal on your
    // own should not carry networking furniture.
    if (peers == 0 && !sync.isBusy) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Tooltip(
        message: peers == 0 ? l10n.liveConnected : l10n.nearbyPeers(peers),
        child: InkWell(
          onTap: () => onRefresh(),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sync.isBusy ? Icons.sync : Icons.wifi_tethering,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                if (peers > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    '$peers',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
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
}

/// Shown when no latency measurement exists on this device.
///
/// Recording without one produces a take that sits behind the beat by the
/// device's round trip — around 30 ms on a phone, which is audible. Better to
/// say so before the player records than to leave them wondering why their
/// part drags.
class _CompensationWarning extends StatelessWidget {
  const _CompensationWarning({required this.route});

  /// What the player is listening on, so the warning can name it.
  final AudioRoute route;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.tertiaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Naming the headset matters: "latency has not been measured"
              // reads as a chore, while "these headphones have not been
              // measured" reads as the reason a take will drag.
              route.kind == 'speaker'
                  ? l10n.rehearsalNoCompensation
                  : l10n.rehearsalRouteUncalibrated(route.label),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // The fix, next to the complaint. Sending someone out of the tune,
          // into settings and down a scrolling list to find it is most of the
          // reason it stays unmeasured.
          TextButton(
            onPressed: () => _calibrate(context),
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.onTertiaryContainer,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(l10n.rehearsalCalibrate),
          ),
        ],
      ),
    );
  }

  /// Explains the measurement, then runs it.
  ///
  /// The explanation is not padding: the probe listens for its own sweeps
  /// through the microphone, so on headphones it hears nothing and fails. That
  /// is a confusing way to meet a feature, and a sentence beforehand avoids it.
  Future<void> _calibrate(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final engine = context.read<RehearsalEngine>();

    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.rehearsalCalibrateTitle),
        content: SingleChildScrollView(
          child: Text(
            // The microphone cannot hear a headset through the air, so the
            // usual instructions are not merely unhelpful here — following
            // them guarantees the measurement finds nothing.
            route.isBluetooth
                ? l10n.rehearsalRouteBluetoothHint
                : l10n.rehearsalCalibrateBody,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.rehearsalCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.rehearsalCalibrateStart),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    // The probe listens for its own sweeps, so anything else coming out of the
    // speakers is interference. It rides on a different bus slot from the
    // rehearsal engine, so stopping the transport is enough — the engine does
    // not have to be torn down.
    await engine.stop();
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LatencyProbeScreen()),
    );
    // The probe writes to shared preferences; this rehearsal read them when it
    // opened, so it has to be told to look again.
    await engine.adoptMeasuredCompensation();
  }
}

class _TempoSheet extends StatefulWidget {
  const _TempoSheet({required this.engine, required this.rehearsal});

  final RehearsalEngine engine;
  final Rehearsal rehearsal;

  @override
  State<_TempoSheet> createState() => _TempoSheetState();
}

class _TempoSheetState extends State<_TempoSheet> {
  late double _bpm = widget.rehearsal.bpm;
  late double _speed = widget.engine.practiceSpeed;
  late int _countIn = widget.rehearsal.countInBars;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.rehearsalTempoTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 20),

            _label(theme, l10n.rehearsalTuneTempo,
                l10n.rehearsalBpmValue(_bpm.toStringAsFixed(0))),
            Slider(
              value: _bpm.clamp(40, 240),
              min: 40,
              max: 240,
              divisions: 200,
              // With a recording in the tune its tempo is not ours to choose:
              // it is whatever was played, and it is discovered on the align
              // screen rather than set here. Dragging this would stretch the
              // recording instead of describing it.
              onChanged: widget.rehearsal.hasMaster
                  ? null
                  : (v) => setState(() => _bpm = v),
              // Committed on release, not while dragging: every change
              // re-renders every recording, and doing that per pixel would
              // render a hundred times to arrive at one answer.
              onChangeEnd: widget.rehearsal.hasMaster
                  ? null
                  : (v) => widget.engine.setBpm(v),
            ),
            _hint(
              theme,
              widget.rehearsal.hasMaster
                  ? l10n.rehearsalTempoFromMaster
                  : l10n.rehearsalTuneTempoHint,
            ),

            const SizedBox(height: 24),
            _label(theme, l10n.rehearsalPracticeSpeed,
                l10n.rehearsalPracticeSpeedValue((_speed * 100).round())),
            Slider(
              value: _speed.clamp(0.5, 1.0),
              min: 0.5,
              max: 1.0,
              // Steps of 5%: fine enough to find a workable speed, coarse
              // enough that the slider lands on round numbers rather than 73%.
              divisions: 10,
              onChanged: (v) => setState(() => _speed = v),
              onChangeEnd: (v) => widget.engine.setPracticeSpeed(v),
            ),
            _hint(theme, l10n.rehearsalPracticeSpeedHint),

            const SizedBox(height: 24),
            // Count-in belongs here rather than only in the create dialog: it
            // is a tempo decision, and it is the one people change once they
            // have tried recording and found two bars too short or too long.
            Text(
              l10n.rehearsalFieldCountIn,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(l10n.rehearsalCountInNone)),
                for (final n in [1, 2, 4])
                  ButtonSegment(
                    value: n,
                    label: Text(l10n.rehearsalCountInBars(n)),
                  ),
              ],
              selected: {_countIn},
              showSelectedIcon: false,
              onSelectionChanged: (v) {
                setState(() => _countIn = v.first);
                widget.engine.setCountInBars(v.first);
              },
            ),

            if (widget.rehearsal.isGridFrozen) ...[
              const SizedBox(height: 16),
              _hint(theme, l10n.rehearsalMeterFrozen),
            ],
            if (widget.engine.isRendering) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(l10n.rehearsalRendering,
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(ThemeData theme, String name, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      );

  Widget _hint(ThemeData theme, String text) => Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
}

/// A small red flag on a lane: something is missing or has not gone out yet.
class _LaneTag extends StatelessWidget {
  const _LaneTag({required this.text, this.neutral = false});

  final String text;

  /// Whether this tag states a fact rather than raising a problem.
  ///
  /// The warning colour is what makes the other tags worth reading at a
  /// glance; spending it on a lane that is simply set up a particular way
  /// would teach players to ignore it.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: neutral ? scheme.secondaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: neutral ? scheme.onSecondaryContainer : scheme.onErrorContainer,
        ),
      ),
    );
  }
}

/// Says whether the player who owns a lane is reachable right now.
///
/// A dot rather than a word: it sits next to a name that is already competing
/// for a narrow lane on a phone, and presence is the kind of thing that should
/// be readable without being read. The tooltip and the semantics label carry
/// the meaning for anyone who needs it spelled out, including screen readers,
/// for whom a coloured circle says nothing at all.
class _PresenceDot extends StatelessWidget {
  const _PresenceDot({required this.isHere});

  final bool isHere;

  /// Green for present, which is the one convention worth borrowing here — a
  /// theme accent would be read as decoration rather than as status. Muted
  /// rather than vivid so a room full of people does not turn into a light
  /// display.
  static const Color _here = Color(0xFF4CAF7D);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final label = isHere ? l10n.rehearsalMemberHere : l10n.rehearsalMemberAway;

    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Filled when here, hollow when away: the two states differ in
            // shape as well as in colour, so the badge still reads for someone
            // who cannot tell the two hues apart.
            color: isHere ? _here : Colors.transparent,
            border:
                isHere
                    ? null
                    : Border.all(color: theme.colorScheme.outline, width: 1.5),
          ),
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
    required this.online,
    required this.awaitingDelivery,
    required this.missingAudio,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onDelete,
    required this.onRemovePart,
    required this.onRemoveMember,
  });

  final RehearsalEngine engine;
  final Rehearsal rehearsal;
  final RehearsalPart part;

  /// Device ids reachable right now, from discovery.
  final Set<String> online;

  /// True while some device in the room is not yet known to hold this take.
  final bool awaitingDelivery;

  /// True when this device knows about the take but has no audio for it.
  final bool missingAudio;

  /// Whether this lane is showing its level slider.
  final bool expanded;

  final VoidCallback onToggleExpanded;

  final VoidCallback onChanged;
  final VoidCallback onDelete;
  final VoidCallback onRemovePart;

  /// Removes the player who owns this lane, and everything they own.
  final VoidCallback onRemoveMember;

  /// Switches this lane between the microphone and the rack, and redraws.
  ///
  /// Kept off the transport's path deliberately: the menu is disabled while
  /// the transport runs, so this never lands in the middle of a take.
  void _setRackInput(bool fromRack) {
    engine.setRecordsFromRack(part, fromRack).then((_) => onChanged());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final member =
        rehearsal.members.where((m) => m.id == part.memberId).firstOrNull;
    final take = part.take;
    final isRecordingThis = engine.recordingPart?.id == part.id;
    final muted = engine.localState.isMuted(part.id);
    // Where this lane records from. Worth saying on the row rather than only
    // in the menu: pressing record on a lane wired to the rack while holding
    // a guitar records silence, and the moment to notice is before the take.
    final fromRack = engine.recordsFromRack(part);
    // You record your own part and nobody else's. Someone else's take is
    // theirs: overwriting it from here would destroy their work and, because
    // the merge keeps the highest revision, would win on their device too.
    final isMine = part.isOwnedBy(engine.localState.selfMemberId);
    // Your own lane is here by definition; everyone else has to be visible on
    // the network. A member with no device id has never opened the tune on a
    // device this one has met, which reads as away — accurately.
    final isHere =
        isMine ||
        (member?.deviceId != null && online.contains(member!.deviceId));
    // A player who is connected can remove themselves, and your own lane is
    // not a thing to be removed from. What is left is a device that has gone
    // for good — the case nobody present can resolve by asking.
    final canRemoveMember = !isMine && !isHere && member != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      // The whole card opens and closes the level. The buttons on it absorb
      // their own taps, so this only catches the parts that do nothing else.
      child: InkWell(
        onTap: take == null ? null : onToggleExpanded,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  instrumentIcon(part.instrument),
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _PresenceDot(isHere: isHere),
                          const SizedBox(width: 6),
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
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                l10n.rehearsalYourPart,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      // The status tags live on this line, not beside the
                      // name. A lane that is both yours and waiting carried
                      // two badges next to a name on one row, which ran off
                      // the side of a cover screen. Down here the text
                      // ellipsizes and the tag keeps its full width.
                      Row(
                        children: [
                          Flexible(
                            child: Text(
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
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isMine && fromRack) ...[
                            const SizedBox(width: 8),
                            _LaneTag(text: l10n.rehearsalInputRack,
                                neutral: true),
                          ],
                          if (missingAudio) ...[
                            const SizedBox(width: 8),
                            // A different complaint from the one after it:
                            // that one says the room has not got your
                            // recording, this one says you have not got
                            // theirs.
                            _LaneTag(text: l10n.rehearsalTakeAwaitingAudio),
                          ],
                          if (awaitingDelivery) ...[
                            const SizedBox(width: 8),
                            // The one thing on this screen that asks the
                            // player to do something — wait — and it stops
                            // mattering the moment it goes.
                            _LaneTag(text: l10n.rehearsalTakePending),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // What a lane offers depends on whose it is. Your own
                // recordings are yours to delete; the one thing you may do to
                // somebody else's lane is remove a player who has gone for
                // good. When neither applies there is no button at all, rather
                // than one that opens an empty menu.
                if (isMine || canRemoveMember)
                  PopupMenuButton<String>(
                    enabled: !engine.isRunning,
                    tooltip: l10n.rehearsalPartActions,
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) => switch (value) {
                      'take' => onDelete(),
                      'member' => onRemoveMember(),
                      'input' => _setRackInput(!fromRack),
                      _ => onRemovePart(),
                    },
                    itemBuilder:
                        (_) => [
                          // Where the take comes from, above the two ways of
                          // throwing one away: it is the only item here that
                          // is a setting rather than a deletion.
                          if (isMine && engine.canRecordFromRack)
                            CheckedPopupMenuItem(
                              value: 'input',
                              checked: fromRack,
                              child: Text(l10n.rehearsalRecordFromRack),
                            ),
                          // Two destructive actions that are easy to confuse, so
                          // they are named rather than offered as two similar
                          // icons: one keeps the lane, the other does not.
                          if (isMine && take != null)
                            PopupMenuItem(
                              value: 'take',
                              child: ListTile(
                                leading: const Icon(Icons.backspace_outlined),
                                title: Text(l10n.rehearsalDeleteTake),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                          if (isMine)
                            PopupMenuItem(
                              value: 'part',
                              child: ListTile(
                                leading: const Icon(Icons.delete_outline),
                                title: Text(l10n.rehearsalRemovePart),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ),
                          // Offered only for someone else who is not here.
                          // Your own lane is not a thing to be removed from,
                          // and a player who is connected can do it
                          // themselves — this exists for a device that has
                          // gone for good, which is the case no amount of
                          // asking around can resolve.
                          if (canRemoveMember)
                            PopupMenuItem(
                              value: 'member',
                              child: ListTile(
                                leading: const Icon(Icons.person_remove_outlined),
                                title: Text(l10n.rehearsalRemoveMember),
                                subtitle: Text(
                                  l10n.rehearsalRemoveMemberHere,
                                  style: theme.textTheme.labelSmall,
                                ),
                                isThreeLine: true,
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
                    tooltip:
                        take == null
                            ? l10n.rehearsalRecord
                            : l10n.rehearsalRerecord,
                    icon: Icon(
                      isRecordingThis ? Icons.stop : Icons.fiber_manual_record,
                      color: isRecordingThis ? null : theme.colorScheme.error,
                    ),
                  ),
                // Always last, and always present even when there is nothing
                // to mute yet. The other buttons on a lane come and go with
                // whose it is and what is on it; if mute moved with them you
                // would have to look for it every time, and muting is the one
                // thing people do *while* the band is playing.
                IconButton(
                  onPressed:
                      take == null ? null : () => engine.setMuted(part, !muted),
                  tooltip: l10n.rehearsalMute,
                  icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
                  color: muted ? theme.colorScheme.error : null,
                ),
              ],
            ),
            // Level is an occasional adjustment, not a performance control
            // (D14), and a slider on every lane cost a full row each — five
            // players filled a phone screen before the chord grid had
            // anywhere to go. Tap a lane to set its level.
            if (expanded && take != null) ...[
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
                Icon(
                  Icons.album_outlined,
                  size: 20,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        master.sourceName.isEmpty
                            ? l10n.masterTitle
                            : master.sourceName,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        l10n.masterDownbeatAt(_fmt(master.offset)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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
    required this.pendingCount,
    required this.onRefresh,
  });

  final RehearsalSyncService sync;
  final String rehearsalId;

  /// How many takes are not yet known to be on every device in the room.
  final int pendingCount;

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    // The bar turns into the warning rather than sitting next to one. It is
    // already the "who is here" strip, and whether the room has everything is
    // the same question — a second bar would compete with it.
    final waiting = pendingCount > 0;
    final background =
        waiting
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.primaryContainer;
    final foreground =
        waiting
            ? theme.colorScheme.onErrorContainer
            : theme.colorScheme.onPrimaryContainer;

    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            waiting
                ? Icons.cloud_upload_outlined
                : (sync.isBusy ? Icons.sync : Icons.wifi_tethering),
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              // Devices visible on the network, not connections made. The
              // latter counts one per sync and reads as a room filling up
              // with people who are not there.
              waiting
                  ? l10n.rehearsalSyncIncomplete
                  : switch (sync.visibleDeviceCount(rehearsalId)) {
                    0 => l10n.liveConnected,
                    final n => l10n.nearbyPeers(n),
                  },
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            tooltip: l10n.liveRefresh,
            icon: Icon(Icons.refresh, size: 18, color: foreground),
          ),
        ],
      ),
    );
  }
}
