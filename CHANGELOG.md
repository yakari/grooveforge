# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [X.x.x]

### Added
- **Global MIDI CC bindings for Looper** — five new system action codes (1009-1013) can be mapped to any hardware CC knob/button in the CC Preferences screen: Record/Stop Rec, Play/Pause, Overdub, Stop, and Clear All. When triggered, the action is dispatched to the single active MIDI Looper slot.
- **Global CC for channel mute/unmute (1014)** — a new system action code lets a single hardware CC toggle the mute state of any set of MIDI channels simultaneously. In the CC Preferences dialog, selecting the "Mute / Unmute Channels" action reveals a channel-selection checklist (Ch 1–16); the chosen channels are persisted with the mapping. This is useful for, e.g., silencing the vocoder channel while keeping a backing instrument playing without unplugging cables.
- **Single-instance enforcement for Jam Mode and MIDI Looper** — the "Add Plugin" sheet now checks for an existing Jam Mode or Looper before inserting a new one. If one is already present, the sheet closes and a SnackBar explains that only one instance is allowed. This prevents incoherent multi-looper setups and simplifies CC mapping.
- **Record-stop quantization (6.7)** — each looper track now has an individual quantize setting (off / 1/4 / 1/8 / 1/16 / 1/32). When set, all recorded event beat-offsets are snapped to the nearest grid line the moment the user presses stop. A minimum one-grid-step gap between paired note-on and note-off is enforced to prevent zero-duration notes. The setting is stored in `LoopTrack.quantize`, persisted in `.gf` project files, and defaults to `off`.
- **Quantize chip in transport strip** — a compact "Q:…" chip (amber, cycles on tap) has been added to the transport strip next to CLEAR, at the slot level. Set it before recording; the grid applies to every subsequent recording pass (first-pass and overdubs).

