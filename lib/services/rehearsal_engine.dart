import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rehearsal.dart';
import 'audio_input_ffi.dart';
import 'rehearsal_tempo_cache.dart';
import 'gfpa_android_bindings.dart';
import 'rehearsal_library.dart';

/// Preference key holding the round trip most recently measured by the latency
/// probe, in frames.
///
/// Stored per device rather than per rehearsal: it is a property of this
/// phone's speaker, microphone and buffer sizes, so every rehearsal on the
/// device starts from the same figure and only diverges if the player nudges
/// one of them.
const String kLatencyCompensationKey = 'gf.rehearsal.compensationFrames';

/// Mix key for the imported master.
///
/// The master is not a part, so it has no part id to key its gain and mute on;
/// this stands in for one inside [RehearsalLocalState].
const String kMasterMixId = 'master';

/// Transport states. Mirrors the C enum in `native_audio/gf_rehearsal.h`.
enum RehearsalTransport { stopped, playing, countIn, recording }

/// Drives the native rehearsal engine for one open rehearsal.
///
/// Owns the mapping between the rehearsal's parts and the engine's track
/// slots, applies the player's own mix, runs the transport, and commits a take
/// to the library when a recording finishes.
///
/// The audio itself never passes through Dart: takes stream from disk inside
/// the engine, and this class only sends control messages and polls position
/// for the playhead (CLAUDE.md Rule 2).
class RehearsalEngine extends ChangeNotifier {
  RehearsalEngine(this._library);

  final RehearsalLibrary _library;

  Rehearsal? _rehearsal;
  RehearsalLocalState _local = RehearsalLocalState();

  /// Part id → native track index, for the parts that have a take loaded.
  final Map<String, int> _trackOf = {};

  /// Native track index of the imported master, or null if there is none.
  int? _masterTrack;

  /// The part currently being recorded into, if any.
  RehearsalPart? _recordingPart;
  String? _recordingFileName;

  Timer? _poll;
  bool _active = false;
  bool _busSourceAdded = false;

  int _positionFrames = 0;
  RehearsalTransport _transport = RehearsalTransport.stopped;
  double _inputPeak = 0.0;

  Rehearsal? get rehearsal => _rehearsal;
  RehearsalLocalState get localState => _local;
  RehearsalTransport get transport => _transport;
  int get positionFrames => _positionFrames;
  double get inputPeak => _inputPeak;
  RehearsalPart? get recordingPart => _recordingPart;

  bool get isRunning => _transport != RehearsalTransport.stopped;

  /// True while the metronome is counting in and nothing is being committed.
  bool get isCountingIn => _transport == RehearsalTransport.countIn;

  int get framesPerBeat => AudioInputFFI().rehFramesPerBeat;
  int get framesPerBar => AudioInputFFI().rehFramesPerBar;

  /// Position as a signed bar number. Negative during the count-in, so the UI
  /// can show "-2, -1" and then bar 1 without a second piece of state.
  int get currentBar {
    final fpb = framesPerBar;
    if (fpb <= 0) return 0;
    return _positionFrames >= 0
        ? _positionFrames ~/ fpb + 1
        : -(((-_positionFrames) + fpb - 1) ~/ fpb);
  }

  /// Beat within the bar, 1-based.
  int get currentBeat {
    final fpb = framesPerBeat;
    final r = _rehearsal;
    if (fpb <= 0 || r == null) return 1;
    var beat = _positionFrames ~/ fpb;
    if (_positionFrames < 0 && _positionFrames % fpb != 0) beat -= 1;
    var inBar = beat % r.beatsPerBar;
    if (inBar < 0) inBar += r.beatsPerBar;
    return inBar + 1;
  }

  // ── Opening and closing ───────────────────────────────────────────────────

