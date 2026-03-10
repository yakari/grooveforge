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
│   │   ├── GrooveForgeKeyboardPlugin   ← model for keyboard slots
│   │   ├── GFpaPluginInstance          ← model for all GFPA slots (Phase 3 ✅)
│   │   └── Vst3PluginInstance          ← desktop only (Linux/macOS/Windows)
│   ├── RackState (ChangeNotifier)      ← ordered slot list + engine sync
│   └── ProjectService (.gf JSON)       ← save/load/autosave project files
│
├── GFPA — GrooveForge Plugin API (Phase 3 ✅)
│   ├── packages/grooveforge_plugin_api/   ← pure Dart, no Flutter dep
│   │   ├── GFPlugin / GFPluginParameter / GFPluginContext
│   │   ├── GFInstrumentPlugin  (MIDI IN → AUDIO OUT)
│   │   ├── GFEffectPlugin      (AUDIO IN → AUDIO OUT)
│   │   └── GFMidiFxPlugin      (MIDI IN → MIDI OUT)
│   ├── packages/grooveforge_plugin_ui/    ← Flutter UI helpers for plugins
│   │   └── RotaryKnob, GFParameterKnob, GFParameterGrid
│   └── Built-in plugins
│       ├── GFKeyboardPlugin    (com.grooveforge.keyboard)
│       ├── GFVocoderPlugin     (com.grooveforge.vocoder)
│       └── GFJamModePlugin     (com.grooveforge.jammode)
│
├── Rack UI
│   ├── RackScreen                         ← reorderable rack (custom drag handles)
│   ├── RackSlotWidget                     ← per-slot wrapper + mini piano
│   │   ├── GrooveForgeKeyboardSlotUI      ← soundfont/patch/scale controls
│   │   ├── GFpaVocoderSlotUI              ← compact vocoder panel
│   │   ├── GFpaJamModeSlotUI              ← RC-20 style routing panel
│   │   └── Vst3SlotUI                     ← generic param sliders (desktop only)
│   └── AddPluginSheet                     ← pick: keyboard / vocoder / jam / vst3
│
└── GrooveForge Keyboard VST3 (separate CMake build, desktop only — Phase 3b)
    ├── native_audio/audio_input.c      ← shared with main app (vocoder DSP)
    ├── FluidSynth static lib           ← compiled in
    └── flutter_vst3 scaffold           ← IPC bridge + Dart audio processor
```

### .gf Project File Format (JSON)

> **v2.0.0 format** — the top-level `jamMode` block has been removed. All jam
> settings now live inside the `GFpaPluginInstance` state of a Jam Mode slot.
> The `role` field on keyboard slots is no longer written or read.

```json
{
  "version": "2.0.0",
  "savedAt": "2026-03-09T12:00:00Z",
  "plugins": [
    {
      "id": "slot-0",
      "type": "grooveforge_keyboard",
      "midiChannel": 1,
      "state": {
        "soundfontPath": "/path/to/guitar.sf2",
        "bank": 0,
        "patch": 25
      }
    },
    {
      "id": "slot-1",
      "type": "grooveforge_keyboard",
      "midiChannel": 2,
      "state": {
        "soundfontPath": null,
        "bank": 0,
        "patch": 4
      }
    },
    {
      "id": "slot-jam-0",
      "type": "gfpa",
      "pluginId": "com.grooveforge.jammode",
      "midiChannel": 0,
      "masterSlotId": "slot-1",
      "targetSlotIds": ["slot-0"],
      "state": {
        "enabled": false,
        "scaleType": "standard",
        "detectionMode": "chord",
        "bpmLockBeats": 0
      }
    }
  ]
}
```

> **GFPA Vocoder entry** (standalone slot with its own MIDI channel):
>
> ```json
> {
>   "id": "slot-voc-0",
>   "type": "gfpa",
>   "pluginId": "com.grooveforge.vocoder",
>   "midiChannel": 3,
>   "state": {
>     "waveform": 0,
>     "noiseMix": 0.05,
>     "envRelease": 0.02,
>     "bandwidth": 0.2,
>     "gateThreshold": 0.01,
>     "inputGain": 1.0
>   }
> }
> ```

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
>   "state": {
>     "parameters": { "0": 0.65, "1": 0.3 }
>   }
> }
> ```

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


| Feature                                | Linux | macOS | Windows | Android | iOS |
| -------------------------------------- | ----- | ----- | ------- | ------- | --- |
| GrooveForge Keyboard GFPA plugin       | ✅     | ✅     | ✅       | ✅       | ✅   |
| Vocoder GFPA plugin                    | ✅     | ⚠️¹   | ⚠️¹     | ✅       | ⚠️¹  |
| Jam Mode GFPA plugin                   | ✅     | ✅     | ✅       | ✅       | ✅   |
| External VST3 hosting                  | ✅     | ✅     | ✅       | ❌       | ❌   |
| .gf save/open                          | ✅     | ✅     | ✅       | ✅       | ✅   |
| Distributable .vst3 bundle             | ✅     | ✅     | ✅       | ❌       | ❌   |

> ⚠️¹ Vocoder audio input (`audio_input.c`) is only wired to ALSA on Linux and
> Android. macOS/iOS/Windows mic input integration is deferred to Phase 8.


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

## Phase 3 — GFPA Core + Built-in Plugin Migration ✅ COMPLETE

> Defines the GrooveForge Plugin API (GFPA) interfaces and migrates all three built-in components — the virtual keyboard, the vocoder, and Jam Mode — to implement them. This is **pure Dart work**, no native changes. It must land before the audio graph (Phase 5) so every built-in plugin is already a typed node when cable routing arrives. The distributable VST3 bundle (previously planned here) is deferred to Phase 3b and simplified by building on top of this foundation.

### Why now, before the audio graph?

The audio graph in Phase 5 connects slots via typed ports (MIDI IN/OUT, AUDIO IN/OUT). For that to work, every slot must declare its port profile. GFPA interfaces carry that port declaration. Migrating built-in plugins to GFPA in Phase 3 means Phase 5 finds everything already typed — no retrofitting required.

Jam Mode in particular becomes dramatically cleaner as a `GFMidiFxPlugin`: instead of global state shared across slots, it is a **slot you insert in the signal chain between two instruments**. In the patch view a Jam Mode plugin sits on a MIDI cable, intercepting note events, locking them to scale, and forwarding them downstream. Multiple independent Jam Mode slots can follow different masters with zero coupling. The old "Jam Mode IPC in a standalone VST3" design question disappears entirely.

### Design — GFPA Interface Hierarchy

```
GFPlugin (base)
  ├── GFInstrumentPlugin    MIDI IN → AUDIO OUT   (keyboard)
  ├── GFEffectPlugin        AUDIO IN → AUDIO OUT  (vocoder, reverb, …)
  └── GFMidiFxPlugin        MIDI IN → MIDI OUT    (Jam Mode, arpeggiator, …)
```

```dart
/// Shared base for all GFPA plugins.
abstract class GFPlugin {
  String get pluginId;           // reverse-DNS, e.g. "com.grooveforge.keyboard"
  String get name;
  String get version;
  GFPluginType get type;
  List<GFPluginParameter> get parameters;
  double getParameter(int paramId);
  void setParameter(int paramId, double normalizedValue);
  Map<String, dynamic> getState();
  void loadState(Map<String, dynamic> state);
  Future<void> initialize(GFPluginContext context);
  Future<void> dispose();
}

/// Instrument: converts MIDI events to audio frames.
abstract class GFInstrumentPlugin extends GFPlugin {
  void noteOn(int channel, int note, int velocity);
  void noteOff(int channel, int note);
  void pitchBend(int channel, double semitones);
  void controlChange(int channel, int cc, int value);
  void processBlock(Float32List outL, Float32List outR, int frameCount);
}

/// Effect: processes an audio stream in-place.
abstract class GFEffectPlugin extends GFPlugin {
  void processBlock(
    Float32List inL, Float32List inR,
    Float32List outL, Float32List outR,
    int frameCount,
  );
}

/// MIDI FX: transforms MIDI events before they reach a downstream instrument.
/// This is the interface Jam Mode implements.
abstract class GFMidiFxPlugin extends GFPlugin {
  /// Receive a batch of events for the current block; return transformed events.
  /// May reorder, transpose, drop, or add events.
  List<TimestampedMidiEvent> processMidi(
    List<TimestampedMidiEvent> events,
    GFTransportContext transport,
  );
}

class GFPluginContext {
  final int sampleRate;
  final int maxFramesPerBlock;
  final GFTransportContext transport;
}

class GFTransportContext {
  final double bpm;
  final int timeSigNumerator;
  final int timeSigDenominator;
  final bool isPlaying;
  final double positionInBeats;
}
```

