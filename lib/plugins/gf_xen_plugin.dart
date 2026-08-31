import 'dart:typed_data';

import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

// ─── Plugin ───────────────────────────────────────────────────────────────────

/// Xen — scale locking and microtonal retuning in one MIDI FX module.
///
/// Xen is the synthesis of the two things GrooveForge already did separately:
/// Jam Mode locks a keyboard to a scale, and Microtone reaches pitches between
/// the keys. Xen does both from a single module, and needs no second keyboard
/// to tell it what the harmony is.
///
/// **The gesture.** Hold a note, tap a scale — [selectScale] reads whatever is
/// held on the source channel, takes the lowest note as the tonic, and latches
/// it. Unlike Jam Mode's bass-note detection, which re-derives the root from
/// the master keyboard continuously, a latched root stays put until the player
/// performs the gesture again. That is the difference between accompanying
/// someone else's harmony and choosing your own.
///
/// **Two independent stages**, either of which can be switched off:
///
///   - **Snap** ([snapEnabled]) quantises incoming notes to the keys the scale
///     allows. On its own this reproduces Jam Mode, self-driven.
///   - **Tune** ([tuneEnabled]) hands the host a 128-entry table of cent
///     deviations ([tuningTable]) so the keys the scale uses sound at their
///     traditional pitches rather than at the piano's approximation of them.
///
/// Splitting them matters musically: a player may want a maqam's key layout
/// without its quarter-tones (to stay in tune with a fixed-pitch band), or its
/// intonation without the lock (to keep the full chromatic keyboard under the
/// fingers). Neither is a degenerate case.
///
/// **Why the tuning table rather than pitch bend.** The older Microtone plugin
/// bends pitch, and MIDI pitch bend is per channel: every held note moves
/// together, so only one microtonal pitch can sound at a time. A tuning table
/// retunes each key independently, which is what lets Xen hold a whole chord
/// in a non-equal temperament. The verification lives in
/// `native_audio/gf_tuning_smoke_test.c`.
class GFXenPlugin extends GFMidiFxPlugin {
  // ─── Host callbacks ────────────────────────────────────────────────────────

  /// Returns the MIDI notes currently held on the channel feeding this module.
  ///
  /// Injected rather than read from [AudioEngine] directly so the gesture
  /// logic can be exercised in tests without an audio engine, and so the same
  /// plugin can be driven from a different host later. Mirrors the callback
  /// style of [GFMidiNodeContext.scaleProvider].
  final Set<int> Function() heldNotesProvider;

  /// Hands a fresh tuning table to the host, or `null` to return the target to
  /// equal temperament.
  ///
  /// Called whenever the scale, the root, or [tuneEnabled] changes — never
  /// per note. Which channels the table reaches is the host's business: this
  /// plugin knows what the tuning should be, not where it goes.
  final void Function(Float64List? table) tuningSink;

  GFXenPlugin({
    required this.heldNotesProvider,
    required this.tuningSink,
  });

  // ─── Internal state ────────────────────────────────────────────────────────

  GFScale _scale = GFScaleLibrary.fallback;

  /// Pitch class of the tonic, 0 = C … 11 = B.
  int _rootPc = 0;

  bool _snapEnabled = true;
  bool _tuneEnabled = true;

  /// Which pitch each sounding key was snapped to, per MIDI channel.
  ///
  /// Needed because snapping is not a fixed transposition: the same key maps
  /// to different pitches before and after a root change. Without recording
  /// the mapping at note-on, a note held across a scale change would be
  /// released at the wrong pitch and hang forever. Keyed by channel, then by
  /// the physical key the player pressed.
  final List<Map<int, int>> _soundingKeys =
      List.generate(16, (_) => <int, int>{});

  // ─── Parameter IDs ─────────────────────────────────────────────────────────

  /// Index into [GFScaleLibrary.all].
  ///
  /// Note that the parameter carries an index while [getState] serialises the
  /// scale's *id*: parameter values must be a dense numeric range for CC
  /// mapping and automation, but a saved project has to survive the catalogue
  /// growing a scale in the middle.
  static const int paramScale = 0;

  /// Tonic pitch class, 0–11.
  static const int paramRoot = 1;

  /// Snap stage on/off.
  static const int paramSnap = 2;

  /// Tune stage on/off.
  static const int paramTune = 3;

  // ─── GFPlugin identity ─────────────────────────────────────────────────────

  @override
  String get pluginId => 'com.grooveforge.xen';

  @override
  String get name => 'Xen';

  @override
  String get version => '1.0.0';

  @override
  GFPluginType get type => GFPluginType.midiFx;

