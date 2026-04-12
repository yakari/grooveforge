import 'dart:async';
import 'dart:io';
import 'dart:math' show sqrt;

import 'package:flutter/foundation.dart';

import 'audio_input_ffi.dart';
import 'transport_engine.dart';
import 'vst_host_service.dart';

/// State of an audio looper clip.  Mirrors the C enum in audio_looper.h.
enum AudioLooperState {
  idle,        // 0
  armed,       // 1
  recording,   // 2
  playing,     // 3
  overdubbing, // 4
  stopping,    // 5 — padding silence to next bar boundary
}

/// Dart-side representation of one audio looper clip.
///
/// Wraps the native clip index and provides a clean API for the UI.
/// The actual PCM data lives in C++ — this class manages state and
/// exposes metadata (length, head position, volume, etc.).
class AudioLooperClip {
  /// Native clip index (0 .. ALOOPER_MAX_CLIPS-1).
  final int nativeIdx;

  /// Human-readable label (e.g. "Clip 1").
  String label;

  /// Current state (polled from native).
  AudioLooperState state = AudioLooperState.idle;

  /// Playback volume (0.0–1.0).
  double volume = 1.0;

  /// Whether playback is reversed.
  bool reversed = false;

  /// Target loop length in beats (0 = free-form).
  double targetLengthBeats = 0.0;

  /// Whether recording waits for the next downbeat (true) or starts
  /// immediately (false).
  bool barSyncEnabled = true;

  /// Decimated RMS waveform for display (~300 bins).
  /// Updated when recording finishes or clip is loaded from WAV.
  List<double> waveformRms = const [];

  /// Recorded length in frames (polled from native).
  int lengthFrames = 0;

  /// Pre-allocated capacity in frames.
  int capacityFrames = 0;

  /// Current head position in frames (polled from native).
  int headFrames = 0;

  /// Sample rate used for this clip.
  int sampleRate;

  AudioLooperClip({
    required this.nativeIdx,
    required this.label,
    this.sampleRate = 48000,
  });

  /// Duration of the recorded audio in seconds.
  double get durationSeconds =>
      sampleRate > 0 ? lengthFrames / sampleRate : 0.0;

  /// Capacity in seconds.
  double get capacitySeconds =>
      sampleRate > 0 ? capacityFrames / sampleRate : 0.0;

  /// Playback progress (0.0–1.0).
  double get progress =>
      lengthFrames > 0 ? headFrames / lengthFrames : 0.0;

  /// Serialise to JSON for .gf project file.
  Map<String, dynamic> toJson() => {
        'label': label,
        'volume': volume,
        'reversed': reversed,
        'targetLengthBeats': targetLengthBeats,
        'barSyncEnabled': barSyncEnabled,
        'sampleRate': sampleRate,
        // PCM data is stored as sidecar WAV, not in JSON.
      };

  /// Restore non-PCM metadata from JSON.
  factory AudioLooperClip.fromJson(Map<String, dynamic> json, int nativeIdx) =>
      AudioLooperClip(
        nativeIdx: nativeIdx,
        label: json['label'] as String? ?? 'Clip ${nativeIdx + 1}',
        sampleRate: json['sampleRate'] as int? ?? 48000,
      )
        ..volume = (json['volume'] as num?)?.toDouble() ?? 1.0
        ..reversed = json['reversed'] as bool? ?? false
        ..targetLengthBeats =
            (json['targetLengthBeats'] as num?)?.toDouble() ?? 0.0
        ..barSyncEnabled = json['barSyncEnabled'] as bool? ?? true;
}

/// Manages audio looper clips for GrooveForge.
///
/// Each clip is backed by a pre-allocated C++ buffer in the JACK callback.
/// This engine handles:
///   - Clip creation/destruction (delegates to native via VstHostService)
///   - State transitions (arm, record, play, overdub, stop)
///   - Periodic polling of native clip state for UI updates
///   - Serialisation metadata (PCM data is WAV sidecar, not in JSON)
///
/// The actual recording and playback happens in C++ inside
/// `dvh_alooper_process()` — this Dart class is the control plane.
class AudioLooperEngine extends ChangeNotifier {
  final TransportEngine _transport;

  /// Active clips, keyed by a Dart-side slot ID (e.g. "alooper-slot-0").
  final Map<String, AudioLooperClip> _clips = {};

