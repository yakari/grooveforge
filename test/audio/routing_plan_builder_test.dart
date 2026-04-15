// ============================================================================
// Unit tests for `buildRoutingPlan`.
//
// These tests exercise the plan-builder in isolation — no native FFI, no
// Flutter framework, no RackState. Every input is a plain Dart object, so
// the whole suite runs headless under `flutter test`.
//
// We use fake handle resolvers that return deterministic integers: the
// real production resolvers will hand back `Pointer.address` values,
// but the builder treats them as opaque ints and never interprets them.
// This means the tests can assert on the full plan by value equality.
//
// Coverage goals:
//   1. Empty / trivial plans.
//   2. Source enumeration (every source kind + mono/stereo layout).
//   3. Insert chain assembly: single-effect, multi-effect chain,
//      fan-in, source → VST3 termination, source → looper termination.
//   4. Looper upstream walk through an effect chain (regression
//      coverage for the 2.13.0 Live Input → Harmonizer → Looper bug).
//   5. Platform capabilities — VST3 routes only on desktop, Android
//      adapters don't see them.
//   6. Backend resolver can reject sources (VST3 on Android) without
//      making the builder crash.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:grooveforge/audio/routing_plan.dart';
import 'package:grooveforge/audio/routing_plan_builder.dart';
import 'package:grooveforge/models/audio_looper_plugin_instance.dart';
import 'package:grooveforge/models/audio_port_id.dart';
import 'package:grooveforge/models/drum_generator_plugin_instance.dart';
import 'package:grooveforge/models/gfpa_plugin_instance.dart';
import 'package:grooveforge/models/grooveforge_keyboard_plugin.dart';
import 'package:grooveforge/models/live_input_source_plugin_instance.dart';
import 'package:grooveforge/models/plugin_instance.dart';
import 'package:grooveforge/models/vst3_plugin_instance.dart';
import 'package:grooveforge/services/audio_graph.dart';

// ── Test helpers ────────────────────────────────────────────────────────────

/// Makes a fake resolver that assigns integers `1, 2, 3, …` to each
/// source in the order it is asked to resolve them. Sources the fake
/// does not know about (by default) resolve to `null`, which simulates
/// an unsupported backend like "VST3 on Android".
///
/// Optional parameters let specific tests override [monoSlots], mark
/// slots as [alwaysMasterSlots], or bind slots to a [captureGroups]
/// entry — the fields added in Phase A.3 that the adapter relies on.
SourceHandleResolver _fakeSourceResolver({
  Set<Type> reject = const {},
  Map<String, ChannelLayout> monoSlots = const {},
  Set<String> alwaysMasterSlots = const {},
  Map<String, CaptureModeGroup> captureGroups = const {},
}) {
  var nextHandle = 1;
  return (PluginInstance plugin) {
    if (reject.contains(plugin.runtimeType)) return null;
    final handle = nextHandle++;
    final kind = plugin is Vst3PluginInstance
        ? SourceKind.vst3Plugin
        : SourceKind.renderFunction;
    final channels = monoSlots[plugin.id] ?? ChannelLayout.stereo;
    final strategy = alwaysMasterSlots.contains(plugin.id)
        ? MasterMixStrategy.alwaysRender
        : MasterMixStrategy.onlyWhenConnected;
    return ResolvedSource(
      kind: kind,
      handle: handle,
      channels: channels,
      masterMixStrategy: strategy,
      captureGroup: captureGroups[plugin.id] ?? CaptureModeGroup.none,
    );
  };
}

/// Makes a fake effect resolver that hands out `100, 101, 102, …` to each
/// distinct effect slot. The concrete integer does not matter — only
/// identity.
EffectHandleResolver _fakeEffectResolver() {
  final assigned = <String, int>{};
  var next = 100;
  return (PluginInstance plugin) =>
      assigned.putIfAbsent(plugin.id, () => next++);
}

/// Convenience: build an `AudioGraph` from a list of
/// `(fromSlotId, fromPort, toSlotId, toPort)` tuples.
AudioGraph _graphFromCables(List<List<dynamic>> cables) {
  final graph = AudioGraph();
  for (final c in cables) {
    graph.connect(c[0] as String, c[1] as AudioPortId,
        c[2] as String, c[3] as AudioPortId);
  }
  return graph;
}

/// Short alias for an audio-only stereo cable.
List<dynamic> _audioCable(String from, String to) =>
    [from, AudioPortId.audioOutL, to, AudioPortId.audioInL];

