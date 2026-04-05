# GrooveForge Roadmap

> **Current released version:** 2.9.0
> **Next milestone:** TBD — MIDI Looper rework (remove chord detection, simplify, then add audio looper)
> **Next after looper:** 🔥 PipeWire migration (Linux audio backend — urgent)
> **Last updated:** 2026-04-03

---

## 📋 At a Glance

| Version | Phase | Status | Description |
|---|---|---|---|
| 2.0.0 | Phase 1 | ✅ Complete | Rack UI + built-in plugin + .gf project files |
| 2.1.0 | Phase 2 | ✅ Complete | External VST3 hosting (desktop) |
| 2.2.0 | Phase 3 | ✅ Complete | GFPA core + Keyboard / Vocoder / Jam Mode (all platforms) |
| 2.2.1 | Phase 3b | ✅ Complete | Distributable `.vst3` bundles (Linux) |
| 2.3.0 | Phase 4 | ✅ Complete | Transport engine: BPM, play/stop, tap tempo, VST3 ProcessContext |
| 2.4.0 | Phase 5 | ✅ Complete | Audio signal graph + "Back of Rack" cable patching UI |
| 2.5.0 | Phase 6 | ✅ Complete | MIDI Looper (multi-track, overdub, quantization) |
| 2.6.0 | Phase 7 | ✅ Complete | VST3 effect support + insert FX chain |
| 2.7.0 | Phase 8 Tier 1 | ✅ Complete | Six bundled GFPA effects as `.gfpd` + native C++ DSP |
| 2.8.0 | Phase 8 + 10 | ✅ Complete | MIDI FX node system (6 plugins); responsive `.gfpd` UI groups |
| 2.9.0 | Drum Generator | ✅ Complete | New Drum Generator features |
| **TBD** | **MIDI Looper rework** | **🔜 Next** | Remove chord detection; simplify engine + UI; keep bar display |
| TBD | PipeWire migration (Linux) | 🔥 Urgent — after looper | Replace direct ALSA with PipeWire/JACK; inter-app routing; lower latency |
| TBD | Multi-USB audio (Android) | 🔜 After PipeWire | Use AAudio `setDeviceId()` to route input/output to separate USB audio devices |
| TBD | Audio Looper (PCM) | 🔜 Likely after | Built on top of the simplified looper |
| TBD | Phase 8 (full) | ⏸ TBD | pub.dev publishing; plugin store; vocoder mk2 |
| TBD | Phase 8b | ⏸ TBD | AudioUnit v3 bridge (macOS + iOS) |
| TBD | Phase 8c | ⏸ TBD | AAP bridge (Android) — pending AAP v1.0 |

---

## 🏗️ Architecture Overview

The diagram below shows how GrooveForge's major components relate to each other. Everything runs in Flutter/Dart except the native audio DSP layer and the VST3 host bridge.

```mermaid
graph TD
    subgraph Rack["Rack Engine (Dart — all platforms)"]
        RS[RackState\nChangeNotifier]
        PI_KB[GFKeyboardPlugin\nbuilt-in instrument]
        PI_GF[GFpaPluginInstance\nGFPA wrapper]
        PI_V3[Vst3PluginInstance\ndesktop only]
        PI_LP[LooperPluginInstance\nMIDI looper slot]
        RS --> PI_KB
        RS --> PI_GF
        RS --> PI_V3
        RS --> PI_LP
    end

    subgraph GFPA["GFPA — grooveforge_plugin_api package"]
        GFI[GFInstrumentPlugin\nMIDI IN → AUDIO OUT]
        GFE[GFEffectPlugin\nAUDIO IN → AUDIO OUT]
        GFM[GFMidiFxPlugin\nMIDI IN → MIDI OUT]
    end

    subgraph Looper["MIDI Looper"]
        LE[LooperEngine\nPPQ-ticked playback]
        LT[LoopTrack\nbase + overdub layers]
        LE --> LT
    end

    subgraph Transport["TransportEngine"]
        TE[BPM · Play/Stop\nTap Tempo · Beat Ticks]
    end

    subgraph AudioGraph["Audio Graph"]
        AG[AudioGraph\nbuses + cable patching]
        BUS_IN[Input Buses]
        BUS_OUT[Output Buses]
        AG --> BUS_IN
        AG --> BUS_OUT
    end

    subgraph Project["ProjectService"]
        PS[.gf JSON\nversioned · auto-saved]
    end

    PI_GF -->|implements| GFI
    PI_GF -->|implements| GFE
    PI_GF -->|implements| GFM
    PI_LP --> LE
    TE -->|ProcessContext| PI_V3
    TE -->|beat ticks| LE
    RS --> AG
    RS -->|serialize| PS
    PS -->|restore| RS
```

---

## 📄 .gf Project Format

`.gf` files are plain JSON, versioned with a `"version"` field, and auto-saved on every meaningful state change. The `"plugins"` array is ordered — the index matches the visual rack slot order. Platform-exclusive slots (VST3, AUv3) carry a `"platform"` annotation so they degrade gracefully to a placeholder on unsupported systems.

### Example 1 — `grooveforge_keyboard` slot

```json
{
  "id": "slot-0",
  "type": "grooveforge_keyboard",
  "midiChannel": 1,
  "state": {
    "soundfontPath": "/path/to/guitar.sf2",
    "bank": 0,
    "patch": 25
  }
}
```

### Example 2 — `gfpa` slot (Jam Mode or Vocoder)

```json
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
```

A vocoder slot uses the same `"type": "gfpa"` envelope with `"pluginId": "com.grooveforge.vocoder"` and vocoder-specific `state` keys (`waveform`, `noiseMix`, `envRelease`, etc.).

### Example 3 — `vst3` slot (desktop-only)

