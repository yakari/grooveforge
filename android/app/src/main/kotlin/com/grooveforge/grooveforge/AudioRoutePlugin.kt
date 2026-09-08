package com.grooveforge.grooveforge

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Tells Dart where the sound is currently coming out.
 *
 * Overdub compensation belongs to the *route*, not to the device: a phone's
 * own speaker is a few milliseconds away, a wired headset a few more, and a
 * Bluetooth headset can be two hundred. One stored number cannot describe all
 * three, so the app keeps a measurement per route and needs a stable key to
 * file them under.
 *
 * Android has no API that reports the latency of a path (the NDK guide says so
 * outright), which is why this reports *identity* rather than latency: knowing
 * which headset is connected is enough to look up a measurement the user has
 * already taken, and to notice when they have not taken one.
 */
class AudioRoutePlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "com.grooveforge/audio_route"
        const val EVENT_CHANNEL = "com.grooveforge/audio_route_events"
    }

    private val audioManager: AudioManager
        get() = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private var events: EventChannel.EventSink? = null
    private var callback: AudioDeviceCallback? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "current" -> result.success(currentRoute())
            else -> result.notImplemented()
        }
    }

    /**
     * The route sound is playing out of, as a stable key and a readable label.
     *
     * Ordered by precedence rather than asked for directly, because Android
     * only exposes which devices are *available*; the active one is inferred
     * the same way the platform itself routes — Bluetooth wins over a wire,
     * a wire wins over the speaker.
     */
    private fun currentRoute(): Map<String, String> {
        val devices = try {
            audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        } catch (e: Exception) {
            emptyArray<AudioDeviceInfo>()
        }

        val bluetooth = devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }
        if (bluetooth != null) {
            // Named, because someone may own several headsets and each has its
            // own delay. A blank name would collapse them into one entry and
            // silently apply the wrong figure.
            val name = bluetooth.productName?.toString()?.trim().orEmpty()
            return mapOf(
                "key" to "bt:" + name.ifEmpty { "unknown" },
                "label" to name.ifEmpty { "Bluetooth" },
                "kind" to "bluetooth",
            )
        }

        val wired = devices.firstOrNull {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                it.type == AudioDeviceInfo.TYPE_USB_DEVICE
        }
        if (wired != null) {
            // Not named: wired headphones differ from each other by a
            // millisecond or two, which is below what any of this can measure.
            return mapOf("key" to "wired", "label" to "Wired", "kind" to "wired")
        }

        return mapOf("key" to "speaker", "label" to "Speaker", "kind" to "speaker")
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        val handler = Handler(Looper.getMainLooper())
        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>?) {
                events?.success(currentRoute())
            }

            override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>?) {
                events?.success(currentRoute())
            }
        }
        callback = cb
        audioManager.registerAudioDeviceCallback(cb, handler)
        // The current state straight away, so a listener does not have to wait
        // for somebody to unplug something before it knows anything.
        sink?.success(currentRoute())
    }

    override fun onCancel(arguments: Any?) {
        callback?.let { audioManager.unregisterAudioDeviceCallback(it) }
        callback = null
        events = null
    }
}
