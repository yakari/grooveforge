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

## Phase 2 — VST3 Hosting (Desktop Only)

> Adds the ability to load external `.vst3` plugins into rack slots on Linux, macOS, and Windows. Android and iOS are unaffected (the "Browse VST3" button is hidden on those platforms).

### 2.1 — Dependency Setup

- Clone `flutter_vst3` toolkit locally: `git clone https://github.com/MelbourneDeveloper/flutter_vst3 packages/flutter_vst3`
- Add `dart_vst_host` as a local path dependency in `pubspec.yaml` (desktop-only via conditional import)
- Add `dart_vst_graph` as a local path dependency
- Build native VST3 host components: `cd packages/flutter_vst3 && ./setup.sh`
- Verify CMake build produces `libvst3host.so` (Linux) / `.dylib` (macOS) / `.dll` (Windows)

### 2.2 — Platform-Conditional Import Architecture

- Create `lib/services/vst_host_service_interface.dart` — abstract `VstHostService`:
  - `Future<void> initialize()`
  - `Future<List<String>> scanPlugins(List<String> searchPaths)`
  - `Future<Vst3PluginInstance> loadPlugin(String path)`
  - `void unloadPlugin(String id)`
  - `void setParameter(String pluginId, int paramId, double value)`
  - `Map<int, double> getParameters(String pluginId)`
- Create `lib/services/vst_host_service_stub.dart` — stub implementation (mobile/web) that throws "Not supported on this platform"
- Create `lib/services/vst_host_service_desktop.dart` — real implementation wrapping `dart_vst_host`
- Create `lib/services/vst_host_service.dart` — conditional export:
  ```dart
  export 'vst_host_service_stub.dart'
      if (dart.library.io) 'vst_host_service_desktop.dart';
  ```
- Register `VstHostService` in `MultiProvider`

### 2.3 — VST3 Plugin Scanner

- Implement `VstHostServiceDesktop.scanPlugins()` checking default OS paths:
  - Linux: `~/.vst3`, `/usr/lib/vst3`, `/usr/local/lib/vst3`
  - macOS: `~/Library/Audio/Plug-Ins/VST3`, `/Library/Audio/Plug-Ins/VST3`
  - Windows: `C:\Program Files\Common Files\VST3`
- Add a "Scan for VST3 Plugins" button in `PreferencesScreen` (desktop only)
- Cache scan results in `SharedPreferences` as `List<String>` of plugin paths + names
- Show scan progress via a modal with a `LinearProgressIndicator`

### 2.4 — Vst3SlotUI

- Create `lib/widgets/rack/vst3_slot_ui.dart`:
  - Shows plugin name, vendor, version
  - Lists all exposed parameters as labeled sliders (using `dart_vst_host` parameter descriptors)
  - "Open Plugin Editor" button — opens the VST3 native GUI window (via `VstHostService`)
  - "MIDI Channel" and "Role" controls (shared with `GrooveForgeKeyboardSlotUI`)
  - On mobile: renders a grey "Plugin unavailable on this platform" placeholder card

### 2.5 — .gf Format Update for VST3

- Update `ProjectService.saveProject()` to write VST3 parameter maps for `Vst3PluginInstance` slots
- Update `ProjectService.openProject()` to reconstruct `Vst3PluginInstance` from `.gf`, skipping gracefully on mobile (leaving a placeholder)
- Add platform field in `.gf` VST3 entry so mobile knows it's a desktop-only slot

### 2.6 — Testing

- Load a free VST3 (e.g., TAL-NoiseMaker) on Linux — verify parameters appear in `Vst3SlotUI`
- Save a project with a VST3 slot as `.gf`, reload — verify parameters are restored
- Open the same `.gf` on Android — verify the VST3 slot shows a placeholder, not a crash
- Verify `.gf` files containing only built-in plugins work identically on all platforms

---

## Phase 3 — GrooveForge Keyboard as Distributable VST3

> Packages the built-in synthesizer/vocoder as a proper `.vst3` bundle loadable in Reaper, Ardour, Bitwig, Ableton, FL Studio, etc. This is a separate CMake build artifact, not part of the Flutter app build.

### 3.1 — VST3 SDK Setup

- Download VST3 SDK 3.8+ (MIT): `git clone https://github.com/steinbergmedia/vst3sdk vst3_plugin/vst3sdk`
- Verify SDK version is 3.8+ (MIT license) — check `vst3sdk/LICENSE.txt`
- Add `vst3sdk/` to `.gitignore` (large, fetched at build time)
- Add a `setup_vst3.sh` script at project root to clone the SDK automatically

### 3.2 — VST3 Plugin Project Scaffold

