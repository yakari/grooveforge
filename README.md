# GrooveForge Synthesizer

GrooveForge Synthesizer is a low-latency, cross-platform Flutter application tailored to connect to MIDI keyboards (such as the Alesis Vortex Wireless 2) and perform multi-timbral soundfont synthesis (`.sf2`).

## Features

GrooveForge Synthesizer provides cross-platform, low-latency multi-timbral synthesis utilizing `.sf2` soundfonts. Key capabilities include:
- **16-Channel Engine**: Fully independent state-managed MIDI channels.
- **Jam Mode (Collaborative)**: Synchronize scales and harmony across multiple channels or musicians. One "Master" channel can lead multiple "Slaves" for flawless improvisation.
- **Integrated Vocoder**: Real-time voice synthesis using your device's microphone to modulate synth carriers.
- **Scale Lock & Highlighting**: A mathematical system that binds notes to the correct scale, featuring visual feedback (Correct/Wrong/Root note highlights) on the virtual keyboard.
- **Advanced CC Mapping**: Map knobs, sliders, and pads to MIDI effects or powerful custom application actions like "Patch Sweeping" or "Global Scale Cycle".
- **Premium UI**: Tactile rotary knobs and a glowing 16-card grid dashboard for a professional studio feel.

For a full, detailed breakdown, see the [Features Documentation](docs/features.md).

## Platform Support

GrooveForge is developed and optimized for the following platforms:
- **Android**: Fully supported and tested (ARM64). Uses Oboe for high-performance audio.
- **Linux**: Fully supported and tested. Relies on `fluidsynth` as a native backend.
- **Windows / macOS / iOS**: **Experimental**. These ports are included in the codebase but are not fully tested and may have limited functionality or performance issues.

## Hardware & Connection Notes

### Android USB Limitations
Due to Android's internal audio routing, you **cannot** use two separate USB audio devices for simultaneous input and output (e.g., plugging a standalone USB microphone and a separate USB DAC into the same USB-C hub). 

For the **Vocoder** to work correctly with external hardware:
- Use a **single USB audio interface** (or an integrated hub/dock that acts as one device) providing both input (XLR/Jack) and output (Headphones/Monitors).
- Or use the **Internal Microphone** while routing output to a USB device or the system speakers.
- **Bluetooth** is not recommended for the Vocoder due to high protocol latency.

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