  @override
  List<GFPluginParameter> get parameters => [
    GFPluginParameter(
      id: paramScale,
      name: 'Scale',
      min: 0,
      max: (GFScaleLibrary.all.length - 1).toDouble(),
      defaultValue: 0,
    ),
    const GFPluginParameter(
      id: paramRoot,
      name: 'Root',
      min: 0,
      max: 11,
      defaultValue: 0,
    ),
    const GFPluginParameter(
      id: paramSnap,
      name: 'Snap',
      min: 0,
      max: 1,
      defaultValue: 1,
    ),
    const GFPluginParameter(
      id: paramTune,
      name: 'Tune',
      min: 0,
      max: 1,
      defaultValue: 1,
    ),
  ];

  // ─── Getters for the UI ────────────────────────────────────────────────────

  /// The scale currently selected.
  GFScale get scale => _scale;

  /// Pitch class of the latched tonic, 0 = C … 11 = B.
  int get rootPc => _rootPc;

  /// True when incoming notes are quantised to the scale.
  bool get snapEnabled => _snapEnabled;

  /// True when the scale's own intonation is applied to the target.
  bool get tuneEnabled => _tuneEnabled;

  /// Keys the scale allows, for the virtual piano's greyed-out rendering, or
  /// `null` when nothing is constrained (snap off, a temperament, a linear
  /// scale). `null` is the same "no constraint" signal Jam Mode already uses.
  Set<int>? get validPitchClasses =>
      _snapEnabled ? _scale.pitchClassesFor(_rootPc) : null;

  /// Cent deviations by pitch class, for the "↑12¢" markers on the keys.
  /// Empty when the tune stage is off.
  Map<int, double> get centsByPitchClass =>
      _tuneEnabled ? _scale.centsByPitchClassFor(_rootPc) : const {};

  /// The 128-entry tuning table to hand the host, or `null` when the target
  /// should stay in equal temperament.
  ///
  /// Returns `null` — rather than an all-zero table — both when the tune stage
  /// is off and when the selected scale is equal-tempered anyway. The two are
  /// audibly identical, and `null` lets the host deactivate the tuning
  /// outright instead of installing a table that does nothing.
  Float64List? get tuningTable {
    if (!_tuneEnabled || !_scale.isMicrotonal) return null;
    return _scale.tuningOffsetsFor(_rootPc);
  }

  // ─── The gesture ───────────────────────────────────────────────────────────

  /// Select [scaleId], latching the tonic from whatever the player is holding.
  ///
  /// This is the module's signature interaction: press a note, keep it down,
  /// tap a scale button. The lowest held note becomes the tonic — lowest
  /// rather than most recent because a player reaching for a scale button with
  /// their free hand naturally leaves the bass of the gesture in place, and
  /// because it matches the convention Jam Mode's bass-note mode already set.
  ///
  /// With nothing held, the current root is kept: tapping through scales to
  /// audition them should not silently move the tonic to C.
  ///
  /// Unknown ids are ignored rather than throwing — a project saved by a newer
  /// build may name a scale this one has never heard of, and the right
  /// response mid-performance is to keep playing.
  void selectScale(String scaleId) {
    final selected = GFScaleLibrary.byId(scaleId);
    if (selected == null) return;
    _scale = selected;
    _latchRootFromHeldNotes();
    _pushTuning();
  }

  /// Re-latch the tonic from the held notes without changing scale.
  ///
  /// Lets the player move a maqam to a new tonic with the same gesture they
  /// used to choose it.
  void latchRoot() {
    _latchRootFromHeldNotes();
    _pushTuning();
  }

  /// Set the tonic by hand, for the module's chromatic strip.
  void setRoot(int pitchClass) {
    _rootPc = pitchClass % 12;
    _pushTuning();
  }

  /// Take the lowest held note as the tonic, or leave the root alone when
  /// nothing is held.
  void _latchRootFromHeldNotes() {
    final held = heldNotesProvider();
    if (held.isEmpty) return;
    _rootPc = held.reduce((a, b) => a < b ? a : b) % 12;
  }

  // ─── Stage toggles ─────────────────────────────────────────────────────────

  /// Turn the snap stage on or off.
  void setSnapEnabled(bool enabled) {
    _snapEnabled = enabled;
  }

  /// Turn the tune stage on or off, pushing or clearing the table to match.
  void setTuneEnabled(bool enabled) {
    _tuneEnabled = enabled;
    _pushTuning();
  }

  /// Hand the current table (or a clear) to the host.
  void _pushTuning() => tuningSink(tuningTable);

  // ─── Parameter access ──────────────────────────────────────────────────────

  @override
  double getParameter(int paramId) {
    switch (paramId) {
      case paramScale:
        final index = GFScaleLibrary.all.indexOf(_scale);
        return index < 0 ? 0.0 : index.toDouble();
      case paramRoot:
        return _rootPc.toDouble();
      case paramSnap:
        return _snapEnabled ? 1.0 : 0.0;
      case paramTune:
        return _tuneEnabled ? 1.0 : 0.0;
      default:
        return 0.0;
    }
  }

