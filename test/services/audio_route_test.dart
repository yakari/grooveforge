import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/rehearsal.dart';

void main() {
  group('compensation per route', () {
    test('a route that has been measured uses its own figure', () {
      final local = RehearsalLocalState(compensationFrames: 1400)
        ..compensationByRoute['bt:WH-1000XM4'] = 9600;

      expect(local.compensationFor('bt:WH-1000XM4'), 9600);
      expect(local.hasCompensationFor('bt:WH-1000XM4'), isTrue);
    });

    test('an unmeasured route falls back rather than to zero', () {
      // A wrong-but-close figure from another route beats no compensation at
      // all, which is a take a whole round trip behind the beat.
      final local = RehearsalLocalState(compensationFrames: 1400);

      expect(local.compensationFor('bt:Unknown'), 1400);
      expect(local.hasCompensationFor('bt:Unknown'), isFalse,
          reason: 'falling back is not the same as having been measured, and '
              'the difference is what the warning is for');
    });

    test('measuring one route leaves the others alone', () {
      // The bug this replaced: one stored number meant measuring with
      // headphones on overwrote the speaker figure, so whichever you measured
      // last was the only one that was right.
      final local = RehearsalLocalState()
        ..compensationByRoute['speaker'] = 1400
        ..compensationByRoute['bt:WH-1000XM4'] = 9600;

      expect(local.compensationFor('speaker'), 1400);
      expect(local.compensationFor('bt:WH-1000XM4'), 9600);
    });

    test('with no route known the single figure is used', () {
      // Desktop, where the platform does not report a route — and where the
      // output does not change under the app anyway.
      final local = RehearsalLocalState(compensationFrames: 700)
        ..compensationByRoute['speaker'] = 1400;

      expect(local.compensationFor(null), 700);
    });

    test('the table survives a save and reload', () {
      final saved = RehearsalLocalState(compensationFrames: 1400)
        ..compensationByRoute['bt:Buds'] = 12000;
      final back = RehearsalLocalState.fromJson(saved.toJson());

      expect(back.compensationFor('bt:Buds'), 12000);
      expect(back.compensationFor('speaker'), 1400);
    });

    test('a file written before routes existed still works', () {
      // Everything measured before this had one number and no route; it stays
      // the fallback for every route, which is what it always was.
      final old = RehearsalLocalState.fromJson({'compensationFrames': 1390});

      expect(old.compensationFor('bt:Anything'), 1390);
      expect(old.compensationByRoute, isEmpty);
    });
  });
}
