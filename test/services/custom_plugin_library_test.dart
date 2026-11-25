// Tests for the user's own .gfpd plugins.
//
// Three things used to go wrong: loading an edited file kept the old version
// (the registry ignored a second plugin with the same id), the plugin was
// forgotten at the next launch, and a project that used it opened with a
// "Plugin not installed" slot. These tests use a MIDI FX plugin, which runs
// entirely in Dart, so the whole path can be driven without the native host.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge_plugin_api/grooveforge_plugin_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/services/audio_engine.dart';
import 'package:grooveforge/services/audio_graph.dart';
import 'package:grooveforge/services/custom_plugin_library.dart';
import 'package:grooveforge/services/rack_state.dart';
import 'package:grooveforge/services/transport_engine.dart';

const _id = 'org.example.shift';

/// A user plugin built from the bundled Transposer, under the user's own id,
/// with the given [name] (to tell two versions apart).
String userPlugin(String name, {String id = _id}) =>
    File('assets/plugins/transposer.gfpd')
        .readAsStringSync()
        .replaceFirst('id: "com.grooveforge.transposer"', 'id: "$id"')
        .replaceFirst('name: "Transposer"', 'name: "$name"');

/// Lets the fire-and-forget plugin initialisation finish.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

RackState newRack() => RackState(AudioEngine(), TransportEngine(), AudioGraph());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GFDescriptorLoader.registerBuiltinNodes();
    GFDescriptorLoader.registerBuiltinMidiNodes();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CustomPluginLibrary.instance.debugReset();
    GFPluginRegistry.instance.unregister(_id);
  });

  test('installing a new version replaces the old one', () async {
    final library = CustomPluginLibrary.instance;
    await library.install(userPlugin('Shift v1'));
    final second = await library.install(userPlugin('Shift v2'));

    expect(second.status, GfpdInstallStatus.installed);
    expect(GFPluginRegistry.instance.findById(_id)!.name, 'Shift v2');
    expect(library.plugins.map((p) => p.name), ['Shift v2']);
  });

  test('a file using a bundled id is refused', () async {
    final result = await CustomPluginLibrary.instance.install(
      userPlugin('Fake', id: 'com.grooveforge.transposer'),
    );
    expect(result.status, GfpdInstallStatus.reservedId);
    expect(CustomPluginLibrary.instance.plugins, isEmpty);
  });

  test('a file that is not a plugin is refused', () async {
    final result =
        await CustomPluginLibrary.instance.install('just: some yaml');
    expect(result.status, GfpdInstallStatus.invalid);
  });

  test('installed plugins come back at the next launch', () async {
    await CustomPluginLibrary.instance.install(userPlugin('Shift'));

    // A new launch: nothing registered, the library read back from storage.
    GFPluginRegistry.instance.unregister(_id);
    CustomPluginLibrary.instance.debugReset();
    await CustomPluginLibrary.instance.load();

    expect(GFPluginRegistry.instance.findById(_id)!.name, 'Shift');
    expect(CustomPluginLibrary.instance.plugins, hasLength(1));
  });

  test('slots in the rack switch to the new version', () async {
    await CustomPluginLibrary.instance.install(userPlugin('Shift v1'));
    final rack = newRack();
    rack.addPlugin(GFpaPluginInstance(id: 'fx', pluginId: _id));
    await settle();
    expect(rack.midiFxInstanceForSlot('fx')!.descriptor.name, 'Shift v1');

    await CustomPluginLibrary.instance.install(userPlugin('Shift v2'));
    rack.reloadDescriptorSlots(_id);
    await settle();

    expect(rack.midiFxInstanceForSlot('fx')!.descriptor.name, 'Shift v2');
    rack.dispose();
  });

  test('a project carries the plugins it uses', () async {
    await CustomPluginLibrary.instance.install(userPlugin('Shift'));
    final rack = newRack();
    rack.addPlugin(GFpaPluginInstance(id: 'fx', pluginId: _id));
    await settle();
    final saved = rack.toJson();
    rack.dispose();

    // Another machine: the plugin was never installed there.
    GFPluginRegistry.instance.unregister(_id);
    final other = newRack();
    other.loadFromJson(saved);
    await settle();

    expect(GFPluginRegistry.instance.findById(_id)?.name, 'Shift');
    expect(other.midiFxInstanceForSlot('fx'), isNotNull,
        reason: 'the slot must run, not show "Plugin not installed"');
    other.dispose();
  });

  test('a project cannot replace a bundled plugin', () async {
    final bundled = GFDescriptorLoader.parse(
      File('assets/plugins/transposer.gfpd').readAsStringSync(),
    )!;
    GFPluginRegistry.instance.register(GFMidiDescriptorPlugin(bundled));

    final rack = newRack();
    rack.loadFromJson([
      GFpaPluginInstance(
        id: 'fx',
        pluginId: 'com.grooveforge.transposer',
        descriptorSource: userPlugin('Impostor', id: 'com.grooveforge.transposer'),
      ).toJson(),
    ]);
    await settle();

    expect(GFPluginRegistry.instance.findById('com.grooveforge.transposer')!.name,
        'Transposer');
    rack.dispose();
  });
}
