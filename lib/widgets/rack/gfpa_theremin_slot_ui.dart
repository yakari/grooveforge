import 'dart:math' show log, pow;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/audio_port_id.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../models/looper_plugin_instance.dart';
import '../../models/vst3_plugin_instance.dart';
import '../../plugins/gf_theremin_plugin.dart';
import '../../services/audio_engine.dart';
import '../../services/audio_graph.dart';
import '../../services/audio_input_ffi.dart';
import '../../services/looper_engine.dart';
import '../../services/rack_state.dart';
import '../../services/theremin_distance_service.dart';
import '../../services/vst_host_service.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

// ─── Input mode ───────────────────────────────────────────────────────────────

/// Whether the theremin is driven by touch or by the camera focal distance.
enum _ThereminInputMode {
  /// Classic touch pad: vertical axis = pitch, horizontal axis = volume.
  touchPad,

  /// Camera mode: hand distance from camera controls pitch at full volume.
  camera,
}

// ─── Slot widget ──────────────────────────────────────────────────────────────

/// Rack-slot body for the GFPA Theremin plugin.
///
/// Two input modes are available via the PAD / CAM toggle at the top:
///
/// **PAD mode** (default)
///   Touch-pad mimicking the hand-near-antenna gesture of a real theremin:
///   • Vertical axis → pitch (bottom = [_baseNote], top = highest note in range).
///   • Horizontal axis → volume (left = quiet, right = loud).
///
/// **CAM mode** (Android / iOS / macOS only)
///   The front camera's autofocus focal distance tracks hand proximity:
///   • Closer hand  → higher pitch.
///   • Farther hand → lower pitch (silence below the [_kSilenceThreshold]).
///   Volume stays at full (1.0) in this mode.
///
/// Audio is routed to the native C theremin oscillator (sine + 3rd harmonic,
/// portamento τ ≈ 42 ms, 6.5 Hz vibrato LFO) via [AudioInputFFI].
///
/// A glowing purple orb follows the active position in both modes.
/// Releasing the finger / moving the hand away silences the instrument.
///
/// Base note, range, and vibrato depth are adjusted via small +/− buttons in
/// the sidebar.  Changes persist in [GFpaPluginInstance.state].
class GFpaThereminSlotUI extends StatefulWidget {
  const GFpaThereminSlotUI({super.key, required this.plugin});

  final GFpaPluginInstance plugin;

  @override
  State<GFpaThereminSlotUI> createState() => _GFpaThereminSlotUIState();
}

class _GFpaThereminSlotUIState extends State<GFpaThereminSlotUI> {
  // ─── Input mode ─────────────────────────────────────────────────────────

  /// Currently active input mode (defaults to touch-pad).
  _ThereminInputMode _inputMode = _ThereminInputMode.touchPad;

  // ─── Camera service ──────────────────────────────────────────────────────

  /// Service that streams focal-distance readings from the native camera plugin.
  late final ThereminDistanceService _distSvc;

  /// True while [ThereminDistanceService.start] is awaiting the native reply.
  bool _camStarting = false;

  /// Error code returned by [ThereminDistanceService.start], or null if OK.
  ///
  /// Possible values: 'NO_PERMISSION', 'NO_CAMERA', 'FIXED_FOCUS',
  /// 'CONFIG_ERROR', 'PLATFORM_UNSUPPORTED'.  null = camera is running fine.
  String? _camError;

  // ─── Playing state ───────────────────────────────────────────────────────

  /// Orb position in local pad coordinates; null when no note is sounding.
  Offset? _orbPosition;

  /// True while a tone is sounding through the native C theremin oscillator.
  bool _isPlaying = false;

  /// MIDI note number last dispatched to connected MIDI OUT targets, or -1
  /// when silent.  Tracked so we can send a note-off when pitch crosses a
  /// semitone boundary or when the sound stops (finger lift / hand away).
  int _lastMidiNoteOut = -1;

  // ─── Layout (written by LayoutBuilder; read by camera listener) ──────────

  /// Most-recent pad dimensions, updated every time [LayoutBuilder] rebuilds.
  ///
  /// Stored as a plain field (not in state) to avoid triggering a rebuild when
  /// only layout changes.  Safe for the camera listener to read because the
  /// listener is always followed by [setState], which re-queries this field.
  Size _padSize = Size.zero;

  // ─── Silence threshold ───────────────────────────────────────────────────

  /// Distance values below this are treated as "no hand detected" → silence.
  ///
  /// EMA-smoothed readings near 0.0 are very noisy, so we apply a small dead
  /// zone.  0.03 maps to roughly 30 cm away for most device cameras.
  static const double _kSilenceThreshold = 0.03;

