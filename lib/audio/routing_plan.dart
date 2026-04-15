// ============================================================================
// RoutingPlan — platform-agnostic description of how the audio graph should
// be executed on any real-time backend (JACK, CoreAudio, Oboe, WASAPI, AUv3).
//
// Phase A.1 of the audio routing redesign — see
// `docs/dev/AUDIO_ROUTING_REDESIGN.md`. This file introduces the **types**
// only; the plan builder (A.2) and the backend adapters (A.3 / A.4) will
// be added in follow-up sessions. Nothing in this file is referenced by
// the existing routing code yet, so the refactor is entirely additive.
//
// Design goals:
//   1. One canonical shape for topology. Every backend adapter reads the
//      same plan, so a source type added to the plan becomes audible on
//      every platform at once.
//   2. Pure Dart, no dart:ffi imports. The plan must be serialisable and
//      unit-testable against a fake backend.
//   3. Flat, ordered. The audio thread's job is to walk arrays, not to
//      traverse a graph.
//   4. Mono/stereo explicit. Today's callbacks pretend everything is
//      stereo; the mono-input Harmonizer regression showed why that's
//      wrong.
// ============================================================================

import 'package:flutter/foundation.dart' show immutable;

/// The kind of audio source a plan entry describes.
///
/// This is used by backend adapters to decide which native FFI call to
/// make when applying a [SourceEntry] — e.g. a JACK adapter registers a
/// `DvhRenderFn` for [SourceKind.renderFunction] and a VST3 plugin
/// ordinal for [SourceKind.vst3Plugin].
enum SourceKind {
  /// A native render function exposed as a C symbol — keyboards,
  /// theremin, stylophone, vocoder, live input, drum generator. The
  /// backend adapter resolves the function pointer from
  /// [SourceEntry.renderFnHandle].
  renderFunction,

  /// A VST3 plugin output, referenced by its ordinal in the topological
  /// processing order. Only usable on desktop backends — Android rejects
  /// VST3 entries at apply time.
  vst3Plugin,

  /// A shared bus slot on an Oboe / AAudio stream (Android only). The
  /// backend adapter calls `oboeStreamAddSource` with the slot ID held
  /// in [SourceEntry.busSlotId]. Desktop adapters ignore these.
  oboeBusSlot,
}

/// Audio channel count of a source. Explicit so downstream effects can
/// skip redundant processing on genuinely mono sources (see the 2.13.0
/// Harmonizer mono shortcut).
enum ChannelLayout {
  mono,
  stereo,
}

/// When should a source contribute samples to the master mix?
///
/// Distinguishes "always audible, even when not cabled" (GF Keyboard,
/// drum generator → percussion — their raw output is what the user hears
/// on a fresh rack) from "only when cabled into something downstream"
/// (theremin, stylophone, vocoder, live input — their raw path is either
/// silent by design or handled by a separate playback device, so the
/// JACK / CoreAudio thread should only pull them when they feed an
/// effect or a looper).
///
/// The builder places both strategies into the same `SourceEntry` list
/// and the backend adapter iterates by [masterMixStrategy] to decide
/// when to issue the native `addMasterRender` call.
enum MasterMixStrategy {
  alwaysRender,
  onlyWhenConnected,
}

/// Which native "capture mode" group a source belongs to, or `none` if
/// it has no capture-mode knob on the native side.
///
/// On the current desktop stack, theremin / stylophone / vocoder each
/// own a separate miniaudio playback device for their standalone sound.
/// When they are cabled into a JACK chain, that device must be silenced
/// (`*_set_capture_mode(true)`) so the JACK thread can drive the DSP
/// without double-rendering. Tracked here so the backend adapter can
/// batch a single `set_capture_mode` call per group based on whether
/// any source in the group is referenced by a chain or looper sink.
enum CaptureModeGroup {
  none,
  theremin,
  stylophone,
  vocoder,
}

/// One audio source in the plan.
///
/// A source produces samples into a stereo output buffer when invoked
/// by its backend. Every plugin instance that produces audio maps to
/// exactly one [SourceEntry] per plan.
@immutable
class SourceEntry {
  /// Rack slot ID of the plugin that owns this source. Used by backend
  /// adapters for logging and by the plan builder to resolve cables
  /// back to their owning slot.
  final String slotId;

  /// Discriminator used by the backend adapter to pick the right FFI
  /// path when applying this entry.
  final SourceKind kind;

