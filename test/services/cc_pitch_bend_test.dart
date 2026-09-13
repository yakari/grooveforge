// Tests for pitch bend as a CC mapping target.
//
// Pitch bend rides in the GM CC picker under a pseudo-CC (128) rather than a
// target type of its own. Two things hold that up and are invisible when they
// break: the pseudo-code must stay outside the real CC range, because every
// other picker in the app enumerates 0..127 and would otherwise offer "pitch
// bend" as an aftertouch destination; and the 7-bit-to-14-bit conversion must
// put the detent exactly on centre, or a controller at rest sits out of tune.

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';

void main() {
  group('pitchBendTarget pseudo-CC', () {
    test('sits outside the real CC range', () {
      // preferences_screen, keyboard_config_dialog and the GM picker all
      // enumerate 0..127 or filter `key <= 127`. If this ever drops into
      // range, pitch bend silently appears in dropdowns that cannot send it.
      expect(CcMappingService.pitchBendTarget, greaterThan(127));
      // Below 1000, or CcMapping.fromLegacyString would migrate it into a
      // SystemTarget instead of a GmCcTarget.
      expect(CcMappingService.pitchBendTarget, lessThan(1000));
    });

    test('has a label, which both display sites look up', () {
      expect(
        CcMappingService.standardGmCcs[CcMappingService.pitchBendTarget],
        isNotNull,
      );
    });

    test('is recognised only by its own predicate', () {
      expect(
        CcMappingService.isPitchBendTarget(CcMappingService.pitchBendTarget),
        isTrue,
      );
      expect(CcMappingService.isPitchBendTarget(1), isFalse);
      expect(CcMappingService.isPitchBendTarget(74), isFalse);
      expect(CcMappingService.isLooperAction(CcMappingService.pitchBendTarget),
          isFalse);
      expect(CcMappingService.isMuteAction(CcMappingService.pitchBendTarget),
          isFalse);
    });
  });

  group('ccToPitchBend', () {
    test('lands the three detents exactly', () {
      expect(CcMappingService.ccToPitchBend(0), 0);
      expect(CcMappingService.ccToPitchBend(64), 8192);
      expect(CcMappingService.ccToPitchBend(127), 16383);
    });

    test('stays inside the 14-bit range for every CC value', () {
      for (int cc = 0; cc <= 127; cc++) {
        final bend = CcMappingService.ccToPitchBend(cc);
        expect(bend, inInclusiveRange(0, 16383), reason: 'cc $cc → $bend');
      }
    });

    test('is monotonic', () {
      int previous = -1;
      for (int cc = 0; cc <= 127; cc++) {
        final bend = CcMappingService.ccToPitchBend(cc);
        expect(bend, greaterThan(previous), reason: 'cc $cc → $bend');
        previous = bend;
      }
    });

    test('clamps values outside the 7-bit range', () {
      expect(CcMappingService.ccToPitchBend(-5), 0);
      expect(CcMappingService.ccToPitchBend(200), 16383);
    });
  });

  group('persistence', () {
    test('a pitch bend mapping survives a .gf JSON round-trip', () {
      const mapping = CcMapping(
        incomingCc: 1,
        target: GmCcTarget(
          targetCc: CcMappingService.pitchBendTarget,
          targetChannel: -2,
        ),
      );

      final restored = CcMapping.fromJson(mapping.toJson());

      expect(restored.incomingCc, 1);
      final target = restored.target as GmCcTarget;
      expect(target.targetCc, CcMappingService.pitchBendTarget);
      expect(target.targetChannel, -2);
    });

    test('legacy migration keeps it a GmCcTarget', () {
      final migrated = CcMapping.fromLegacyString(
          '1:${CcMappingService.pitchBendTarget}:-2');
      expect(migrated.target, isA<GmCcTarget>());
    });
  });
}
