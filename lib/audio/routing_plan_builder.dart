// ============================================================================
// RoutingPlanBuilder — single pure function that turns the Dart AudioGraph +
// rack plugin list into a flat, backend-agnostic RoutingPlan.
//
// Phase A.2 of the audio routing redesign (see
// `docs/dev/AUDIO_ROUTING_REDESIGN.md`). No caller in production code yet;
// Phase A.3 and A.4 will replace the existing `syncAudioRouting` branches
// with thin backend adapters that consume the plan produced here.
//
// Why a pure function:
//   1. Unit-testable. All inputs are plain Dart data, no native FFI calls,
//      no dart:ffi imports. The whole file can run under `flutter test`.
//   2. One source of truth. Linux, macOS, Android, and future Windows / iOS
//      adapters all read the same flat plan. Platform differences live in
//      the adapters, not here.
//   3. Dirty-check friendly. Since RoutingPlan has value equality, the
//      caller can memoise and skip FFI apply when the plan has not
//      changed — something the current duplicated sync code cannot do.
//
// What this file deliberately does NOT do:
//   - No FFI calls. The caller supplies a [SourceHandleResolver] that turns
//     a plugin instance into an opaque `int` handle (function pointer
//     address on desktop, Oboe bus slot ID on Android). In tests this
//     resolver is a pure function over fake plugins.
//   - No RackState / Provider access. Inputs are passed by argument so the
//     builder can be exercised from tests that know nothing about Flutter.
//   - No side effects. Calling `buildRoutingPlan` twice with the same
//     inputs must return equal plans (verified by the `equals` tests).
// ============================================================================

import '../models/audio_graph_connection.dart';
import '../models/audio_looper_plugin_instance.dart';
import '../models/audio_port_id.dart';
import '../models/gfpa_plugin_instance.dart';
import '../models/plugin_instance.dart';
import '../models/vst3_plugin_instance.dart';
import '../services/audio_graph.dart';
import 'audio_source_descriptor.dart';
import 'routing_plan.dart';

/// Returns true when [plugin] is a recognised audio *source* — a slot
/// that produces samples from nothing, not an effect that transforms
/// someone else's audio. Used by [_walkUpstreamToSource] to know when
/// to stop climbing the graph.
///
/// Phase B cashes the plan-builder dividend: this predicate is now a
/// two-line check that asks the plugin itself ("are you an audio
/// source?") via the [AudioSourcePlugin] mixin. Adding a new source
/// kind no longer requires editing this function — just mix in
/// [AudioSourcePlugin] on the new plugin class and override
/// [AudioSourcePlugin.describeAudioSource] to return a non-null
/// descriptor.
bool _isAudioSource(PluginInstance plugin) {
  return plugin is AudioSourcePlugin &&
      (plugin as AudioSourcePlugin).describeAudioSource() != null;
}

/// Returns true when [plugin] is a GFPA descriptor-backed effect (reverb,
/// delay, wah, eq, compressor, chorus, audio_harmonizer, …).
///
/// A GFPA plugin that does not declare itself an audio source via the
/// descriptor is, by construction, an effect (or a MIDI FX). The
/// non-GFPA cases — VST3 effects, the audio looper, anything else —
/// are not GFPA-chainable and return `false`.
bool _isGfpaEffect(PluginInstance plugin) {
  return plugin is GFpaPluginInstance &&
      plugin.describeAudioSource() == null;
}

// ── Handle resolution ───────────────────────────────────────────────────────

/// Opaque handle for a source render callback.
///
/// On desktop this is the `int` address of a C function pointer
/// (`thereminRenderBlockPtr.address`, `keyboardRenderFnForSlot(...).address`).
/// On Android the live input / theremin / stylophone / vocoder sources are
/// registered on the Oboe bus instead, and the handle field is unused —
/// the plan entry carries a [SourceEntry.busSlotId] in that case.
///
/// The builder never interprets this integer; it just passes it through.
typedef RenderFnAddress = int;

