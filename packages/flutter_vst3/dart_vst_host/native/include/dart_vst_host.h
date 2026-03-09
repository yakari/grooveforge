// VST3 Host interface for Dart
// Generated for cross-platform Dart VST hosting

#pragma once
#include <stdint.h>

#ifdef _WIN32
  #ifdef DART_VST_HOST_EXPORTS
    #define DVH_API __declspec(dllexport)
  #else
    #define DVH_API __declspec(dllimport)
  #endif
#else
  #define DVH_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef void* DVH_Host;
typedef void* DVH_Plugin;

// Returns a version string for the host library (e.g. "1.1.0-macOS").
DVH_API const char* dvh_get_version();

// Create a VST3 host. Provide sample rate and max block size.
DVH_API DVH_Host dvh_create_host(double sample_rate, int32_t max_block);
// Destroy a previously created host.
DVH_API void      dvh_destroy_host(DVH_Host host);

// Load a plugin from module path. Optional class UID filters which class to instantiate.
DVH_API DVH_Plugin dvh_load_plugin(DVH_Host host, const char* module_path_utf8, const char* class_uid_or_null);
// Unload a previously loaded plugin.
DVH_API void       dvh_unload_plugin(DVH_Plugin p);

// Resume processing on a plugin. Must be called after loading before processing.
DVH_API int32_t dvh_resume(DVH_Plugin p, double sample_rate, int32_t max_block);
// Suspend processing on a plugin.
DVH_API int32_t dvh_suspend(DVH_Plugin p);

// Process stereo audio. Input pointers must be valid arrays of length num_frames. Output will be written in-place.
DVH_API int32_t dvh_process_stereo_f32(DVH_Plugin p,
                                       const float* inL, const float* inR,
                                       float* outL, float* outR,
                                       int32_t num_frames);

// Send a NoteOn to the plugin. Channel and pitch follow MIDI convention. Velocity in [0,1].
DVH_API int32_t dvh_note_on(DVH_Plugin p, int32_t channel, int32_t note, float velocity);
// Send a NoteOff to the plugin.
DVH_API int32_t dvh_note_off(DVH_Plugin p, int32_t channel, int32_t note, float velocity);

// Query number of parameters for a plugin. Returns 0 if no controller present.
DVH_API int32_t dvh_param_count(DVH_Plugin p);
// Query parameter info by index. Fills id, title and units buffers. Returns 1 on success.
DVH_API int32_t dvh_param_info(DVH_Plugin p, int32_t index,
                               int32_t* id_out,
                               char* title_utf8, int32_t title_cap,
                               char* units_utf8, int32_t units_cap);

// Get a parameter value normalized [0,1] by ID.
DVH_API float   dvh_get_param_normalized(DVH_Plugin p, int32_t param_id);
// Set a parameter normalized value. Returns 1 on success.
DVH_API int32_t dvh_set_param_normalized(DVH_Plugin p, int32_t param_id, float normalized);

// Audio loop management (Linux ALSA only).
// Add a plugin to the audio loop managed by this host.
DVH_API void    dvh_audio_add_plugin(DVH_Host host, DVH_Plugin plugin);
// Remove a plugin from the audio loop.
DVH_API void    dvh_audio_remove_plugin(DVH_Host host, DVH_Plugin plugin);
// Remove all plugins from the audio loop.
DVH_API void    dvh_audio_clear_plugins(DVH_Host host);
// Start an ALSA output thread mixing all registered plugins.
// alsa_device may be null/"default" for the system default device.
// Returns 1 on success, 0 on failure.
DVH_API int32_t dvh_start_alsa_thread(DVH_Host host, const char* alsa_device);
// Stop the ALSA output thread. Blocks until the thread exits.
DVH_API void    dvh_stop_alsa_thread(DVH_Host host);

// macOS specific audio device management (CoreAudio/miniaudio)
DVH_API int32_t dvh_mac_start_audio(DVH_Host host);
DVH_API void    dvh_mac_stop_audio(DVH_Host host);

// Parameter unit/group API — for grouping parameters by category.
// Returns the unitId for the parameter at [index]. Returns -1 on failure.
DVH_API int32_t dvh_param_unit_id(DVH_Plugin p, int32_t index);
// Returns the number of declared units (groups) for this plugin.
// Returns 0 if the plugin does not implement IUnitInfo.
DVH_API int32_t dvh_unit_count(DVH_Plugin p);
// Fills [name_out] with the UTF-8 name of the unit whose ID is [unit_id].
// Returns 1 on success, 0 if not found or IUnitInfo not available.
DVH_API int32_t dvh_unit_name(DVH_Plugin p, int32_t unit_id,
                              char* name_out, int32_t name_cap);

// Plugin editor GUI (X11 on Linux, stub on other platforms).
// Open the plugin's native editor in a standalone X11 window.
// title: window title string (may be null).
// Returns the X11 Window ID on success, 0 if the plugin has no GUI.
DVH_API intptr_t dvh_open_editor(DVH_Plugin p, const char* title);
// Close the editor window opened by dvh_open_editor.
DVH_API void     dvh_close_editor(DVH_Plugin p);
// Returns 1 if an editor window is currently open for this plugin.
DVH_API int32_t  dvh_editor_is_open(DVH_Plugin p);

// macOS specific editor (Cocoa/NSWindow)
DVH_API intptr_t dvh_mac_open_editor(DVH_Plugin p, const char* title);
DVH_API void     dvh_mac_close_editor(DVH_Plugin p);
DVH_API int32_t  dvh_mac_editor_is_open(DVH_Plugin p);

#ifdef __cplusplus
}
#endif