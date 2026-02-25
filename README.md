# GrooveForge Synthesizer

GrooveForge Synthesizer is a low-latency, cross-platform Flutter application tailored to connect to MIDI keyboards (such as the Alesis Vortex Wireless 2) and perform multi-timbral soundfont synthesis (`.sf2`).

## Features

GrooveForge Synthesizer provides cross-platform, zero-latency multi-timbral synthesis utilizing `.sf2` soundfonts. Key capabilities include:
- **16-Channel Engine**: Fully independent state-managed MIDI channels.
- **Advanced CC Mapping**: Map knobs, sliders, and pads to MIDI effects or powerful custom application actions (e.g. Patch Sweeping).
- **Interactive UI**: A glowing 16-card grid dashboard representing your workspace.
- **Real-Time Music Theory**: Live chord detection parsing and a mathematical "Scale Lock" system that flawlessly binds wrong notes into the correct grooving scale.

For a full, detailed breakdown of all capabilities, see the [Features Documentation](docs/features.md).

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

GrooveForge Synthesizer is built using the Flutter framework and relies on several fantastic open-source packages:

- **[Flutter](https://flutter.dev/)** - Framework and SDK.
- **[flutter_midi_command](https://pub.dev/packages/flutter_midi_command)** - For routing and receiving hardware MIDI messages.
- **[provider](https://pub.dev/packages/provider)** - For reactive state management across the app.
- **[file_picker](https://pub.dev/packages/file_picker)** & **[path_provider](https://pub.dev/packages/path_provider)** - For opening and managing `.sf2` soundfont files.
- **[shared_preferences](https://pub.dev/packages/shared_preferences)** - For persisting configurations and dashboard state.
- **[cupertino_icons](https://pub.dev/packages/cupertino_icons)** - For UI iconography.

### Custom Audio Engine (`flutter_midi_pro`)

This repository embeds a **modified version** of **[flutter_midi_pro](https://pub.dev/packages/flutter_midi_pro)** originally created by [Melih Hakan Pektas](https://github.com/melihhakanpektas) (Licensed under the MIT License). 

Our embedded version has been heavily customized to support multi-timbral features and Linux `fluidsynth` integration. We are deeply grateful to the original author for providing such a solid foundation for Oboe/AVFoundation synthesis.