/// Result of [SourceHandleResolver]: where on the native layer this
/// source lives. Produced by the caller (which has access to the real
/// FFI layer) and consumed by the builder to fill in [SourceEntry].
class ResolvedSource {
  /// How the backend adapter should treat this source — render function,
  /// VST3 plugin ordinal, or Oboe bus slot.
  final SourceKind kind;

  /// Integer handle interpreted per [kind]. See [SourceEntry.renderFnHandle].
  final int handle;

  /// Oboe / AAudio bus slot ID, or −1 if [kind] is not `oboeBusSlot`.
  final int busSlotId;

  /// Declared channel layout of the raw source output. `mono` unlocks
  /// the Harmonizer mono shortcut and similar optimisations.
  final ChannelLayout channels;

  /// When the backend adapter should register this source with the
  /// master mix. Defaults to `onlyWhenConnected` — the safe choice for
  /// instruments whose raw path is already audible without JACK's help.
  final MasterMixStrategy masterMixStrategy;

  /// Capture-mode group this source belongs to (theremin / stylo /
  /// vocoder / none). The adapter aggregates per-group usage and issues
  /// one `set_capture_mode` call per group at the end of each sync.
  final CaptureModeGroup captureGroup;

  const ResolvedSource({
    required this.kind,
    required this.handle,
    this.busSlotId = -1,
    this.channels = ChannelLayout.stereo,
    this.masterMixStrategy = MasterMixStrategy.onlyWhenConnected,
    this.captureGroup = CaptureModeGroup.none,
  });
}

/// Callback that turns a [PluginInstance] into its native source handle,
/// or `null` if the plugin is not an audio source on this backend (e.g.
/// VST3 on Android).
///
/// Production callers will implement this by looking up
/// `AudioInputFFI().thereminRenderBlockPtr.address`, the keyboard slot
/// render function, the Oboe bus slot, etc. Tests pass a fake that
/// returns deterministic integers so plans can be compared by equality.
typedef SourceHandleResolver =
    ResolvedSource? Function(PluginInstance plugin);

/// Callback that returns the native DSP handle for an effect slot, or
/// `null` if the slot does not yet have one (e.g. the effect is still
/// being initialised asynchronously). When the handle is `null`, the
/// builder simply omits that effect from the chain — the next plan
/// rebuild will include it once registration completes.
typedef EffectHandleResolver = int? Function(PluginInstance plugin);

// ── Drag-time validation (Phase H UI feedback) ──────────────────────────────

/// Returns true if [plugin] is a GFPA effect slot — a descriptor-backed
/// GFPA instance that is not one of the three instrument plugin IDs.
/// Used by the drag-time validator below to decide whether a cable
/// endpoint is "an effect" (which has mutable filter state and cannot
/// be fed from divergent paths) or "a source" (which is free to fan in).
bool _isValidatorEffect(PluginInstance plugin) {
  if (plugin is! GFpaPluginInstance) return false;
  return plugin.describeAudioSource() == null;
}

