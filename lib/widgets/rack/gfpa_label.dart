import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge_plugin_ui/grooveforge_plugin_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/gfpa_plugin_instance.dart';
import '../../models/plugin_instance.dart';

/// Translated text for the panels of the plugins bundled as `.gfpd` files.
///
/// The plugin UI package draws a descriptor's panel but holds no
/// translations, so it asks the host for every text it draws through
/// `GFDescriptorPluginUI.labelResolver`. This file is that host side, and
/// also names bundled plugins in the rack slot header.
///
/// gen-l10n offers no lookup by string, so the table below maps each text's
/// stable address — plugin, [GFLabelKind] and key — to its ARB getter. The
/// table is generated from the bundled `.gfpd` files; a text missing from it
/// (a third-party plugin, a symbol such as `BPM` or `1/8T`) keeps the
/// descriptor's own text.

/// Id prefix reserved for the plugins that ship with the app. Third-party
/// `.gfpd` files cannot use it, so only bundled plugins reach the table.
const _bundledPrefix = 'com.grooveforge.';

/// The language part of [l10n]'s locale (`fr` for `fr_CA`), used to pick the
/// text of `.gfpd` names and labels written as language maps.
String gfpaLanguageCode(AppLocalizations l10n) =>
    l10n.localeName.split(RegExp('[_-]')).first;

/// Returns the translation of one text of the bundled plugin [pluginId], or
/// [fallback] when there is none.
///
/// [kind] and [key] follow [GFLabelKind]: the key is a parameter id, a
/// button action, a group label slug or `<parameter id>.<option index>`.
String gfpaLabel(
  AppLocalizations l10n,
  String pluginId,
  GFLabelKind kind,
  String key,
  String fallback,
) {
  if (!pluginId.startsWith(_bundledPrefix)) return fallback;
  final short = pluginId.substring(_bundledPrefix.length);
  return _bundledLabel(l10n, '$short|${kind.name}|$key') ?? fallback;
}

/// The resolver to hand to `GFDescriptorPluginUI.labelResolver` for a slot
/// running [pluginId].
GFLabelResolver gfpaLabelResolver(AppLocalizations l10n, String pluginId) =>
    (kind, key, fallback) => gfpaLabel(l10n, pluginId, kind, key, fallback);

/// The name shown in a rack slot header: the translated name for a
/// descriptor plugin, the slot's own [PluginInstance.displayName] for
/// everything else.
String gfpaSlotHeaderName(AppLocalizations l10n, PluginInstance plugin) {
  if (plugin is! GFpaPluginInstance) return plugin.displayName;
  final registered = GFPluginRegistry.instance.findById(plugin.pluginId);
  if (registered is! GFAbstractDescriptorPlugin) return plugin.displayName;

  // A third-party name written as a language map resolves here; a bundled
  // plugin's name then goes through the ARB table.
  final descriptor = registered.descriptor;
  final ownName = descriptor.nameIn(gfpaLanguageCode(l10n));
  return gfpaLabel(l10n, descriptor.id, GFLabelKind.pluginName, '', ownName);
}

