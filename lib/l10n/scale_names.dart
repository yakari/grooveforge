// Localized names of the scales the engine derives from a chord.
//
// The engine (AudioEngine) has no BuildContext and names its scales in
// English, because those names are also matched in code. These helpers turn
// them into the player's language at the moment they are drawn.

import '../models/chord_detector.dart';
import '../services/audio_engine.dart';
import 'app_localizations.dart';

/// Short name of a scale type, as listed in the Jam Mode and channel menus
/// ("Pentatonic", "Harm. Minor"…).
String scaleTypeLabel(AppLocalizations l10n, ScaleType type) => switch (type) {
      ScaleType.standard => l10n.jamModeScaleTypeStandard,
      ScaleType.pentatonic => l10n.jamModeScaleTypePentatonic,
      ScaleType.blues => l10n.jamModeScaleTypeBlues,
      ScaleType.rock => l10n.jamModeScaleTypeRock,
      ScaleType.jazz => l10n.jamModeScaleTypeJazz,
      ScaleType.dorian => l10n.jamModeScaleTypeDorian,
      ScaleType.mixolydian => l10n.jamModeScaleTypeMixolydian,
      ScaleType.harmonicMinor => l10n.jamModeScaleTypeHarmonicMinor,
      ScaleType.melodicMinor => l10n.jamModeScaleTypeMelodicMinor,
      ScaleType.classical => l10n.jamModeScaleTypeClassical,
      ScaleType.asiatic => l10n.jamModeScaleTypeAsiatic,
      ScaleType.oriental => l10n.jamModeScaleTypeOriental,
      ScaleType.wholeTone => l10n.jamModeScaleTypeWholeTone,
      ScaleType.diminished => l10n.jamModeScaleTypeDiminished,
    };

/// The scale a channel plays over [chord] with scale type [type], named in
/// the player's language: "Mixolydian" over a G7 in jazz, "Minor Blues" over
/// Am in blues. Without a chord, the scale type's name in capitals, as the
/// engine shows it.
String descriptiveScaleName(
  AppLocalizations l10n,
  AudioEngine engine,
  ChordMatch? chord,
  ScaleType type,
) {
  if (chord == null) return scaleTypeLabel(l10n, type).toUpperCase();
  final english = engine.getDescriptiveScaleName(chord, type);
  return _scaleName(l10n, english) ?? english;
}

/// The translation of an English scale name from
/// `AudioEngine.getDescriptiveScaleName`, or null for a name not listed here
/// (the caller then shows the English one rather than nothing).
String? _scaleName(AppLocalizations l10n, String english) => switch (english) {
      'Standard' => l10n.scaleNameStandard,
      'Ionian' => l10n.scaleNameIonian,
      'Dorian' => l10n.scaleNameDorian,
      'Phrygian' => l10n.scaleNamePhrygian,
      'Lydian' => l10n.scaleNameLydian,
      'Mixolydian' => l10n.scaleNameMixolydian,
      'Aeolian' => l10n.scaleNameAeolian,
      'Locrian' => l10n.scaleNameLocrian,
      'Locrian #2' => l10n.scaleNameLocrianSharp2,
      'Lydian Dominant' => l10n.scaleNameLydianDominant,
      'Phrygian Dominant' => l10n.scaleNamePhrygianDominant,
      'Altered Scale' => l10n.scaleNameAltered,
      'Major' => l10n.scaleNameMajor,
      'Natural Major' => l10n.scaleNameNaturalMajor,
      'Harmonic Minor' => l10n.scaleNameHarmonicMinor,
      'Melodic Minor' => l10n.scaleNameMelodicMinor,
      'Major Pentatonic' => l10n.scaleNameMajorPentatonic,
      'Minor Pentatonic' => l10n.scaleNameMinorPentatonic,
      'Major Blues' => l10n.scaleNameMajorBlues,
      'Minor Blues' => l10n.scaleNameMinorBlues,
      'Rock Hexatonic' => l10n.scaleNameRockHexatonic,
      'Whole Tone' => l10n.scaleNameWholeTone,
      'Diminished' => l10n.scaleNameDiminished,
      _ => null,
    };
