// Tests for the derivation of virtual data cables in the patch view.
//
// Data cables are not stored in the audio graph — they are re-derived from
// each module's routing fields on every build. That makes one failure mode
// very easy to hit and very hard to notice in review: a module left out of the
// derivation patches correctly, sounds correctly, and draws nothing. The patch
// view then denies a connection that is plainly in effect, which is exactly
// what happened to Xen when the derivation filtered on Jam Mode alone.

import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/models/audio_port_id.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/models/plugin_instance.dart';
import 'package:grooveforge/widgets/patch_cable_overlay.dart';

GFpaPluginInstance _module(
  String id,
  String pluginId, {
  String? master,
  List<String> targets = const [],
  List<String> tuningTargets = const [],
}) =>
    GFpaPluginInstance(
      id: id,
      pluginId: pluginId,
      masterSlotId: master,
      targetSlotIds: List.of(targets),
      tuningTargetSlotIds: List.of(tuningTargets),
    );

void main() {
  group('Xen cables', () {
    test('a scale cable is drawn from a Xen slot', () {
      final cables = deriveDataCables(<PluginInstance>[
        _module('slot-xen', 'com.grooveforge.xen', targets: ['slot-kb']),
      ]);

      expect(cables, hasLength(1));
      expect(cables.single.fromPort, AudioPortId.scaleOut);
      expect(cables.single.toPort, AudioPortId.scaleIn);
      expect(cables.single.fromSlotId, 'slot-xen');
      expect(cables.single.toSlotId, 'slot-kb');
    });

    test('a tuning cable is drawn, separately from the scale cable', () {
      final cables = deriveDataCables(<PluginInstance>[
        _module('slot-xen', 'com.grooveforge.xen',
            targets: ['slot-kb'], tuningTargets: ['slot-kb']),
      ]);

      // Two cables to the same slot: that is the point of the two jacks.
      expect(cables, hasLength(2));
      expect(
        cables.map((c) => c.fromPort),
        containsAll([AudioPortId.scaleOut, AudioPortId.tuningOut]),
      );
    });

    test('a tuning cable can exist without a scale cable', () {
      // Retuning a keyboard without locking it is a normal patch.
      final cables = deriveDataCables(<PluginInstance>[
        _module('slot-xen', 'com.grooveforge.xen', tuningTargets: ['slot-kb']),
      ]);
      expect(cables, hasLength(1));
      expect(cables.single.fromPort, AudioPortId.tuningOut);
    });

    test('a chord cable is drawn into a Xen slot', () {
      final cables = deriveDataCables(<PluginInstance>[
        _module('slot-xen', 'com.grooveforge.xen', master: 'slot-kb'),
      ]);
      expect(cables.single.fromPort, AudioPortId.chordOut);
      expect(cables.single.fromSlotId, 'slot-kb');
      expect(cables.single.toSlotId, 'slot-xen');
    });

    test('the tuning cable wears the tuning jack colour', () {
      final cables = deriveDataCables(<PluginInstance>[
        _module('slot-xen', 'com.grooveforge.xen',
            targets: ['slot-kb'], tuningTargets: ['slot-kb']),
      ]);
      final scale =
          cables.firstWhere((c) => c.fromPort == AudioPortId.scaleOut);
      final tuning =
          cables.firstWhere((c) => c.fromPort == AudioPortId.tuningOut);
      // The two cables must be told apart on screen at a glance.
      expect(tuning.color, isNot(scale.color));
      expect(tuning.color, AudioPortId.tuningOut.color);
    });
  });

  group('Jam Mode cables still derive', () {
    test('chord and scale cables are unaffected by the Xen addition', () {
      final cables = deriveDataCables(<PluginInstance>[
        _module('slot-jam', 'com.grooveforge.jammode',
            master: 'slot-a', targets: ['slot-b', 'slot-c']),
      ]);
      expect(cables, hasLength(3));
      expect(
        cables.where((c) => c.fromPort == AudioPortId.scaleOut).length,
        2,
      );
    });

    test('both modules can route at once', () {
      final cables = deriveDataCables(<PluginInstance>[
        _module('slot-jam', 'com.grooveforge.jammode', targets: ['slot-a']),
        _module('slot-xen', 'com.grooveforge.xen',
            targets: ['slot-b'], tuningTargets: ['slot-b']),
      ]);
      expect(cables, hasLength(3));
    });
  });

  group('non-routing slots', () {
    test('a module without routing jacks derives nothing', () {
      final cables = deriveDataCables(<PluginInstance>[
        _module('slot-arp', 'com.grooveforge.arpeggiator', targets: ['slot-a']),
      ]);
      expect(cables, isEmpty,
          reason: 'targetSlotIds on a MIDI FX slot is not a data cable');
    });

    test('an empty rack derives nothing', () {
      expect(deriveDataCables(const <PluginInstance>[]), isEmpty);
    });
  });

  group('cable identity', () {
    test('compares by value so the painter can skip identical repaints', () {
      // Without this the derivation's fresh list was never equal to the
      // previous one, so the patch view repainted in a loop: painting
      // schedules a setState to reposition the disconnect badges, which
      // rebuilds, which re-derives, which repaints.
      final rack = <PluginInstance>[
        _module('slot-xen', 'com.grooveforge.xen', targets: ['slot-kb']),
      ];
      expect(deriveDataCables(rack), deriveDataCables(rack));
    });

    test('differs once the patch changes', () {
      final before = deriveDataCables(<PluginInstance>[
        _module('slot-xen', 'com.grooveforge.xen', targets: ['slot-kb']),
      ]);
      final after = deriveDataCables(<PluginInstance>[
        _module('slot-xen', 'com.grooveforge.xen',
            targets: ['slot-kb'], tuningTargets: ['slot-kb']),
      ]);
      expect(before, isNot(after));
    });
  });

  test('an Audio Harmonizer with a chord patched in draws its cable', () {
    // The failure this guards: the chord source was first stored in a map
    // inside RackState, which deriveDataCables cannot see. The drop was
    // accepted, the harmony followed the chord — and the cable vanished the
    // moment the finger lifted, so the patch view denied a connection that
    // was plainly in effect.
    final cables = deriveDataCables([
      GFpaPluginInstance(
        id: 'harm-1',
        pluginId: 'com.grooveforge.audio_harmonizer',
        midiChannel: 1,
        masterSlotId: 'kbd-1',
      ),
    ]);

    expect(cables.map((c) => c.id), contains('kbd-1:chordOut>harm-1:chordIn'));
  });

  test('an Audio Harmonizer with nothing patched draws no chord cable', () {
    final cables = deriveDataCables([
      GFpaPluginInstance(
        id: 'harm-1',
        pluginId: 'com.grooveforge.audio_harmonizer',
        midiChannel: 1,
      ),
    ]);
    expect(cables, isEmpty);
  });
}