### 3.1 — `grooveforge_plugin_api` Package

- [x] Create `packages/grooveforge_plugin_api/` — standalone Dart package, no Flutter dependency
- [x] `lib/src/gf_plugin.dart` — `GFPlugin`, `GFPluginType`, `GFPluginParameter` (`id`, `name`, `min`, `max`, `defaultValue`, `unitLabel`), `GFPluginContext`, `GFTransportContext`
- [x] `lib/src/gf_instrument_plugin.dart` — `GFInstrumentPlugin`
- [x] `lib/src/gf_effect_plugin.dart` — `GFEffectPlugin`
- [x] `lib/src/gf_midi_fx_plugin.dart` — `GFMidiFxPlugin`, `TimestampedMidiEvent` (`ppqPosition`, MIDI bytes)
- [x] `lib/src/gf_plugin_registry.dart` — `GFPluginRegistry` singleton (`register`, `all`, `instruments`, `effects`, `midiFx`)
- [x] `lib/grooveforge_plugin_api.dart` — barrel export
- [x] Add as a path dependency in the main `pubspec.yaml`
- [x] Create `packages/grooveforge_plugin_ui/` — Flutter companion package exposing reusable UI helpers (`RotaryKnob`, `GFParameterKnob`, `GFParameterGrid`) for use in GFPA plugin slot UIs

### 3.2 — Migrate GrooveForge Keyboard → `GFInstrumentPlugin`

- [x] Create `lib/plugins/gf_keyboard_plugin.dart` — implements `GFInstrumentPlugin`
  - `pluginId`: `"com.grooveforge.keyboard"`
  - `noteOn/Off/pitchBend/controlChange` — delegate to existing `AudioEngine` FFI calls
  - `processBlock` — no-op (FluidSynth writes to ALSA output directly)
  - `getState/loadState` — delegates to `GrooveForgeKeyboardPlugin` model fields
- [x] Register in `GFPluginRegistry` at app startup (always, all platforms)
- Note: `GrooveForgeKeyboardPlugin` model unchanged for backward compat; `GFKeyboardPlugin` is the runtime delegate

### 3.3 — Migrate Vocoder → `GFInstrumentPlugin`

- [x] Create `lib/plugins/gf_vocoder_plugin.dart` — implements `GFInstrumentPlugin`
  - `pluginId`: `"com.grooveforge.vocoder"`
  - `parameters`: waveform, noise mix, env release, bandwidth, gate threshold, input gain (6 params)
  - `processBlock` — no-op; vocoder DSP runs in native `audio_input.c` engine
  - `getState/loadState` — round-trips vocoder JSON fields
- [x] Register in `GFPluginRegistry` at startup (all platforms)
- [x] Vocoder is now a **standalone `GFpaPluginInstance` slot** with its own MIDI channel and piano
- [x] Create `lib/widgets/rack/gfpa_vocoder_slot_ui.dart` — waveform selector, param sliders, level meters
- Note: vocoder implemented as `GFInstrumentPlugin` (not `GFEffectPlugin`) because it needs a MIDI channel for note-on routing. Reclassification as true effect with audio cable (Phase 5) deferred.

### 3.4 — Migrate Jam Mode → `GFMidiFxPlugin`

- [x] Create `lib/plugins/gf_jam_mode_plugin.dart` — implements `GFMidiFxPlugin`
  - `pluginId`: `"com.grooveforge.jammode"`
  - **Parameters**: scale type, detection mode, BPM lock beats
  - `processMidi` — transforms note-on events to nearest in-scale pitch
  - `getState/loadState` — scale type, detection mode, BPM lock
- [x] Register in `GFPluginRegistry` at startup (all platforms)
- [x] Jam Mode is a **standalone `GFpaPluginInstance` slot** with `masterSlotId` + `targetSlotIds` (list — supports multiple simultaneous targets)
- [x] `RackState._syncJamFollowerMapToEngine()` reads `GFpaPluginInstance` jam slots and pushes independent `GFpaJamEntry` objects to `AudioEngine.gfpaJamEntries`
- [x] Create `lib/widgets/rack/gfpa_jam_mode_slot_ui.dart` — RC-20-inspired hardware-panel UI:
  - Signal-flow row: MASTER dropdown → amber LCD (live scale name + type tag) → TARGETS chips
  - LCD doubles as scale-type selector (tap to change); displays `[SCALE TYPE]` bracket only for families where the name is not self-describing (Standard, Jazz, Classical, Asiatic, Oriental)
  - Glowing LED enable/disable button with ON/OFF indicator
  - Controls strip with labeled `DETECT` (Chord / Bass note) and `SYNC` (Off / 1 beat / ½ bar / 1 bar) sections, each with explanatory tooltips
  - Visual toggle buttons for key borders and wrong-note dimming (moved from Preferences)
  - Responsive layout: wide (≥480 px) two-row panel; narrow (<480 px) stacked column; controls strip uses `Wrap` to reflow on very small screens
- [x] **Detection mode — Chord**: derives scale from `AudioEngine` chord detector (existing behaviour)
- [x] **Detection mode — Bass Note**: uses lowest active note on master channel as scale root. Ideal for walking bass lines.
- [x] **BPM Lock** (`1 beat` / `½ bar` / `1 bar`): scale root only changes on beat boundaries (stored in state, fully functional in Phase 4 when transport engine is wired)
- [x] Old `JamSessionWidget`, global `ScaleLockMode` preference, and `GrooveForgeKeyboardPlugin.jamEnabled/jamMasterSlotId` fields **removed** (dead code purge)
- [x] Default new project includes a pre-configured Jam Mode slot (master = CH 2, target = CH 1, inactive by default)

### 3.5 — `GFpaPluginInstance` Model & Rack Integration

- [x] Create `lib/models/gfpa_plugin_instance.dart` — `id`, `pluginId`, `midiChannel`, `state`, `targetSlotIds` (list), `masterSlotId`; `toJson/fromJson` with `"type": "gfpa"`; backward-compat reading of old `targetSlotId` (string)
- [x] `PluginInstance.fromJson` handles `"type": "gfpa"` → `GFpaPluginInstance.fromJson`
- [x] `RackState` holds `GFpaPluginInstance` entries; `addPlugin`, `removePlugin`, `_applyAllPluginsToEngine` all handle the new type
- [x] `AddPluginSheet` — Vocoder + Jam Mode tiles added (always visible on all platforms)
- [x] `RackSlotWidget` dispatches to `GFpaVocoderSlotUI` or `GFpaJamModeSlotUI`; MIDI channel badge hidden for channel-0 slots; piano shown for vocoder
- [x] `ReorderableListView` uses `buildDefaultDragHandles: false` — custom left-side drag handle in each slot header is the sole reorder control

### 3.6 — Audio Thread Integration (pre-graph)

Before Phase 5's audio graph exists, GFPA plugin audio is integrated via the existing engine mechanisms:

- [x] Vocoder GFPA slot: `RackState._applyGfpaPluginToEngine` assigns `vocoderMode` to the slot's MIDI channel; external MIDI controllers route to the vocoder via the standard `processMidiPacket` path (no omni-mode workaround needed)
- [x] Jam Mode GFPA slot: `RackState._syncJamFollowerMapToEngine` reads `masterSlotId`/`targetSlotIds` and populates `AudioEngine.gfpaJamEntries` (independent `GFpaJamEntry` objects, one per Jam Mode slot)
- [x] `AudioEngine._performChordUpdate` and `_propagateJamScaleUpdate` propagate scale changes to all GFPA jam followers independently of legacy per-channel scale lock
- [x] `GFJamModePlugin.processMidi` implemented as a proper `GFMidiFxPlugin` — ready for Phase 5 audio graph (not yet called by engine in Phase 3)
- [x] **MIDI routing fix**: removed erroneous omni-mode vocoder routing that caused all MIDI input to also trigger the vocoder channel regardless of target
- [x] **Startup hang fix** (`MidiService`): added `_isConnecting` guard to prevent concurrent `connectToDevice` calls when the 2-second polling timer races with `_tryAutoConnect` on Linux
- Note: Full `AudioEngine._renderFrame()` linear pass with `processBlock` calls deferred to Phase 5 when the audio graph replaces it entirely

### 3.7 — Localization

- [x] Add EN/FR keys: `rackAddVocoder`, `rackAddVocoderSubtitle`, `rackAddJamMode`, `rackAddJamModeSubtitle`
- [x] Remove obsolete EN/FR keys related to old jam mode UI (`jamStart`, `jamStop`, `jamMaster`, `scaleLockModeTitle`, `modeClassic`, `synthSaveFilters`, etc.)

