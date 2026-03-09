// Conditional export: desktop platforms get the real ALSA/VST3 implementation;
// all others get a stub that gracefully reports "not supported".
export 'vst_host_service_stub.dart'
    if (dart.library.io) 'vst_host_service_desktop.dart';
