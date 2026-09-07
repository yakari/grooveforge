import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rehearsal.dart';
import 'audio_input_ffi.dart';
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

    ffi.rehSetGrid(rehearsal.bpm, rehearsal.beatsPerBar, rehearsal.beatUnit);
    ffi.rehSetMetronome(
        enabled: _local.metronomeEnabled, gain: 0.6);

    await _loadTracks();
    _startPolling();
    notifyListeners();
  }

  /// Loads every recorded part as a native track and applies the local mix.
  Future<void> _loadTracks() async {
    final r = _rehearsal;
    if (r == null) return;
    final ffi = AudioInputFFI();
    ffi.rehClearTracks();
    _trackOf.clear();
    _masterTrack = null;

    // The master goes in first so it holds the lowest slot and is easy to spot
    // in a log; nothing depends on the order.
    final master = r.master;
    if (master != null) {
      final path = await _library.masterPath(r.id, master);
      final idx = ffi.rehAddTrack(path);
      if (idx < 0) {
        debugPrint('RehearsalEngine: could not load the master ($idx)');
      } else {
        _masterTrack = idx;
        // This is what puts the tune's first downbeat on the grid's downbeat.
        ffi.rehSetTrackOffset(idx, master.offsetFrames);
        ffi.rehSetTrackGain(idx, _local.gainFor(kMasterMixId));
        ffi.rehSetTrackMute(idx, _local.isMuted(kMasterMixId));
      }
    }

    for (final part in r.parts) {
      final take = part.take;
      if (take == null) continue;
      final path = await _library.takePath(r.id, take);
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
        .rehRecord(path, _local.compensationFrames, r.countInBars);
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

    final r = _rehearsal;
    if (part != null && fileName != null && r != null && frames > 0) {
      await _library.commitTake(r, part,
          fileName: fileName,
          frames: frames,
          sampleRate: 48000,
          compensationFrames: _local.compensationFrames);
      // Reload so the new take joins the mix and the old slot is released.
      await _loadTracks();
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

  /// Sets the tempo. Refused once a take exists, because every recorded part
  /// is aligned to the current grid.
  Future<void> setBpm(double bpm) async {
    final r = _rehearsal;
    if (r == null || r.isGridFrozen) return;
    r.bpm = bpm;
    AudioInputFFI().rehSetGrid(bpm, r.beatsPerBar, r.beatUnit);
    await _library.save(r);
    notifyListeners();
  }

  /// Reloads after a master has been imported or removed.
  Future<void> reloadTracks() async {
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

  /// Stores the latency compensation measured by the probe, in frames.
  Future<void> setCompensationFrames(int frames) async {
    _local.compensationFrames = frames;
    notifyListeners();
    await _saveLocal();
  }

  Future<void> _saveLocal() async {
    final r = _rehearsal;
    if (r == null) return;
    await _library.saveLocalState(r.id, _local);
  }

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
      _positionFrames = pos;
      _transport = next;
      _inputPeak = peak;
      if (changed) notifyListeners();
    });
  }
}
