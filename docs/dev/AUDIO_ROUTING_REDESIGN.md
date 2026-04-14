# Audio routing redesign — analysis & plan

> **Status:** Proposal, 2026-04-13. Drafted after the 2.13.0 Live Input session
> exposed how many files a new source slot requires.
> **Scope:** Dart routing sync layer + native real-time callbacks on Linux,
> macOS, Android, Windows, iOS.
> **TL;DR:** Staged refactor, **not** a rewrite. No Rust. ~1-week project.

---

## 1. Why we're here

Shipping the Live Input Source in v2.13.0 required edits in **seven** places
for a single feature:

1. `native_audio/audio_input.c` — capture passthrough + bus-render trampoline.
2. `lib/services/audio_input_ffi_native.dart` + stub — FFI bindings.
3. `lib/services/native_instrument_controller.dart` — rack lifetime.
4. `lib/services/live_input_source_engine.dart` — device picker + peak meter.
5. `lib/services/vst_host_service_desktop.dart` — desktop routing branch.
6. `lib/services/vst_host_service_desktop.dart` — Android routing branch
   (same file, separate function, zero shared logic).
7. `packages/flutter_midi_pro/android/src/main/cpp/*.cpp` — Oboe bus
   registration + `kMaxBusSlot` bump.

Then during debugging we found:

- A pre/post-chain capture bug that needed **two** identical fixes in
  `dart_vst_host_jack.cpp` and `oboe_stream_android.cpp` because the
  capture semantic is duplicated by copy-paste.
- A mono-input CPU overrun in the Harmonizer that no single component
  could diagnose in isolation — symptoms were in the AAudio callback,
  cause was in the DSP, fix is in a third file.

Every new source slot is going to repeat this pattern unless the
architecture changes.

---

## 2. Inventory of what exists today

### 2.1 Native audio backends (real-time callback ownership)

| Platform | Backend         | Callback owner                                     | Status |
|---       |---              |---                                                 |---     |
| Linux    | JACK            | `dart_vst_host_jack.cpp` — `_jackProcessCallback`  | ✅ Mature |
| macOS    | CoreAudio via miniaudio | `dart_vst_host_audio_mac.cpp`              | ✅ Works |
| Windows  | —               | `dart_vst_host_platform_stubs.cpp` (no-op)         | ⛔ Stub  |
| Android  | AAudio via Oboe | `oboe_stream_android.cpp` — `audioCallback`        | ✅ Works |
| iOS      | —               | No audio code                                      | ⛔ Missing |

### 2.2 Topology snapshot passing (Dart → RT callback)

- **Desktop (JACK + macOS)**: triple-buffered atomic swap. `RoutingSnapshot`
  is a flat POD with `orderedCount`, `routeCount`, `masterRenderCount`,
  `insertChainCount`, etc. Dart mutates authoritative vectors under
  `pluginsMtx`, `_publishSnapshot()` copies into the next write slot,
  `activeIdx.store(release)` publishes, callback does a single
  `load(acquire)`. RT-correct and elegant.
- **Android (Oboe)**: brief `std::lock_guard` at the top of the callback,
  copy of `g_sources[]` into stack memory, lock released. Simpler;
  works fine at current source counts.

Both are internally correct. **The problem is that they use different
data shapes and different APIs**, so the Dart side has to speak both.

### 2.3 Dart routing sync — the duplication

`lib/services/vst_host_service_desktop.dart`:

| Function                          | Lines | Purpose |
|---                                 |---    |---      |
| `syncAudioRouting` (desktop branch)| 393   | Walks graph, pushes to JACK host C API |
| `_syncAudioRoutingAndroid`         | 76    | Walks same graph, pushes to Android FFI |
| `_syncAudioLooperSourcesAndroid`   | ~60   | Android-only looper source resolver |
| `_resolveAndroidBusSlotId`         | ~30   | Source → bus slot ID mapping |
| `_addChainInsertsDesktop`          | ~40   | DFS downstream effect walker (desktop) |
| `_addChainInserts`                 | ~40   | DFS downstream effect walker (Android) |
| `_walkUpToAudioSource`             | ~40   | DFS upstream source walker (shared) |

