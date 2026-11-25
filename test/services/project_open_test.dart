// Tests for opening a project from inside the app.
//
// Opening a project replaces the rack, which disposes every audio-effect
// slot's live plugin. Only the MIDI FX were recreated: the audio effects were
// left to the splash screen, which only runs at startup. A project opened
// later loaded its Riff, Amp, Reverb… slots with no live plugin, so each sat
// on its loading spinner and made no sound.
//
// These tests go through ProjectService.loadProject with a real .gf file on
// disk — the path the Open Project menu takes — rather than calling the rack
// directly, so the step that was missing is the one under test.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/looper_engine.dart';
import 'package:grooveforge/services/project_service.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';

const _ampId = 'com.grooveforge.amp';

/// Everything [ProjectService.loadProject] needs, built the way the app
/// builds it.
class _App {
  final engine = AudioEngine();
  final transport = TransportEngine();
  final graph = AudioGraph();
  late final rack = RackState(engine, transport, graph);
  late final looper = LooperEngine(transport);
  final projects = ProjectService();

  /// Open [path] as the Open Project menu does.
  Future<void> open(String path) =>
      projects.loadProject(path, rack, engine, transport, graph, looper);

  void dispose() => rack.dispose();
}

/// Writes a minimal project holding [plugins] and returns its path.
Future<String> _writeProject(
  Directory dir,
  List<Map<String, dynamic>> plugins,
) async {
  final file = File('${dir.path}/project.gf');
  await file.writeAsString(jsonEncode({
    'version': '2.0.0',
    'plugins': plugins,
    'audioGraph': <String, dynamic>{},
  }));
  return file.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  // Loaded once: rootBundle reads hang the second test in a file.
  setUpAll(() async {
    for (final name in ['riff', 'amp']) {
      final yaml = await rootBundle.loadString('assets/plugins/$name.gfpd');
      final descriptor = GFDescriptorLoader.parse(yaml)!;
      GFPluginRegistry.instance.register(GFDescriptorPlugin(descriptor));
    }
  });

  setUp(() => tmp = Directory.systemTemp.createTempSync('gf_open_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('an opened project brings its Riff and Amp up, not a spinner',
      () async {
    final path = await _writeProject(tmp, [
      GFpaPluginInstance(id: 'riff', pluginId: kRiffPluginId, midiChannel: 2)
          .toJson(),
      GFpaPluginInstance(id: 'amp', pluginId: _ampId).toJson(),
    ]);

    final app = _App();
    try {
      await app.open(path);

      // The slot panel shows a spinner until both exist.
      for (final id in ['riff', 'amp']) {
        expect(app.rack.audioEffectInstanceForSlot(id), isNotNull,
            reason: '$id has no live plugin after Open Project');
        expect(app.rack.audioEffectParamNotifierForSlot(id), isNotNull,
            reason: '$id has no param notifier after Open Project');
      }
    } finally {
      app.dispose();
    }
  });

  test('opening over a rack that already had the slot recreates it',
      () async {
    // The case from the field: Riff added, project saved, new project, then
    // the saved one reopened. Loading disposes the old instance first, so a
    // slot that was live before the open must be live again after it.
    final riff =
        GFpaPluginInstance(id: 'riff', pluginId: kRiffPluginId, midiChannel: 2);
    final path = await _writeProject(tmp, [riff.toJson()]);

    final app = _App();
    try {
      app.rack.addPlugin(riff);
      await Future<void>.delayed(Duration.zero);
      final before = app.rack.audioEffectInstanceForSlot('riff');
      expect(before, isNotNull);

      await app.open(path);

      final after = app.rack.audioEffectInstanceForSlot('riff');
      expect(after, isNotNull);
      expect(identical(after, before), isFalse,
          reason: 'the instance from before the open was disposed');
    } finally {
      app.dispose();
    }
  });

  test('saved knob values come back with the slot', () async {
    final path = await _writeProject(tmp, [
      GFpaPluginInstance(
        id: 'riff',
        pluginId: kRiffPluginId,
        midiChannel: 2,
        state: {'palm_mute': 0.75},
      ).toJson(),
    ]);

    final app = _App();
    try {
      await app.open(path);
      final plugin = app.rack.audioEffectInstanceForSlot('riff')!;
      final palmMute = plugin.descriptor.parameters
          .firstWhere((p) => p.id == 'palm_mute');
      expect(plugin.getParameter(palmMute.paramId), closeTo(0.75, 1e-9));
    } finally {
      app.dispose();
    }
  });
}
