import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/loop_track.dart';
import 'transport_engine.dart';

// ── Looper state ──────────────────────────────────────────────────────────────

/// The recording / playback state machine for one looper slot session.
///
/// Transitions:
/// ```
/// idle ──► armed ──► recording ──► playing
///                                     │
///                                     ▼
///                              overdubbing ──► playing
/// ```
/// • [idle]           — no loop recorded yet; engine is quiescent.
/// • [armed]          — transport is stopped; engine will start recording
///                      as soon as the transport plays.
/// • [recording]      — actively accumulating MIDI events.
/// • [waitingForBar]  — play was requested mid-bar; engine is counting
///                      beats until the next bar 1 before starting.
/// • [playing]        — replaying the recorded events in a loop.
/// • [overdubbing]    — replaying AND accumulating new events on top.
enum LooperState { idle, armed, recording, waitingForBar, playing, overdubbing }

// ── CC action ─────────────────────────────────────────────────────────────────

/// Looper actions that can be bound to hardware CC knobs/buttons.
enum LooperAction {
  /// Toggle between recording / overdubbing and playing.
  toggleRecord,

  /// Toggle play / pause without clearing the loop.
  togglePlay,

  /// Stop playback and return to idle (clears the active recording pass).
  stop,

  /// Erase all recorded tracks and return to idle.
  clearAll,
}

// ── Per-slot session ──────────────────────────────────────────────────────────

/// Internal state for one looper rack slot.
///
/// Holds all tracks, the current state-machine phase, timing references, and
/// in-progress recording bookkeeping.  [LooperEngine] keeps one of these per
/// [LooperPluginInstance] slot ID.
class LooperSession {
  /// Current state-machine phase for this slot.
  LooperState state;

  /// All recorded tracks for this slot (parallel playback layers).
  final List<LoopTrack> tracks;

  /// Transport beat position when the current recording pass started.
  /// Used to compute [TimestampedMidiEvent.beatOffset] for each event.
  double recordingStartBeat;

  /// Notes heard per bar during the current recording pass, used for
  /// per-bar chord detection at each bar boundary.
  /// Key = bar index relative to recording start; value = set of MIDI pitches.
  final Map<int, Set<int>> notesInBar;

  /// The last recording-relative bar index whose notes have been flushed to
  /// [LoopTrack.chordPerBar].  Updated each time [_detectBeatCrossings]
  /// advances past a bar boundary.  Allows [stopRecording] to flush any
  /// bars that crossed just before the user pressed stop (i.e. before the
  /// next timer tick had a chance to flush them).
  int prevRelativeBar;

  /// Previous beat-floor value observed by the playback ticker.
  /// Used to detect transport-downbeat crossings for UI notifications.
  double prevBeatFloor;

  /// Actual transport beat position at the end of the previous tick.
  ///
  /// Used instead of a hardcoded "10 ms ago" estimate so that the playback
  /// phase window is accurate even when the Dart timer fires late (GC pause,
  /// heavy UI frame, etc.).  Initialised to [recordingStartBeat] when
  /// playback begins so the first tick fires from the correct position.
  double prevPlaybackBeat;

  /// Map from CC number → action bound to that CC for this slot.
  final Map<int, LooperAction> ccAssignments;

  LooperSession()
      : state = LooperState.idle,
        tracks = [],
        recordingStartBeat = 0.0,
        notesInBar = {},
        prevRelativeBar = 0,
        prevBeatFloor = 0.0,
        prevPlaybackBeat = 0.0,
        ccAssignments = {};

  // ── Derived helpers ────────────────────────────────────────────────────

  /// True when the slot is actively accepting MIDI input for a new recording.
  bool get isRecordingActive =>
      state == LooperState.recording || state == LooperState.overdubbing;

  /// True when the slot should be firing recorded MIDI events.
  bool get isPlayingActive =>
      state == LooperState.playing || state == LooperState.overdubbing;

  /// The track that is currently being written to (recording / overdub pass),
  /// or null if no recording is in progress.
  LoopTrack? get activeRecordingTrack =>
      isRecordingActive ? tracks.lastOrNull : null;

  // ── JSON ───────────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'tracks': tracks.map((t) => t.toJson()).toList(),
        // Volatile fields (state, playheads, recording timestamps) are not
        // persisted — the looper always starts in idle after a project load.
      };

  void loadFromJson(Map<String, dynamic> json) {
    tracks.clear();
    final rawTracks = json['tracks'] as List<dynamic>? ?? [];
    for (final t in rawTracks) {
      tracks.add(LoopTrack.fromJson(t as Map<String, dynamic>));
    }
  }
}

// ── Looper engine ─────────────────────────────────────────────────────────────

