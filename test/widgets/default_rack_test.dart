// Tests for the factory rack layout.
//
// The default rack is the first thing a new user sees and the only one nobody
// chose, so what it teaches matters. It replaced a two-keyboard Jam Mode setup
// that demonstrated nothing until the user understood a master/follower
// relationship and enabled a module that started off.
//
// The one that would be easy to get wrong and hard to notice: patching only
// the scale cable. The rack would look complete, the module would work, and
// the first tap on a maqam would play back in equal temperament.

import 'package:flutter_test/flutter_test.dart';

import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/models/grooveforge_keyboard_plugin.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

/// Builds a fresh rack at factory defaults, then disposes it.
Future<void> withDefaultRack(Future<void> Function(RackState) body) async {
  final rack = RackState(AudioEngine(), TransportEngine(), AudioGraph());
  rack.initDefaults();
  try {
    await body(rack);
  } finally {
    rack.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('one keyboard and one Xen — nothing else to understand', () async {
    await withDefaultRack((rack) async {
      expect(rack.plugins.whereType<GrooveForgeKeyboardPlugin>(), hasLength(1));
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      expect(xen.pluginId, 'com.grooveforge.xen');
      expect(rack.plugins, hasLength(2));
    });
  });

  test('both cables are patched, not just the scale lock', () async {
    // With only scaleOut connected, tapping a maqam would sound equal-tempered
    // and the module would look broken on first use.
    await withDefaultRack((rack) async {
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      expect(xen.targetSlotIds, ['slot-0'], reason: 'scale lock');
      expect(xen.tuningTargetSlotIds, ['slot-0'], reason: 'retuning');
    });
  });

  test('the module starts enabled and constrains the keyboard', () async {
    await withDefaultRack((rack) async {
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      expect(xen.state['enabled'], isTrue);

      final plugin = rack.xenPluginFor(xen.id)!;
      expect(plugin.snapEnabled, isTrue);
      expect(plugin.tuneEnabled, isTrue);
      // The greyed keys are what explain the module on the first note.
      expect(plugin.validPitchClasses, {0, 2, 4, 5, 7, 9, 11});
    });
  });

  test('the engine is told about the lock', () async {
    await withDefaultRack((rack) async {
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      expect(rack.xenPluginFor(xen.id), isNotNull,
          reason: 'the live plugin must exist before the first frame');
    });
  });

  test('C major, so the keyboard behaves ordinarily until asked not to',
      () async {
    await withDefaultRack((rack) async {
      final plugin =
          rack.xenPluginFor(rack.plugins.whereType<GFpaPluginInstance>().single.id)!;
      expect(plugin.scale.id, GFScaleLibrary.fallback.id);
      expect(plugin.rootPc, 0);
      // Nothing is retuned yet: the tuning cable is patched and idle.
      expect(plugin.tuningTable, isNull);
    });
  });

  test('the default survives a save and reload', () async {
    await withDefaultRack((rack) async {
      final saved = rack.toJson();
      final restored = saved
          .where((j) => j['type'] == 'gfpa')
          .map(GFpaPluginInstance.fromJson)
          .where((p) => p.pluginId == 'com.grooveforge.xen')
          .toList();
      expect(restored, hasLength(1));
      expect(restored.single.targetSlotIds, ['slot-0']);
      expect(restored.single.tuningTargetSlotIds, ['slot-0']);
      expect(restored.single.state['enabled'], isTrue);
    });
  });

  test('Jam Mode is no longer in the default rack', () async {
    // Still available from the plugin sheet — just not the thing a new user
    // has to decipher before playing a note.
    await withDefaultRack((rack) async {
      expect(
        rack.plugins
            .whereType<GFpaPluginInstance>()
            .where((p) => p.pluginId == 'com.grooveforge.jammode'),
        isEmpty,
      );
    });
  });
}
