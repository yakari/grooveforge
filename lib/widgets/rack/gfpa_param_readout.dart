import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

import '../../l10n/app_localizations.dart';

/// Localised readouts for the values printed under `.gfpd` plugin knobs.
///
/// The plugin UI package renders the controls but carries no translations,
/// so it asks the host for the text through
/// `GFDescriptorPluginUI.valueFormatter`. This file is that host side.
///
/// Only parameters that declared a `display:` style in their descriptor ever
/// reach here — everything else keeps the plain label-only knob.

/// Returns the readout for [param] at raw value [raw], or null to let the
/// plugin UI fall back to its own language-neutral formatting.
String? gfpaParamReadout(
  AppLocalizations l10n,
  GFDescriptorParameter param,
  double raw,
) {
  return switch (param.display) {
    GFParamDisplay.integer => raw.round().toString(),
    GFParamDisplay.interval => _intervalReadout(l10n, param, raw),
    GFParamDisplay.none => null,
  };
}

/// `+7 st · P5` — the semitone count with the interval it names.
///
/// The number alone is ambiguous to anyone who does not count semitones in
/// their head, and the name alone hides which direction the voice moves, so
/// the readout carries both. The sign is always explicit: a harmony a fifth
/// below reads `-7 st · P5`, not `7 st · P5`.
String _intervalReadout(
  AppLocalizations l10n,
  GFDescriptorParameter param,
  double raw,
) {
  final semis = raw.round();
  final sign = semis > 0 ? '+' : '';
  final name = _intervalName(l10n, semis.abs());
  return l10n.intervalReadout('$sign$semis', param.unit, name);
}

/// Names the interval spanning [semitones] (already made positive).
///
/// Intervals wider than an octave are named by their simple form plus the
/// octaves on top — a major ninth is "a major second an octave up" — which
/// is how musicians describe them and keeps the table to twelve entries.
String _intervalName(AppLocalizations l10n, int semitones) {
  final octaves = semitones ~/ 12;
  final remainder = semitones % 12;

  // Whole octaves have their own name; there is no "unison plus an octave".
  if (remainder == 0 && octaves > 0) {
    if (octaves == 1) return l10n.intervalOctave;
    return l10n.intervalOctaveMultiple(octaves, l10n.intervalOctave);
  }

  final base = _simpleIntervalName(l10n, remainder);
  if (octaves == 0) return base;
  if (octaves == 1) return l10n.intervalCompoundSingle(base, l10n.intervalOctave);
  return l10n.intervalCompound(base, octaves, l10n.intervalOctave);
}

/// The twelve interval names inside a single octave.
String _simpleIntervalName(AppLocalizations l10n, int semitones) {
  return switch (semitones) {
    0 => l10n.intervalUnison,
    1 => l10n.intervalMinor2,
    2 => l10n.intervalMajor2,
    3 => l10n.intervalMinor3,
    4 => l10n.intervalMajor3,
    5 => l10n.intervalPerfect4,
    6 => l10n.intervalTritone,
    7 => l10n.intervalPerfect5,
    8 => l10n.intervalMinor6,
    9 => l10n.intervalMajor6,
    10 => l10n.intervalMinor7,
    _ => l10n.intervalMajor7,
  };
}
