import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/loop_track.dart';

void main() {
  // ── JSON round-trip ──────────────────────────────────────────────────────

  group('LoopTrack JSON round-trip', () {
    test('round-trips a fully populated track', () {
      final original = LoopTrack(
        id: 'track_42',
        lengthInBeats: 16.0,
        events: [
          const TimestampedMidiEvent(
            beatOffset: 0.0,
            status: 0x90,
            data1: 60,
            data2: 100,
          ),
          const TimestampedMidiEvent(
            beatOffset: 1.5,
            status: 0x80,
            data1: 60,
            data2: 0,
          ),
        ],
        muted: true,
        reversed: true,
        speed: LoopTrackSpeed.double_,
        quantize: LoopQuantize.eighth,
      );

      final json = original.toJson();
      final restored = LoopTrack.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.lengthInBeats, original.lengthInBeats);
      expect(restored.muted, original.muted);
      expect(restored.reversed, original.reversed);
      expect(restored.speed, original.speed);
      expect(restored.quantize, original.quantize);
      expect(restored.events.length, original.events.length);
      expect(restored.events[0].beatOffset, 0.0);
      expect(restored.events[0].status, 0x90);
      expect(restored.events[0].data1, 60);
      expect(restored.events[0].data2, 100);
      expect(restored.events[1].beatOffset, 1.5);
      expect(restored.events[1].status, 0x80);
    });

    test('round-trips a track with default values', () {
      final original = LoopTrack(id: 'track_default');

      final json = original.toJson();
      final restored = LoopTrack.fromJson(json);

      expect(restored.id, 'track_default');
      expect(restored.lengthInBeats, isNull);
      expect(restored.events, isEmpty);
      expect(restored.muted, false);
      expect(restored.reversed, false);
      expect(restored.speed, LoopTrackSpeed.normal);
      expect(restored.quantize, LoopQuantize.off);
    });

    test('toJson does not include chordPerBar', () {
      final track = LoopTrack(id: 'track_no_chord', lengthInBeats: 8.0);
      final json = track.toJson();

      expect(json.containsKey('chordPerBar'), isFalse);
    });
  });

  // ── Backward compatibility ──────────────────────────────────────────────

  group('Backward compatibility', () {
    test('fromJson silently drops legacy chordPerBar field', () {
      // Simulates a .gf project file saved before chord-detection removal.
      final legacyJson = <String, dynamic>{
        'id': 'track_old',
        'lengthInBeats': 16.0,
        'events': [
          {
            'beatOffset': 0.0,
            'status': 0x90,
            'data1': 60,
            'data2': 100,
          },
        ],
        'muted': false,
        'reversed': false,
        'speed': 'normal',
        'quantize': 'off',
        'chordPerBar': {
          '0': 'Cmaj7',
          '1': 'Am7',
          '2': null,
          '3': 'G',
        },
      };

      // Must not throw.
      final track = LoopTrack.fromJson(legacyJson);

      expect(track.id, 'track_old');
      expect(track.lengthInBeats, 16.0);
      expect(track.events.length, 1);
      expect(track.muted, false);
      expect(track.speed, LoopTrackSpeed.normal);
    });

    test('fromJson handles missing optional fields gracefully', () {
      // Minimal JSON — only required fields.
      final minimalJson = <String, dynamic>{
        'id': 'track_minimal',
        'events': <dynamic>[],
      };

      final track = LoopTrack.fromJson(minimalJson);

      expect(track.id, 'track_minimal');
      expect(track.lengthInBeats, isNull);
      expect(track.events, isEmpty);
      expect(track.muted, false);
      expect(track.reversed, false);
      expect(track.speed, LoopTrackSpeed.normal);
      expect(track.quantize, LoopQuantize.off);
    });
  });

  // ── barCount ────────────────────────────────────────────────────────────

  group('barCount', () {
    test('returns 0 when lengthInBeats is null', () {
      final track = LoopTrack(id: 't');
      expect(track.barCount(4), 0);
    });

    test('returns correct bar count for 4/4 time', () {
      final track = LoopTrack(id: 't', lengthInBeats: 16.0);
      expect(track.barCount(4), 4);
    });

    test('returns correct bar count for 3/4 time', () {
      final track = LoopTrack(id: 't', lengthInBeats: 12.0);
      expect(track.barCount(3), 4);
    });

    test('returns 1 for a single bar', () {
      final track = LoopTrack(id: 't', lengthInBeats: 4.0);
      expect(track.barCount(4), 1);
    });
  });
}