**~500 lines of Dart doing the same topological walk twice** against two
different FFI surfaces. The Android and desktop branches share exactly
one helper (`_walkUpToAudioSource`, added in 2.13.0). Every other piece
of logic is duplicated by hand.

Every time a bug is found, the fix must be made in **both** branches.
Evidence: the 2.13.0 live input had three consecutive bugs requiring
simultaneous changes in both branches (resolver upstream walk, post-chain
capture, mono source detection).

### 2.4 Native registries — "eight buckets" problem

`dart_vst_host_jack.cpp` exposes eight separate registries the Dart side
has to remember to populate in the right order:

1. `plugins[]` — loaded VST3 plugin pointers
2. `processOrder[]` — topological processing order
3. `routes[]` — VST3 → VST3 audio routes
4. `externalRenders[]` — non-VST3 → VST3 routes
5. `masterRenders[]` — bare render contributors
6. `masterInsertChains[]` — fan-in source → effect chains
7. `renderCapture[m]` — per-source post-chain capture for looper read-back
8. `alooperSrc[c]` — per-clip audio looper source buffer

Oboe has a smaller equivalent set. Dart's routing sync has to correctly
populate each bucket for each source type without overlap.

### 2.5 Source types the router handles

Keyboard, Drum Generator, Theremin, Stylophone, Vocoder, Live Input,
VST3. That's **seven**. Every pair `(source, platform)` is a separate
code path in the Dart sync layer.

### 2.6 Total LOC in the routing + RT surface

| Component                               | LOC   |
|---                                      |---    |
| Dart routing sync (desktop + Android)   | ~590  |
| `dart_vst_host_jack.cpp`                | 1 017 |
| `dart_vst_host_audio_mac.cpp`           | ~800  |
| `gfpa_dsp.cpp` (shared Linux+macOS+Android) | 996 |
| `oboe_stream_android.cpp`               | 621   |
| `native_audio/audio_input.c`            | 1 942 |
| `native_instrument_controller.dart`     | 263   |
| **Total**                               | **~6 200** |

### 2.7 What's actually good

- **GFPA DSP is already unified** — one `gfpa_dsp.cpp` compiled into
  both `libdart_vst_host.{so,dylib}` and `libnative-lib.so`. No duplication.
- **JACK triple-buffered snapshot** is RT-correct and non-trivial to
  replicate. Throwing it away means re-debugging atomic ordering.
- **Oboe callback** is short, correct, and cleanly structured.
- **miniaudio capture** is reused by vocoder and live input — no duplication.

---

## 3. What a clean architecture would look like

### 3.1 One platform-agnostic routing plan

```
AudioGraph (Dart) ──walk once──▶ RoutingPlan (Dart POD) ──apply──▶ Native backend
                                                          (JACK | CoreAudio | Oboe | WASAPI | AUv3)
```

`RoutingPlan` is a flat, ordered description of what the audio thread
should do in one block:

```dart
class RoutingPlan {
  final List<SourceEntry>      sources;       // each has a render fn handle
  final List<InsertChainEntry> insertChains;  // (sources[], effects[])
  final List<LooperSinkEntry>  looperSinks;   // clip → [source indices]
  final List<RouteEntry>       vstRoutes;     // VST3 → VST3 (desktop only)
}
```

### 3.2 One source descriptor

Every plugin that can produce audio implements:

```dart
AudioSourceDescriptor? describeAudioSource(BackendCapabilities caps);
```

The descriptor carries: `kind`, `renderFnHandle` (opaque int address or
bus slot ID — backend decides), `channelCount`, and the rack slot ID.
Adding a new source is **implementing one method**, not editing seven
files.

### 3.3 One capture contract

`runInsertChain(input, output, captureSlot, chain)` is a single helper
defined in a shared C++ header (or just duplicated with a shared test
that guarantees bit-identical semantics). Both JACK and Oboe call it.
The "which buffer does the looper read from" question has exactly one
answer.

### 3.4 Backend adapters

Each backend adapter is ~200 lines:

- `applyPlanJack(RoutingPlan)` — already exists as `syncAudioRouting`,
  slimmed down.
