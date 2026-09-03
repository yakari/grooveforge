// Tests for switching a Xen module off.
//
// Three symptoms, one shape: the module's own LED appeared dead, a mapped CC
// did nothing, and tapping the drag handle turned the module off. The last one
// was the clue — the state map was changing on the LED tap, but nothing told
// the widget tree, so the panel only caught up when some unrelated rebuild
// happened to repaint it.
//
// Underneath sat a second problem: two independent switches mean "off"
// (the panel's `enabled` and the generic MIDI FX `__bypass` a CC uses) and
// only one of them was consulted.

import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/cc_mapping_service.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';

Future<void> withDefaultRack(
  Future<void> Function(RackState rack, GFpaPluginInstance xen) body,
) async {
  final rack = RackState(AudioEngine(), TransportEngine(), AudioGraph());
  rack.initDefaults();
  final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
  try {
    await body(rack, xen);
  } finally {
    rack.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the LED turns the module off, and the engine hears about it', () async {
    await withDefaultRack((rack, xen) async {
      expect(rack.isXenActive(xen.id), isTrue);
      expect(rack.xenScaleLocksForTest, isNotEmpty);

      rack.setXenEnabled(xen.id, enabled: false);

      expect(rack.isXenActive(xen.id), isFalse);
      expect(rack.xenScaleLocksForTest, isEmpty,
          reason: 'a module reporting OFF must stop snapping');
    });
  });

  test('turning it off notifies the UI', () async {
    await withDefaultRack((rack, xen) async {
      var notifications = 0;
      rack.addListener(() => notifications++);
      rack.setXenEnabled(xen.id, enabled: false);
      // Without this the panel kept showing ON until an unrelated rebuild.
      expect(notifications, greaterThan(0));
    });
  });

  test('a generic state write notifies too', () async {
    await withDefaultRack((rack, xen) async {
      var notifications = 0;
      rack.addListener(() => notifications++);
      rack.setGfpaPluginState(xen.id, {...xen.state, 'rootPc': 5});
      expect(notifications, greaterThan(0));
    });
  });

  test('the bypass switch silences it as well', () async {
    await withDefaultRack((rack, xen) async {
      // What a mapped CC hits. It used to leave the module snapping while the
      // panel and the toast both said "bypassed".
      rack.toggleMidiFxBypass(xen.id);

      expect(rack.isXenActive(xen.id), isFalse);
      expect(rack.xenScaleLocksForTest, isEmpty);
    });
  });

  test('the panel reflects a bypass it did not set', () async {
    await withDefaultRack((rack, xen) async {
      rack.toggleMidiFxBypass(xen.id);
      // The LED must not claim to be on while a pad has bypassed the slot.
      expect(rack.isXenActive(xen.id), isFalse);
    });
  });

  test('turning it back on from the panel clears a CC bypass', () async {
    await withDefaultRack((rack, xen) async {
      rack.toggleMidiFxBypass(xen.id);
      expect(rack.isXenActive(xen.id), isFalse);

      // Pressing ON means "work". Leaving the bypass set would make the
      // button look broken a second time.
      rack.setXenEnabled(xen.id, enabled: true);
      expect(rack.isXenActive(xen.id), isTrue);
      expect(rack.xenScaleLocksForTest, isNotEmpty);
    });
  });

  test('the CC bypass mapping reaches the module', () async {
    await withDefaultRack((rack, xen) async {
      rack.handleSlotParamCc(xen.id, 'bypass', CcParamMode.toggle, 0);
      expect(rack.isXenActive(xen.id), isFalse);
    });
  });

  // Not covered here: that switching off also hands the target channel back
  // to equal temperament. Asserting it means first installing a real tuning,
  // which calls into libaudio_input — a library `flutter test` does not load.
  // `native_audio/gf_tuning_smoke_test.c` covers the clearing itself against a
  // real synth; what is missing is the wiring between the two, and it is
  // missing because a unit test cannot reach it, not because it is untested by
  // choice.
}
