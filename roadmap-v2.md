# GrooveForge v2.0.0 Roadmap — Full DAW Experience

This document tracks all work required to ship v2.0.0. Check off items as they are completed. This file is updated in place as progress is made.

---

## Resources & References


| Resource                               | URL                                                                                                                                                                                  | Purpose                                                          |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------- |
| VST3 SDK (MIT since v3.8, Oct 2025)    | [https://github.com/steinbergmedia/vst3sdk](https://github.com/steinbergmedia/vst3sdk)                                                                                               | Core VST3 standard library                                       |
| VST3 Developer Portal                  | [https://steinbergmedia.github.io/vst3_dev_portal/](https://steinbergmedia.github.io/vst3_dev_portal/)                                                                               | API docs, licensing info                                         |
| flutter_vst3 toolkit                   | [https://github.com/MelbourneDeveloper/flutter_vst3](https://github.com/MelbourneDeveloper/flutter_vst3)                                                                             | Build VST3 plugins & host from Dart/Flutter                      |
| dart_vst_host (inside flutter_vst3)    | [https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/dart_vst_host](https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/dart_vst_host)                             | VST3 hosting API for Dart apps                                   |
| dart_vst_graph (inside flutter_vst3)   | [https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/dart_vst_graph](https://github.com/MelbourneDeveloper/flutter_vst3/tree/main/dart_vst_graph)                           | Audio graph / routing system                                     |
| Steinberg VST3 License                 | [https://steinbergmedia.github.io/vst3_dev_portal/pages/VST+3+Licensing/VST3+License.html](https://steinbergmedia.github.io/vst3_dev_portal/pages/VST+3+Licensing/VST3+License.html) | MIT — fully compatible with our MIT license                      |
| flutter_midi_engine (future migration) | [https://pub.dev/packages/flutter_midi_engine](https://pub.dev/packages/flutter_midi_engine)                                                                                         | SF3 support + web support                                        |
| MuseScore General SF3                  | [ftp://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf3](ftp://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf3)         | High-quality MIT-licensed default soundfont (post-SF3 migration) |
| ReorderableListView (Flutter)          | [https://api.flutter.dev/flutter/material/ReorderableListView-class.html](https://api.flutter.dev/flutter/material/ReorderableListView-class.html)                                   | Drag/drop rack slot reordering                                   |
| file_selector (Flutter)                | [https://pub.dev/packages/file_selector](https://pub.dev/packages/file_selector)                                                                                                     | Cross-platform file open/save dialogs for .gf files              |


---

## Architecture Overview

```
GrooveForge v2.0.0
│
├── Rack Engine (Dart, all platforms)
│   ├── PluginInstance (abstract base)
│   │   ├── GrooveForgeKeyboardPlugin   ← built-in plugin (all platforms)
│   │   └── Vst3PluginInstance          ← desktop only (Linux/macOS/Windows)
│   ├── RackState (ChangeNotifier)      ← replaces channel list in AudioEngine
│   └── ProjectService (.gf JSON)       ← save/load/autosave project files
│
├── Rack UI
│   ├── RackScreen                      ← replaces SynthesizerScreen
│   ├── RackSlotWidget                  ← replaces ChannelCard
│   │   ├── GrooveForgeKeyboardSlotUI   ← existing controls, unified per-slot
│   │   └── Vst3SlotUI                  ← generic param sliders (desktop only)
│   ├── AddPluginSheet                  ← bottom sheet: pick plugin type
│   └── Drag/drop reordering            ← ReorderableListView
│
└── GrooveForge Keyboard VST3 (separate CMake build, desktop only)
    ├── native_audio/audio_input.c      ← shared with main app (vocoder DSP)
    ├── FluidSynth static lib           ← compiled in
    └── flutter_vst3 scaffold           ← IPC bridge + Dart audio processor
```

### .gf Project File Format (JSON)

```json
{
  "version": "2.0.0",
  "name": "My Project",
  "createdAt": "2026-03-08T12:00:00Z",
  "jamMode": {
    "enabled": false,
    "scaleType": "standard",
    "scaleLockMode": "jam"
  },
  "plugins": [
    {
      "id": "slot-0",
      "type": "grooveforge_keyboard",
      "midiChannel": 1,
      "role": "slave",
      "state": {
        "soundfontPath": "vocoder",
        "bank": 0,
        "patch": 0,
        "vocoderEnabled": false,
        "vocoderWaveform": 0,
        "vocoderNoiseMix": 0.05,
        "vocoderEnvRelease": 0.02,
        "vocoderBandwidth": 0.2,
        "vocoderGateThreshold": 0.01,
        "vocoderInputGain": 1.0
      }
    },
    {
      "id": "slot-1",
      "type": "grooveforge_keyboard",
      "midiChannel": 2,
      "role": "master",
      "state": {
        "soundfontPath": "default",
        "bank": 0,
        "patch": 0,
        "vocoderEnabled": false,
        "vocoderWaveform": 0,
        "vocoderNoiseMix": 0.05,
        "vocoderEnvRelease": 0.02,
        "vocoderBandwidth": 0.2,
        "vocoderGateThreshold": 0.01,
        "vocoderInputGain": 1.0
      }
    }
  ]
}
```

> **VST3 entry** (desktop-only, written when external plugins are added):
>
> ```json
> {
>   "id": "slot-2",
>   "type": "vst3",
>   "platform": ["linux", "macos", "windows"],
>   "path": "/home/user/.vst3/TAL-Reverb.vst3",
>   "name": "TAL Reverb IV",
>   "midiChannel": 3,
>   "role": "slave",
>   "state": {
>     "parameters": { "0": 0.65, "1": 0.3 }
>   }
> }
> ```

### Platform Constraints


| Feature                         | Linux | macOS | Windows | Android | iOS |
| ------------------------------- | ----- | ----- | ------- | ------- | --- |
| GrooveForge Keyboard (built-in) | ✅     | ✅     | ✅       | ✅       | ✅   |
| External VST3 hosting           | ✅     | ✅     | ✅       | ❌       | ❌   |
| .gf save/open                   | ✅     | ✅     | ✅       | ✅       | ✅   |
| Distributable .vst3 bundle      | ✅     | ✅     | ✅       | ❌       | ❌   |
| Vocoder                         | ✅     | ❌     | ❌       | ✅       | ❌   |


---

## Phase 1 — Rack Core + Built-in Plugin + .gf Format ✅ COMPLETE

> Pure Dart/Flutter work — no native changes. This is the breaking UI migration that all other phases build upon.

### 1.1 — Plugin Instance Abstraction ✅

- [x] Create `lib/models/plugin_instance.dart` — abstract base (`id`, `midiChannel`, `role`, `toJson`, factory `fromJson`)
- [x] Create `lib/models/plugin_role.dart` — `PluginRole` enum (`master`, `slave`)
- [x] Create `lib/models/grooveforge_keyboard_plugin.dart` — concrete built-in plugin with `soundfontPath`, `bank`, `program`, all vocoder params, `copyWith`, JSON round-trip
- [x] Create `lib/models/vst3_plugin_instance.dart` — external VST3 stub with `path`, `pluginName`, `parameters` map, JSON round-trip

### 1.2 — RackState ChangeNotifier ✅

- [x] Create `lib/services/rack_state.dart` — ordered `List<PluginInstance>`, `addPlugin`, `removePlugin`, `reorderPlugins`, `setPluginMidiChannel`, `setPluginRole`, `setPluginSoundfont`, `setPluginPatch`, `snapshotVocoderParams`, `initDefaults`, `toJson`, `loadFromJson`, `generateSlotId`, `nextAvailableMidiChannel`
- [x] `_syncJamChannelsToEngine()` derives `jamMasterChannel` / `jamSlaveChannels` from rack roles automatically
- [x] `onChanged` callback wired to autosave after every mutation

### 1.3 — ProjectService (.gf Format) ✅

- [x] Create `lib/services/project_service.dart` using existing `file_picker` package
- [x] `autosave(rack, engine)` — silent write to `<app_documents>/autosave.gf`
- [x] `loadOrInitDefault(rack, engine)` — loads autosave or calls `initDefaults()`
- [x] `saveProjectAs(rack, engine)` — file picker (desktop) or documents dir (mobile)
- [x] `openProject(rack, engine)` — file picker + load + autosave
- [x] Jam Mode global settings (`enabled`, `scaleType`, `lockMode`) saved/restored in `.gf`

### 1.4 — RackScreen (replaces SynthesizerScreen) ✅

- [x] Create `lib/screens/rack_screen.dart` replacing `SynthesizerScreen`
- [x] App bar: folder popup with Open / Save As / New Project actions
- [x] Reorderable rack body (`ReorderableListView`) with `RackSlotWidget` items
- [x] FAB: "Add Plugin" → `showAddPluginSheet(context)`
- [x] Preserves: `JamSessionWidget` sidebar/header layout, MIDI device prompt, toast system, auto-scroll
- [x] Delete `lib/screens/synthesizer_screen.dart` ✅

### 1.5 — RackSlotWidget + GrooveForgeKeyboardSlotUI ✅

- [x] Create `lib/widgets/rack_slot_widget.dart` — slot header (drag handle, plugin name, MIDI badge, role chip, delete), active-note flash, piano (`_RackSlotPiano`), dispatch to slot body
- [x] Create `lib/widgets/rack/grooveforge_keyboard_slot_ui.dart` — bridges plugin model to existing `ChannelPatchInfo` + vocoder controls via `engine.channels[midiChannel-1]`
- [x] Create `lib/widgets/rack/vst3_slot_ui.dart` — informational placeholder for desktop Phase 2
- [x] `_MidiChannelBadge` — tap to pick MIDI channel (1–16), blocks already-used channels
- [x] `_RoleChip` — tap to toggle master/slave, updates rack immediately
- [x] `_RackSlotPiano` — full VirtualPiano with all gesture callbacks (note on/off, pitch bend, CC, interacting state)

### 1.6 — AddPluginSheet ✅

- [x] Create `lib/widgets/add_plugin_sheet.dart` — bottom sheet with GrooveForge Keyboard tile (all platforms) and Browse VST3 tile (desktop only via `Platform.isLinux/isMacOS/isWindows`)

### 1.7 — AudioEngine Refactor ✅

- [x] Remove `visibleChannels` `ValueNotifier` from `AudioEngine`
- [x] Remove `visible_channels` from `_saveState()` and `_restoreState()`
- [x] Remove `visibleChannels.value = ...` from `resetPreferences()`
- [x] Register `RackState` in `MultiProvider` via `ChangeNotifierProxyProvider` in `main.dart`
- [x] Register `ProjectService` as `Provider` in `main.dart`

### 1.8 — JamSessionWidget Migration ✅

- [x] Remove `_buildMasterDropdown`, `_buildSlavesSection`, `_showSlaveSelectDialog` (now handled per-slot in rack headers)
- [x] JamSessionWidget now shows only: JAM start/stop + Scale type selector

### 1.9 — SplashScreen & First Launch ✅

- [x] `SplashScreen` calls `ProjectService().loadOrInitDefault(rack, engine)` after `engine.init()`
- [x] `rack.onChanged` wired to autosave in splash before loading
- [x] First launch: `initDefaults()` → slot-0 slave ch1, slot-1 master ch2

### 1.10 — Localization ✅

- [x] Add EN keys to `app_en.arb`: `rackTitle`, `rackAddPlugin`, `rackAddGrooveForgeKeyboard`, `rackAddGrooveForgeKeyboardSubtitle`, `rackAddVst3`, `rackAddVst3Subtitle`, `rackRemovePlugin`, `rackRemovePluginConfirm`, `rackRemove`, `rackPluginUnavailableOnMobile`, `rackMidiChannel`, `rackRoleMaster`, `rackRoleSlave`, `rackOpenProject`, `rackSaveProject`, `rackSaveProjectAs`, `rackNewProject`, `rackNewProjectConfirm`, `rackNewProjectButton`, `rackProjectSaved`, `rackProjectOpened`, `rackAutosaveRestored`, `splashRestoringRack`
- [x] Add matching FR keys to `app_fr.arb`
- [x] Run `flutter gen-l10n` — 0 errors

### 1.11 — Cleanup & Testing ✅

- [x] Remove `visibleChannels` from `AudioEngine` save/restore/reset
- [x] Update `CHANGELOG.md` with v2.0.0 entry
- [x] Bump version to `2.0.0+28` in `pubspec.yaml`
- [x] `dart analyze lib/` → **No issues found**
- [x] Update `CHANGELOG.fr.md` with v2.0.0 French entry
- [ ] Manual smoke test: Linux
- [ ] Manual smoke test: Android

---

## Phase 2 — VST3 Hosting (Desktop Only) ✅ COMPLETE

> Adds the ability to load external `.vst3` plugins into rack slots on Linux, macOS, and Windows. Android and iOS are unaffected (the "Browse VST3" button is hidden on those platforms).

### 2.1 — Native Library & Build Automation ✅

- [x] Vendored `flutter_vst3` toolkit at `packages/flutter_vst3/` (BSD-3-Clause, compatible with MIT)
- [x] Removed nested `.git` so the vendored copy can be committed to the repo
- [x] Patched `dart_vst_host` native C++:
  - ALSA audio output thread (`dart_vst_host_alsa.cpp`) — `dvh_audio_add_plugin/remove/clear`, `dvh_start/stop_alsa_thread`
  - X11 plugin editor window (`dart_vst_host_editor_linux.cpp`) — `dvh_open/close_editor`, `dvh_editor_is_open`, full `IRunLoop` + `IPlugFrame` implementation for JUCE-based plugins (Surge XT etc.)
  - Parameter unit/group API (`dart_vst_host.cpp`) — `dvh_param_unit_id`, `dvh_unit_count`, `dvh_unit_name`
  - Cross-platform stubs (`dart_vst_host_platform_stubs.cpp`) — no-op ALSA + editor functions on Windows/macOS
- [x] Converted `dart_vst_host` to a Flutter FFI plugin (`ffiPlugin: true` for linux/windows/macos in `pubspec.yaml`)
  - Created `dart_vst_host/linux/CMakeLists.txt` — symlink-aware (`get_filename_component(... REALPATH)`), links ALSA + X11
  - Created `dart_vst_host/windows/CMakeLists.txt` — Win32 VST3 module loader, links user32/ole32/uuid
  - Created `dart_vst_host/macos/CMakeLists.txt` — ObjC++ module loader, links Cocoa/Carbon/CoreFoundation/AudioToolbox
  - Removed manual `.so` copy from `linux/CMakeLists.txt` — Flutter build system handles bundling automatically
- [x] Updated `.github/workflows/release.yml`: `libx11-dev` + `ccache` for VST3 SDK compilation, `libx11-6` in `.deb` depends

### 2.2 — Platform-Conditional Import Architecture ✅

- [x] `lib/services/vst_host_service_stub.dart` — no-op stub for mobile/web
- [x] `lib/services/vst_host_service_desktop.dart` — `initialize`, `loadPlugin`, `unloadPlugin`, `noteOn/Off`, `getParameters`, `getUnitNames`, `setParameter`, `startAudio/stopAudio`, `scanPluginPaths`, `openEditor`, `closeEditor`, `isEditorOpen`
- [x] `lib/services/vst_host_service.dart` — conditional export (`dart.library.io`)
- [x] Registered `VstHostService` in `MultiProvider` in `main.dart`
- [x] `VstParamInfo` includes `unitId` for parameter grouping

### 2.3 — VST3 Plugin Loading ✅

- [x] VST3 bundle directory detection + `.so` resolution inside bundle in `add_plugin_sheet.dart` (uses `FilePicker.getDirectoryPath()`)
- [x] `dvh_load_plugin` fixed to store `PlugProvider` in `DVH_PluginState` (prevents premature termination)
- [x] `setComponentState()` added after init for JUCE-based plugins (Surge XT, DISTRHO) to build internal processor reference
- [x] Single-component VST3 support — controller queried from component when `getControllerPtr()` returns null (Aeolus, Guitarix)
- [x] Multi-output-bus support in `dvh_resume` — all buses configured dynamically (Surge XT has Scene B, etc.)
- [x] Instrument plugin support (0 audio inputs) — `nullptr` inputs passed to `dvh_resume`
- [x] Autosave reload — `SplashScreen` re-loads all `Vst3PluginInstance`s into `VstHostService` on startup

### 2.4 — Vst3SlotUI (parameter knobs + editor button) ✅

- [x] Compact **category chips** in the rack card — one chip per parameter group (IUnitInfo unit or name-detected sub-group)
- [x] Large groups (> 48 params) expanded at chip level using `_SubGroupDetector` (3/2/1-word prefix analysis, `|` as separator for MIDI CC channels)
- [x] Tapping a chip opens `_ParamCategoryModal` — grid of `RotaryKnob` widgets (reuses existing `lib/widgets/rotary_knob.dart`)
- [x] Modal: search bar, sub-group dropdown for very large categories, pagination (24 per page)
- [x] **Show/Close Plugin UI** button — opens the plugin's native editor in a floating X11 window
  - Editor close button: `XWithdrawWindow` for immediate visual feedback + detached background thread for non-blocking `IPlugView::removed()` cleanup
  - Editor X-button close: `removed()` called on the event thread (JUCE's GUI thread) to avoid deadlock
  - Re-open after close: `g_cleanupFutures` wait ensures `removed()` finishes before `createView()` is called
  - Self-join crash fix: cleanup future never erased from within its own lambda (would cause `EDEADLK` via `std::shared_future` destructor)
- [x] `_EditorButton` polls `isEditorOpen` via `Timer.periodic` to sync state with native window close/open
- [x] Parameter values persisted into `Vst3PluginInstance.parameters` via `rack.setVst3Parameter()`
- [x] Mobile / empty-path → `_UnavailablePlaceholder`

### 2.5 — .gf Format Update for VST3 ✅

- [x] `Vst3PluginInstance.toJson/fromJson` writes/reads `parameters` map (keyed by param ID string)
- [x] `RackState.setVst3Parameter()` — persists param change in model for `.gf` autosave

### 2.6 — Testing (manual smoke test) ✅

- [x] Loaded Surge XT (`/usr/lib/vst3/Surge XT.vst3`) — audio output via ALSA confirmed working
- [x] Loaded Aeolus (`/usr/lib/vst3/Aeolus.vst3`) — parameters grouped correctly
- [x] Loaded Guitarix (single-component VST3) — parameters accessible
- [x] Native editor window opens for Surge XT, can be opened/closed/reopened without freeze or crash
- [x] Parameter knobs display and update plugin state in real time
- [ ] Save project as `.gf`, reload — verify VST3 parameters restored *(pending full round-trip test)*
- [ ] Open same `.gf` on Android — verify placeholder shown, no crash

---

## Phase 3 — GrooveForge Keyboard as Distributable VST3

> Packages the built-in synthesizer/vocoder as a proper `.vst3` bundle loadable in Reaper, Ardour, Bitwig, Ableton, FL Studio, etc. This is a separate CMake build artifact, not part of the Flutter app build.

### ⚠️ Open Design Question — Jam Mode in a Standalone VST3

The Jam Mode feature (per-slot scale locking driven by a master chord) is tightly coupled to **multiple GrooveForge Keyboard instances running in the same host process**. Distributing as a single VST3 plugin creates a fundamental architectural challenge:

**Option A — Host-side IPC between instances**
Each `GrooveForge Keyboard.vst3` instance communicates with sibling instances via a named pipe, shared memory segment, or D-Bus message. The "master" instance broadcasts the detected chord; "follower" instances receive it and lock their scale. Complexity: high. Latency: low if shared memory.

**Option B — GrooveForge Keyboard as a "rack host" plugin**
The VST3 itself is a mini-host: it embeds multiple virtual keyboards (with individual MIDI channels and soundfonts) inside a single plugin instance, plus the Jam session widget as part of its own editor UI. The DAW sees only one plugin slot. Complexity: very high (embedded audio sub-graph). Benefit: Jam Mode works identically to the standalone app.

**Option C — Jam Mode stays app-only, standalone VST3 is soundfont/vocoder only**
The distributable VST3 exposes soundfont player + vocoder as a single-instance instrument. Jam Mode remains exclusive to the GrooveForge standalone app where multiple rack slots can coordinate. Simplest to implement; clearest separation of concerns.

**Current leaning: Option C** for the first release (simplicity), with Option A prototyped later if demand exists.

---

### 3.1 — VST3 SDK Setup

- [ ] Download VST3 SDK 3.8+ (MIT): `git clone https://github.com/steinbergmedia/vst3sdk vst3_plugin/vst3sdk`
- [ ] Verify SDK version is 3.8+ (MIT license) — check `vst3sdk/LICENSE.txt`
- [ ] Add `vst3sdk/` to `.gitignore` (already vendored for hosting; the plugin build can reuse `packages/flutter_vst3/vst3sdk`)
- [ ] Add a `setup_vst3_plugin.sh` script at project root (separate from hosting SDK)

### 3.2 — VST3 Plugin Project Scaffold

- [ ] Create `vst3_plugin/` directory at project root
- [ ] Create `vst3_plugin/CMakeLists.txt`:
  - Target: `GrooveForge Keyboard.vst3`
  - Links: `vst3sdk` (reuse `packages/flutter_vst3/vst3sdk`), FluidSynth static lib, `native_audio/audio_input.c`
  - Platform install paths: `~/.vst3/` (Linux), `~/Library/Audio/Plug-Ins/VST3/` (macOS), `C:\Program Files\Common Files\VST3\` (Windows)
- [ ] Create `vst3_plugin/src/processor.cpp` — `IAudioProcessor`:
  - Delegates MIDI note on/off to FluidSynth
  - Delegates vocoder processing to `audio_input.c` DSP (Linux only for now, see vocoder platform table)
- [ ] Create `vst3_plugin/src/controller.cpp` — `IEditController`:
  - Parameters: soundfont path, bank, patch, vocoder on/off, waveform, noise mix, bandwidth, gate threshold, gain
  - Parameter IDs match `.gf` state keys for round-trip compatibility
- [ ] Create `vst3_plugin/src/factory.cpp` — plugin factory registration
- [ ] Create `vst3_plugin/src/grooveforge_keyboard_ids.h` — VST3 class UIDs (generate with `uuidgen`)
- [ ] Create `vst3_plugin/resources/GrooveForgeKeyboard.uidesc` — VSTGUI layout (knobs + soundfont dropdown)

### 3.3 — Shared Audio Engine Code

- [ ] Ensure `native_audio/audio_input.c` compiles cleanly as a static lib without the Flutter FFI entrypoint
- [ ] Bundle FluidSynth as a static lib in the VST3 build (no runtime dynamic dependency)
- [ ] Include default soundfont `assets/soundfonts/default.sf2` in the `.vst3` bundle's `Resources/` folder

### 3.4 — Build Targets

- [ ] `make vst-linux` — builds for Linux x86_64, installs to `~/.vst3/`
- [ ] `make vst-macos` — universal binary (Intel + Apple Silicon)
- [ ] `make vst-windows` — cross-compile or native Windows build
- [ ] GitHub Actions CI job: build VST3 on Ubuntu/macOS/Windows, upload as release artifacts

### 3.5 — Jam Mode IPC Prototype (Option A, post-launch)

- [ ] Investigate `shm_open` / `mmap` shared memory for inter-instance chord broadcast on Linux/macOS
- [ ] Design a minimal protocol: master writes `{scale_root, scale_type, chord_notes[]}`, followers poll at audio callback rate
- [ ] Evaluate if DAW sandboxing (macOS, some Linux setups) blocks shared memory between plugin instances

### 3.6 — Testing

- [ ] Load in **Reaper** (Linux) — play notes via MIDI, change patches, verify audio
- [ ] Load in **Ardour** (Linux) — verify MIDI routing and audio output
- [ ] Soundfont selection parameter updates instrument in real time
- [ ] Vocoder activates when waveform parameter ≠ off (Linux)
- [ ] Plugin state saves/restores correctly when DAW project is saved and reopened
- [ ] Test on macOS with Logic Pro / GarageBand
- [ ] Test on Windows with FL Studio / Reaper

---

## Housekeeping & Cross-Cutting

- Update `TODO.md` — mark Web and SF3 items as still pending (not in scope for v2.0.0), add VST3 hosting items from Phase 2 once complete
- Add `vst3sdk/`, `vst3_plugin/build/` to `.gitignore`
- Add `setup_vst3.sh` to project root (VST3 SDK auto-download)
- Add `vst3_plugin/` build instructions to `README.md`
- Trademark compliance: if using "VST3" branding in the UI or plugin name, follow [Steinberg trademark guidelines](https://www.steinberg.net/vst-instrument-and-plug-in-developer/Steinberg_VST_Plug-In_SDK_Licensing_Agreement.pdf) (logo usage rules, no implication of Steinberg endorsement)

---

## Version Plan


| Version | Phase   | Status      | Description                                                        |
| ------- | ------- | ----------- | ------------------------------------------------------------------ |
| `2.0.0` | Phase 1 | ✅ Complete  | Rack UI + GrooveForge Keyboard built-in plugin + .gf project files |
| `2.1.0` | Phase 2 | ✅ Complete  | External VST3 hosting (desktop only)                               |
| `2.2.0` | Phase 3 | 🔜 TODO     | GrooveForge Keyboard as distributable `.vst3` bundle               |


---

*Last updated: 2026-03-08 — Phase 2 complete. Native VST3 hosting with ALSA audio, X11 editor windows (IRunLoop/IPlugFrame), parameter knobs (RotaryKnob), smart name-based category grouping. Phase 3 architecture options documented. Zero analyzer errors.*

---

## Jam Mode Redesign (implemented between Phase 1 and Phase 2)

The old global master/slave model was replaced with a per-slot opt-in model:

### Before
- One global master channel (only the first one had effect if multiple were set)
- Multiple slave channels defined globally in `JamSessionWidget`
- Setting a channel as "slave to no one" required marking it Master — unintuitive

### After
- **Every rack slot independently opts in** to Jam following with a "JAM OFF / JAM ON" toggle button in its header
- **No master designation required** — any slot can be watched by other slots
- When toggling JAM ON for the **first time**, a modal prompts the user to pick which slot drives the harmony
- When JAM is ON, an adjacent chip shows the master's MIDI channel and allows changing it with one tap
- **Multiple slots can follow the same or different masters** simultaneously
- Slots with JAM OFF play freely with no scale constraint
- The global JAM start/stop in the top bar acts as a master on/off switch without losing configurations

### Key code changes
- `GrooveForgeKeyboardPlugin`: `PluginRole role` → `bool jamEnabled, String? jamMasterSlotId`
- `AudioEngine`: `jamMasterChannel + jamSlaveChannels` → `jamFollowerMap: ValueNotifier<Map<int,int>>` (follower ch → master ch)
- `RackState`: new `setPluginJamEnabled()` / `setPluginJamMaster()` / `_syncJamFollowerMapToEngine()`
- `rack_slot_widget.dart`: `_RoleChip` → `_JamChip` + `_MasterPickerChip`
- `plugin_role.dart` deleted; `channel_card.dart` deleted