- Create `vst3_plugin/` directory at project root
- Create `vst3_plugin/CMakeLists.txt`:
  - Targets: `GrooveForgeKeyboard.vst3`
  - Links: `vst3sdk`, FluidSynth static lib, `native_audio/audio_input.c` (shared with app)
  - Platform install paths: `~/.vst3/` (Linux), `~/Library/Audio/Plug-Ins/VST3/` (macOS), `C:\Program Files\Common Files\VST3\` (Windows)
- Create `vst3_plugin/src/processor.cpp` — VST3 `IAudioProcessor` implementation:
  - Delegates MIDI note on/off to FluidSynth
  - Delegates vocoder processing to `audio_input.c` DSP (Linux/macOS/Windows builds only)
- Create `vst3_plugin/src/controller.cpp` — VST3 `IEditController` implementation:
  - Exposes parameters: soundfont path, bank, patch, vocoder waveform, noise mix, bandwidth, sibilance, gate threshold, gain
  - Parameter IDs match `.gf` state keys for round-trip compatibility
- Create `vst3_plugin/src/factory.cpp` — VST3 plugin factory registration
- Create `vst3_plugin/src/grooveforge_keyboard_ids.h` — VST3 class UIDs (generated with `uuidgen`)
- Create `vst3_plugin/resources/GrooveForgeKeyboard.uidesc` — VSTGUI layout (basic knobs + dropdown for soundfont)

### 3.3 — Shared Audio Engine Code

- Symlink or copy `native_audio/audio_input.c` into `vst3_plugin/src/` (or use CMake `include_directories`)
- Ensure `native_audio/audio_input.c` compiles cleanly as a static library without the Flutter FFI entrypoint
- Bundle FluidSynth as a static lib in the VST3 build (no dynamic dependency at runtime)
- Include default soundfont `assets/soundfonts/default.sf2` in the `.vst3` bundle's `Resources/` folder

### 3.4 — Build Targets

- Add `Makefile` targets at project root:
  - `make vst-linux` — builds `GrooveForge Keyboard.vst3` for Linux x86_64
  - `make vst-macos` — builds universal binary (Intel + Apple Silicon)
  - `make vst-windows` — cross-compile or native Windows build
  - `make vst-install` — installs to OS default VST3 folder
- Add GitHub Actions CI job: build VST3 on Ubuntu, macOS, Windows; upload as release artifacts

### 3.5 — flutter_vst3 Integration Option

- Evaluate replacing the raw CMake approach with `flutter_vst3` toolkit scaffold:
  - Pros: Dart audio processor, Flutter UI, less C++ boilerplate
  - Cons: IPC overhead, experimental status (43 stars)
  - Decision: **Start with raw CMake for performance-critical audio path, use flutter_vst3 only for the UI editor window if needed**

### 3.6 — Testing

- Load `GrooveForge Keyboard.vst3` in **Reaper** (Linux) — play notes via MIDI, change patches
- Load in **Ardour** (Linux) — verify MIDI routing and audio output
- Verify soundfont selection parameter updates the instrument in real time
- Verify vocoder activates when waveform parameter is set (Linux/macOS builds)
- Verify the plugin state saves/restores correctly when the DAW project is saved and reopened
- Test on macOS with Logic Pro / GarageBand
- Test on Windows with FL Studio / Reaper

---

## Housekeeping & Cross-Cutting

- Update `TODO.md` — mark Web and SF3 items as still pending (not in scope for v2.0.0), add VST3 hosting items from Phase 2 once complete
- Add `vst3sdk/`, `vst3_plugin/build/` to `.gitignore`
- Add `setup_vst3.sh` to project root (VST3 SDK auto-download)
- Add `vst3_plugin/` build instructions to `README.md`
- Trademark compliance: if using "VST3" branding in the UI or plugin name, follow [Steinberg trademark guidelines](https://www.steinberg.net/vst-instrument-and-plug-in-developer/Steinberg_VST_Plug-In_SDK_Licensing_Agreement.pdf) (logo usage rules, no implication of Steinberg endorsement)

---

## Version Plan


| Version | Phase   | Description                                                        |
| ------- | ------- | ------------------------------------------------------------------ |
| `2.0.0` | Phase 1 | Rack UI + GrooveForge Keyboard built-in plugin + .gf project files |
| `2.1.0` | Phase 2 | External VST3 hosting (desktop only)                               |
| `2.2.0` | Phase 3 | GrooveForge Keyboard as distributable `.vst3` bundle               |


---

*Last updated: 2026-03-08 — Phase 1 complete. Zero analyzer errors. Ready for smoke testing.*