// Factories for each source type — keep the tests short.

GrooveForgeKeyboardPlugin _keyboard(String id, {int channel = 1}) =>
    GrooveForgeKeyboardPlugin(
      id: id,
      midiChannel: channel,
      soundfontPath: '/fake/path.sf2',
    );

GFpaPluginInstance _theremin(String id) => GFpaPluginInstance(
      id: id,
      pluginId: 'com.grooveforge.theremin',
      midiChannel: 1,
    );

GFpaPluginInstance _stylophone(String id) => GFpaPluginInstance(
      id: id,
      pluginId: 'com.grooveforge.stylophone',
      midiChannel: 1,
    );

GFpaPluginInstance _vocoder(String id) => GFpaPluginInstance(
      id: id,
      pluginId: 'com.grooveforge.vocoder',
      midiChannel: 1,
    );

GFpaPluginInstance _reverb(String id) => GFpaPluginInstance(
      id: id,
      pluginId: 'com.grooveforge.reverb',
      midiChannel: 0,
    );

GFpaPluginInstance _harmonizer(String id) => GFpaPluginInstance(
      id: id,
      pluginId: 'com.grooveforge.audio_harmonizer',
      midiChannel: 0,
    );

LiveInputSourcePluginInstance _liveInput(String id) =>
    LiveInputSourcePluginInstance(id: id);

AudioLooperPluginInstance _looper(String id) =>
    AudioLooperPluginInstance(id: id);

DrumGeneratorPluginInstance _drums(String id) => DrumGeneratorPluginInstance(
      id: id,
      midiChannel: 10,
      builtinPatternId: 'rock_basic',
    );

Vst3PluginInstance _vst3Effect(String id) => Vst3PluginInstance(
      id: id,
      path: '/fake/effect.vst3',
      pluginName: 'Fake Effect',
      pluginType: Vst3PluginType.effect,
      midiChannel: 1,
    );