  /// Opaque integer handle interpreted per [kind]:
  ///   - [SourceKind.renderFunction]: raw C function pointer address
  ///     returned by `...RenderFnAddr()` — handed to JACK / CoreAudio /
  ///     Oboe-bus as a `DvhRenderFn` or `AudioSourceRenderFn`.
  ///   - [SourceKind.vst3Plugin]: ordinal index in the processing order.
  ///   - [SourceKind.oboeBusSlot]: unused — see [busSlotId].
  final int renderFnHandle;

  /// Oboe / AAudio bus slot ID for [SourceKind.oboeBusSlot], or −1 when
  /// [kind] is not a bus-slot entry. Split out from [renderFnHandle] so
  /// the two fields can coexist for sources that register on Oboe *and*
  /// expose a desktop render function (e.g. the live input).
  final int busSlotId;

  /// Declared channel layout of the raw source output. Used by the
  /// Harmonizer and other heavy effects to skip redundant processing on
  /// known-mono inputs without having to do a per-block memcmp.
  final ChannelLayout channels;

  /// When the backend adapter should register this source with the
  /// master mix. See [MasterMixStrategy] for the two-case rationale.
  final MasterMixStrategy masterMixStrategy;

  /// Capture-mode group this source belongs to, or [CaptureModeGroup.none]
  /// when no `set_capture_mode` call is needed for this source kind.
  final CaptureModeGroup captureGroup;

  const SourceEntry({
    required this.slotId,
    required this.kind,
    required this.renderFnHandle,
    this.busSlotId = -1,
    this.channels = ChannelLayout.stereo,
    this.masterMixStrategy = MasterMixStrategy.onlyWhenConnected,
    this.captureGroup = CaptureModeGroup.none,
  });

  SourceEntry copyWith({
    String? slotId,
    SourceKind? kind,
    int? renderFnHandle,
    int? busSlotId,
    ChannelLayout? channels,
    MasterMixStrategy? masterMixStrategy,
    CaptureModeGroup? captureGroup,
  }) {
    return SourceEntry(
      slotId: slotId ?? this.slotId,
      kind: kind ?? this.kind,
      renderFnHandle: renderFnHandle ?? this.renderFnHandle,
      busSlotId: busSlotId ?? this.busSlotId,
      channels: channels ?? this.channels,
      masterMixStrategy: masterMixStrategy ?? this.masterMixStrategy,
      captureGroup: captureGroup ?? this.captureGroup,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SourceEntry &&
      other.slotId == slotId &&
      other.kind == kind &&
      other.renderFnHandle == renderFnHandle &&
      other.busSlotId == busSlotId &&
      other.channels == channels &&
      other.masterMixStrategy == masterMixStrategy &&
      other.captureGroup == captureGroup;

  @override
  int get hashCode => Object.hash(
        slotId,
        kind,
        renderFnHandle,
        busSlotId,
        channels,
        masterMixStrategy,
        captureGroup,
      );
}

/// One effect in an insert chain. The backend adapter uses [dspHandle]
/// as an opaque pointer to the pre-instantiated native DSP object — the
/// plan never creates or destroys effects, only references them.
@immutable
class EffectEntry {
  /// Rack slot ID of the effect plugin.
  final String slotId;

  /// Opaque native DSP handle (e.g. a `GfpaDspInstance*` cast to int).
  /// Lifetime is managed by the existing eager-instantiation path in
  /// [RackState]; the plan does not own the handle.
  final int dspHandle;

  const EffectEntry({
    required this.slotId,
    required this.dspHandle,
  });

  @override
  bool operator ==(Object other) =>
      other is EffectEntry &&
      other.slotId == slotId &&
      other.dspHandle == dspHandle;

  @override
  int get hashCode => Object.hash(slotId, dspHandle);
}

/// One insert chain: a set of sources summed together, run through a
/// series of effects, and routed to [destination].
///
/// Multiple sources feeding the same chain represent fan-in mixing
/// (e.g. two keyboards cabled to the same reverb). Empty [effects]
/// means "raw sum into destination" — used by the audio looper to
/// record a clean mix of cabled sources.
@immutable
class InsertChainEntry {
  /// Indices into [RoutingPlan.sources] that feed this chain. Ordering
  /// is stable but not semantically significant — the RT callback sums
  /// them before applying effects.
  final List<int> sourceIndices;

  /// Effects applied in series. Output of effect N is the input of
  /// effect N+1. Empty list means "no effects, pass-through".
  final List<EffectEntry> effects;

  /// Where the final post-chain signal goes.
  final ChainDestination destination;

  const InsertChainEntry({
    required this.sourceIndices,
    required this.effects,
    required this.destination,
  });

  @override
  bool operator ==(Object other) =>
      other is InsertChainEntry &&
      _listEquals(sourceIndices, other.sourceIndices) &&
      _listEquals(effects, other.effects) &&
      destination == other.destination;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(sourceIndices),
        Object.hashAll(effects),
        destination,
      );
}

/// Destination of an insert chain's final signal.
///
/// A chain can end at the master mix, at a VST3 plugin input (desktop
/// only), or at a looper clip (for post-effect recording — the 2.13.0
/// Live Input → Harmonizer → Looper case).
enum ChainDestinationKind {
  masterMix,
  vst3Plugin,
  looperClip,
}

@immutable
class ChainDestination {
  final ChainDestinationKind kind;

