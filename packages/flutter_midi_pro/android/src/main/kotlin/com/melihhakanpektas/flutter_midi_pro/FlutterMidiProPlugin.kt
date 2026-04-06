package com.melihhakanpektas.flutter_midi_pro

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import android.media.AudioManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  companion object {
    init {
      System.loadLibrary("native-lib")
    }
    @JvmStatic
    private external fun loadSoundfont(path: String, bank: Int, program: Int): Int

    @JvmStatic
    private external fun selectInstrument(sfId: Int, channel:Int, bank: Int, program: Int)

    @JvmStatic
    private external fun playNote(channel: Int, key: Int, velocity: Int, sfId: Int)

    @JvmStatic
    private external fun stopNote(channel: Int, key: Int, sfId: Int)

    @JvmStatic
    private external fun stopAllNotes(sfId: Int)

    @JvmStatic
    private external fun controlChange(sfId: Int, channel: Int, controller: Int, value: Int)

    @JvmStatic
    private external fun pitchBend(sfId: Int, channel: Int, value: Int)

    @JvmStatic
    private external fun setGain(gain: Double)

    @JvmStatic
    private external fun unloadSoundfont(sfId: Int)

    @JvmStatic
    private external fun setOutputDevice(deviceId: Int)

    @JvmStatic
    private external fun dispose()
  }

  private lateinit var channel : MethodChannel
  private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

  // Dedicated single-threaded executor for real-time audio JNI calls.
  //
  // Every hot-path operation (playNote, stopNote, controlChange, pitchBend)
  // is dispatched here instead of running on the Android main thread.
  //
  // The Android main thread also handles the Choreographer (vsync) callbacks
  // that drive Flutter's frame pipeline.  When playNote ran on the main thread,
  // a vsync frame render could interleave between consecutive note-on messages
  // of a chord — delaying subsequent notes by 10–20 ms even on fast hardware.
  //
  // By executing on this isolated thread:
  //   1. FluidSynth JNI calls are never preempted by UI frame renders.
  //   2. All three notes of a chord reach fluid_synth_noteon() back-to-back,
  //      within the same FluidSynth audio buffer → heard simultaneously.
  //   3. result.success(null) is returned to Dart *before* the JNI call,
  //      so the Dart event loop is unblocked immediately regardless of
  //      how long the audio work takes.
  //
  // Thread priority is set to MAX so the OS scheduler prefers audio work over
  // background tasks when the device is under load.
  private val audioExecutor = Executors.newSingleThreadExecutor { runnable ->
    Thread(runnable, "GrooveForge-Audio").also {
      it.priority = Thread.MAX_PRIORITY
    }
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    this.flutterPluginBinding = flutterPluginBinding
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "loadSoundfont" -> {
        CoroutineScope(Dispatchers.IO).launch {
          val path = call.argument<String>("path") as String
          val bank = call.argument<Int>("bank")?:0
          val program = call.argument<Int>("program")?:0
          val audioManager = flutterPluginBinding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

          // Mute while loading to prevent a click when FluidSynth reinitialises.
          audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, 0)

          val sfId = loadSoundfont(path, bank, program)
          delay(250)

          audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0)

          withContext(Dispatchers.Main) {
            if (sfId == -1) {
              result.error("INVALID_ARGUMENT", "Something went wrong. Check the path of the template soundfont", null)
            } else {
              result.success(sfId)
            }
          }
        }
      }

      "selectInstrument" -> {
        val sfId = call.argument<Int>("sfId")?:1
        val ch   = call.argument<Int>("channel")?:0
        val bank = call.argument<Int>("bank")?:0
        val prog = call.argument<Int>("program")?:0
        result.success(null)
        audioExecutor.execute { selectInstrument(sfId, ch, bank, prog) }
      }

      // ── Real-time note events ────────────────────────────────────────────
      // result.success(null) is sent BEFORE the JNI dispatch so that the
      // Dart Future resolves immediately.  Dart never awaits these calls in
      // the hot path, but returning early ensures the method-channel round-
      // trip does not add latency on top of the audio thread queue.

      "playNote" -> {
        val ch  = call.argument<Int>("channel")
        val key = call.argument<Int>("key")
        val vel = call.argument<Int>("velocity")
        val sfId = call.argument<Int>("sfId")
        if (ch != null && key != null && vel != null && sfId != null) {
          result.success(null)
          audioExecutor.execute { playNote(ch, key, vel, sfId) }
        } else {
          result.error("INVALID_ARGUMENT", "channel, key, velocity and sfId are required", null)
        }
      }

      "stopNote" -> {
        val ch   = call.argument<Int>("channel")
        val key  = call.argument<Int>("key")
        val sfId = call.argument<Int>("sfId")
        if (ch != null && key != null && sfId != null) {
          result.success(null)
          audioExecutor.execute { stopNote(ch, key, sfId) }
        } else {
          result.error("INVALID_ARGUMENT", "channel and key are required", null)
        }
      }

      "stopAllNotes" -> {
        val sfId = call.argument<Int>("sfId") as Int
        result.success(null)
        audioExecutor.execute { stopAllNotes(sfId) }
      }

      "controlChange" -> {
        val sfId       = call.argument<Int>("sfId") ?: 1
        val ch         = call.argument<Int>("channel") ?: 0
        val controller = call.argument<Int>("controller") ?: 0
        val value      = call.argument<Int>("value") ?: 0
        result.success(null)
        audioExecutor.execute { controlChange(sfId, ch, controller, value) }
      }

      "pitchBend" -> {
        val sfId  = call.argument<Int>("sfId") ?: 1
        val ch    = call.argument<Int>("channel") ?: 0
        val value = call.argument<Int>("value") ?: 8192
        result.success(null)
        audioExecutor.execute { pitchBend(sfId, ch, value) }
      }

      "setGain" -> {
        val gain = call.argument<Double>("gain") ?: 5.0
        result.success(null)
        audioExecutor.execute { setGain(gain) }
      }

      "unloadSoundfont" -> {
        val sfId = call.argument<Int>("sfId")
        if (sfId != null) {
          result.success(null)
          audioExecutor.execute { unloadSoundfont(sfId) }
        } else {
          result.error("INVALID_ARGUMENT", "sfId is required", null)
        }
      }

      "setOutputDevice" -> {
        val deviceId = call.argument<Int>("deviceId") ?: 0
        result.success(null)
        audioExecutor.execute { setOutputDevice(deviceId) }
      }

      "dispose" -> {
        result.success(null)
        audioExecutor.execute { dispose() }
      }

      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    audioExecutor.shutdown()
  }
}
