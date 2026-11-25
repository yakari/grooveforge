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

  test('the module starts off and leaves the keyboard alone', () async {
    // A new user's first notes must not be corrected by a module they never
    // switched on.
    await withDefaultRack((rack) async {
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      expect(xen.state['enabled'], isFalse);
      expect(rack.isXenActive(xen.id), isFalse);
      expect(rack.xenScaleLocksForTest, isEmpty);
    });
  });

  test('one tap on ON is enough to make it work', () async {
    // Snap and tune are ready, so switching the module on needs nothing else.
    await withDefaultRack((rack) async {
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      final plugin = rack.xenPluginFor(xen.id)!;
      expect(plugin.snapEnabled, isTrue);
      expect(plugin.tuneEnabled, isTrue);

      rack.setXenEnabled(xen.id, enabled: true);

      expect(rack.isXenActive(xen.id), isTrue);
      expect(rack.xenScaleLocksForTest, isNotEmpty);
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
      expect(restored.single.state['enabled'], isFalse);
    });
  });

  test('a saved project brings back the Xen settings, not the defaults',
      () async {
    // The default is only for a new project. Whatever the player set — on,
    // scale (and with it the family the panel opens on), root, snap, tune —
    // must come back exactly when the project is opened.
    // A scale outside the Western family, so the family is checked too. It
    // must be equal-tempered: a microtonal one would push a tuning table into
    // libaudio_input, which `flutter test` does not load.
    final scale = GFScaleFamily.values
        .where((f) => f != GFScaleFamily.western)
        .expand(GFScaleLibrary.byFamily)
        .firstWhere((s) => !s.isMicrotonal);

    late List<Map<String, dynamic>> saved;
    await withDefaultRack((rack) async {
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      rack.setXenEnabled(xen.id, enabled: true);
      rack.selectXenScale(xen.id, scale.id);
      rack.setXenRoot(xen.id, 7);
      rack.setXenSnapEnabled(xen.id, enabled: false);
      rack.setXenTuneEnabled(xen.id, enabled: false);
      saved = rack.toJson();
    });

    final reopened = RackState(AudioEngine(), TransportEngine(), AudioGraph());
    try {
      reopened.loadFromJson(saved);
      final xen = reopened.plugins.whereType<GFpaPluginInstance>().single;
      final plugin = reopened.xenPluginFor(xen.id)!;

      expect(reopened.isXenActive(xen.id), isTrue);
      expect(plugin.scale.id, scale.id);
      expect(plugin.scale.family, scale.family);
      expect(plugin.rootPc, 7);
      expect(plugin.snapEnabled, isFalse);
      expect(plugin.tuneEnabled, isFalse);
    } finally {
      reopened.dispose();
    }
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

  test('tapping a scale switches the module on', () async {
    // With Xen off by default, a scale tap that changed nothing audible
    // would look like a dead button.
    await withDefaultRack((rack) async {
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      rack.selectXenScale(xen.id, GFScaleLibrary.fallback.id);

      expect(rack.isXenActive(xen.id), isTrue);
      expect(rack.xenScaleLocksForTest, isNotEmpty);
    });
  });

  test('tapping a scale also lifts a CC bypass', () async {
    // Same meaning as the panel's ON button: choosing a scale means "work".
    await withDefaultRack((rack) async {
      final xen = rack.plugins.whereType<GFpaPluginInstance>().single;
      rack.setXenEnabled(xen.id, enabled: true);
      rack.toggleMidiFxBypass(xen.id);
      expect(rack.isXenActive(xen.id), isFalse);

      rack.selectXenScale(xen.id, GFScaleLibrary.fallback.id);

      expect(rack.isXenActive(xen.id), isTrue);
    });
  });
}
