// Tests for the localised readouts printed under `.gfpd` plugin knobs.
//
// A knob shows an angle, so the harmonizer's interval knobs print the
// interval they are set to. These tests pin the naming — including the
// sign, which is what tells a fifth above from a fifth below — and the
// French abbreviations, which order the quality after the degree (5J, not
// P5).

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

import 'package:grooveforge/l10n/app_localizations.dart';
import 'package:grooveforge/widgets/rack/gfpa_param_readout.dart';

void main() {
  /// An interval parameter shaped like the audio harmonizer's voice knobs.
  const interval = GFDescriptorParameter(
    id: 'voice1_semitones',
    paramId: 1,
    name: 'V1 Semis',
    min: -24,
    max: 24,
    defaultValue: 7,
    unit: 'st',
    display: GFParamDisplay.interval,
  );

  /// A plain count parameter.
  const count = GFDescriptorParameter(
    id: 'voice_count',
    paramId: 0,
    name: 'Voices',
    min: 1,
    max: 4,
    defaultValue: 2,
    display: GFParamDisplay.integer,
  );

  /// A parameter that opted out — most knobs in most plugins.
  const plain = GFDescriptorParameter(
    id: 'dry_wet',
    paramId: 9,
    name: 'Dry/Wet',
    min: 0,
    max: 1,
    defaultValue: 0.5,
  );

  late AppLocalizations en;
  late AppLocalizations fr;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    fr = await AppLocalizations.delegate.load(const Locale('fr'));
  });

  test('a parameter without a display style prints nothing', () {
    expect(gfpaParamReadout(en, plain, 0.5), isNull);
  });

  test('a count prints as a whole number', () {
    expect(gfpaParamReadout(en, count, 3.0), '3');
    // Knobs are continuous, so the raw value between two counts rounds to
    // the one the DSP will actually use.
    expect(gfpaParamReadout(en, count, 2.6), '3');
  });

  test('intervals inside an octave are named', () {
    expect(gfpaParamReadout(en, interval, 0), '0 st · U');
    expect(gfpaParamReadout(en, interval, 3), '+3 st · m3');
    expect(gfpaParamReadout(en, interval, 4), '+4 st · M3');
    expect(gfpaParamReadout(en, interval, 6), '+6 st · TT');
    expect(gfpaParamReadout(en, interval, 7), '+7 st · P5');
    expect(gfpaParamReadout(en, interval, 11), '+11 st · M7');
  });

  test('the sign distinguishes a voice below from one above', () {
    expect(gfpaParamReadout(en, interval, -7), '-7 st · P5');
    expect(gfpaParamReadout(en, interval, -5), '-5 st · P4');
  });

  test('octaves and compound intervals are named by their simple form', () {
    expect(gfpaParamReadout(en, interval, 12), '+12 st · 8ve');
    expect(gfpaParamReadout(en, interval, 14), '+14 st · M2+8ve');
    expect(gfpaParamReadout(en, interval, 24), '+24 st · 2×8ve');
    expect(gfpaParamReadout(en, interval, -12), '-12 st · 8ve');
  });

  test('French uses its own interval abbreviations', () {
    // French music theory writes the degree first: 5J for a perfect fifth,
    // 3M for a major third.
    expect(gfpaParamReadout(fr, interval, 7), '+7 st · 5J');
    expect(gfpaParamReadout(fr, interval, 4), '+4 st · 3M');
    expect(gfpaParamReadout(fr, interval, 5), '+5 st · 4J');
    expect(gfpaParamReadout(fr, interval, 12), '+12 st · 8J');
  });
}
