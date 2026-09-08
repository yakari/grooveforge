// Conditional export, the same shape as audio_input_ffi.dart: native targets
// get the real renderer, web gets a stub.
//
// Without this the web build fails outright — `dart:ffi` does not exist there,
// and the rehearsal library is reachable from main.dart, so importing it
// directly poisoned the whole dart2js compile.
export 'rehearsal_stretch_io.dart'
    if (dart.library.js_interop) 'rehearsal_stretch_stub.dart';
