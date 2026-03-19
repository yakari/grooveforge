/// Dart FFI bindings to the native Dart VST host library. This
/// translation mirrors the C API defined in dart_vst_host.h. It
/// provides low‑level functions for creating a host, loading VST
/// plug‑ins and processing audio. Higher level classes are defined
/// in host.dart which wrap these bindings in a safer API.
library;

import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Type definitions matching the C API signatures. Each typedef
// corresponds to a C function pointer. See dart_vst_host.h for
// documentation on each function.
typedef _HostCreateC = Pointer<Void> Function(Double, Int32);
typedef _HostDestroyC = Void Function(Pointer<Void>);

typedef _LoadC = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>);
typedef _UnloadC = Void Function(Pointer<Void>);

typedef _ResumeC = Int32 Function(Pointer<Void>, Double, Int32);
typedef _SuspendC = Int32 Function(Pointer<Void>);

typedef _SetTransportC = Void Function(Double, Int32, Int32, Int32, Double, Int32);

typedef _ProcessStereoC = Int32 Function(
  Pointer<Void>,
  Pointer<Float>, Pointer<Float>,
  Pointer<Float>, Pointer<Float>,
  Int32);

typedef _NoteC = Int32 Function(Pointer<Void>, Int32, Int32, Float);

typedef _ParamCountC = Int32 Function(Pointer<Void>);
typedef _ParamInfoC = Int32 Function(Pointer<Void>, Int32, Pointer<Int32>, Pointer<Utf8>, Int32, Pointer<Utf8>, Int32);
typedef _GetParamC = Float Function(Pointer<Void>, Int32);
typedef _SetParamC = Int32 Function(Pointer<Void>, Int32, Float);

/// Wrapper around the dynamic library providing access to the C
/// functions. Users generally should not use this directly; instead
/// use the VstHost and VstPlugin classes in host.dart which manage
/// resources safely.
class NativeBindings {
  final DynamicLibrary lib;

  NativeBindings(this.lib);

  late final Pointer<Utf8> Function() dvhGetVersion =
      lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('dvh_get_version');

  late final Pointer<Void> Function(double, int) dvhCreateHost =
      lib.lookupFunction<_HostCreateC, Pointer<Void> Function(double, int)>('dvh_create_host');

  late final void Function(Pointer<Void>) dvhDestroyHost =
      lib.lookupFunction<_HostDestroyC, void Function(Pointer<Void>)>('dvh_destroy_host');