```json
{
  "id": "slot-2",
  "type": "vst3",
  "platform": ["linux", "macos", "windows"],
  "path": "/home/user/.vst3/TAL-Reverb.vst3",
  "name": "TAL Reverb IV",
  "midiChannel": 3
}
```

When this file is opened on Android or iOS, `ProjectService` detects the `"platform"` mismatch and inserts a read-only placeholder slot instead of crashing.

---

## 🖥️ Platform Support

| Feature | Linux | macOS | Windows | Android | iOS | Web |
|---|---|---|---|---|---|---|
| GF Keyboard plugin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Vocoder plugin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Jam Mode plugin | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| External VST3 hosting | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| MIDI Looper | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Drum Generator | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Audio Looper (PCM) | 🔜 | 🔜 | 🔜 | 🔜 | 🔜 | ❌ |
| AUv3 hosting | ❌ | 🔜 | ❌ | ❌ | 🔜 | ❌ |
| AAP hosting | ❌ | ❌ | ❌ | 🔜 | ❌ | ❌ |
| Web MIDI | ❌ | ❌ | ❌ | ❌ | ❌ | 🔜 |

> ⚠️ = partially works (web has MIDI plugin limitations); 🔜 = planned but not yet shipped.

---

## 🔗 Resources

| Resource | URL | Purpose |
|---|---|---|
| VST3 SDK (MIT since v3.8) | https://github.com/steinbergmedia/vst3sdk | Core VST3 standard library |
| VST3 Developer Portal | https://steinbergmedia.github.io/vst3_dev_portal/ | API docs |
| flutter_vst3 toolkit | https://github.com/MelbourneDeveloper/flutter_vst3 | VST3 plugins & host from Dart |
| flutter_midi_engine (future) | https://pub.dev/packages/flutter_midi_engine | SF3 support + web MIDI |
| MuseScore General SF3 | ftp://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf3 | MIT-licensed default soundfont |
| AAP repository | https://github.com/atsushieno/aap-core | Android Audio Plugins (monitor) |

---

## 📋 Backlog — Unscheduled

Tasks that are confirmed desirable but not yet assigned to a version.

### 🖥️ Platform — Web

Web is a first-class target for GrooveForge's reach, enabling users to play and compose without installation. Both items below are blockers before any meaningful web experience can ship.

- [ ] **Web MIDI**: `flutter_midi_command` throws `MissingPluginException` on web. Integrate a web-compatible MIDI library (Web MIDI API).
- [ ] **Web platform checks**: refactor all `Platform.isLinux` / `Platform.isAndroid` calls to use `kIsWeb` from `flutter/foundation.dart` to avoid `Unsupported operation: Platform._operatingSystem` errors on web.

### 🎛️ Audio Engine

The current SF2 stack (`flutter_midi_pro`) lacks SF3 support, web compatibility, and standard MIDI CC handling. Migrating to `flutter_midi_engine` unblocks higher-quality default sounds and the web platform target simultaneously.

- [ ] **Migrate to `flutter_midi_engine`**: replace `flutter_midi_pro` to gain SF3 support, built-in reverb/chorus, 16-channel support, pitch bend, standard CC messages.
- [ ] **MuseScore General SF3**: switch to `MuseScore_General.sf3` (MIT) as the default soundfont once SF3 support lands on all platforms.

### 🎸 Instruments

These instrument-level enhancements extend the live-performance capability of the rack. MIDI OUT for the Theremin and Stylophone turns them into modulation sources that can drive any downstream slot.

- [ ] **MIDI out for Theremin + Stylophone**: add MIDI OUT jack so these instruments can drive keyboard/VST slots; add a "mute own sound" option.

### 🎼 Jam / Chord Progression