  /// Periodic timer that polls native state (armed→recording, head position).
  /// Runs at ~30 Hz when any clip is active, stopped when all are idle.
  Timer? _pollTimer;

  /// Called when clip data changes (recording completes, clip cleared).
  /// Used to trigger project autosave.
  VoidCallback? onDataChanged;

  /// Slot ID waiting for the next bar downbeat to start recording.
  /// Set by [arm], cleared when the downbeat fires.
  String? _pendingArmSlotId;

  /// Number of bar downbeats to skip before starting (count-in).
  int _pendingArmSkipBars = 0;

  /// Number of bar downbeats seen since arming.
  int _pendingArmDownbeats = 0;

  /// Slot ID waiting for the next bar downbeat to stop recording.
  String? _pendingStopSlotId;

  /// Maximum seconds per clip (pre-allocated buffer).
  static const double maxClipSeconds = 60.0;

  AudioLooperEngine(this._transport);

  /// True when running on Android (audio looper accessed via AudioInputFFI
  /// instead of VstHostService.host).
  bool get _useAndroidPath => !kIsWeb && Platform.isAndroid;

  // ── Platform-dispatch helpers ────────────────────────────────────────
  void _nSetState(int idx, int state) {
    if (_useAndroidPath) { AudioInputFFI().alooperSetState(idx, state); }
    else { VstHostService.instance.host?.setAudioLooperState(idx, state); }
  }
  int _nGetState(int idx) {
    if (_useAndroidPath) return AudioInputFFI().alooperGetState(idx);
    return VstHostService.instance.host?.getAudioLooperState(idx) ?? 0;
  }
  void _nSetVolume(int idx, double v) {
    if (_useAndroidPath) { AudioInputFFI().alooperSetVolume(idx, v); }
    else { VstHostService.instance.host?.setAudioLooperVolume(idx, v); }
  }
  void _nSetReversed(int idx, bool r) {
    if (_useAndroidPath) { AudioInputFFI().alooperSetReversed(idx, r); }
    else { VstHostService.instance.host?.setAudioLooperReversed(idx, r); }
  }
  void _nSetBarSync(int idx, bool e) {
    if (_useAndroidPath) { AudioInputFFI().alooperSetBarSync(idx, e); }
    else { VstHostService.instance.host?.setAudioLooperBarSync(idx, e); }
  }
  int _nGetLength(int idx) {
    if (_useAndroidPath) return AudioInputFFI().alooperGetLength(idx);
    return VstHostService.instance.host?.getAudioLooperLength(idx) ?? 0;
  }
  int _nGetHead(int idx) {
    if (_useAndroidPath) return AudioInputFFI().alooperGetHead(idx);
    return VstHostService.instance.host?.getAudioLooperHead(idx) ?? 0;
  }
  void _nDestroy(int idx) {
    if (_useAndroidPath) { AudioInputFFI().alooperDestroy(idx); }
    else { VstHostService.instance.host?.destroyAudioLooperClip(idx); }
  }