/// Drag-time validator for the "shared stateful effect" constraint.
///
/// Rejects the exact topology that the v2.13.0 grésillement bug
/// exposed: an audio effect slot receiving two or more incoming audio
/// cables where at least one of them originates from *another effect*.
/// Stateful effects (reverb, delay, chorus, harmonizer, wah, …) hold
/// internal filter state that is advanced on every `process()` call;
/// if the callback ran them once per incoming cable with different
/// inputs, each call would corrupt the next one's filter history.
///
/// The rule is deliberately **local** (O(incoming cables on `toSlotId`))
/// rather than a whole-plan dedup replay. It gives a clean, predictable
/// answer regardless of the rest of the rack, and never false-positives
/// on unrelated pre-existing conflicts in the loaded project.
///
/// Allowed shapes:
/// * 0 or 1 incoming cables on the target effect → always OK.
/// * 2+ incoming cables where ALL come directly from audio sources
///   (keyboards, theremin, live input, …) → pure fan-in, handled
///   correctly by every backend's chain machinery.
///
/// Blocked shape:
/// * 2+ incoming cables where AT LEAST ONE comes from another effect
///   → divergent-upstream fan-in into a stateful effect. Block and
///   return the target effect's slotId so the UI can name it in a
///   SnackBar.
///
/// * [plugins] — current rack contents (used to look up the target
///   plugin kind and the upstream plugin kind for each incoming cable).
/// * [graph] — current cable graph (not mutated).
/// * [fromSlotId] / [fromPort] / [toSlotId] / [toPort] — the proposed
///   cable. Only audio-input ports trigger the check; other target
///   ports return null unconditionally.
///
/// Returns `null` if the cable is allowed, or the target effect's slot
/// ID string if the rule is violated.
String? wouldCauseSharedStatefulEffect({
  required List<PluginInstance> plugins,
  required AudioGraph graph,
  required String fromSlotId,
  required AudioPortId fromPort,
  required String toSlotId,
  required AudioPortId toPort,
}) {
  // Only audio cables (fromPort = audioOutL) are subject to the rule.
  // MIDI and data cables bypass the check — they cannot participate in
  // an effect-chain shared-state conflict.
  if (fromPort != AudioPortId.audioOutL) return null;
  if (toPort != AudioPortId.audioInL) return null;

  // Look up the target plugin. If it is not a GFPA effect slot, the
  // rule does not apply — the target is either a source (which has no
  // state to corrupt), a looper, or a VST3 plugin (handled by its own
  // routing code).
  final targetPlugin = plugins.where((p) => p.id == toSlotId).firstOrNull;
  if (targetPlugin == null) return null;
  if (!_isValidatorEffect(targetPlugin)) return null;

  // Collect the upstream slot IDs of every *existing* incoming audio
  // cable on the target effect, plus the proposed new cable.
  // `audioInR` is the stereo pair of `audioInL` and contributes the
  // same logical "incoming signal path" — we treat both as the same
  // edge for validation purposes, which is why we count cables per
  // fromSlotId rather than per port.
  final existingUpstreamSlotIds = <String>{};
  for (final conn in graph.connections) {
    if (conn.toSlotId != toSlotId) continue;
    if (conn.toPort != AudioPortId.audioInL &&
        conn.toPort != AudioPortId.audioInR) {
      continue;
    }
    existingUpstreamSlotIds.add(conn.fromSlotId);
  }

  // If the proposed source is already in the set, nothing changes —
  // the cable is a duplicate that the graph will reject at commit time
  // anyway. Defer to the graph's duplicate check by returning null.
  if (existingUpstreamSlotIds.contains(fromSlotId)) return null;

  // Build the post-add set of upstream slot IDs (existing + new).
  final allUpstreamSlotIds = <String>{
    ...existingUpstreamSlotIds,
    fromSlotId,
  };

  // 0 or 1 upstream: impossible at this point (we just added one), but
  // defensive — nothing to check.
  if (allUpstreamSlotIds.length < 2) return null;

  // 2+ upstream sources. Block if ANY of them is another effect.
  for (final upstreamSlotId in allUpstreamSlotIds) {
    final upstreamPlugin =
        plugins.where((p) => p.id == upstreamSlotId).firstOrNull;
    if (upstreamPlugin == null) continue;
    if (_isValidatorEffect(upstreamPlugin)) {
      return toSlotId;
    }
  }

  // All upstream cables come from audio sources — pure fan-in, allowed
  // by every backend.
  return null;
}

// ── The builder ─────────────────────────────────────────────────────────────

