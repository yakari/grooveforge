import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The FluidSynth level moved to a calibrated scale in 3.5 (reference 1.0,
/// max 2.0) from the old 0-10 knob whose 3.0 default clipped loud chords.
void main() {
  Future<double> restore(Map<String, Object> saved) async {
    SharedPreferences.setMockInitialValues(saved);
    final prefs = await SharedPreferences.getInstance();
    return AudioEngine.fluidSynthGainFromPrefs(prefs);
  }

  test('fresh install gets the calibrated reference', () async {
    expect(await restore({}), AudioEngine.kFluidSynthGainDefault);
  });

  test('old default 3.0 becomes the new default', () async {
    expect(await restore({'fluidsynth_gain': 3.0}), closeTo(1.0, 1e-9));
  });

  test('an old value keeps its position relative to the default', () async {
    expect(await restore({'fluidsynth_gain': 1.5}), closeTo(0.5, 1e-9));
  });

  test('an old loud value is capped at +6 dB', () async {
    expect(await restore({'fluidsynth_gain': 10.0}),
        AudioEngine.kFluidSynthGainMax);
  });

  test('a new-scale value wins over a leftover old one', () async {
    expect(
        await restore({'fluidsynth_level': 0.8, 'fluidsynth_gain': 9.0}),
        closeTo(0.8, 1e-9));
  });
}
