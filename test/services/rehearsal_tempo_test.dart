import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/rehearsal.dart';
import 'package:grooveforge/services/rehearsal_tempo_cache.dart';

void main() {
  group('practice speed', () {
    test('a fresh rehearsal plays at its own tempo', () {
      final local = RehearsalLocalState();
      expect(local.practiceSpeed, 1.0);
      expect(local.effectiveBpm(120), 120);
    });

    test('slowing down lowers the effective tempo', () {
      final local = RehearsalLocalState()..practiceSpeed = 0.5;
      expect(local.effectiveBpm(120), 60);
    });

    test('it survives a save and reload, and never escapes its range', () {
      final saved = RehearsalLocalState()..practiceSpeed = 0.7;
      final back = RehearsalLocalState.fromJson(saved.toJson());
      expect(back.practiceSpeed, closeTo(0.7, 1e-9));

      // A hand-edited or corrupted file must not be able to ask for a tempo
      // the renderer would refuse, which would leave every track unloadable.
      final absurd =
          RehearsalLocalState.fromJson({'practiceSpeed': 12.0});
      expect(absurd.practiceSpeed, 1.0);
    });
  });

  group('calibrating against a recording', () {
    test('the recording does not move while its tempo is being measured', () {
      // The bug this replaced: nudging the tempo to line the beats up with the
      // music stretched the music, so the two could never meet — chase the
      // tempo and it runs away from you.
      final master = RehearsalMaster(
        fileName: 'm.wav',
        sourceName: 'song.mp3',
        frames: 480000,
        sampleRate: 48000,
        nativeBpm: 140,
      );
      final local = RehearsalLocalState();

      // Calibration moves both together, which is what "the recording is at
      // 142, not 140" means.
      master.nativeBpm = 142;
      final tuneBpm = 142.0;

      final ratio = master.nativeBpm / local.effectiveBpm(tuneBpm);
      expect(ratio, 1.0,
          reason: 'a recording being measured must not be stretched');
      expect(RehearsalTempoCache.needsRender(ratio), isFalse,
          reason: 'and so it must not be re-rendered either');
    });

    test('slowing down for practice does stretch it', () {
      // The other case entirely, and here stretching is the whole point.
      final master = RehearsalMaster(
        fileName: 'm.wav',
        sourceName: 'song.mp3',
        frames: 480000,
        sampleRate: 48000,
        nativeBpm: 140,
      );
      final local = RehearsalLocalState()..practiceSpeed = 0.5;

      final ratio = master.nativeBpm / local.effectiveBpm(140);
      expect(ratio, 2.0, reason: 'half speed is twice as long');
      expect(RehearsalTempoCache.needsRender(ratio), isTrue);
    });
  });

  group('the render cache', () {
    test('a tempo that has not moved renders nothing', () {
      // Passing audio through a vocoder is never quite lossless, so rendering
      // a file in order to play it back unaltered is worse than not doing it.
      expect(RehearsalTempoCache.needsRender(1.0), isFalse);
      expect(RehearsalTempoCache.needsRender(1.0000001), isFalse);
      expect(RehearsalTempoCache.needsRender(0.5), isTrue);
      expect(RehearsalTempoCache.needsRender(1.5), isTrue);
    });

    test('a rendered file is named for its ratio', () {
      // Without the ratio in the name a stale render is indistinguishable from
      // a current one, and the result is a track playing at the wrong length
      // against a correct grid — which sounds like a broken app, not a stale
      // cache.
      final half = RehearsalTempoCache.fileNameFor('p1-2.wav', 2.0);
      final slower = RehearsalTempoCache.fileNameFor('p1-2.wav', 1.5);
      expect(half, isNot(slower));
      expect(half, contains('p1-2.wav'));
    });
  });

  group('takes remember the tempo they were played at', () {
    RehearsalTake take({double bpm = 120}) => RehearsalTake(
          fileName: 'p1-1.wav',
          revision: 1,
          frames: 48000,
          sampleRate: 48000,
          compensationFrames: 0,
          recordedAt: DateTime(2026, 1, 1),
          recordedBpm: bpm,
        );

    test('the tempo travels with the take', () {
      final back = RehearsalTake.fromJson(take(bpm: 88).toJson());
      expect(back.recordedBpm, 88);
    });

    test('a take from before the field is marked as unknown', () {
      // Zero is the signal the library migration looks for. Defaulting to a
      // plausible tempo instead would silently mis-stretch every old take.
      final old = {
        'fileName': 'p1-1.wav',
        'revision': 1,
        'frames': 48000,
        'sampleRate': 48000,
        'compensationFrames': 0,
        'recordedAt': DateTime(2026, 1, 1).toIso8601String(),
      };
      expect(RehearsalTake.fromJson(old).recordedBpm, 0);
    });
  });
}
