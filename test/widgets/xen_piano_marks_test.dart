// Tests for the microtonal markers on the virtual piano, and for the record
// that carries them from a Xen slot to the keyboard.
//
// The markers exist because a maqam borrows the key layout of the scale it
// sits on: rooted on C, maqam Rast uses exactly the white keys of C major.
// Without something drawn on the keys, the quarter-tones are audible but
// invisible — the hardest kind of state to reason about mid-performance. What
// is worth testing is therefore not the pixels but the routing: that a channel
// patched to one jack does not show the other jack's effect.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/widgets/virtual_piano.dart';

/// Maqam Rast on C — the third and seventh a quarter-tone flat.
const _rastMarks = {4: -50.0, 11: -50.0};

Future<void> pumpPiano(
  WidgetTester tester, {
  Set<int>? validPitchClasses,
  Map<int, double> centsOffsets = const {},
}) async {
  tester.view.physicalSize = const Size(1000, 400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: VirtualPiano(
            activeNotes: const {},
            validPitchClasses: validPitchClasses,
            centsOffsets: centsOffsets,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VirtualPiano cent markers', () {
    testWidgets('renders with markers and without', (tester) async {
      await pumpPiano(tester);
      expect(tester.takeException(), isNull);

      await pumpPiano(tester, centsOffsets: _rastMarks);
      expect(tester.takeException(), isNull);
      expect(find.byType(VirtualPiano), findsOneWidget);
    });

    testWidgets('markers are independent of the scale lock', (tester) async {
      // A keyboard patched only to Xen's tuningOut is retuned but not locked:
      // it must stay fully chromatic and still show the detuning.
      await pumpPiano(tester, centsOffsets: _rastMarks);
      final piano = tester.widget<VirtualPiano>(find.byType(VirtualPiano));
      expect(piano.validPitchClasses, isNull);
      expect(piano.centsOffsets, _rastMarks);
      expect(tester.takeException(), isNull);
    });

    testWidgets('defaults to no markers', (tester) async {
      await pumpPiano(tester);
      expect(
        tester.widget<VirtualPiano>(find.byType(VirtualPiano)).centsOffsets,
        isEmpty,
      );
    });

    testWidgets('survives a very wide key range', (tester) async {
      // Sub-cent deviations are dropped and whole-octave-spanning values are
      // clamped upstream; neither may throw during paint.
      await pumpPiano(tester, centsOffsets: const {
        0: 0.4,      // inaudible — must be skipped
        1: -23.951,  // meantone
        2: 140.0,    // a linear scale's stretch
        3: -0.0,
      });
      expect(tester.takeException(), isNull);
    });
  });

  group('XenChannelLock', () {
    test('carries the two halves of the module separately', () {
      // A scale cable with no tuning cable, and the reverse, are both normal
      // patches — the record must be able to express each on its own.
      const lockedOnly = XenChannelLock(
        allowedPitchClasses: {0, 2, 4, 5, 7, 9, 11},
        centsByPitchClass: {},
        rootPitchClass: 0,
      );
      const tunedOnly = XenChannelLock(
        allowedPitchClasses: {},
        centsByPitchClass: _rastMarks,
        rootPitchClass: 0,
      );

      expect(lockedOnly.allowedPitchClasses, isNotEmpty);
      expect(lockedOnly.centsByPitchClass, isEmpty);
      expect(tunedOnly.allowedPitchClasses, isEmpty);
      expect(tunedOnly.centsByPitchClass, isNotEmpty);
      expect(lockedOnly, isNot(tunedOnly));
    });

    test('compares by value so the notifier only fires on real changes', () {
      // ValueNotifier skips identical values; without a value comparison every
      // rack mutation would repaint every piano.
      const a = XenChannelLock(
        allowedPitchClasses: {0, 4, 7},
        centsByPitchClass: _rastMarks,
        rootPitchClass: 2,
      );
      const b = XenChannelLock(
        allowedPitchClasses: {7, 0, 4},
        centsByPitchClass: {11: -50.0, 4: -50.0},
        rootPitchClass: 2,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      const differentRoot = XenChannelLock(
        allowedPitchClasses: {0, 4, 7},
        centsByPitchClass: _rastMarks,
        rootPitchClass: 3,
      );
      expect(a, isNot(differentRoot));
    });
  });
}