/// Produces a flat [RoutingPlan] from the current rack topology.
///
/// * [plugins] — every slot currently in the rack, in rack order.
/// * [graph] — the AudioGraph holding all cables. Only audio cables
///   (`audioOutL → audioInL`) are consulted; MIDI / chord / scale cables
///   are ignored here.
/// * [caps] — backend capability profile; controls whether VST3 routes
///   are emitted and how sources are preferred on Android.
/// * [resolveSource] — turns a plugin into its native source handle.
/// * [resolveEffect] — turns an effect plugin into its native DSP handle.
///
/// The builder performs three passes over the graph:
///
///   1. **Source enumeration** — every plugin that answers "yes" to
///      [_isAudioSource] gets one [SourceEntry]. The `resolveSource`
///      callback provides the handle and channel layout.
///
///   2. **Chain assembly** — walks the outgoing audio cables of every
///      source, collects downstream effect chains, and emits one
///      [InsertChainEntry] per chain with the correct destination
///      (master mix, VST3 plugin, or looper clip).
///
///   3. **Looper binding** — for each cable that terminates at an audio
///      looper's `audioInL`, walks *upstream* past any effects to find
///      the root source, and emits a [LooperSinkEntry] keyed to that
///      source's index. Reading the looper's input from the post-chain
///      capture of the root source is what makes "Live Input →
///      Harmonizer → Looper" record the harmonized signal instead of
///      the dry mic.
///
/// The returned plan's lists are freshly allocated — the caller is free
/// to cache and compare them by value.
RoutingPlan buildRoutingPlan({
  required List<PluginInstance> plugins,
  required AudioGraph graph,
  required BackendCapabilities caps,
  required SourceHandleResolver resolveSource,
  required EffectHandleResolver resolveEffect,
}) {
  // ── Pass 1: enumerate sources ──────────────────────────────────────────
  //
  // Stable order = rack order. Effect / looper slots are skipped so their
  // indices never appear as source entries. We still keep a map from
  // slotId → index so the later passes can reference sources cheaply.
  final sources = <SourceEntry>[];
  final sourceIndexBySlotId = <String, int>{};

  for (final plugin in plugins) {
    if (!_isAudioSource(plugin)) continue;
    final resolved = resolveSource(plugin);
    if (resolved == null) continue; // unsupported on this backend

    sources.add(
      SourceEntry(
        slotId: plugin.id,
        kind: resolved.kind,
        renderFnHandle: resolved.handle,
        busSlotId: resolved.busSlotId,
        channels: resolved.channels,
        masterMixStrategy: resolved.masterMixStrategy,
        captureGroup: resolved.captureGroup,
      ),
    );
    sourceIndexBySlotId[plugin.id] = sources.length - 1;
  }

  // ── Pass 2: insert chains ──────────────────────────────────────────────
  //
  // For every source we walk downstream through audio cables, collecting
  // contiguous GFPA effects into a chain until we hit a destination: the
  // master mix (implicit), a VST3 effect, or an audio looper. The looper
  // case is handled in Pass 3 because it does not produce a chain — it
  // consumes the root source's capture buffer directly.
  //
  // Multi-source fan-in (two keyboards → reverb) is represented as a
  // single InsertChainEntry whose `sourceIndices` holds both sources.
  // A chain is identified by the ordered list of effect slot IDs it
  // contains plus its destination; we deduplicate with a map.
  final chainsByKey = <String, _ChainBuilder>{};
  final pluginsById = {for (final p in plugins) p.id: p};

  for (final source in plugins) {
    if (!_isAudioSource(source)) continue;
    if (!sourceIndexBySlotId.containsKey(source.id)) continue;

    // Walk each outgoing audio cable independently. A source with two
    // audio-out cables branches into two chains.
    for (final conn in graph.connections) {
      if (conn.fromSlotId != source.id) continue;
      if (conn.fromPort != AudioPortId.audioOutL) continue; // stereo pair

      final chain = _collectChainDownstream(
        startSlotId: source.id,
        cable: conn,
        pluginsById: pluginsById,
        graph: graph,
        resolveEffect: resolveEffect,
      );
      if (chain == null) continue; // dead-end cable

      // Looper-terminated chains are handled in Pass 3. We still emit
      // the chain (with looper destination) so its effects run in the
      // callback — the looper will read from the root source's
      // post-chain capture, which is where the wet signal lives.
      final key = chain.dedupKey();
      final existing = chainsByKey[key];
      if (existing != null) {
        existing.addSource(sourceIndexBySlotId[source.id]!);
      } else {
        chain.addSource(sourceIndexBySlotId[source.id]!);
        chainsByKey[key] = chain;
      }
    }
  }

  final insertChains = [
    for (final chain in chainsByKey.values) chain.build(),
  ];

  // ── Pass 2b: shared stateful-effect dedup ───────────────────────────────
  //
  // Phase H of the audio routing redesign: stateful GFPA effects
  // (reverb, delay, chorus, harmonizer, …) hold internal filter state
  // that is updated on every `process()` call. Calling the same DSP
  // instance twice per audio block with different inputs interleaves
  // both signals into the shared state and produces corrupted output —
  // the v2.13.0 "grésillement" bug. Neither the desktop JACK callback
  // nor the Oboe callback can call an effect twice per block safely, so
  // the plan builder guarantees each native DSP handle appears in at
  // most one chain.
  //
  // When two chains reference the same `dspHandle`, we keep the first
  // one (stable ordering = first encountered) and drop the shared
  // effect from every subsequent chain. If dropping the shared effect
  // empties a chain (i.e. the chain's only effect was the shared one),
  // the whole chain is removed. A diagnostic is emitted for every drop
  // so the adapter can debugPrint it — and a future Phase F.5 will
  // surface the warnings in the patch view.
  final dedupedChains = <InsertChainEntry>[];
  final diagnostics = <RoutingDiagnostic>[];
  final chainIndexByDspHandle = <int, int>{};
  for (final chain in insertChains) {
    final keptEffects = <EffectEntry>[];
    for (final effect in chain.effects) {
      final firstChainIdx = chainIndexByDspHandle[effect.dspHandle];
      if (firstChainIdx == null) {
        // First time we see this DSP handle — claim it for this chain.
        chainIndexByDspHandle[effect.dspHandle] = dedupedChains.length;
        keptEffects.add(effect);
      } else {
        // Already claimed by an earlier chain. Drop the effect from this
        // chain and emit a diagnostic so the user can see why their
        // cable is not producing audio.
        diagnostics.add(
          RoutingDiagnostic(
            kind: RoutingDiagnosticKind.sharedStatefulEffect,
            slotId: effect.slotId,
            message:
                'Effect "${effect.slotId}" is cabled into multiple signal '
                'paths with different upstream sources. Stateful effects '
                'cannot be shared across chains — duplicate the effect '
                'slot so each path has its own instance. Dropping this '
                'cable for now.',
          ),
        );
      }
    }
    // If the chain still has content after dedup, keep it. A chain with
    // no effects AND no audio destination (looper / VST3) is pointless;
    // drop it entirely. A chain with no effects but a looper/VST3
    // destination is still valid (it's a direct source → sink cable).
    final keepChain = keptEffects.isNotEmpty ||
        chain.destination.kind != ChainDestinationKind.masterMix;
    if (keepChain) {
      dedupedChains.add(
        InsertChainEntry(
          sourceIndices: chain.sourceIndices,
          effects: keptEffects,
          destination: chain.destination,
        ),
      );

      // Android fan-in limitation: a multi-source chain with effects
      // can only be applied to the first source's bus slot. Emit a
      // diagnostic so the user sees in logcat why additional sources
      // are not getting the effect applied. Desktop backends support
      // fan-in natively and do not get this warning.
      if (caps.prefersOboeBus &&
          chain.sourceIndices.length > 1 &&
          keptEffects.isNotEmpty) {
        final droppedSourceCount = chain.sourceIndices.length - 1;
        final effectNames = keptEffects.map((e) => e.slotId).join(', ');
        diagnostics.add(
          RoutingDiagnostic(
            kind: RoutingDiagnosticKind.androidFanInNotSupported,
            // Flag the first effect in the chain — it's the handle
            // that will actually run. Downstream UI work may choose
            // to highlight the effect slot in the patch view.
            slotId: keptEffects.first.slotId,
            message:
                'Android: effect chain [$effectNames] has '
                '${chain.sourceIndices.length} fan-in sources. Only the '
                'first source will get the effect; $droppedSourceCount '
                'additional source(s) will output dry. Duplicate the '
                'effect slot so each source has its own instance.',
          ),
        );
      }
    }
  }

  // ── Pass 3: looper sinks ───────────────────────────────────────────────
  //
  // For every audio cable into an audio looper clip, walk upstream past
  // any effects until we find the root source, then emit a LooperSinkEntry
  // pointing at that source's index. The backend's RT callback writes the
  // post-effect mix into the source's capture buffer (see the renderCapture
  // overwrite in dart_vst_host_jack.cpp and g_srcCapture on Android), so
  // the looper reads the processed audio for free.
  final looperSinks = <LooperSinkEntry>[];
  for (final conn in graph.connections) {
    if (conn.toPort != AudioPortId.audioInL) continue;
    final dest = pluginsById[conn.toSlotId];
    if (dest is! AudioLooperPluginInstance) continue;

    final origin = pluginsById[conn.fromSlotId];
    if (origin == null) continue;

    final root = _walkUpstreamToSource(
      start: origin,
      pluginsById: pluginsById,
      graph: graph,
    );
    if (root == null) continue;

    final rootIndex = sourceIndexBySlotId[root.id];
    if (rootIndex == null) continue; // source unsupported on this backend

    looperSinks.add(
      LooperSinkEntry(clipSlotId: dest.id, sourceIndex: rootIndex),
    );
  }

  // ── Pass 4: VST3 routes ────────────────────────────────────────────────
  //
  // VST3 → VST3 audio routes are emitted only when the backend supports
  // VST3 hosting. On Android they are silently dropped.
  final vstRoutes = <VstRouteEntry>[];
  if (caps.supportsVst3) {
    for (final conn in graph.connections) {
      if (conn.fromPort != AudioPortId.audioOutL) continue;
      if (conn.toPort != AudioPortId.audioInL) continue;
      final from = pluginsById[conn.fromSlotId];
      final to = pluginsById[conn.toSlotId];
      if (from is Vst3PluginInstance && to is Vst3PluginInstance) {
        vstRoutes.add(
          VstRouteEntry(fromSlotId: from.id, toSlotId: to.id),
        );
      }
    }
  }

  return RoutingPlan(
    sources: List.unmodifiable(sources),
    insertChains: List.unmodifiable(dedupedChains),
    looperSinks: List.unmodifiable(looperSinks),
    vstRoutes: List.unmodifiable(vstRoutes),
    diagnostics: List.unmodifiable(diagnostics),
  );
}

