import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// Finds where an imported recording actually starts making a sound.
///
/// Commercial tracks and screen recordings begin with anything from a few
/// milliseconds of digital black to two seconds of room tone, and the first
/// thing anybody does when aligning one is drag the marker past it. This is
/// that drag, done for them.
///
/// It only reports *where* the sound starts; nothing is cut. The file stays
/// whole because the grid may legitimately begin before the first note — an
/// upbeat, a count-in on the recording itself — and a trim would throw that
/// away irreversibly.
class MasterSilence {
  /// Where the master stops being silent, in frames, or 0 if it never is.
  ///
  /// Reads only the opening of the file: the answer is always near the front,
  /// and a three-minute master is seventeen megabytes nobody needs to load to
  /// find it.
  static Future<int> firstSound(String wavPath, {int sampleRate = 48000}) async {
    try {
      return await Isolate.run(() => _scan(wavPath, sampleRate));
    } catch (e) {
      debugPrint('MasterSilence: could not scan — $e');
      return 0;
    }
  }
}

/// Mono 16-bit, which is what every decoded master is stored as.
const int _headerBytes = 44;

/// How far in to look. A recording that is quiet for longer than this is not
/// leading silence, it is the arrangement.
const int _windowSeconds = 30;

/// Level a sample has to reach to count as sound.
///
/// About -46 dBFS. Low enough to catch a soft entry, high enough to ignore
/// the noise floor of a phone recording or an MP3's encoder hiss, which never
/// quite reaches digital silence.
const int _threshold = 160;

/// How much sound has to be there before it counts.
///
/// A single sample over the threshold is a click or a decoder artefact. A
/// couple of milliseconds of it is a note.
const int _runFrames = 96;

int _scan(String path, int sampleRate) {
  final file = File(path);
  if (!file.existsSync()) return 0;

  final length = file.lengthSync();
  final want = _headerBytes + sampleRate * 2 * _windowSeconds;
  final raf = file.openSync();
  Uint8List bytes;
  try {
    raf.setPositionSync(_headerBytes);
    final toRead = (want < length ? want : length) - _headerBytes;
    if (toRead <= 0) return 0;
    bytes = raf.readSync(toRead);
  } finally {
    raf.closeSync();
  }

  final samples = bytes.buffer.asInt16List(
    bytes.offsetInBytes,
    bytes.lengthInBytes ~/ 2,
  );

  var run = 0;
  for (var i = 0; i < samples.length; i++) {
    final v = samples[i];
    if ((v < 0 ? -v : v) < _threshold) {
      run = 0;
      continue;
    }
    run++;
    // Report the start of the run, not its end: the note began where the
    // sound first crossed the threshold.
    if (run >= _runFrames) return i - run + 1;
  }
  return 0;
}
