import '../models/rehearsal.dart';

/// What a merge produced, and what still has to be fetched to complete it.
class MergeOutcome {
  MergeOutcome({
    required this.merged,
    required this.partsToFetch,
    required this.masterToFetch,
    required this.changed,
  });

  /// The merged document. The same object as the local one, mutated in place,
  /// so callers holding a reference see the result.
  final Rehearsal merged;

  /// Part ids whose take now comes from the peer, so its audio is not on this
  /// device yet. Merging the manifest is not finished until these arrive.
  final List<String> partsToFetch;

  /// Whether the master's audio has to be fetched too.
  final bool masterToFetch;

  /// Whether anything at all changed. Nothing to save, and nothing to tell the
  /// user about, when false.
  final bool changed;
}

/// Merges a peer's rehearsal document into the local one.
///
/// The design goal is that this can never conflict, because a conflict between
/// two people's recordings has no good resolution — you cannot average two
/// bass parts. It is achieved by making sure no two devices ever write the
/// same thing:
///
/// - **Takes** are owned by exactly one part and are immutable once recorded.
///   Re-recording produces a new take with the next revision, so merging is
///   "for each part, keep the highest revision" — a grow-only map, not a diff.
/// - **Members and parts** are keyed by random ids generated on the device
///   that created them, so two people creating a part offline cannot collide.
/// - **Metadata** is the only genuinely shared, mutable state, and gets
///   last-writer-wins per field with a Lamport stamp (see [FieldClock]).
///
/// Merging is *symmetric*: running it on both devices from their own point of
/// view produces the same document. That is what lets any two members sync
/// whenever they meet, with no server and no designated host.
MergeOutcome mergeRehearsal(Rehearsal local, Rehearsal remote) {
  var changed = false;

  // ── Metadata: last writer wins, per field ───────────────────────────────
  //
  // A field the peer has never touched carries a zero stamp and loses, so a
  // rehearsal created before syncing existed merges without a migration.
  for (final field in RehearsalField.all) {
    // The master is settled below, where the audio it needs is worked out
    // too. Letting it through here would stamp its clock before that check
    // runs, and the check would then decide the peer had nothing newer.
    if (field == RehearsalField.master) continue;

    final theirs = remote.clockFor(field);
    if (!theirs.beats(local.clockFor(field))) continue;

    switch (field) {
      case RehearsalField.title:
        if (local.title != remote.title) changed = true;
        local.title = remote.title;
      case RehearsalField.bpm:
        if (local.bpm != remote.bpm) changed = true;
        local.bpm = remote.bpm;
      case RehearsalField.beatsPerBar:
        if (local.beatsPerBar != remote.beatsPerBar) changed = true;
        local.beatsPerBar = remote.beatsPerBar;
      case RehearsalField.beatUnit:
        if (local.beatUnit != remote.beatUnit) changed = true;
        local.beatUnit = remote.beatUnit;
      case RehearsalField.countInBars:
        if (local.countInBars != remote.countInBars) changed = true;
        local.countInBars = remote.countInBars;
    }
    local.clocks[field] = theirs;
  }

  // ── Master ───────────────────────────────────────────────────────────────
  var masterToFetch = false;
  final masterTheirs = remote.clockFor(RehearsalField.master);
  if (masterTheirs.beats(local.clockFor(RehearsalField.master))) {
    final remoteMaster = remote.master;
    final localMaster = local.master;

    // Whether the two sides are pointing at the same recording, compared on
    // source name and length rather than object identity: the same file
    // imported on two phones produces two different objects, and re-fetching
    // tens of megabytes to discover they match would be a poor trade.
    final sameRecording = remoteMaster != null &&
        localMaster != null &&
        localMaster.sourceName == remoteMaster.sourceName &&
        localMaster.frames == remoteMaster.frames;

    // Only the audio has to travel. A peer that merely re-anchored the
    // downbeat is a metadata change, and moving the file again for it would
    // make aligning the grid feel expensive.
    masterToFetch = remoteMaster != null && !sameRecording;

    if (!sameRecording ||
        localMaster.offsetFrames != remoteMaster.offsetFrames) {
      changed = true;
    }
    local.master = remoteMaster;
    local.clocks[RehearsalField.master] = masterTheirs;
  }

  // ── Members: union by id ─────────────────────────────────────────────────
  //
  // A member already known keeps the local copy. Names and instruments are set
  // when someone joins and rarely change; giving them their own clocks would
  // cost more than it is worth.
  final knownMembers = {for (final m in local.members) m.id};
  for (final m in remote.members) {
    if (knownMembers.contains(m.id)) continue;
    local.members.add(m);
    changed = true;
  }

  // ── Parts: union by id, highest take revision wins ───────────────────────
  final partsToFetch = <String>[];
  final localByPartId = {for (final p in local.parts) p.id: p};

  for (final remotePart in remote.parts) {
    final localPart = localByPartId[remotePart.id];

    if (localPart == null) {
      local.parts.add(remotePart);
      changed = true;
      if (remotePart.take != null) partsToFetch.add(remotePart.id);
      continue;
    }

    final theirTake = remotePart.take;
    if (theirTake == null) continue;

    final ourTake = localPart.take;
    // Strictly greater: an equal revision is the same take, and re-fetching
    // it would move megabytes to arrive at what is already here.
    if (ourTake == null || theirTake.revision > ourTake.revision) {
      localPart.take = theirTake;
      partsToFetch.add(remotePart.id);
      changed = true;
    }
  }

  // Keep the document clock ahead of everything either side has seen, so the
  // next local edit stamps a counter no peer can already have used.
  final highest = remote.lamport > local.lamport ? remote.lamport : local.lamport;
  if (highest != local.lamport) {
    local.lamport = highest;
    // Not a user-visible change on its own, so `changed` is left alone.
  }

  return MergeOutcome(
    merged: local,
    partsToFetch: partsToFetch,
    masterToFetch: masterToFetch,
    changed: changed,
  );
}
