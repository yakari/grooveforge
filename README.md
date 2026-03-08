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
| **Linux** | ✅ Primary target | Full VST3 hosting (ALSA audio, X11 editor windows), FluidSynth synthesis |
| **Android** | ✅ Supported | GrooveForge Keyboard only; VST3 hosting is desktop-exclusive |
| **Windows** | 🔜 Planned | VST3 hosting plumbing in place; WASAPI audio not yet wired |
| **macOS** | 🧪 Experimental | GrooveForge Keyboard only; CoreAudio/VST3 not yet wired |
| **iOS** | 🧪 Experimental | Basic build only; untested |

## Prerequisites

### All platforms

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (≥ 3.10)

### Linux (required for building and running)

```bash
# FluidSynth — synthesizer backend
sudo apt-get install fluidsynth libfluidsynth-dev

# ALSA and X11 — VST3 audio and editor window support
sudo apt-get install libasound2-dev libx11-dev

# GTK and other Flutter Linux dependencies
sudo apt-get install libgtk-3-dev libblkid-dev liblzma-dev libgcrypt20-dev libmpv-dev
```

### VST3 SDK (required to build on Linux or Windows)

The VST3 SDK is too large to commit to the repository. Clone it once into the expected location before running a build:

```bash
git clone --depth=1 https://github.com/steinbergmedia/vst3sdk.git \
  packages/flutter_vst3/vst3sdk
```

The SDK must live at `packages/flutter_vst3/vst3sdk/`. Flutter's build system picks it up automatically via the `dart_vst_host` FFI plugin — no manual CMake step is needed.

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

### 2 — Fetch the VST3 SDK (Linux / Windows only)

```bash
git clone --depth=1 https://github.com/steinbergmedia/vst3sdk.git \
  packages/flutter_vst3/vst3sdk
```

### 3 — Run or build

```bash
# Development
flutter run -d linux

# Release builds
flutter build linux --release
flutter build apk --release
flutter build windows --release
```

The native `libdart_vst_host.so` (Linux) or `dart_vst_host.dll` (Windows) is compiled and bundled automatically by Flutter's FFI plugin system. No separate CMake invocation is required.

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