  @override
  void setParameter(int paramId, double normalizedValue) {
    switch (paramId) {
      case paramScale:
        final index =
            normalizedValue.round().clamp(0, GFScaleLibrary.all.length - 1);
        _scale = GFScaleLibrary.all[index];
        _pushTuning();
      case paramRoot:
        _rootPc = normalizedValue.round().clamp(0, 11);
        _pushTuning();
      case paramSnap:
        _snapEnabled = normalizedValue.round() != 0;
      case paramTune:
        _tuneEnabled = normalizedValue.round() != 0;
        _pushTuning();
    }
  }

  // ─── State serialisation ───────────────────────────────────────────────────

  @override
  Map<String, dynamic> getState() => {
    // The id, not the catalogue index — see [paramScale].
    'scaleId': _scale.id,
    'rootPc': _rootPc,
    'snapEnabled': _snapEnabled,
    'tuneEnabled': _tuneEnabled,
  };

  @override
  void loadState(Map<String, dynamic> state) {
    final scaleId = state['scaleId'] as String?;
    if (scaleId != null) {
      _scale = GFScaleLibrary.byId(scaleId) ?? GFScaleLibrary.fallback;
    }
    _rootPc = ((state['rootPc'] as num?)?.toInt() ?? 0) % 12;
    _snapEnabled = state['snapEnabled'] as bool? ?? true;
    _tuneEnabled = state['tuneEnabled'] as bool? ?? true;
    _pushTuning();
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  Future<void> initialize(GFPluginContext context) async {
    // Clear any mapping left by a previous project or a hot reload — a stale
    // entry would send a note-off to a pitch nothing is playing.
    for (final channel in _soundingKeys) {
      channel.clear();
    }
    _pushTuning();
  }

  @override
  Future<void> dispose() async {
    // Leave the target in equal temperament: the module is going away, and a
    // tuning table outliving it would silently detune the next thing patched
    // into that channel.
    tuningSink(null);
  }

  // ─── MIDI FX processing ────────────────────────────────────────────────────

  @override
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  ) {
    if (!_snapEnabled) return events;

    final allowed = _scale.pitchClassesFor(_rootPc);
    // A temperament or a linear scale allows every key: there is nothing to
    // snap, and the tune stage is doing all the work.
    if (allowed == null || allowed.isEmpty) return events;

    return events.map((e) => _processEvent(e, allowed)).toList();
  }

  /// Route one event: notes are remapped, everything else passes through.
  TimestampedMidiEvent _processEvent(
    TimestampedMidiEvent event,
    Set<int> allowed,
  ) {
    if (event.isNoteOn) return _processNoteOn(event, allowed);
    if (event.isNoteOff) return _processNoteOff(event);
    return event;
  }

  /// Snap a note-on and remember where it went.
  TimestampedMidiEvent _processNoteOn(
    TimestampedMidiEvent event,
    Set<int> allowed,
  ) {
    final snapped = _snapToScale(event.data1, allowed);
    // Record the mapping even when the note was already in scale: the note-off
    // path then needs no special case, and a root change between press and
    // release cannot desynchronise the two.
    _soundingKeys[event.midiChannel][event.data1] = snapped;
    return _withPitch(event, snapped);
  }

  /// Release a note at the pitch it was actually started on.
  ///
  /// Falls back to the incoming pitch when no mapping is recorded — which
  /// happens for a note that was already sounding when the module was patched
  /// in, and which must still be releasable.
  TimestampedMidiEvent _processNoteOff(TimestampedMidiEvent event) {
    final mapped = _soundingKeys[event.midiChannel].remove(event.data1);
    return mapped == null ? event : _withPitch(event, mapped);
  }

  /// Copy [event] with a different pitch.
  TimestampedMidiEvent _withPitch(TimestampedMidiEvent event, int pitch) =>
      TimestampedMidiEvent(
        ppqPosition: event.ppqPosition,
        status: event.status,
        data1: pitch,
        data2: event.data2,
      );

  /// Move [note] to the nearest key the scale allows.
  ///
  /// Searches outward a semitone at a time, testing downward before upward at
  /// each distance so that a tie resolves to the lower note — the same
  /// down-first convention Jam Mode uses, which keeps a snapped melody from
  /// drifting upward over a long run.
  int _snapToScale(int note, Set<int> allowed) {
    if (allowed.contains(note % 12)) return note;
    for (var distance = 1; distance <= 6; distance++) {
      final down = note - distance;
      if (down >= 0 && allowed.contains(down % 12)) return down;
      final up = note + distance;
      if (up <= 127 && allowed.contains(up % 12)) return up;
    }
    return note; // unreachable for a non-empty scale; keeps the note playable
  }
}