  // ─── State helpers ────────────────────────────────────────────────────────

  /// Lowest MIDI note from persistent slot state (defaults to C3 = 48).
  int get _baseNote =>
      (widget.plugin.state['baseNote'] as num?)?.toInt().clamp(36, 72) ?? 48;

  /// Pitch range in octaves from persistent slot state (defaults to 2).
  int get _rangeOctaves =>
      (widget.plugin.state['rangeOctaves'] as num?)?.toInt().clamp(1, 4) ?? 2;

  /// Vibrato depth from persistent slot state (defaults to 0 = no vibrato).
  double get _vibrato =>
      (widget.plugin.state['vibrato'] as num?)?.toDouble().clamp(0.0, 1.0) ??
      0.0;

  /// Pad height index from persistent slot state (0 = S, 1 = M, 2 = L, 3 = XL).
  ///
  /// Defaults to 1 (M = 160 px), which is a touch taller than the original
  /// fixed size and feels comfortable on most screen sizes.
  int get _padHeightIdx =>
      (widget.plugin.state['padHeightIdx'] as num?)?.toInt().clamp(0, 3) ?? 1;

  /// Pixel heights corresponding to [_padHeightIdx] values 0–3.
  static const List<double> _kPadHeights = [120, 160, 210, 270];

  /// Pixel height label shown in the sidebar (S / M / L / XL).
  static const List<String> _kPadHeightLabels = ['S', 'M', 'L', 'XL'];

  /// Returns the current pad height in logical pixels.
  double get _padPixelHeight => _kPadHeights[_padHeightIdx];

  /// Whether the native C synthesiser is muted (MIDI OUT continues to flow).
  bool get _muteSound =>
      (widget.plugin.state['muteSound'] as bool?) ?? false;

