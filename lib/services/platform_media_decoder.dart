import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the platform decoder produced.
class PlatformDecodeResult {
  const PlatformDecodeResult({
    required this.frames,
    required this.sampleRate,
    required this.channels,
  });

  final int frames;
  final int sampleRate;
  final int channels;
}

/// Decodes the formats GrooveForge's bundled decoders cannot read, using the
/// platform's own codecs.
///
/// miniaudio covers MP3, FLAC and WAV everywhere. AAC/M4A — most of what sits
/// in a phone's music library — and the audio track of a video container need
/// a decoder we deliberately do not bundle: `ffmpeg_kit_flutter` was archived
/// in 2025 and ships prebuilt binaries, which F-Droid will not accept. The
/// platform's own MediaExtractor and MediaCodec are system APIs and bundle
/// nothing.
///
/// The result is a WAV at the source's own sample rate and channel count.
/// Folding to mono and resampling to the engine's rate is left to
/// `gf_media_to_mono_wav`, which already does both.
class PlatformMediaDecoder {
  PlatformMediaDecoder._();

  static const MethodChannel _channel =
      MethodChannel('com.grooveforge/media_decode');

  /// Whether this platform has a decoder beyond the bundled ones.
  ///
  /// Android only for now. iOS has the equivalent in AVAssetReader and is the
  /// obvious next one; the desktop builds have no system decoder to reach for,
  /// so there the bundled three formats are the whole set.
  static bool get isSupported => !kIsWeb && Platform.isAndroid;

  /// Decodes the first audio track of [src] into a 16-bit PCM WAV at [dst].
  ///
  /// Returns null if the platform cannot decode it. Takes a second or two on a
  /// four-minute file, but runs on a background thread on the platform side,
  /// so it does not block the UI.
  static Future<PlatformDecodeResult?> decodeToWav(
      String src, String dst) async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'decodeToWav',
        {'src': src, 'dst': dst},
      );
      if (res == null) return null;
      return PlatformDecodeResult(
        frames: (res['frames'] as num?)?.toInt() ?? 0,
        sampleRate: (res['sampleRate'] as num?)?.toInt() ?? 0,
        channels: (res['channels'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      debugPrint('PlatformMediaDecoder: ${e.code} ${e.message}');
      return null;
    } on MissingPluginException {
      // The channel is only registered on Android; anywhere else this is the
      // expected outcome rather than a failure worth reporting.
      return null;
    }
  }

  /// Extensions worth offering in a file picker on this platform.
  ///
  /// The picker greys out everything else, so a file that cannot be imported
  /// cannot be chosen in the first place — better than accepting it and
  /// failing afterwards.
  static List<String> get pickableExtensions => isSupported
      ? const [
          // Handled by the bundled decoders on every platform.
          'mp3', 'wav', 'flac',
          // Handled by the platform decoder.
          'm4a', 'aac', 'mp4', 'm4b', '3gp', 'ogg', 'opus', 'mkv', 'webm',
        ]
      : const ['mp3', 'wav', 'flac'];
}
