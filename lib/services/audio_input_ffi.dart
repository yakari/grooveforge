// Conditional export: native platforms load the real FFI bindings to
// libaudio_input; web targets load a no-op stub that routes Stylophone
// and Theremin calls to the Web Audio API bridge (grooveforge_audio.js).
//
// dart.library.js_interop is only available on web/Wasm targets, so this
// condition correctly selects the stub for web and the real impl elsewhere.
export 'audio_input_ffi_native.dart'
    if (dart.library.js_interop) 'audio_input_ffi_stub.dart';
