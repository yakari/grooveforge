package com.grooveforge.grooveforge

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Decodes the formats GrooveForge's bundled decoders cannot read.
 *
 * miniaudio ships with dr_wav, dr_flac and dr_mp3, which covers MP3, FLAC and
 * WAV on every platform for free. It does not cover AAC/M4A — which is most of
 * what sits in a phone's music library — nor the audio track of a video
 * container, which is how a screencast arrives.
 *
 * The obvious answer, bundling FFmpeg, is not open to us: `ffmpeg_kit_flutter`
 * was archived in 2025 and ships prebuilt binaries, which F-Droid will not
 * accept. Android's own MediaExtractor and MediaCodec are system APIs, so they
 * bundle nothing at all and handle every format the phone can already play.
 *
 * Scope is deliberately narrow: this produces a WAV at the source's *own*
 * sample rate and channel count, and nothing else. Folding to mono and
 * resampling to the engine's rate is left to `gf_media_to_mono_wav`, which
 * already does both and is already tested — reimplementing a resampler in
 * Kotlin to save one intermediate file would be a poor trade.
 */
class MediaDecoderPlugin : MethodChannel.MethodCallHandler {

    companion object {
        const val METHOD_CHANNEL = "com.grooveforge/media_decode"
        private const val TAG = "GrooveForgeMedia"

        /** Give up rather than spin forever on a file the codec will not drain. */
        private const val DEQUEUE_TIMEOUT_US = 10_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "decodeToWav" -> {
                val src = call.argument<String>("src")
                val dst = call.argument<String>("dst")
                if (src == null || dst == null) {
                    result.error("BAD_ARGS", "src and dst are required", null)
                    return
                }
                // Decoding a four-minute file takes seconds, and method calls
                // arrive on the platform thread — doing it here would freeze
                // the UI and eventually ANR.
                Thread {
                    val outcome = try {
                        decode(src, dst)
                    } catch (e: Exception) {
                        Log.e(TAG, "decode failed", e)
                        Result.failure<Map<String, Any>>(e)
                    }
                    mainHandler.post {
                        outcome.fold(
                            onSuccess = { result.success(it) },
                            onFailure = {
                                result.error("DECODE_FAILED",
                                    it.message ?: "could not decode", null)
                            },
                        )
                    }
                }.start()
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Decodes the first audio track of [src] into a 16-bit PCM WAV at [dst].
     *
     * Returns the sample rate, channel count and frame count of what was
     * written, so the caller can sanity-check it before handing the file on.
     */
    private fun decode(src: String, dst: String): Result<Map<String, Any>> {
        val extractor = MediaExtractor()
        extractor.setDataSource(src)

        // A video container has a video track first; taking "track 0" would
        // hand the audio decoder a stream of pictures.
        var trackIndex = -1
        var format: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val f = extractor.getTrackFormat(i)
            val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                trackIndex = i
                format = f
                break
            }
        }
        if (trackIndex < 0 || format == null) {
            extractor.release()
            return Result.failure(IllegalArgumentException("no audio track"))
        }

        extractor.selectTrack(trackIndex)
        val mime = format.getString(MediaFormat.KEY_MIME)!!
        var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

        val codec = MediaCodec.createDecoderByType(mime)
        codec.configure(format, null, null, 0)
        codec.start()

        val out = File(dst)
        val raf = RandomAccessFile(out, "rw")
        raf.setLength(0)
        raf.write(ByteArray(44))          // header placeholder, patched at the end

        var totalBytes = 0L
        var sawInputEnd = false
        var sawOutputEnd = false
        val info = MediaCodec.BufferInfo()

        try {
            while (!sawOutputEnd) {
                if (!sawInputEnd) {
                    val inIndex = codec.dequeueInputBuffer(DEQUEUE_TIMEOUT_US)
                    if (inIndex >= 0) {
                        val buffer = codec.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            codec.queueInputBuffer(inIndex, 0, 0, 0,
                                MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            sawInputEnd = true
                        } else {
                            codec.queueInputBuffer(inIndex, 0, size,
                                extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                when (val outIndex = codec.dequeueOutputBuffer(info, DEQUEUE_TIMEOUT_US)) {
                    MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        // The real values only become known once decoding has
                        // begun; the track format is a hint the codec is free
                        // to contradict.
                        val actual = codec.outputFormat
                        sampleRate = actual.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = actual.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                    MediaCodec.INFO_TRY_AGAIN_LATER -> { /* nothing ready yet */ }
                    else -> {
                        if (outIndex >= 0) {
                            val buffer = codec.getOutputBuffer(outIndex)!!
                            if (info.size > 0) {
                                val chunk = ByteArray(info.size)
                                buffer.position(info.offset)
                                buffer.get(chunk, 0, info.size)
                                raf.write(chunk)
                                totalBytes += info.size
                            }
                            buffer.clear()
                            codec.releaseOutputBuffer(outIndex, false)
                            if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                                sawOutputEnd = true
                            }
                        }
                    }
                }
            }
        } finally {
            try { codec.stop() } catch (_: Exception) {}
            codec.release()
            extractor.release()
        }

        if (totalBytes <= 0L) {
            raf.close()
            out.delete()
            return Result.failure(IllegalStateException("decoded nothing"))
        }

        writeWavHeader(raf, totalBytes, sampleRate, channels)
        raf.close()

        val frames = totalBytes / (2L * channels)
        Log.i(TAG, "decoded $mime -> $frames frames, $sampleRate Hz, $channels ch")
        return Result.success(
            mapOf(
                "frames" to frames,
                "sampleRate" to sampleRate,
                "channels" to channels,
            )
        )
    }

    /** Patches a 16-bit PCM WAV header over the 44 bytes reserved at the start. */
    private fun writeWavHeader(
        raf: RandomAccessFile,
        dataBytes: Long,
        sampleRate: Int,
        channels: Int,
    ) {
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        val byteRate = sampleRate * channels * 2
        header.put("RIFF".toByteArray())
        header.putInt((36 + dataBytes).toInt())
        header.put("WAVE".toByteArray())
        header.put("fmt ".toByteArray())
        header.putInt(16)
        header.putShort(1)                       // PCM
        header.putShort(channels.toShort())
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort((channels * 2).toShort())
        header.putShort(16)                      // bits per sample
        header.put("data".toByteArray())
        header.putInt(dataBytes.toInt())
        raf.seek(0)
        raf.write(header.array())
    }
}