Vst3PluginInstance _vst3Instrument(String id) => Vst3PluginInstance(
      id: id,
      path: '/fake/instrument.vst3',
      pluginName: 'Fake Instrument',
      pluginType: Vst3PluginType.instrument,
      midiChannel: 1,
    );

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('buildRoutingPlan — empty / trivial', () {
    test('empty rack produces empty plan', () {
      final plan = buildRoutingPlan(
        plugins: const [],
        graph: AudioGraph(),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan, RoutingPlan.empty);
    });

    test('lone keyboard with no cables → one source, no chains', () {
      final plan = buildRoutingPlan(
        plugins: [_keyboard('kb')],
        graph: AudioGraph(),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.sources, hasLength(1));
      expect(plan.sources.first.slotId, 'kb');
      expect(plan.sources.first.kind, SourceKind.renderFunction);
      expect(plan.insertChains, isEmpty);
      expect(plan.looperSinks, isEmpty);
      expect(plan.vstRoutes, isEmpty);
    });
  });

  group('source enumeration', () {
    test('every recognised source kind is emitted once', () {
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb', channel: 1),
          _drums('dg'),
          _theremin('th'),
          _stylophone('st'),
          _vocoder('vc'),
          _liveInput('li'),
          _vst3Instrument('vi'),
        ],
        graph: AudioGraph(),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(
        plan.sources.map((s) => s.slotId).toList(),
        ['kb', 'dg', 'th', 'st', 'vc', 'li', 'vi'],
      );
    });

    test('looper and effect slots are NOT emitted as sources', () {
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb'),
          _reverb('rv'),
          _harmonizer('hm'),
          _looper('lp'),
        ],
        graph: AudioGraph(),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.sources.map((s) => s.slotId).toList(), ['kb']);
    });

    test('mono channel layout flows through to the plan', () {
      final plan = buildRoutingPlan(
        plugins: [_liveInput('li')],
        graph: AudioGraph(),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(
          monoSlots: {'li': ChannelLayout.mono},
        ),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.sources.single.channels, ChannelLayout.mono);
    });

    test('master mix strategy and capture group flow through to the plan',
        () {
      final plan = buildRoutingPlan(
        plugins: [_keyboard('kb'), _theremin('th')],
        graph: AudioGraph(),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(
          alwaysMasterSlots: {'kb'},
          captureGroups: {'th': CaptureModeGroup.theremin},
        ),
        resolveEffect: _fakeEffectResolver(),
      );
      final kb = plan.sources.firstWhere((s) => s.slotId == 'kb');
      final th = plan.sources.firstWhere((s) => s.slotId == 'th');
      expect(kb.masterMixStrategy, MasterMixStrategy.alwaysRender);
      expect(kb.captureGroup, CaptureModeGroup.none);
      expect(th.masterMixStrategy, MasterMixStrategy.onlyWhenConnected);
      expect(th.captureGroup, CaptureModeGroup.theremin);
    });
  });

  group('insert chain assembly', () {
    test('keyboard → reverb → master produces one chain with one effect',
        () {
      final graph = _graphFromCables([_audioCable('kb', 'rv')]);
      final plan = buildRoutingPlan(
        plugins: [_keyboard('kb'), _reverb('rv')],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.insertChains, hasLength(1));
      final chain = plan.insertChains.single;
      expect(chain.effects.map((e) => e.slotId).toList(), ['rv']);
      expect(chain.destination.kind, ChainDestinationKind.masterMix);
      expect(chain.sourceIndices, [0]); // kb is at index 0
    });

    test('multi-effect chain: kb → wah → reverb → master', () {
      final wah = GFpaPluginInstance(
          id: 'wa', pluginId: 'com.grooveforge.wah', midiChannel: 0);
      final graph = _graphFromCables([
        _audioCable('kb', 'wa'),
        _audioCable('wa', 'rv'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [_keyboard('kb'), wah, _reverb('rv')],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.insertChains, hasLength(1));
      expect(
        plan.insertChains.single.effects.map((e) => e.slotId).toList(),
        ['wa', 'rv'],
      );
    });

    test('fan-in: two keyboards → one reverb → master (single chain)', () {
      final graph = _graphFromCables([
        _audioCable('kb1', 'rv'),
        _audioCable('kb2', 'rv'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _reverb('rv'),
        ],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      // Both sources emitted, but they share one chain (same effect list
      // and destination).
      expect(plan.sources.map((s) => s.slotId).toSet(), {'kb1', 'kb2'});
      expect(plan.insertChains, hasLength(1));
      expect(plan.insertChains.single.sourceIndices.length, 2);
    });

    test('chain terminating at a VST3 effect uses vst3Plugin destination',
        () {
      final graph = _graphFromCables([_audioCable('kb', 'v3')]);
      final plan = buildRoutingPlan(
        plugins: [_keyboard('kb'), _vst3Effect('v3')],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.insertChains, hasLength(1));
      expect(plan.insertChains.single.destination.kind,
          ChainDestinationKind.vst3Plugin);
      expect(plan.insertChains.single.destination.slotId, 'v3');
      expect(plan.insertChains.single.effects, isEmpty);
    });
  });

  group('looper sink wiring', () {
    test('direct keyboard → looper: sink points at keyboard index', () {
      final graph = _graphFromCables([_audioCable('kb', 'lp')]);
      final plan = buildRoutingPlan(
        plugins: [_keyboard('kb'), _looper('lp')],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.looperSinks, hasLength(1));
      expect(plan.looperSinks.single.clipSlotId, 'lp');
      expect(plan.looperSinks.single.sourceIndex, 0);
    });

    test(
        'live input → harmonizer → looper: looper reads from live input '
        '(2.13.0 regression coverage)', () {
      final graph = _graphFromCables([
        _audioCable('li', 'hm'),
        _audioCable('hm', 'lp'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [_liveInput('li'), _harmonizer('hm'), _looper('lp')],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.looperSinks, hasLength(1));
      expect(plan.looperSinks.single.clipSlotId, 'lp');
      // Live input is the only source in the plan → index 0.
      expect(plan.looperSinks.single.sourceIndex, 0);

      // The chain must also exist so the harmonizer actually runs; its
      // destination is the looper, and the post-chain capture is where
      // the looper will read the wet signal from.
      expect(plan.insertChains, hasLength(1));
      expect(plan.insertChains.single.destination.kind,
          ChainDestinationKind.looperClip);
      expect(plan.insertChains.single.effects.map((e) => e.slotId).toList(),
          ['hm']);
    });

    test('looper with no upstream cable → no sink entry', () {
      final plan = buildRoutingPlan(
        plugins: [_looper('lp')],
        graph: AudioGraph(),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.looperSinks, isEmpty);
    });
  });

  group('VST3 routes and platform caps', () {
    test('VST3 → VST3 audio route emitted under JACK caps', () {
      final graph = _graphFromCables([_audioCable('v3a', 'v3b')]);
      final plan = buildRoutingPlan(
        plugins: [_vst3Instrument('v3a'), _vst3Effect('v3b')],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.vstRoutes, hasLength(1));
      expect(plan.vstRoutes.single.fromSlotId, 'v3a');
      expect(plan.vstRoutes.single.toSlotId, 'v3b');
    });

    test('VST3 routes NOT emitted under Oboe caps (Android)', () {
      final graph = _graphFromCables([_audioCable('v3a', 'v3b')]);
      final plan = buildRoutingPlan(
        plugins: [_vst3Instrument('v3a'), _vst3Effect('v3b')],
        graph: graph,
        caps: BackendCapabilities.oboe,
        resolveSource: _fakeSourceResolver(
          // Android backend resolver rejects VST3 sources entirely.
          reject: {Vst3PluginInstance},
        ),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.vstRoutes, isEmpty);
      // And since the VST3 instrument was rejected, there is no source
      // entry for it — the builder does not crash on null resolver output.
      expect(plan.sources, isEmpty);
    });
  });

  group('Oboe (Android) backend shape', () {
    // Fake Android resolver that mirrors the production one: keyboards /
    // theremin / stylophone / vocoder / live input resolve to
    // oboeBusSlot entries, VST3 resolves to null (not hosted on Android).
    ResolvedSource? androidFake(PluginInstance plugin) {
      if (plugin is Vst3PluginInstance) return null;
      if (plugin is GrooveForgeKeyboardPlugin ||
          plugin is DrumGeneratorPluginInstance) {
        // Sfid = (channel-based fake). The real builder passes this
        // through from the keyboardSfIds map.
        return const ResolvedSource(
          kind: SourceKind.oboeBusSlot,
          handle: 0,
          busSlotId: 1,
        );
      }
      if (plugin is LiveInputSourcePluginInstance) {
        return const ResolvedSource(
          kind: SourceKind.oboeBusSlot,
          handle: 0,
          busSlotId: 103,
        );
      }
      if (plugin is GFpaPluginInstance) {
        return switch (plugin.pluginId) {
          'com.grooveforge.theremin' => const ResolvedSource(
              kind: SourceKind.oboeBusSlot,
              handle: 0,
              busSlotId: 100,
            ),
          'com.grooveforge.stylophone' => const ResolvedSource(
              kind: SourceKind.oboeBusSlot,
              handle: 0,
              busSlotId: 101,
            ),
          'com.grooveforge.vocoder' => const ResolvedSource(
              kind: SourceKind.oboeBusSlot,
              handle: 0,
              busSlotId: 102,
            ),
          _ => null,
        };
      }
      return null;
    }

    test('every source emitted as oboeBusSlot with correct bus slot ID',
        () {
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb'),
          _theremin('th'),
          _stylophone('st'),
          _vocoder('vc'),
          _liveInput('li'),
        ],
        graph: AudioGraph(),
        caps: BackendCapabilities.oboe,
        resolveSource: androidFake,
        resolveEffect: _fakeEffectResolver(),
      );
      final byId = {for (final s in plan.sources) s.slotId: s};
      expect(byId['kb']!.kind, SourceKind.oboeBusSlot);
      expect(byId['kb']!.busSlotId, 1);
      expect(byId['th']!.busSlotId, 100);
      expect(byId['st']!.busSlotId, 101);
      expect(byId['vc']!.busSlotId, 102);
      expect(byId['li']!.busSlotId, 103);
    });

    test('VST3 sources rejected → no source, no chain, no sink', () {
      final graph = _graphFromCables([_audioCable('vi', 'lp')]);
      final plan = buildRoutingPlan(
        plugins: [_vst3Instrument('vi'), _looper('lp')],
        graph: graph,
        caps: BackendCapabilities.oboe,
        resolveSource: androidFake,
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.sources, isEmpty);
      expect(plan.insertChains, isEmpty);
      expect(plan.looperSinks, isEmpty);
    });

    test(
        'live input → harmonizer → looper on Oboe: sink points at live '
        'input source, chain runs on live-input bus slot', () {
      final graph = _graphFromCables([
        _audioCable('li', 'hm'),
        _audioCable('hm', 'lp'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [_liveInput('li'), _harmonizer('hm'), _looper('lp')],
        graph: graph,
        caps: BackendCapabilities.oboe,
        resolveSource: androidFake,
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.sources.single.busSlotId, 103);
      expect(plan.looperSinks.single.sourceIndex, 0);
      final chain = plan.insertChains.single;
      expect(chain.effects.map((e) => e.slotId).toList(), ['hm']);
      expect(chain.destination.kind, ChainDestinationKind.looperClip);
      expect(chain.sourceIndices, [0]);
    });
  });

  group('Phase H — shared stateful-effect dedup', () {
    // Topology: kb1 → reverb, kb2 → harmonizer → reverb, theremin →
    // harmonizer → reverb. This is the v2.13.0 "grésillement" bug:
    // the reverb handle would otherwise end up in two distinct chains
    // (one direct [kb1] → [reverb], one [kb2, theremin] → [harmonizer,
    // reverb]) and get its stateful filters trashed by being called
    // twice per audio block with different inputs. The builder must
    // keep the first chain that claimed the reverb DSP and drop the
    // effect from any subsequent chain, with a diagnostic for each drop.
    test(
        'grésillement topology: reverb is kept in first chain only, '
        'second chain loses it but stays as harmonizer chain, diagnostic emitted',
        () {
      final harmonizer = _harmonizer('hm');
      final reverb = _reverb('rv');
      final graph = _graphFromCables([
        _audioCable('kb1', 'rv'),
        _audioCable('kb2', 'hm'),
        _audioCable('th', 'hm'),
        _audioCable('hm', 'rv'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _theremin('th'),
          harmonizer,
          reverb,
        ],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );

      // Exactly one diagnostic about a dropped reverb reference.
      expect(plan.diagnostics, hasLength(1));
      final diag = plan.diagnostics.single;
      expect(diag.kind, RoutingDiagnosticKind.sharedStatefulEffect);
      expect(diag.slotId, 'rv');

      // We expect two chains: the first claims the reverb, the second
      // used to contain the reverb but had it stripped by dedup and
      // now only contains the harmonizer.
      expect(plan.insertChains, hasLength(2));

      // Find the chain that still contains the reverb — exactly one
      // such chain is allowed after dedup.
      final chainsWithReverb = plan.insertChains
          .where((c) => c.effects.any((e) => e.slotId == 'rv'))
          .toList();
      expect(chainsWithReverb, hasLength(1));

      // The surviving harmonizer-only chain must still exist so that
      // kb2 and theremin still reach the master mix via the harmonizer.
      final harmonizerOnly = plan.insertChains.firstWhere(
        (c) =>
            c.effects.length == 1 && c.effects.single.slotId == 'hm',
        orElse: () => throw StateError('no harmonizer-only chain'),
      );
      expect(harmonizerOnly.effects.single.slotId, 'hm');
    });

    test(
        'two keyboards fan-in into same reverb is NOT dedup — it stays as '
        'one merged chain with two sources', () {
      // Straight fan-in: kb1 and kb2 both go directly into the same
      // reverb. This is a SINGLE chain from the builder's point of view
      // (same effect sequence + same destination), and must remain a
      // single chain with sourceCount == 2. No dedup, no diagnostics.
      final graph = _graphFromCables([
        _audioCable('kb1', 'rv'),
        _audioCable('kb2', 'rv'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _reverb('rv'),
        ],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.diagnostics, isEmpty);
      expect(plan.insertChains, hasLength(1));
      expect(plan.insertChains.single.sourceIndices.length, 2);
      expect(
        plan.insertChains.single.effects.map((e) => e.slotId).toList(),
        ['rv'],
      );
    });

    test(
        'chain emptied entirely by dedup is dropped when destination is '
        'masterMix', () {
      // Two sources share a single reverb with no other effect on
      // either side. First chain wins and the second chain becomes
      // effectless → entirely dropped since it goes to masterMix.
      //
      // This is the same as the fan-in case topologically, but we
      // construct it as two SEPARATE source chains because each source
      // has its own divergent upstream (kb1 alone, kb2 → harmonizer).
      // The only shared element is reverb, and dropping it from the
      // second chain means the harmonizer output never reaches master.
      //
      // We expect one diagnostic for the dropped reverb and one
      // remaining chain (harmonizer-only, because the harmonizer is
      // NOT shared).
      final graph = _graphFromCables([
        _audioCable('kb1', 'rv'),
        _audioCable('kb2', 'hm'),
        _audioCable('hm', 'rv'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _harmonizer('hm'),
          _reverb('rv'),
        ],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.diagnostics, hasLength(1));
      expect(plan.diagnostics.single.slotId, 'rv');

      // Two chains survive: one with reverb, one with only harmonizer.
      expect(plan.insertChains, hasLength(2));
      final reverbChains = plan.insertChains
          .where((c) => c.effects.any((e) => e.slotId == 'rv'));
      expect(reverbChains, hasLength(1));
      final harmOnly = plan.insertChains
          .where((c) => c.effects.every((e) => e.slotId == 'hm') &&
              c.effects.isNotEmpty);
      expect(harmOnly, hasLength(1));
    });

    test(
        'Android: multi-source fan-in chain emits androidFanInNotSupported '
        'diagnostic (Oboe cannot share a stateful effect across bus slots)',
        () {
      // Same topology as the "two keyboards fan-in into same reverb"
      // test, but under Oboe caps: the plan builder should still emit
      // one chain with two sources (desktop semantics are preserved),
      // but also attach a new diagnostic telling the adapter that
      // Android will only apply the effect to the first source.
      final graph = _graphFromCables([
        _audioCable('kb1', 'rv'),
        _audioCable('kb2', 'rv'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _reverb('rv'),
        ],
        graph: graph,
        caps: BackendCapabilities.oboe,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.insertChains, hasLength(1));
      expect(plan.insertChains.single.sourceIndices.length, 2);
      expect(plan.diagnostics, hasLength(1));
      expect(
        plan.diagnostics.single.kind,
        RoutingDiagnosticKind.androidFanInNotSupported,
      );
      expect(plan.diagnostics.single.slotId, 'rv');
    });

    test(
        'desktop JACK caps: fan-in chains do NOT get the Android '
        'diagnostic', () {
      final graph = _graphFromCables([
        _audioCable('kb1', 'rv'),
        _audioCable('kb2', 'rv'),
      ]);
      final plan = buildRoutingPlan(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _reverb('rv'),
        ],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.diagnostics, isEmpty);
    });

    test(
        'no shared effects → no diagnostics, no dedup', () {
      final graph = _graphFromCables([_audioCable('kb', 'rv')]);
      final plan = buildRoutingPlan(
        plugins: [_keyboard('kb'), _reverb('rv')],
        graph: graph,
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(plan.diagnostics, isEmpty);
      expect(plan.insertChains, hasLength(1));
    });
  });

  group('wouldCauseSharedStatefulEffect — drag-time validator', () {
    test(
        'adding a second divergent upstream into reverb returns the '
        'reverb slot ID', () {
      // Setup: kb2 → harmonizer → reverb already exists.
      // Proposed new cable: kb1 → reverb. This is the grésillement
      // topology; the validator must block it and return "rv".
      final graph = _graphFromCables([
        _audioCable('kb2', 'hm'),
        _audioCable('hm', 'rv'),
      ]);
      final conflict = wouldCauseSharedStatefulEffect(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _harmonizer('hm'),
          _reverb('rv'),
        ],
        graph: graph,
        fromSlotId: 'kb1',
        fromPort: AudioPortId.audioOutL,
        toSlotId: 'rv',
        toPort: AudioPortId.audioInL,
      );
      expect(conflict, 'rv');
    });

    test(
        'simple fan-in (two keyboards directly into one reverb) is '
        'allowed — builder does not dedup it', () {
      final graph = _graphFromCables([_audioCable('kb1', 'rv')]);
      final conflict = wouldCauseSharedStatefulEffect(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _reverb('rv'),
        ],
        graph: graph,
        fromSlotId: 'kb2',
        fromPort: AudioPortId.audioOutL,
        toSlotId: 'rv',
        toPort: AudioPortId.audioInL,
      );
      expect(conflict, isNull);
    });

    test(
        'single direct cable into an effect is always allowed', () {
      final conflict = wouldCauseSharedStatefulEffect(
        plugins: [_keyboard('kb'), _reverb('rv')],
        graph: AudioGraph(),
        fromSlotId: 'kb',
        fromPort: AudioPortId.audioOutL,
        toSlotId: 'rv',
        toPort: AudioPortId.audioInL,
      );
      expect(conflict, isNull);
    });

    test(
        'chaining a second effect after an existing effect does not '
        'trigger the validator (single upstream root)', () {
      // kb → hm is already cabled. Adding hm → rv means rv has one
      // upstream chain and is fine.
      final graph = _graphFromCables([_audioCable('kb', 'hm')]);
      final conflict = wouldCauseSharedStatefulEffect(
        plugins: [_keyboard('kb'), _harmonizer('hm'), _reverb('rv')],
        graph: graph,
        fromSlotId: 'hm',
        fromPort: AudioPortId.audioOutL,
        toSlotId: 'rv',
        toPort: AudioPortId.audioInL,
      );
      expect(conflict, isNull);
    });

    test(
        'cabling a keyboard into a fresh effect slot is always '
        'allowed, even when the rack has pre-existing shared-effect '
        'topologies (regression for the slot-6 wah block)', () {
      // Mirrors the exact rack state from the user's logcat:
      //   slot-0 kb, slot-1 kb, slot-3 theremin,
      //   slot-4 harmonizer, slot-5 reverb (pre-existing shared),
      //   slot-6 wah (freshly added, zero cables yet).
      // Cables:
      //   kb → rv
      //   kb2 → hm
      //   th → hm
      //   hm → rv   (← the divergent upstream on reverb)
      // Proposed new cable: kb → wah. Must be allowed.
      final wah = GFpaPluginInstance(
          id: 'slot-6', pluginId: 'com.grooveforge.wah', midiChannel: 0);
      final graph = _graphFromCables([
        _audioCable('slot-0', 'slot-5'),
        _audioCable('slot-1', 'slot-4'),
        _audioCable('slot-3', 'slot-4'),
        _audioCable('slot-4', 'slot-5'),
      ]);
      final conflict = wouldCauseSharedStatefulEffect(
        plugins: [
          _keyboard('slot-0', channel: 1),
          _keyboard('slot-1', channel: 2),
          _theremin('slot-3'),
          _harmonizer('slot-4'),
          _reverb('slot-5'),
          wah,
        ],
        graph: graph,
        fromSlotId: 'slot-0',
        fromPort: AudioPortId.audioOutL,
        toSlotId: 'slot-6',
        toPort: AudioPortId.audioInL,
      );
      expect(conflict, isNull);
    });

    test(
        'pre-existing conflict is NOT blamed on an unrelated new '
        'cable — only the newly-introduced conflict is reported', () {
      // The project already contains a broken topology: kb1 → rv and
      // kb2 → hm → rv, loaded from an old .gf file. The user now adds
      // an unrelated cable kb3 → wh. The validator must NOT flag rv
      // as a conflict caused by kb3 → wh, because rv was already
      // broken before.
      final wah = GFpaPluginInstance(
          id: 'wh', pluginId: 'com.grooveforge.wah', midiChannel: 0);
      final graph = _graphFromCables([
        _audioCable('kb1', 'rv'),
        _audioCable('kb2', 'hm'),
        _audioCable('hm', 'rv'),
      ]);
      final conflict = wouldCauseSharedStatefulEffect(
        plugins: [
          _keyboard('kb1', channel: 1),
          _keyboard('kb2', channel: 2),
          _keyboard('kb3', channel: 3),
          _harmonizer('hm'),
          _reverb('rv'),
          wah,
        ],
        graph: graph,
        fromSlotId: 'kb3',
        fromPort: AudioPortId.audioOutL,
        toSlotId: 'wh',
        toPort: AudioPortId.audioInL,
      );
      expect(conflict, isNull);
    });
  });

  group('equality + determinism', () {
    test('building the same topology twice produces equal plans', () {
      PluginInstance k() => _keyboard('kb');
      PluginInstance r() => _reverb('rv');
      final cables = [_audioCable('kb', 'rv')];

      final a = buildRoutingPlan(
        plugins: [k(), r()],
        graph: _graphFromCables(cables),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      final b = buildRoutingPlan(
        plugins: [k(), r()],
        graph: _graphFromCables(cables),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('changing a cable yields an unequal plan', () {
      final a = buildRoutingPlan(
        plugins: [_keyboard('kb'), _reverb('rv')],
        graph: AudioGraph(),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      final b = buildRoutingPlan(
        plugins: [_keyboard('kb'), _reverb('rv')],
        graph: _graphFromCables([_audioCable('kb', 'rv')]),
        caps: BackendCapabilities.jack,
        resolveSource: _fakeSourceResolver(),
        resolveEffect: _fakeEffectResolver(),
      );
      expect(a == b, isFalse);
    });
  });
}
