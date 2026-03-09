// Non-Linux stubs for dart_vst_host.
//
// dart_vst_host_alsa.cpp and dart_vst_host_editor_linux.cpp are entirely
// wrapped in #ifdef __linux__, so their symbols are absent on Windows and
// macOS. This file provides no-op stubs so the shared library links cleanly
// on those platforms.
//
// On Windows, CoreAudio/WASAPI audio output and Win32/HWND editor windows
// can be implemented here in the future. On macOS, CoreAudio and NSView/
// Cocoa PlatformView are the equivalents.

#if !defined(__linux__) && !defined(__APPLE__)

#include "dart_vst_host.h"

extern "C" {

// ── ALSA / audio-loop stubs ──────────────────────────────────────────────────

void dvh_audio_add_plugin(DVH_Host /*host*/, DVH_Plugin /*plugin*/) {}
void dvh_audio_remove_plugin(DVH_Host /*host*/, DVH_Plugin /*plugin*/) {}
void dvh_audio_clear_plugins(DVH_Host /*host*/) {}

int32_t dvh_start_alsa_thread(DVH_Host /*host*/, const char* /*alsa_device*/) {
    return 0; // not available on this platform
}

void dvh_stop_alsa_thread(DVH_Host /*host*/) {}

// ── Plugin editor stubs ──────────────────────────────────────────────────────

intptr_t dvh_open_editor(DVH_Plugin /*p*/, const char* /*title*/) {
    return 0; // no native GUI support yet on this platform
}

void dvh_close_editor(DVH_Plugin /*p*/) {}

int32_t dvh_editor_is_open(DVH_Plugin /*p*/) {
    return 0;
}

} // extern "C"

#endif // !__linux__
