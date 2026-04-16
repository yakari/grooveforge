// ============================================================================
// Tests for the [AudioSourcePlugin] mixin on every plugin class.
//
// Phase B contract: every plugin class that can produce audio
// implements [AudioSourcePlugin.describeAudioSource] and returns the
// expected descriptor. If any of these tests fails after a future
// refactor, the routing plan builder will silently drop that source
// type on every backend — the unit test is the early warning.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/audio/audio_source_descriptor.dart';
import 'package:grooveforge/models/audio_looper_plugin_instance.dart';
import 'package:grooveforge/models/drum_generator_plugin_instance.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/models/grooveforge_keyboard_plugin.dart';
import 'package:grooveforge/models/live_input_source_plugin_instance.dart';
import 'package:grooveforge/models/vst3_plugin_instance.dart';

void main() {
  group('GrooveForgeKeyboardPlugin', () {
    test('describes itself as a gfKeyboard source with its MIDI channel',
        () {
      final kb = GrooveForgeKeyboardPlugin(
        id: 'kb-1',
        midiChannel: 3,
        soundfontPath: null,
      );
      final descriptor = kb.describeAudioSource();
      expect(descriptor.kind, AudioSourceKind.gfKeyboard);
      expect(descriptor.midiChannel, 3);
    });
  });

  group('DrumGeneratorPluginInstance', () {
    test('describes itself as a drumGenerator source', () {
      final drums = DrumGeneratorPluginInstance(
        id: 'dg-1',
        midiChannel: 10,
        builtinPatternId: 'rock_basic',
      );
      expect(
        drums.describeAudioSource().kind,
        AudioSourceKind.drumGenerator,
      );
    });
  });

  group('LiveInputSourcePluginInstance', () {
    test('describes itself as a liveInput source', () {
      final li = LiveInputSourcePluginInstance(id: 'li-1');
      expect(
        li.describeAudioSource().kind,
        AudioSourceKind.liveInput,
      );
    });
  });

  group('GFpaPluginInstance', () {
    // Three GFPA instruments count as sources.
    test('theremin → theremin source', () {
      final p = GFpaPluginInstance(
        id: 'gfpa-th',
        pluginId: 'com.grooveforge.theremin',
        midiChannel: 1,
      );
      expect(p.describeAudioSource()?.kind, AudioSourceKind.theremin);
    });

    test('stylophone → stylophone source', () {
      final p = GFpaPluginInstance(
        id: 'gfpa-st',
        pluginId: 'com.grooveforge.stylophone',
        midiChannel: 1,
      );
      expect(p.describeAudioSource()?.kind, AudioSourceKind.stylophone);
    });

    test('vocoder → vocoder source', () {
      final p = GFpaPluginInstance(
        id: 'gfpa-vc',
        pluginId: 'com.grooveforge.vocoder',
        midiChannel: 1,
      );
      expect(p.describeAudioSource()?.kind, AudioSourceKind.vocoder);
    });

    // Every other GFPA plugin is a pure effect or MIDI FX and must
    // return null so the plan builder does not mistake it for a
    // source. These are the cases that regressed in v2.13.0 when a
    // new source type was added and the hardcoded list fell out of
    // sync with reality.
    const effectIds = [
      'com.grooveforge.reverb',
      'com.grooveforge.delay',
      'com.grooveforge.wah',
      'com.grooveforge.eq',
      'com.grooveforge.compressor',
      'com.grooveforge.chorus',
      'com.grooveforge.audio_harmonizer',
      'com.grooveforge.jammode',
      'com.grooveforge.unknown_plugin',
    ];
    for (final id in effectIds) {
      test('$id → null (not a source)', () {
        final p = GFpaPluginInstance(
          id: 'gfpa-$id',
          pluginId: id,
          midiChannel: 0,
        );
        expect(p.describeAudioSource(), isNull);
      });
    }
  });

  group('Vst3PluginInstance', () {
    test('instrument → vst3Instrument source', () {
      final vi = Vst3PluginInstance(
        id: 'vi-1',
        midiChannel: 1,
        path: '/fake/instrument.vst3',
        pluginName: 'Fake Instrument',
        pluginType: Vst3PluginType.instrument,
      );
      expect(
        vi.describeAudioSource()?.kind,
        AudioSourceKind.vst3Instrument,
      );
    });

    test('effect → null (routed via routeAudio, not a source)', () {
      final ve = Vst3PluginInstance(
        id: 've-1',
        midiChannel: 0,
        path: '/fake/effect.vst3',
        pluginName: 'Fake Effect',
        pluginType: Vst3PluginType.effect,
      );
      expect(ve.describeAudioSource(), isNull);
    });

    test('analyzer → null (pure sink, no audio output)', () {
      final va = Vst3PluginInstance(
        id: 'va-1',
        midiChannel: 0,
        path: '/fake/analyzer.vst3',
        pluginName: 'Fake Analyzer',
        pluginType: Vst3PluginType.analyzer,
      );
      expect(va.describeAudioSource(), isNull);
    });
  });

  group('AudioLooperPluginInstance', () {
    test('does not implement AudioSourcePlugin', () {
      // The audio looper consumes sources — it is not one itself.
      // Leaving the mixin unimplemented is the declarative "no audio
      // production" statement.
      final lp = AudioLooperPluginInstance(id: 'lp-1');
      expect(lp, isNot(isA<AudioSourcePlugin>()));
    });
  });

  group('AudioSourceDescriptor value semantics', () {
    test('equal descriptors compare equal', () {
      const a = AudioSourceDescriptor(
        kind: AudioSourceKind.gfKeyboard,
        midiChannel: 2,
      );
      const b = AudioSourceDescriptor(
        kind: AudioSourceKind.gfKeyboard,
        midiChannel: 2,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('different midi channels compare unequal', () {
      const a = AudioSourceDescriptor(
        kind: AudioSourceKind.gfKeyboard,
        midiChannel: 1,
      );
      const b = AudioSourceDescriptor(
        kind: AudioSourceKind.gfKeyboard,
        midiChannel: 2,
      );
      expect(a == b, isFalse);
    });

    test('different kinds compare unequal', () {
      const a = AudioSourceDescriptor(kind: AudioSourceKind.theremin);
      const b = AudioSourceDescriptor(kind: AudioSourceKind.stylophone);
      expect(a == b, isFalse);
    });
  });
}