- `applyPlanCoreAudio(RoutingPlan)` — similar, targets the mac host.
- `applyPlanOboe(RoutingPlan)` — replaces `_syncAudioRoutingAndroid` +
  friends.
- `applyPlanWasapi(RoutingPlan)` — new, unlocks Windows.
- `applyPlanAuv3(RoutingPlan)` — new, eventually unlocks iOS.

---

## 4. Should we rewrite from scratch? **No.**

**Arguments for full rewrite:**
- Current Dart routing layer is duplicated two ways and has grown
  organically. It's worth replacing.
- No Windows or iOS support. A clean slate makes adding them easier.

**Arguments against full rewrite:**
- It works. 2.13.0 ships real features on Linux, macOS, Android.
- The JACK triple-buffer is correct and was hard to get right; rewriting
  it risks regressing RT correctness for no user-visible benefit.
- Oboe callback is 140 lines and correct.
- `gfpa_dsp.cpp` is already unified.
- Solo dev, user-facing feature roadmap (Chord Progression, Phase 8, AUv3)
  is the real limiter on release velocity — not the audio engine.

**The pain is in the Dart routing sync and the pre/post-chain duplication,
not in the native callbacks.** Replacing just those is a 1-week project
with moderate risk. Replacing the whole audio engine is a 1-3 month
project with high regression risk and no new user-visible capability.

## 5. Should we move to Rust? **No, not yet.**

**Pro:**
- Memory safety, enforced atomic ordering, cross-platform FFI.

**Con:**
- Flutter/Rust bridge adds a new toolchain for a solo dev.
- The RT-critical parts are already in C/C++ and correct. Rust doesn't
  buy much when the lock-free constraints are the same.
- miniaudio, JACK, Oboe, FluidSynth are all C libraries — Rust would
  still call them via FFI, so the integration surface doesn't shrink.
- We'd be rewriting 6 200 LOC of working code to learn a new ecosystem.
- The problems we're fixing (duplication, registry sprawl) are solved
  in C++ by better data shapes, not by language choice.

**When Rust would make sense:** a new, isolated component with no
existing C dependency and a clear RT contract — e.g. a future bespoke
phase-vocoder library. Not a whole-engine rewrite.

---

## 6. Staged plan

All phases preserve the existing native callbacks and DSP — they only
reshape the **Dart routing sync** and the **shared C++ helpers** that
the callbacks call. Each phase ships behind a working build with
`flutter analyze` clean.

### Phase A — Unified `RoutingPlan` in Dart (~3–5 sessions)

**A.1 Define plan types** (this session, if approved)
- `lib/services/audio_routing_plan.dart` — pure Dart POD classes.
- No behavior change; compile + analyze clean.

**A.2 Build plan from `AudioGraph`**
- One pure function `buildRoutingPlan(rack, graph, caps)` in a new file.
- Single walk of the graph, single resolver, single upstream walker.
- No caller yet — tested via unit tests.

**A.3 Desktop adapter consumes plan**
- Rewrite `syncAudioRouting` desktop branch as a thin `applyPlanJack`.
- Before/after regression test: save a rack, compare native FFI call
  sequences.

**A.4 Android adapter consumes plan**
- Rewrite `_syncAudioRoutingAndroid` + friends as `applyPlanOboe`.
- Delete duplicated resolver / walker code.
- Expected net deletion: **~300 LOC**.

**A.5 Move upstream/downstream walks out of routing**
- Into the plan builder; they run once, not twice.

Acceptance: live input + harmonizer + looper works on Linux, macOS,
Android with identical user-observable behavior. Net code shrink ~300
LOC in Dart.

### Phase B — Source descriptor interface (~1–2 sessions)

- Add `AudioSourceMixin` / `describeAudioSource()` to
  `PluginInstance` subclasses that produce audio.
- Plan builder queries the mixin, not types.
- Effect of adding a new source type: **one file**.

### Phase C — Shared post-chain capture helper (~1 session)

- Extract `runInsertChain(…, captureDst)` into a header shared by
  `dart_vst_host_jack.cpp`, `dart_vst_host_audio_mac.cpp`, and
  `oboe_stream_android.cpp`.
- Delete the copy-pasted capture logic in each backend.
- Shared unit test: identical input → identical output across backends.