/// The ARB text addressed by `<plugin>|<kind>|<key>`, or null when the
/// bundled plugins have no such text.
///
/// Generated from `assets/plugins/*.gfpd`. Language-neutral texts (`BPM`,
/// `LFO`, note names, chord symbols, note divisions, amp model and cabinet
/// names) are left out on purpose and keep the descriptor's text.
String? _bundledLabel(AppLocalizations l10n, String address) {
  return switch (address) {
      'amp|pluginName|' => l10n.rackAddAmp,
      'amp|group|drive' => l10n.gfpaAmpDrive,
      'amp|group|amp' => l10n.gfpaAmpAmp,
      'amp|group|cab' => l10n.gfpaAmpCab,
      'amp|group|output' => l10n.gfpaLabelOutput,
      'amp|control|drive_on' => l10n.gfpaAmpOn,
      'amp|control|drive_mode' => l10n.gfpaLabelType,
      'amp|option|drive_mode.0' => l10n.gfpaAmpOverdrive,
      'amp|option|drive_mode.1' => l10n.vst3EffectTypeDistortion,
      'amp|control|drive' => l10n.gfpaAmpDrive,
      'amp|control|drive_tone' => l10n.gfpaLabelTone,
      'amp|control|amp_on' => l10n.gfpaAmpOn,
      'amp|control|amp_model' => l10n.gfpaAmpModel,
      'amp|control|gain' => l10n.gfpaAmpGain,
      'amp|control|bass' => l10n.gfpaAmpBass,
      'amp|control|middle' => l10n.gfpaAmpMiddle,
      'amp|control|treble' => l10n.gfpaAmpTreble,
      'amp|control|cab_on' => l10n.gfpaAmpOn,
      'amp|control|cab_type' => l10n.gfpaAmpCabinet,
      'amp|control|level' => l10n.gfpaLabelLevel,
      'arpeggiator|pluginName|' => l10n.rackAddArpeggiator,
      'arpeggiator|group|pattern' => l10n.gfpaArpeggiatorPattern,
      'arpeggiator|group|rhythm' => l10n.gfpaArpeggiatorRhythm,
      'arpeggiator|group|gate' => l10n.gfpaArpeggiatorGate,
      'arpeggiator|group|range' => l10n.gfpaArpeggiatorRange,
      'arpeggiator|control|pattern' => l10n.gfpaArpeggiatorPattern,
      'arpeggiator|option|pattern.0' => l10n.gfpaArpeggiatorUp,
      'arpeggiator|option|pattern.1' => l10n.gfpaArpeggiatorDown,
      'arpeggiator|option|pattern.2' => l10n.gfpaArpeggiatorUpDown,
      'arpeggiator|option|pattern.3' => l10n.gfpaArpeggiatorDnUp,
      'arpeggiator|option|pattern.4' => l10n.gfpaArpeggiatorPlayed,
      'arpeggiator|option|pattern.5' => l10n.drumGeneratorFillRandom,
      'arpeggiator|control|division' => l10n.gfpaArpeggiatorDivision,
      'arpeggiator|control|gate' => l10n.gfpaArpeggiatorGate,
      'arpeggiator|control|octaves' => l10n.gfpaArpeggiatorOctaves,
      'audio_harmonizer|pluginName|' => l10n.rackAddAudioHarmonizer,
      'audio_harmonizer|group|setup' => l10n.gfpaLabelSetup,
      'audio_harmonizer|control|voice_count' => l10n.gfpaLabelVoices,
      'audio_harmonizer|control|dry_wet' => l10n.gfpaAudioHarmonizerDryWet,
      'audio_harmonizer|control|scale_lock' => l10n.gfpaLabelScaleLock,
      'audio_harmonizer|control|voice1_mix' => l10n.gfpaLabelLevel,
      'audio_harmonizer|control|voice2_mix' => l10n.gfpaLabelLevel,
      'audio_harmonizer|control|voice3_mix' => l10n.gfpaLabelLevel,
      'audio_harmonizer|control|voice4_mix' => l10n.gfpaLabelLevel,
      'autotune|pluginName|' => l10n.rackAddAutotune,
      'autotune|group|notes' => l10n.gfpaAutotuneNotes,
      'autotune|group|tune' => l10n.gfpaAutotuneTune,
      'autotune|group|voice' => l10n.gfpaAutotuneVoice,
      'autotune|control|key' => l10n.gfpaAutotuneKey,
      'autotune|control|scale' => l10n.gfpaLabelScale,
      'autotune|option|scale.0' => l10n.gfpaAutotuneChromatic,
      'autotune|option|scale.1' => l10n.gfpaAutotuneMajor,
      'autotune|option|scale.2' => l10n.gfpaAutotuneMinor,
      'autotune|option|scale.3' => l10n.gfpaAutotuneHarmonicMinor,
      'autotune|option|scale.4' => l10n.gfpaAutotuneMajorPenta,
      'autotune|option|scale.5' => l10n.gfpaAutotuneMinorPenta,
      'autotune|option|scale.6' => l10n.gfpaAutotuneBlues,
      'autotune|control|strength' => l10n.gfpaAutotuneStrength,
      'autotune|control|retune' => l10n.gfpaAutotuneRetune,
      'autotune|control|humanize' => l10n.gfpaAutotuneHumanize,
      'autotune|control|mix' => l10n.gfpaLabelMix,
      'chord|pluginName|' => l10n.rackAddChordExpand,
      'chord|group|chord' => l10n.gfpaChordChord,
      'chord|group|voicing' => l10n.gfpaChordVoicing,
      'chord|group|scale' => l10n.gfpaLabelScale,
      'chord|control|chord_type' => l10n.gfpaChordChordType,
      'chord|control|spread' => l10n.gfpaChordSpread,
      'chord|option|spread.0' => l10n.gfpaChordClose,
      'chord|option|spread.1' => l10n.gfpaChordOpen,
      'chord|option|spread.2' => l10n.gfpaChordWide,
      'chord|control|snap_to_scale' => l10n.gfpaLabelScaleLock,
      'chorus|pluginName|' => l10n.rackAddChorus,
      'chorus|group|delay' => l10n.gfpaLabelDelay,
      'chorus|group|output' => l10n.gfpaLabelOutput,
      'chorus|parameter|rate' => l10n.gfpaLabelRate,
      'chorus|parameter|depth' => l10n.gfpaLabelDepth,
      'chorus|option|beat_div.0' => l10n.drumGeneratorIntroCountIn2,
      'chorus|option|beat_div.1' => l10n.drumGeneratorIntroCountIn1,
      'chorus|parameter|delay' => l10n.gfpaLabelDelay,
      'chorus|parameter|mix' => l10n.gfpaLabelMix,
      'compressor|pluginName|' => l10n.rackAddCompressor,
      'compressor|group|compression' => l10n.gfpaCompressorCompression,
      'compressor|group|envelope' => l10n.gfpaCompressorEnvelope,
      'compressor|group|output' => l10n.gfpaLabelOutput,
      'compressor|parameter|threshold' => l10n.gfpaCompressorThresh,
      'compressor|parameter|ratio' => l10n.gfpaCompressorRatio,
      'compressor|parameter|attack' => l10n.gfpaLabelAttack,
      'compressor|parameter|release' => l10n.gfpaCompressorRelease,
      'compressor|parameter|makeup' => l10n.gfpaCompressorMakeup,
      'delay|pluginName|' => l10n.rackAddDelay,
      'delay|group|timing' => l10n.gfpaDelayTiming,
      'delay|group|character' => l10n.gfpaDelayCharacter,
      'delay|group|output' => l10n.gfpaLabelOutput,
      'delay|parameter|time' => l10n.gfpaDelayTime,
      'delay|option|beat_div.0' => l10n.drumGeneratorIntroCountIn2,
      'delay|option|beat_div.1' => l10n.drumGeneratorIntroCountIn1,
      'delay|parameter|feedback' => l10n.gfpaLabelFeedback,
      'delay|parameter|mix' => l10n.gfpaLabelMix,
      'eq|pluginName|' => l10n.rackAddEq,
      'eq|group|low' => l10n.gfpaEqLow,
      'eq|group|low_mid' => l10n.gfpaEqLowMid,
      'eq|group|high_mid' => l10n.gfpaEqHighMid,
      'eq|group|high' => l10n.gfpaEqHigh,
      'eq|group|output' => l10n.gfpaLabelOutput,
      'eq|parameter|low_freq' => l10n.gfpaEqLowHz,
      'eq|parameter|low_gain' => l10n.gfpaEqLowGain,
      'eq|parameter|lmid_freq' => l10n.gfpaEqLMHz,
      'eq|parameter|lmid_q' => l10n.gfpaEqLMQ,
      'eq|parameter|lmid_gain' => l10n.gfpaEqLM,
      'eq|parameter|hmid_freq' => l10n.gfpaEqHMHz,
      'eq|parameter|hmid_q' => l10n.gfpaEqHMQ,
      'eq|parameter|hmid_gain' => l10n.gfpaEqHM,
      'eq|parameter|high_freq' => l10n.gfpaEqHiHz,
      'eq|parameter|high_gain' => l10n.gfpaEqHighGain,
      'eq|control|reset' => l10n.gfpaEqFlat,
      'gate|pluginName|' => l10n.rackAddGate,
      'gate|group|velocity' => l10n.gfpaLabelVelocity,
      'gate|group|pitch' => l10n.gfpaGatePitch,
      'gate|control|min_velocity' => l10n.gfpaGateMinVel,
      'gate|control|max_velocity' => l10n.gfpaGateMaxVel,
      'gate|control|min_pitch' => l10n.gfpaGateMinNote,
      'gate|control|max_pitch' => l10n.gfpaGateMaxNote,
      'harmonizer|pluginName|' => l10n.rackAddHarmonizer,
      'harmonizer|group|setup' => l10n.gfpaLabelSetup,
      'harmonizer|control|voice_count' => l10n.gfpaLabelVoices,
      'harmonizer|control|snap_to_scale' => l10n.gfpaLabelScaleLock,
      'microtone|pluginName|' => l10n.rackAddMicrotone,
      'microtone|group|cluster' => l10n.gfpaMicrotoneCluster,
      'microtone|group|output' => l10n.gfpaLabelOutput,
      'microtone|control|chord_window' => l10n.gfpaLabelDelay,
      'microtone|control|cluster_mode' => l10n.gfpaLabelMode,
      'microtone|option|cluster_mode.0' => l10n.gfpaMicrotoneOuterAvg,
      'microtone|option|cluster_mode.1' => l10n.gfpaMicrotoneMean,
      'microtone|control|bend_range' => l10n.gfpaMicrotoneBendRange,
      'microtone|control|velocity_mode' => l10n.gfpaLabelVelocity,
      'microtone|option|velocity_mode.0' => l10n.gfpaMicrotoneAverage,
      'microtone|option|velocity_mode.1' => l10n.gfpaMicrotoneLastNote,
      'reverb|pluginName|' => l10n.rackAddReverb,
      'reverb|group|room' => l10n.gfpaReverbRoom,
      'reverb|group|output' => l10n.gfpaLabelOutput,
      'reverb|parameter|room_size' => l10n.gfpaReverbRoomSize,
      'reverb|parameter|damping' => l10n.gfpaReverbDamp,
      'reverb|parameter|width' => l10n.gfpaReverbWidth,
      'reverb|parameter|mix' => l10n.gfpaLabelMix,
      'riff|pluginName|' => l10n.rackAddRiff,
      'riff|group|picking_hand' => l10n.gfpaRiffPickingHand,
      'riff|group|fretting_hand' => l10n.gfpaRiffFrettingHand,
      'riff|group|pickups' => l10n.gfpaRiffPickups,
      'riff|group|feedback' => l10n.gfpaLabelFeedback,
      'riff|group|strings' => l10n.gfpaRiffStrings,
      'riff|control|palm_mute' => l10n.gfpaRiffPalmMute,
      'riff|control|pick_pos' => l10n.gfpaRiffPickPos,
      'riff|control|attack' => l10n.gfpaLabelAttack,
      'riff|control|legato' => l10n.gfpaRiffLegato,
      'riff|control|legato_overlap' => l10n.gfpaRiffOverlap,
      'riff|control|bend_range' => l10n.gfpaRiffBend,
      'riff|control|pickup' => l10n.gfpaRiffPickup,
      'riff|option|pickup.0' => l10n.gfpaRiffNeck,
      'riff|option|pickup.1' => l10n.gfpaRiffMiddle,
      'riff|option|pickup.2' => l10n.gfpaRiffBridge,
      'riff|option|pickup.3' => l10n.gfpaRiffNeckPlusBridge,
      'riff|control|pickup_type' => l10n.gfpaLabelType,
      'riff|option|pickup_type.0' => l10n.gfpaRiffSingleCoil,
      'riff|option|pickup_type.1' => l10n.gfpaRiffHumbucker,
      'riff|control|tone' => l10n.gfpaLabelTone,
      'riff|control|feedback' => l10n.gfpaLabelFeedback,
      'riff|control|fb_harmonic' => l10n.gfpaRiffHarmonic,
      'riff|option|fb_harmonic.0' => l10n.gfpaRiffRoot,
      'riff|option|fb_harmonic.1' => l10n.intervalNameOctave,
      'riff|option|fb_harmonic.2' => l10n.gfpaRiffOctPlus5th,
      'riff|option|fb_harmonic.3' => l10n.gfpaRiff2Oct,
      'riff|control|sustain' => l10n.gfpaRiffSustain,
      'riff|control|pedal_sustain' => l10n.gfpaRiffPedalSus,
      'riff|control|level' => l10n.gfpaLabelLevel,
      'transposer|pluginName|' => l10n.rackAddTransposer,
      'transposer|group|pitch_shift' => l10n.gfpaTransposerPitchShift,
      'transposer|control|semitones' => l10n.gfpaTransposerSemitones,
      'velocity_curve|pluginName|' => l10n.rackAddVelocityCurve,
      'velocity_curve|group|curve_type' => l10n.gfpaVelocityCurveCurveType,
      'velocity_curve|group|intensity' => l10n.gfpaVelocityCurveIntensity,
      'velocity_curve|control|mode' => l10n.gfpaLabelMode,
      'velocity_curve|option|mode.0' => l10n.gfpaVelocityCurvePower,
      'velocity_curve|option|mode.1' => l10n.gfpaVelocityCurveSigmoid,
      'velocity_curve|option|mode.2' => l10n.gfpaVelocityCurveFixed,
      'velocity_curve|control|amount' => l10n.gfpaVelocityCurveAmount,
      'wah|pluginName|' => l10n.rackAddWah,
      'wah|group|filter' => l10n.gfpaWahFilter,
      'wah|group|sweep' => l10n.gfpaWahSweep,
      'wah|group|output' => l10n.gfpaLabelOutput,
      'wah|parameter|center' => l10n.gfpaWahCenter,
      'wah|parameter|resonance' => l10n.gfpaWahReso,
      'wah|parameter|depth' => l10n.gfpaLabelDepth,
      'wah|control|mode' => l10n.gfpaLabelMode,
      'wah|option|mode.0' => l10n.gfpaWahAuto,
      'wah|option|mode.1' => l10n.gfpaWahManual,
      'wah|parameter|pedal' => l10n.gfpaWahPedal,
      'wah|parameter|rate' => l10n.gfpaLabelRate,
      'wah|control|waveform' => l10n.gfpaWahWave,
      'wah|option|waveform.0' => l10n.gfpaWahSine,
      'wah|option|waveform.2' => l10n.gfpaWahSaw,
      'wah|option|beat_div.0' => l10n.drumGeneratorIntroCountIn2,
      'wah|option|beat_div.1' => l10n.drumGeneratorIntroCountIn1,
      'wah|parameter|mix' => l10n.gfpaLabelMix,
      _ => null,
  };
}
