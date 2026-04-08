# GrooveForge 2.0

GrooveForge is a cross-platform Flutter DAW application. It connects to physical MIDI keyboards, hosts external VST3 plugins (desktop), runs a built-in multi-timbral synthesizer / vocoder, and supports real-time collaborative Jam Mode with scale locking across multiple plugin slots.

## Features

- **Plugin Rack** — an ordered, drag-and-drop rack of plugin slots. Add, remove, and reorder plugins at any time.
- **GrooveForge Keyboard** — the built-in plugin. Each slot has independent soundfont selection (`.sf2`), bank/patch assignment, a real-time vocoder, MIDI channel routing, and per-slot Jam Mode.
- **VST3 Hosting (Linux, planned on Windows)** — load any installed VST3 instrument or effect. Parameters are displayed as rotary knobs grouped by category. The plugin's native GUI opens in a separate floating window.
- **Jam Mode** — enable per-slot scale locking. Each slot picks a master slot; when the master plays a chord, all following slots lock to that scale. A global override pauses all following without losing individual settings.
- **Scale Lock & Highlighting** — binds notes to the selected scale with visual feedback (root / correct / wrong note colouring) on the on-screen keyboard.
- **Advanced CC Mapping** — map hardware knobs, sliders, and pads to MIDI effects or application actions (Patch Sweep, Global Scale Cycle, etc.).
- **Project Files** — save and restore complete rack configurations, including VST3 parameter snapshots, to a `.gf` JSON file. The last session is autosaved on every change.

## Platform Support

| Platform | Status | Notes |
|---|---|---|
| **Linux** | ✅ Primary target | Full Vocoder & VST3 hosting (ALSA audio, X11 editor windows), FluidSynth synthesis |
| **Android** | ✅ Supported | GrooveForge Keyboard only, with Vocoder; VST3 hosting is desktop-exclusive |
| **Windows** | 🔜 Planned | VST3 hosting plumbing in place; WASAPI audio not yet wired |
| **macOS** | ✅ Supported | Full Vocoder & VST3 hosting; App Sandbox must be disabled for 3rd-party VSTs |
| **iOS** | 🧪 Experimental | Basic build only; untested |

## Prerequisites

