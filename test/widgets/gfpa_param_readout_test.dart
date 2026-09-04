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
    expect(gfpaParamReadout(en, count, 3.0)!.value, '3');
    // Knobs and sliders are continuous, so a raw value between two counts
    // rounds to the one the DSP will actually use.
    expect(gfpaParamReadout(en, count, 2.6)!.value, '3');
  });

  test('an interval reads as a count plus the name of the interval', () {
    final r = gfpaParamReadout(en, interval, 7)!;
    expect(r.value, '+7 st');
    expect(r.detail, 'Perfect 5th');
  });

  test('interval names are spelled out, not abbreviated', () {
    // "m3" and "M3" differ only by letter case, which is the first thing to
    // stop being legible at 10 px.
    String name(double semis) => gfpaParamReadout(en, interval, semis)!.detail!;
    expect(name(0), 'Unison');
    expect(name(3), 'Minor 3rd');
    expect(name(4), 'Major 3rd');
    expect(name(6), 'Tritone');
    expect(name(7), 'Perfect 5th');
    expect(name(11), 'Major 7th');
  });

  test('the sign distinguishes a voice below from one above', () {
    expect(gfpaParamReadout(en, interval, -7)!.value, '-7 st');
    expect(gfpaParamReadout(en, interval, -7)!.detail, 'Perfect 5th');
    expect(gfpaParamReadout(en, interval, -5)!.value, '-5 st');
  });

  test('octaves and compound intervals are named by their simple form', () {
    String name(double semis) => gfpaParamReadout(en, interval, semis)!.detail!;
    expect(name(12), 'Octave');
    expect(name(14), 'Major 2nd +1 oct');
    expect(name(24), '2 octaves');
    expect(name(-12), 'Octave');
  });

  test('the tooltip says which way the voice goes', () {
    expect(gfpaParamReadout(en, interval, 7)!.tooltip,
        'Perfect 5th, 7 semitones above the played note');
    expect(gfpaParamReadout(en, interval, -7)!.tooltip,
        'Perfect 5th, 7 semitones below the played note');
    expect(gfpaParamReadout(en, interval, 0)!.tooltip,
        'Unison — the same pitch as the played note');
  });

  test('French names the intervals in French', () {
    expect(gfpaParamReadout(fr, interval, 7)!.detail, 'Quinte juste');
    expect(gfpaParamReadout(fr, interval, 4)!.detail, 'Tierce majeure');
    expect(gfpaParamReadout(fr, interval, 5)!.detail, 'Quarte juste');
    expect(gfpaParamReadout(fr, interval, 12)!.detail, 'Octave');
  });
}
