import 'dart:async';

import 'package:flutter/foundation.dart';

import 'transport_engine.dart';
import 'vst_host_service.dart';

/// State of an audio looper clip.  Mirrors the C enum in audio_looper.h.
enum AudioLooperState {
  idle,     // 0
  armed,    // 1
  recording,// 2
  playing,  // 3
  overdubbing, // 4
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

  /// Maximum seconds per clip (pre-allocated buffer).
  static const double maxClipSeconds = 60.0;

  AudioLooperEngine(this._transport);

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

    final host = VstHostService.instance.host;
    if (host == null) return null;

    final sr = 48000;
    final nativeIdx = host.createAudioLooperClip(maxClipSeconds, sampleRate: sr);
    if (nativeIdx < 0) {
      debugPrint('AudioLooperEngine: native pool full, cannot create clip');
      return null;
    }

    final clip = AudioLooperClip(
      nativeIdx: nativeIdx,
      label: 'Clip ${_clips.length + 1}',
      sampleRate: sr,
    );
    clip.capacityFrames = host.getAudioLooperCapacity(nativeIdx);
    _clips[slotId] = clip;
    debugPrint('AudioLooperEngine: created clip for $slotId (native=$nativeIdx)');
    notifyListeners();
    return clip;
  }

  /// Destroys the clip for [slotId] and frees native memory.
  void destroyClip(String slotId) {
    final clip = _clips.remove(slotId);
    if (clip == null) return;

    final host = VstHostService.instance.host;
    host?.setAudioLooperState(clip.nativeIdx, AudioLooperState.idle.index);
    host?.destroyAudioLooperClip(clip.nativeIdx);
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
    switch (clip.state) {
      case AudioLooperState.idle:
        (clip.lengthFrames > 0) ? play(slotId) : arm(slotId);
      case AudioLooperState.armed:
        stop(slotId);
      case AudioLooperState.recording:
        // Stop recording → auto-play.
        final host = VstHostService.instance.host;
        host?.setAudioLooperState(clip.nativeIdx, AudioLooperState.playing.index);
        clip.state = AudioLooperState.playing;
        _updatePollTimer();
        notifyListeners();
        onDataChanged?.call();
      case AudioLooperState.playing:
        overdub(slotId);
      case AudioLooperState.overdubbing:
        play(slotId);
    }
  }

  /// Toggles bar-sync mode for [slotId].
  void toggleBarSync(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;
    clip.barSyncEnabled = !clip.barSyncEnabled;
    VstHostService.instance.host
        ?.setAudioLooperBarSync(clip.nativeIdx, clip.barSyncEnabled);
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

    // Start the transport if bar sync is on and it's not playing.
    if (clip.barSyncEnabled && !_transport.isPlaying) _transport.play();

    final host = VstHostService.instance.host;
    if (host == null) return;

    // Push bar sync and target length settings to native.
    host.setAudioLooperBarSync(clip.nativeIdx, clip.barSyncEnabled);
    if (clip.targetLengthBeats > 0) {
      host.setAudioLooperLengthBeats(clip.nativeIdx, clip.targetLengthBeats);
    }

    host.setAudioLooperState(clip.nativeIdx, AudioLooperState.armed.index);
    clip.state = AudioLooperState.armed;
    _updatePollTimer();
    notifyListeners();
  }

  /// Stops recording/playback and resets the clip to idle.
  void stop(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;

    final host = VstHostService.instance.host;
    host?.setAudioLooperState(clip.nativeIdx, AudioLooperState.idle.index);
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

    final host = VstHostService.instance.host;
    host?.setAudioLooperState(clip.nativeIdx, AudioLooperState.playing.index);
    clip.state = AudioLooperState.playing;
    _updatePollTimer();
    notifyListeners();
  }

  /// Starts overdub mode — plays existing audio while recording new input.
  void overdub(String slotId) {
    final clip = _clips[slotId];
    if (clip == null || clip.lengthFrames == 0) return;

    final host = VstHostService.instance.host;
    host?.setAudioLooperState(clip.nativeIdx, AudioLooperState.overdubbing.index);
    clip.state = AudioLooperState.overdubbing;
    _updatePollTimer();
    notifyListeners();
  }

  /// Clears all recorded audio from the clip (resets to empty, idle).
  void clear(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;

    final host = VstHostService.instance.host;
    host?.setAudioLooperState(clip.nativeIdx, AudioLooperState.idle.index);
    clip.state = AudioLooperState.idle;
    clip.lengthFrames = 0;
    clip.headFrames = 0;
    notifyListeners();
    onDataChanged?.call();
  }

  /// Sets the playback volume for [slotId].
  void setVolume(String slotId, double volume) {
    final clip = _clips[slotId];
    if (clip == null) return;

    clip.volume = volume.clamp(0.0, 1.0);
    VstHostService.instance.host
        ?.setAudioLooperVolume(clip.nativeIdx, clip.volume);
    notifyListeners();
  }

  /// Toggles reverse playback for [slotId].
  void toggleReversed(String slotId) {
    final clip = _clips[slotId];
    if (clip == null) return;

    clip.reversed = !clip.reversed;
    VstHostService.instance.host
        ?.setAudioLooperReversed(clip.nativeIdx, clip.reversed);
    notifyListeners();
  }

  /// Total memory used by all clips (bytes).
  int get memoryUsedBytes =>
      VstHostService.instance.host?.getAudioLooperMemoryUsed() ?? 0;

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

  /// Restore clip metadata from JSON.  The caller must also load sidecar WAV
  /// files and push PCM data into the native buffers separately.
  void loadFromJson(Map<String, dynamic> json) {
    // Destroy existing clips first.
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
      // Apply volume and reversed to native.
      final host = VstHostService.instance.host;
      host?.setAudioLooperVolume(clip.nativeIdx, clip.volume);
      host?.setAudioLooperReversed(clip.nativeIdx, clip.reversed);
    }
    notifyListeners();
  }

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
    final host = VstHostService.instance.host;
    if (host == null) return;

    bool changed = false;
    for (final clip in _clips.values) {
      final nativeState = host.getAudioLooperState(clip.nativeIdx);
      final newState = AudioLooperState.values[nativeState.clamp(0, 4)];

      // Detect state transitions made by the C++ callback
      // (armed→recording, recording→playing).
      if (newState != clip.state) {
        clip.state = newState;
        changed = true;
        // If transitioned to playing from recording, data changed.
        if (newState == AudioLooperState.playing) {
          onDataChanged?.call();
        }
      }

      clip.lengthFrames = host.getAudioLooperLength(clip.nativeIdx);
      clip.headFrames = host.getAudioLooperHead(clip.nativeIdx);
    }
    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    // Destroy all native clips.
    final host = VstHostService.instance.host;
    for (final clip in _clips.values) {
      host?.setAudioLooperState(clip.nativeIdx, AudioLooperState.idle.index);
      host?.destroyAudioLooperClip(clip.nativeIdx);
    }
    _clips.clear();
    super.dispose();
  }
}
