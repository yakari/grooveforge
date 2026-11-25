/// Localised labels for the CC targets that services define without a
/// [BuildContext].
///
/// [CcMappingService.standardGmCcs] and [CcParamRegistry] keep their English
/// labels: they are `const` tables, read by code that has no locale, and the
/// English text doubles as the fallback here. These helpers turn an entry into
/// the label the player reads, at the point where an [AppLocalizations] is in
/// hand. gen-l10n offers no lookup by string key, hence the switches.
library;

import '../l10n/app_localizations.dart';
import 'cc_mapping_service.dart';
import 'cc_param_registry.dart';

/// Localised name of a standard GM CC, a pitch-bend target or a legacy system
/// action — every key of [CcMappingService.standardGmCcs].
///
/// Returns null when [cc] is not in that table, so callers keep their own
/// "CC n" / "unknown" fallback exactly as with a map lookup.
String? gmCcLabel(AppLocalizations l10n, int cc) {
  final english = CcMappingService.standardGmCcs[cc];
  if (english == null) return null;
  return switch (cc) {
    0 => l10n.ccGmBankSelect,
    1 => l10n.ccGmModWheel,
    2 => l10n.ccGmBreath,
    4 => l10n.ccGmFootPedal,
    5 => l10n.ccGmPortamentoTime,
    7 => l10n.ccGmMainVolume,
    10 => l10n.ccGmPan,
    11 => l10n.ccGmExpression,
    64 => l10n.ccGmSustainPedal,
    65 => l10n.ccGmPortamento,
    71 => l10n.ccGmResonance,
    74 => l10n.ccGmCutoff,
    91 => l10n.ccGmReverbSend,
    93 => l10n.ccGmChorusSend,
    CcMappingService.pitchBendTarget => l10n.actionPitchBend,
    1001 => l10n.ccSysNextSoundfont,
    1002 => l10n.ccSysPrevSoundfont,
    1003 => l10n.ccSysNextPatch,
    1004 => l10n.ccSysPrevPatch,
    1005 => l10n.ccSysPatchSweep,
    1006 => l10n.ccSysBankSweep,
    1007 => l10n.ccSysJamMode,
    1008 => l10n.ccSysCycleScale,
    1009 => l10n.ccSysMidiLooperLoop,
    1012 => l10n.ccSysMidiLooperStop,
    1015 => l10n.ccSysAudioLooperLoop,
    1016 => l10n.ccSysAudioLooperStop,
    1014 => l10n.ccSysMuteChannels,
    // A code added to the table without a translation yet: English beats
    // nothing.
    _ => english,
  };
}

