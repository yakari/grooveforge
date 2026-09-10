import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/rehearsal.dart';
import 'package:grooveforge/services/audio_route_service.dart';
import 'package:grooveforge/services/latency_calibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('calibration is device-wide', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      // One table for the whole app is right in an app and wrong across a
      // suite: without this each case would start on the previous one's
      // measurements.
      LatencyCalibration().resetForTests();
    });

    test('measuring in one tune answers for the next', () async {
      // The reported bug: calibrating a headset while one tune was open left
      // the next tune reporting that same headset as unknown, because the
      // table lived inside the rehearsal.
      final first = LatencyCalibration();
      await first.load();
      await first.record('bt:WH-1000XM4', 9600);

      final second = LatencyCalibration();
      await second.load();

      expect(second.hasRoute('bt:WH-1000XM4'), isTrue);
      expect(second.forRoute('bt:WH-1000XM4'), 9600);
    });

    test('each route keeps its own figure', () async {
      final c = LatencyCalibration();
      await c.load();
      await c.record('speaker', 1400);
      await c.record('bt:Buds', 12000);

      expect(c.forRoute('speaker'), 1400);
      expect(c.forRoute('bt:Buds'), 12000);
    });

    test('an unmeasured route falls back but is not called measured', () async {
      final c = LatencyCalibration();
      await c.load();
      await c.record('speaker', 1400);

      expect(c.forRoute('bt:Unknown'), 1400,
          reason: 'a close figure beats a whole round trip of error');
      expect(c.hasRoute('bt:Unknown'), isFalse,
          reason: 'which is what the warning on the tune screen reads');
    });

    test('a calibration from before routes existed is kept', () async {
      SharedPreferences.setMockInitialValues(
          {LatencyCalibration.legacyKey: 1390});
      final c = LatencyCalibration();
      await c.load();

      expect(c.forRoute('speaker'), 1390);
      expect(c.byRoute, isEmpty);
    });

    test('measurements stranded in a rehearsal are taken in', () async {
      // Rescues anything filed per-tune by the version that had this wrong.
      final c = LatencyCalibration();
      await c.load();
      await c.adoptFromRehearsal({'bt:Old': 8000}, 1400);

      expect(c.forRoute('bt:Old'), 8000);

      final reopened = LatencyCalibration();
      await reopened.load();
      expect(reopened.hasRoute('bt:Old'), isTrue, reason: 'and it persists');
    });

    test('a stale per-tune figure never overwrites the device table', () async {
      final c = LatencyCalibration();
      await c.load();
      await c.record('bt:Old', 9600);
      await c.adoptFromRehearsal({'bt:Old': 100}, 0);

      expect(c.forRoute('bt:Old'), 9600);
    });

    test('what the probe files is what the next take is armed with', () async {
      // The reported bug, and the reason there is one instance rather than
      // two. The probe screen filed a fresh measurement, the open tune went on
      // arming takes with what it had read when it opened, and the take came
      // out a quarter of a second early against a calibration that was right.
      // Re-reading fixed it only where somebody had remembered to ask, and the
      // path the guide recommends — Settings — never did.
      final engineSide = LatencyCalibration();
      await engineSide.load();

      final probeSide = LatencyCalibration();
      await probeSide.load();
      await probeSide.record('bt:New', 7777);

      expect(engineSide.forRoute('bt:New'), 7777,
          reason: 'no reload, no waiting for anyone to remember one');
      expect(engineSide.hasRoute('bt:New'), isTrue);
    });

    test('the table tells whoever is listening that it changed', () async {
      // What repaints the "not calibrated yet" warning on a tune screen when
      // the measurement was taken two screens away.
      final c = LatencyCalibration();
      await c.load();
      var beeps = 0;
      void listener() => beeps++;
      c.addListener(listener);
      addTearDown(() => c.removeListener(listener));

      await c.record('speaker', 1400);

      expect(beeps, greaterThan(0));
    });

    test('re-reading from disk still works, for a table changed underneath',
        () async {
      final c = LatencyCalibration();
      await c.load();
      await c.record('speaker', 1400);

      SharedPreferences.setMockInitialValues(
          {'flutter.${LatencyCalibration.tableKey}': '{"speaker":2500}'});
      await c.reload();

      expect(c.forRoute('speaker'), 2500);
    });
  });

  group('following the route', () {
    test('a change reaches the engine without anything being on screen', () {
      // It used to be pushed from a screen's build, which meant writing to a
      // notifier while another widget was building — and left the compensation
      // wrong whenever that screen had not rebuilt yet.
      final routes = AudioRouteService();
      var notified = 0;
      routes.addListener(() => notified++);

      routes.debugSetRoute(const AudioRoute(
          key: 'bt:WH-1000XM4', label: 'WH-1000XM4', kind: 'bluetooth'));

      expect(routes.route.key, 'bt:WH-1000XM4');
      expect(routes.route.isBluetooth, isTrue);
      expect(notified, 1);
    });

    test('setting the same route again says nothing', () {
      final routes = AudioRouteService();
      var notified = 0;
      routes.addListener(() => notified++);
      const same = AudioRoute(key: 'wired', label: 'Wired', kind: 'wired');

      routes.debugSetRoute(same);
      routes.debugSetRoute(same);

      expect(notified, 1, reason: 'a rebuild per audio callback is noise');
    });
  });
}
