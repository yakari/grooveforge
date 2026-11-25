// Tests for the velocity of the on-screen keys.
//
// Every key used to play at velocity 100, so the keyboard could not play
// softly or loudly at all. The velocity now comes from where the finger lands
// on the key: near the front edge is loud, near the back is soft.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/widgets/virtual_piano.dart';

void main() {
  /// Pumps a piano and returns the velocities it reports, in press order.
  Future<List<int>> pumpPiano(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final velocities = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: VirtualPiano(
              activeNotes: const {},
              onNotePressed: (note, velocity) => velocities.add(velocity),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return velocities;
  }

  /// A point on the first white key, [fromTop] pixels below the top of the
  /// piano. The first white key is a C: its left half is clear of the black
  /// C# key, so the point hits the white key at any height.
  Offset onFirstWhiteKey(WidgetTester tester, double fromTop) {
    final rect = tester.getRect(find.byType(VirtualPiano));
    return Offset(rect.left + 8, rect.top + fromTop);
  }

  testWidgets('a touch near the front edge plays louder than near the back',
      (tester) async {
    final velocities = await pumpPiano(tester);
    // The keys stop 32 px above the bottom, where the scrollbar sits.
    final keyLength = tester.getRect(find.byType(VirtualPiano)).height - 32;

    await tester.tapAt(onFirstWhiteKey(tester, keyLength - 4));
    await tester.tapAt(onFirstWhiteKey(tester, 4));

    expect(velocities, hasLength(2));
    expect(velocities[0], greaterThan(120), reason: 'front edge: loud');
    expect(velocities[1], lessThan(50), reason: 'back of the key: soft');
    expect(velocities[1],
        greaterThanOrEqualTo(VirtualPiano.minTouchVelocity),
        reason: 'never so soft that the note cannot be heard');
  });
}
