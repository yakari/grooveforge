# GrooveForge

GrooveForge is a free music app for playing, practising and rehearsing. Plug in
a MIDI keyboard (or use the one on screen), build a rack of instruments and
effects, lock the keys to a scale, record loops, and rehearse a tune with your
band, each player on their own phone.

It runs on Android, Linux, macOS and Windows, and as a demo in the browser.

## Get it

- **Android**: [Google Play](https://play.google.com/store/apps/details?id=com.grooveforge.grooveforge)
  or [F-Droid](https://f-droid.org/packages/com.grooveforge.grooveforge/).
  F-Droid builds the app itself, so a new version can reach it later than
  Google Play. The two are signed differently: to switch from one to the
  other, uninstall first.
- **Linux, macOS, Windows**: download from the
  [latest release](https://github.com/yakari/grooveforge/releases/latest).
  Linux has a `.deb`, an `.rpm`, an Arch package (`.pkg.tar.zst`), a
  `.flatpak` and a plain `.zip`. macOS is a `.zip` built for Apple Silicon.
  Windows is a `.zip`.
- **Browser**: the [web demo](https://yakari.github.io/grooveforge/demo/) has
  fewer modules than the app (no reverb or delay, for example). It does not
  keep your session: use **Save As…** to download your project.

On Linux, GrooveForge plays sound through JACK. On most current distributions
this is PipeWire with its JACK layer (`pipewire-jack`). The release
packages ask for it.

iOS is not supported. The release page has an unsigned iOS build that has
never been tested.

## How it works in one minute

Your rack is a stack of modules: instruments, effects, loopers, a drum
machine. Tap the cable icon at the top of the screen to see the back of each
module, with sockets you connect with cables, like on real gear.

1. An instrument plays through the speakers on its own. You do not need a
   cable to hear it.
2. Yellow cables carry notes (MIDI), from a keyboard to an instrument. Red and
   white cables carry sound, left and right.
3. To put an effect after an instrument, cable the instrument's **AUDIO OUT L**
   and **AUDIO OUT R** into the effect's **AUDIO IN L** and **AUDIO IN R**.
   What comes out of the effect goes to the speakers.

To draw a cable, long-press a socket and drag it to another one.

The [user guide](https://yakari.github.io/grooveforge/guide/) shows each step
with a short video: [how sound moves](https://yakari.github.io/grooveforge/guide/#how-sound-moves),
[add an effect](https://yakari.github.io/grooveforge/guide/#effect),
[connect a MIDI controller](https://yakari.github.io/grooveforge/guide/#controller),
[record a loop](https://yakari.github.io/grooveforge/guide/#loop) and more.

## What is in it

- [Modules](https://yakari.github.io/grooveforge/modules/): the SoundFont
  keyboard, a modelled electric guitar (Riff), a guitar amp, a vocoder,
  Stylophone, Theremin, a drum generator, audio and MIDI loopers, and audio
  effects.
- [MIDI FX](https://yakari.github.io/grooveforge/midi-fx/): modules that change
  the notes on their way to an instrument, such as the arpeggiator, the
  harmonizer and Xen, which locks the keyboard to one of 92 scales and retunes
  it.
- [Rehearsals](https://yakari.github.io/grooveforge/rehearsals/): each band
  member records their own part over a shared click. Devices sync over the
  local network, with no account and no server.
- [VST3 plugins](https://yakari.github.io/grooveforge/vst/): load your own
  plugins. Desktop only.
- [All features](https://yakari.github.io/grooveforge/features/), in detail.

The site is also [in French](https://yakari.github.io/grooveforge/fr/).

## Build from source

You need [Flutter](https://docs.flutter.dev/get-started/install) 3.41 or later
(the release builds use 3.41.6) and Git.

### 1. Get the code

```bash
git clone https://github.com/yakari/grooveforge.git
cd grooveforge
flutter pub get
```

### 2. Android

The Android build compiles FluidSynth (the sound engine) from a Git submodule.
Fetch it once. Do not add `--recursive`: FluidSynth's own submodules are large
and the build does not need them.

```bash
git submodule update --init
```

You also need the Android SDK and Java 17. Flutter installs the NDK on the
first build. The app needs Android 8.0 (API 26) or later.

```bash
flutter run -d <device>         # debug build on a connected phone
flutter build apk --release
```

Without `android/app/release-keystore.jks`, a release build is signed with the
debug key.

### 3. Desktop: the VST3 SDK

Linux, macOS and Windows need the Steinberg VST3 SDK. It is not in the
repository. Clone it once, with its submodules:

```bash
git clone --depth=1 --recurse-submodules --shallow-submodules \
  https://github.com/steinbergmedia/vst3sdk.git \
  packages/flutter_vst3/vst3sdk
```

If you keep the SDK somewhere else, set `VST3_SDK_DIR` to its path before
building.

### 4. Linux

Debian or Ubuntu:

```bash
sudo apt install clang cmake ninja-build pkg-config libstdc++-12-dev \
  libgtk-3-dev libblkid-dev liblzma-dev libgcrypt20-dev \
  libasound2-dev libjack-jackd2-dev libx11-dev libfluidsynth-dev \
  pipewire pipewire-jack pipewire-alsa pipewire-pulse wireplumber
```

Fedora:

```bash
sudo dnf install clang cmake ninja-build pkg-config \
  gtk3-devel libblkid-devel xz-devel libgcrypt-devel \
  alsa-lib-devel pipewire-jack-audio-connection-kit-devel libX11-devel fluidsynth-devel \
  pipewire pipewire-alsa pipewire-pulseaudio wireplumber
```

Arch or Manjaro (headers come with the main packages):

```bash
sudo pacman -S clang cmake ninja pkg-config \
  gtk3 util-linux-libs xz libgcrypt \
  alsa-lib libx11 fluidsynth \
  pipewire pipewire-jack pipewire-alsa pipewire-pulse wireplumber
```

Then:

```bash
flutter run -d linux
flutter build linux --release   # output in build/linux/x64/release/bundle/
```

If the app says the JACK server is not running, check that PipeWire is
running (`systemctl --user enable --now pipewire pipewire-pulse wireplumber`)
and that `pipewire-jack` is installed rather than `jack2`.

The repository also has a [Dev Container](.devcontainer/devcontainer.json)
with the Linux dependencies installed.

### 5. macOS

You need Xcode, CocoaPods and [Homebrew](https://brew.sh/).

```bash
brew install cmake fluid-synth
cd macos && pod install && cd ..
flutter run -d macos
flutter build macos --release
```

An Xcode build step (`scripts/build_native_macos.sh`) compiles the native
audio libraries on each build. A local build links the Homebrew FluidSynth,
so it only runs on a Mac that has it installed. The release workflow bundles
FluidSynth into the app with `dylibbundler`.

### 6. Windows

You need Visual Studio with the "Desktop development with C++" workload.

Download the FluidSynth build for Windows into `native_audio/fluidsynth_win64`
(PowerShell, from the repository folder):

```powershell
Invoke-WebRequest -Uri "https://github.com/FluidSynth/fluidsynth/releases/download/v2.5.2/fluidsynth-v2.5.2-win10-x64-cpp11.zip" -OutFile fluidsynth-win64.zip
Expand-Archive fluidsynth-win64.zip -DestinationPath native_audio/fluidsynth_tmp
Move-Item native_audio/fluidsynth_tmp/fluidsynth-v2.5.2-win10-x64-cpp11 native_audio/fluidsynth_win64
Remove-Item -Recurse native_audio/fluidsynth_tmp; Remove-Item fluidsynth-win64.zip
```

Then:

```powershell
flutter run -d windows
flutter build windows --release
```

On Windows, VST3 plugins load and play, but their own editor windows do not
open yet: use the knobs GrooveForge shows instead.

### Checks

```bash
flutter analyze   # must report no issues
flutter test
```

`scripts/run_smoke_tests.sh` builds and runs the native audio tests. Read the
comment at the top of the script first.

## For developers

- [Plugin descriptors (.gfpd)](https://yakari.github.io/grooveforge/gfpd/):
  write audio effects and MIDI FX for GrooveForge without Dart.
- [Drum patterns (.gfdrum)](https://yakari.github.io/grooveforge/gfdrum/):
  the pattern file format.
- [`docs/dev/REHEARSALS.md`](docs/dev/REHEARSALS.md): how rehearsal sync works.
- [`docs/writing-help.md`](docs/writing-help.md): rules for any text a user
  reads, including this file.
- [`CHANGELOG.md`](CHANGELOG.md): what changed in each version.

## Contributing

Report bugs and ideas in [GitHub issues](https://github.com/yakari/grooveforge/issues).
GrooveForge is made by one person in their spare time, so answers can take a
while. Before a pull request, run `flutter analyze` and `flutter test`, and
add a line to both `CHANGELOG.md` and `CHANGELOG.fr.md`.

## License

GrooveForge's source code is under the [MIT License](LICENSE).

The default sound bank, TimGM6mb by Tim Brechbill
(`assets/soundfonts/default.sf2`), is under the GPL-2.0
([`assets/soundfonts/LICENSE.txt`](assets/soundfonts/LICENSE.txt)). The app
reads it as data, so the source stays MIT, but a built app that contains it
cannot be redistributed as MIT-only.

Other parts and their licenses:

- [FluidSynth](https://www.fluidsynth.org/), the SoundFont engine: LGPL-2.1 or
  later.
- [VST3 SDK](https://github.com/steinbergmedia/vst3sdk) by Steinberg: MIT
  (version 3.8 and later).
- `packages/flutter_midi_pro`, a modified copy of
  [flutter_midi_pro](https://pub.dev/packages/flutter_midi_pro) by Melih Hakan
  Pektas: MIT. It adds 16-channel playback and native backends.
- `packages/flutter_vst3`, a modified copy of
  [flutter_vst3](https://github.com/MelbourneDeveloper/flutter_vst3) by
  Melbourne Developer: BSD-3-Clause. Its `dart_vst_host` package was extended
  with the audio backends, editor windows and parameter groups GrooveForge
  uses.
