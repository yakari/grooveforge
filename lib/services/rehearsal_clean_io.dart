import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'clean_job.dart';

/// Removes the phone's own speaker from [job]'s take, in whatever isolate
/// calls this.
///
/// Binds the one function it needs rather than building the app's whole FFI
/// surface, for the same reason [renderStretchJobs] does: that surface opens a
/// second library and resolves scores of symbols belonging to the synth, the
/// looper and the vocoder, none of which has anything to do with cancelling an
/// echo, and any one of which failing to resolve in a background isolate takes
/// the whole thing down.
CleanResult runCleanJob(CleanJob job) {
  late final DynamicLibrary lib;
  try {
    lib = Platform.isMacOS
        ? DynamicLibrary.open('libaudio_input.dylib')
        : Platform.isWindows
            ? DynamicLibrary.open('audio_input.dll')
            : DynamicLibrary.open('libaudio_input.so');
  } catch (e) {
    debugPrint('rehearsal clean: no audio library in this isolate — $e');
    return CleanResult.failed;
  }

  final render = lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32,
          Pointer<Float>),
      int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int,
          Pointer<Float>)>('gf_aec_render');

  final mic = job.takePath.toNativeUtf8();
  final ref = job.referencePath.toNativeUtf8();
  final out = job.outputPath.toNativeUtf8();
  final reduction = malloc<Float>();
  try {
    reduction.value = 0;
    final rc = render(mic, ref, out, job.expectedDelayFrames, reduction);
    if (rc != 0) {
      debugPrint('rehearsal clean: canceller returned $rc');
      return CleanResult.failed;
    }
    return CleanResult(ok: true, reductionDb: reduction.value);
  } catch (e) {
    debugPrint('rehearsal clean: failed — $e');
    return CleanResult.failed;
  } finally {
    malloc.free(mic);
    malloc.free(ref);
    malloc.free(out);
    malloc.free(reduction);
  }
}