  // ─── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _distSvc = ThereminDistanceService();
    // Listen to every distance update so we can drive pitch in camera mode.
    _distSvc.distance.addListener(_onCameraDistance);
    // Listen to preview frame updates to refresh the pad background overlay.
    _distSvc.previewFrame.addListener(_onPreviewFrame);
    // Start native C theremin oscillator for this slot.
    AudioInputFFI().thereminStart();
    // Sync saved vibrato depth to the native synth.
    AudioInputFFI().thereminSetVibrato(_vibrato);
  }

  @override
  void dispose() {
    // Remove listeners first so callbacks cannot fire after disposal.
    _distSvc.distance.removeListener(_onCameraDistance);
    _distSvc.previewFrame.removeListener(_onPreviewFrame);
    _stopCurrentNote();
    // Silence the native device then shut it down.
    AudioInputFFI().thereminSetVolume(0.0);
    AudioInputFFI().thereminStop();
    _distSvc.dispose(); // stops the camera session and disposes the notifier
    super.dispose();
  }

  // ─── Camera distance listener ─────────────────────────────────────────────

  /// Called by [ThereminDistanceService.distance] on every camera frame (~30 fps).
  ///
  /// Ignored when in touch-pad mode.  In camera mode the new distance drives
  /// pitch changes and orb position updates.
  void _onCameraDistance() {
    if (_inputMode != _ThereminInputMode.camera) return;
    if (!mounted) return;
    _processDistanceFrame(_distSvc.distance.value);
  }

  /// Translates a raw [dist] value ∈ [0,1] into a pitch + orb position.
  ///
  /// Values below [_kSilenceThreshold] are treated as silence (no hand).
  /// The mapping is:
  ///   dist = 0  → hand far from camera → lowest note (orb at bottom).
  ///   dist = 1  → hand at minimum focus → highest note (orb at top).
  void _processDistanceFrame(double dist) {
    if (dist < _kSilenceThreshold) {
      _silenceIfActive();
      return;
    }

    // Y position: dist=1 (close hand) → top of pad → high pitch.
    final orbY = _padSize.height * (1.0 - dist);
    final orbX = _padSize.width / 2; // centred horizontally

    final hz = _yToHz(orbY, _padSize.height);

    // Native sound: camera mode uses full volume — pitch only.
    if (!_muteSound) {
      AudioInputFFI().thereminSetPitchHz(hz);
      AudioInputFFI().thereminSetVolume(1.0);
    }

    // MIDI OUT: dispatch note changes at semitone boundaries.
    final midiNote = _hzToMidiNote(hz);
    if (midiNote != _lastMidiNoteOut) {
      if (_lastMidiNoteOut >= 0) _dispatchNoteOff(_lastMidiNoteOut);
      _dispatchNoteOn(midiNote, 100);
      _lastMidiNoteOut = midiNote;
    }

    setState(() {
      _isPlaying = true;
      _orbPosition = Offset(orbX, orbY);
    });
  }

  /// Stops the sounding tone and hides the orb when distance falls to silence.
  void _silenceIfActive() {
    // Nothing to do if already silent and orb already hidden.
    if (!_isPlaying && _orbPosition == null) return;

    if (!_muteSound) AudioInputFFI().thereminSetVolume(0.0);
    if (_lastMidiNoteOut >= 0) {
      _dispatchNoteOff(_lastMidiNoteOut);
      _lastMidiNoteOut = -1;
    }
    setState(() {
      _isPlaying = false;
      _orbPosition = null;
    });
  }

  /// Called when a new preview frame thumbnail arrives from the camera.
  ///
  /// Triggers a rebuild so [_CamStatusOverlay] can display the updated frame.
  void _onPreviewFrame() {
    if (mounted) setState(() {});
  }

  // ─── Mode switching ───────────────────────────────────────────────────────

  /// Switches to camera mode: requests permission, starts the native session.
  ///
  /// Sets [_camStarting] while waiting for the native reply so the UI can show
  /// a loading indicator.  On failure [_camError] is set and the mode stays
  /// as camera so the error message is visible in the pad area.
  Future<void> _switchToCamera() async {
    if (!_distSvc.isPlatformSupported) return;

    // Release any sounding MIDI note before switching modes.
    if (_lastMidiNoteOut >= 0) {
      _dispatchNoteOff(_lastMidiNoteOut);
      _lastMidiNoteOut = -1;
    }
    _stopCurrentNote();
    setState(() {
      _inputMode = _ThereminInputMode.camera;
      _camError = null;
      _camStarting = true;
      _orbPosition = null;
    });

    final error = await _distSvc.start();
    if (!mounted) return;

    setState(() {
      _camStarting = false;
      _camError = error;
    });
  }

  /// Switches back to touch-pad mode and stops the camera session.
  void _switchToPad() {
    // Release any sounding MIDI note before switching modes.
    if (_lastMidiNoteOut >= 0) {
      _dispatchNoteOff(_lastMidiNoteOut);
      _lastMidiNoteOut = -1;
    }
    _stopCurrentNote();
    _distSvc.stop();
    setState(() {
      _inputMode = _ThereminInputMode.touchPad;
      _camError = null;
      _camStarting = false;
      _orbPosition = null;
    });
  }

  // ─── Parameter controls ───────────────────────────────────────────────────

  /// Changes [_baseNote] by [delta] octaves (12 semitones per step).
  void _changeBaseNote(int delta, RackState rack) {
    final newBase = (_baseNote + delta * 12).clamp(36, 72);
    widget.plugin.state['baseNote'] = newBase;
    _syncToRegistry();
    rack.markDirty();
    setState(() {});
  }

  /// Changes [_rangeOctaves] by [delta] (1 to 4 octaves).
  void _changeRange(int delta, RackState rack) {
    final newRange = (_rangeOctaves + delta).clamp(1, 4);
    widget.plugin.state['rangeOctaves'] = newRange;
    _syncToRegistry();
    rack.markDirty();
    setState(() {});
  }

  /// Changes vibrato depth by [delta] steps of 0.25 (four positions: 0–1).
  ///
  /// Persists the new value and propagates it to the native C synth
  /// immediately via [AudioInputFFI.thereminSetVibrato].
  void _changeVibrato(int delta, RackState rack) {
    final newVal = (_vibrato + delta * 0.25).clamp(0.0, 1.0);
    widget.plugin.state['vibrato'] = newVal;
    // Propagate to the native C synth — takes effect on the next audio frame.
    AudioInputFFI().thereminSetVibrato(newVal);
    _syncToRegistry();
    rack.markDirty();
    setState(() {});
  }

  /// Cycles the pad height index by [delta] (−1 or +1) through the four
  /// preset sizes (S → M → L → XL) and persists the new value.
  void _changePadHeight(int delta, RackState rack) {
    final newIdx = (_padHeightIdx + delta).clamp(0, 3);
    widget.plugin.state['padHeightIdx'] = newIdx;
    _syncToRegistry();
    rack.markDirty();
    setState(() {});
  }

  /// Mirrors slot state into the [GFThereminPlugin] registry instance so that
  /// [getParameter] stays consistent with what is shown on screen.
  void _syncToRegistry() {
    final plugin = GFPluginRegistry.instance
        .findById('com.grooveforge.theremin') as GFThereminPlugin?;
    if (plugin == null) return;
    plugin.setParameter(
        GFThereminPlugin.paramBaseNote, (_baseNote - 36) / 36.0);
    plugin.setParameter(
        GFThereminPlugin.paramRange, (_rangeOctaves - 1) / 3.0);
    plugin.setParameter(GFThereminPlugin.paramVibrato, _vibrato);
  }

  // ─── MIDI OUT dispatch ────────────────────────────────────────────────────

  /// Converts a frequency in Hz to the nearest MIDI note number [0, 127].
  ///
  /// Inverse of the equal-temperament formula: A4 = 440 Hz = MIDI 69.
  /// Used to determine which MIDI note to emit when pitch crosses a semitone.
  int _hzToMidiNote(double hz) {
    if (hz <= 0) return 0;
    return (12.0 * (log(hz / 440.0) / log(2.0)) + 69.0)
        .round()
        .clamp(0, 127);
  }

  /// Sends a MIDI note-on to every slot connected to this plugin's MIDI OUT
  /// jack.  Mirrors the routing logic of [_RackSlotWidget._dispatchMidiNoteOn]
  /// so Looper, VST3, and FluidSynth targets are all handled correctly.
  void _dispatchNoteOn(int note, int velocity) {
    final cables = context
        .read<AudioGraph>()
        .connectionsFrom(widget.plugin.id)
        .where((c) => c.fromPort == AudioPortId.midiOut)
        .toList();
    if (cables.isEmpty) return;

    final ch = (widget.plugin.midiChannel - 1).clamp(0, 15);
    final status = 0x90 | (ch & 0x0F);
    final engine = context.read<AudioEngine>();

    for (final cable in cables) {
      final target = context
          .read<RackState>()
          .plugins
          .where((p) => p.id == cable.toSlotId)
          .firstOrNull;
      if (target == null) continue;

      if (target is LooperPluginInstance) {
        context.read<LooperEngine>().feedMidiEvent(
            target.id, status, note, velocity);
        continue;
      }

      final targetCh = (target.midiChannel - 1).clamp(0, 15);
      if (target is Vst3PluginInstance) {
        context.read<VstHostService>().noteOn(target.id, 0, note, 1.0);
        engine.noteOnUiOnly(channel: targetCh, key: note);
      } else {
        engine.playNote(channel: targetCh, key: note, velocity: velocity);
      }
    }
  }

  /// Sends a MIDI note-off to every slot connected to this plugin's MIDI OUT
  /// jack.  Mirrors [_dispatchNoteOn].
  void _dispatchNoteOff(int note) {
    final cables = context
        .read<AudioGraph>()
        .connectionsFrom(widget.plugin.id)
        .where((c) => c.fromPort == AudioPortId.midiOut)
        .toList();
    if (cables.isEmpty) return;

    final ch = (widget.plugin.midiChannel - 1).clamp(0, 15);
    final status = 0x80 | (ch & 0x0F);
    final engine = context.read<AudioEngine>();

    for (final cable in cables) {
      final target = context
          .read<RackState>()
          .plugins
          .where((p) => p.id == cable.toSlotId)
          .firstOrNull;
      if (target == null) continue;

      if (target is LooperPluginInstance) {
        context.read<LooperEngine>().feedMidiEvent(target.id, status, note, 0);
        continue;
      }

      final targetCh = (target.midiChannel - 1).clamp(0, 15);
      if (target is Vst3PluginInstance) {
        context.read<VstHostService>().noteOff(target.id, 0, note);
        engine.noteOffUiOnly(channel: targetCh, key: note);
      } else {
        engine.stopNote(channel: targetCh, key: note);
      }
    }
  }

  /// Toggles the native synthesiser mute flag.
  ///
  /// When muted the built-in C oscillator stays silent but MIDI OUT events
  /// continue flowing to any connected instruments (GFK, VST3, Looper, etc.).
  void _toggleMute(RackState rack) {
    widget.plugin.state['muteSound'] = !_muteSound;
    // If active and now muted, silence the native oscillator immediately.
    if (_muteSound && _isPlaying) AudioInputFFI().thereminSetVolume(0.0);
    rack.markDirty();
    setState(() {});
  }

  // ─── Pitch / volume mapping ───────────────────────────────────────────────

  /// Converts a vertical pad position to a frequency in Hz.
  ///
  /// Y = 0 (top of pad) → highest note; Y = height → lowest note.
  /// This matches the theremin convention where raising the hand raises pitch.
  /// Uses equal-temperament formula: A4 = 440 Hz, MIDI 69.
  double _yToHz(double y, double height) {
    // t ∈ [0, 1]: 0 = bottom (low pitch), 1 = top (high pitch).
    final t = 1.0 - (y / height).clamp(0.0, 1.0);
    final semitones = t * _rangeOctaves * 12.0;
    return 440.0 *
        pow(2.0, ((_baseNote + semitones) - 69.0) / 12.0).toDouble();
  }

  /// Converts a horizontal pad position to a normalised volume value [0, 1].
  ///
  /// X = 0 (left) → silent; X = width (right) → full volume.
  double _xToVolNorm(double x, double width) =>
      (x / width).clamp(0.0, 1.0);

  // ─── Touch handlers (PAD mode only) ──────────────────────────────────────

  /// Called on every pointer-down/move to update pitch + volume.
  ///
  /// Sends the continuous Hz value to the native C oscillator (unless muted)
  /// and dispatches MIDI note-on/off via MIDI OUT whenever the pitch crosses
  /// a semitone boundary.
  void _onTouch(Offset position) {
    final hz = _yToHz(position.dy, _padSize.height);
    final vol = _xToVolNorm(position.dx, _padSize.width);

    // Native sound — skip when muted so the C oscillator stays silent.
    if (!_muteSound) {
      AudioInputFFI().thereminSetPitchHz(hz);
      AudioInputFFI().thereminSetVolume(vol);
    }

    // MIDI OUT: emit note-off for the previous note and note-on for the new
    // one whenever the pitch crosses a semitone boundary.
    if (mounted) {
      final midiNote = _hzToMidiNote(hz);
      final velocity = (vol * 127).round().clamp(1, 127);
      if (midiNote != _lastMidiNoteOut) {
        if (_lastMidiNoteOut >= 0) _dispatchNoteOff(_lastMidiNoteOut);
        _dispatchNoteOn(midiNote, velocity);
        _lastMidiNoteOut = midiNote;
      }
    }

    setState(() {
      _isPlaying = true;
      _orbPosition = position;
    });
  }

  /// Called when the finger lifts: fade native volume to zero and release MIDI.
  void _onRelease() {
    if (!_muteSound) AudioInputFFI().thereminSetVolume(0.0);
    if (mounted && _lastMidiNoteOut >= 0) {
      _dispatchNoteOff(_lastMidiNoteOut);
      _lastMidiNoteOut = -1;
    }
    setState(() {
      _isPlaying = false;
      _orbPosition = null;
    });
  }

  /// Stops the sounding note without a setState call.  Safe to call from
  /// [dispose] and mode-switch paths where rebuilding is undesirable.
  ///
  /// Does not dispatch MIDI — callers that have context should call
  /// [_dispatchNoteOff] themselves before calling this.
  void _stopCurrentNote() {
    if (!_isPlaying) return;
    AudioInputFFI().thereminSetVolume(0.0);
    _isPlaying = false;
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rack = context.read<RackState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Mode toggle (PAD / CAM) ──────────────────────────────────────
          _buildModeToggle(l10n),

          const SizedBox(height: 4),

          // ── Main row: pad + controls sidebar ─────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Touch / camera pad ──────────────────────────────────────
              Expanded(
                child: SizedBox(
                  height: _padPixelHeight,
                  child: LayoutBuilder(
                    builder: (ctx, constraints) {
                      // Capture pad dimensions for the camera listener.
                      _padSize =
                          Size(constraints.maxWidth, constraints.maxHeight);

                      return GestureDetector(
                        // Claim all pan gestures (horizontal + vertical) so
                        // the parent rack ScrollView cannot scroll while the
                        // player's finger is on the pad. The Listener child
                        // still receives all raw pointer events for pitch/volume
                        // mapping — the two mechanisms are independent.
                        behavior: HitTestBehavior.opaque,
                        onPanDown: (_) {},
                        onPanStart: (_) {},
                        onPanUpdate: (_) {},
                        onPanEnd: (_) {},
                        onPanCancel: () {},
                        child: Listener(
                        // Raw pointer events avoid gesture arena conflicts with
                        // the enclosing rack scroll view.
                        onPointerDown: (e) {
                          if (_inputMode == _ThereminInputMode.touchPad) {
                            _onTouch(e.localPosition);
                          }
                        },
                        onPointerMove: (e) {
                          if (_inputMode == _ThereminInputMode.touchPad) {
                            _onTouch(e.localPosition);
                          }
                        },
                        onPointerUp: (_) {
                          if (_inputMode == _ThereminInputMode.touchPad) {
                            _onRelease();
                          }
                        },
                        onPointerCancel: (_) {
                          if (_inputMode == _ThereminInputMode.touchPad) {
                            _onRelease();
                          }
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Dark gradient pad + glowing orb.
                            _ThereminPad(
                              orbPosition: _orbPosition,
                              baseNote: _baseNote,
                              rangeOctaves: _rangeOctaves,
                            ),
                            // Camera status overlay (badge / spinner / error).
                            if (_inputMode == _ThereminInputMode.camera)
                              _CamStatusOverlay(
                                isStarting: _camStarting,
                                errorCode: _camError,
                                isPlaying: _orbPosition != null,
                                previewFrame: _distSvc.previewFrame.value,
                                l10n: l10n,
                              ),
                          ],
                        ),
                      ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // ── Controls sidebar ─────────────────────────────────────────
              _ControlSidebar(
                baseNote: _baseNote,
                rangeOctaves: _rangeOctaves,
                vibrato: _vibrato,
                padHeightIdx: _padHeightIdx,
                padHeightLabels: _GFpaThereminSlotUIState._kPadHeightLabels,
                onBaseNoteDecrement: () => _changeBaseNote(-1, rack),
                onBaseNoteIncrement: () => _changeBaseNote(1, rack),
                onRangeDecrement: () => _changeRange(-1, rack),
                onRangeIncrement: () => _changeRange(1, rack),
                onVibratoDecrement: () => _changeVibrato(-1, rack),
                onVibratoIncrement: () => _changeVibrato(1, rack),
                onPadHeightDecrement: () => _changePadHeight(-1, rack),
                onPadHeightIncrement: () => _changePadHeight(1, rack),
                l10n: l10n,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the PAD / CAM / MUTE control row.
  ///
  /// PAD and CAM are input-mode toggles; MUTE is an independent output toggle
  /// that silences the native C oscillator while MIDI OUT keeps flowing.
  Widget _buildModeToggle(AppLocalizations l10n) {
    final isPad = _inputMode == _ThereminInputMode.touchPad;
    final camSupported = _distSvc.isPlatformSupported;
    final rack = context.read<RackState>();

    final camButton = _ModeButton(
      label: l10n.thereminModeCam,
      selected: !isPad,
      enabled: camSupported,
      // Only allow switching *to* camera when in pad mode (avoids double-start).
      onTap: camSupported && isPad ? () => _switchToCamera() : null,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ModeButton(
          label: l10n.thereminModePad,
          selected: isPad,
          // Allow switching back to pad mode from any camera sub-state.
          onTap: isPad ? null : _switchToPad,
        ),
        const SizedBox(width: 4),
        // On unsupported platforms wrap in a tooltip explaining why it's greyed out.
        camSupported
            ? camButton
            : Tooltip(
                message: l10n.thereminCamErrUnsupported,
                child: camButton,
              ),
        // Visual gap to separate mode toggles from the output option.
        const SizedBox(width: 8),
        // MUTE silences the native synth; MIDI OUT continues to flow.
        _ModeButton(
          label: l10n.midiMuteOwnSound,
          selected: _muteSound,
          onTap: () => _toggleMute(rack),
        ),
      ],
    );
  }
}

// ─── Mode toggle button ───────────────────────────────────────────────────────

/// A small pill-shaped toggle button used in the PAD / CAM selector row.
///
/// When [selected] is true the button is highlighted in purple to indicate the
/// active mode.  When [enabled] is false the button is visually dimmed and
/// [onTap] is not invoked (the platform does not support that mode).
class _ModeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _ModeButton({
    required this.label,
    required this.selected,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? Colors.purpleAccent.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected
                ? Colors.purpleAccent.withValues(alpha: 0.65)
                : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
            color: !enabled
                ? Colors.white24
                : selected
                    ? Colors.purpleAccent
                    : Colors.white54,
          ),
        ),
      ),
    );
  }
}

// ─── Camera status overlay ────────────────────────────────────────────────────

/// Overlay drawn on top of the theremin pad while in camera mode.
///
/// Three states:
///   • **Starting** — shows a circular progress indicator while the native
///     camera session is starting.
///   • **Error**    — shows a camera-off icon and a localised error message.
///   • **Active**   — shows a small "CAM" badge in the top-right corner.
///     When [isPlaying] is false (hand out of range) an additional hint text
///     is shown in the centre so the user knows what to do.
class _CamStatusOverlay extends StatelessWidget {
  final bool isStarting;
  final String? errorCode;

  /// True when the orb is visible (a note is sounding), false when silent.
  final bool isPlaying;

  /// Latest JPEG thumbnail from the camera preview channel, or null if not yet received.
  final Uint8List? previewFrame;

  final AppLocalizations l10n;

  const _CamStatusOverlay({
    required this.isStarting,
    required this.errorCode,
    required this.isPlaying,
    required this.previewFrame,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    if (isStarting) return _buildStarting();
    if (errorCode != null) return _buildError();
    return _buildActive();
  }

  /// Centred spinner shown while [ThereminDistanceService.start] is awaiting.
  Widget _buildStarting() {
    return const Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.purpleAccent,
        ),
      ),
    );
  }

  /// Semi-transparent overlay with a camera-off icon and a localised message.
  Widget _buildError() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white38, size: 24),
              const SizedBox(height: 8),
              Text(
                _errorMessage(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small CAM badge in the top-right, plus a centre hint when silent.
  Widget _buildActive() {
    return Stack(
      children: [
        // Semi-transparent camera preview (updated at ≈ 5 fps).
        // Opacity 0.35 so the glowing orb remains the visual focus.
        if (previewFrame != null)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Opacity(
                opacity: 0.35,
                child: Image.memory(
                  previewFrame!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true, // prevents flicker between frames
                ),
              ),
            ),
          ),

        // "CAM" badge — always visible so users know which mode is active.
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.purpleAccent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: Colors.purpleAccent.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.videocam,
                  size: 9,
                  color: Colors.purpleAccent.withValues(alpha: 0.8),
                ),
                const SizedBox(width: 3),
                Text(
                  'CAM',
                  style: TextStyle(
                    fontSize: 8,
                    letterSpacing: 1,
                    fontWeight: FontWeight.bold,
                    color: Colors.purpleAccent.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Hint text: visible only when no note is sounding.
        if (!isPlaying)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                l10n.thereminCamHint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0x33FFFFFF),
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Maps an error code returned by [ThereminDistanceService.start] to a
  /// localised message string.
  String _errorMessage() {
    switch (errorCode) {
      case 'NO_PERMISSION':
        return l10n.thereminCamErrNoPermission;
      case 'NO_CAMERA':
        return l10n.thereminCamErrNoCamera;
      case 'FIXED_FOCUS':
        return l10n.thereminCamErrFixedFocus;
      case 'CONFIG_ERROR':
        return l10n.thereminCamErrConfigError;
      case 'PLATFORM_UNSUPPORTED':
        return l10n.thereminCamErrUnsupported;
      default:
        return l10n.thereminCamErrConfigError;
    }
  }
}

// ─── Touch pad ────────────────────────────────────────────────────────────────

/// The main theremin playing surface: a dark gradient pad with a floating
/// glowing orb at the active position (touch or camera-driven).
class _ThereminPad extends StatelessWidget {
  final Offset? orbPosition;
  final int baseNote;
  final int rangeOctaves;

  const _ThereminPad({
    required this.orbPosition,
    required this.baseNote,
    required this.rangeOctaves,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ── Background gradient ──────────────────────────────────────────
          // Deep blue at the bottom (low pitch) → violet at the top (high pitch),
          // evoking the electromagnetic field around a real theremin antenna.
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Color(0xFF050510),
                  Color(0xFF120A22),
                  Color(0xFF1E083A),
                ],
              ),
              border: Border.fromBorderSide(
                BorderSide(color: Color(0xFF3A1A5A), width: 1),
              ),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            ),
          ),

          // ── Hint overlays (PAD mode axis labels) ─────────────────────────
          const Positioned(
            left: 8,
            top: 6,
            child: Text(
              '▲ High',
              style: TextStyle(color: Color(0x44FFFFFF), fontSize: 9),
            ),
          ),
          const Positioned(
            left: 8,
            bottom: 6,
            child: Text(
              '▼ Low',
              style: TextStyle(color: Color(0x44FFFFFF), fontSize: 9),
            ),
          ),
          const Positioned(
            right: 8,
            bottom: 6,
            child: Text(
              'Vol ▶',
              style: TextStyle(color: Color(0x44FFFFFF), fontSize: 9),
            ),
          ),

          // ── Glowing orb ──────────────────────────────────────────────────
          // Appears while a note is sounding (in both PAD and CAM modes).
          if (orbPosition != null)
            Positioned(
              // Centre the 48 × 48 orb on the active position.
              left: orbPosition!.dx - 24,
              top: orbPosition!.dy - 24,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // Inner core: bright white-purple.
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.9),
                      Colors.purpleAccent.withValues(alpha: 0.7),
                      Colors.purpleAccent.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                  boxShadow: [
                    // Outer glow — wide spread for the theremin field effect.
                    BoxShadow(
                      color: Colors.purpleAccent.withValues(alpha: 0.6),
                      blurRadius: 32,
                      spreadRadius: 12,
                    ),
                    // Inner sharp glow for a bright core.
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.5),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Controls sidebar ─────────────────────────────────────────────────────────

/// Small vertical sidebar with +/− controls for base note, range, vibrato,
/// and pad height.
///
/// Displayed to the right of the theremin pad so the controls are always
/// accessible without occluding the playing surface.
class _ControlSidebar extends StatelessWidget {
  final int baseNote;
  final int rangeOctaves;
  final double vibrato;

  /// Current pad-height preset index (0 = S, 1 = M, 2 = L, 3 = XL).
  final int padHeightIdx;

  /// Display labels for the four height presets, indexed by [padHeightIdx].
  final List<String> padHeightLabels;

  final VoidCallback onBaseNoteDecrement;
  final VoidCallback onBaseNoteIncrement;
  final VoidCallback onRangeDecrement;
  final VoidCallback onRangeIncrement;
  final VoidCallback onVibratoDecrement;
  final VoidCallback onVibratoIncrement;
  final VoidCallback onPadHeightDecrement;
  final VoidCallback onPadHeightIncrement;
  final AppLocalizations l10n;

  const _ControlSidebar({
    required this.baseNote,
    required this.rangeOctaves,
    required this.vibrato,
    required this.padHeightIdx,
    required this.padHeightLabels,
    required this.onBaseNoteDecrement,
    required this.onBaseNoteIncrement,
    required this.onRangeDecrement,
    required this.onRangeIncrement,
    required this.onVibratoDecrement,
    required this.onVibratoIncrement,
    required this.onPadHeightDecrement,
    required this.onPadHeightIncrement,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    // Note name for the base note label (e.g. C3, D♯4).
    const noteNames = [
      'C', 'C♯', 'D', 'D♯', 'E',
      'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B',
    ];
    final noteName = '${noteNames[baseNote % 12]}${(baseNote ~/ 12) - 1}';

    // Display vibrato as a percentage string: 0%, 25%, 50%, 75%, 100%.
    final vibratoLabel = '${(vibrato * 100).round()}%';

    return SizedBox(
      width: 62,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Base note control.
          _SideControl(
            label: 'BASE',
            value: noteName,
            canDecrement: baseNote > 36,
            canIncrement: baseNote < 72,
            onDecrement: onBaseNoteDecrement,
            onIncrement: onBaseNoteIncrement,
          ),

          const SizedBox(height: 8),

          // Range control.
          _SideControl(
            label: 'RANGE',
            value: '${rangeOctaves}oct',
            canDecrement: rangeOctaves > 1,
            canIncrement: rangeOctaves < 4,
            onDecrement: onRangeDecrement,
            onIncrement: onRangeIncrement,
          ),

          const SizedBox(height: 8),

          // Vibrato depth control.
          _SideControl(
            label: l10n.thereminVibrato,
            value: vibratoLabel,
            canDecrement: vibrato > 0.0,
            canIncrement: vibrato < 1.0,
            onDecrement: onVibratoDecrement,
            onIncrement: onVibratoIncrement,
          ),

          const SizedBox(height: 8),

          // Pad height preset control (S / M / L / XL).
          _SideControl(
            label: l10n.thereminPadHeight,
            value: padHeightLabels[padHeightIdx],
            canDecrement: padHeightIdx > 0,
            canIncrement: padHeightIdx < padHeightLabels.length - 1,
            onDecrement: onPadHeightDecrement,
            onIncrement: onPadHeightIncrement,
          ),
        ],
      ),
    );
  }
}

/// A labelled mini +/− control used in [_ControlSidebar].
class _SideControl extends StatelessWidget {
  final String label;
  final String value;
  final bool canDecrement;
  final bool canIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _SideControl({
    required this.label,
    required this.value,
    required this.canDecrement,
    required this.canIncrement,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            color: Colors.white38,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MiniButton(
              icon: Icons.remove,
              enabled: canDecrement,
              onPressed: onDecrement,
            ),
            const SizedBox(width: 4),
            _MiniButton(
              icon: Icons.add,
              enabled: canIncrement,
              onPressed: onIncrement,
            ),
          ],
        ),
      ],
    );
  }
}

/// Tiny icon button used inside [_SideControl].
class _MiniButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  const _MiniButton({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: enabled
              ? Colors.white12
              : Colors.white.withValues(alpha: 0.04),
          foregroundColor: enabled ? Colors.white70 : Colors.white24,
          shape: const CircleBorder(),
          elevation: 0,
        ),
        onPressed: enabled ? onPressed : null,
        child: Icon(icon, size: 12),
      ),
    );
  }
}