### All platforms

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (≥ 3.10)
- [Dart SDK](https://dart.dev/get-dart) (≥ 3.7) — bundled with Flutter
- Git

### Quick start with DevContainer

The repository includes a [DevContainer](.devcontainer/devcontainer.json) configuration that sets up the full Flutter development environment automatically — all Linux dependencies, VST3 test plugins (Surge XT, Aeolus), PulseAudio passthrough, and display forwarding. This is the fastest way to get a working build environment.

**Requirements:** Docker (or Podman), and VS Code with the Dev Containers extension _or_ any IDE with DevContainer support.

```bash
# Open in VS Code — the IDE will prompt to reopen in the container
code .

# Or build manually with the CLI
devcontainer up --workspace-folder .
```

> **Note:** The DevContainer routes audio to the host via PulseAudio socket and forwards
> the display (Wayland/X11) for GTK dialogs and VST3 editor windows. USB devices
> (`/dev/bus/usb`, `/dev/snd`) are passed through for MIDI hardware and ALSA.
> If you encounter issues with display forwarding, audio passthrough, or USB access
> (e.g. ADB for Android deployment), consider developing directly on the host instead.

---

### Linux

GrooveForge requires a C/C++ toolchain, Flutter's GTK dependencies, audio/synthesis libraries, and a **JACK-compatible audio server** (PipeWire with `pipewire-jack` is recommended on modern distros).

#### Debian / Ubuntu (apt)

```bash
# Build toolchain
sudo apt install clang lld cmake ninja-build pkg-config

# Flutter Linux desktop dependencies
sudo apt install libgtk-3-dev libblkid-dev liblzma-dev libgcrypt20-dev libstdc++-12-dev

# Audio and MIDI
sudo apt install libasound2-dev libpulse-dev

# Audio server runtime — GrooveForge opens a JACK client for audio output;
# PipeWire with its JACK compatibility layer is the recommended setup.
sudo apt install pipewire pipewire-jack pipewire-alsa pipewire-pulse wireplumber

# VST3 editor windows
sudo apt install libx11-dev

# Synthesizer engine
sudo apt install libfluidsynth-dev

# Media (optional, for media playback features)
sudo apt install libmpv-dev
```

One-liner:

```bash
sudo apt install clang lld cmake ninja-build pkg-config \
  libgtk-3-dev libblkid-dev liblzma-dev libgcrypt20-dev libstdc++-12-dev \
  libasound2-dev libpulse-dev libx11-dev libfluidsynth-dev libmpv-dev \
  pipewire pipewire-jack pipewire-alsa pipewire-pulse wireplumber
```

#### Fedora (dnf)

```bash
sudo dnf install clang lld cmake ninja-build pkg-config \
  gtk3-devel libblkid-devel xz-devel libgcrypt-devel libstdc++-devel \
  alsa-lib-devel pulseaudio-libs-devel libX11-devel fluidsynth-devel mpv-libs-devel \
  pipewire pipewire-jack-audio-connection-kit pipewire-alsa pipewire-pulseaudio wireplumber
```

#### Arch / Manjaro (pacman)

```bash
sudo pacman -S clang lld cmake ninja pkg-config \
  gtk3 util-linux-libs xz libgcrypt \
  alsa-lib libpulse libx11 fluidsynth mpv \
  pipewire pipewire-jack pipewire-alsa pipewire-pulse wireplumber
```

> On Arch, development headers are included in the main packages — no separate `-dev`/`-devel` packages needed.
>
> **Audio server:** GrooveForge uses JACK for audio output. The `pipewire-jack` package provides JACK compatibility through PipeWire (the default audio server on modern Arch and Manjaro). If you have `jack2` installed and get "jack server is not running" errors, replace it with `pipewire-jack`. After installing, ensure the PipeWire services are running:
>
> ```bash
> systemctl --user enable --now pipewire pipewire-pulse wireplumber
> ```

---

### Android

- [Android SDK](https://developer.android.com/studio) with platform tools (for `adb`)
- Android NDK — installed automatically by Flutter on first build
- Java Development Kit 17+ (e.g. [Eclipse Temurin](https://adoptium.net/) via [SDKMAN](https://sdkman.io/))
- Min SDK: **26** (required for AAudio low-latency audio)

Set up the environment:

```bash
export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
```

FluidSynth and all other native dependencies for Android are pre-built and bundled in the repository for all architectures (arm64-v8a, armeabi-v7a, x86, x86_64) — no extra system packages are required.

---

### macOS

```bash
# CMake — required to build native audio and VST3 host
brew install cmake

# FluidSynth — synthesizer engine
brew install fluidsynth
```

Xcode Command Line Tools must be installed (`xcode-select --install`). macOS system frameworks (CoreAudio, AudioToolbox, Cocoa, Carbon) are provided by the OS.

> **App Sandbox:** To load third-party VST3 plugins, the App Sandbox entitlement must be
> disabled in `macos/Runner/Release.entitlements` and `DebugProfile.entitlements`.

---

### Windows (planned)

- Visual Studio 2019+ (or Build Tools) with the C++ desktop workload
- CMake ≥ 3.14
- VST3 hosting plumbing is in place; WASAPI audio backend is not yet wired

### VST3 SDK (required to build on Linux or Windows)

The VST3 SDK is too large to commit to the repository. Clone it once into the expected location before running a build:

```bash
git clone --depth=1 --recurse-submodules --shallow-submodules \
  https://github.com/steinbergmedia/vst3sdk.git \
  packages/flutter_vst3/vst3sdk
```

The `--recurse-submodules` flag is required because `public.sdk` is a git submodule inside the Steinberg repository — a plain `--depth=1` clone leaves that directory empty and the build fails. The SDK must live at `packages/flutter_vst3/vst3sdk/`. Flutter's build system picks it up automatically via the `dart_vst_host` FFI plugin — no manual CMake step is needed.

You can also override the path with the `VST3_SDK_DIR` environment variable if you already have the SDK installed elsewhere:

```bash
export VST3_SDK_DIR=/opt/vst3sdk
flutter build linux --release
```

> The VST3 SDK v3.8+ is MIT-licensed and fully compatible with GrooveForge's MIT license.

## How to Build

### 1 — Clone and fetch Dart dependencies

```bash
git clone https://github.com/your-org/grooveforge.git
cd grooveforge
flutter pub get
```

### 2 — Fetch the VST3 SDK (Desktop only)

```bash
# Linux / Windows / macOS
git clone --depth=1 --recurse-submodules --shallow-submodules \
  https://github.com/steinbergmedia/vst3sdk.git \
  packages/flutter_vst3/vst3sdk
```

### 3 — Run or build

```bash
# Development
flutter run -d linux
flutter run -d macos

# Release builds
flutter build linux --release
flutter build macos --release
flutter build apk --release
flutter build windows --release
```

The native `libdart_vst_host` and `libaudio_input` libraries are compiled and bundled automatically by Flutter's FFI plugin system (on macOS, ensure `cmake` is installed).

## Using VST3 Plugins (Linux)

1. Open the app and tap **+** in the rack to add a plugin slot.
2. Choose **VST3 Plugin** and select the plugin's `.vst3` bundle directory (e.g. `/usr/lib/vst3/Surge XT.vst3`).
3. The plugin loads, starts producing audio via ALSA, and its parameters appear as grouped rotary knobs in the rack card.
4. Tap **Show plugin UI** in the card to open the plugin's native editor window.
5. Use **Save Project** (top bar) to write a `.gf` file that snapshots all parameter values for later recall.

Common installed locations on Linux:

```
/usr/lib/vst3/
~/.vst3/
/usr/local/lib/vst3/
```

## Project File Format (`.gf`)

GrooveForge saves projects as plain JSON with a `.gf` extension. The file stores the full rack order, all GrooveForge Keyboard settings (soundfont, bank, patch, MIDI channel, Jam configuration), and a snapshot of every VST3 parameter value. Open a project with **Open Project** in the top bar.

## Open Source Credits

- **[Flutter](https://flutter.dev/)** — framework and SDK.
- **[FluidSynth](https://www.fluidsynth.org/)** — soundfont synthesis engine (Linux native).
- **[VST3 SDK](https://github.com/steinbergmedia/vst3sdk)** — Steinberg VST3 interfaces (MIT license, v3.8+).
- **[flutter_midi_command](https://pub.dev/packages/flutter_midi_command)** — hardware MIDI routing.
- **[provider](https://pub.dev/packages/provider)** — reactive state management.
- **[file_picker](https://pub.dev/packages/file_picker)** & **[path_provider](https://pub.dev/packages/path_provider)** — file system access.
- **[shared_preferences](https://pub.dev/packages/shared_preferences)** — lightweight preference persistence.

### Embedded packages (modified)

Both packages below are vendored inside `packages/` and carry their own licenses. Our modifications are described for transparency.

**[flutter_midi_pro](https://pub.dev/packages/flutter_midi_pro)** by [Melih Hakan Pektas](https://github.com/melihhakanpektas) — MIT License.
The embedded version adds multi-timbral support (16 independent channels) and a Linux FluidSynth native backend that was absent from the upstream package.

**[flutter_vst3](https://github.com/MelbourneDeveloper/flutter_vst3)** by Melbourne Developer — BSD-3-Clause License.
The embedded `dart_vst_host` sub-package has been extended with: a Linux ALSA audio thread, an X11 floating editor window with full `IRunLoop` / `IPlugFrame` support, parameter unit/group APIs (`dvh_param_unit_id`, `dvh_unit_count`, `dvh_unit_name`), multi-output-bus resume logic, single-component VST3 fallback, and platform stub files for Windows and macOS compilation.
