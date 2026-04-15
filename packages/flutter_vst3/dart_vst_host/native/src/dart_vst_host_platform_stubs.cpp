// Non-Linux thin stubs for dart_vst_host.
//
// macOS and Windows share the miniaudio-based audio backend defined in
// `dart_vst_host_audio_desktop.cpp`, which provides every audio-graph
// routing symbol (`dvh_set_processing_order`, `dvh_route_audio`,
// `dvh_clear_routes`, `dvh_add_master_render`, etc.). Linux has its
// dedicated JACK backend in `dart_vst_host_jack.cpp`.
//
// This file only has to plug the gaps that are Linux-specific OR not
// yet implemented on a particular desktop:
//
//   1. JACK client entry points — Linux-only. macOS and Windows both
//      use `dvh_start_desktop_audio`/`dvh_stop_desktop_audio`
//      instead. The no-op stubs below satisfy the Dart FFI loader so
//      the shared library links cleanly on every desktop.
//
//   2. Native plugin editor window — macOS provides `dvh_open_editor`
//      directly from `dart_vst_host_editor_mac.mm`, and Linux from
//      `dart_vst_host_editor_linux.cpp`. Windows would need a Win32
//      HWND wrapper which is deferred to a future "editor windows"
//      phase; for now, opening a VST3 editor on Windows is a no-op
//      and plugins are controlled through GrooveForge's built-in
//      parameter UI.

#if !defined(__linux__)

#include "dart_vst_host.h"

extern "C" {

// ── JACK client stubs (macOS + Windows) ─────────────────────────────────────

int32_t dvh_start_jack_client(DVH_Host /*host*/, const char* /*client_name*/) {
    return 0;
}
void    dvh_stop_jack_client(DVH_Host /*host*/) {}
int32_t dvh_jack_get_xrun_count(DVH_Host /*host*/) { return 0; }

} // extern "C"

#endif // !__linux__

// ── Plugin editor stubs (Windows only) ─────────────────────────────────────
//
// macOS provides the real `dvh_open_editor` / `dvh_close_editor` /
// `dvh_editor_is_open` implementations in `dart_vst_host_editor_mac.mm`,
// so this block is Windows-exclusive to avoid duplicate symbols.
#if defined(_WIN32)

#include "dart_vst_host.h"

extern "C" {

intptr_t dvh_open_editor(DVH_Plugin /*p*/, const char* /*title*/) { return 0; }
void     dvh_close_editor(DVH_Plugin /*p*/) {}
int32_t  dvh_editor_is_open(DVH_Plugin /*p*/) { return 0; }

} // extern "C"

#endif // _WIN32