  /// Loads [rehearsal] into the engine: grid, every recorded take, and this
  /// device's own mix.
  Future<void> open(Rehearsal rehearsal) async {
    await close();

    _rehearsal = rehearsal;
    _local = await _library.loadLocalState(rehearsal.id);

    // If this device's own member was removed while it was away, it is not a
    // member any more. Clearing the id makes it a fresh joiner rather than a
    // ghost that owns nothing, cannot record, and matches no lane — and the
    // tombstone means simply re-adding the old id would not survive a sync.
    final selfId = _local.selfMemberId;
    if (selfId != null && rehearsal.deletedMemberIds.contains(selfId)) {
      debugPrint('RehearsalEngine: this device was removed from the band');
      _local.selfMemberId = null;
      await _library.saveLocalState(rehearsal.id, _local);
    }

    // A rehearsal that has never been calibrated adopts whatever the latency
    // probe last measured on this device, so the player does not have to
    // re-measure for every tune they start.
    if (_local.compensationFrames == 0) {
      final prefs = await SharedPreferences.getInstance();
      final measured = prefs.getInt(kLatencyCompensationKey) ?? 0;
      if (measured > 0) {
        _local.compensationFrames = measured;
        await _library.saveLocalState(rehearsal.id, _local);
      }
    }

    final ffi = AudioInputFFI();
    if (ffi.rehActivate() != 0) {
      debugPrint('RehearsalEngine: native engine would not start');
      return;
    }
    _active = true;
    _addBusSource();

    // The engine is fed by the app's capture device, and nothing opens that
    // until something asks for the microphone. Without this a take records
    // silence — the transport runs, the metronome clicks, and the file comes
    // out empty.
    //
    // permission_handler is only registered for Android and iOS in this
    // project; the desktop builds open the microphone directly, exactly as the
    // Live Input module does.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        debugPrint('RehearsalEngine: microphone denied — playback only');
      }
    }
    ffi.startCapture();

    ffi.rehSetGrid(_local.effectiveBpm(rehearsal.bpm), rehearsal.beatsPerBar,
        rehearsal.beatUnit);
    ffi.rehSetMetronome(
        enabled: _local.metronomeEnabled, gain: 0.6);

    await _loadTracks();
    _startPolling();
    notifyListeners();
  }

  /// Loads every recorded part as a native track and applies the local mix.
  ///
  /// When the tune is not playing at the tempo its recordings were made at,
  /// each one is rendered to the new tempo first and the rendered file is what
  /// gets loaded. The engine itself has no idea any of this happened: it opens
  /// a mono WAV and streams it, exactly as before.
  Future<void> _loadTracks() async {
    final r = _rehearsal;
    if (r == null) return;
    final ffi = AudioInputFFI();

    await _renderForTempo(r);
    _applyFormLength(r);

    ffi.rehClearTracks();
    _trackOf.clear();
    _masterTrack = null;

    // The master goes in first so it holds the lowest slot and is easy to spot
    // in a log; nothing depends on the order.
    final master = r.master;
    if (master != null) {
      final ratio = _ratioFor(master.nativeBpm, r);
      final path = await _pathForMaster(r, master, ratio);
      final idx = ffi.rehAddTrack(path);
      if (idx < 0) {
        debugPrint('RehearsalEngine: could not load the master ($idx)');
      } else {
        _masterTrack = idx;
        // This is what puts the tune's first downbeat on the grid's downbeat.
        // Scaled by the same ratio the audio was: the downbeat sits at the
        // same musical place, which is a different number of frames once the
        // recording has been stretched.
        ffi.rehSetTrackOffset(idx, (master.offsetFrames * ratio).round());
        ffi.rehSetTrackGain(idx, _local.gainFor(kMasterMixId));
        ffi.rehSetTrackMute(idx, _local.isMuted(kMasterMixId));
      }
    }

    for (final part in r.parts) {
      final take = part.take;
      if (take == null) continue;
      final ratio = _ratioFor(take.recordedBpm, r);
      final path = await _pathForTake(r, take, ratio);
      final idx = ffi.rehAddTrack(path);
      if (idx < 0) {
        debugPrint('RehearsalEngine: could not load ${take.fileName} ($idx)');
        continue;
      }
      _trackOf[part.id] = idx;
      ffi.rehSetTrackGain(idx, _local.gainFor(part.id));
      ffi.rehSetTrackMute(idx, _local.isMuted(part.id));
    }
  }

  /// Tells the engine how long the written form is.
  ///
  /// A band that types out a chart and presses play should hear the click run
  /// through it, rather than have the transport stop at once because nothing
  /// is recorded yet. Re-applied whenever the tracks reload, because the bar
  /// length moves with the tempo.
  void _applyFormLength(Rehearsal r) {
    final ffi = AudioInputFFI();
    final bars = r.formBars;
    ffi.rehSetFormEnd(bars <= 0 ? 0 : bars * ffi.rehFramesPerBar);
  }

  /// Rewrites the tune's form and tells the engine its new length.
  ///
  /// Stamped through updateField so the edit is visible to the merge; the grid
  /// travels as one value, because a chart is a shape rather than a stream of
  /// independent edits.
  Future<void> setChords(List<RehearsalBar> bars) async {
    final r = _rehearsal;
    if (r == null) return;
    await _library.updateField(r, RehearsalField.chords, () {
      r.chords = bars;
    });
    _applyFormLength(r);
    notifyListeners();
  }

  /// How much a recording made at [nativeBpm] has to stretch to fit the tune
  /// as it is being played here.
  ///
  /// Above 1 means longer, which is what slowing down asks for. A recording
  /// with no tempo recorded — nothing on disk should have one after the
  /// library's migration — is left alone rather than guessed at.
  double _ratioFor(double nativeBpm, Rehearsal r) {
    if (nativeBpm <= 0) return 1.0;
    final target = _local.effectiveBpm(r.bpm);
    if (target <= 0) return 1.0;
    return (nativeBpm / target).clamp(0.25, 4.0);
  }

  Future<String> _pathForTake(
      Rehearsal r, RehearsalTake take, double ratio) async {
    if (!RehearsalTempoCache.needsRender(ratio)) {
      return _library.takePath(r.id, take);
    }
    final dir = await _library.tempoDir(r.id);
    return '${dir.path}/'
        '${RehearsalTempoCache.fileNameFor(take.fileName, ratio)}';
  }

  Future<String> _pathForMaster(
      Rehearsal r, RehearsalMaster master, double ratio) async {
    if (!RehearsalTempoCache.needsRender(ratio)) {
      return _library.masterPath(r.id, master);
    }
    final dir = await _library.tempoDir(r.id);
    return '${dir.path}/'
        '${RehearsalTempoCache.fileNameFor(master.fileName, ratio)}';
  }

  /// True while recordings are being rendered to a new tempo.
  ///
  /// Surfaced so the screen can say what it is waiting for. A few seconds of
  /// unexplained silence after moving a slider reads as a bug.
  bool get isRendering => _rendering;
  bool _rendering = false;

  /// Renders whatever this tempo needs and clears out what it does not.
  Future<void> _renderForTempo(Rehearsal r) async {
    final jobs = <StretchJob>[];
    final keep = <String>{};
    final dir = await _library.tempoDir(r.id);

    Future<void> plan(String sourcePath, String fileName, double bpm) async {
      final ratio = _ratioFor(bpm, r);
      if (!RehearsalTempoCache.needsRender(ratio)) return;
      final name = RehearsalTempoCache.fileNameFor(fileName, ratio);
      keep.add(name);
      jobs.add(StretchJob(
        source: sourcePath,
        destination: '${dir.path}/$name',
        ratio: ratio,
      ));
    }

    final master = r.master;
    if (master != null) {
      await plan(await _library.masterPath(r.id, master), master.fileName,
          master.nativeBpm);
    }
    for (final part in r.parts) {
      final take = part.take;
      if (take == null) continue;
      await plan(
          await _library.takePath(r.id, take), take.fileName, take.recordedBpm);
    }

    if (jobs.isNotEmpty) {
      _rendering = true;
      notifyListeners();
      try {
        await _tempoCache.render(jobs);
      } finally {
        _rendering = false;
        notifyListeners();
      }
    }
    // Swept afterwards, never before: the files being replaced may still be
    // open in the engine, and a track whose file vanishes underneath it is a
    // worse failure than a few seconds of extra disk use.
    await _tempoCache.sweep(dir, keep);
  }

  final RehearsalTempoCache _tempoCache = RehearsalTempoCache();

  /// Parts whose take is in the manifest but whose audio is not playable here.
  ///
  /// Taken from what actually loaded rather than from a fresh look at the
  /// filesystem: the engine has already tried to open every file, and a track
  /// that is not in [_trackOf] is one that failed.
  ///
  /// This is a real state, not a defensive check. The manifest merges and
  /// saves before a single byte of audio moves, so a session that dies
  /// mid-transfer — or a peer that passes on a take whose audio it does not
  /// have yet — leaves the record of a take without the recording. The next
  /// sync fetches it; until then the lane should say so rather than showing a
  /// duration over silence.
  Set<String> get partsMissingAudio => {
        for (final part in _rehearsal?.parts ?? const <RehearsalPart>[])
          if (part.take != null && !_trackOf.containsKey(part.id)) part.id,
      };

  /// Stops the transport, releases the tracks and stops routing audio.
  Future<void> close() async {
    if (!_active && _rehearsal == null) return;
    _poll?.cancel();
    _poll = null;
    final ffi = AudioInputFFI();
    ffi.rehStop();
    ffi.rehClearTracks();
    ffi.rehDeactivate();
    _removeBusSource();
    _active = false;
    _trackOf.clear();
    _recordingPart = null;
    _rehearsal = null;
    _transport = RehearsalTransport.stopped;
    _positionFrames = 0;
  }

  @override
  void dispose() {
    _poll?.cancel();
    AudioInputFFI().rehStop();
    AudioInputFFI().rehDeactivate();
    _removeBusSource();
    super.dispose();
  }

  // ── Android output routing ────────────────────────────────────────────────
  //
  // Android never opens the miniaudio playback device — output goes through
  // Oboe — so on Android the engine has to register as a bus source to be
  // heard at all. Everywhere else the playback callback mixes it in directly.

  bool get _needsBusSource => !kIsWeb && Platform.isAndroid;

  void _addBusSource() {
    if (!_needsBusSource || _busSourceAdded) return;
    final addr = AudioInputFFI().rehBusRenderFnAddr();
    if (addr == 0) return;
    GfpaAndroidBindings.instance.oboeStreamAddSource(addr, kBusSlotRehearsal);
    _busSourceAdded = true;
  }

  void _removeBusSource() {
    if (!_busSourceAdded) return;
    GfpaAndroidBindings.instance.oboeStreamRemoveSource(kBusSlotRehearsal);
    _busSourceAdded = false;
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  /// Plays from the top.
  void play() {
    if (!_active) return;
    AudioInputFFI().rehPlay(0);
    _transport = RehearsalTransport.playing;
    notifyListeners();
  }

  /// Records [part], counting in and compensating by this device's measured
  /// round trip. Existing takes play underneath so the player hears the band.
  Future<void> record(RehearsalPart part) async {
    final r = _rehearsal;
    if (r == null || !_active) return;

    // A part being re-recorded must not also play back into the take: the
    // player would hear their previous attempt over the top of themselves.
    final existing = _trackOf[part.id];
    if (existing != null) AudioInputFFI().rehSetTrackMute(existing, true);

    final fileName = _library.nextTakeFileName(part);
    final dir = await _library.takesDir(r.id);
    final path = '${dir.path}/$fileName';

    final rc = AudioInputFFI()
        .rehRecord(path, compensationFrames, r.countInBars);
    if (rc != 0) {
      debugPrint('RehearsalEngine: record failed ($rc)');
      if (existing != null) {
        AudioInputFFI().rehSetTrackMute(existing, _local.isMuted(part.id));
      }
      return;
    }
    _recordingPart = part;
    _recordingFileName = fileName;
    _transport = r.countInBars > 0
        ? RehearsalTransport.countIn
        : RehearsalTransport.recording;
    notifyListeners();
  }

  /// Stops the transport, and commits the take if one was being recorded.
  Future<void> stop() async {
    if (!_active) return;
    final ffi = AudioInputFFI();
    final part = _recordingPart;
    final fileName = _recordingFileName;
    // Read before stopping: the engine resets nothing, but the count is the
    // thing the manifest needs and reading it first keeps the order obvious.
    final frames = ffi.rehRecordedFrames;

    ffi.rehStop();
    _transport = RehearsalTransport.stopped;
    _recordingPart = null;
    _recordingFileName = null;

    // Anything that arrived while this was playing is picked up now.
    if (_reloadPending) {
      _reloadPending = false;
      await _loadTracks();
    }

    final r = _rehearsal;
    if (part != null && fileName != null && r != null && frames > 0) {
      await _library.commitTake(r, part,
          fileName: fileName,
          frames: frames,
          sampleRate: 48000,
          compensationFrames: compensationFrames,
          // The tempo it was played at, which is the practice speed if one is
          // set — not the tune's own. Storing the tune's would misfile a take
          // cut at half speed as if it had been played at full.
          recordedBpm: _local.effectiveBpm(r.bpm));
      // Reload so the new take joins the mix and the old slot is released.
      await _loadTracks();
      // And tell whoever is listening, rather than making them wait for the
      // next tick: the player has just stopped and is looking up at the room.
      onTakeCommitted?.call();
    }
    notifyListeners();
  }

  // ── Mix ───────────────────────────────────────────────────────────────────

  Future<void> setGain(RehearsalPart part, double gain) async {
    _local.gains[part.id] = gain;
    final idx = _trackOf[part.id];
    if (idx != null) AudioInputFFI().rehSetTrackGain(idx, gain);
    notifyListeners();
    await _saveLocal();
  }

  Future<void> setMuted(RehearsalPart part, bool muted) async {
    if (muted) {
      _local.mutedPartIds.add(part.id);
    } else {
      _local.mutedPartIds.remove(part.id);
    }
    final idx = _trackOf[part.id];
    if (idx != null) AudioInputFFI().rehSetTrackMute(idx, muted);
    notifyListeners();
    await _saveLocal();
  }

  /// Moves the grid's first downbeat to [offsetFrames] inside the recording,
  /// and applies it straight away so the change can be heard.
  Future<void> setMasterOffset(int offsetFrames) async {
    final r = _rehearsal;
    if (r == null || r.master == null) return;
    await _library.setMasterOffset(r, offsetFrames);
    final idx = _masterTrack;
    if (idx != null) AudioInputFFI().rehSetTrackOffset(idx, offsetFrames);
    notifyListeners();
  }

  /// Sets the tune's tempo, for everyone.
  ///
  /// No longer refused once a take exists: takes carry the tempo they were
  /// played at, so this re-renders them to the new one rather than stranding
  /// them. It syncs, so every device does the same thing on its own copy —
  /// only the number travels, never the rendered audio.
  Future<void> setBpm(double bpm) async {
    final r = _rehearsal;
    if (r == null) return;
    await stop();
    // Through updateField, so the edit is stamped: an unstamped tempo change
    // is invisible to the merge and a peer would silently put it back.
    await _library.updateField(r, RehearsalField.bpm, () {
      r.bpm = bpm;
    });
    await _applyTempo(r);
  }

  /// Sets how fast the tune plays *here*, as a fraction of its own tempo.
  ///
  /// Local, like gain and mute: one person working a hard bar at half speed
  /// should not drag the band down with them, and the tune's written tempo is
  /// left alone.
  Future<void> setPracticeSpeed(double speed) async {
    final r = _rehearsal;
    if (r == null) return;
    final clamped = speed.clamp(0.5, 1.0);
    if ((clamped - _local.practiceSpeed).abs() < 0.001) return;
    await stop();
    _local.practiceSpeed = clamped;
    await _library.saveLocalState(r.id, _local);
    await _applyTempo(r);
  }

  double get practiceSpeed => _local.practiceSpeed;

  /// Moves the grid and the recordings to whatever tempo is now in force.
  ///
  /// Stopped first by the callers, because swapping every track's file out
  /// from under a running transport is not something the engine is built to
  /// survive.
  Future<void> _applyTempo(Rehearsal r) async {
    AudioInputFFI().rehSetGrid(
        _local.effectiveBpm(r.bpm), r.beatsPerBar, r.beatUnit);
    await _loadTracks();
    notifyListeners();
  }

  /// Set when audio arrived while the transport was running.
  bool _reloadPending = false;

  /// Reloads after a master has been imported or removed, or after a peer's
  /// take has arrived.
  ///
  /// Reloading clears every native track and reopens them, which is a dropout
  /// if it happens mid-playback. A take that arrives while the band is
  /// listening therefore waits until the transport stops — a moment away, and
  /// far better than a gap in the middle of the tune.
  Future<void> reloadTracks() async {
    if (isRunning) {
      _reloadPending = true;
      return;
    }
    _reloadPending = false;
    _local = await _library.loadLocalState(_rehearsal?.id ?? '');
    AudioInputFFI()
        .rehSetMetronome(enabled: _local.metronomeEnabled, gain: 0.6);
    await _loadTracks();
    notifyListeners();
  }

  /// Absolute path of the decoded master, or null if there is none.
  Future<String?> masterFilePath() async {
    final r = _rehearsal;
    final m = r?.master;
    if (r == null || m == null) return null;
    return _library.masterPath(r.id, m);
  }

  double get masterGain => _local.gainFor(kMasterMixId);
  bool get isMasterMuted => _local.isMuted(kMasterMixId);

  Future<void> setMasterGain(double gain) async {
    _local.gains[kMasterMixId] = gain;
    final idx = _masterTrack;
    if (idx != null) AudioInputFFI().rehSetTrackGain(idx, gain);
    notifyListeners();
    await _saveLocal();
  }

  Future<void> setMasterMuted(bool muted) async {
    if (muted) {
      _local.mutedPartIds.add(kMasterMixId);
    } else {
      _local.mutedPartIds.remove(kMasterMixId);
    }
    final idx = _masterTrack;
    if (idx != null) AudioInputFFI().rehSetTrackMute(idx, muted);
    notifyListeners();
    await _saveLocal();
  }

  /// Plays a two-bar window from [fromFrame] so the alignment can be checked
  /// by ear rather than only by eye.
  void playFrom(int fromFrame) {
    if (!_active) return;
    AudioInputFFI().rehPlay(fromFrame);
    _transport = RehearsalTransport.playing;
    notifyListeners();
  }

  Future<void> setMetronome(bool enabled) async {
    _local.metronomeEnabled = enabled;
    AudioInputFFI().rehSetMetronome(enabled: enabled, gain: 0.6);
    notifyListeners();
    await _saveLocal();
  }

  /// Re-reads this device's local state from disk.
  ///
  /// Needed when something outside the engine writes it — joining as a member
  /// is the case: the library records the new identity, and the engine is
  /// holding the copy every lane is compared against. Without this the device
  /// would go on thinking it is nobody until the tune was closed and reopened.
  Future<void> reloadLocalState() async {
    final r = _rehearsal;
    if (r == null) return;
    _local = await _library.loadLocalState(r.id);
    notifyListeners();
  }

  /// Picks up whatever the probe last measured on this device.
  ///
  /// The probe writes to shared preferences, which this rehearsal read once
  /// when it opened. Without this, calibrating from inside a rehearsal would
  /// appear to do nothing until the tune was closed and opened again — and the
  /// warning that sent the player to the probe would still be sitting there.
  Future<void> adoptMeasuredCompensation() async {
    final prefs = await SharedPreferences.getInstance();
    final measured = prefs.getInt(kLatencyCompensationKey) ?? 0;
    if (measured <= 0 || measured == compensationFrames) return;
    await setCompensationFrames(measured);
  }

  /// Which output this device is playing through, as far as the engine knows.
  ///
  /// Set by whoever is watching the route. Null means nobody is, which is the
  /// case on desktop — there the single stored figure is used, which is right,
  /// because a laptop's output does not change under it.
  String? _routeKey;

  set routeKey(String? key) {
    if (key == _routeKey) return;
    _routeKey = key;
    notifyListeners();
  }

  String? get routeKey => _routeKey;

  /// The compensation that applies to what the player is listening on.
  int get compensationFrames => _local.compensationFor(_routeKey);

  /// Whether the current route has ever been measured.
  ///
  /// False is worth saying out loud: a Bluetooth headset that has not been
  /// measured will put a take a fifth of a second behind the beat, and the
  /// figure from the speaker is nowhere near close enough to cover it.
  bool get isRouteCalibrated => _local.hasCompensationFor(_routeKey);

  /// Stores the latency compensation measured by the probe, in frames.
  ///
  /// Filed against the route it was measured on as well as kept as the
  /// fallback, so measuring with headphones on no longer overwrites the
  /// speaker's figure.
  Future<void> setCompensationFrames(int frames, {String? forRoute}) async {
    _local.compensationFrames = frames;
    final key = forRoute ?? _routeKey;
    if (key != null) _local.compensationByRoute[key] = frames;
    notifyListeners();
    await _saveLocal();
  }

  Future<void> _saveLocal() async {
    final r = _rehearsal;
    if (r == null) return;
    await _library.saveLocalState(r.id, _local);
  }

  /// Called once a take has been written and the manifest updated, so a live
  /// session can push it without waiting for its next poll.
  void Function()? onTakeCommitted;

  /// Peak level of a part since the last poll, for its meter.
  double peakFor(RehearsalPart part) {
    final idx = _trackOf[part.id];
    if (idx == null) return 0.0;
    return AudioInputFFI().rehTrackPeak(idx);
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  /// Mirrors the native transport into Dart for the playhead and meters.
  ///
  /// 30 Hz: fast enough that the bar counter never looks stuck, slow enough
  /// that it costs nothing. The audio side is unaffected either way — nothing
  /// here feeds back into it.
  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final ffi = AudioInputFFI();
      final pos = ffi.rehPosition;
      final state = ffi.rehState;
      final peak = ffi.rehInputPeak;

      final next = switch (state) {
        1 => RehearsalTransport.playing,
        2 => RehearsalTransport.countIn,
        3 => RehearsalTransport.recording,
        _ => RehearsalTransport.stopped,
      };

      final changed = pos != _positionFrames ||
          next != _transport ||
          (peak - _inputPeak).abs() > 0.01;
      final wasRunning = _transport != RehearsalTransport.stopped;
      _positionFrames = pos;
      _transport = next;
      _inputPeak = peak;

      // The engine stops itself when the last track runs out, so a reload that
      // was deferred during playback has to be picked up here as well as in
      // stop() — otherwise a part that arrived mid-tune would stay silent
      // until the transport was started and stopped by hand.
      if (wasRunning &&
          next == RehearsalTransport.stopped &&
          _reloadPending) {
        _reloadPending = false;
        _loadTracks();
      }

      if (changed) notifyListeners();
    });
  }
}