// ── Chain collection helpers ────────────────────────────────────────────────

/// Walks downstream from [startSlotId] along [cable]: follows contiguous
/// GFPA effects, stopping when it reaches one of:
///   - the master mix (cable leads to a slot that consumes audio but is
///     not itself a chainable effect — e.g. an audio looper);
///   - a VST3 effect (destination = that plugin);
///   - a dead end (cable into nothing or a MIDI-only slot).
///
/// Returns a builder that carries the ordered effect list and the
/// destination; the caller is responsible for attaching the source
/// index(es) that feed the chain.
_ChainBuilder? _collectChainDownstream({
  required String startSlotId,
  required AudioGraphConnection cable,
  required Map<String, PluginInstance> pluginsById,
  required AudioGraph graph,
  required EffectHandleResolver resolveEffect,
  int maxHops = 16,
}) {
  final effects = <EffectEntry>[];
  ChainDestination destination = const ChainDestination.masterMix();
  var currentConn = cable;

  // Guards against cycles and pathological graphs. Cycles are prevented
  // elsewhere but the bound doubles as a belt-and-braces safety net.
  for (var hop = 0; hop < maxHops; hop++) {
    final next = pluginsById[currentConn.toSlotId];
    if (next == null) return null; // dangling cable

    // Audio looper as destination — emit chain to the looper, Pass 3
    // will hook it up to the correct source's capture buffer.
    if (next is AudioLooperPluginInstance) {
      destination = ChainDestination.looperClip(next.id);
      break;
    }

    // VST3 → chain terminates here (the VST3 will receive the signal
    // via its audio input).
    if (next is Vst3PluginInstance) {
      destination = ChainDestination.vst3Plugin(next.id);
      break;
    }

    // GFPA effect → accumulate and keep walking.
    if (_isGfpaEffect(next)) {
      final handle = resolveEffect(next);
      if (handle != null) {
        effects.add(EffectEntry(slotId: next.id, dspHandle: handle));
      }
      // Find this effect's outgoing audio cable, if any.
      final outgoing = graph.connections.where(
        (c) =>
            c.fromSlotId == next.id && c.fromPort == AudioPortId.audioOutL,
      ).firstOrNull;
      if (outgoing == null) {
        // Effect is a terminal sink (reverb into master mix).
        break;
      }
      currentConn = outgoing;
      continue;
    }

    // Anything else (another source, an instrument) — stop. The chain
    // walker is only meant to skip *effects*.
    return null;
  }

  return _ChainBuilder(effects: effects, destination: destination);
}