/// Central service that manages MIDI looper sessions for every
/// [LooperPluginInstance] slot in the rack.
///
/// ### Timing model
/// The engine runs a private 10 ms [Timer.periodic] whenever at least one
/// session is actively playing or recording.  On each tick it reads
/// [TransportEngine.positionInBeats] as the authoritative clock and fires any
/// MIDI events whose beat offset has been passed since the last tick.
///
/// This avoids coupling to [TransportEngine.onBeat] (which has only one
/// callback slot) and is self-correcting: if a tick fires late, the next tick
/// catches up all missed events.
///
/// ### Bar-sync on loop end
/// When [stopRecording] is called, the loop length is rounded up to the
/// nearest whole bar boundary.  On the next downbeat the loop begins playing
/// immediately.  If the user stopped recording slightly *after* a downbeat
/// (within [_syncToleranceBeat] beats), the engine treats it as "just missed"
/// and starts playback immediately rather than waiting a full extra bar.
///
/// ### Chord detection
/// During recording, at each bar-crossing the engine collects all note pitches
/// heard in the bar that just ended and calls [LoopTrack.detectAndStoreChord].
/// The result is shown in the looper UI as a chord grid.
class LooperEngine extends ChangeNotifier {
  final TransportEngine _transport;

  /// Per-slot sessions, keyed by [LooperPluginInstance.id].
  final Map<String, LooperSession> _sessions = {};

  /// Callback invoked when the looper wants to emit a MIDI event during
  /// playback.  The rack screen registers this to dispatch to connected slots.
  ///
  /// Parameters: slotId (source looper slot), status, data1, data2.
  void Function(String slotId, int status, int data1, int data2)?
      onMidiPlayback;

  /// Called whenever persistent recorded data changes — specifically after
  /// [stopRecording] completes a pass and after [clearAll].
  ///
  /// Use this to trigger project autosave rather than [addListener], which
  /// fires on every playback tick (every bar boundary) and would cause
  /// excessive writes to disk.
  VoidCallback? onDataChanged;

  /// 10 ms ticker driving beat-accurate playback across all sessions.
  Timer? _ticker;

  LooperEngine(this._transport);

  // ── Session lifecycle ──────────────────────────────────────────────────

  /// Returns an unmodifiable view of all sessions.
  UnmodifiableMapView<String, LooperSession> get sessions =>
      UnmodifiableMapView(_sessions);

  /// Returns the session for [slotId], or null if not yet initialised.
  LooperSession? session(String slotId) => _sessions[slotId];

  /// Creates a session for [slotId] if one does not already exist.
  void ensureSession(String slotId) {
    _sessions.putIfAbsent(slotId, LooperSession.new);
  }

  /// Removes the session for [slotId] and its associated recordings.
  void removeSession(String slotId) {
    _sessions.remove(slotId);
    _updateTicker();
    notifyListeners();
  }

  // ── Recording control ──────────────────────────────────────────────────

  /// Begins a new recording pass for [slotId].
  ///
  /// If the transport is playing, recording starts immediately.  If the
  /// transport is stopped, the session enters [LooperState.armed] and will
  /// begin recording automatically when play is pressed.
  void startRecording(String slotId) {
    final s = _requireSession(slotId);
    final alreadyPlaying = s.state == LooperState.playing;

    if (_transport.isPlaying) {
      _beginRecordingPass(s);
      s.state =
          alreadyPlaying ? LooperState.overdubbing : LooperState.recording;
    } else {
      s.state = LooperState.armed;
    }

    _updateTicker();
    notifyListeners();
  }

  /// Ends the current recording pass for [slotId], quantises the loop length
  /// to the nearest bar boundary, and transitions to [LooperState.playing].
  ///
  /// If there are no completed tracks (first recording stopped immediately),
  /// transitions back to [LooperState.idle] instead.
  void stopRecording(String slotId) {
    final s = _requireSession(slotId);
    if (!s.isRecordingActive) return;

    final track = s.activeRecordingTrack;
    if (track != null) {
      final rawLength = _transport.positionInBeats - s.recordingStartBeat;
      track.lengthInBeats = _quantiseToBar(rawLength);
      _sortTrackEvents(track);
    }

    // Flush any bars that have not yet been processed by the timer tick.
    // This covers two cases:
    //   1. The final partial bar (still being recorded when stop was pressed).
    //   2. A bar boundary that crossed just before stop but after the last tick,
    //      so prevRelativeBar is behind by one or more bars.
    final finalRelBar = _currentRelativeBar(s);
    for (int bar = s.prevRelativeBar; bar <= finalRelBar; bar++) {
      _flushBarChord(s, barIndex: bar);
    }
    s.prevRelativeBar = finalRelBar;

    final hasPlayableTracks =
        s.tracks.any((t) => t.lengthInBeats != null && t.events.isNotEmpty);
    s.state = hasPlayableTracks ? LooperState.playing : LooperState.idle;

    if (s.state == LooperState.playing) {
      // For a first recording (not an overdub), anchor prevPlaybackBeat to
      // recordingStartBeat so the first tick's event window starts at loop
      // phase 0 and notes at the very beginning of the loop are not skipped.
      // For overdubs the loop is already playing, so we stay at the current
      // transport position to keep the phase window continuous.
      final isFirstRecording = s.tracks.length == 1;
      s.prevPlaybackBeat = isFirstRecording
          ? s.recordingStartBeat
          : _transport.positionInBeats;
    }

    _updateTicker();
    notifyListeners();
    // Notify after state is fully settled so that autosave captures the
    // completed track data.
    onDataChanged?.call();
  }