  late final Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) dvhLoadPlugin =
      lib.lookupFunction<_LoadC, Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>('dvh_load_plugin');

  late final void Function(Pointer<Void>) dvhUnloadPlugin =
      lib.lookupFunction<_UnloadC, void Function(Pointer<Void>)>('dvh_unload_plugin');

  late final int Function(Pointer<Void>, double, int) dvhResume =
      lib.lookupFunction<_ResumeC, int Function(Pointer<Void>, double, int)>('dvh_resume');

  late final int Function(Pointer<Void>) dvhSuspend =
      lib.lookupFunction<_SuspendC, int Function(Pointer<Void>)>('dvh_suspend');

  late final void Function(double, int, int, int, double, int) dvhSetTransport =
      lib.lookupFunction<_SetTransportC, void Function(double, int, int, int, double, int)>('dvh_set_transport');

  late final int Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>, int) dvhProcessStereoF32 =
      lib.lookupFunction<_ProcessStereoC, int Function(Pointer<Void>, Pointer<Float>, Pointer<Float>, Pointer<Float>, Pointer<Float>, int)>('dvh_process_stereo_f32');

  late final int Function(Pointer<Void>, int, int, double) dvhNoteOn =
      lib.lookupFunction<_NoteC, int Function(Pointer<Void>, int, int, double)>('dvh_note_on');

  late final int Function(Pointer<Void>, int, int, double) dvhNoteOff =
      lib.lookupFunction<_NoteC, int Function(Pointer<Void>, int, int, double)>('dvh_note_off');

  late final int Function(Pointer<Void>) dvhParamCount =
      lib.lookupFunction<_ParamCountC, int Function(Pointer<Void>)>('dvh_param_count');

  late final int Function(Pointer<Void>, int, Pointer<Int32>, Pointer<Utf8>, int, Pointer<Utf8>, int) dvhParamInfo =
      lib.lookupFunction<_ParamInfoC, int Function(Pointer<Void>, int, Pointer<Int32>, Pointer<Utf8>, int, Pointer<Utf8>, int)>('dvh_param_info');

  late final double Function(Pointer<Void>, int) dvhGetParam =
      lib.lookupFunction<_GetParamC, double Function(Pointer<Void>, int)>('dvh_get_param_normalized');

  late final int Function(Pointer<Void>, int, double) dvhSetParam =
      lib.lookupFunction<_SetParamC, int Function(Pointer<Void>, int, double)>('dvh_set_param_normalized');

  // ALSA audio thread management (Linux only, stubs on other platforms).
  late final void Function(Pointer<Void>, Pointer<Void>) dvhAudioAddPlugin =
      lib.lookupFunction<
          Void Function(Pointer<Void>, Pointer<Void>),
          void Function(Pointer<Void>, Pointer<Void>)
      >('dvh_audio_add_plugin');

  late final void Function(Pointer<Void>, Pointer<Void>) dvhAudioRemovePlugin =
      lib.lookupFunction<
          Void Function(Pointer<Void>, Pointer<Void>),
          void Function(Pointer<Void>, Pointer<Void>)
      >('dvh_audio_remove_plugin');

  late final void Function(Pointer<Void>) dvhAudioClearPlugins =
      lib.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
      >('dvh_audio_clear_plugins');

  late final int Function(Pointer<Void>, Pointer<Utf8>) dvhStartAlsaThread =
      lib.lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>)
      >('dvh_start_alsa_thread');

  late final void Function(Pointer<Void>) dvhStopAlsaThread =
      lib.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
      >('dvh_stop_alsa_thread');

  // Audio graph routing (Phase 5.4).
  // dvh_set_processing_order: set topological processing order.
  late final void Function(Pointer<Void>, Pointer<Pointer<Void>>, int) dvhSetProcessingOrder =
      lib.lookupFunction<
          Void Function(Pointer<Void>, Pointer<Pointer<Void>>, Int32),
          void Function(Pointer<Void>, Pointer<Pointer<Void>>, int)
      >('dvh_set_processing_order');

  // dvh_route_audio: route from_plugin output → to_plugin input.
  late final void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>) dvhRouteAudio =
      lib.lookupFunction<
          Void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
          void Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)
      >('dvh_route_audio');

  // dvh_clear_routes: remove all audio routing rules.
  late final void Function(Pointer<Void>) dvhClearRoutes =
      lib.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
      >('dvh_clear_routes');

  // dvh_set_external_render: register a non-VST3 render function as the audio
  // source for a VST3 plugin's input (e.g. Theremin DSP → Reverb effect).
  // [fn] is a Pointer to a C function with signature:
  //   void render(float* outL, float* outR, int32_t frames)
  late final void Function(
    Pointer<Void>, Pointer<Void>,
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
  ) dvhSetExternalRender = lib.lookupFunction<
      Void Function(
        Pointer<Void>, Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
      ),
      void Function(
        Pointer<Void>, Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
      )
  >('dvh_set_external_render');

  // dvh_clear_external_render: remove external render for a plugin.
  late final void Function(Pointer<Void>, Pointer<Void>) dvhClearExternalRender =
      lib.lookupFunction<
          Void Function(Pointer<Void>, Pointer<Void>),
          void Function(Pointer<Void>, Pointer<Void>)
      >('dvh_clear_external_render');

  // dvh_add_master_render: register a render fn as a master-mix contributor.
  // The fn is called each ALSA block and its stereo output is mixed into the
  // master bus alongside VST3 plugin outputs. Deduplicated on the C side.
  late final void Function(
    Pointer<Void>,
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
  ) dvhAddMasterRender = lib.lookupFunction<
      Void Function(
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
      ),
      void Function(
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
      )
  >('dvh_add_master_render');

  // dvh_remove_master_render: remove a previously registered master-mix fn.
  late final void Function(
    Pointer<Void>,
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
  ) dvhRemoveMasterRender = lib.lookupFunction<
      Void Function(
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
      ),
      void Function(
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
      )
  >('dvh_remove_master_render');

  // ── GFPA native DSP API ────────────────────────────────────────────────────
  //
  // Bindings for the GFPA DSP effect instances defined in gfpa_dsp.h.
  // These are used by VstHostService to create/destroy per-slot native effects
  // and to wire them into the ALSA master-insert chain.

  /// Create a native DSP instance for the given pluginId.
  /// Returns nullptr for unrecognised IDs.
  late final Pointer<Void> Function(Pointer<Utf8>, int, int) gfpaDspCreate =
      lib.lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>, Int32, Int32),
          Pointer<Void> Function(Pointer<Utf8>, int, int)
      >('gfpa_dsp_create');

  /// Set a physical (denormalized) parameter value on a DSP instance.
  late final void Function(Pointer<Void>, Pointer<Utf8>, double) gfpaDspSetParam =
      lib.lookupFunction<
          Void Function(Pointer<Void>, Pointer<Utf8>, Double),
          void Function(Pointer<Void>, Pointer<Utf8>, double)
      >('gfpa_dsp_set_param');

  /// Return the static insert callback function pointer for this DSP instance.
  /// The type is treated as Pointer(Void) since Dart FFI cannot store function
  /// pointers in typed fields directly; the native side casts it correctly.
  late final Pointer<Void> Function(Pointer<Void>) gfpaDspInsertFn =
      lib.lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
      >('gfpa_dsp_insert_fn');

  /// Return the userdata pointer to pass alongside the insert callback.
  late final Pointer<Void> Function(Pointer<Void>) gfpaDspUserdata =
      lib.lookupFunction<
          Pointer<Void> Function(Pointer<Void>),
          Pointer<Void> Function(Pointer<Void>)
      >('gfpa_dsp_userdata');

  /// Destroy a DSP instance and free all associated resources.
  late final void Function(Pointer<Void>) gfpaDspDestroy =
      lib.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
      >('gfpa_dsp_destroy');

  /// Set the global BPM for BPM-synced effects (delay, wah, chorus).
  late final void Function(double) gfpaSetBpm =
      lib.lookupFunction<Void Function(Double), void Function(double)>('gfpa_set_bpm');

  // ── GFPA master-insert chain ───────────────────────────────────────────────

  /// Register a GFPA insert on a master-render source.
  /// insertFnPtr and userdata are both Pointer(Void) at the FFI boundary;
  /// the native side casts them back to the correct function pointer types.
  late final void Function(
    Pointer<Void>,
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
    Pointer<Void>,
    Pointer<Void>,
  ) dvhAddMasterInsert = lib.lookupFunction<
      Void Function(
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
        Pointer<Void>,
        Pointer<Void>,
      ),
      void Function(
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
        Pointer<Void>,
        Pointer<Void>,
      )
  >('dvh_add_master_insert');

  /// Remove the GFPA insert registered for [source].
  late final void Function(
    Pointer<Void>,
    Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
  ) dvhRemoveMasterInsert = lib.lookupFunction<
      Void Function(
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
      ),
      void Function(
        Pointer<Void>,
        Pointer<NativeFunction<Void Function(Pointer<Float>, Pointer<Float>, Int32)>>,
      )
  >('dvh_remove_master_insert');

  /// Remove all registered master inserts.
  late final void Function(Pointer<Void>) dvhClearMasterInserts =
      lib.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
      >('dvh_clear_master_inserts');

  // macOS specific audio management
  late final int Function(Pointer<Void>) dvhMacStartAudio =
      lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('dvh_mac_start_audio');

  late final void Function(Pointer<Void>) dvhMacStopAudio =
      lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('dvh_mac_stop_audio');

  // Parameter unit/group API.
  late final int Function(Pointer<Void>, int) dvhParamUnitId =
      lib.lookupFunction<Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)>('dvh_param_unit_id');

  late final int Function(Pointer<Void>) dvhUnitCount =
      lib.lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('dvh_unit_count');

  late final int Function(Pointer<Void>, int, Pointer<Utf8>, int) dvhUnitName =
      lib.lookupFunction<
          Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>, Int32),
          int Function(Pointer<Void>, int, Pointer<Utf8>, int)>('dvh_unit_name');

  // Plugin editor GUI (X11 on Linux, stubs elsewhere).
  late final int Function(Pointer<Void>, Pointer<Utf8>) dvhOpenEditor =
      lib.lookupFunction<
          IntPtr Function(Pointer<Void>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>)
      >('dvh_open_editor');

  late final void Function(Pointer<Void>) dvhCloseEditor =
      lib.lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
      >('dvh_close_editor');

  late final int Function(Pointer<Void>) dvhEditorIsOpen =
      lib.lookupFunction<
          Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)
      >('dvh_editor_is_open');

  // macOS specific editor
  late final int Function(Pointer<Void>, Pointer<Utf8>) dvhMacOpenEditor =
      lib.lookupFunction<IntPtr Function(Pointer<Void>, Pointer<Utf8>), int Function(Pointer<Void>, Pointer<Utf8>)>('dvh_mac_open_editor');

  late final void Function(Pointer<Void>) dvhMacCloseEditor =
      lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('dvh_mac_close_editor');

  late final int Function(Pointer<Void>) dvhMacEditorIsOpen =
      lib.lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>('dvh_mac_editor_is_open');
}

/// Load the native library. The optional [path] may be used to point
/// directly at libdart_vst_host.{so,dylib,dll}. On platforms where
/// dynamic library lookup is provided by the process/executable, this
/// falls back accordingly.
DynamicLibrary loadDvh({String? path}) {
  if (path != null) return DynamicLibrary.open(path);
  if (Platform.isMacOS) return DynamicLibrary.open('libdart_vst_host.dylib');
  if (Platform.isLinux) return DynamicLibrary.open('libdart_vst_host.so');
  if (Platform.isWindows) return DynamicLibrary.open('dart_vst_host.dll');
  // Use process/executable fallback when available
  try {
    return DynamicLibrary.process();
  } catch (_) {}
  try {
    return DynamicLibrary.executable();
  } catch (_) {}
  throw UnsupportedError('Unable to locate native dart_vst_host library');
}