/// Climbs the audio graph from [start] through audio cables until a real
/// source is found. Used by Pass 3 to decide what the audio looper
/// should record when the cable to the looper passes through an effect
/// chain.
///
/// Returns [start] itself when it is already a source. Returns `null` if
/// the walk exceeds [maxHops] or the upstream cable leads nowhere.
PluginInstance? _walkUpstreamToSource({
  required PluginInstance start,
  required Map<String, PluginInstance> pluginsById,
  required AudioGraph graph,
  int maxHops = 16,
}) {
  PluginInstance? current = start;
  for (var hop = 0; hop < maxHops; hop++) {
    if (current == null) return null;
    if (_isAudioSource(current)) return current;

    // Current is a pure effect: find the cable feeding its audioInL.
    final upstream = graph.connections.where(
      (c) =>
          c.toSlotId == current!.id && c.toPort == AudioPortId.audioInL,
    ).firstOrNull;
    if (upstream == null) return null;

    current = pluginsById[upstream.fromSlotId];
  }
  return null;
}

// ── Internal chain builder ──────────────────────────────────────────────────

/// Mutable accumulator used during Pass 2. Converted to an immutable
/// [InsertChainEntry] by [build] once all fan-in sources have been
/// collected.
class _ChainBuilder {
  final List<EffectEntry> effects;
  final ChainDestination destination;
  final List<int> _sourceIndices = [];

  _ChainBuilder({required this.effects, required this.destination});

  void addSource(int index) {
    if (_sourceIndices.contains(index)) return;
    _sourceIndices.add(index);
  }

  /// Deduplication key. Two chains with the same effect sequence and
  /// destination are merged into a single entry with multiple source
  /// indices — this is how fan-in ("two keyboards → reverb → master")
  /// is represented in the plan.
  String dedupKey() {
    final effectKey = effects.map((e) => '${e.slotId}#${e.dspHandle}').join('>');
    final destKey = switch (destination.kind) {
      ChainDestinationKind.masterMix => 'master',
      ChainDestinationKind.vst3Plugin => 'vst3:${destination.slotId}',
      ChainDestinationKind.looperClip => 'looper:${destination.slotId}',
    };
    return '$effectKey|$destKey';
  }

  InsertChainEntry build() {
    return InsertChainEntry(
      sourceIndices: List.unmodifiable(_sourceIndices),
      effects: List.unmodifiable(effects),
      destination: destination,
    );
  }
}