See the dedicated [Chord Progression](#-chord-progression-module) section below for the full design, motivation, and step-by-step breakdown.

- [ ] **Chord progression module**: grid of bars where each bar can hold one or more chords (one per beat, to support jazz/blues grids); synced with the transport (current beat advances the active chord); integrated with the Jam module so the active chord automatically locks the scale.

### 🎹 MIDI Looper — Enhancements

Deferred from Phase 6 and reassessed after the looper rework (Step 4). These build on the simplified engine and bar-strip UI.

- [ ] **Volume slider per track**: multiply velocity by a 0–100 % scale factor in `_fireEventsInRange`; add a `volumeScale` field to `LoopTrack` (persisted in `.gf`); expose via a compact slider in `_TrackRow`.
- [ ] **Long-press STOP → confirm-clear dialog**: replace the current one-tap CLEAR button with a long-press gesture on STOP that shows a confirmation `AlertDialog`, preventing accidental loop erasure during performance.
- [ ] **Humanize jitter**: add an optional random offset (0–50 ms, configurable per track) applied after quantize in `_applyQuantization`; stored as `humanizeMs` on `LoopTrack`.
- [ ] **`looperJumpToBar` CC action**: add a `jumpToBar` variant to `LooperAction` that maps CC value 0–127 to bar index; reset `recordingStartBeat` phase so playback jumps to the target bar on the next tick.
- [ ] **CC Mapping integration**: surface per-slot `LooperSession.ccAssignments` in the global `cc_preferences.dart` screen so users can manage looper CC bindings alongside other mappings.
- [ ] **Two looper slots simultaneously — no timing drift**: verify that two looper slots sharing the same `TransportEngine` clock stay phase-locked over 5+ minutes of continuous playback; add a regression test if drift is found.

### 📦 VST3 Bundles (Phase 3b — incomplete items)

These tasks complete the distributable `.vst3` bundle story started in Phase 3b. They are prerequisites for listing GrooveForge plugins in DAW plugin managers on macOS and Windows.

- [ ] Bundle default soundfont in `Resources/` of the keyboard `.vst3` bundle.
- [ ] `make vst-macos` → universal binary build.
- [ ] `make vst-windows` → Win32 build.
- [ ] GitHub Actions CI: build VST3 bundles on Ubuntu/macOS/Windows, upload as release artifacts.
- [ ] Load keyboard in Reaper (Linux) — MIDI note on/off, bank/program, state save/restore.
- [ ] Load vocoder in Reaper (Linux) — sidechain audio input, carrier oscillator modes.
- [ ] Save/restore plugin state in DAW project.

---

## 🎹 Next — MIDI Looper Rework

The current looper stores per-bar chord names (detected via `ChordDetector`) and displays them in a chord grid strip. This adds complexity for marginal benefit — the bar display itself (length, current bar, overdub position) is the genuinely useful part. The goal is to strip chord detection out entirely, simplify the engine and UI down to what matters, then build the audio looper on top of the cleaner foundation.

### ✅ Step 1 — Remove chord detection

- [x] Remove `chordsPerBar` / `chordPerBar` fields from `LoopTrack` model; remove from `toJson`/`fromJson`.
- [x] Remove `_detectBeatCrossings` and `_flushBarChord` from `LooperEngine`.
- [x] Remove `LoopTrack.detectAndStoreChord` and its `ChordDetector` dependency.
- [x] Remove `chordPerBar` from `.gf` save/load in `ProjectService` (keep backward-compat read that silently drops the field).
- [x] Update `LooperSlotUI` chord grid strip: replace chord name labels with plain bar-number cells (bar 1, bar 2, …). Keep: current-bar highlight, overdub-bar indicator, tap-to-set-resume-point.
- [x] Remove any `ChordDetector` import from looper-related files; verify `dart analyze` clean.

### ✅ Step 2 — Simplify the engine

- [x] Audit `LooperEngine` for any other dead code revealed by removing chord detection.
- [x] Simplify `LoopTrack` state machine if any transitions were chord-detection-gated.
- [x] Confirm `LoopTrack.toJson`/`fromJson` round-trips cleanly with the stripped model.
- [x] Verify old `.gf` files with `chordsPerBar` still load without error.

### ✅ Step 3 — UI cleanup & bar-alignment fix

- [x] Verify bar strip works correctly after removing chord labels: bar count, current-bar highlight, overdub indicator, resume-point tap.
- [x] Remove any chord-grid-related l10n keys that are now dead (`looperNoChord` removed from `app_en.arb` / `app_fr.arb`).
- [x] Run `flutter analyze` — no issues.
- [x] Fix bar-alignment bug: `_beginRecordingPass` now snaps `recordingStartBeat` to the preceding bar-1 downbeat so event offsets are bar-relative from the start; `_activatePlayback` sets `recordingStartBeat = anchorBeat` so stop/restart and save/reload produce identical playback alignment; removed `_firstEventOffset` (no longer needed).

### ✅ Step 4 — Deferred looper features (reassessed & implemented)

Features deferred during Phase 6, reassessed after the rework.

**Implemented:**
- [x] **Volume slider per track**: `LoopTrack.volumeScale` (0.0–1.0) persisted in `.gf`; velocity scaled in `_fireEventsInRange`; compact `_VolumeSlider` widget in `_TrackRow`.
- [x] **CC assignment UI**: `_CcAssignStrip` in `LooperSlotUI` — shows current bindings as chips (deletable); "Assign CC" button opens `_CcAssignDialog` (pick action → learn mode → move a knob/fader to bind). `LooperEngine.onCcLearn` callback + CC routing via `feedMidiEvent`.

**Already implemented** (no action needed):
- [x] Smart sync: tap Play 100 ms after downbeat → starts immediately — `_isAtBarBoundary` uses 0.1-beat tolerance (~50 ms at 120 BPM).
- [x] Smart sync: tap Play 400 ms after downbeat → waits for next downbeat — `startPlayback` already enters `waitingForBar` when mid-bar.

**Deferred to Backlog** (still relevant, lower priority):
- [x] Long-press STOP → confirm-clear dialog → moved to Backlog.
- [x] Optional "humanize" jitter (0–50 ms random offset after quantize) → moved to Backlog.
- [x] `looperJumpToBar` CC: map CC value 0–127 to bar index → moved to Backlog.
- [x] Integration with global CC Mapping settings screen → moved to Backlog.
- [x] Two looper slots playing simultaneously → no timing drift → moved to Backlog.

**Moved to Chord Progression Module** (depends on that feature, not the looper rework):
- [x] GFK → Looper → Jam Mode + GFK2 chain: scale locks follow recorded chord progression → see Chord Progression section.

### 🧪 Step 5 — Smoke test

- [ ] Record a 4-bar loop → bar strip shows 4 cells, current bar advances correctly during playback.
- [ ] Overdub → overdubbing bar highlighted correctly.
- [ ] Tap a bar cell → playback resumes from that bar.
- [ ] Save/load project → bar count and loop events restored; no crash on old files with `chordsPerBar`.

---

## 🎛️ TBD — PipeWire Migration (Linux) 🔥 Urgent

GrooveForge currently talks to ALSA directly via `snd_pcm_open` / `snd_pcm_writei` in a dedicated real-time thread (`dart_vst_host_alsa.cpp`). This works but has serious limitations for a professional audio application:

- **No inter-application routing**: users cannot route GrooveForge audio to/from other Linux audio tools (Ardour, Bitwig, Carla, system effects) without manual JACK bridging.
- **Exclusive device access**: ALSA PCM can only be opened by one application at a time (unless going through PulseAudio/dmix, which adds latency). The current code sets 50 ms latency as a workaround for "PipeWire/dmix compatibility."
- **No session management**: ALSA has no concept of audio sessions, port naming, or automatic reconnection — users must manually configure routing every time.
- **PipeWire is the standard**: Fedora, Ubuntu 22.10+, Arch, and most modern distros ship PipeWire as the default audio server. PipeWire's JACK-compatible API gives sub-5 ms latency while coexisting with desktop audio, and is the expected interface for pro audio apps on Linux in 2026.

Migrating to PipeWire (via the JACK client API) unblocks inter-app routing, proper port naming, session restore, and positions GrooveForge as a first-class citizen in the Linux pro audio ecosystem. The JACK API also works transparently on native JACK2 installations (e.g. older studio setups), so a single implementation covers both.

### Current architecture vs. target

```mermaid
graph LR
    subgraph Current["Current: Direct ALSA"]
        GF_A[GrooveForge\naudio thread] -->|snd_pcm_writei| ALSA_D[ALSA PCM\n'default' device]
        ALSA_D --> HW[Hardware]
    end

    subgraph Target["Target: PipeWire via JACK API"]
        GF_J[GrooveForge\nJACK client] -->|jack_port_register\njack_connect| PW[PipeWire\nJACK server]
        PW --> HW2[Hardware]
        PW <-->|inter-app routing| DAW[Ardour / Bitwig\n/ Carla]
        PW <-->|system audio| DESK[Desktop apps\n/ browser]
    end
```

### Affected files

| File | Current role | Migration impact |
|---|---|---|
| `packages/flutter_vst3/dart_vst_host/native/src/dart_vst_host_alsa.cpp` | ALSA real-time thread, PCM write loop, plugin processing | **Replace** with JACK client: `jack_client_open`, `jack_set_process_callback`, `jack_port_register` |
| `packages/flutter_vst3/dart_vst_host/native/CMakeLists.txt` | `find_package(ALSA REQUIRED)` | Replace with `pkg_check_modules(JACK REQUIRED jack)` |
| `packages/flutter_vst3/dart_vst_host/linux/CMakeLists.txt` | `find_package(ALSA REQUIRED)` | Replace with `pkg_check_modules(JACK REQUIRED jack)` |
| `packages/flutter_vst3/dart_vst_host/lib/src/bindings.dart` | FFI: `dvhStartAlsaThread` / `dvhStopAlsaThread` | Rename to `dvhStartJackClient` / `dvhStopJackClient`; add port query FFI |
| `packages/flutter_vst3/dart_vst_host/lib/src/host.dart` | `startAlsaThread(device)` / `stopAlsaThread()` | Rename to `startJackClient(clientName)` / `stopJackClient()`; add port connection API |
| `lib/services/vst_host_service_desktop.dart` | Calls `startAlsaThread()` | Call `startJackClient('GrooveForge')` |
| `native_audio/audio_input.c` | miniaudio for audio capture (uses ALSA backend internally) | Investigate switching miniaudio backend to JACK, or capture directly via JACK input ports |
| `.devcontainer/devcontainer.json` | `libasound2-dev` | Replace with or add `libjack-jackd2-dev` (or `pipewire-jack-audio-connection-kit-devel`) |

### 🎛️ Step 1 — Investigation & proof of concept

Before committing to the migration, validate assumptions and measure real-world latency.

- [ ] **Benchmark current ALSA latency**: measure round-trip latency of the existing `dart_vst_host_alsa.cpp` thread at 48 kHz / 256 samples on a PipeWire system (expected: ~50 ms due to the dmix workaround).
- [ ] **JACK API proof of concept**: write a standalone C program that opens a JACK client, registers stereo output ports, and plays a sine wave via `jack_set_process_callback`. Measure callback-to-hardware latency on PipeWire (target: < 10 ms at 256 samples / 48 kHz).
- [ ] **Verify JACK API availability on target distros**: confirm `libjack-jackd2-dev` (or PipeWire's `pipewire-jack` shim) is available on Ubuntu 22.04+, Fedora 38+, Arch, and Debian 12+.
- [ ] **Evaluate miniaudio JACK backend**: determine whether miniaudio's built-in JACK backend (`ma_backend_jack`) is suitable for the vocoder/audio-input path, or whether a direct JACK port approach is cleaner.
- [ ] **Design decision: JACK-only or ALSA fallback?** — decide whether to drop ALSA entirely or keep it as a compile-time fallback for embedded/headless systems. Document rationale.

### 🎛️ Step 2 — Engine migration

Replace the ALSA audio thread with a JACK client in `dart_vst_host`.

- [ ] **Create `dart_vst_host_jack.cpp`**: implement `dvh_start_jack_client(const char* clientName)` and `dvh_stop_jack_client()`; register stereo output ports (`GrooveForge:out_L`, `GrooveForge:out_R`) and optionally stereo input ports (`GrooveForge:in_L`, `GrooveForge:in_R`).
- [ ] **Port the audio render loop**: move the VST3 plugin processing, GFPA DSP insertion, and master render contributor mixing from the ALSA `while(running)` loop into the JACK `process_callback(jack_nframes_t nframes, void* arg)`.
  > The JACK process callback is already real-time-safe by contract (no alloc, no syscall) — the existing code mostly complies, but audit for any `snd_pcm_recover` or error-logging paths that must be removed.
- [ ] **Sample rate negotiation**: read sample rate from `jack_get_sample_rate()` instead of hardcoding; propagate to VST3 `ProcessContext` and FluidSynth instances.
- [ ] **Buffer size handling**: use `jack_get_buffer_size()` and handle `jack_set_buffer_size_callback` for dynamic changes; resize any internal buffers accordingly.
- [ ] **Auto-connect to system playback**: on startup, `jack_connect` output ports to `system:playback_1` / `system:playback_2` (PipeWire maps these to the default audio sink).
- [ ] **XRUN handling**: register `jack_set_xrun_callback` — log to a Dart-visible counter (not on the audio thread), surface in UI as a latency warning.
- [ ] **Update CMakeLists.txt** (both locations): replace `find_package(ALSA REQUIRED)` with `pkg_check_modules(JACK REQUIRED jack)`; link `${JACK_LIBRARIES}`.

### 🎛️ Step 3 — FFI & Dart API

Update the Dart bindings and high-level API to reflect the new backend.

- [ ] **Update `bindings.dart`**: rename `dvhStartAlsaThread` → `dvhStartJackClient`, `dvhStopAlsaThread` → `dvhStopJackClient`; add `dvhJackGetPorts()` and `dvhJackConnect(srcPort, dstPort)` for port management.
- [ ] **Update `host.dart`**: rename `startAlsaThread(device)` → `startJackClient(clientName)`, `stopAlsaThread()` → `stopJackClient()`; add `getAvailablePorts()` and `connectPorts(src, dst)` methods.
- [ ] **Update `vst_host_service_desktop.dart`**: call `startJackClient('GrooveForge')` instead of `startAlsaThread()`.
- [ ] **Port routing UI (stretch goal)**: expose available JACK ports in a "Connections" panel so users can route GrooveForge to/from other apps. This can be deferred to a follow-up if the auto-connect covers the common case.

### 🎛️ Step 4 — Audio input migration

Migrate the vocoder/audio-input path from miniaudio's ALSA backend to JACK.

- [ ] **Evaluate approach**: either switch miniaudio to `ma_backend_jack` in `audio_input.c`, or capture directly from the JACK input ports registered in Step 2.
- [ ] **Implement chosen approach**: ensure audio capture latency matches or improves on the current miniaudio/ALSA path.
- [ ] **Verify vocoder round-trip**: vocoder carrier + modulator must not introduce additional latency vs. the ALSA baseline.

### 🎛️ Step 5 — Build & CI

- [ ] **Update `.devcontainer/devcontainer.json`**: add `libjack-jackd2-dev` (or `pipewire-jack-audio-connection-kit-devel`) to `postCreateCommand`.
- [ ] **Update GitHub Actions Linux CI** (if applicable): install JACK dev headers in the build matrix.
- [ ] **Conditional compilation (if ALSA fallback kept)**: use a CMake option (`-DGFAUDIO_BACKEND=jack|alsa`) to select backend at build time; default to JACK.

### 🧪 Step 6 — Testing

- [ ] **Basic playback**: start GrooveForge on PipeWire → JACK client appears in `pw-jack`/`qjackctl` → audio plays through system speakers.
- [ ] **Latency measurement**: measure callback-to-output latency at 48 kHz / 256 samples — target < 10 ms (vs. current ~50 ms ALSA/dmix).
- [ ] **Inter-app routing**: route GrooveForge stereo out to Ardour input via `jack_connect` or Helvum — audio passes through.
- [ ] **VST3 processing**: load a VST3 instrument + VST3 effect chain — no xruns over 5 minutes of continuous playback.
- [ ] **Vocoder**: audio input capture works via JACK — vocoder processes live mic input.
- [ ] **FluidSynth keyboards**: GF Keyboard plays notes with correct latency and no clicks/pops.
- [ ] **Native JACK2 compatibility**: test on a system running native JACK2 (no PipeWire) — client connects and plays audio.
- [ ] **Graceful degradation**: if JACK server is not running, GrooveForge shows a clear error message (not a crash).

---

## 🎙️ TBD — Multi-USB Audio Device Routing (Android)

Android's default USB audio HAL binds to a single USB audio device per direction (input/output). When a user plugs a USB hub with both a jack output (for an amp/speakers) and a USB-C microphone, the system typically only activates one of them. This is an Android audio policy limitation, not a USB protocol issue.

### Background

- **Android ≤ 13**: the USB audio HAL selects one USB audio device per role; no app-level override.
- **Android 14+**: `AudioTrack.setPreferredDevice()` / `AudioRecord.setPreferredDevice()` and AAudio's `AAudioStreamBuilder_setDeviceId()` allow targeting specific `AudioDeviceInfo` instances. If the system enumerates both USB devices, an app can direct output to one and input to another.
- **OEM variability**: device enumeration through a USB hub is inconsistent across manufacturers. Some enumerate both devices; many only activate one. The OEM's `audio_policy_configuration.xml` heavily influences behavior.

### Reliable alternatives

| Approach | Reliability | Notes |
|---|---|---|
| USB composite audio device (single USB device exposing both input + output interfaces) | ✅ High | HAL sees one device; best option if user hardware supports it |
| Built-in mic + USB jack output | ✅ High | Android handles mixed built-in + USB routing well |
| Two separate USB devices on a hub + `setDeviceId()` | ⚠️ Variable | Works on some OEMs (Android 14+), fails on others |

### 🎙️ Step 1 — Investigation & proof of concept

- [ ] **Enumerate USB audio devices**: add a debug screen that calls `AudioManager.getDevices(GET_DEVICES_OUTPUTS | GET_DEVICES_INPUTS)` and lists all `AudioDeviceInfo` entries with their `type`, `id`, and `productName`. Test with a USB hub + two audio devices on 3+ Android devices from different OEMs.
- [ ] **AAudio multi-device PoC**: open two separate AAudio streams via Oboe — one output stream targeting device A (`setDeviceId(outputId)`), one input stream targeting device B (`setDeviceId(inputId)`). Verify both streams run simultaneously without errors.
- [ ] **Measure latency**: compare round-trip latency of the multi-device setup vs. single-device baseline. Document any additional latency introduced by the hub or device switching.
- [ ] **Document OEM compatibility matrix**: test on at least Samsung, Pixel, and Xiaomi devices; record which combinations work and which fail.

### 🎙️ Step 2 — Integration into GrooveForge audio engine

- [ ] **Device selector UI**: add an audio settings screen where users can independently choose input and output devices from the enumerated list. Default to "System default" for backwards compatibility.
- [ ] **Oboe stream builder changes**: when the user selects specific devices, pass `setDeviceId()` to the Oboe `AudioStreamBuilder` for each direction. Handle `ErrorDisconnected` gracefully (device unplugged mid-session).
- [ ] **Fallback behavior**: if `setDeviceId()` fails or the target device disappears, fall back to the system default device and notify the user via a snackbar.
- [ ] **Minimum API level gate**: guard the multi-device feature behind `Build.VERSION.SDK_INT >= 34` (Android 14). On older versions, show a single device selector with an explanation.

### 🎙️ Step 3 — l10n

- [ ] Add EN/FR keys: `audioDeviceInput`, `audioDeviceOutput`, `audioDeviceDefault`, `audioDeviceMultiUsbUnsupported`, `audioDeviceDisconnected`.

### 🧪 Step 4 — Testing

- [ ] USB hub + jack output + USB mic on Pixel (Android 14+) → both streams active, audio plays through jack while mic captures.
- [ ] USB hub + jack output + USB mic on Samsung → document result (pass/fail).
- [ ] Single USB audio device → works as before, no regression.
- [ ] Unplug USB device mid-session → graceful fallback to system default, no crash.
- [ ] Android < 14 → multi-device option hidden, single device selector shown.
- [ ] USB composite device (single device with both I/O) → works without needing multi-device routing.

---

## 🔊 TBD — Audio Looper (PCM)

> Builds on the simplified MIDI looper. Adds PCM recording alongside or instead of MIDI.

The Audio Looper extends the looper slot concept from MIDI events to raw PCM audio. This lets users layer live audio (vocals, guitar, synth output) the same way they layer MIDI — arm, record on the next downbeat, overdub, reverse. It also enables a hardware-style workflow where the entire rack output can be captured into a loop clip, not just MIDI note data.

### PCM signal flow

```mermaid
graph TD
    IN[Audio Input Bus] -->|audio frames per callback| WH[Ring Buffer\nWrite Head]
    WH -->|on loop boundary| CLIP[AudioLoopClip\nPCM buffer L+R]
    CLIP -->|readHead advance| RH[Playback Read Head]
    RH -->|× volumeScale| MIX[Output Bus Mix]
    RH -->|overdub: old buffer to output| WH
```

### 🔊 Engine

- [ ] `AudioLoopEngine` (`ChangeNotifier`) — manages `List<AudioLoopClip>`.
- [ ] `armClip(clipId)` — allocates `bufferL/R`; waits for next downbeat.
- [ ] Recording: write `frameCount` PCM frames per audio callback into ring buffer.
- [ ] On loop boundary: switch to `playing`, reset `readHead = 0`.
- [ ] Playback: add `buffer[readHead…] × volumeScale` to target bus; advance `readHead`.
- [ ] Overdub: simultaneously read old buffer to output AND write new audio (summed).
- [ ] Latency compensation: measure round-trip latency, shift `writeHead` back by that amount.
- [ ] Memory cap: warn if total clip memory exceeds 256 MB (configurable in preferences).

### 🔊 UI

- [ ] `AudioLoopClipCard` in the Looper Panel (visually distinct from MIDI track cards).
- [ ] Waveform preview: `CustomPainter` draws RMS envelope (decimated to ~300 points).
- [ ] Clip controls: Record, Play/Stop, Overdub, Clear, Mute, Reverse toggle.
- [ ] Source bus selector: pick which audio bus to capture (Main, or specific slot audio out).

### 🧪 Testing

- [ ] Record 4 bars of Surge XT output → seamless loop playback.
- [ ] Overdub adds audio without gaps.
- [ ] Reverse plays clip backwards correctly.
- [ ] Memory warning appears when clips exceed threshold.
- [ ] Save/load project → clips preserved (base64 embedded or sidecar `.pcm`).

---

## 📦 TBD — Phase 8 Full (pub.dev + Plugin Store)

Publishing `grooveforge_plugin_api` to pub.dev makes the GFPA an open ecosystem: any Dart developer can write and distribute GFPA instruments and effects as regular pub packages. The Plugin Store browser then closes the loop by letting users discover community plugins from inside the app.

### 📦 8.1 — Publish `grooveforge_plugin_api` to pub.dev

- [ ] Prepare `packages/grooveforge_plugin_api/` for publication: `CHANGELOG.md`, `example/`, license headers.
- [ ] Add `GFAnalyzerPlugin` interface (audio → visual data stream, no audio output).
- [ ] Run `dart pub publish --dry-run` — fix any issues.
- [ ] Tag v1.0.0 and publish.

### 📦 8.2 — First-Party Plugins (remaining)

| Asset | Type | Description | Status |
|---|---|---|---|
| `com.grooveforge.vocoder_mk2` | Effect | Improved vocoder (see design notes below) | [ ] pending |

**Vocoder Mk2 design** — improvements in priority order:
1. Unvoiced/voiced detection + noise path — detect unvoiced phonemes (/s/, /t/, /f/) via ZCR + autocorrelation; crossfade carrier/noise. Biggest single intelligibility win.
2. LPC analysis mode (~12 poles, Levinson-Durbin) — extracts vocal formants directly; more natural than fixed bands.
3. Formant shift (±N semitones on LPC poles) — changes vocal character without pitch shift.
4. Asymmetric envelope followers — per-band fast attack (~1 ms) / configurable release (30–80 ms).

### 📦 8.3 — Plugin Store Browser (in-app)

- [ ] Add "Plugin Store" modal accessible from `AddPluginSheet`.
- [ ] Query pub.dev search API for packages with keyword `grooveforge_plugin`.
- [ ] Show plugin name, author, version, description, type chip (Instrument / Effect / MIDI FX).
- [ ] "Install" button: display the `pubspec.yaml` entry the user must add and rebuild (informational — dynamic Dart compilation not possible yet).

### 📦 8.4 — Localization

- [ ] Add EN/FR keys: `gfpaPluginStore`, `gfpaPluginInstall`, `gfpaPluginNotInstalled`, `gfpaAnalyzer`.

### 🧪 8.5 — Testing

- [ ] `grooveforge_plugin_api` published to pub.dev — third-party dev can implement `GFEffectPlugin` against it.
- [ ] Plugin Store browser lists pub.dev packages with keyword `grooveforge_plugin`.
- [ ] Unknown `pluginId` in `.gf` file → "Plugin not installed" placeholder, no crash.
- [ ] `GFAnalyzerPlugin` slot renders spectrum data without producing audio output.

### 🧪 Smoke Tests (pending from earlier phases)

- [ ] Manual smoke test Phase 1: Linux.
- [ ] Manual smoke test Phase 1: Android.
- [ ] Phase 2.6 — Save project as `.gf`, reload — verify VST3 parameters restored.
- [ ] Phase 2.6 — Open same `.gf` on Android — verify placeholder shown, no crash.
- [ ] Phase 7.5 — Load a compressor VST3 effect (e.g. LSP Compressor) — verify detected as effect.
- [ ] Phase 7.5 — Insert compressor after Surge XT — audio passes through, effect audible.
- [ ] Phase 7.5 — Reorder effects in insert chain — verify processing order reflected.
- [ ] Phase 7.5 — Save/load project — effect slots and connections restored.
- [ ] Phase 10.2 — Medium layout: `TabBar` + `TabBarView` per group (phone landscape).
- [ ] Phase 10.3 — Validate layout at phone portrait (360×800), phone landscape (800×360), tablet portrait (768×1024), desktop (1280+).
- [ ] Phase 10.4 — Verify `Vst3SlotUI` category chips + modal usable on phone portrait.

---

## 🖥️ TBD — Phase 8b: AudioUnit v3 (macOS + iOS)

AUv3 is the mandatory plugin format for iOS (App Store rules prohibit bundling arbitrary DSP code outside of AUv3 containers) and the standard for GarageBand and Logic Pro integration on macOS. Shipping an AUv3 host unlocks the entire macOS/iOS third-party instrument and effect ecosystem for GrooveForge users without requiring desktop-side VST3 bridges.

### 🖥️ 8b.1 — AuHostService (Dart)

- [ ] `lib/services/au_host_service_stub.dart` — no-op stub for non-Apple platforms.
- [ ] `lib/services/au_host_service_apple.dart` — method channel: `initialize`, `scanPlugins`, `loadPlugin`, `unloadPlugin`, `noteOn/Off`, `getParameters`, `setParameter`, `startAudio`, `stopAudio`.
- [ ] `lib/services/au_host_service.dart` — conditional export (`Platform.isMacOS || Platform.isIOS`).
- [ ] `AuPluginInfo` model — `name`, `manufacturer`, `componentType`, `componentSubType`, `manufacturerCode`, `version`.

### 🖥️ 8b.2 — Native AuHostPlugin (Objective-C++ / Swift)

- [ ] `ios/Classes/AuHostPlugin.swift` + `macos/Classes/AuHostPlugin.swift` (shared logic, platform-specific audio session).
- [ ] `scanPlugins` — `AVAudioUnitComponentManager`, filter to `kAudioUnitType_MusicDevice` + `kAudioUnitType_Effect`.
- [ ] `loadPlugin` — `AVAudioUnit.instantiate`, connect to `AVAudioEngine` main mixer.
- [ ] `setParameter` — `AUParameterTree` lookup + `AUParameter.setValue`.
- [ ] `getParameters` — serialize `AUParameterTree` to `{id, name, min, max, value, unitName}`.
- [ ] `noteOn/Off` — `AUMIDIEventList` via `AUAudioUnit.scheduleMIDIEventBlock`.
- [ ] Transport — `AUAudioUnit.transportStateBlock` wired to `TransportEngine`.
- [ ] iOS audio session: `AVAudioSession.setCategory(.playback, .mixWithOthers)` + interruption handling.

### 🖥️ 8b.3 — AUv3 Slot UI

- [ ] `AuSlotUI` — category chips from `AUParameterGroup`s, `RotaryKnob` grid, "Show Plugin UI" button.
- [ ] "Show Plugin UI" — `AUViewControllerBase`; iOS: modal sheet; macOS: floating window.
- [ ] `AddPluginSheet` gains "AudioUnit" browse option on Apple platforms.

### 🖥️ 8b.4 — `.gf` Format

- [ ] AUv3 slot type `"type": "auv3"` with `componentType`, `componentSubType`, `manufacturer`, `auPreset`.
- [ ] On non-Apple load: show platform-incompatible placeholder, no crash.
- [ ] `AUAudioUnit.fullState` (NSDictionary) serialized to JSON for full state round-trip.

### 🧪 8b.5 — Testing

- [ ] macOS: scan finds installed AUv3 plugins (GarageBand instruments etc.).
- [ ] Load AUSampler or Moog Model D — play notes — audio via CoreAudio.
- [ ] Load built-in AU effect (AUReverb2, AUDelay) — insert after instrument — wet signal audible.
- [ ] "Show Plugin UI" opens native AUv3 view in floating window.
- [ ] iOS: scan finds AUv3 instruments — load one — audio via speaker/headphones.
- [ ] Save/load project: `fullState` round-trips, plugin restored after reload.
- [ ] Open AUv3 `.gf` on Linux → placeholder, no crash.

---

## 🖥️ Phase 8c — AAP Bridge (Android) ⏸ Deferred

Android Audio Plugins (AAP) are the emerging open standard for third-party audio plugins on Android, analogous to VST3 on desktop. GrooveForge defers this work until the ecosystem matures enough to justify the Binder IPC complexity — the four conditions below define "mature enough."

Revisit when **all** conditions are met:

- [ ] AAP reaches v1.0.0 with a stability commitment.
- [ ] At least 10 high-quality instrument/effect plugins available as AAP APKs.
- [ ] A `flutter_aap_host` package exists on pub.dev.
- [ ] Binder IPC round-trip latency < 5 ms on a mid-range Android device.

See [AAP repository](https://github.com/atsushieno/aap-core) for current status.

---

## 🎼 Chord Progression Module

A chord progression module lets users define a looping grid of bars, each bar holding one or more chords (one per beat — enabling jazz and blues ii-V-I grids, 12-bar blues, and similar patterns). The grid is synced to the transport: as playback advances beat by beat, the "active chord" changes. The Jam module reads the active chord to automatically derive and lock the scale — so all instruments snap to the right notes without manual intervention. This makes chord-locked live performance accessible without deep music theory knowledge.

### Component interaction

```mermaid
sequenceDiagram
    participant TE as TransportEngine
    participant CG as ChordGridEngine
    participant JM as GFpaJamModePlugin
    participant UI as ChordGridUI

    TE->>CG: beat tick (bar index, beat index)
    CG->>CG: advance activeBarIndex / activeBeatIndex
    CG-->>JM: activeChordNotifier changed
    JM->>JM: derive scale from active chord\n(e.g. C dom7 → C Mixolydian)
    JM-->>UI: repaint current bar/chord highlight
    UI-->>CG: user taps beat cell → chord picker
```

### 🎼 Step 1 — Data model

- [ ] **Chord progression module**: grid of bars where each bar can hold one or more chords (one per beat, to support jazz/blues grids); synced with the transport (current beat advances the active chord); integrated with the Jam module so the active chord automatically locks the scale.
- [ ] `ChordGrid` — ordered `List<ChordBar>`, max bar count configurable, JSON `toJson`/`fromJson`.
- [ ] `ChordBar` — ordered `List<ChordBeat>` (length = time signature numerator), `toJson`/`fromJson`.
- [ ] `ChordBeat` — `int rootNote` (MIDI pitch class 0–11) + `ChordQuality quality` (maj / min / dom7 / min7 / maj7 / dim / aug).
- [ ] JSON round-trip in `.gf` format: `"type": "chordGrid"` top-level key alongside `"plugins"`.
- [ ] l10n keys for chord quality names: `chordQualityMaj`, `chordQualityMin`, `chordQualityDom7`, `chordQualityMin7`, `chordQualityMaj7`, `chordQualityDim`, `chordQualityAug` (EN + FR).

### 🎼 Step 2 — Engine

- [ ] `ChordGridEngine` (`ChangeNotifier`) — holds a `ChordGrid` and an `activeChordNotifier` (`ValueNotifier<ChordBeat?>`).
- [ ] Subscribes to `TransportEngine` beat ticks; on each tick advances `activeBarIndex` / `activeBeatIndex` modulo grid length.
- [ ] Exposes `ChordBeat? get activeChord` — null when transport is stopped or grid is empty.
- [ ] Thread-safe write: beat ticks arrive from the audio thread; use atomic index updates, no lock on the hot path.

### 🎼 Step 3 — Jam integration

- [ ] `GFpaJamModePlugin` gains an optional `ChordGridEngine? chordGrid` reference.
- [ ] When `chordGrid` is set, derive the current scale from `activeChord` (e.g. C dom7 → C Mixolydian; A min → A Natural Minor) instead of using its manual scale setting.
- [ ] Auto-updates via `activeChordNotifier.addListener` — propagated as an atomic write to the scale state, never via `async`/`await`.
- [ ] When `chordGrid` is null or transport is stopped, fall back to the manually selected scale.

### 🎼 Step 4 — UI

- [ ] `ChordGridWidget` — horizontal scrollable bar grid; each bar displays its beats as cells.
- [ ] Tapping a beat cell opens a chord picker: root note wheel (C → B) + quality selector (chips or dropdown).
- [ ] Current beat cell highlighted in sync with transport (driven by `activeChordNotifier`).
- [ ] Responsive: desktop shows full grid inline; phone portrait collapses to a compact horizontal strip with a "Edit grid" sheet.

### 🧪 Step 5 — Smoke tests

- [ ] Enter a 12-bar blues grid (I7 / IV7 / V7 pattern) → play → verify active chord advances bar by bar.
- [ ] Verify Jam Mode scale updates on each chord change (e.g. C7 → C Mixolydian; F7 → F Mixolydian).
- [ ] Verify keyboard notes snap to correct scale on each chord change.
- [ ] Save/load project → grid restored exactly; no extra `ChordBeat` or missing bars.

---

## ✅ Completed Phases (for reference)

| Phase | Version | Summary |
|---|---|---|
| Phase 1 | 2.0.0 | Rack UI, GrooveForgeKeyboard plugin, .gf project files |
| Phase 2 | 2.1.0 | VST3 hosting (Linux/macOS/Windows), ALSA audio, X11 editor window |
| Phase 3 | 2.2.0 | GFPA interfaces, Keyboard/Vocoder/JamMode as GFPA plugins |
| Phase 3b | 2.2.1 | Distributable Keyboard + Vocoder `.vst3` bundles |
| Phase 4 | 2.3.0 | TransportEngine: BPM, tap tempo, ProcessContext to VST3, Jam Mode BPM lock |
| Phase 5 | 2.4.0 | AudioGraph, "Back of Rack" patch view, bezier cables, Virtual Piano slot |
| Phase 6 | 2.5.0 | MIDI Looper: multi-track, overdub, quantization, CC assignments, pinned slots |
| Phase 7 | 2.6.0 | VST3 effect slots, Vst3EffectSlotUI, insert FX chain shortcut |
| Phase 8 Tier 1 | 2.7.0 | Six `.gfpd` effects (reverb, delay, EQ, compressor, chorus, wah) + native C++ DSP |
| Phase 8 + 10 | 2.8.0 | Six MIDI FX plugins; `.gfpd` `groups:`; responsive plugin panels |
| Drum Generator | 2.9.0 | New Drum Generator features and improvements |

Full implementation notes for completed phases are preserved in `git log` and the per-version `CHANGELOG.md`.