  /// Convenience toggle: arms/starts a new recording pass, or stops recording.
  void toggleRecord(String slotId) {
    final s = _requireSession(slotId);
    if (s.isRecordingActive) {
      stopRecording(slotId);
    } else {
      startRecording(slotId);
    }
  }

  // ── Playback control ───────────────────────────────────────────────────

  /// Starts playback for [slotId], quantised to the next bar boundary.
  ///
  /// If the current transport position is already at (or within 0.1 beats of)
  /// a bar-1 downbeat, playback begins immediately.  Otherwise the session
  /// enters [LooperState.waitingForBar]: the 10 ms ticker keeps running, and
  /// [_checkWaitingForBar] fires the actual start when bar 1 arrives.
  ///
  /// This ensures the loop always launches in sync with the metronome —
  /// pressing play mid-bar never causes a phase offset.
  void startPlayback(String slotId) {
    final s = _requireSession(slotId);
    final hasContent =
        s.tracks.any((t) => t.lengthInBeats != null && t.events.isNotEmpty);
    if (!hasContent ||
        s.state == LooperState.playing ||
        s.state == LooperState.waitingForBar) {
      return;
    }

    final pos = _transport.positionInBeats;

    if (_isAtBarBoundary(pos)) {
      // Already on a bar-1 downbeat — prime prevBeatFloor to just before pos
      // so that _activatePlayback's first _tickTrack window covers any events
      // at the downbeat phase.  A sub-microsecond epsilon is sufficient.
      s.prevBeatFloor = pos - 1e-6;
      _activatePlayback(s, pos);
    } else {
      // Arm the bar-sync wait.  prevBeatFloor is set to the current position
      // so _checkWaitingForBar can detect the NEXT beat crossing correctly.
      s.prevBeatFloor = pos;
      s.state = LooperState.waitingForBar;
      _updateTicker();
      notifyListeners();
    }
  }

  /// Returns true if [pos] is within 0.1 beats of a bar-1 downbeat.
  ///
  /// Downbeat beat-floors satisfy `(floor - 1) % timeSigNumerator == 0`
  /// (the TransportEngine fires beat 1 immediately at start and advances
  /// positionInBeats to 1.0, so downbeats land at 1, 5, 9, … for 4/4).
  bool _isAtBarBoundary(double pos) {
    final floor = pos.floor();
    final frac = pos - floor;
    return frac < 0.1 && (floor - 1) % _transport.timeSigNumerator == 0;
  }

