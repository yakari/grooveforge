// Tests for Xen's rack-level wiring: the back-panel ports, the persistence of
// its two independent target lists, and the CC mapping that lets a pad bank
// recall a scale.
//
// These are the pieces that decide whether a patch survives being saved and
// reopened, and whether a hardware pad still points at the right scale after
// the rack has been rearranged — both invisible until they go wrong.

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/audio_port_id.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/cc_param_registry.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

void main() {
  group('tuning ports', () {
    test('tuningOut connects only to tuningIn', () {
      expect(
        AudioPortId.tuningOut.compatibleWith(AudioPortId.tuningIn),
        isTrue,
      );
      // Must not be interchangeable with Jam Mode's scale cable: locking a
      // keyboard and retuning it are different acts on different jacks.
      expect(
        AudioPortId.tuningOut.compatibleWith(AudioPortId.scaleIn),
        isFalse,
      );
      expect(
        AudioPortId.scaleOut.compatibleWith(AudioPortId.tuningIn),
        isFalse,
      );
    });

    test('direction and family are declared consistently', () {
      expect(AudioPortId.tuningOut.isOutput, isTrue);
      expect(AudioPortId.tuningIn.isInput, isTrue);
      // Data-family membership is what keeps AudioGraph from storing these as
      // audio cables — RackState owns them instead.
      expect(AudioPortId.tuningOut.isDataPort, isTrue);
      expect(AudioPortId.tuningIn.isDataPort, isTrue);
      expect(AudioPortId.tuningOut.isTuningPort, isTrue);
      expect(AudioPortId.scaleOut.isTuningPort, isFalse);
    });

    test('an input port is never a valid cable source', () {
      expect(AudioPortId.tuningIn.compatibleWith(AudioPortId.tuningOut),
          isFalse);
    });

    test('tuning jacks are visually distinct from the data jacks', () {
      expect(AudioPortId.tuningOut.color, isNot(AudioPortId.scaleOut.color));
      expect(AudioPortId.tuningOut.color, AudioPortId.tuningIn.color);
    });
  });

  group('slot persistence', () {
    test('the two target lists round-trip independently', () {
      final slot = GFpaPluginInstance(
        id: 'slot-3',
        pluginId: 'com.grooveforge.xen',
        targetSlotIds: ['slot-0'],
        tuningTargetSlotIds: ['slot-0', 'slot-1'],
        state: {'scaleId': 'maqamRast', 'rootPc': 2},
      );

      final restored = GFpaPluginInstance.fromJson(slot.toJson());
      expect(restored.targetSlotIds, ['slot-0']);
      expect(restored.tuningTargetSlotIds, ['slot-0', 'slot-1']);
      expect(restored.state['scaleId'], 'maqamRast');
      expect(restored.state['rootPc'], 2);
    });

    test('a project saved before Xen existed loads with no tuning targets', () {
      // The key is simply absent in older files; an empty list is the correct
      // reading, not a parse failure.
      final restored = GFpaPluginInstance.fromJson({
        'id': 'slot-1',
        'type': 'gfpa',
        'pluginId': 'com.grooveforge.jammode',
        'midiChannel': 0,
        'targetSlotIds': ['slot-0'],
      });
      expect(restored.tuningTargetSlotIds, isEmpty);
    });

    test('copyWith carries the tuning targets', () {
      final slot = GFpaPluginInstance(
        id: 'slot-3',
        pluginId: 'com.grooveforge.xen',
        tuningTargetSlotIds: ['slot-0'],
      );
      expect(slot.copyWith(midiChannel: 2).tuningTargetSlotIds, ['slot-0']);
    });

    test('the slot is named Xen in the rack', () {
      final slot = GFpaPluginInstance(
        id: 'slot-3',
        pluginId: 'com.grooveforge.xen',
      );
      expect(slot.displayName, 'Xen');
    });
  });

  group('CC mapping — pad bank', () {
    test('a direct mapping round-trips with its recalled value', () {
      const mapping = CcMapping(
        incomingCc: 36,
        target: SlotParamTarget(
          slotId: 'slot-3',
          paramKey: 'scale',
          mode: CcParamMode.direct,
          directValue: 'maqamRast',
        ),
      );

      final restored = CcMapping.fromJson(mapping.toJson());
      final target = restored.target as SlotParamTarget;
      expect(target.mode, CcParamMode.direct);
      expect(target.directValue, 'maqamRast');
    });

    test('non-direct mappings stay free of the new field', () {
      const mapping = CcMapping(
        incomingCc: 40,
        target: SlotParamTarget(
          slotId: 'slot-3',
          paramKey: 'snap',
          mode: CcParamMode.toggle,
        ),
      );
      expect(mapping.toJson()['target'], isNot(contains('directValue')));
      final restored =
          CcMapping.fromJson(mapping.toJson()).target as SlotParamTarget;
      expect(restored.directValue, isNull);
    });

    test('swapping slots keeps the recalled value', () {
      // Losing directValue here would turn a "recall Rast" pad into a pad that
      // silently does nothing — and only after a rack rearrangement, which is
      // the worst possible time to discover it.
      final service = CcMappingService();
      service.mappingsNotifier.value = const [
        CcMapping(
          incomingCc: 36,
          target: SlotParamTarget(
            slotId: 'slot-3',
            paramKey: 'scale',
            mode: CcParamMode.direct,
            directValue: 'ragaYaman',
          ),
        ),
      ];

      service.swapSlotReferences('slot-3', 'slot-7');

      final target =
          service.mappingsNotifier.value.single.target as SlotParamTarget;
      expect(target.slotId, 'slot-7');
      expect(target.directValue, 'ragaYaman');
    });

    test('the scale choices cover the whole catalogue and use stable ids', () {
      final choices = CcParamRegistry.xenScaleChoices();
      expect(choices.length, GFScaleLibrary.all.length);
      for (final choice in choices) {
        expect(GFScaleLibrary.byId(choice.value), isNotNull,
            reason: '${choice.value} must resolve to a real scale');
        expect(choice.label, isNotEmpty);
      }
    });

    test('root choices cover the twelve tonics', () {
      final values = CcParamRegistry.xenRootChoices()
          .map((c) => int.parse(c.value))
          .toList();
      expect(values, List.generate(12, (i) => i));
    });

    test('the registry exposes the pad-bank parameters', () {
      final params = CcParamRegistry.forPluginId('com.grooveforge.xen');
      expect(params, isNotNull);
      final keys = params!.map((p) => p.paramKey).toSet();
      // "snap" is the one the player asked for by name: dropping the lock
      // mid-solo without touching the intonation.
      expect(keys, containsAll(['scale', 'root', 'snap', 'tune', 'next_scale']));

      final scale = CcParamRegistry.findParam('com.grooveforge.xen', 'scale')!;
      expect(scale.defaultMode, CcParamMode.direct);
      expect(scale.directChoices, isNotNull);

      final snap = CcParamRegistry.findParam('com.grooveforge.xen', 'snap')!;
      expect(snap.defaultMode, CcParamMode.toggle);
      expect(snap.directChoices, isNull);
    });
  });
}