### Phase D — Windows backend (~2–3 sessions)

- New `dart_vst_host_wasapi.cpp` targeting WASAPI (or miniaudio's
  CoreAudio-style wrapper for unified latency tuning).
- `applyPlanWasapi(RoutingPlan)` adapter.
- Unblocked by phases A–C; no other dependency.

### Phase E — iOS backend (~deferred, AUv3 milestone)

- AudioUnit v3 host already planned for Phase 8b. That work becomes the
  iOS adapter for the unified plan.
- No extra cost beyond what 8b already carries.

### Phase F — VST3 ↔ GFPA effect interop (~2–3 sessions)

> **Known gap** surfaced during Phase A.3 manual smoke testing
> (2026-04-14). Cabling `VST3 instrument → GFPA effect (reverb /
> harmonizer / …)` has **never** worked on any platform. It was silently
> dropped by the pre-A.3 routing code and is still dropped by the new
> plan-driven adapter — faithful parity, not a regression.
>
> **Root cause** is native-side, not Dart:
>
> - `dart_vst_host_jack.cpp` has two parallel audio paths: the VST3
>   processing order (output → master mix, or → another VST3 via
>   `routeAudio`), and the master render list (render-function based,
>   with insert chains keyed by `DvhRenderFn`).
> - `addMasterInsert(renderFn, dspHandle)` is keyed by function pointer.
>   There is no equivalent that takes a VST3 plugin as the "source" of
>   the chain.
> - Android (`oboe_stream_android.cpp`) has the same shape: insert
>   chains are keyed by bus slot ID, and VST3 does not exist there at
>   all.
>
> **What a fix requires**:
>
> 1. New native concept: take a VST3 plugin's output bus as the source
>    of a GFPA chain, run the chain before mixing into master. Touches
>    `dart_vst_host_jack.cpp` callback + `dart_vst_host_audio_mac.cpp` +
>    the triple-buffered snapshot struct.
> 2. New FFI surface: `addVst3InsertChain(plugin, dspHandles[])`.
> 3. New Dart plan shape: `InsertChainEntry.sourceKind` extended, or a
>    parallel `Vst3InsertChainEntry` list — whichever keeps the adapter
>    simpler.
> 4. Looper capture semantics: VST3 → GFPA → Looper should record the
>    post-chain wet signal. This needs the shared post-chain helper from
>    Phase C to avoid yet another platform-specific hack.
>
> **Ordering**: deliberately placed **after** A.4 + C because Phase C's
> shared `runInsertChain(…, captureDst)` helper is the exact scaffolding
> this fix needs. Landing F before C would mean writing the VST3-source
> chain runner twice and then extracting it — wasted work.

Acceptance:
- VST3 instrument → GFPA reverb → master → audible reverberated VST3 on
  Linux, macOS, Android.
- VST3 instrument → GFPA effect → Audio Looper → recording captures the
  post-chain signal (mirrors the v2.13.0 Live Input → Harmonizer →
  Looper semantic).
- No regression for the nine existing-and-working source types.

### Phase H — Atomic chain commit (native API fix, ~1–2 sessions)