  /// Slot ID of the destination plugin (for vst3Plugin / looperClip)
  /// or `null` for master mix.
  final String? slotId;

  const ChainDestination.masterMix()
      : kind = ChainDestinationKind.masterMix,
        slotId = null;

  const ChainDestination.vst3Plugin(String this.slotId)
      : kind = ChainDestinationKind.vst3Plugin;

  const ChainDestination.looperClip(String this.slotId)
      : kind = ChainDestinationKind.looperClip;

  @override
  bool operator ==(Object other) =>
      other is ChainDestination &&
      other.kind == kind &&
      other.slotId == slotId;

  @override
  int get hashCode => Object.hash(kind, slotId);
}

/// The looper records the post-effect wet signal of the named source —
/// identified by its index into [RoutingPlan.sources]. The source index
/// (rather than the chain index) lets the backend adapter read from the
/// per-source `renderCapture[m]` buffer that the callback maintains.
@immutable
class LooperSinkEntry {
  /// Rack slot ID of the audio looper clip receiving this signal.
  final String clipSlotId;

  /// Index into [RoutingPlan.sources] of the (post-chain) capture buffer
  /// the looper should read from.
  final int sourceIndex;

  const LooperSinkEntry({
    required this.clipSlotId,
    required this.sourceIndex,
  });

  @override
  bool operator ==(Object other) =>
      other is LooperSinkEntry &&
      other.clipSlotId == clipSlotId &&
      other.sourceIndex == sourceIndex;

  @override
  int get hashCode => Object.hash(clipSlotId, sourceIndex);
}

/// A VST3-to-VST3 audio route. Desktop-only; ignored by the Android
/// backend adapter.
@immutable
class VstRouteEntry {
  final String fromSlotId;
  final String toSlotId;

  const VstRouteEntry({
    required this.fromSlotId,
    required this.toSlotId,
  });

  @override
  bool operator ==(Object other) =>
      other is VstRouteEntry &&
      other.fromSlotId == fromSlotId &&
      other.toSlotId == toSlotId;

  @override
  int get hashCode => Object.hash(fromSlotId, toSlotId);
}

/// Backend feature flags used by the plan *builder*, not by adapters.
///
/// The builder consults these to decide whether to emit, say, a VST3
/// route entry (desktop) or to prefer an Oboe bus slot over a render
/// function (Android). Adapters can still reject unsupported entries
/// at apply time as a defence in depth.
@immutable
class BackendCapabilities {
  final bool supportsVst3;
  final bool prefersOboeBus;
  final bool supportsMasterInsertChains;

  const BackendCapabilities({
    required this.supportsVst3,
    required this.prefersOboeBus,
    required this.supportsMasterInsertChains,
  });

  /// Capability profile for the Linux JACK host.
  static const jack = BackendCapabilities(
    supportsVst3: true,
    prefersOboeBus: false,
    supportsMasterInsertChains: true,
  );

  /// Capability profile for the macOS CoreAudio host. Same as JACK at
  /// the plan level; differences live inside the backend adapter.
  static const coreAudio = BackendCapabilities(
    supportsVst3: true,
    prefersOboeBus: false,
    supportsMasterInsertChains: true,
  );

