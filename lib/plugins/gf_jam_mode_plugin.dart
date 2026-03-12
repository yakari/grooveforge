import 'dart:math' show min;
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import '../services/audio_engine.dart';

// ─── Detection mode ───────────────────────────────────────────────────────────

/// How the Jam Mode plugin determines the active scale on each processing call.
///
/// - [chord]: Traditional chord-based detection. The [AudioEngine] chord
///   detector analyses all active notes on the master channel and derives a
///   diatonic scale from the detected harmony. Works well for polyphonic
///   playing.
///
/// - [bassNote]: Single-note / walking-bass detection. Only the **lowest**
///   currently-playing note on the master channel is used as the scale root.
///   The selected [ScaleType] is built from that root without any chord
///   analysis. Ideal for bass-line driven harmony: play one note on the master,
///   the scale for the target snaps to it instantly. With [bpmLockBeats] > 0,
///   the root only updates on beat boundaries — perfect for walking-bass lines
///   where each chord change is rhythmically intentional.
enum JamDetectionMode { chord, bassNote }

// ─── Plugin ───────────────────────────────────────────────────────────────────

/// Jam Mode as a GFPA MIDI FX plugin.
///
/// Transforms note-on events destined for a [targetSlotId] by snapping their
/// pitch to the scale determined by the [masterSlotId] channel.
///
/// **Detection modes** (controlled by [paramDetectionMode]):
///   - `chord`    — derives scale from chord detected on master channel (legacy)
///   - `bassNote` — derives scale from lowest active note on master channel
///
/// **BPM lock** (controlled by [paramBpmLockBeats]):
///   > 0 = scale root only changes on beat boundaries (transport synced).
///   Set to 1 for every beat, 2 for half-bar, 4 for every bar.
///   Requires the transport engine (Phase 4). In Phase 3 the setting is
///   stored but beat-boundary enforcement is not yet applied.
///
/// **Signal flow (Phase 3):**
/// The [processMidi] method is fully implemented and callable. In Phase 3 the
/// engine calls it via [RackState._syncJamFollowerMapToEngine] for chord-mode
/// slots, and will route events through it for bassNote-mode slots in Phase 4.
/// Phase 5 (audio graph) replaces this with a proper MIDI cable between
/// master's MIDI OUT and this plugin's MIDI IN.
class GFJamModePlugin implements GFMidiFxPlugin {
  final AudioEngine _engine;

  GFJamModePlugin(this._engine);

  // ─── Runtime connection (set by RackState) ────────────────────────────────

  /// 0-indexed MIDI channel of the master slot.
  int? masterChannelIndex;

  // ─── Internal state ───────────────────────────────────────────────────────

  ScaleType _scaleType = ScaleType.standard;
  JamDetectionMode _detectionMode = JamDetectionMode.chord;

  /// 0 = off, 1 = every beat, 2 = every 2 beats, 4 = every bar.
  int _bpmLockBeats = 0;

  /// Cached scale pitch-classes for the current beat window (BPM lock mode).
  Set<int>? _lockedScalePcs;

  /// Beat-window index at which [_lockedScalePcs] was last updated.
  int _lastLockWindow = -1;

  // ─── Parameter IDs ────────────────────────────────────────────────────────

  static const int paramScaleType = 0;
  static const int paramDetectionMode = 1;
  static const int paramBpmLockBeats = 2;

  // ─── GFPlugin identity ────────────────────────────────────────────────────

  @override
  String get pluginId => 'com.grooveforge.jammode';

  @override
  String get name => 'Jam Mode';

  @override
  String get version => '1.1.0';

  @override
  GFPluginType get type => GFPluginType.midiFx;

  @override
  List<GFPluginParameter> get parameters => [
    GFPluginParameter(
      id: paramScaleType,
      name: 'Scale',
      min: 0,
      max: (ScaleType.values.length - 1).toDouble(),
      defaultValue: 0,
    ),
    const GFPluginParameter(
      id: paramDetectionMode,
      name: 'Detection',
      min: 0,
      max: 1,
      defaultValue: 0, // 0 = chord, 1 = bassNote
    ),
    const GFPluginParameter(
      id: paramBpmLockBeats,
      name: 'BPM Lock',
      min: 0,
      max: 4,
      defaultValue: 0, // 0 = off
    ),
  ];

  // ─── Getters for UI ───────────────────────────────────────────────────────

  JamDetectionMode get detectionMode => _detectionMode;
  ScaleType get scaleType => _scaleType;
  int get bpmLockBeats => _bpmLockBeats;

  // ─── Parameter access ─────────────────────────────────────────────────────

  @override
  double getParameter(int paramId) {
    switch (paramId) {
      case paramScaleType: return _scaleType.index.toDouble();
      case paramDetectionMode: return _detectionMode.index.toDouble();
      case paramBpmLockBeats: return _bpmLockBeats.toDouble();
      default: return 0.0;
    }
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    switch (paramId) {
      case paramScaleType:
        final idx = normalizedValue.round().clamp(0, ScaleType.values.length - 1);
        _scaleType = ScaleType.values[idx];
      case paramDetectionMode:
        _detectionMode = normalizedValue.round() == 0
            ? JamDetectionMode.chord
            : JamDetectionMode.bassNote;
        _lockedScalePcs = null;
      case paramBpmLockBeats:
        _bpmLockBeats = normalizedValue.round().clamp(0, 4);
        _lockedScalePcs = null;
    }
  }

  // ─── State serialisation ──────────────────────────────────────────────────