/// Localised name of a CC-controllable parameter.
///
/// Keyed on the entry's English [CcParamEntry.displayName] rather than its
/// `paramKey`, because the same key means different things on different
/// plugins ("bypass" is "Mute" on Riff and "Toggle On/Off" on Jam Mode), while
/// equal labels always mean the same thing. An unknown label is shown as is.
String ccParamLabel(AppLocalizations l10n, CcParamEntry entry) {
  return switch (entry.displayName) {
    'Mix' => l10n.ccParamMix,
    'Waveform' => l10n.ccParamWaveform,
    'Volume' => l10n.ccParamVolume,
    'Toggle On/Off' => l10n.ccParamToggleOnOff,
    'Stop' => l10n.ccParamStop,
    'Level' => l10n.ccParamLevel,
    'Bypass' => l10n.ccParamBypass,
    'Vibrato Depth' => l10n.ccParamVibratoDepth,
    'Vibrato' => l10n.ccParamVibrato,
    'Tune On/Off' => l10n.ccParamTuneOnOff,
    'Tone' => l10n.ccParamTone,
    'Time' => l10n.ccParamTime,
    'Threshold' => l10n.ccParamThreshold,
    'Swing' => l10n.ccParamSwing,
    'Sustain' => l10n.ccParamSustain,
    'Strength' => l10n.ccParamStrength,
    'Start / Stop' => l10n.ccParamStartStop,
    'Snap On/Off' => l10n.ccParamSnapOnOff,
    'Semitones' => l10n.ccParamSemitones,
    'Select Patch' => l10n.ccParamSelectPatch,
    'Scale Type' => l10n.ccParamScaleType,
    'Retune' => l10n.ccParamRetune,
    'Recall Scale' => l10n.ccParamRecallScale,
    'Recall Root' => l10n.ccParamRecallRoot,
    'Rate' => l10n.ccParamRate,
    'Range (octaves)' => l10n.ccParamRangeOctaves,
    'Previous Soundfont' => l10n.ccParamPrevSoundfont,
    'Previous Pattern' => l10n.ccParamPrevPattern,
    'Previous Patch' => l10n.ccParamPrevPatch,
    'Pickup type' => l10n.ccParamPickupType,
    'Pickup' => l10n.ccParamPickup,
    'Pick position' => l10n.ccParamPickPosition,
    'Pedal sustain' => l10n.ccParamPedalSustain,
    'Pedal' => l10n.ccParamPedal,
    'Pattern' => l10n.ccParamPattern,
    'Patch (knob)' => l10n.ccParamPatchKnob,
    'Palm mute on/off' => l10n.ccParamPalmMuteOnOff,
    'Palm mute' => l10n.ccParamPalmMute,
    'Overlap legato on/off' => l10n.ccParamOverlapLegato,
    'Noise Mix' => l10n.ccParamNoiseMix,
    'Next Soundfont' => l10n.ccParamNextSoundfont,
    'Next Scale (in family)' => l10n.ccParamNextScaleInFamily,
    'Next Pattern' => l10n.ccParamNextPattern,
    'Next Patch' => l10n.ccParamNextPatch,
    'Mute' => l10n.ccParamMute,
    'Mode' => l10n.ccParamMode,
    'Loop Button (Record/Play/Overdub)' => l10n.ccParamMidiLoopButton,
    'Loop Button (Arm/Record/Play/Overdub)' => l10n.ccParamAudioLoopButton,
    'Legato on/off (hammer-on / pull-off)' => l10n.ccParamLegatoOnOff,
    'Latch Root from Held Notes' => l10n.ccParamLatchRoot,
    'Input Gain' => l10n.ccParamInputGain,
    'Human Feel' => l10n.ccParamHumanFeel,
    'Gate Threshold' => l10n.ccParamGateThreshold,
    'Gain' => l10n.ccParamGain,
    'Feedback (larsen)' => l10n.ccParamFeedback,
    'Feedback harmonic' => l10n.ccParamFeedbackHarmonic,
    'Envelope Release' => l10n.ccParamEnvRelease,
    'Drive type' => l10n.ccParamDriveType,
    'Drive on/off' => l10n.ccParamDriveOnOff,
    'Drive' => l10n.ccParamDrive,
    'Division' => l10n.ccParamDivision,
    'Detection Mode' => l10n.ccParamDetectionMode,
    'Depth' => l10n.ccParamDepth,
    'Chord Type' => l10n.ccParamChordType,
    'Chiptune Arp On/Off' => l10n.ccParamChipArpOnOff,
    'Chiptune Arp Chord' => l10n.ccParamChipArpChord,
    'Center' => l10n.ccParamCenter,
    'Cab on/off' => l10n.ccParamCabOnOff,
    'BPM Sync' => l10n.ccParamBpmSync,
    'Base Note' => l10n.ccParamBaseNote,
    'Bandwidth' => l10n.ccParamBandwidth,
    'Attack' => l10n.ccParamAttack,
    'Arp Rate (PAL/NTSC)' => l10n.ccParamArpRate,
    'Amp on/off' => l10n.ccParamAmpOnOff,
    'Amount' => l10n.ccParamAmount,
    _ => entry.displayName,
  };
}