### 3.8 — Testing

- [x] Vocoder inserted as a standalone slot on Linux — vocal processing audible
- [x] Vocoder responds to external MIDI controller on its assigned channel
- [x] Jam Mode plugin added between two keyboard slots — notes on slot A lock slot B to scale; highlighting and key borders visible on target slots
- [x] Jam Mode: changing scale type in the rack takes effect immediately without stop/restart
- [x] Jam Mode: multiple target slots supported (e.g. keyboard CH 1 + vocoder CH 3 both follow CH 2)
- [x] Jam Mode: active scale name displayed correctly with root note prefix ("C Minor Blues", not "Minor Blues")
- [x] Key labels (note names) visible on both white and black keys for active and fundamental notes
- [x] Two Jam Mode plugins, each following a different master — independent, no interference
- [x] Save/load project with GFPA slots — state round-trips cleanly
- [x] Old `.gf` files without GFPA slots continue to load without errors (backward compat)

---

## Phase 3b — GrooveForge Keyboard as Distributable VST3

> Deferred from original Phase 3. Now simpler: the C++ `IAudioProcessor` calls the same `audio_input.c` + FluidSynth DSP already used by the `GFEffectPlugin` and `GFInstrumentPlugin` implementations. Jam Mode is **not** included in the distributable VST3 — it lives in the GFPA layer and is exclusive to GrooveForge's own rack. No design question remains.

### 3b.1 — VST3 Plugin Scaffold

- [ ] Create `vst3_plugin/CMakeLists.txt` — links `vst3sdk` (reuse `packages/flutter_vst3/vst3sdk`), FluidSynth static lib, `native_audio/audio_input.c`
- [ ] `vst3_plugin/src/processor.cpp` — `IAudioProcessor`: MIDI note on/off → FluidSynth; vocoder DSP from `audio_input.c` (Linux only)
- [ ] `vst3_plugin/src/controller.cpp` — `IEditController`: parameters mirror `GFKeyboardPlugin.parameters` and `GFVocoderPlugin.parameters` IDs exactly (same normalized range, same unit labels)
- [ ] `vst3_plugin/src/factory.cpp` + `grooveforge_keyboard_ids.h` (generate UIDs with `uuidgen`)
- [ ] Bundle default soundfont in `Resources/` of the `.vst3` bundle

### 3b.2 — Build & CI

- [ ] `make vst-linux` → installs to `~/.vst3/`
- [ ] `make vst-macos` → universal binary
- [ ] `make vst-windows` → Win32 build
- [ ] GitHub Actions CI: build on Ubuntu/macOS/Windows, upload as release artifacts alongside the Flutter app

### 3b.3 — Testing

- [ ] Load in Reaper (Linux) — notes via MIDI, soundfont change, vocoder — verify audio
- [ ] Load in Ardour (Linux) — verify MIDI routing + audio output
- [ ] Save/restore plugin state in DAW project

---

## Housekeeping & Cross-Cutting

