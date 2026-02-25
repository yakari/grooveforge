# Yakalive TODO List

## Web Platform Support
Currently, the Web build (`flutter run -d web-server`) compiles and the UI renders correctly, but the application fails to function due to two major technical blockers:

*   **MIDI Plugin Missing Implementation**: The `flutter_midi_command` package throws a `MissingPluginException` for the web platform. The app cannot currently listen to or connect with MIDI devices in the browser. A web-compatible MIDI library or interface needs to be integrated.
*   **Unsupported dart:io Operations**: The application heavily relies on `Platform.isLinux` and `Platform.isAndroid` from `dart:io`. These calls throw an `Unsupported operation: Platform._operatingSystem` error on the Web. 
    *   **Fix**: Platform checks should be refactored to use `kIsWeb` from `flutter/foundation.dart` to safely bypass or handle non-mobile/desktop platforms.
