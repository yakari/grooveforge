// Conditional export, the same shape as rehearsal_stretch.dart: native targets
// get the real canceller, web gets a stub.
//
// Without this the web build fails outright — `dart:ffi` does not exist there,
// and the rehearsal engine is reachable from main.dart, so importing the
// native side directly poisons the whole dart2js compile.
export 'rehearsal_clean_io.dart'
    if (dart.library.js_interop) 'rehearsal_clean_stub.dart';