- Update `TODO.md` — mark Web and SF3 items as still pending (not in scope for v2.0.0), add VST3 hosting items from Phase 2 once complete
- Add `vst3sdk/`, `vst3_plugin/build/` to `.gitignore`
- Add `setup_vst3.sh` to project root (VST3 SDK auto-download)
- Add `vst3_plugin/` build instructions to `README.md`
- Trademark compliance: if using "VST3" branding in the UI or plugin name, follow [Steinberg trademark guidelines](https://www.steinberg.net/vst-instrument-and-plug-in-developer/Steinberg_VST_Plug-In_SDK_Licensing_Agreement.pdf) (logo usage rules, no implication of Steinberg endorsement)

---

## Version Plan


| Version | Phase   | Status      | Description                                                                      |
| ------- | ------- | ----------- | -------------------------------------------------------------------------------- |
| `2.0.0` | Phase 1 | ✅ Complete  | Rack UI + GrooveForge Keyboard built-in plugin + .gf project files               |
| `2.1.0` | Phase 2 | ✅ Complete  | External VST3 hosting (desktop only)                                             |
| `2.2.0` | Phase 3 | 🔜 TODO     | GrooveForge Keyboard as distributable `.vst3` bundle                             |
| `2.3.0` | Phase 4 | 🔜 TODO     | Transport engine: global BPM, time signature, play/stop, ProcessContext to VSTs  |
| `2.4.0` | Phase 5 | 🔜 TODO     | Audio signal graph + "Back of Rack" cable patching UI                            |
| `2.5.0` | Phase 6 | 🔜 TODO     | VST3 effect plugin support (insert FX chains per slot, master bus FX)            |
| `2.6.0` | Phase 7 | 🔜 TODO     | MIDI Looper (BPM-synced, per-slot, multi-track overdub)                          |
| `3.0.0` | Phase 8 | 🔜 TODO     | GrooveForge Plugin API (GFPA) — mobile-native plugin system (Android/iOS/all)   |
| `3.1.0` | Phase 9 | 🔜 TODO     | Audio looper (requires audio graph from Phase 5)                                 |


---

*Last updated: 2026-03-09 — Phases 4–9 planned. Transport engine, audio graph, cable patching UI, MIDI looper, GrooveForge Plugin API (GFPA), and audio looper. See below for full specification.*

---

## Phase 4 — Transport Engine (BPM + Clock)

> Pure Dart state + a single native `ProcessContext` struct injected into every VST3 audio callback. No audio graph changes required. Immediately unlocks BPM-synced parameters in any loaded VST3 (arpeggiators, tempo-synced LFOs, delay times, chorus rates).

### Design

A global `TransportEngine` (`ChangeNotifier`) holds:

```dart
class TransportEngine extends ChangeNotifier {
  double bpm;                  // beats per minute (20.0 – 300.0)
  int timeSigNumerator;        // e.g. 4
  int timeSigDenominator;      // e.g. 4 (power of two)
  bool isPlaying;
  bool isRecording;
  double positionInBeats;      // current playhead position in beats (fractional)
  int positionInSamples;       // absolute sample position since last play
  double swing;                // 0.0 = straight, 1.0 = full triplet swing (future)
}
```

The native ALSA audio thread reads this struct on every callback and populates the VST3 `ProcessContext` before calling `IAudioProcessor::process()`. All VST3 plugins that declare `IProcessContextRequirements` will automatically use the tempo.

### 4.1 — TransportEngine Model

- [ ] Create `lib/services/transport_engine.dart` — `ChangeNotifier` with `bpm`, `timeSigNumerator`, `timeSigDenominator`, `isPlaying`, `isRecording`, `positionInBeats`, `positionInSamples`, `swing`
- [ ] `play()`, `stop()`, `reset()` — updates state + notifies listeners
- [ ] `tapTempo()` — records tap timestamps, computes average BPM over last 4 taps, rejects outliers
- [ ] Register in `MultiProvider` in `main.dart`
- [ ] Wire `TransportEngine` to `VstHostService` so the ALSA thread reads it on each callback

### 4.2 — Native ProcessContext Integration

- [ ] Add `dvh_set_transport(bpm, timeSigNum, timeSigDen, isPlaying, positionInBeats, positionInSamples)` to `dart_vst_host` C++ API
- [ ] Call `dvh_set_transport` from `VstHostService` every time `TransportEngine` state changes (debounced — once per UI frame is fine)
- [ ] In `dart_vst_host_alsa.cpp`: read transport globals in `audioCallback()` and populate `ProcessContext` before `processor->process()`
- [ ] Set `ProcessContext::kTempoValid | kTimeSigValid | kProjectTimeMusicValid | kBarPositionValid | kCycleValid` flags appropriately
- [ ] On Windows/macOS stubs: same transport call, routes to WASAPI/CoreAudio equivalents

### 4.3 — Transport UI

- [ ] Add a compact transport bar to `RackScreen` app bar (or below the app bar): **BPM field** (tap to type, scroll to nudge ±0.1), **Tap Tempo button**, **▶ / ■ Play/Stop button**, **Time signature selector** (e.g. `4/4`)
- [ ] BPM nudge: long-press ± arrows for fine control; scroll wheel on desktop increments by 1
- [ ] Visual metronome pulse: a subtle indicator (beat flash, or a thin bar animating) so the user sees the grid without a full metronome click
- [ ] Optional audible metronome click (generated via FluidSynth or a short raw PCM buffer) toggleable per project

### 4.4 — .gf Format Update

- [ ] Add top-level `"transport"` object to `.gf` JSON (reserved immediately even before the engine is implemented):

```json
"transport": {
  "bpm": 120.0,
  "timeSigNumerator": 4,
  "timeSigDenominator": 4,
  "swing": 0.0,
  "metronomeEnabled": false
}
```

- [ ] `ProjectService` reads/writes `transport` key; missing key defaults to `bpm: 120.0, 4/4, swing: 0`
- [ ] Add `"audioGraph": { "connections": [] }` and `"loopTracks": []` as empty reserved keys in the same pass — prevents schema churn when Phases 5 and 7 land

### 4.5 — Localization

- [ ] Add EN/FR keys: `transportBpm`, `transportTapTempo`, `transportPlay`, `transportStop`, `transportTimeSig`, `transportMetronome`, `transportSwing`

### 4.6 — GFPA Transport Integration

When the transport engine lands, wire it to GFPA plugins via `GFTransportContext`:

- [ ] `GFTransportContext` already defined (Phase 3). Populate it from `TransportEngine` state in `RackState` before every `processMidi` / `processBlock` call.
- [ ] **Jam Mode BPM lock** — `GFJamModePlugin.processMidi` uses `transport.positionInBeats` and `bpmLockBeats` to gate scale-root changes at beat boundaries. Already implemented; becomes functional here.
- [ ] **Walking bass workflow** — practical example: set Jam Mode to `Bass Note` detection + `1 beat` BPM lock. Play a bass line on the master keyboard (one note per beat). The scale for the target keyboard snaps to that note's scale at each beat boundary → the target can improvise freely over the walking bass progression.
- [ ] Validate: play 4-note walking bass at 120 BPM → scale changes exactly on beat → confirm with metronome visual.

### 4.7 — Testing

- [ ] Load Surge XT → enable a BPM-synced LFO → verify it syncs to app BPM
- [ ] Change BPM while playing → verify plugin follows within one buffer
- [ ] Tap Tempo: 4+ taps, verify BPM computed correctly, verify outlier rejection
- [ ] Save/load project → verify BPM restored correctly
- [ ] Jam Mode walking bass: bass line at 120 BPM, 1-beat lock → target scale changes on beat ✓

---

## Phase 5 — Audio Signal Graph + "Back of Rack" Cable Patching UI

> The largest architectural change in the roadmap. Introduces a directed audio graph connecting rack slots, enables effect-to-instrument routing, and exposes it to the user through a visual cable patching interface modelled on the back of a modular rack.

### Design — Audio Graph Model

Each rack slot becomes an **audio graph node** with typed ports:

| Port type  | Direction | Color  | Description                                          |
| ---------- | --------- | ------ | ---------------------------------------------------- |
| MIDI IN    | Input     | Yellow | Receives MIDI events (from hardware or another slot) |
| MIDI OUT   | Output    | Yellow | Sends MIDI events to another slot's MIDI IN          |
| AUDIO IN L | Input     | Red    | Left-channel audio input (effects only)              |
| AUDIO IN R | Input     | White  | Right-channel audio input (effects only)             |
| AUDIO OUT L| Output    | Red    | Left-channel audio output                            |
| AUDIO OUT R| Output    | White  | Right-channel audio output                           |
| SEND OUT   | Output    | Orange | Taps a copy of the audio to a send bus               |
| RETURN IN  | Input     | Orange | Receives processed audio back from a send bus        |

A **connection** is a directed edge between one output port and one compatible input port:

```dart
class AudioGraphConnection {
  final String fromSlotId;
  final AudioPortId fromPort;   // enum: midiOut, audioOutL, audioOutR, sendOut
  final String toSlotId;
  final AudioPortId toPort;     // enum: midiIn, audioInL, audioInR, returnIn
}
```

Connection rules enforced at patch time:
- MIDI OUT → MIDI IN only
- AUDIO OUT L/R → AUDIO IN L/R only (types must match: L→L, R→R)
- SEND OUT → RETURN IN only
- No cycles (instrument A → effect B → effect A is blocked)

The `AudioGraph` service (a `ChangeNotifier`) holds the full `List<AudioGraphConnection>` and provides:

```dart
void connect(fromSlotId, fromPort, toSlotId, toPort);
void disconnect(connectionId);
List<AudioGraphConnection> connectionsFrom(slotId);
List<AudioGraphConnection> connectionsTo(slotId);
bool wouldCreateCycle(fromSlotId, toSlotId); // DFS check
List<String> topologicalOrder();             // determines audio processing order
```

### Design — "Back of Rack" Patch View

Inspired by the back panel of Reason's rack and hardware modular synthesizers. A single button in the top bar (🔌 or "Patch") flips the entire rack to show all slot back panels simultaneously.

**Front View** (default): existing rack UI with knobs, controls, jam mode chips.

**Patch View** (new): each slot card is replaced by its back-panel equivalent — a dark panel showing the slot name and a row of coloured virtual jacks.

```
┌─────────────────────────────────────────────────────────┐
│  SLOT 0 — Surge XT                              [FRONT] │
│  ◉ MIDI IN    ◎ MIDI OUT    ◉ AUDIO IN L    ◉ AUDIO IN R │
│  ◎ AUDIO OUT L    ◎ AUDIO OUT R    ◎ SEND OUT           │
└─────────────────────────────────────────────────────────┘
         │                              │
   ~~~~~~│~~ yellow cable ~~~~~~~~~~~~~~│~~~  (bezier overlay)
         │                              │
┌─────────────────────────────────────────────────────────┐
│  SLOT 1 — TAL Reverb                            [FRONT] │
│  ◉ MIDI IN    ◎ MIDI OUT    ◉ AUDIO IN L    ◉ AUDIO IN R │
│  ◎ AUDIO OUT L    ◎ AUDIO OUT R    ◎ SEND OUT           │
└─────────────────────────────────────────────────────────┘
```

Cables are rendered as **bezier curves** in a `CustomPainter` overlay covering the entire `ListView`. Each cable has a colour matching its type and a slight physics-based sag (constant downward bias on the midpoint control point). An active (connected) jack shows a filled circle; an unconnected jack shows an empty circle.

**Interaction — making a connection:**
1. User long-presses an output jack → a "live" bezier cable follows the finger/cursor
2. Compatible target jacks highlight (pulse animation); incompatible jacks dim
3. User releases finger over a compatible input jack → connection created, cable snaps into place
4. Tapping an existing cable → shows a context menu with "Disconnect" and "Cable colour" options

**Interaction — removing a connection:**
- Tap the cable → context menu with Disconnect
- Or tap the destination jack and drag the cable end off a valid target

### 5.1 — AudioGraph Model & Service

- [ ] Create `lib/models/audio_graph_connection.dart` — `fromSlotId`, `fromPort`, `toSlotId`, `toPort`, `id` (uuid), `cableColor` (optional override)
- [ ] Create `lib/models/audio_port_id.dart` — enum `{ midiIn, midiOut, audioInL, audioInR, audioOutL, audioOutR, sendOut, returnIn }`
- [ ] Create `lib/services/audio_graph.dart` (`ChangeNotifier`) — `connections`, `connect`, `disconnect`, `connectionsFrom`, `connectionsTo`, `wouldCreateCycle`, `topologicalOrder`, `toJson`, `fromJson`
- [ ] Register `AudioGraph` in `MultiProvider`
- [ ] `RackState` notifies `AudioGraph` when a slot is removed (auto-disconnect its cables)

### 5.2 — .gf Format Update

- [ ] `ProjectService` reads/writes `"audioGraph": { "connections": [...] }` key
- [ ] `AudioGraphConnection.toJson` / `fromJson` round-trips all fields

### 5.3 — Patch View UI

- [ ] Add "Patch" toggle button to `RackScreen` app bar — `ValueNotifier<bool> isPatchView`
- [ ] Create `lib/widgets/rack/slot_back_panel_widget.dart` — displays slot name + row of `_JackWidget`s per port type (present only if the slot type supports that port: instrument has no AUDIO IN, effect has no MIDI IN by default, etc.)
- [ ] `_JackWidget` — colored circle (filled = connected, outlined = free), label below, `GestureDetector` for long-press-to-start-cable and tap
- [ ] Create `lib/widgets/patch_cable_overlay.dart` — `CustomPainter` that reads `AudioGraph.connections`, computes jack positions from `GlobalKey`s on each `_JackWidget`, and draws:
  - Bezier cubic curves: P0 = source jack center, P3 = target jack center, P1/P2 computed for a natural sag
  - Stroke width = 4 dp, rounded cap, color per port type (yellow MIDI, red audio-L, white audio-R, orange send)
  - Semi-transparent shadow (blur 6 dp, opacity 0.4) for depth
- [ ] "Live cable" during drag: `_DragCableOverlay` (separate painter) renders the in-progress bezier following the pointer
- [ ] Highlight animation on compatible jacks during drag: pulsing ring using `AnimationController`
- [ ] Tap on cable body → `_CableContextMenu` → Disconnect action
- [ ] `RackScreen` wraps the reorderable list + overlays in a `Stack`:

#### 5.3.1 — Virtual Piano as MIDI source node

The in-app virtual piano (`VirtualPiano` widget) becomes a first-class MIDI OUT node in the audio graph, enabling tablet / multitouch use cases:

- [ ] `VirtualPianoSlot` — a lightweight rack slot (no audio output, no MIDI channel badge) that represents the touchscreen keyboard as a MIDI signal source. Its back panel exposes only a **MIDI OUT** jack.
- [ ] Users can cable `[Virtual Piano] MIDI OUT → [Jam Mode] MIDI IN → MIDI OUT → [Instrument] MIDI IN` to have the on-screen keyboard play through scale-locking on a tablet.
- [ ] A single `VirtualPianoSlot` can fan out to multiple Jam Mode instances in parallel (one cable per target), enabling creative multi-layer harmonisation from a single touch surface.
- [ ] The existing `VirtualPiano` widget remains unchanged on instrument slots (direct note dispatch). The new `VirtualPianoSlot` is an addable slot type from `AddPluginSheet` — intended for standalone MIDI routing on touch devices.
- [ ] In Phase 3, the `VirtualPianoSlot` back-panel design is documented but the cable is simulated via the existing `masterSlotId` field on Jam Mode slots (user sets "master = Virtual Piano slot" in the UI).

```dart
Stack(children: [
  ReorderableListView(...),           // front or back panels depending on isPatchView
  PatchCableOverlay(graph: audioGraph), // always rendered, no-op when empty
  if (draggingCable) DragCableOverlay(...),
])
```

### 5.4 — Native Audio Graph Execution

- [ ] `dart_vst_host`: add `dvh_set_processing_order(List<int> pluginIds)` — reorders ALSA callback processing to match topological sort
- [ ] `dart_vst_host`: add `dvh_route_audio(fromId, toId)` — connects the output buffer of `fromId` to the input buffer of `toId` instead of mixing directly to the ALSA output
- [ ] Built-in keyboard + FluidSynth: expose an `AudioBuffer` output hook so its PCM can be routed into an effect chain before reaching ALSA
- [ ] Master mix bus: any slot not explicitly routed to another slot's AUDIO IN feeds into the master mix, which is the final ALSA output

### 5.5 — Testing

- [ ] Patch Surge XT AUDIO OUT → TAL Reverb AUDIO IN → AUDIO OUT → master: verify reverb applied
- [ ] Patch MIDI OUT of slot 0 → MIDI IN of slot 1: verify notes played on slot 0 also drive slot 1
- [ ] Disconnect a cable → audio routing reverts immediately
- [ ] Save/load project → cables restored correctly
- [ ] Cycle detection: attempt to route A→B→A, verify refusal with user-facing error toast

---

## Phase 6 — VST3 Effect Plugin Support

> Distinguishes instrument and effect VST3 plugins and integrates them properly into the audio graph. Effect plugins appear as distinct slot types in the rack and can be connected to instruments via the patch view.

### Design

When loading a VST3 plugin, inspect its main audio bus configuration:

- **0 audio inputs + ≥ 1 audio outputs** → `Vst3PluginType.instrument`
- **≥ 1 audio inputs + ≥ 1 audio outputs** → `Vst3PluginType.effect`
- **≥ 1 audio inputs + 0 audio outputs** → `Vst3PluginType.analyzer` (display only, rare)

An **effect slot** in the rack looks different from an instrument slot:
- No MIDI channel badge (effects process audio, not MIDI — unless the effect also responds to MIDI, like a vocoder controlled by a MIDI note)
- No virtual piano
- Shows: plugin name, effect type chip (Reverb / Compressor / EQ / Delay / Other), parameter knobs, editor button
- In the patch view its back panel shows AUDIO IN L/R + AUDIO OUT L/R jacks (and optionally MIDI IN if the plugin declares a MIDI input bus)

### 6.1 — Plugin Type Detection

- [ ] `dvh_get_audio_input_count(pluginId)` — new FFI call, returns the number of audio input buses
- [ ] `dvh_get_audio_output_count(pluginId)` — returns number of audio output buses
- [ ] `VstHostService.loadPlugin()` — after loading, calls both, sets `Vst3PluginInstance.pluginType` field
- [ ] `AddPluginSheet` — shows two browsing options: "Load VST3 Instrument" and "Load VST3 Effect", but detection overrides at load time with an informational toast if the file type differs from what was selected

### 6.2 — Vst3PluginInstance Model Update

- [ ] Add `Vst3PluginType pluginType` enum field to `Vst3PluginInstance` (`.instrument`, `.effect`, `.analyzer`)
- [ ] `toJson/fromJson` updated for new field
- [ ] `PluginInstance.availablePorts` — computed property based on `pluginType`:
  - Instrument: `[midiIn, audioOutL, audioOutR, sendOut]`
  - Effect: `[audioInL, audioInR, audioOutL, audioOutR, sendOut, returnIn]`

### 6.3 — Effect Slot UI (Vst3EffectSlotUI)

- [ ] Create `lib/widgets/rack/vst3_effect_slot_ui.dart` — reuses `Vst3SlotUI` parameter knob system, removes piano + MIDI badge, adds effect-type category chip in the header
- [ ] Effect type chip auto-detected from plugin name heuristics (contains "Reverb", "Comp", "EQ", "Delay", "Chorus", "Dist", etc.) and from VST3 `kFx` sub-category metadata if available
- [ ] `RackSlotWidget` dispatches to `Vst3EffectSlotUI` when `pluginType == effect`

### 6.4 — Insert FX Chain (per instrument slot, optional shortcut)

While the full audio graph (Phase 5) is the canonical routing mechanism, a simplified **insert FX chain** UI shortcut is useful for the common case of "apply a reverb to this synth":

- [ ] Each instrument slot card has an expandable **"FX Inserts"** section below the controls (collapsed by default, `▸ FX (0)` chip)
- [ ] Tapping `▸ FX` expands a mini-list of effect slots chained in series
- [ ] `+` button adds an effect slot inline (opens `AddPluginSheet` filtered to effects only)
- [ ] Dragging inside the mini-list reorders effects in the insert chain
- [ ] This is syntactic sugar over the audio graph: under the hood it creates `audioOutL/R → audioInL/R` connections automatically
- [ ] The patch view still shows these as explicit cables

### 6.5 — Testing

- [ ] Load a compressor VST3 effect (e.g. dragonfly, LSP Compressor) — verify detected as effect type
- [ ] Insert after Surge XT — verify audio passes through and effect is audible
- [ ] Reorder effects in insert chain — verify order reflected in audio processing
- [ ] Save/load project — verify effect slots and connections restored

---

## Phase 7 — MIDI Looper

> A BPM-synced MIDI recording and playback system. Purely Dart-side (no native audio required). Records MIDI events from any rack slot over N bars, loops them in sync with the transport clock, and supports multi-layer overdub.

### Design

A **loop track** is associated with one or more rack slots (its MIDI targets). It records raw `MidiEvent`s (note-on, note-off, CC, pitch bend) with PPQ timestamps. On playback, events are dispatched to the target slots' `noteOn/Off/cc/pitchBend` handlers at the correct times.

```dart
class LoopTrack {
  final String id;
  String name;
  int lengthInBars;                      // 1, 2, 4, 8, 16
  List<String> targetSlotIds;            // which slots receive playback
  List<TimestampedMidiEvent> events;     // sorted by ppqPosition
  LoopTrackState state;                  // idle | armed | recording | playing | overdubbing | muted
  double volumeScale;                    // 0.0 – 1.0 playback velocity multiplier
  bool muted;
}

class TimestampedMidiEvent {
  final double ppqPosition;             // position in PPQ within the loop
  final MidiEvent event;
}
```

The **LooperEngine** (`ChangeNotifier`) manages all loop tracks:
- Listens to `TransportEngine` position changes on every audio tick
- Dispatches playback events to `AudioEngine` at the correct PPQ positions
- Records incoming MIDI events (routed from `AudioEngine.onMidiIn` stream) into the armed track

### 7.1 — LooperEngine Service

- [ ] Create `lib/services/looper_engine.dart` — `ChangeNotifier`, `List<LoopTrack> tracks`
- [ ] `armTrack(trackId)` — sets track to `armed`; on the next downbeat (bar boundary), switches to `recording`
- [ ] `stopRecord(trackId)` — on next downbeat, stops recording, switches to `playing`, trims `events` to `lengthInBars` bars worth of PPQ
- [ ] `overdub(trackId)` — continues playing while also recording new events layered on top
- [ ] `clear(trackId)` — removes all events, sets state to `idle`
- [ ] `mute(trackId)` / `unmute(trackId)` — suppresses playback dispatch without losing events
- [ ] `_tick(ppqPosition)` — called from `TransportEngine` on every UI frame (~60 fps); dispatches any events whose `ppqPosition` falls within the current frame's window
- [ ] MIDI input routing: `AudioEngine` exposes a `Stream<MidiEvent> midiInStream` that `LooperEngine` subscribes to when a track is armed/overdubbing

### 7.2 — LoopTrack Model

- [ ] Create `lib/models/loop_track.dart` — all fields above, `toJson/fromJson` round-trip
- [ ] `TimestampedMidiEvent.toJson` encodes `ppqPosition` + MIDI bytes
- [ ] `LoopTrackState` enum

### 7.3 — .gf Format Update

- [ ] `ProjectService` writes/reads `"loopTracks": [...]` array
- [ ] Each track serialized with: `id`, `name`, `lengthInBars`, `targetSlotIds`, `events` array, `volumeScale`, `muted`
- [ ] Events stored compact: `[ppq, status, data1, data2]` tuples

### 7.4 — Looper UI

- [ ] Add a **Looper Panel** below the transport bar in `RackScreen` (or as a collapsible drawer from the bottom edge)
- [ ] Panel shows a horizontal scrollable list of `LoopTrackCard`s
- [ ] `LoopTrackCard` displays:
  - Track name (editable inline)
  - State indicator light (idle=grey, armed=yellow pulse, recording=red pulse, playing=green, overdub=orange)
  - Length selector: `1 / 2 / 4 / 8 / 16` bars (segmented control)
  - Target slots: compact chip list showing which slot(s) feed / receive this track
  - **Rec** button — arms recording (starts on next downbeat when transport is running)
  - **Play/Stop** button — manually toggle playback (independent of global transport for jamming freedom)
  - **Overdub** button — layers on top of existing events while playing
  - **Clear** button (with confirm)
  - **Mute** toggle
  - Mini event density visualization: thin bar showing note density across the loop length (drawn as a `CustomPainter`)
- [ ] `+` FAB in looper panel adds a new empty loop track, prompts for target slot selection
- [ ] Looper panel visibility toggle saved in preferences (not in `.gf`)

### 7.5 — Quantization

- [ ] Optional per-track quantization applied at record-stop time (not during recording, to preserve feel)
- [ ] Quantize values: off, 1/32, 1/16, 1/8, 1/4, 1/2
- [ ] Quantize snaps each event's `ppqPosition` to the nearest grid division
- [ ] "Humanize" slider (0–50ms random jitter) can be applied after quantize to restore feel

### 7.6 — Localization

- [ ] Add EN/FR keys: `looperPanel`, `looperAddTrack`, `looperRecord`, `looperStop`, `looperPlay`, `looperOverdub`, `looperClear`, `looperClearConfirm`, `looperMute`, `looperLength`, `looperTargetSlots`, `looperQuantize`

### 7.7 — Testing

- [ ] Record 2 bars of notes on Surge XT → verify playback loops at correct tempo
- [ ] Change BPM → verify loop playback stretches/compresses correctly (PPQ-based, not time-based)
- [ ] Overdub adds notes without erasing existing ones
- [ ] Clear removes all events
- [ ] Mute suppresses audio without stopping the internal playhead
- [ ] Save/load project → loop tracks with events restored
- [ ] Quantize 1/16 → verify event positions snapped

---

## Phase 8 — Plugin Ecosystem: GFPA + Platform Bridges (AudioUnit / AAP)

> Mobile platforms cannot host VST3. This phase adds plugin extensibility on all platforms through a **three-tier strategy**: a first-party pure-Dart plugin API (GFPA) as the universal baseline, an AudioUnit v3 bridge for iOS and macOS, and a future AAP bridge for Android. Each tier targets a different trade-off between simplicity and ecosystem reach.

### Existing Art — Why Not Just Use These?

Before designing GFPA, two existing standards were evaluated:

#### [AAP — Audio Plugins For Android](https://github.com/atsushieno/aap-core)

AAP (MIT license) is the most serious effort to bring a VST3-like format to Android. Its design is well thought-out, and it supports JUCE and LV2 wrappers. However, several factors make it a poor primary choice for GrooveForge today:

| Concern | Detail |
|---|---|
| **Out-of-process model** | Plugins run as separate Android APKs communicating via Binder IPC. Even with shared-memory audio buffers (ashmem), the cross-process marshalling adds architectural complexity and latency overhead per callback. |
| **No Flutter integration** | AAP exposes a Kotlin + NDK API. Bridging it into Flutter requires writing a full native Flutter plugin (Kotlin method channel + C++ FFI glue). Non-trivial effort with no existing package to build on. |
| **API still evolving** | v0.9.1.1 (April 2025) — the project itself warns "we wouldn't really consider our API as stable". |
| **Tiny ecosystem** | Very few AAP-native plugins exist. Most value comes from JUCE/LV2 wrappers, which require building those plugins specifically for AAP. |
| **User distribution friction** | Each plugin is a separate APK install from outside the Play Store — significant UX friction for casual musicians. |

**Verdict**: AAP is worth monitoring and a bridge (Phase 8c) is worth building once the ecosystem grows and the API stabilises. It is not the right foundation for GrooveForge's primary mobile plugin story today.

#### AudioUnit v3 (iOS / macOS)

Apple's AUv3 is the most compelling existing standard for GrooveForge's target platforms:

| Platform | Value |
|---|---|
| **iOS** | AUv3 is the **only** professional plugin format available. The ecosystem is large (Moog, Korg, Arturia, Eventide, etc. all ship AUv3). On iOS 13+, AUv3 plugins run as in-process extensions embedded inside another app — no separate install. |
| **macOS** | Alongside VST3 (already working), AUv3 hosting gives access to Logic Pro / GarageBand plugins and the entire Apple-native ecosystem. |

Integration requires Objective-C++ method channel code and `AVAudioEngine` / `AUAudioUnit` APIs, but the pattern is well-documented and Apple provides full reference implementations.

**Verdict**: AudioUnit v3 bridging is valuable, especially for iOS (Phase 8b). It is native-code work but not novel research.

### The Three-Tier Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│ Tier 1 — GFPA (all platforms, pure Dart)                       │
│  Zero FFI. Simple interfaces. Plugins distributed via pub.dev.  │
│  Built-in GF Keyboard and vocoder live here. Community effects. │
│  Works identically on Android, iOS, Linux, macOS, Windows.      │
├─────────────────────────────────────────────────────────────────┤
│ Tier 2 — AudioUnit v3 bridge (macOS + iOS, Phase 8b)           │
│  Hosts existing AUv3 plugins via AVAudioEngine + native code.   │
│  Massive ecosystem. The only professional option on iOS.         │
├─────────────────────────────────────────────────────────────────┤
│ Tier 3 — AAP bridge (Android, Phase 8c, post-ecosystem growth)  │
│  Hosts Android AAP plugins from other apps via Binder IPC.      │
│  Deferred until AAP ecosystem and API are more mature.           │
└─────────────────────────────────────────────────────────────────┘
```

All three tiers expose the same rack port model (MIDI IN/OUT, AUDIO IN/OUT) used in Phase 5. The audio graph does not know or care whether a node is GFPA, VST3, AUv3, or AAP.

### Platform Feature Matrix (post-Phase 8)

| Feature | Linux | macOS | Windows | Android | iOS |
|---|---|---|---|---|---|
| VST3 instruments | ✅ | ✅ | ✅ | ❌ | ❌ |
| VST3 effects | ✅ | ✅ | ✅ | ❌ | ❌ |
| GFPA instruments | ✅ | ✅ | ✅ | ✅ | ✅ |
| GFPA effects | ✅ | ✅ | ✅ | ✅ | ✅ |
| AudioUnit v3 | ❌ | ✅ | ❌ | ❌ | ✅ |
| AAP (Android) | ❌ | ❌ | ❌ | 🔜 8c | ❌ |

### Motivation

By Phase 8, the GFPA interfaces and all three built-in plugins (keyboard, vocoder, Jam Mode) are already implemented and running (Phase 3). This phase extends the ecosystem outward:

1. Publish `grooveforge_plugin_api` to pub.dev so third-party developers can depend on it
2. Ship the first-party effect library (reverb, delay, EQ, etc.) as standalone pub.dev packages
3. Add an in-app plugin store browser
4. Add a `GFAnalyzerPlugin` interface for visual plugins (spectrum analyser, oscilloscope, etc.)

### Design — Plugin Distribution

Third-party GFPA plugins are regular Dart packages added to the host app's `pubspec.yaml`. They declare a specific keyword so the in-app browser can discover them on pub.dev:

```yaml
# In a community GFPA plugin's pubspec.yaml:
name: grooveforge_reverb
keywords:
  - grooveforge_plugin
  - grooveforge_effect
```

Each package registers itself via `GFPluginRegistry.register(MyPlugin())` in its Flutter plugin entrypoint. The interfaces (defined in Phase 3) are already published as `grooveforge_plugin_api` on pub.dev.

### 8.1 — Publish `grooveforge_plugin_api` to pub.dev

- [ ] Prepare `packages/grooveforge_plugin_api/` for publication: `CHANGELOG.md`, `example/`, license headers, `dart pub publish --dry-run`
- [ ] Add `GFAnalyzerPlugin` interface (audio → visual data stream, no audio output) for spectrum analysers, oscilloscopes, etc.
- [ ] Tag v1.0.0 and publish

### 8.2 — First-Party GFPA Effect Plugins (mobile-first)

Once the GFPA framework is in place, implement the following as standalone packages:

| Package name              | Type       | Description                                          | Platforms |
| ------------------------- | ---------- | ---------------------------------------------------- | --------- |
| `gf_plugin_reverb`        | Effect     | Schroeder plate reverb (pure Dart DSP)               | All       |
| `gf_plugin_delay`         | Effect     | Stereo ping-pong delay, BPM-synced tap divisions     | All       |
| `gf_plugin_compressor`    | Effect     | RMS compressor with attack/release/ratio/makeup      | All       |
| `gf_plugin_eq`            | Effect     | 4-band parametric EQ (biquad filters)                | All       |
| `gf_plugin_chorus`        | Effect     | Stereo chorus / flanger, BPM-syncable rate           | All       |
| `gf_plugin_vocoder_mk2`   | Effect     | Improved vocoder replacing the built-in DSP          | All       |
| `gf_plugin_arpeggiator`   | MIDI FX    | BPM-synced arpeggiator, pattern editor               | All       |
| `gf_plugin_chord`         | MIDI FX    | Harmonizer / chord generator from single notes       | All       |

Each is a pure-Dart DSP implementation, no native code, works identically on Android, iOS, Linux, macOS, Windows.

### 8.3 — Plugin Store Browser (in-app)

- [ ] Add a "Plugin Store" tab or modal accessible from `AddPluginSheet`
- [ ] Queries pub.dev search API for packages with keyword `grooveforge_plugin`
- [ ] Shows plugin name, author, version, description, type chip (Instrument / Effect / MIDI FX)
- [ ] "Install" button copies the package name — since dynamic Dart compilation isn't possible, this is informational for now: it shows the `pubspec.yaml` entry the user needs to add and rebuild
- [ ] Long term (post-3.0): investigate Dart's `dart:mirrors` or native dynamic loading for truly hot-pluggable GFPA plugins without rebuild

### 8.4 — Localization

- [ ] Add EN/FR keys: `gfpaPluginStore`, `gfpaPluginInstall`, `gfpaPluginNotInstalled`, `gfpaAnalyzer`

### 8.5 — Testing (Phase 8)

- [ ] `grooveforge_plugin_api` published to pub.dev — third-party dev can implement `GFEffectPlugin` against it
- [ ] `gf_plugin_reverb` added to `pubspec.yaml` → appears in `AddPluginSheet` — audio processed on Android and iOS
- [ ] Plugin Store browser lists pub.dev packages with keyword `grooveforge_plugin`
- [ ] Unknown `pluginId` in `.gf` file → "Plugin not installed" placeholder, no crash
- [ ] `GFAnalyzerPlugin` slot renders spectrum data correctly without producing audio output

---

## Phase 8b — AudioUnit v3 Bridge (macOS + iOS)

> Hosts existing AUv3 plugins from the Apple ecosystem. On iOS this is the **only** path to third-party instrument and effect plugins. On macOS it complements VST3 hosting. Implementation is Objective-C++ native code behind a Flutter method channel.

### Design

AUv3 plugins on Apple platforms are loaded via `AVAudioEngine` and `AUAudioUnit`. On iOS 13+ they run in-process as app extensions embedded inside another app (no separate install step). On macOS they can also run out-of-process in a sandboxed host.

GrooveForge wraps AUv3 hosting in a `AuHostService` that mirrors the API of `VstHostService`:

```
AuHostService (Dart)
  ↕ method channel (platform thread safe)
AuHostPlugin (Objective-C++ / Swift)
  └── AVAudioEngine
        └── AUAudioUnit (the loaded AUv3 plugin)
              └── AUAudioUnitBus → connects to engine's main mixer
```

The existing `AudioGraph` (Phase 5) treats each AUv3 slot as an opaque node with typed audio ports, exactly as it does for VST3 nodes.

### 8b.1 — AuHostService (Dart)

- [ ] Create `lib/services/au_host_service_stub.dart` — no-op on non-Apple platforms
- [ ] Create `lib/services/au_host_service_apple.dart` — method channel client: `initialize`, `scanPlugins`, `loadPlugin(componentDescription)`, `unloadPlugin`, `noteOn/Off`, `getParameters`, `setParameter`, `startAudio`, `stopAudio`
- [ ] Create `lib/services/au_host_service.dart` — conditional export (`Platform.isMacOS || Platform.isIOS`)
- [ ] `AuPluginInfo` model — `name`, `manufacturer`, `componentType` (instrument/effect), `componentSubType`, `manufacturerCode` (four-char codes), `version`

### 8b.2 — Native AuHostPlugin (Objective-C++ / Swift)

- [ ] Create `ios/Classes/AuHostPlugin.swift` and `macos/Classes/AuHostPlugin.swift` (shared logic, platform-specific audio session)
- [ ] `scanPlugins` — calls `AVAudioUnitComponentManager.shared().components(passingTest:)`, returns serialized `AuPluginInfo` list filtered to `kAudioUnitType_MusicDevice` (instruments) and `kAudioUnitType_Effect`
- [ ] `loadPlugin` — `AVAudioUnit.instantiate(with:options:completionHandler:)`, connects to `AVAudioEngine`'s main mixer node
- [ ] `setParameter(paramId, value)` — `AUAudioUnit.parameterTree` lookup + `AUParameter.setValue`
- [ ] `getParameters` — serializes `AUParameterTree` to a list of `{id, name, min, max, value, unitName}` (mirrors `VstParamInfo`)
- [ ] `noteOn/Off` — `AUMIDIEventList` dispatch via `AUAudioUnit.scheduleMIDIEventBlock`
- [ ] Transport: `AUAudioUnit.transportStateBlock` wired to `TransportEngine` BPM + position
- [ ] iOS audio session: `AVAudioSession.setCategory(.playback, options: .mixWithOthers)` + interruption handling

### 8b.3 — AUv3 Slot UI

- [ ] `AuSlotUI` — mirrors `Vst3SlotUI`: category chips from `AUParameterGroup`s, `RotaryKnob` grid, "Show Plugin UI" button
- [ ] "Show Plugin UI" — `AUAudioUnitViewConfiguration` + `AUViewControllerBase`; on iOS presented as a modal sheet, on macOS as a floating window (equivalent to X11 editor on Linux)
- [ ] `AddPluginSheet` gains an "AudioUnit" browse option on Apple platforms — lists scanned `AuPluginInfo`

### 8b.4 — .gf Format

- [ ] AUv3 slot JSON:

```json
{
  "id": "slot-5",
  "type": "auv3",
  "platform": ["macos", "ios"],
  "componentType": "aumu",
  "componentSubType": "Rztr",
  "manufacturer": "Appl",
  "name": "AUSampler",
  "midiChannel": 1,
  "state": {
    "auPreset": { "...": "Apple AUPreset dict serialized as JSON" }
  }
}
```

- [ ] On non-Apple load: show platform-incompatible placeholder (same pattern as VST3 on Android)
- [ ] `AUAudioUnit.fullState` (NSDictionary) serialized to JSON for full state round-trip

### 8b.5 — Testing

- [ ] macOS: scan finds installed AUv3 plugins (GarageBand instruments, etc.)
- [ ] Load AUSampler or Moog Minimoog Model D — play notes via virtual keyboard — audio output via CoreAudio
- [ ] Load a built-in AU effect (AUReverb2, AUDelay) — insert after instrument — verify wet signal
- [ ] "Show Plugin UI" opens native AUv3 view inside a floating window
- [ ] iOS: scan finds available AUv3 instruments — load one — play notes — audio via speaker/headphones
- [ ] Save/load project: AUv3 `fullState` round-trips correctly, plugin restored after reload
- [ ] Open an AUv3 `.gf` on Linux → platform-incompatible placeholder, no crash

---

## Phase 8c — AAP Bridge (Android) *(Deferred — monitor ecosystem)*

> Hosts [AAP (Audio Plugins For Android)](https://github.com/atsushieno/aap-core) plugins from the Android app ecosystem via Binder IPC. Deferred until AAP's API stabilises further (currently v0.9.x) and the plugin ecosystem grows enough to justify the integration complexity.

### Why deferred?

1. **IPC latency**: AAP's out-of-process model routes every audio callback through Binder (mitigated by ashmem shared memory, but architectural overhead remains)
2. **No Flutter integration exists**: requires writing a full native Flutter plugin (Kotlin + NDK + Binder boilerplate) from scratch
3. **Small ecosystem**: most AAP "plugins" are JUCE or LV2 wrappers that require a specific build for AAP — users must install separate APKs from outside the Play Store
4. **Unstable API**: the project itself warns against treating the API as stable

### Trigger conditions to start 8c

Revisit this phase when **all** of the following are true:

- [ ] AAP reaches v1.0.0 with a stability commitment
- [ ] At least 10 high-quality instrument or effect plugins are available as AAP APKs
- [ ] A Flutter `flutter_aap_host` package exists on pub.dev (or a community contribution is offered)
- [ ] Binder IPC round-trip latency is measured to be < 5 ms on a mid-range Android device

### High-level design (for reference, not yet implemented)

- `AapHostService` — Kotlin-side `AudioPluginServiceConnector` wrapped behind a Flutter method channel
- Plugin discovery: queries `PackageManager` for services with `org.androidaudioplugin.AudioPluginService` intent filter
- Audio routing: AAP uses ashmem shared buffers; the Dart side passes buffer handles, not PCM data directly
- `.gf` format: `"type": "aap"`, `"packageName"`, `"pluginId"`, `"state"` (AAP preset blob)
- Port model: AAP plugin's declared ports mapped to audio graph AUDIO IN/OUT + MIDI IN/OUT jacks

### Reference

- AAP repository: https://github.com/atsushieno/aap-core (MIT license)
- AAP developer guide: https://github.com/atsushieno/aap-core/blob/main/docs/DEVELOPERS.md

---

## Phase 9 — Audio Looper

> Extends the MIDI looper from Phase 7 to record and play back **audio** (PCM samples). Requires the audio graph from Phase 5 to capture mixed audio from any bus or slot. Significantly more complex than MIDI looping due to memory, latency compensation, and synchronization.

### Design

An **audio loop clip** records the PCM output of a given audio bus into a ring buffer of length `N bars × samples-per-bar`. On loop boundary, it seamlessly transitions from write mode to read mode. Overdub layers on top by summing.

```dart
class AudioLoopClip {
  final String id;
  String name;
  int lengthInBars;
  String sourceBusId;              // which audio bus to capture from
  List<String> targetBusIds;       // where to send playback
  Float32List bufferL;             // left channel PCM
  Float32List bufferR;             // right channel PCM
  AudioLoopState state;
  double volumeScale;
  bool muted;
  bool reversed;                   // playback direction (creative effect)
}
```

### 9.1 — Audio Loop Engine

- [ ] `AudioLoopEngine` (`ChangeNotifier`) — manages `List<AudioLoopClip>`
- [ ] `armClip(clipId)` — allocates `bufferL/R` based on `lengthInBars × sampleRate × samplesPerBeat`; waits for next downbeat to start
- [ ] Recording: each audio callback, write `frameCount` frames of the source bus into `buffer[writeHead…]`; advance `writeHead`
- [ ] On loop boundary (writeHead wraps): switch to `playing` state, reset `readHead = 0`
- [ ] Playback: add `buffer[readHead…]` × `volumeScale` into the target bus output; advance `readHead` (wraps)
- [ ] Overdub: simultaneously read old buffer into output AND write new audio into buffer (summed)
- [ ] Latency compensation: measure round-trip latency (audio output → capture), shift `writeHead` back by latency samples so the loop aligns on the downbeat
- [ ] Memory cap: warn user if total clip memory exceeds 256 MB (configurable in preferences)

### 9.2 — Audio Loop UI

- [ ] `AudioLoopClipCard` in the Looper Panel (alongside MIDI loop track cards, visually distinguished)
- [ ] Waveform preview: `CustomPainter` draws the RMS envelope of `bufferL` after recording completes (decimated to ~300 points)
- [ ] Clip controls: Record, Play/Stop, Overdub, Clear, Mute, Reverse toggle
- [ ] Source bus selector: pick which audio bus to capture (Main, or a specific slot's audio out)

### 9.3 — Testing

- [ ] Record 4 bars of Surge XT output → verify seamless loop playback
- [ ] Overdub adds new audio without gaps
- [ ] Reverse plays clip backwards correctly
- [ ] Memory warning appears when clips exceed threshold
- [ ] Save/load project → clips preserved (embedded as base64 in `.gf` or referenced as sidecar `.pcm` files)

---

## .gf Format — Forward-Compatibility Summary

All keys below are **reserved immediately** in the current `ProjectService` to avoid format churn:

```json
{
  "version": "2.3.0",
  "name": "My Project",
  "createdAt": "2026-03-09T12:00:00Z",
  "transport": {
    "bpm": 120.0,
    "timeSigNumerator": 4,
    "timeSigDenominator": 4,
    "swing": 0.0,
    "metronomeEnabled": false
  },
  "jamMode": { "..." : "..." },
  "audioGraph": {
    "connections": [
      {
        "id": "conn-0",
        "fromSlotId": "slot-0",
        "fromPort": "audioOutL",
        "toSlotId": "slot-2",
        "toPort": "audioInL",
        "cableColor": null
      }
    ]
  },
  "loopTracks": [
    {
      "id": "loop-0",
      "name": "Bass line",
      "type": "midi",
      "lengthInBars": 4,
      "targetSlotIds": ["slot-0"],
      "volumeScale": 1.0,
      "muted": false,
      "quantize": "1/16",
      "events": [
        [0.0, 144, 60, 100],
        [1.0, 128, 60, 0]
      ]
    }
  ],
  "plugins": [ "..." ]
}
```

---

## Version Plan


| Version | Phase   | Status      | Description                                                                      |
| ------- | ------- | ----------- | -------------------------------------------------------------------------------- |
| `2.0.0` | Phase 1  | ✅ Complete  | Rack UI + GrooveForge Keyboard built-in plugin + .gf project files               |
| `2.1.0` | Phase 2  | ✅ Complete  | External VST3 hosting (desktop only)                                             |
| `2.2.0` | Phase 3  | 🚧 In Progress | GFPA core interfaces + migrate keyboard, vocoder, Jam Mode to GFPA plugins    |
| `2.2.x` | Phase 3b | 🔜 TODO     | Distributable GrooveForge Keyboard `.vst3` bundle (deferred, simpler post-3)     |
| `2.3.0` | Phase 4  | 🔜 TODO     | Transport engine: global BPM, time signature, play/stop, ProcessContext to VSTs  |
| `2.4.0` | Phase 5  | 🔜 TODO     | Audio signal graph + "Back of Rack" cable patching UI                            |
| `2.5.0` | Phase 6  | 🔜 TODO     | VST3 effect plugin support (insert FX chains per slot, master bus FX)            |
| `2.6.0` | Phase 7  | 🔜 TODO     | MIDI Looper (BPM-synced, per-slot, multi-track overdub)                          |
| `3.0.0` | Phase 8  | 🔜 TODO     | GFPA community plugins — first-party effects (reverb, EQ, delay…) + plugin store |
| `3.1.0` | Phase 8b | 🔜 TODO     | AudioUnit v3 bridge (macOS + iOS) — hosts AUv3 ecosystem plugins                 |
| `3.2.0` | Phase 9  | 🔜 TODO     | Audio looper (PCM, requires audio graph from Phase 5)                            |
| `TBD`   | Phase 8c | ⏸ Deferred  | AAP bridge (Android) — deferred pending AAP v1.0 + ecosystem growth              |


---

*Last updated: 2026-03-09 — Phases 4–9 specified. Transport engine, audio signal graph + cable patching UI, VST3 effect support, MIDI looper, GrooveForge Plugin API (mobile-native plugin system), audio looper.*

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