# Yakalive Synthesizer

Yakalive Synthesizer is a low-latency, cross-platform Flutter application tailored to connect to MIDI keyboards (such as the Alesis Vortex Wireless 2) and perform multi-timbral soundfont synthesis (`.sf2`).

## Features

- **Cross-Platform Low Latency Audio**: Supports Android, iOS, macOS, Windows, and Linux.
  - *Android*: Utilizes Google's ultra-low latency `Oboe` engine via the `flutter_midi_pro` plugin.
  - *Apple*: Runs natively on `AVFoundation`.
  - *Linux*: Automatically orchestrates a background ALSA `fluidsynth` CLI process capturing inputs and outputs to provide zero-latency synthesized sound matching native mobile experiences.
- **16-Channel Multi-timbral Architecture**: Features a robust 16-channel state manager. Each channel independently tracks its assigned Soundfont, Program Patch, and Bank MSB, allowing for complex multi-instrument performances.
- **Interactive Dashboard UI**: A 16-card grid dashboard actively animates and flashes borders in real-time on channels receiving MIDI data. Tap on any channel to instantly assign an instrument and patch.
- **Multiple Soundfont Management**: Load multiple `.sf2` soundfont files simultaneously into your workspace. Memory management allows for loading and unloading soundfonts seamlessly.
- **Advanced CC Mapping**: Intercept and map your hardware's physically knobs, sliders, and ribbons to General MIDI effects (Volume, Expression, Reverb, Chorus, Pan, etc.) or powerful Custom System Actions:
  - *Next/Prev Soundfont*
  - *Next/Prev Program Patch*
  - *Absolute Patch Sweep (knobs mapped directly to instrument 0-127)*
  - Offers 3-way custom routing: Map to the *Same Channel*, *All Channels (omni)*, or a *Specific Channel*.
- **State Persistence**: Your loaded soundfont array and your exact 16-channel configurations are saved automatically via `shared_preferences` and restored instantly on launch.

## Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- **Linux Users**: You must have `fluidsynth` installed to use the Linux backend natively.
  ```bash
  sudo apt-get install fluidsynth
  ```

## How to Build and Run

1. **Clone the repository and install dependencies:**
   ```bash
   flutter pub get
   ```
2. **Run the application:**
   You can target whichever connected device or desktop environment you are developing on:
   ```bash
   flutter run -d linux
   ```
3. **Build a release version:**
   ```bash
   flutter build linux
   # Or target `flutter build apk`, `flutter build macos`, etc.
   ```

## Usage

1. Open **Preferences** by clicking the Gear Icon in the top right.
2. Under **MIDI Connection**, select your connected MIDI Keyboard device.
3. Under **Soundfonts**, click **Load Soundfont (.sf2)** to add your preferred instruments.
4. Go back to the main **Dashboard**, tap on any of the 16 channels, and assign a soundfont, program index, and bank to that channel.
5. *(Optional)* Dive into **CC Mapping Preferences** to map your hardware's controllers to specific effects or actions like switching between instruments on-the-fly.

## Open Source Credits

Yakalive Synthesizer is built using the Flutter framework and relies on several fantastic open-source packages:

- **[Flutter](https://flutter.dev/)** - Framework and SDK.
- **[flutter_midi_command](https://pub.dev/packages/flutter_midi_command)** - For routing and receiving hardware MIDI messages.
- **[provider](https://pub.dev/packages/provider)** - For reactive state management across the app.
- **[file_picker](https://pub.dev/packages/file_picker)** & **[path_provider](https://pub.dev/packages/path_provider)** - For opening and managing `.sf2` soundfont files.
- **[shared_preferences](https://pub.dev/packages/shared_preferences)** - For persisting configurations and dashboard state.
- **[cupertino_icons](https://pub.dev/packages/cupertino_icons)** - For UI iconography.

### Custom Audio Engine (`flutter_midi_pro`)

This repository embeds a **modified version** of **[flutter_midi_pro](https://pub.dev/packages/flutter_midi_pro)** originally created by [Melih Hakan Pektas](https://github.com/melihhakanpektas) (Licensed under the MIT License). 

Our embedded version has been heavily customized to support multi-timbral features and Linux `fluidsynth` integration. We are deeply grateful to the original author for providing such a solid foundation for Oboe/AVFoundation synthesis.
