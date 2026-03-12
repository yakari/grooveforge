# GrooveForge VST3 Plugins

Two distributable VST3 plugins — a **FluidSynth keyboard instrument** and a **band-vocoder effect** — written in pure C++ with no Dart runtime or IPC bridge.

> These are separate from the GFPA (GrooveForge Plugin API) built-in plugins.  
> See [GFPA vs VST3](#gfpa-built-in-plugins-vs-these-vst3-plugins) for when to use which.

---

## Plugins

### GrooveForge Keyboard (`grooveforge_keyboard.vst3`)

| Property | Value |
|---|---|
| Type | VST3 Instrument (`kInstrumentSynth`) |
| Audio out | Stereo |
| MIDI in | Yes (notes, channel-aware) |
| Parameters | Gain, Bank (0–127), Program (0–127) |
| Engine | FluidSynth 2.4 (built from source, static) |

Loads any SF2 soundfont. On first activation it searches common system paths:

```
/usr/share/sounds/sf2/FluidR3_GM.sf2
/usr/share/soundfonts/FluidR3_GM.sf2
/usr/share/sounds/sf2/default_soundfont.sf2
```

The soundfont path is saved in the DAW project state (`getState`/`setState`).

---

### GrooveForge Vocoder (`grooveforge_vocoder.vst3`)

| Property | Value |
|---|---|
| Type | VST3 Effect (`kFxModulation`) |
| Audio in | Mono (voice / microphone — sidechain) |
| Audio out | Stereo |
| MIDI in | Yes (notes drive the carrier oscillator) |
| Parameters | Waveform, Noise Mix, Bandwidth, Gate Threshold, Env Release, Input Gain |
| DSP | `vocoder_dsp.c` — 32-band phase vocoder, self-contained |

The voice signal comes from the DAW's audio input bus (standard sidechain routing). The vocoder does **not** capture the microphone itself — that is handled by the DAW, which gives you full routing flexibility (insert on a track, side-chain from another track, etc.).

**Ardour routing example:**
1. Create an audio track for your microphone → name it "Voice"
2. Create a MIDI track for keyboard input
3. Create a bus → add the Vocoder plugin → set its audio input to "Voice"
4. Send MIDI from the MIDI track to the Vocoder track

---

## Building

### Prerequisites

| Tool | Notes |
|---|---|
| CMake ≥ 3.20 | `sudo pacman -S cmake` |
| GLib2 dev headers | `sudo pacman -S glib2` — keyboard only |
| patchelf | `sudo pacman -S patchelf` — required for Flatpak bundling |
| git | For FluidSynth FetchContent (first keyboard build only) |

The VST3 SDK is bundled at `../vst3sdk/`. FluidSynth is fetched and compiled from source automatically on the first keyboard build (needs network access, takes ~3 min, then cached).

### Quick build (both plugins)

```bash
cd packages/flutter_vst3
make grooveforge          # build + install both to ~/.vst3/
```

### Build individually

```bash
make keyboard             # build + install keyboard
make vocoder              # build + install vocoder
```

The `make` targets always install a **real copy** (not a symlink) to `~/.vst3/`. This is required for Flatpak-sandboxed DAWs (Ardour, Reaper) which cannot follow symlinks outside the home directory.

### Manual CMake build

```bash
mkdir -p vsts/grooveforge_keyboard/build
cd vsts/grooveforge_keyboard/build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
# Plugin installed to ~/.vst3/ and symlinked from the build dir
```

---

## Architecture

```
grooveforge_keyboard/
├── include/grooveforge_keyboard_ids.h   — UIDs + parameter enum
└── src/
    ├── processor.cpp   — IAudioProcessor: FluidSynth synthesis
    ├── controller.cpp  — IEditController: Gain, Bank, Program
    └── factory.cpp     — GetPluginFactory + ModuleEntry (Linux)

grooveforge_vocoder/
├── include/grooveforge_vocoder_ids.h    — UIDs + parameter enum
└── src/
    ├── processor.cpp   — IAudioProcessor: vocoder_dsp.c bridge
    ├── controller.cpp  — IEditController: 6 DSP parameters
    └── factory.cpp     — GetPluginFactory + ModuleEntry (Linux)

../../../../native_audio/
├── vocoder_dsp.h        — Context-based vocoder DSP API
└── vocoder_dsp.c        — 32-band phase vocoder implementation
```

**Single compilation unit pattern:** `factory.cpp` `#include`s `processor.cpp` and `controller.cpp` directly. This keeps the build simple (one `.o` per plugin) and avoids cross-unit linkage issues with the VST3 factory macros.

**Linux entry points:** Every VST3 plugin on Linux must export three functions:

| Symbol | Purpose |
|---|---|
| `GetPluginFactory()` | Returns the plugin factory — standard VST3 |
| `ModuleEntry(void*)` | Called on `dlopen` — initialises SDK internals |
| `ModuleExit()` | Called on `dlclose` — tears down SDK internals |

`GetPluginFactory` comes from `pluginfactory.h`. `ModuleEntry`/`ModuleExit` come from `linuxmain.cpp` (included via `#if defined(__linux__)`). Missing either causes the host to report "Invalid VST3 plugin" or "missing ModuleEntry".

---

## Flatpak DAW compatibility

Both Ardour and Reaper on Linux are distributed as Flatpaks. Their sandbox isolates the plugin process from the host system's `/usr/lib`, so shared libraries must be either **bundled** inside the `.vst3` bundle or linked **statically**.

### Keyboard: static FluidSynth + minimal bundling

FluidSynth is built from source with **all audio backends disabled** (`-Denable-sdl3=OFF -Denable-portaudio=OFF -Denable-alsa=OFF` …). This eliminates the problematic system dependencies (SDL3, PortAudio, readline…) that require newer glibc than the Flatpak runtime provides.

The resulting plugin's only runtime dependency is **GLib2**, which is present in all Flatpak runtimes. Two small libraries (`libgomp.so.1`, `libpcre2-8.so.0`) are auto-bundled by `scripts/bundle_deps.sh` since they may not be in all runtimes.

### Vocoder: fully self-contained

The vocoder DSP is compiled statically into the plugin. Compiled with `-ffast-math`, the compiler inlines math functions (`sqrtf`, etc.) as hardware instructions — eliminating glibc versioned symbol references that would fail in older Flatpak runtimes.

The vocoder `.so` has **zero bundled dependencies**.

### `scripts/bundle_deps.sh`

A post-build script (called automatically by CMake) that:
1. Walks all `ldd` dependencies of the plugin `.so` recursively
2. Copies any library not present in the Flatpak runtime to the bundle's `Contents/x86_64-linux/` directory
3. Patches every bundled `.so`'s RPATH to `$ORIGIN`
4. Strips unused FluidSynth audio-backend entries from `libfluidsynth.so.3`'s `DT_NEEDED` (SDL3, PortAudio, readline) to remove glibc version requirements

Libraries excluded from bundling (guaranteed in the Flatpak runtime): glibc, libstdc++, JACK, ALSA, PipeWire, PulseAudio, GLib2, D-Bus, X11/XCB.

---

## GFPA built-in plugins vs. these VST3 plugins

GrooveForge has two plugin systems serving different purposes:

| | GFPA plugins | These VST3 plugins |
|---|---|---|
| **Where they run** | Inside the GrooveForge app (Android, iOS, Linux, macOS, Windows) | In any VST3-compatible DAW (Ardour, Reaper, etc.) |
| **Language** | Pure Dart | Pure C++ |
| **Distribution** | Compiled into the app | `.vst3` bundle, installed to `~/.vst3/` |
| **UI** | Flutter widgets (full GrooveForge UI) | DAW's generic parameter UI (no custom view) |
| **State** | GrooveForge project file (`.gf`) | DAW project / VST3 `setState`/`getState` |
| **Jam Mode** | Integrated (scale lock, chord detection) | Not available — DAW handles MIDI routing |
| **Soundfont** | Selected in GrooveForge rack UI | Loaded from system paths, configurable via state |
| **Mic input** | Captured by GrooveForge's audio engine | Routed by the DAW as a sidechain audio bus |

**Use GFPA plugins** when performing or composing inside GrooveForge — they integrate with the Jam Mode scale lock, the virtual keyboard, and the project save system.

**Use these VST3 plugins** when you want to use GrooveForge's keyboard or vocoder DSP inside a professional DAW workflow, record to a DAW timeline, or combine them with other VST3 effects.

Both systems share the same underlying DSP (`vocoder_dsp.c`). The keyboard VST3 uses the same FluidSynth engine as the GFPA keyboard, just driven differently.

---

## Troubleshooting

**Plugin blacklisted by Ardour after a failed scan:**

Ardour does not retry blacklisted plugins. Clear the blacklist:
```bash
truncate -s 0 ~/.var/app/org.ardour.Ardour/cache/ardour9/vst3_x64_blacklist.txt
```
Then restart Ardour and scan again.

**"Invalid VST3 plugin" error:**

Means the library loaded but failed the VST3 interface check. Usually caused by a missing `ModuleEntry` export. Verify with the VST3 SDK validator:
```bash
./build/bin/Release/validator ~/.vst3/grooveforge_keyboard.vst3
```

**"libXxx: cannot open shared object file" inside Flatpak Ardour:**

A library used by the plugin isn't in the Flatpak runtime and wasn't bundled. Re-run `bundle_deps.sh` manually:
```bash
bash scripts/bundle_deps.sh \
    ~/.vst3/grooveforge_keyboard.vst3/Contents/x86_64-linux/grooveforge_keyboard.so \
    ~/.vst3/grooveforge_keyboard.vst3/Contents/x86_64-linux/
```
Then clear the blacklist and rescan.

**"GLIBC_x.xx not found" error:**

A bundled library was compiled against a newer glibc than the Flatpak runtime provides. `bundle_deps.sh` strips known offenders from `libfluidsynth.so.3`. For new cases, identify the problematic library with:
```bash
objdump -T ~/.vst3/grooveforge_keyboard.vst3/Contents/x86_64-linux/grooveforge_keyboard.so \
    | grep "GLIBC_2\.[3-9][0-9]"
```
If it's in the plugin `.so` itself (not a bundled dep), add `-ffast-math` to the relevant compile target in `CMakeLists.txt`.