> **Known gap** surfaced during Phase A.4 manual smoke testing
> (2026-04-14). Cabling divergent topologies where the **same effect is
> reachable from multiple upstream sources** produces crackling audio
> and callback overruns on all platforms. Example: `kb1 → reverb`,
> `kb2 → harmonizer → reverb`, `theremin → harmonizer → reverb` —
> with all four cables present, every note grates and the AAudio log
> shows `VERY LATE 98 ms` repeating.
>
> **Root cause is in the native chain-builder**, not in Dart or the A.3
> adapter:
>
> 1. The native `dvh_add_master_insert(source, insertFn, userdata)` API
>    has a three-stage heuristic (`dart_vst_host_jack.cpp` lines 731–774):
>    - **Stage 1**: if any existing chain already contains `userdata`,
>      merge `source` into that chain's source list.
>    - **Stage 2**: if any existing chain already contains `source`,
>      append `userdata` to its effect list.
>    - **Stage 3**: create a brand-new chain.
> 2. Stage 1 fires before Stage 2, so calls that register the same
>    effect for a second source *always* merge the source into the
>    original chain even when the second source has its own upstream
>    chain with different earlier effects.
> 3. For the topology above, this produces two chains:
>    - `[kb1, kb2, theremin] → [reverb]` (wrong: kb2 and theremin
>      bypass the harmonizer)
>    - `[kb2, theremin] → [harmonizer]` (wrong: no downstream reverb
>      and the source render fns are called a second time in the same
>      block).
> 4. The JACK callback then:
>    - Calls `kb2_render` and `theremin_render` **twice per block**,
>      which advances their FluidSynth / miniaudio state twice — the
>      second read produces phase-discontinuous samples, hence the
>      crackling.
>    - Blows past the RT deadline because the harmonizer and reverb
>      each process more sources than they should.
>
> **What a fix requires**:
>
> 1. New native entry point:
>    ```c
>    void dvh_set_master_insert_chain(
>        DVH_Host host,
>        DvhRenderFn* sources, int sourceCount,
>        GfpaInsertFn* effectFns, void** effectUserdatas, int effectCount);
>    ```
>    Creates one `FlatInsertChain` atomically with an explicit
>    `(sources[], effects[])` pair — no merge heuristic, no ordering
>    dependency.
> 2. Mirror on macOS (`dart_vst_host_audio_mac.cpp`) and Android
>    (`gfpa_audio_android.cpp` — per-bus-slot chain replacement,
>    matching the new semantic).
> 3. Dart wrapper in `packages/flutter_vst3/dart_vst_host/lib/src/host.dart`.
> 4. A ~30-line change in `_applyPlanDesktop` / `_applyPlanAndroid` to
>    emit one `setMasterInsertChain` call per `InsertChainEntry` in the
>    plan, replacing the current `addMasterInsert` loop that triggers
>    the merge heuristic.
>
> **Ordering**: sit alongside Phase F in a single "native API extensions"
> session because F also touches `dart_vst_host_jack.cpp` and the
> snapshot struct. Landing F + H together avoids a second RT-callback
> review and lets both fixes share the Phase C shared-capture helper.
>
> **User workaround until the fix lands**: avoid cabling the same effect
> from more than one upstream chain. Route each source through its own
> distinct effect chain (duplicate effect slots if needed), or keep
> chain-shared effects as a terminal stage that no other source
> branches around.

Acceptance:
- `kb1 → reverb`, `kb2 → harmonizer → reverb`, `theremin → harmonizer →
  reverb` produces clean audio on Linux, macOS, Android.
- No crackling, no callback overruns under the same load.
- No regression for every topology that worked under Phase A.

---

## 7. Risk & mitigation

| Risk | Mitigation |
|---|---|
| RT correctness regression on JACK | Don't touch the JACK callback or snapshot publisher in phases A–B. Only replace the Dart caller. |
| Android source routing regression | `applyPlanOboe` is a transliteration of current logic against the same FFI calls. Ship desktop adapter first, validate, then Android. |
| Platform drift (Linux fixed, Android still broken) | Shared `RoutingPlan` means both platforms see the same facts. Diffs between platforms become expressible as backend capability flags, not code paths. |
| Refactor-in-the-dark | Each phase ships a green build. If Phase A.4 hits a wall we still have A.1–A.3. No big-bang landing. |

---

## 8. Decision

**Recommended:** proceed with **Phase A**, starting with **A.1** (pure
type definitions) in the current session. Evaluate after A.1 ships and
Before committing to A.2.

**Rejected for now:**
- Full engine rewrite in C++.
- Rust migration.
- Adding Windows or iOS *before* Phases A–C land (the new backend would
  inherit today's mess).

---

## 9. Open questions

- Do we want `RoutingPlan` to be immutable (copy-on-write) or mutable
  with a snapshot at apply time? Leaning immutable — it's built once
  per topology change, throughput is not a concern here.
- Should the plan builder live in `lib/services/` or in a new
  `lib/audio/` subtree? Neutral; `lib/audio/` would make the new
  boundary visually obvious.
- Should we introduce a unit-testable `FakeBackend` for the plan? Yes,
  essential for A.2 to land with confidence.