### Fixed
- **Jam Mode and Looper rack headers incorrectly highlighted / never highlighted** — Jam Mode and Looper slots have no MIDI channel (`midiChannel == 0`), mapping to channel index 0 — the same as any instrument on MIDI channel 1. Pressing a key on an unconnected Virtual Piano updated `channels[0].activeNotes`, causing both racks to flash blue even without a cable connection, while they never lit up for their own activity. Fixed by routing each plugin type to its own reactive listener: Looper glows when `LooperSession.isPlayingActive` is true (actively sending MIDI to connected slots), Jam Mode glows only when enabled AND the master channel is actively sending input matching the Detect setting (bass-note mode: at least one key held; chord mode: a chord recognised), and instrument slots continue to glow on `channelState.activeNotes`.
- **Pitch bend / CC not forwarded through VP → instrument cable (external MIDI)** — external MIDI pitch-bend (0xE0), control-change (0xB0), and channel-pressure (0xD0) messages received on a Virtual Piano slot's channel are now forwarded through its MIDI OUT cable to every connected downstream slot. Previously only Note On/Off were relayed; expression messages were silently dropped.
- **Pitch bend / CC not forwarded through VP → instrument cable (on-screen piano)** — sliding a finger on the Virtual Piano widget (pitch bend, vibrato, any CC gesture) now also forwards through the VP's MIDI OUT cable to connected slots. Previously these gestures called `AudioEngine` directly on the VP's own channel, bypassing cable routing entirely.
- **Pitch bend inoperative on the Vocoder** — the Vocoder carrier oscillator now responds to MIDI pitch bend. A new `VocoderPitchBend` C FFI function updates a `g_pitchBendFactor` multiplier applied in `renderOscillator()` across all four waveform modes (Saw, Square, Choral, Natural/PSOLA). Bend range is ±2 semitones (VST convention).
- **Vibrato (CC#1 / mod wheel) inoperative on the Vocoder** — added a 5.5 Hz LFO to the vocoder carrier oscillator driven by CC#1 (modulation wheel). Depth 0 = no vibrato; depth 127 = ±1 semitone modulation. A new `VocoderControlChange` C FFI function and `g_vibratoDepth` global control the depth; `g_effectivePitchFactor` now combines both pitch bend and vibrato for a single multiply in `renderOscillator`.
- **Pitch bend / CC not sent to VST3 plugins via cable** — `VstHostService` now exposes `pitchBend()` and `controlChange()` methods so that expression messages arriving via VP cable routing reach VST3 instrument plugins (effective once the native `dart_vst_host` binding is added).
- **Soundfont volume too low** — FluidSynth's built-in default gain (0.2) produced ~0.1 amplitude, far quieter than typical VST output. Raised to 5.0 on both Linux (CLI `-g 5` flag) and Android (`synth.gain` in native-lib.cpp), bringing soundfonts in line with the rest of the audio graph.
- **"Pin below transport" Jam Mode shortcut** — the pin toggle in the Jam Mode rack slot now works as intended. Pinning a Jam Mode slot inserts a compact one-liner strip (slot name · ON/OFF LED · live scale LCD) directly below the transport bar for quick control without scrolling. Pin state is persisted in `.gf` project files.
- **"Pin below transport" looper shortcut** — the pin toggle in the looper rack slot now works as intended. Pinning a looper inserts a compact one-liner control strip (slot name · LOOP · STOP · CLEAR · Q chip · state LCD) directly below the transport bar so the user can control the looper from anywhere without scrolling to its rack slot.

## [2.5.0] - 2026-03-13

### Added
- **MIDI Looper (Phase 7.1–7.4)** — new multi-track MIDI looper rack slot (`LooperPluginInstance`) with MIDI IN / MIDI OUT jacks in the patch view. Record MIDI from any connected source, loop it back to instrument slots, and overdub additional layers in parallel.
- **LooperEngine service** — beat-accurate 10 ms playback engine with bar-quantised loop lengths, smart downbeat sync, per-track mute/reverse/half-speed/double-speed modifiers, and per-bar chord detection via `ChordDetector`. State machine: idle → armed → recording → playing → overdubbing.
- **LoopTrack model** — serialisable MIDI event timeline with beat-offset timestamps, speed modifiers, reverse flag, mute state, and a per-bar chord grid (`Map<int, String?>`).
- **Looper front-panel UI** — hardware-style slot panel with REC / PLAY / OVERDUB (amber layers icon) / STOP / CLEAR transport buttons; state LCD badge; per-track chord grid (horizontally scrollable bar cells); mute (M), reverse (R), and speed (½× / 1× / 2×) per-track controls; pin-below-transport toggle.
- **Overdub** — dedicated OD button (amber, layers icon) enabled only while a loop is playing. Pressing it starts a new overdub layer; pressing again stops the overdub pass and resumes clean playback. REC button is disabled during play to prevent accidental first-pass overwrite.
- **Looper persistence** — recorded tracks and chord grids are saved in `.gf` project files under `"looperSessions"` and restored on project open/autosave reload.
- **Hardware CC assignment** — bind any CC to looper actions (toggle-record, toggle-play, stop, clear) per slot.
- **Add Plugin sheet** — "MIDI Looper" tile added (green loop icon).
- 20 new localised strings for the looper UI (EN + FR).

### Fixed
- **Linux audio silence after looper repeat** — FluidSynth stdout/stderr were never drained, causing the OS pipe buffer (~64 KB) to fill up after prolonged looper playback. Once full, FluidSynth blocked on its own output writes, stopped reading from stdin, and all note-on/note-off commands silently dropped — producing stuck held notes followed by total silence from all sources (looper, MIDI keyboard, on-screen piano). Fixed by draining both streams immediately after `Process.start` and adding the `-q` (quiet) flag to reduce FluidSynth's output volume.
- **Save As… crash** — `ProjectService` was registered as `Provider` instead of `ChangeNotifierProvider`, causing an unhandled exception when `context.read<ProjectService>()` was called from `rack_screen.dart`. Fixed by changing to `ChangeNotifierProvider`.
- **Splash screen ProjectService isolation** — splash screen now uses the shared `Provider`-registered `ProjectService` instance (via `context.read`) instead of creating a local instance, so autosave path and project state are consistent between screens.
- **Looper not recording from GFK on-screen keys** — on-screen piano key presses for `GrooveForgeKeyboardPlugin` (and other non-VP, non-VST3 slots) now also feed any looper connected via a MIDI OUT cable in the patch view. Previously only `VirtualPianoPlugin` slots dispatched through cables; GFK called FluidSynth directly and bypassed the looper entirely.
- **Looper not recording from external (hardware) MIDI on GFK channel** — `_routeMidiToVst3Plugins` in `rack_screen.dart` now also looks up GFK slots for the incoming MIDI channel and calls `_feedMidiToLoopers` as a side-effect, so a hardware controller playing on a GFK channel is captured by a connected looper. FluidSynth still plays in parallel (return value unchanged for pure GFK channels).
- **Looper chord grid not refreshing during recording** — `LooperEngine._detectBeatCrossings` now calls `notifyListeners()` when a bar-boundary chord flush occurs, so the chord grid in `LooperSlotUI` updates in real time without waiting for a state-machine transition.
- **Loops lost on app restart** — the autosave callbacks (`rack.onChanged` and `audioGraph.addListener`) are now registered **after** `loadOrInitDefault` completes in `splash_screen.dart`. Previously, `audioGraph.notifyListeners()` fired synchronously during `audioGraph.loadFromJson` — before `looperEngine.loadFromJson` was called — triggering an autosave that captured an empty looper and overwrote the persisted session data.
- **Missed playback events / skipped notes** — looper playback now uses `LooperSession.prevPlaybackBeat` (the actual transport beat at the end of the previous tick) to define the event window. Previously a hardcoded `0.01 × bpm / 60` estimate was used, which silently skipped events whenever the Dart timer fired late (GC pause, heavy UI frame).
- **Stuck notes and progressive chord decay** — notes held past the loop boundary (no note-off recorded) no longer ring indefinitely. `LoopTrack.activePlaybackNotes` tracks which notes are "on" during playback; at wrap-around the looper sends note-offs before the next iteration begins; at stop/pause/transport-stop all held notes are silenced. Eliminates the FluidSynth voice-stealing that caused a 3-note chord to lose one note per loop iteration.

## [2.4.0] - 2026-03-12

### Added
- **Audio Signal Graph** — directed graph model (`AudioGraph` service) connecting rack slots with typed ports: MIDI IN/OUT (yellow), Audio IN/OUT L/R (red/white), Send/Return (orange), and Data chord/scale ports (purple for Jam Mode). Validates port compatibility, prevents duplicate edges, and enforces cycle detection via DFS.
- **"Back of Rack" patch view** — toggle via the cable icon in the app bar. The rack flips to show each slot's back panel with coloured virtual jacks. MIDI/Audio cables are drawn as bezier curves with natural downward sag; data cables (chord/scale routing) are rendered in purple and stay in sync with the Jam Mode dropdowns.
- **Cable interactions** — long-press an output jack to start drawing a cable; compatible input jacks pulse; drop on a valid target to create the connection. Tap a cable to disconnect it via a context menu. Incompatible drops are silently ignored.
- **VirtualPianoPlugin** — a new addable slot type (addable from "Add Plugin") with a real MIDI channel, an on-screen piano keyboard, and MIDI IN / MIDI OUT / Scale IN jacks in the patch view. MIDI OUT is aligned with the same position as other slots. Touch-keyboard notes are forwarded through drawn MIDI cables to connected target slots (VST3 or FluidSynth). Jam Mode's Scale OUT can be wired to its Scale IN jack to enable scale locking for VST instruments.
- **Audio graph persistence** — all MIDI/Audio cable connections are saved and restored in `.gf` project files under the `"audioGraph"` key. Data connections continue to be stored per-plugin in `masterSlotId`/`targetSlotIds`.
- **Slot cleanup** — removing a rack slot automatically disconnects all its MIDI/Audio cables from the graph.
- 20 new localised strings for the patch view UI (EN + FR).
- **User guide "Rack & Cables" tab** — new fifth tab in the in-app user guide covering patch view toggle, jack types, cable drawing, disconnecting, data cable/Jam Mode sync, and the Virtual Piano slot.
- **Cable disconnect badge** — visible ✕ badge drawn at each cable's midpoint with a 48 dp tap zone; `HitTestBehavior.opaque` ensures the badge reliably receives taps.
- **Add Plugin sheet scrollable** — sheet now uses `isScrollControlled: true` and `SingleChildScrollView`, preventing overflow on small or crowded screens.

### Fixed
- **Scale lock on individual key taps** — `VirtualPiano._onDown` now applies `_validTarget` snapping before calling `onNotePressed`, so tapping a single invalid key redirects to the nearest valid pitch class (same behaviour as glissando). The same fix applies to glissando note transitions in `_onMove`: the snapped pitch is stored in `_pointerNote` and forwarded to the callback instead of the raw key under the finger. This matters especially for VP→VST3 cable routing which bypasses the engine's internal snapping.
- **External MIDI through Virtual Piano** — incoming MIDI on a VP's channel is now forwarded through its MIDI OUT cable connections (respecting scale lock/Jam Mode snapping), so a hardware MIDI controller can drive a VST3 instrument via the VP routing chain. Previously, external MIDI on a VP channel fell through to FluidSynth (silent/wrong sound) and never reached the downstream VST.

### Fixed
- **Scale lock on individual key taps** — `VirtualPiano._onDown` now applies `_validTarget` snapping before calling `onNotePressed`, so tapping a single invalid key redirects to the nearest valid pitch class (same behaviour as glissando). The same fix applies to glissando note transitions in `_onMove`: the snapped pitch is stored in `_pointerNote` and forwarded to the callback instead of the raw key under the finger.
- **External MIDI through Virtual Piano** — incoming MIDI on a VP's channel is now forwarded through its MIDI OUT cable connections (respecting scale lock/Jam Mode snapping), so a hardware MIDI controller can drive a VST3 instrument via the VP routing chain. Previously, external MIDI on a VP channel fell through to FluidSynth (silent/wrong sound) and never reached the downstream VST.
- **VST3 pitch off by ~1.5 semitones on Linux** — the ALSA audio state had a hardcoded default sample rate of 44100 Hz while VST3 plug-ins were resumed at 48000 Hz, causing the audio output to play back at the wrong speed. `dvh_start_alsa_thread` now reads `sr` and `maxBlock` from the host configuration so ALSA opens at the same rate the plug-ins use.

### Architecture
- `AudioPortId` enum with colour, direction, family, and compatibility helpers.
- `AudioGraphConnection` model with canonical composite ID (no UUID dependency).
- `PatchDragController` ChangeNotifier for live cable drag state.
- `RackState` now receives `AudioGraph` as a constructor parameter (`ChangeNotifierProxyProvider3`).
- `ProjectService` methods gain an `AudioGraph` parameter; autosave is also triggered on graph mutations.
- `PatchCableOverlay` uses per-midpoint `Positioned` tap zones computed via `addPostFrameCallback` after each paint; no full-screen gesture interceptor.
- `DragCableOverlay` is a `StatefulWidget` with an internal `ListenableBuilder` so it repaints on pointer-move without a parent `Consumer`.
- **Native audio graph execution** — `dart_vst_host` ALSA/CoreAudio loop gains `dvh_set_processing_order` (topological order) and `dvh_route_audio` / `dvh_clear_routes` (signal routing). When a VST3 audio cable is drawn in the patch view, the source plugin's output is fed directly into the destination plugin's audio input; the source is no longer mixed into the master bus. Plugins with no outgoing audio cable continue mixing directly to the master output. Dart-side sync via `VstHostService.syncAudioRouting` is triggered whenever the `AudioGraph` changes or a slot is added/removed.
- `GraphImpl::process()` in `dart_vst_graph` now uses Kahn's topological sort so nodes are always processed in dependency order (sources before effects), replacing the previous naïve index-order traversal.
- `dvh_graph_add_plugin` added to the `dart_vst_graph` C API — wraps an already-loaded `DVH_Plugin` as a non-owning node so external plugin managers can participate in the graph without transferring lifecycle responsibility.

## [2.3.0] - 2026-03-11

### Added
- **Global transport engine**: a new `TransportEngine` service tracks BPM (20–300), time signature, play/stop state, and swing. Changes are propagated live to all loaded VST3 plugins via `dvh_set_transport` → `ProcessContext`, so tempo-synced effects (LFOs, delays, arpeggiators) instantly lock to the app BPM.
- **Transport bar** in the `RackScreen` app bar: inline BPM field (tap to type), **`−` / `+` nudge buttons** (tap ±1 BPM; hold for rapid repeat — 400 ms initial delay then 80 ms intervals), **scroll-wheel on BPM display** (scroll up/down ±1 BPM), **Tap Tempo** button (averages the last 4 taps, rejects outliers), **▶ / ■ Play/Stop** toggle, **time signature selector**, **beat-pulse LED** (flashes amber on every beat, red on downbeat with fade animation), and **audible metronome toggle** (🎵 icon; GM percussion click via FluidSynth / flutter_midi_pro channel 9 — side-stick on downbeat, high-wood-block on other beats).
- **Transport state saved/restored** in `.gf` project files: BPM, time signature, swing, and `metronomeEnabled` are preserved per project. Missing `transport` key in older files defaults to `120 BPM / 4/4 / metronome off`.
- **Jam Mode BPM lock** — fully functional end-to-end: the `Off / 1 beat / ½ bar / 1 bar` sync setting in each Jam Mode slot now gates scale-root changes at beat-window boundaries (wall-clock based, derived from live BPM). Both the piano shading and the note snapping use the same locked pitch-class set — what you see highlighted is exactly what you hear.
- **Walking bass scale persistence**: when the master channel has no active notes (bass note released between steps), the last known bass scale is cached in `_lastBassScalePcs` so follower channels continue snapping correctly across note transitions.
- **`bpmLockBeats` wired end-to-end**: the beat-lock setting flows from the Jam Mode UI → `plugin.state` → `RackState._syncJamFollowerMapToEngine` → `GFpaJamEntry.bpmLockBeats` → `AudioEngine._shouldUpdateLockedScale()`.
- **Forward-compatibility reserved keys**: `"audioGraph": { "connections": [] }` and `"loopTracks": []` added to newly created `.gf` files (empty — prevents format churn when Phases 5 and 7 land).

### Fixed
- **Jam Mode chord scale locking**: snapping and piano shading now always use the same `_getScaleInfo(chord, scaleType)` function. Previously, Gemini-introduced code routed snapping through `GFJamModePlugin.processMidi` (which used `chord.scalePitchClasses` — the raw chord-detector output) while the shading used the chord-quality × scale-type matrix. For Jazz, Pentatonic, Blues, Classical and all non-Standard scale types, the two diverged — played notes no longer matched highlighted keys. Snapping is now always done directly via `_snapKeyToGfpaJam`, which calls `_getScaleInfo` identically to the shading logic.
- **Jam Mode MIDI input locking**: external MIDI keyboard notes on a follower channel are now correctly snapped. The broken plugin-registry routing introduced by a previous refactor is removed; all paths go through `_snapKeyToGfpaJam`.
- **Snap algorithm direction restored**: all three snapping paths (scale lock, GFPA jam, virtual piano) now use the original DOWN-first tie-breaking preference (nearest lower neighbor wins on equidistant candidates), matching the pre-regression behaviour.

### Architecture
- `TransportEngine` now runs a `Timer.periodic(10 ms)` ticker while playing; it advances `positionInBeats` / `positionInSamples` by wall-clock elapsed microseconds, fires `onBeat(isDownbeat)` on each beat boundary, increments `ValueNotifier<int> beatCount` (for UI pulse), and calls `_syncToHost()` every tick so VST3 plugins always read an accurate playhead position.
- `TransportEngine.onBeat` callback is wired by `RackState` to call `AudioEngine.playMetronomeClick(isDownbeat)` when `metronomeEnabled` is true.
- `AudioEngine.bpmProvider` / `isPlayingProvider` — lightweight function-reference callbacks injected by `RackState`; the audio engine reads live transport state without a hard import dependency on `TransportEngine`.
- `AudioEngine._bpmLockedScalePcs` — per-follower-channel cache of the currently committed locked scale pitch-class set, shared by both the piano shading propagation (`_performChordUpdate`) and the note snapper (`_snapKeyToGfpaJam`).
- `AudioEngine._lastScaleLockTime` — wall-clock timestamp per follower channel; `_shouldUpdateLockedScale()` compares elapsed time against `bpmLockBeats × 60 / bpm` ms to gate updates.

---

## [2.2.1] - 2026-03-11

### Added
- **GrooveForge Keyboard VST3 plugin**: Distributable `.vst3` bundle (Linux) that runs inside any VST3-compatible DAW (Ardour, Reaper, etc.) without requiring the GrooveForge app. MIDI in → FluidSynth → stereo audio out. Parameters: Gain, Bank, Program.
- **GrooveForge Vocoder VST3 plugin**: Distributable `.vst3` bundle (Linux) implementing the sidechain vocoder pattern standard in professional DAWs. Route any audio track as the carrier signal via the DAW's sidechain bus; play MIDI notes to control pitch. Parameters: Waveform, Noise Mix, Bandwidth, Gate Threshold, Env Release, Input Gain.
- **`vocoder_dsp.h/c`**: Context-based vocoder DSP library extracted from `audio_input.c` — no audio-backend dependencies, usable from both the GFPA plugin and the VST3 bundle.
- **Flatpak DAW compatibility**: Both bundles load correctly inside sandboxed Flatpak builds of Ardour/Reaper. Achieved by statically linking FluidSynth (built from source with all audio backends disabled), inlining math functions with `-ffast-math`, and patching all `$ORIGIN` RPATHs via `scripts/bundle_deps.sh`.
- **`scripts/bundle_deps.sh`**: Shell script that recursively bundles shared library dependencies into a `.vst3` bundle and patches all RPATHs to `$ORIGIN` for self-contained deployment.
- **VST3 build documentation**: Comprehensive `packages/flutter_vst3/vsts/README.md` covering plugin properties, build instructions, Flatpak compatibility notes, a GFPA vs VST3 comparison table, and a troubleshooting guide.

### Architecture
- Pure C++ VST3 plugins using the Steinberg VST3 SDK (MIT since v3.8) — no Dart or Flutter runtime required in the DAW.
- `grooveforge_keyboard.vst3`: single compilation unit (`factory.cpp` includes `processor.cpp` + `controller.cpp`), FluidSynth statically linked via CMake `FetchContent` (v2.4.0 built from source), Linux `ModuleEntry`/`ModuleExit` entry points via `linuxmain.cpp`.
- `grooveforge_vocoder.vst3`: same single-TU pattern, `vocoder_dsp` static library compiled with `-fPIC -ffast-math`, zero external runtime dependencies.
- `make keyboard` / `make vocoder` / `make grooveforge` targets perform a real `cp -rL` install to `~/.vst3/` (no symlinks — required for Flatpak sandbox compatibility).

---

## [2.2.0] - 2026-03-09

### Added
- **GrooveForge Plugin API (GFPA)**: A pure-Dart extensible plugin system, platform-independent (Linux, macOS, Windows, Android, iOS). Defines typed interfaces: `GFInstrumentPlugin` (MIDI in → audio out), `GFEffectPlugin` (audio in → audio out), `GFMidiFxPlugin` (MIDI in → MIDI out). Ships as a standalone `packages/grooveforge_plugin_api/` package with no Flutter dependency, enabling third-party plugins.
- **`packages/grooveforge_plugin_ui/`**: Flutter companion package exposing reusable UI helpers — `RotaryKnob`, `GFParameterKnob`, `GFParameterGrid` — for rapid plugin UI development.
- **Vocoder as a standalone GFPA slot**: The vocoder is now its own rack slot with a dedicated MIDI channel, piano, and controls. Multiple vocoders can coexist independently in the same project.
- **Jam Mode GFPA plugin**: A full `GFMidiFxPlugin` implementation with a complete UI overhaul inspired by the Roland RC-20.
  - Signal-flow row: MASTER dropdown → amber LCD (live scale name + type tag) → TARGETS chips.
  - LCD doubles as a scale-type selector; displays `[SCALE TYPE]` bracket only for families where the name is not self-describing (Standard, Jazz, Classical, Asiatic, Oriental).
  - Glowing LED enable/disable button with ON/OFF indicator.
  - **Multiple targets**: one Jam Mode slot can control any number of keyboard and vocoder slots simultaneously.
  - **Bass note detection mode**: uses the lowest active note on the master channel as the scale root — ideal for walking-bass lines.
  - **BPM sync lock** (Off / 1 beat / ½ bar / 1 bar): scale root changes only on beat boundaries (activates fully when Phase 4 transport lands).
  - Responsive layout: wide two-row panel (≥480 px); narrow stacked column (<480 px); controls strip reflows with `Wrap` on very small screens.
  - Key borders and wrong-note dimming settings moved from Preferences into the Jam Mode rack slot.
- **Default project template**: new projects start with two keyboard slots and a pre-configured Jam Mode slot (master = CH 2, target = CH 1, inactive by default).
- **`GFpaPluginInstance` model**: serializes/deserializes as `"type": "gfpa"` in `.gf` files; supports multiple `targetSlotIds` (backward-compatible with old single `targetSlotId` string).
- **GFPA plugin registry** (`GFPluginRegistry`): singleton registry for all built-in and future third-party plugins.

### Changed
- Scale name display in the Jam rack now shows the full `"C Minor Blues"` form (root note + scale name); the `[TYPE]` bracket is shown only when the scale family does not already encode the type.
- Virtual keyboard no longer exposes a vocoder option in its soundfont dropdown (vocoder is its own slot type).
- Default new project no longer sets master/slave roles on keyboard slots (role concept superseded by the Jam Mode GFPA slot).

### Removed
- **Legacy `JamSessionWidget`** and global `ScaleLockMode` preference — all jam routing is now managed by the Jam Mode GFPA plugin slot.
- **`GrooveForgeKeyboardPlugin.jamEnabled/jamMasterSlotId`** fields — dead code purge after GFPA migration.
- **`_buildMasterDropdown` / `_buildSlavesSection`** — replaced by `GFpaJamModeSlotUI`.
- **Vocoder option from the keyboard soundfont dropdown** — vocoder is a dedicated slot type.

### Fixed
- **Vocoder MIDI routing**: removed erroneous omni-mode routing that caused all MIDI input to trigger the vocoder channel regardless of which slot was targeted.
- **Startup hang**: added `_isConnecting` guard to `MidiService` to prevent concurrent `connectToDevice` calls when the 2-second polling timer raced with `_tryAutoConnect` on Linux.
- **Note labels on white keys**: note name labels (e.g. `C4`, `F#6`) now render correctly on white keys as well as black keys.
- **Scale immediately applied on change**: changing the scale type in a Jam Mode slot now propagates to all target channels without requiring a stop/restart cycle.
- **Vocoder targetable by Jam Mode**: vocoder slots can now be added as Jam Mode targets, receiving scale locking the same way keyboard slots do.
- **Rack bottom padding**: added bottom margin so the FAB no longer overlaps the last rack slot.

---

## [2.1.0] - 2026-03-08

### Added
- **External VST3 plugin hosting** (Linux, macOS, Windows): load any `.vst3` bundle into a rack slot via the "Browse VST3" tile in the Add Plugin sheet.
- **Parameter knobs**: each VST3 slot displays category chips (one per parameter group). Tapping a chip opens a modal grid of `RotaryKnob` widgets with search, sub-group filter, and pagination (24 per page).
- **Native plugin editor window** (Linux): opens the VST3 plugin's own GUI in a floating X11 window. The editor can be opened, closed, and reopened without freezing or crashing.
- **ALSA audio output thread**: `dart_vst_host_alsa.cpp` — low-latency ALSA playback thread consuming VST3 audio output in real time.
- **Single-component VST3 support**: controller is queried from the component when `getControllerPtr()` returns null (Aeolus, Guitarix).
- **Multi-output-bus support**: all audio output buses are configured dynamically on resume (Surge XT Scene B, etc.).
- **Autosave reload**: VST3 plugin instances in a `.gf` project are re-loaded into `VstHostService` on startup via the splash screen.
- **Parameter persistence**: VST3 parameter values are stored in `Vst3PluginInstance.parameters` and saved to the `.gf` project.

### Architecture
- `packages/flutter_vst3/` vendored at project root (BSD-3-Clause, compatible with MIT); nested `.git` removed so it is committed to the repo.
- `dart_vst_host` converted to a Flutter FFI plugin (`ffiPlugin: true`) with platform-specific CMakeLists for Linux (ALSA + X11), Windows (Win32), and macOS (Cocoa/CoreAudio).
- Platform-conditional import: `vst_host_service.dart` exports the desktop implementation on Linux/macOS/Windows and a no-op stub on mobile.

### Fixed
- JUCE-based plugins (Surge XT, DISTRHO): `setComponentState()` called after init to build the internal processor reference.
- Editor X-button close: `removed()` called on the event thread to avoid deadlock with JUCE's GUI thread.
- Re-open after close: `g_cleanupFutures` wait ensures `removed()` finishes before `createView()` is called again.

---

## [2.0.0] - 2026-03-08

### Added
- **Plugin Rack**: Replaced the fixed channel list with a fully dynamic, reorderable plugin rack. Each slot is an independent synthesizer lane with its own MIDI channel, soundfont/patch, and Jam Mode role.
- **GrooveForge Keyboard Plugin**: The built-in synth/vocoder is now a proper plugin instance with per-slot configuration (soundfont, bank, patch, vocoder settings) and full save/restore support.
- **Drag-and-Drop Reordering**: Rack slots can be reordered freely by dragging the handle on the left of each slot header.
- **Add / Remove Plugins**: A floating action button opens a sheet to add new GrooveForge Keyboard slots (or VST3 plugins on desktop — Phase 2). Slots can be removed with confirmation.
- **Master / Slave Roles in Slot Headers**: Each slot now has a Master/Slave chip directly in its header. Tapping toggles the role; the Jam Mode engine is updated automatically.
- **MIDI Channel Badge**: Each slot shows its MIDI channel and allows changing it via a picker, preventing conflicts with other slots.
- **Project Files (.gf format)**: Projects are now saved and loaded as JSON `.gf` files. The app bar file menu provides Open, Save As, and New Project actions.
- **Autosave**: Every rack change is automatically persisted to `autosave.gf` in the app documents directory, restoring the session on next launch.
- **First-Launch Defaults**: On first launch, the rack is pre-configured with one Slave slot on MIDI channel 1 and one Master slot on MIDI channel 2.
- **Simplified Jam Mode Widget**: The Jam Mode bar no longer shows master/slave channel dropdowns (managed per-slot in the rack); it now focuses on the JAM start/stop and scale type controls.

### Removed
- **Visible Channels Modal**: The "Filter Visible Channels" dialog has been removed. The rack is the channel list — every slot is visible.
- **SynthesizerScreen** and **ChannelCard**: Replaced by `RackScreen` and `RackSlotWidget`.

### Architecture
- New `PluginInstance` abstract model with `GrooveForgeKeyboardPlugin` and `Vst3PluginInstance` (desktop Phase 2 stub).
- New `RackState` ChangeNotifier manages the plugin list and syncs Jam master/slave to `AudioEngine`.
- New `ProjectService` handles `.gf` file I/O (JSON save/load/autosave).

## [1.7.1] - 2026-03-07
### Added
- **Vocoder Feedback Warning**: Implemented a safety modal that warns users about potential audio feedback (Larsen effect) when using the vocoder with internal microphones and speakers. The warning is shown once and can be dismissed permanently.

### Fixed
- **Android Audio Input Regression**: Fixed a critical issue where internal and external microphones were not working on Android due to missing runtime permissions and incorrect device ID handling in the native layer.

## [1.7.0] - 2026-03-07
### Added
- **Absolute Pitch Vocoder (Natural Mode)**: A complete redesign of the vocoder's high-fidelity mode using **PSOLA (Pitch Synchronous Overlap and Add)** grain synthesis. It now captures your voice cycle and triggers fixed-duration grains at the **exact MIDI frequency**. This preserves your natural vocal formants and vowel character, eliminating the "accelerated" feeling and ensuring perfect pitch locking even if you sing out of tune.
- **Audio Device Persistence Fix (Linux)**: Resolved an issue where the preferred audio input device was not correctly initialized on startup. All vocoder settings (Waveform, Noise Mix, Gain, etc.) are now correctly persistent and applied before the audio stream starts.
- **Improved Vocoder Volume**: Integrated RMS-based normalization into the PSOLA engine to ensure the Natural mode matches the perceived loudness of the other vocoder modes.
- **Vocoder Noise Gate**: Added a dedicated "GATE" control to the vocoder panel to eliminate background noise and feedback hum during quiet passages.
- **Zoomed Knob Preview**: Added a zoomed knob preview that appears on interaction (200ms hold or instant drag), providing clear visual feedback on the current value.
- **Autoscroll Toggle**: Added a user preference to enable or disable automatic channel list scrolling when MIDI notes are played (disabled by default).
- **Audio Output Device Selection**: Added an output device selector in Preferences, alongside the existing mic selector, for routing vocoder output to a specific speaker or headset.
- **AAudio Jitter Mitigation**: Integrated a background health watcher that monitors audio stream stability and triggers a silent engine restart if persistent glitches are detected.
- **DSP Inner-Loop Optimization**: Significantly reduced per-sample processing overhead by refactoring core audio synthesis logic, enhancing real-time performance on mobile devices.
- **Engine Stability & Audio Decoupling**: Massive improvement in overall app stability and sound quality by decoupling the low-level audio lifecycle from the Flutter UI thread. This eliminates the "chopped sound" and UI lag that previously occurred after extended use.

### Changed
- **Vocoder Mode Rename**: "Neutral" mode is now **"Natural"** to better reflect its high-fidelity vocal character.
- **Knob Responsiveness**: Enhanced `RotaryKnob` sizing and layout for narrow/mobile screens to improve touch accuracy and visibility.
- **Adaptive Vocoder Layout**: Optimized the vocoder row with smart icon/label switching to maintain accessibility on small screens.
- **Mic automatically restarts on device change**: Changing the input or output device in Preferences now automatically restarts the audio capture engine without requiring a manual "Refresh Mic" tap.

### Fixed
- **Absolute MIDI Locking**: Fixed the issue where the vocoder would follow the singer's pitch inaccuracies instead of the keyboard notes.
- **Optimized Vocoder Latency**: Achieved near-real-time performance by decoupling microphone capture from the main playback thread using a lock-free ring buffer. This eliminates the significant (400ms+) onset delay caused by Android's duplex clock synchronization.
- **Squelch Gate Precision**: Bypassed the noise gate when notes are active to prevent sound occlusion at the start of vocal phrases.
- **USB Audio Device Enumeration**: Switched Android audio device queries to `GET_DEVICES_ALL` with capability-based filtering, ensuring USB microphones and wired headsets are always listed even when sharing a USB-C hub.
- **Duplicate device in input list**: Bidirectional USB headsets (e.g. a USB headset with both mic and speaker) no longer appear twice in the mic selector — only the source/mic side is listed.
- **Stale device ID after reconnect**: Selecting a USB mic or headset and then unplugging/replugging the hub (which reassigns device IDs) no longer shows "Disconnected" — the selection automatically resets to the system default.
- **Auto-fallback on device disconnect**: The app now listens to Android `AudioDeviceCallback` events. When a previously selected input or output device is removed, the selection resets to the system default automatically.
- **Audio engine restart loop**: Added a re-entrancy guard (`_isRestartingCapture`) with a 500 ms cooldown on `restartCapture()` to prevent Fluidsynth's Oboe disconnect-recovery events from cascading into an infinite restart loop.

## [1.6.1] - 2026-03-06
### Added
- **Revamped User Guide**: Reorganized tabs (Features, MIDI Connectivity, Soundfonts, Musical Tips).
- **Vocoder Documentation**: Added detailed instructions on how to use the new vocoder features.
- **Musical Improvisation Tips**: Added a new section with theory bits to help beginners improvise using scales.
- **Auto-Welcome**: The user guide now appears automatically on first launch or after a major update to highlight new features.

## [1.6.0] - 2026-03-05
### Added
- **Vocoder Overhaul**: 32-band polyphonic vocoder with carrier waveform selection (including new 'Neutral' mode).
- **Native Audio Input**: High-performance audio capture via miniaudio + FFI.
- **Rotary UI Control**: New `RotaryKnob` custom widget for a more tactile experience.
- **Advanced Vocoder Controls**: Added Bandwidth and Sibilance injection parameters.
- **Audio Session Management**: Integration with `audio_session` for improved Bluetooth and routing support.
- **Enhanced Level Meters**: Real-time visual feedback for vocoder input and output levels.

### Changed
- **Performance Optimizations**: Low-latency audio profile and optimized note release tails.

## [1.5.2] - 2026-03-04
### Fixed
- **Chord Release Stabilization**: Optimized the chord release logic in Jam Mode by implementing a robust 50ms debounced stabilization window, preventing chord identity "flickering" during natural finger lift-offs.

## [1.5.1] - 2026-03-04
### Added
- **Instant Device Connection**: When a new MIDI device is plugged in while on the main synthesizer screen, an automatic prompt appears allowing instant connection.
- **Improved Auto-Reconnect**: MIDI devices now reliably auto-reconnect even if unplugged and replugged while the app is running.

## [1.5.0] - 2026-03-04
### Added
- **Internationalization (i18n)**: Added full support for application localization.
- **French Language**: Translated the entire application UI and provided a French changelog (`CHANGELOG.fr.md`).
- **Language Preferences**: Users can now dynamically switch the application language from the Preferences screen (System Default, English, French).

## [1.4.5] - 2026-03-04
### Added
- **Jam Mode Borders Toggle**: Added a user-configurable preference to toggle the visibility of the visual borders around scale-mapped key groups in Jam Mode.
- **Jam Mode Wrong Note Highlighting**: Pressing an out-of-scale physical key in Jam Mode now colors the originally pressed wrong key in red and highlights the correctly mapped target note in blue, with a user preference to optionally toggle the red coloring.

## [1.4.4] - 2026-03-03
### Added
- **Jam Mode Click Zones**: Virtual Piano keys in Jam Mode are now grouped with the valid keys they snap to, forming unified clickable zones enclosed in subtle colored borders.

## [1.4.3] - 2026-03-02
### Fixed
- **Virtual Piano Artifacts**: Fixed a bug where Virtual Piano shading did not update immediately when Jam Mode was started or stopped.
- **Scroll Interference**: Prevented the main screen from scrolling vertically when performing gestures on the Virtual Piano keys.

## [1.4.2] - 2026-03-02
### Added
- **Reactive Jam Mode Sync**: Scale tags and virtual piano visuals (grayed-out keys) now update in real-time when the jam master scale changes or when slave channel configurations are modified.

### Changed
- **Virtual Piano Scalability**: Slave channels now visually gray out keys that do not belong to the master channel's current scale.
- **Improved UI Performance**: Fixed complex widget nesting issues in `ChannelCard` to guarantee clean and reactive UI builds.

### Fixed
- **Glissando Behavior**: Notes outside the current scale continue to sound if they are part of an ongoing glissando gesture instead of being stopped abruptly.
- **Virtual Piano Artifacts**: Resolved keyboard transparency artifacts by using solid colors for disabled keys.

## [1.4.1] - 2026-02-28
### Added
- **Configurable Expressive Gestures**: Users can now independently assign actions (None, Pitch Bend, Vibrato, Glissando) to Vertical and Horizontal key gestures.
- **Unified Gesture Preferences**: High-level configuration in the Preferences screen with new axis-specific dropdown menus.
- **Android Permission Optimization**: Decoupled Bluetooth from Location for Android 12+. Location access is no longer required on modern devices.
- **Improved UI Responsiveness**: Refactored the Preferences screen with an adaptive layout to prevent text crushing on narrow mobile devices.

### Changed
- **Performance Optimization**: Chord detection in Jam mode is now asynchronous, significantly reducing UI latency during heavy performance tracking.

### Fixed
- Resolved a runtime `Provider` crash on application startup.
- Fixed a minor linting warning in the `VirtualPiano` logic.

## [1.4.0] - 2026-02-28
### Added
- **Expressive Gestures**: Introduced vertical Pitch Bend and horizontal Vibrato on the Virtual Piano.
- **Gesture-Locked Scrolling**: Automatic suppression of piano list scrolling while expressive gestures are in progress to prevent accidental movement.
- **Independent Jam Chords**: Every channel now detects and displays its own chord independently in Jam mode.
- **Dynamic Slave Visibility**: Slave channel chord names now hide automatically when they are not actively playing.

### Changed
- Refined Jam mode chord badges by removing the "JAM:" prefix for a cleaner aesthetic.
- Scale names across all channels correctly reference the Master's chord context for synchronized performance feedback.

## [1.3.6] - 2026-02-28
### Added
- New "About" section in Preferences screen.
- Integrated Changelog viewer to see the history of changes directly in the app.

## [1.3.5] - 2026-02-28
### Added
- Maximized vertical real estate for the Virtual Piano keys. Reduced padding and margins across the main screen and channel cards to improve playability on mobile/tablet devices.

## [1.3.4] - 2026-02-28
### Changed
- Virtual Piano "Glissando" (Drag to Play) is now enabled by default for new installations and preference resets.

## [1.3.3] - 2026-02-28
### Added
- Unified "boxed" styling for Jam Master, Slaves, and Scale controls in both horizontal and vertical layouts.
- Centered vertical layout for the Jam sidebar with a more compact footprint (95px width).
- New interactive icons for dropdowns to clearly signal clickability.

### Fixed
- Flutter assertion error when `itemHeight` was set too low in Jam dropdowns.
- Vertical sidebar now correctly centers vertically on the left edge.

## [1.3.2] - 2026-02-27

### Added
- **Dual-Mode Jam UI:** Overhauled the Jam Session widget with strict layout isolation. Mobile landscape now features a premium, labeled vertical sidebar, while portrait/narrow displays use an ultra-compact, correctly ordered horizontal bar.
- **Subtle Labels:** Added high-contrast, tiny labels to both horizontal and vertical Jam UI modes for improved clarity during performance.

### Fixed
- **Splash Screen Cropping:** Changed splash screen image scaling to prevent cropping on portrait displays.
- **Jam Bar Restoration:** Restored the legacy widget order (Jam, Master, Slaves, Scale) and compact container sizing in the horizontal header.
- **Label Redundancy:** Removed duplicate labels in the vertical sidebar for a cleaner aesthetic.

## [1.3.1] - 2026-02-27

### Added
- **Interactive User Guide:** A comprehensive, multi-tabbed in-app guide replacing the legacy CC help modal. It covers connectivity, soundfonts, CC mapping, and Jam Mode.
- **Exhaustive System Actions:** All 8 system-level MIDI CC actions (1001-1008) are now fully implemented and documented, including Absolute Patch/Bank sweeps.

### Changed
- **System Action Renaming:** "Toggle Scale Lock" (1007) has been renamed to "Start/Stop Jam Mode" to better reflect its primary performance role.
- **Improved Action Descriptions:** Descriptions in the CC mapping service and Guide are now more descriptive and accurate.

## [1.3.0] - 2026-02-27

### Added
- **Musical Scale Names:** Real descriptive names (e.g., Dorian, Mixolydian, Altered Scale) are now displayed in the UI instead of generic labels.
- **Smart Jam Mode:** Significant overhaul of the Jam Mode engine to support multi-channel scale locking and dynamic mode calculation based on the Master's chord.
- **Improved UI Propagation:** Descriptive scale names are now propagated to all UI components, offering better musical feedback during performance.

### Changed
- **Default Lock Mode:** "Jam Mode" is now the default scale-locking preference.

### Fixed
- **Chord Release Stabilization:** Implemented a peak-preservation logic with a 30ms grace period to prevent chord identity "flickering" during release transitions.
## [1.2.1] - 2026-02-27

### Added
- **Reset Preferences:** Added a "Reset All Preferences" feature in the Preferences screen with a confirmation dialog to restore factory settings.
- **Improved Soundfont UI:** The Default soundfont now displays as "Default soundfont", appears first in lists, and is protected from deletion.

### Fixed
- **Linux Stability:** Resolved a crash and duplicated soundfont entries caused by logic errors in the soundfont loading state.
- **macOS Audio Pipeline:** Complete refactor of the macOS audio engine to use a single shared `AVAudioEngine` with 16 mixer buses, providing better performance and fixing "no sound" issues.
- **macOS Custom Soundfonts:** Removed a redundant file-copying loop that caused `PathNotFoundException` and added an automatic bank fallback (MSB 0) to fix load error `-10851`.
- **Audio Improvements:** Boosted default audio volume on macOS by 15dB for better parity with other platforms.
- **Path Migration:** Implemented a robust migration layer to automatically move legacy soundfont paths to the new secure internal storage.


## [1.2.0] - 2026-02-26

### Added
- Implemented a custom application icon for all platforms.
- Added a native splash screen (Android, iOS) for a seamless startup experience.
- Created a dynamic, fullscreen Flutter splash screen that shows initialization progress (loading preferences, starting backends, etc.).

## [1.1.0] - 2026-02-26

### Added
- Bundled a default, lightweight General MIDI Soundfont (`TimGM6mb.sf2`) so the app produces sound out-of-the-box on all platforms without requiring a manual download.
- Added a horizontal scrollbar to the virtual piano.
- Added a preference to customize the default number of piano keys visible on screen.

### Changed
- The virtual piano now initializes centered on Middle C (C4) instead of the far left.
- Re-architected virtual piano auto-scrolling to track active notes robustly.
- Synthesizer view gracefully adapts to ultra-wide/short aspect ratios (e.g., landscape mobile phones) by displaying a single channel vertically.

## [1.0.1] - 2026-02-26

### Changed
- Replaced the channel configuration modal with interactive dropdowns for Soundfont, Patch, and Bank right on the `ChannelCard`.
- Made the dropdown layout responsive to different screen widths.

## [1.0.0] - 2026-02-26

### Added
- Initial project release.
- Core capability to parse MIDI.
- Bluetooth LE compatibility.
- Virtual piano interactable via mouse/touch.
- Real-time chord parsing and identification.
- User Preferences screen to select output MIDI devices or internal Soundfonts.
- Automatic channel parsing and UI component architecture `ChannelCard`.
- Scale-locking chord functionality to constraint the played keys.
