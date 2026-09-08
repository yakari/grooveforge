import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'stretch_job.dart';

/// Renders every job in turn, in whatever isolate calls this.
///
/// Binds the one function it needs rather than building the app's whole FFI
/// surface. That surface opens a second library and resolves scores of symbols
/// belonging to the synth, the looper and the vocoder — none of which has
/// anything to do with stretching a file, and any one of which failing to
/// resolve in a background isolate takes the render down with it.
///
/// Returns the number of jobs that failed, or -1 if the library itself could
/// not be opened.
int renderStretchJobs(List<StretchJob> jobs) {
  late final DynamicLibrary lib;
  try {
    lib = Platform.isMacOS
        ? DynamicLibrary.open('libaudio_input.dylib')
        : Platform.isWindows
            ? DynamicLibrary.open('audio_input.dll')
            : DynamicLibrary.open('libaudio_input.so');
  } catch (e) {
    debugPrint('rehearsal stretch: no audio library in this isolate — $e');
    return -1;
  }

  final render = lib.lookupFunction<
      Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Float),
      int Function(Pointer<Utf8>, Pointer<Utf8>, double)>('gf_ts_render');

  var failures = 0;
  for (final job in jobs) {
    final from = job.source.toNativeUtf8();
    final to = job.destination.toNativeUtf8();
    try {
      final rc = render(from, to, job.ratio);
      if (rc != 0) {
        failures++;
        debugPrint('rehearsal stretch: failed ($rc) for ${job.source}');
      }
    } finally {
      calloc.free(from);
      calloc.free(to);
    }
  }
  return failures;
}
