// Tests for turning the Autotune's native readouts into what its panel shows.

import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/models/autotune_pitch.dart';

void main() {
  group('AutotunePitch.fromReadouts', () {
    test('negative notes mean nothing is heard', () {
      final p = AutotunePitch.fromReadouts(
          inputNote: -1, targetNote: -1, correction: 0);
      expect(p.isVoiced, isFalse);
      expect(p.centsOffTarget, isNull);
    });

    test('missing readouts (no native DSP) read as silence', () {
      final p = AutotunePitch.fromReadouts(
          inputNote: null, targetNote: null, correction: null);
      expect(p, AutotunePitch.silent);
    });

    test('a sharp note reports positive cents towards its target', () {
      final p = AutotunePitch.fromReadouts(
          inputNote: 57.3, targetNote: 57, correction: -0.3);
      expect(p.isVoiced, isTrue);
      expect(p.targetNote, 57);
      expect(p.centsOffTarget, 30);
    });

    test('a flat note reports negative cents', () {
      final p = AutotunePitch.fromReadouts(
          inputNote: 56.8, targetNote: 57, correction: 0.2);
      expect(p.centsOffTarget, -20);
    });
  });

  group('autotuneNoteName', () {
    test('letter names put middle C in octave 4', () {
      expect(autotuneNoteName(60), 'C4');
      expect(autotuneNoteName(57), 'A3');
      expect(autotuneNoteName(69), 'A4');
      expect(autotuneNoteName(61), 'C#4');
    });

    test('solfège puts middle C in octave 3, as French readers expect', () {
      expect(autotuneNoteName(60, solfege: true), 'Do3');
      expect(autotuneNoteName(69, solfege: true), 'La3');
      expect(autotuneNoteName(62, solfege: true), 'Ré3');
    });
  });

  test('both scale-following audio effects get a SCALE IN jack', () {
    expect(kScaleFollowingAudioEffects, contains(kAutotunePluginId));
    expect(kScaleFollowingAudioEffects,
        contains('com.grooveforge.audio_harmonizer'));
  });
}