  /// Transitions [s] to [LooperState.playing], anchored to [anchorBeat].
  ///
  /// Called from [startPlayback] (immediate path, already on a downbeat) and
  /// from [_checkWaitingForBar] (deferred path, bar just arrived).
  ///
  /// ### recordingStartBeat realignment
  ///
  /// Each [TimestampedMidiEvent.beatOffset] is `transportBeat - recordingStartBeat`
  /// at record time.  The first event has some `firstOffset` (e.g. 1.64 beats —
  /// the gap between pressing record and playing the first note on bar 1).
  ///
  /// We want that first note to fire exactly at [anchorBeat], so:
  /// ```
  ///   phase(anchorBeat) = firstOffset
  ///   (anchorBeat − recordingStartBeat) % loopLen = firstOffset
  ///   → recordingStartBeat = anchorBeat − firstOffset
  /// ```
  ///
  /// This is correct both when the session was just recorded (same transport
  /// session) and after a project reload where `recordingStartBeat` has been
  /// reset to 0 — no JSON persistence of `recordingStartBeat` is required.
  ///
  /// ### prevPlaybackBeat initialisation
  ///
  /// [s.prevBeatFloor] holds the transport beat from the last ticker tick
  /// before this downbeat.  Using it as [s.prevPlaybackBeat] makes the first
  /// [_tickTrack] event window straddle [anchorBeat], so events at the
  /// downbeat phase fire immediately rather than one loop iteration later.
  ///
  /// ### Unified code path
  ///
  /// Both the bar-highlight and the audio fire on the **same** tick:
  /// [_detectBeatCrossings] notifies listeners when it sees the beat-floor
  /// advance past [anchorBeat], while [_tickTrack] fires the MIDI events.
  void _activatePlayback(LooperSession s, double anchorBeat) {
    // Re-anchor recordingStartBeat so the first note of the loop always fires
    // exactly at anchorBeat (the bar downbeat), regardless of where in the
    // transport the recording originally started.
    //
    // Why: all TimestampedMidiEvent.beatOffset values are relative to
    // recordingStartBeat.  The first note has beatOffset = firstOffset (e.g.
    // 1.64 beats after the user pressed record).  For it to fire at anchorBeat
    // we need:
    //   phase(anchorBeat) = firstOffset
    //   (anchorBeat - recordingStartBeat) % loopLen = firstOffset
    //   → recordingStartBeat = anchorBeat - firstOffset
    //
    // This is correct both in the "live" case (just recorded, same session)
    // and after a project reload (recordingStartBeat defaults to 0.0, which
    // would otherwise misalign the loop by firstOffset beats).
    //
    // prevPlaybackBeat is set to s.prevBeatFloor (the transport beat from the
    // last tick before the downbeat) so the first _tickTrack window straddles
    // anchorBeat and fires events at that exact phase.
    final firstOffset = _firstEventOffset(s);
    s.recordingStartBeat = anchorBeat - firstOffset;
    s.prevPlaybackBeat = s.prevBeatFloor;
    s.state = LooperState.playing;
    _updateTicker();
    notifyListeners();
    debugPrint(
      '[Looper] _activatePlayback: anchorBeat=$anchorBeat  '
      'firstOffset=$firstOffset  '
      'recordingStartBeat=${s.recordingStartBeat}  '
      'prevPlaybackBeat=${s.prevPlaybackBeat}  '
      'time=${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  /// Returns the beat offset of the earliest event across all playable tracks.
  ///
  /// Used by [_activatePlayback] to compute the correct [LooperSession.recordingStartBeat]
  /// so that the first note of the loop fires at the bar downbeat.
  ///
  /// Events within each track are already sorted by [_sortTrackEvents], so
  /// index 0 is the earliest.  Returns 0.0 when no events are found.
  double _firstEventOffset(LooperSession s) {
    for (final track in s.tracks) {
      if (track.lengthInBeats == null || track.events.isEmpty) continue;
      // Tracks are ordered by recording time (base loop first, then overdubs).
      // The first non-empty track's first event defines the loop's start.
      return track.events[0].beatOffset;
    }
    return 0.0;
  }

  /// Pauses playback without clearing recordings.
  void pausePlayback(String slotId) {
    final s = _requireSession(slotId);
    if (s.state != LooperState.playing) return;
    s.state = LooperState.idle;
    // Release any notes that were held during playback so they do not ring
    // indefinitely after the looper stops.
    _silenceAllTracks(slotId, s);
    _updateTicker();
    notifyListeners();
  }

  /// Convenience toggle: starts or pauses playback.
  void togglePlay(String slotId) {
    final s = _requireSession(slotId);
    switch (s.state) {
      case LooperState.playing:
        pausePlayback(slotId);
      case LooperState.idle:
        startPlayback(slotId);
      case LooperState.waitingForBar:
        // Second tap cancels the pending bar-sync and returns to idle.
        s.state = LooperState.idle;
        _updateTicker();
        notifyListeners();
      default:
        break;
    }
  }

  /// Stops all activity for [slotId] and returns to [LooperState.idle].
  /// Does NOT erase recorded tracks.
  void stop(String slotId) {
    final s = _requireSession(slotId);
    if (s.state == LooperState.idle) return;
    s.state = LooperState.idle;
    _silenceAllTracks(slotId, s);
    _updateTicker();
    notifyListeners();
  }

  /// Erases all recorded tracks for [slotId] and resets to idle.
  void clearAll(String slotId) {
    final s = _requireSession(slotId);
    _silenceAllTracks(slotId, s);
    s.tracks.clear();
    s.notesInBar.clear();
    s.state = LooperState.idle;
    _updateTicker();
    notifyListeners();
    onDataChanged?.call();
  }

  // ── MIDI input ─────────────────────────────────────────────────────────

  /// Feeds an incoming MIDI event to [slotId]'s recording buffer.
  ///
  /// Called by the rack screen for every MIDI event arriving on the cable
  /// connected to the looper's MIDI IN jack.  Events are ignored when the
  /// session is not actively recording.
  ///
  /// Note-on pitches are accumulated in [LooperSession.notesInBar] per
  /// relative bar index.  Chord identification runs only at bar boundaries
  /// (in [_detectBeatCrossings]) and at recording stop, so the complete set
  /// of notes played during a bar — not just the first three — is used.  This
  /// prevents false matches caused by partial note sets (e.g. {C, G} from an
  /// octave-doubled C before Eb and Bb are played, which a chord detector
  /// would label as a "C5" power chord rather than the intended CmMaj7).
  void feedMidiEvent(String slotId, int status, int data1, int data2) {
    final s = _sessions[slotId];
    if (s == null || !s.isRecordingActive) return;

    final track = s.activeRecordingTrack;
    if (track == null) return;

    final beatOffset = _transport.positionInBeats - s.recordingStartBeat;
    track.events.add(TimestampedMidiEvent(
      beatOffset: beatOffset,
      status: status,
      data1: data1,
      data2: data2,
    ));

    // Accumulate note-on pitches per bar for end-of-bar chord detection.
    // Note-offs and CC events are not relevant for chord identification.
    final isNoteOn = (status & 0xF0) == 0x90 && data2 > 0;
    if (!isNoteOn) return;

    final relativeBar = _currentRelativeBar(s);
    s.notesInBar.putIfAbsent(relativeBar, HashSet.new).add(data1);
  }

  // ── CC assignment ──────────────────────────────────────────────────────

  /// Binds [cc] to [action] for [slotId].
  void setCcAssignment(String slotId, int cc, LooperAction action) {
    _requireSession(slotId).ccAssignments[cc] = action;
    notifyListeners();
  }

  /// Removes the CC binding for [cc] in [slotId].
  void removeCcAssignment(String slotId, int cc) {
    _requireSession(slotId).ccAssignments.remove(cc);
    notifyListeners();
  }

  /// Handles an incoming CC event for [slotId] if a binding exists.
  ///
  /// Standard convention: value ≥ 64 = button press (trigger action);
  /// value < 64 = button release (ignored for toggle actions).
  void handleCc(String slotId, int cc, int value) {
    if (value < 64) return; // ignore release half
    final action = _sessions[slotId]?.ccAssignments[cc];
    switch (action) {
      case LooperAction.toggleRecord:
        toggleRecord(slotId);
      case LooperAction.togglePlay:
        togglePlay(slotId);
      case LooperAction.stop:
        stop(slotId);
      case LooperAction.clearAll:
        clearAll(slotId);
      case null:
        break;
    }
  }

  // ── Track modifiers ────────────────────────────────────────────────────

  /// Toggles the mute state of [trackId] in [slotId].
  void toggleMute(String slotId, String trackId) {
    final track = _findTrack(slotId, trackId);
    if (track == null) return;
    track.muted = !track.muted;
    notifyListeners();
  }

  /// Toggles the reversed flag of [trackId] in [slotId].
  void toggleReverse(String slotId, String trackId) {
    final track = _findTrack(slotId, trackId);
    if (track == null) return;
    track.reversed = !track.reversed;
    notifyListeners();
  }

  /// Sets the [speed] modifier for [trackId] in [slotId].
  void setSpeed(String slotId, String trackId, LoopTrackSpeed speed) {
    final track = _findTrack(slotId, trackId);
    if (track == null) return;
    track.speed = speed;
    notifyListeners();
  }

  /// Removes [trackId] from [slotId].
  void removeTrack(String slotId, String trackId) {
    final s = _sessions[slotId];
    s?.tracks.removeWhere((t) => t.id == trackId);
    notifyListeners();
  }

  // ── Transport-arm bridge ───────────────────────────────────────────────

  /// Called by the rack screen when the global transport starts playing.
  ///
  /// Any [armed] session transitions immediately to [recording] so that
  /// recording starts in sync with the beat.
  void onTransportPlay() {
    bool changed = false;
    for (final entry in _sessions.entries) {
      if (entry.value.state == LooperState.armed) {
        _beginRecordingPass(entry.value);
        entry.value.state = LooperState.recording;
        changed = true;
      }
    }
    if (changed) {
      _updateTicker();
      notifyListeners();
    }
  }

  // ── Playback position queries ──────────────────────────────────────────

  /// Returns the 0-based bar index currently being replayed for [track] inside
  /// [slotId]'s session, or null when the session is not playing.
  ///
  /// Accounts for the track's [LoopTrackSpeed] so a ½× track that spans 2 bars
  /// of the transport clock still reports the correct bar within its own
  /// loop-beat space.
  int? currentPlaybackBarForTrack(String slotId, LoopTrack track) {
    final s = _sessions[slotId];
    if (s == null || !s.isPlayingActive) return null;
    if (track.lengthInBeats == null) return null;

    final loopLen = track.lengthInBeats!;
    final mul = speedMultiplier(track.speed);

    // Effective length in transport-clock beats.
    final effectiveLen = loopLen / mul;

    // Current phase within the loop in loop-beat space (0 → loopLen).
    final rawPhase =
        (_transport.positionInBeats - s.recordingStartBeat) % effectiveLen;
    final loopPhase = rawPhase * mul;

    return (loopPhase / _transport.timeSigNumerator).floor();
  }

  // ── JSON persistence ───────────────────────────────────────────────────

  /// Serialises all sessions (tracks only; volatile state is not saved).
  Map<String, dynamic> toJson() => _sessions.map(
        (slotId, session) => MapEntry(slotId, session.toJson()),
      );

  /// Loads sessions from [json].  Existing sessions are replaced.
  void loadFromJson(Map<String, dynamic> json) {
    _sessions.clear();
    for (final entry in json.entries) {
      final s = LooperSession();
      s.loadFromJson(entry.value as Map<String, dynamic>);
      _sessions[entry.key] = s;
    }
    _updateTicker();
    notifyListeners();
  }

  // ── Internal helpers ───────────────────────────────────────────────────

  /// Returns the session for [slotId], throwing if it does not exist.
  LooperSession _requireSession(String slotId) {
    final s = _sessions[slotId];
    if (s == null) throw StateError('No looper session for slot $slotId');
    return s;
  }

  /// Initialises a new recording pass on [session]: creates a fresh [LoopTrack]
  /// and captures the current transport beat as the reference point.
  void _beginRecordingPass(LooperSession session) {
    final trackId = 'track_${DateTime.now().millisecondsSinceEpoch}';
    session.tracks.add(LoopTrack(id: trackId));
    session.recordingStartBeat = _transport.positionInBeats;
    session.notesInBar.clear();
    session.prevRelativeBar = 0;
    session.prevBeatFloor = _transport.positionInBeats;
  }

  /// Quantises [rawBeats] to the nearest whole-bar boundary.
  ///
  /// A bar is [_transport.timeSigNumerator] beats long.  The result is always
  /// at least one full bar so that very short recordings are still usable.
  ///
  /// Uses `round()` instead of `ceil()` so that pressing stop a few beats
  /// past a bar boundary snaps back to that boundary rather than adding a
  /// full extra bar of silence before the loop restarts.
  double _quantiseToBar(double rawBeats) {
    final beatsPerBar = _transport.timeSigNumerator.toDouble();
    final bars = (rawBeats / beatsPerBar).round().clamp(1, 1 << 20);
    return bars * beatsPerBar;
  }

  /// Returns the recording-relative bar index for the current transport
  /// position.
  ///
  /// Bar 0 spans `[recordingStartBeat, recordingStartBeat + N)`, bar 1 spans
  /// the next N beats, etc. (N = [TransportEngine.timeSigNumerator]).
  ///
  /// This is independent of the global transport bar grid: recording can start
  /// anywhere mid-bar without causing notes to be misclassified into the wrong
  /// relative bar.
  int _currentRelativeBar(LooperSession session) {
    final beats = (_transport.positionInBeats - session.recordingStartBeat)
        .clamp(0.0, double.infinity);
    return (beats / _transport.timeSigNumerator).floor();
  }

  /// Runs chord detection on [barIndex] (relative to recording start) and
  /// stores the result in the active recording track.
  ///
  /// Called at bar boundaries (passing the bar that just *ended*) and at
  /// recording stop (passing the current partial bar).
  ///
  /// Bars with no notes played (e.g. a partial tail bar the user recorded
  /// nothing in) are skipped so they do not add empty "—" cells to the chord
  /// grid beyond the actual recorded content.
  void _flushBarChord(LooperSession session, {required int barIndex}) {
    final track = session.activeRecordingTrack;
    if (track == null) return;

    // Use the full set of notes accumulated across the entire bar so that
    // chords are identified from all notes played, not just the first three.
    final notes = session.notesInBar[barIndex];
    if (notes == null || notes.isEmpty) return;

    track.detectAndStoreChord(barIndex, notes);
  }

  /// Sorts [track.events] by beat offset so playback iteration is O(scan).
  void _sortTrackEvents(LoopTrack track) {
    track.events.sort((a, b) => a.beatOffset.compareTo(b.beatOffset));
  }

  LoopTrack? _findTrack(String slotId, String trackId) =>
      _sessions[slotId]
          ?.tracks
          .where((t) => t.id == trackId)
          .firstOrNull;

  // ── Ticker management ──────────────────────────────────────────────────

  /// Starts or stops the 10 ms playback ticker based on whether any session
  /// is actively recording or playing.
  void _updateTicker() {
    final needsTicker = _sessions.values.any(
      (s) =>
          s.isPlayingActive ||
          s.isRecordingActive ||
          s.state == LooperState.waitingForBar,
    );
    if (needsTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(milliseconds: 10), _tick);
    } else if (!needsTicker && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  // ── Playback tick ──────────────────────────────────────────────────────

  /// Fires on every 10 ms timer tick.
  ///
  /// For each playing session, advances per-track playheads and emits any
  /// MIDI events that have become due since the last tick.  Also handles:
  /// - Beat-crossing detection for per-bar chord snapshotting during recording.
  /// - "Just missed a downbeat" snap-to-start for loop phase alignment.
  /// - Transport stop detection (pauses all active sessions).
  void _tick(Timer _) {
    if (!_transport.isPlaying) {
      _handleTransportStopped();
      return;
    }

    final currentBeat = _transport.positionInBeats;

    for (final session in _sessions.values) {
      _tickSession(session, currentBeat);
    }
  }

  void _handleTransportStopped() {
    bool changed = false;
    for (final entry in _sessions.entries) {
      final s = entry.value;
      if (s.isPlayingActive ||
          s.isRecordingActive ||
          s.state == LooperState.waitingForBar) {
        s.state = LooperState.idle;
        _silenceAllTracks(entry.key, s);
        changed = true;
      }
    }
    if (changed) {
      _updateTicker();
      notifyListeners();
    }
  }

  void _tickSession(LooperSession session, double currentBeat) {
    // If we are waiting for a bar boundary, check for it and return early —
    // no chord detection or MIDI playback until the bar fires.
    if (session.state == LooperState.waitingForBar) {
      _checkWaitingForBar(session, currentBeat);
      return;
    }

    // Detect beat crossings for chord detection during recording.
    _detectBeatCrossings(session, currentBeat);

    if (session.isPlayingActive) {
      final slotId = _slotIdFor(session);
      if (slotId != null) {
        for (final track in session.tracks) {
          if (track.muted || track.lengthInBeats == null) continue;
          _tickTrack(slotId, session, track, currentBeat);
        }
      }
    }

    // Advance the stored beat so the next tick has an accurate previous
    // position.  Updated even when not playing so it is fresh when playback
    // resumes (avoids a large catch-up window on the very first playing tick).
    session.prevPlaybackBeat = currentBeat;
  }

  /// Checks whether a bar-1 downbeat has arrived while the session is in
  /// [LooperState.waitingForBar].  When it does, calls [_activatePlayback]
  /// with the exact integer beat of the downbeat so the loop phase is
  /// perfectly aligned to the bar grid.
  void _checkWaitingForBar(LooperSession session, double currentBeat) {
    final currFloor = currentBeat.floor();
    final prevFloor = session.prevBeatFloor.floor();

    if (currFloor > prevFloor) {
      for (int b = prevFloor + 1; b <= currFloor; b++) {
        // Same downbeat formula as TransportEngine: beat 1 was fired at start
        // then positionInBeats was set to 1.0, so bar 1 lands at b=1, 5, 9…
        if ((b - 1) % _transport.timeSigNumerator == 0) {
          // Snap anchor to the exact integer beat rather than currentBeat to
          // eliminate sub-10 ms jitter from the timer firing slightly late.
          _activatePlayback(session, b.toDouble());
          return;
        }
      }
    }

    // No downbeat yet — just advance the cursor.
    session.prevBeatFloor = currentBeat;
  }

  /// Checks whether the recording or playback has crossed a bar boundary since
  /// the last tick, and reacts accordingly.
  ///
  /// **Recording** — uses the recording-relative bar index
  /// ([_currentRelativeBar]) which is independent of the global transport
  /// phase.  When the relative bar advances, all completed bars since the last
  /// flush are processed and [notifyListeners] is called so the chord grid
  /// updates in real time.
  ///
  /// **Playback** — uses the transport-level beat-floor to detect downbeats
  /// (same formula as [TransportEngine.onBeat]).  Notifies listeners on each
  /// downbeat so the chord-grid bar highlight advances.
  void _detectBeatCrossings(LooperSession session, double currentBeat) {
    bool needsNotify = false;

    if (session.isRecordingActive) {
      // Compare the recording-relative bar index against the last flushed bar.
      // If the bar has advanced, flush all completed bars between them.
      final currentRelBar = _currentRelativeBar(session);
      if (currentRelBar > session.prevRelativeBar) {
        for (int bar = session.prevRelativeBar; bar < currentRelBar; bar++) {
          _flushBarChord(session, barIndex: bar);
        }
        session.prevRelativeBar = currentRelBar;
        needsNotify = true;
      }
    } else if (session.isPlayingActive) {
      // Detect transport-level downbeats for the bar-highlight UI pulse.
      final currFloor = currentBeat.floor();
      final prevFloor = session.prevBeatFloor.floor();
      if (currFloor > prevFloor) {
        for (int b = prevFloor + 1; b <= currFloor; b++) {
          // TransportEngine fires beat 1 immediately then sets positionInBeats
          // = 1.0, so downbeats hit at b=5, 9, 13, … → (b-1) % N == 0.
          if ((b - 1) % _transport.timeSigNumerator == 0) {
            needsNotify = true;
            break;
          }
        }
      }
    }

    // Always advance the beat-floor cursor (used for both branches above).
    session.prevBeatFloor = currentBeat;

    if (needsNotify) notifyListeners();
  }

  /// Advances a single track's playhead and emits any due events.
  ///
  /// Uses [LooperSession.prevPlaybackBeat] — the actual transport beat at
  /// the end of the previous tick — to define the event window.  This avoids
  /// the inaccuracy of a hardcoded "10 ms ago" estimate: if the timer fires
  /// late (GC pause, heavy UI frame) no events are silently skipped.
  ///
  /// At loop wrap-around, any notes still held from the previous iteration are
  /// silenced before the new iteration's events are fired.  This prevents notes
  /// whose note-off falls beyond the loop boundary from ringing indefinitely.
  void _tickTrack(
    String slotId,
    LooperSession session,
    LoopTrack track,
    double currentBeat,
  ) {
    final loopLen = track.lengthInBeats!;
    final mul = speedMultiplier(track.speed);

    // Effective loop length in transport-clock beats (adjusted for speed).
    final effectiveLen = loopLen / mul;

    // Current phase in loop-beat space (0 → loopLen, then wraps).
    final rawPhase = (currentBeat - session.recordingStartBeat) % effectiveLen;
    final loopPhase = rawPhase * mul;

    // Previous phase using the actual stored beat (not a hardcoded estimate).
    final prevRaw =
        (session.prevPlaybackBeat - session.recordingStartBeat) % effectiveLen;
    final prevLoopPhase = prevRaw * mul;

    // Detect wrap-around: the previous phase was near loopLen and the current
    // phase is near 0.  Silence any notes still held from the previous
    // iteration before the new iteration begins.
    final didWrap = prevLoopPhase > loopPhase;
    if (didWrap) _silenceTrack(slotId, track);

    _fireEventsBetween(slotId, track, prevLoopPhase, loopPhase, loopLen);
  }

  /// Emits all events whose beat offset falls within (prevPhase, currentPhase].
  ///
  /// Handles the wrap-around case: if [prevPhase] > [currentPhase] the loop
  /// just restarted, so events from [prevPhase] → [loopLen] and 0 →
  /// [currentPhase] are both fired.
  void _fireEventsBetween(
    String slotId,
    LoopTrack track,
    double prevPhase,
    double currentPhase,
    double loopLen,
  ) {
    if (prevPhase <= currentPhase) {
      _fireEventsInRange(slotId, track, prevPhase, currentPhase);
    } else {
      // Loop wrapped: fire tail then head.
      _fireEventsInRange(slotId, track, prevPhase, loopLen);
      _fireEventsInRange(slotId, track, 0.0, currentPhase);
    }
  }

  void _fireEventsInRange(
    String slotId,
    LoopTrack track,
    double from,
    double to,
  ) {
    final events = track.reversed ? track.events.reversed : track.events;
    for (final event in events) {
      final offset = track.reversed
          ? (track.lengthInBeats! - event.beatOffset)
          : event.beatOffset;
      if (offset > from && offset <= to) {
        debugPrint(
          '[Looper] MIDI fire: slotId=$slotId  '
          'beatOffset=$offset  window=($from,$to]  '
          'status=0x${event.status.toRadixString(16)}  '
          'note=${event.data1}  vel=${event.data2}  '
          'time=${DateTime.now().millisecondsSinceEpoch}',
        );
        onMidiPlayback?.call(slotId, event.status, event.data1, event.data2);
        // Track which notes are currently "on" so we can silence them at loop
        // wrap-around or when playback stops.
        _updateActiveNotes(track, event.status, event.data1, event.data2);
      }
    }
  }

  /// Updates [track.activePlaybackNotes] as a MIDI event fires during playback.
  ///
  /// Notes are packed as `(channelNibble << 7) | pitch` for compact storage.
  void _updateActiveNotes(LoopTrack track, int status, int data1, int data2) {
    final cmd = status & 0xF0;
    final key = ((status & 0x0F) << 7) | (data1 & 0x7F);
    if (cmd == 0x90 && data2 > 0) {
      track.activePlaybackNotes.add(key);
    } else if (cmd == 0x80 || (cmd == 0x90 && data2 == 0)) {
      track.activePlaybackNotes.remove(key);
    }
  }

  /// Emits note-off for every note currently held by [track] during playback,
  /// then clears the active-note set.
  ///
  /// Called at loop wrap-around (to prevent notes from bleeding into the next
  /// iteration) and when playback stops (to prevent stuck notes).
  void _silenceTrack(String slotId, LoopTrack track) {
    for (final key in List<int>.from(track.activePlaybackNotes)) {
      final ch = key >> 7;
      final note = key & 0x7F;
      onMidiPlayback?.call(slotId, 0x80 | ch, note, 0);
    }
    track.activePlaybackNotes.clear();
  }

  /// Silences all tracks in [session] — convenience wrapper for stop/pause.
  void _silenceAllTracks(String slotId, LooperSession session) {
    for (final track in session.tracks) {
      _silenceTrack(slotId, track);
    }
  }

  /// Looks up the slot ID that owns [session] by scanning [_sessions].
  /// O(n) on session count — acceptable since the rack is small (< 20 slots).
  String? _slotIdFor(LooperSession session) {
    for (final entry in _sessions.entries) {
      if (identical(entry.value, session)) return entry.key;
    }
    return null;
  }

  // ── Dispose ────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
