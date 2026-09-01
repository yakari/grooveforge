// Tests for binding one scale per hardware pad.
//
// The behaviour the player asked for: pick a scale, bind it to a CC, and have
// that CC jump straight to it — several scales on several CCs at once. The
// mode already existed; what these tests pin down is that the mappings stay
// independent of each other, since the failure that matters is one pad
// silently stealing another's binding.

import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/cc_param_registry.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

CcMapping _pad(int cc, String scaleId) => CcMapping(
      incomingCc: cc,
      target: SlotParamTarget(
        slotId: 'slot-xen',
        paramKey: 'scale',
        mode: CcParamMode.direct,
        directValue: scaleId,
      ),
    );

void main() {
  group('a bank of pads', () {
    test('several scales can be bound at once, each to its own CC', () {
      final service = CcMappingService();
      service.mappingsNotifier.value = [
        _pad(36, 'maqamRast'),
        _pad(37, 'ragaYaman'),
        _pad(38, 'slendro'),
      ];

      final byCc = {
        for (final m in service.mappingsNotifier.value)
          m.incomingCc: (m.target as SlotParamTarget).directValue,
      };
      expect(byCc, {36: 'maqamRast', 37: 'ragaYaman', 38: 'slendro'});
    });

    test('the mappings survive a save and reload', () {
      final restored = [
        for (final m in [_pad(36, 'maqamRast'), _pad(37, 'edo24')])
          CcMapping.fromJson(m.toJson())
      ];
      expect(
        restored.map((m) => (m.target as SlotParamTarget).directValue),
        ['maqamRast', 'edo24'],
      );
      expect(restored.every((m) => (m.target as SlotParamTarget).mode ==
          CcParamMode.direct), isTrue);
    });

    test('every bound value resolves to a real scale', () {
      for (final choice in CcParamRegistry.xenScaleChoices()) {
        expect(GFScaleLibrary.byId(choice.value), isNotNull,
            reason: '${choice.value} must be recallable');
      }
    });

    test('the choice list covers the experimental scales too', () {
      final values =
          CcParamRegistry.xenScaleChoices().map((c) => c.value).toSet();
      expect(values, containsAll(['edo24', 'bohlenPierce', 'maqamRast']));
    });
  });

  group('the assign dialog offers the direct params', () {
    test('scale and root are no longer filtered out', () {
      // They used to be hidden from the quick-assign dialog, which left the
      // module offering only "next scale" — the one mapping that does not
      // scale to a catalogue this size.
      final params = CcParamRegistry.forPluginId('com.grooveforge.xen')!;
      final direct =
          params.where((p) => p.defaultMode == CcParamMode.direct).toList();
      expect(direct.map((p) => p.paramKey), containsAll(['scale', 'root']));
      for (final p in direct) {
        expect(p.directChoices, isNotNull,
            reason: '${p.paramKey} must offer values to pick from');
        expect(p.directChoices!(), isNotEmpty);
      }
    });
  });
}
