import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:grooveforge_plugin_ui/grooveforge_plugin_ui.dart';

import '../../l10n/app_localizations.dart';

/// Localised readouts for the values printed beside `.gfpd` plugin controls.
///
/// The plugin UI package renders the controls but carries no translations, so
/// it asks the host for the text through
/// `GFDescriptorPluginUI.valueFormatter`. This file is that host side.
///
/// Only parameters that declared a `display:` style in their descriptor ever
/// reach here — everything else keeps its plain, unlabelled control.

/// Returns the readout for [param] at raw value [raw], or null to let the
/// plugin UI fall back to its own language-neutral formatting.
GFParamReadout? gfpaParamReadout(
  AppLocalizations l10n,
  GFDescriptorParameter param,
  double raw,
) {
  return switch (param.display) {
    GFParamDisplay.integer => GFParamReadout(value: raw.round().toString()),
    GFParamDisplay.interval => _intervalReadout(l10n, param, raw),
    GFParamDisplay.none => null,
  };
}

/// The semitone count, the interval it names, and a full sentence for the
/// tooltip.
///
/// Three fields rather than one string because they are read at different
/// distances: the count is the number being adjusted, the name is what it
/// means musically, and the sentence is what someone reaches for when the
/// name alone did not settle it.
GFParamReadout _intervalReadout(
  AppLocalizations l10n,
  GFDescriptorParameter param,
  double raw,
) {
  final semis = raw.round();
  final sign = semis > 0 ? '+' : '';
  final name = _intervalName(l10n, semis.abs());

  return GFParamReadout(
    value: l10n.intervalSemitones('$sign$semis'),
    detail: name,
    tooltip: switch (semis.sign) {
      0 => l10n.intervalTooltipUnison,
      1 => l10n.intervalTooltipAbove(name, semis),
      _ => l10n.intervalTooltipBelow(name, semis.abs()),
    },
  );
}

/// Names the interval spanning [semitones] (already made positive).
///
/// Intervals wider than an octave are named by their simple form plus the
/// octaves on top — a major ninth is "a major second an octave up" — which is
/// how musicians describe them and keeps the table to twelve entries.
String _intervalName(AppLocalizations l10n, int semitones) {
  final octaves = semitones ~/ 12;
  final remainder = semitones % 12;

  // Whole octaves have their own name; there is no "unison plus an octave".
  if (remainder == 0 && octaves > 0) {
    if (octaves == 1) return l10n.intervalNameOctave;
    return l10n.intervalNameOctaves(octaves);
  }

  final base = _simpleIntervalName(l10n, remainder);
  if (octaves == 0) return base;
  return l10n.intervalNameCompound(base, octaves);
}

/// The twelve interval names inside a single octave.
String _simpleIntervalName(AppLocalizations l10n, int semitones) {
  return switch (semitones) {
    0 => l10n.intervalNameUnison,
    1 => l10n.intervalNameMinor2,
    2 => l10n.intervalNameMajor2,
    3 => l10n.intervalNameMinor3,
    4 => l10n.intervalNameMajor3,
    5 => l10n.intervalNamePerfect4,
    6 => l10n.intervalNameTritone,
    7 => l10n.intervalNamePerfect5,
    8 => l10n.intervalNameMinor6,
    9 => l10n.intervalNameMajor6,
    10 => l10n.intervalNameMinor7,
    _ => l10n.intervalNameMajor7,
  };
}
