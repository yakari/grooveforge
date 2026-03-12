import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

/// Identifies a typed port on a rack slot's back panel.
///
/// Ports are grouped into three signal families:
///   - **MIDI** (yellow)   — MIDI note and CC event streams
///   - **Audio** (red/white/orange) — PCM audio signals
///   - **Data** (purple)   — Chord and scale information for Jam Mode routing
enum AudioPortId {
  // ── MIDI family ──────────────────────────────────────────────────────────
  /// Receives MIDI events from hardware or another slot's MIDI OUT.
  midiIn,

  /// Sends MIDI events to another slot's MIDI IN.
  midiOut,

  // ── Audio family ─────────────────────────────────────────────────────────
  /// Left-channel audio input (effects / VST3 only).
  audioInL,

  /// Right-channel audio input (effects / VST3 only).
  audioInR,

  /// Left-channel audio output.
  audioOutL,

  /// Right-channel audio output.
  audioOutR,

  /// Taps a copy of the audio to an auxiliary send bus.
  sendOut,

  /// Receives processed audio back from a send bus.
  returnIn,

  // ── Data family (Jam Mode chord/scale routing) ───────────────────────────
  /// Outputs the chord detected by a keyboard slot (connects to a Jam Mode
  /// [chordIn] port to designate this keyboard as the Jam Master).
  chordOut,

  /// Receives chord information from a master keyboard slot.
  chordIn,

  /// Outputs the computed scale from a Jam Mode slot (connects to a
  /// keyboard's [scaleIn] port to apply scale locking).
  scaleOut,

  /// Receives scale-lock information from a Jam Mode slot.
  scaleIn,
}

/// Extensions providing display, colour, and compatibility metadata for
/// [AudioPortId] values.
extension AudioPortIdX on AudioPortId {
  // ── Colour ─────────────────────────────────────────────────────────────

  /// Visual colour used for cable rendering and jack indicators.
  Color get color {
    switch (this) {
      case AudioPortId.midiIn:
      case AudioPortId.midiOut:
        return const Color(0xFFFFD700); // yellow
      case AudioPortId.audioInL:
      case AudioPortId.audioOutL:
        return const Color(0xFFFF4444); // red  (left channel)
      case AudioPortId.audioInR:
      case AudioPortId.audioOutR:
        return const Color(0xFFF0F0F0); // white (right channel)
      case AudioPortId.sendOut:
      case AudioPortId.returnIn:
        return const Color(0xFFFF8C00); // orange (send bus)
      case AudioPortId.chordOut:
      case AudioPortId.chordIn:
      case AudioPortId.scaleOut:
      case AudioPortId.scaleIn:
        return const Color(0xFFAA44FF); // purple (data)
    }
  }

  // ── Direction ──────────────────────────────────────────────────────────

  /// True for output ports (the "cable source" side).
  bool get isOutput {
    switch (this) {
      case AudioPortId.midiOut:
      case AudioPortId.audioOutL:
      case AudioPortId.audioOutR:
      case AudioPortId.sendOut:
      case AudioPortId.chordOut:
      case AudioPortId.scaleOut:
        return true;
      default:
        return false;
    }
  }

  /// True for input ports (the "cable destination" side).
  bool get isInput => !isOutput;

  // ── Family ─────────────────────────────────────────────────────────────

  /// True for Jam Mode chord/scale data ports (purple family).
  bool get isDataPort {
    switch (this) {
      case AudioPortId.chordOut:
      case AudioPortId.chordIn:
      case AudioPortId.scaleOut:
      case AudioPortId.scaleIn:
        return true;
      default:
        return false;
    }
  }

  // ── Compatibility ──────────────────────────────────────────────────────

  /// Returns true if this output port can connect to [other] input port.
  ///
  /// Connection rules:
  ///   - midiOut    → midiIn
  ///   - audioOutL  → audioInL
  ///   - audioOutR  → audioInR
  ///   - sendOut    → returnIn
  ///   - chordOut   → chordIn
  ///   - scaleOut   → scaleIn
  bool compatibleWith(AudioPortId other) {
    switch (this) {
      case AudioPortId.midiOut:
        return other == AudioPortId.midiIn;
      case AudioPortId.audioOutL:
        return other == AudioPortId.audioInL;
      case AudioPortId.audioOutR:
        return other == AudioPortId.audioInR;
      case AudioPortId.sendOut:
        return other == AudioPortId.returnIn;
      case AudioPortId.chordOut:
        return other == AudioPortId.chordIn;
      case AudioPortId.scaleOut:
        return other == AudioPortId.scaleIn;
      default:
        // Input ports cannot be a drag source — never compatible as "from".
        return false;
    }
  }

  // ── Localised label ────────────────────────────────────────────────────

  /// Short localised label displayed below the jack in the patch view.
  String localizedLabel(AppLocalizations l10n) {
    switch (this) {
      case AudioPortId.midiIn:
        return l10n.portMidiIn;
      case AudioPortId.midiOut:
        return l10n.portMidiOut;
      case AudioPortId.audioInL:
        return l10n.portAudioInL;
      case AudioPortId.audioInR:
        return l10n.portAudioInR;
      case AudioPortId.audioOutL:
        return l10n.portAudioOutL;
      case AudioPortId.audioOutR:
        return l10n.portAudioOutR;
      case AudioPortId.sendOut:
        return l10n.portSendOut;
      case AudioPortId.returnIn:
        return l10n.portReturnIn;
      case AudioPortId.chordOut:
        return l10n.portChordOut;
      case AudioPortId.chordIn:
        return l10n.portChordIn;
      case AudioPortId.scaleOut:
        return l10n.portScaleOut;
      case AudioPortId.scaleIn:
        return l10n.portScaleIn;
    }
  }
}
