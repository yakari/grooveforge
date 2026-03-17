// Conditional export: desktop platforms get the real ALSA/VST3 implementation;
// web/Wasm targets get a stub that gracefully reports "not supported".
//
// We condition on dart.library.js_interop (present only on web/Wasm) rather than
// dart.library.io, because dart:io is partially available on Flutter web in
// Dart 3.x — making the dart.library.io condition unreliable for this purpose.
export 'vst_host_service_desktop.dart'
    if (dart.library.js_interop) 'vst_host_service_stub.dart';