  @override
  Map<String, dynamic> getState() => {
    'scaleType': _scaleType.name,
    'detectionMode': _detectionMode.name,
    'bpmLockBeats': _bpmLockBeats,
  };

  @override
  void loadState(Map<String, dynamic> state) {
    final s = state['scaleType'] as String?;
    if (s != null) {
      _scaleType = ScaleType.values.firstWhere(
        (v) => v.name == s,
        orElse: () => ScaleType.standard,
      );
    }

    final d = state['detectionMode'] as String?;
    if (d != null) {
      _detectionMode = JamDetectionMode.values.firstWhere(
        (v) => v.name == d,
        orElse: () => JamDetectionMode.chord,
      );
    }

    _bpmLockBeats =
        (state['bpmLockBeats'] as num?)?.toInt().clamp(0, 4) ?? 0;
    _lockedScalePcs = null;
  }

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  Future<void> initialize(GFPluginContext context) async {}

  @override
  Future<void> dispose() async {}

  // ─── MIDI FX processing ───────────────────────────────────────────────────

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    final masterCh = masterChannelIndex;
    if (masterCh == null || masterCh < 0 || masterCh >= 16) return events;

    final scalePcs = _resolveScalePcs(masterCh, transport);
    if (scalePcs == null || scalePcs.isEmpty) return events;

    return events.map((e) {
      if (e.isNoteOn) {
        final snapped = _snapToScale(e.data1, scalePcs);
        return TimestampedMidiEvent(
          ppqPosition: e.ppqPosition,
          status: e.status,
          data1: snapped,
          data2: e.data2,
        );
      }
      return e;
    }).toList();
  }

  // ─── Scale resolution ─────────────────────────────────────────────────────

  /// Compute the active scale pitch-class set, honouring detection mode and
  /// BPM lock.
  Set<int>? _resolveScalePcs(int masterCh, GFTransportContext transport) {
    // BPM lock: only update the scale at beat-window boundaries.
    if (_bpmLockBeats > 0 && transport.isPlaying) {
      final window =
          (transport.positionInBeats / _bpmLockBeats).floor();
      if (window != _lastLockWindow) {
        _lastLockWindow = window;
        _lockedScalePcs = _computeScalePcs(masterCh);
      }
      return _lockedScalePcs;
    }

    return _computeScalePcs(masterCh);
  }

  Set<int>? _computeScalePcs(int masterCh) {
    switch (_detectionMode) {
      case JamDetectionMode.chord:
        return _scaleFromChord(masterCh);
      case JamDetectionMode.bassNote:
        return _scaleFromBassNote(masterCh);
    }
  }

  /// Chord mode — derive scale from [AudioEngine] chord detector output.
  Set<int>? _scaleFromChord(int masterCh) {
    final chord = _engine.channels[masterCh].lastChord.value;
    if (chord == null) return null;
    return chord.scalePitchClasses.toSet();
  }

  /// Bass note mode — find the lowest active note on the master channel and
  /// build a scale from its pitch class using [_scaleType].
  Set<int>? _scaleFromBassNote(int masterCh) {
    final active = _engine.channels[masterCh].activeNotes.value;
    if (active.isEmpty) return null;

    final bassNote = active.reduce(min);
    final rootPc = bassNote % 12;
    final intervals = _intervalsFor(_scaleType);
    return intervals.map((i) => (rootPc + i) % 12).toSet();
  }

  // ─── Note snapping ────────────────────────────────────────────────────────

  int _snapToScale(int note, Set<int> scalePcs) {
    final octave = note ~/ 12;
    final pc = note % 12;
    if (scalePcs.contains(pc)) return note;

    var bestPc = scalePcs.first;
    var bestDist = 13;
    for (final candidate in scalePcs) {
      final dist = (candidate - pc).abs();
      final wrapped = dist > 6 ? 12 - dist : dist;
      if (wrapped < bestDist) {
        bestDist = wrapped;
        bestPc = candidate;
      }
    }

    return octave * 12 + bestPc;
  }

  // ─── Scale interval tables ────────────────────────────────────────────────
  //
  // Mirrors AudioEngine._getScaleInfo but without chord-quality dependency.
  // In bassNote mode there is no chord context, so we always use the
  // "major / ascending" form of each scale. Users who want a minor flavour
  // should pick Dorian, Aeolian (Harmonic/Melodic Minor), or Blues.

  static List<int> _intervalsFor(ScaleType type) {
    switch (type) {
      case ScaleType.standard:
      case ScaleType.classical:
      case ScaleType.jazz:
        return [0, 2, 4, 5, 7, 9, 11]; // Ionian / natural major
      case ScaleType.pentatonic:
      case ScaleType.asiatic:
        return [0, 2, 4, 7, 9]; // major pentatonic
      case ScaleType.blues:
        return [0, 2, 3, 4, 7, 9]; // major blues hexatonic
      case ScaleType.rock:
        return [0, 2, 3, 4, 7, 9]; // rock hexatonic
      case ScaleType.oriental:
        return [0, 1, 4, 5, 7, 8, 10]; // Phrygian dominant
      case ScaleType.dorian:
        return [0, 2, 3, 5, 7, 9, 10];
      case ScaleType.mixolydian:
        return [0, 2, 4, 5, 7, 9, 10];
      case ScaleType.harmonicMinor:
        return [0, 2, 3, 5, 7, 8, 11];
      case ScaleType.melodicMinor:
        return [0, 2, 3, 5, 7, 9, 11];
      case ScaleType.wholeTone:
        return [0, 2, 4, 6, 8, 10];
      case ScaleType.diminished:
        return [0, 1, 3, 4, 6, 7, 9, 10];
    }
  }
}