  /// Called by the transport on every beat.  Handles bar-synced arm/stop.
  /// Must be wired up in splash_screen or rack_screen via [TransportEngine.onBeat].
  void onTransportBeat(bool isDownbeat) {
    if (!isDownbeat) return;

    // ── Pending arm: start recording on this downbeat ──────────────
    if (_pendingArmSlotId != null) {
      _pendingArmDownbeats++;
      if (_pendingArmDownbeats <= _pendingArmSkipBars) {
        debugPrint('[ALOOPER] skipping downbeat $_pendingArmDownbeats/$_pendingArmSkipBars');
        return;
      }
      final slotId = _pendingArmSlotId!;
      _pendingArmSlotId = null;
      final clip = _clips[slotId];
      if (clip == null) return;

      debugPrint('[ALOOPER] BAR → start RECORDING for $slotId at beat=${_transport.positionInBeats.toStringAsFixed(1)}');

      // Tell C++ to start recording NOW (no bar detection in C++).
      _nSetBarSync(clip.nativeIdx, false);
      _nSetState(clip.nativeIdx, AudioLooperState.armed.index);
      // The C++ ARMED handler with sync=false starts recording immediately.
      clip.state = AudioLooperState.recording;
      _updatePollTimer();
      notifyListeners();
      return;
    }

    // ── Pending stop: stop recording on this downbeat ──────────────
    if (_pendingStopSlotId != null) {
      final slotId = _pendingStopSlotId!;
      _pendingStopSlotId = null;
      final clip = _clips[slotId];
      if (clip == null) return;

      debugPrint('[ALOOPER] BAR → stop RECORDING for $slotId at beat=${_transport.positionInBeats.toStringAsFixed(1)}');

      // Tell C++ to finalize immediately (PLAYING state).
      _nSetState(clip.nativeIdx, AudioLooperState.playing.index);
      clip.state = AudioLooperState.playing;
      _updatePollTimer();
      notifyListeners();
      onDataChanged?.call();
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Read-only view of all active clips.
  Map<String, AudioLooperClip> get clips => Map.unmodifiable(_clips);

  /// Creates a new audio looper clip for [slotId].
  ///
  /// Allocates a native PCM buffer (60 seconds stereo at 48kHz ≈ 22 MB).
  /// Returns the [AudioLooperClip] on success, or null if the native pool
  /// is full (max 8 clips).
  AudioLooperClip? createClip(String slotId) {
    if (_clips.containsKey(slotId)) return _clips[slotId];

    const sr = 48000;
    int nativeIdx;
    int capacityFrames;

    if (_useAndroidPath) {
      nativeIdx = AudioInputFFI().alooperCreate(maxClipSeconds, sampleRate: sr);
      if (nativeIdx < 0) {
        debugPrint('AudioLooperEngine: native pool full (Android)');
        return null;
      }
      capacityFrames = AudioInputFFI().alooperGetCapacity(nativeIdx);
    } else {
      final host = VstHostService.instance.host;
      if (host == null) return null;
      nativeIdx = host.createAudioLooperClip(maxClipSeconds, sampleRate: sr);
      if (nativeIdx < 0) {
        debugPrint('AudioLooperEngine: native pool full');
        return null;
      }
      capacityFrames = host.getAudioLooperCapacity(nativeIdx);
    }

    final clip = AudioLooperClip(
      nativeIdx: nativeIdx,
      label: 'Clip ${_clips.length + 1}',
      sampleRate: sr,
    );
    clip.capacityFrames = capacityFrames;
    _clips[slotId] = clip;
    debugPrint('AudioLooperEngine: created clip for $slotId (native=$nativeIdx)');
    notifyListeners();
    return clip;
  }

  /// Destroys the clip for [slotId] and frees native memory.
  void destroyClip(String slotId) {
    final clip = _clips.remove(slotId);
    if (clip == null) return;

    _nSetState(clip.nativeIdx, AudioLooperState.idle.index);
    _nDestroy(clip.nativeIdx);
    _updatePollTimer();
    notifyListeners();
    onDataChanged?.call();
  }

  /// Single-button handler — cycles through looper states like the MIDI looper.
  ///
  /// idle (empty) → arm → recording → playing → overdubbing → playing.
  void looperButtonPress(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;
    debugPrint('[ALOOPER] buttonPress: state=${clip.state}, len=${clip.lengthFrames}, '
        'transport=${_transport.isPlaying}, beat=${_transport.positionInBeats.toStringAsFixed(1)}');
    switch (clip.state) {
      case AudioLooperState.idle:
        (clip.lengthFrames > 0) ? play(slotId) : arm(slotId);
      case AudioLooperState.armed:
        stop(slotId);
      case AudioLooperState.recording:
        debugPrint('[ALOOPER] stop requested at beat=${_transport.positionInBeats.toStringAsFixed(1)}');
        if (clip.barSyncEnabled) {
          // Bar-synced: wait for next bar downbeat via onTransportBeat.
          _pendingStopSlotId = slotId;
          clip.state = AudioLooperState.stopping;
          notifyListeners();
        } else {
          // Free-form: stop immediately.
          _nSetState(clip.nativeIdx, AudioLooperState.playing.index);
          clip.state = AudioLooperState.playing;
          _updatePollTimer();
          notifyListeners();
          onDataChanged?.call();
        }
      case AudioLooperState.playing:
        overdub(slotId);
      case AudioLooperState.stopping:
        // Already padding to bar — ignore button press during pad.
        break;
      case AudioLooperState.overdubbing:
        play(slotId);
    }
  }

  /// Toggles bar-sync mode for [slotId].
  void toggleBarSync(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;
    clip.barSyncEnabled = !clip.barSyncEnabled;
    _nSetBarSync(clip.nativeIdx, clip.barSyncEnabled);
    notifyListeners();
  }

  /// Arms the clip for [slotId] — recording starts at the next downbeat
  /// (if bar-synced) or immediately (if free-form).
  ///
  /// If the transport is stopped and bar sync is on, starts the transport
  /// first (same UX as the MIDI looper).
  void arm(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;

    if (clip.barSyncEnabled) {
      // Bar-synced: Dart handles the bar detection via onTransportBeat.
      final startedTransport = !_transport.isPlaying;
      debugPrint('[ALOOPER] arm: barSync=true, startingTransport=$startedTransport');
      if (startedTransport) _transport.play();

      // Register pending arm — onTransportBeat will fire recording on the
      // next bar downbeat.  Skip 1 bar if we just started the transport
      // (count-in bar).
      _pendingArmSlotId = slotId;
      // No skip needed: _transport.play() fires beat 1 synchronously BEFORE
      // _pendingArmSlotId is set, so the looper never sees beat 1's downbeat.
      // The first downbeat it receives is beat 5 (bar 2) = after the count-in.
      _pendingArmSkipBars = 0;
      _pendingArmDownbeats = 0;
      clip.state = AudioLooperState.armed;
      _updatePollTimer();
      notifyListeners();
    } else {
      // Free-form: start recording immediately via C++.
      debugPrint('[ALOOPER] arm: barSync=false, starting immediately');
      _nSetBarSync(clip.nativeIdx, false);
      _nSetState(clip.nativeIdx, AudioLooperState.armed.index);
      clip.state = AudioLooperState.recording;
      _updatePollTimer();
      notifyListeners();
    }
  }

  /// Stops recording/playback and resets the clip to idle.
  void stop(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;

    _nSetState(clip.nativeIdx, AudioLooperState.idle.index);
    clip.state = AudioLooperState.idle;
    _updatePollTimer();
    notifyListeners();
    // If we stopped from recording, data changed.
    onDataChanged?.call();
  }

  /// Starts playback of the clip for [slotId] from the beginning.
  void play(String slotId) {
    final clip = _clips[slotId];
    if (clip == null || clip.lengthFrames == 0) return;

    _nSetState(clip.nativeIdx, AudioLooperState.playing.index);
    clip.state = AudioLooperState.playing;
    _updatePollTimer();
    notifyListeners();
  }

  /// Starts overdub mode — plays existing audio while recording new input.
  void overdub(String slotId) {
    final clip = _clips[slotId];
    if (clip == null || clip.lengthFrames == 0) return;

    _nSetState(clip.nativeIdx, AudioLooperState.overdubbing.index);
    clip.state = AudioLooperState.overdubbing;
    _updatePollTimer();
    notifyListeners();
  }

  /// Clears all recorded audio from the clip (resets to empty, idle).
  void clear(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;

    _nSetState(clip.nativeIdx, AudioLooperState.idle.index);
    clip.state = AudioLooperState.idle;
    clip.lengthFrames = 0;
    clip.headFrames = 0;
    clip.waveformRms = const [];
    notifyListeners();
    onDataChanged?.call();
  }

  /// Sets the playback volume for [slotId].
  void setVolume(String slotId, double volume) {
    final clip = _clips[slotId];
    if (clip == null) return;

    clip.volume = volume.clamp(0.0, 1.0);
    _nSetVolume(clip.nativeIdx, clip.volume);
    notifyListeners();
  }

  /// Toggles reverse playback for [slotId].
  void toggleReversed(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;

    clip.reversed = !clip.reversed;
    _nSetReversed(clip.nativeIdx, clip.reversed);
    notifyListeners();
  }

  /// Total memory used by all clips (bytes).
  int get memoryUsedBytes =>
      VstHostService.instance.host?.getAudioLooperMemoryUsed() ?? 0;

  /// Recomputes the decimated waveform RMS for [slotId] from native PCM data.
  ///
  /// Called when recording finishes, clip loads from WAV, or overdub completes.
  /// Reads native PCM buffers and computes an RMS envelope for the waveform
  /// preview. Runs on every recording stop, overdub stop, and WAV import.
  ///
  /// Uses `dynamic`-typed handles so this file doesn't need to import
  /// `dart:ffi`. Both platform branches go through a helper that
  /// internally wraps the native `Pointer<Float>` as a zero-copy
  /// [Float32List] view *before* returning — so dynamic dispatch on `[i]`
  /// works.
  ///
  /// **Critical:** indexing a raw `Pointer<Float>` through a `dynamic`
  /// receiver silently fails with `NoSuchMethodError` because `FloatPointer`
  /// extensions (including `operator []` and `asTypedList`) are static.
  /// The helpers below must always return `Float32List`, never a pointer.
  ///
  ///   - **Desktop** (Linux/macOS): [VstHost.getAudioLooperDataAsListL/R]
  ///     wraps the pointer inside the `package:dart_vst_host` library.
  ///   - **Android**: [AudioInputFFI.alooperGetDataAsListL/R] wraps the
  ///     pointer inside [audio_input_ffi_native.dart], which is the only
  ///     file in this subtree that imports `dart:ffi`.
  void updateWaveform(String slotId, {int bins = 300}) {
    final clip = _clips[slotId];
    if (clip == null) return;

    try {
      final int length;
      final dynamic dataL;
      final dynamic dataR;

      if (_useAndroidPath) {
        length = AudioInputFFI().alooperGetLength(clip.nativeIdx);
        if (length <= 0) { clip.waveformRms = const []; return; }
        clip.lengthFrames = length;
        dataL = AudioInputFFI().alooperGetDataAsListL(clip.nativeIdx, length);
        dataR = AudioInputFFI().alooperGetDataAsListR(clip.nativeIdx, length);
      } else {
        final dynamic host = VstHostService.instance.host;
        if (host == null) { clip.waveformRms = const []; return; }
        length = (host.getAudioLooperLength(clip.nativeIdx) as num).toInt();
        if (length <= 0) { clip.waveformRms = const []; return; }
        clip.lengthFrames = length;
        dataL = host.getAudioLooperDataAsListL(clip.nativeIdx, length);
        dataR = host.getAudioLooperDataAsListR(clip.nativeIdx, length);
      }
      if (dataL == null || dataR == null) {
        clip.waveformRms = const [];
        return;
      }

      final actualBins = length < bins ? length : bins;
      final samplesPerBin = length / actualBins;
      final rms = List<double>.filled(actualBins, 0.0);

      for (int b = 0; b < actualBins; b++) {
        final start = (b * samplesPerBin).toInt();
        final end = ((b + 1) * samplesPerBin).toInt().clamp(start + 1, length);
        double sumSq = 0;
        for (int i = start; i < end; i++) {
          final double l = (dataL[i] as num).toDouble();
          final double r = (dataR[i] as num).toDouble();
          sumSq += (l * l + r * r) * 0.5;
        }
        rms[b] = sqrt(sumSq / (end - start));
      }
      clip.waveformRms = rms;
    } catch (e) {
      debugPrint('updateWaveform error: $e');
      clip.waveformRms = const [];
    }
  }

  // ── Serialisation ───────────────────────────────────────────────────────

  /// Serialise clip metadata to JSON.  PCM data is NOT included — it is
  /// saved as sidecar WAV files by the caller.
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{};
    for (final entry in _clips.entries) {
      result[entry.key] = entry.value.toJson();
    }
    return result;
  }

  /// Pending clip metadata from project load.  Stored here because the native
  /// host is not yet available when loadFromJson runs (JACK starts later).
  /// Consumed by [finalizeLoad] after the host is ready.
  Map<String, dynamic>? _pendingJson;

  /// Path to the .gf file for WAV sidecar import.
  String? _pendingGfPath;

  /// Restore clip metadata from JSON.
  ///
  /// At this point the native host is typically not available (JACK hasn't
  /// started).  The metadata is saved as [_pendingJson] and the native clips
  /// are created later by [finalizeLoad] (called from the widget or splash).
  void loadFromJson(Map<String, dynamic> json) {
    _pendingJson = json;
    notifyListeners();
  }

  /// Set the .gf path so [finalizeLoad] can import sidecar WAVs.
  void setPendingGfPath(String path) {
    _pendingGfPath = path;
  }

  /// Creates native clips from [_pendingJson] and loads sidecar WAV data.
  ///
  /// Must be called after the native host is available (JACK client running).
  /// Called from [AudioLooperSlotUI.initState] or explicitly after startAudio.
  Future<void> finalizeLoad() async {
    final json = _pendingJson;
    if (json == null || json.isEmpty) return;
    _pendingJson = null;

    for (final slotId in _clips.keys.toList()) {
      destroyClip(slotId);
    }
    for (final entry in json.entries) {
      final slotId = entry.key;
      final clipJson = entry.value as Map<String, dynamic>;
      final clip = createClip(slotId);
      if (clip == null) continue;
      clip.label = clipJson['label'] as String? ?? clip.label;
      clip.volume = (clipJson['volume'] as num?)?.toDouble() ?? 1.0;
      clip.reversed = clipJson['reversed'] as bool? ?? false;
      clip.targetLengthBeats =
          (clipJson['targetLengthBeats'] as num?)?.toDouble() ?? 0.0;
      clip.barSyncEnabled = clipJson['barSyncEnabled'] as bool? ?? true;
      _nSetVolume(clip.nativeIdx, clip.volume);
      _nSetReversed(clip.nativeIdx, clip.reversed);
      _nSetBarSync(clip.nativeIdx, clip.barSyncEnabled);
    }

    // Import sidecar WAV data if a .gf path is available.
    if (_pendingGfPath != null) {
      await _importWavs(_pendingGfPath!);
      _pendingGfPath = null;
      // Compute waveforms for all loaded clips.
      for (final slotId in _clips.keys) {
        updateWaveform(slotId);
      }
    }

    notifyListeners();
  }

  /// Has pending metadata that needs [finalizeLoad] to complete.
  bool get hasPendingLoad => _pendingJson != null && _pendingJson!.isNotEmpty;

  /// Import sidecar WAVs into native clip buffers.
  /// Delegated to [wavImporter] which is set by the platform-specific startup
  /// code (splash_screen.dart) to keep dart:ffi imports out of this file.
  Future<void> _importWavs(String gfPath) async {
    if (kIsWeb || wavImporter == null) return;
    await wavImporter!(gfPath, _clips);
  }

  /// Platform-specific WAV importer.  Set by splash_screen on desktop to a
  /// function that reads WAV files and pushes PCM data into native buffers.
  /// Null on web.
  Future<void> Function(String gfPath, Map<String, AudioLooperClip> clips)?
      wavImporter;

  // ── Polling ─────────────────────────────────────────────────────────────

  /// Starts or stops the poll timer based on whether any clip is active.
  void _updatePollTimer() {
    final anyActive = _clips.values.any(
        (c) => c.state != AudioLooperState.idle);
    if (anyActive && _pollTimer == null) {
      _pollTimer = Timer.periodic(
          const Duration(milliseconds: 33), (_) => _pollNativeState());
    } else if (!anyActive && _pollTimer != null) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// Reads native clip state and updates Dart-side metadata.
  /// Called ~30 times/second when clips are active.
  void _pollNativeState() {
    bool changed = false;
    for (final clip in _clips.values) {
      final nativeState = _nGetState(clip.nativeIdx);
      final newState = AudioLooperState.values[nativeState.clamp(0, 5)];

      // Detect state transitions made by the C++ callback
      // (armed→recording, recording→playing).
      if (newState != clip.state) {
        clip.state = newState;
        changed = true;
        // If transitioned to playing (from recording/stopping/overdub),
        // recompute waveform and trigger autosave.
        if (newState == AudioLooperState.playing) {
          // Find the slotId for this clip.
          final slotId = _clips.entries
              .where((e) => e.value == clip)
              .firstOrNull?.key;
          if (slotId != null) updateWaveform(slotId);
          onDataChanged?.call();
        }
      }

      clip.lengthFrames = _nGetLength(clip.nativeIdx);
      clip.headFrames = _nGetHead(clip.nativeIdx);

      // If the clip is playing/idle with audio but no waveform, compute it.
      if (clip.lengthFrames > 0 && clip.waveformRms.isEmpty &&
          (clip.state == AudioLooperState.playing ||
           clip.state == AudioLooperState.idle)) {
        final slotId = _clips.entries
            .where((e) => e.value == clip)
            .firstOrNull?.key;
        if (slotId != null) updateWaveform(slotId);
      }
    }
    // Always notify when any clip is active — the waveform painter needs
    // continuous head position updates for a smooth playback cursor.
    final anyActive = _clips.values.any(
        (c) => c.state != AudioLooperState.idle);
    if (changed || anyActive) notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // Destroy all native clips.
    for (final clip in _clips.values) {
      _nSetState(clip.nativeIdx, AudioLooperState.idle.index);
      _nDestroy(clip.nativeIdx);
    }
    _clips.clear();
    super.dispose();
  }
}
