// Conditional export: native platforms load the real FFI bindings to
// libnative-lib.so (Android only); web/Wasm targets load a no-op stub.
//
// dart.library.js_interop is only available on web/Wasm targets, so this
// condition correctly selects the stub for web and the real impl elsewhere.
export 'gfpa_android_bindings_native.dart'
    if (dart.library.js_interop) 'gfpa_android_bindings_web.dart';