  /// Capability profile for the Android Oboe/AAudio host. No VST3, and
  /// sources prefer the shared bus over raw render functions because
  /// `gfpa_audio_android` applies insert chains by bus slot ID.
  static const oboe = BackendCapabilities(
    supportsVst3: false,
    prefersOboeBus: true,
    supportsMasterInsertChains: true,
  );
}

/// Non-fatal warning emitted by the plan builder when it had to drop or
/// alter part of the user's cable graph to avoid a correctness failure.
///
/// The canonical case is the Phase H "shared effect" scenario: the user
/// cabled the same stateful GFPA DSP instance into two disjoint sub-
/// topologies (e.g. `kb1 → reverb` AND `kb2 → harmonizer → reverb`).
/// Stateful effects cannot be processed twice per audio block with
/// different inputs without corrupting their internal filter buffers,
/// so the builder keeps the first chain containing the shared effect
/// and drops the others. This diagnostic carries the information the
/// UI will eventually surface as a warning overlay.
@immutable
class RoutingDiagnostic {
  /// Kind of diagnostic — lets callers filter or bucket by category
  /// when the list grows beyond the current single entry.
  final RoutingDiagnosticKind kind;

  /// Human-readable explanation, suitable for a debugPrint or UI tooltip.
  /// No localisation — this is debug-facing for now.
  final String message;

  /// Slot ID of the plugin at the centre of the diagnostic. For
  /// `sharedStatefulEffect`, this is the effect slot that is referenced
  /// by more than one chain.
  final String slotId;

  const RoutingDiagnostic({
    required this.kind,
    required this.message,
    required this.slotId,
  });

  @override
  bool operator ==(Object other) =>
      other is RoutingDiagnostic &&
      other.kind == kind &&
      other.message == message &&
      other.slotId == slotId;

  @override
  int get hashCode => Object.hash(kind, message, slotId);

  @override
  String toString() =>
      'RoutingDiagnostic(kind: $kind, slot: $slotId, "$message")';
}

/// Discriminator for [RoutingDiagnostic].
enum RoutingDiagnosticKind {
  /// One GFPA DSP handle is referenced by more than one insert chain.
  /// Stateful effects (reverb, delay, chorus, harmonizer, …) cannot be
  /// shared across chains without corrupting internal state — see the
  /// v2.13.0 "gresillant" bug. The builder keeps the first occurrence
  /// and drops the rest.
  sharedStatefulEffect,

  /// One insert chain has multiple fan-in sources under the Oboe
  /// (Android) backend. Android's per-bus-slot chain model cannot run
  /// a single stateful DSP instance against more than one source
  /// without state corruption. The adapter commits the chain to the
  /// first source only; other sources in the same chain output dry.
  /// The user can work around this by creating one effect slot per
  /// source.
  androidFanInNotSupported,
}

/// The complete, flat, immutable description of how the audio graph
/// should be executed for one topology. Produced by the plan builder
/// (Phase A.2) and consumed by backend adapters (Phase A.3+).
///
/// Two plans compare equal if and only if their lists compare equal,
/// so the dirty-check in `RackState.syncAudioRouting` can short-circuit
/// identical topologies and avoid native FFI calls.
@immutable
class RoutingPlan {
  /// Every audio-producing slot in the rack, in a stable order. Chain
  /// and looper entries reference sources by their index in this list.
  final List<SourceEntry> sources;

  /// Every insert chain — including bare master renders (represented as
  /// a chain with empty effects and masterMix destination) and
  /// source → VST3 external renders.
  final List<InsertChainEntry> insertChains;

  /// Post-effect recording targets for the audio looper.
  final List<LooperSinkEntry> looperSinks;

  /// VST3 → VST3 routes (desktop only).
  final List<VstRouteEntry> vstRoutes;

  /// Non-fatal warnings from the builder. Callers should `debugPrint`
  /// these after applying the plan, and future UI work will surface
  /// them as patch-view overlays.
  final List<RoutingDiagnostic> diagnostics;

  const RoutingPlan({
    this.sources = const [],
    this.insertChains = const [],
    this.looperSinks = const [],
    this.vstRoutes = const [],
    this.diagnostics = const [],
  });

  /// Empty plan — applying it clears every native registry.
  static const empty = RoutingPlan();

  @override
  bool operator ==(Object other) {
    if (other is! RoutingPlan) return false;
    return _listEquals(sources, other.sources) &&
        _listEquals(insertChains, other.insertChains) &&
        _listEquals(looperSinks, other.looperSinks) &&
        _listEquals(vstRoutes, other.vstRoutes) &&
        _listEquals(diagnostics, other.diagnostics);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(sources),
        Object.hashAll(insertChains),
        Object.hashAll(looperSinks),
        Object.hashAll(vstRoutes),
        Object.hashAll(diagnostics),
      );
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
