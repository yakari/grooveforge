# GrooveForge TODO List

## Web Platform Support
Currently, the Web build (`flutter run -d web-server`) compiles and the UI renders correctly, but the application fails to function due to two major technical blockers:

*   **MIDI Plugin Missing Implementation**: The `flutter_midi_command` package throws a `MissingPluginException` for the web platform. The app cannot currently listen to or connect with MIDI devices in the browser. A web-compatible MIDI library or interface needs to be integrated.
*   **Unsupported dart:io Operations**: The application heavily relies on `Platform.isLinux` and `Platform.isAndroid` from `dart:io`. These calls throw an `Unsupported operation: Platform._operatingSystem` error on the Web. 
    *   **Fix**: Platform checks should be refactored to use `kIsWeb` from `flutter/foundation.dart` to safely bypass or handle non-mobile/desktop platforms.

## Audio Engine & Soundfonts
*   **Migrate to [`flutter_midi_engine`](https://pub.dev/packages/flutter_midi_engine)**: Replace `flutter_midi_pro` to gain advanced synthesizer capabilities:
    *   **SF3 Support**: Native playback of compressed soundfonts on all platforms (Android, iOS/macOS, and Web).
    *   **Experimental Web Support**: Potential path to functional MIDI playback in the browser.
    *   **Built-in Effects**: Use integrated **reverb and chorus** effects to enhance sound quality.
    *   **Advanced Control**: 16-channel support, pitch bend, and standard CC messages.
*   **Integrate MuseScore General Soundfont**: Switch to `MuseScore_General.sf3` (MIT Licensed) as the high-quality default soundfont once SF3 support is available on all platforms. ftp://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf3
*   **Fix "Chipmunk" Effect in Natural Vocoder Mode**: The current Live-Wavetable implementation in `Natural` mode causes a pitch-shifted "chipmunk" sound because formants are shifted along with the fundamental.
    *   **Solution**: Implement true **Formant Preservation** (e.g., using a separate spectral envelope for the carrier or a PSOLA-based approach) to keep the vocal character while changing the pitch.
