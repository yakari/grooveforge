package com.grooveforge.grooveforge

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TAG = "GrooveForge"
    private val CHANNEL = "com.grooveforge.grooveforge/audio_config"
    private val mainHandler = Handler(Looper.getMainLooper())
    private var methodChannel: MethodChannel? = null
    private var audioManager: AudioManager? = null

    // ── Audio focus ──────────────────────────────────────────────────────────
    //
    // Android has no way for an app to lock other apps out of the audio
    // hardware — AAudio's EXCLUSIVE (MMAP) mode is exclusive over a device
    // *endpoint*, not over the system, and the only thing it does when
    // another app already holds it is make GrooveForge fall back to a shared
    // stream. Audio focus is the mechanism that actually makes the other app
    // stop, and without requesting it GrooveForge was simply one more player
    // in the mix.
    //
    // Two symptoms this addresses. Plugging a jack makes Spotify start
    // playing, because nothing told it not to. And a media app that was
    // already running holds the low-latency path, which forces GrooveForge
    // onto a contended shared stream — heard as audio cutting every few
    // hundred milliseconds.
    //
    // AUDIOFOCUS_GAIN, not one of the TRANSIENT variants: a musical
    // instrument is not a notification that borrows the output for a second
    // and hands it back. Other media apps are expected to stop, not duck.
    private var audioFocusRequest: AudioFocusRequest? = null

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        // Deliberately no reaction beyond logging. Pausing the engine on
        // focus loss would kill a live performance the moment a notification
        // arrived, and GrooveForge is an instrument: the player decides when
        // it stops.
        Log.i(TAG, "Audio focus changed: $change")
    }

    /// Asks the system to hand this app the output and stop other players.
    private fun requestAudioFocus() {
        val am = audioManager ?: return
        if (audioFocusRequest != null) return

        val attributes = AudioAttributes.Builder()
            // Matches the AAudio stream's own usage, so the platform routes
            // and prioritises both halves of the app the same way.
            .setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes)
            // Never let the system quietly duck the instrument under a
            // notification; a harmony dropping 20 dB mid-phrase is worse than
            // the notification being inaudible.
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener(focusListener, mainHandler)
            .build()

        val result = am.requestAudioFocus(request)
        if (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            audioFocusRequest = request
            Log.i(TAG, "Audio focus granted — other media apps asked to stop")
        } else {
            Log.w(TAG, "Audio focus request refused ($result); another app keeps the output")
        }
    }

    /// Hands focus back, so whatever was playing may resume.
    private fun abandonAudioFocus() {
        val am = audioManager ?: return
        audioFocusRequest?.let {
            am.abandonAudioFocusRequest(it)
            audioFocusRequest = null
            Log.i(TAG, "Audio focus released")
        }
    }

    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
            mainHandler.post { methodChannel?.invokeMethod("audioDevicesChanged", null) }
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
            mainHandler.post { methodChannel?.invokeMethod("audioDevicesChanged", null) }
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        // ── Theremin camera distance plugin ───────────────────────────────────
        // Streams front-camera focal distance as normalized [0, 1] values for
        // the camera-mode Theremin. MethodChannel handles start/stop; the main
        // EventChannel carries the per-frame distance stream; the preview
        // EventChannel carries 5 fps JPEG thumbnails for the pad background.
        val thereminCameraPlugin = ThereminCameraPlugin(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ThereminCameraPlugin.METHOD_CHANNEL
        ).setMethodCallHandler(thereminCameraPlugin)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ThereminCameraPlugin.EVENT_CHANNEL
        ).setStreamHandler(thereminCameraPlugin)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ThereminCameraPlugin.PREVIEW_CHANNEL
        ).setStreamHandler(thereminCameraPlugin.previewStreamHandler())

        channel.setMethodCallHandler { call, result ->
            val am = audioManager!!
            when (call.method) {
                "getAudioInputDevices" -> {
                    val allDevices = am.getDevices(AudioManager.GET_DEVICES_ALL)
                    // Use type allowlist + isSource to exclude the sink side of bidirectional
                    // USB headsets (e.g. CS202 shows as two separate AudioDeviceInfo objects)
                    val inputTypes = setOf(
                        AudioDeviceInfo.TYPE_BUILTIN_MIC,
                        AudioDeviceInfo.TYPE_WIRED_HEADSET,
                        AudioDeviceInfo.TYPE_USB_DEVICE,
                        AudioDeviceInfo.TYPE_USB_HEADSET,
                        AudioDeviceInfo.TYPE_USB_ACCESSORY,
                        AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                        AudioDeviceInfo.TYPE_LINE_ANALOG,
                        AudioDeviceInfo.TYPE_LINE_DIGITAL,
                        AudioDeviceInfo.TYPE_AUX_LINE,
                        AudioDeviceInfo.TYPE_TELEPHONY,
                    )
                    val inputDevices = allDevices.filter { it.type in inputTypes && it.isSource }
                    result.success(enumerateDevices(inputDevices.toTypedArray(), "Input"))
                }
                "getAudioOutputDevices" -> {
                    // GET_DEVICES_OUTPUTS misses wired headsets when a USB audio device (mic)
                    // is active on the same hub. Query all devices and filter to sinks instead.
                    val allDevices = am.getDevices(AudioManager.GET_DEVICES_ALL)
                    val outputDevices = allDevices.filter { it.isSink }
                    result.success(enumerateDevices(outputDevices.toTypedArray(), "Output"))
                }
                "getAudioDeviceDetails" -> {
                    // Returns full AudioDeviceInfo data for every device on the
                    // system — used by the USB audio debug screen to investigate
                    // multi-device routing support.
                    val allDevices = am.getDevices(AudioManager.GET_DEVICES_ALL)
                    result.success(allDevices.map { device ->
                        val typeString = deviceTypeString(device.type)
                        val map = mutableMapOf<String, Any>(
                            "id" to device.id,
                            "productName" to device.productName.toString(),
                            "type" to device.type,
                            "typeString" to typeString,
                            "isSource" to device.isSource,
                            "isSink" to device.isSink,
                            "sampleRates" to device.sampleRates.toList(),
                            "channelCounts" to device.channelCounts.toList(),
                            "channelMasks" to device.channelMasks.toList(),
                            "encodings" to device.encodings.toList(),
                        )
                        // API 28+ fields
                        if (android.os.Build.VERSION.SDK_INT >= 28) {
                            map["address"] = device.address
                        }
                        map
                    })
                }
                "setSystemVolume" -> {
                    // Set the system media volume to a percentage (0-100).
                    // Maps CC 0-127 → 0-100% → 0-maxVolume on STREAM_MUSIC.
                    val pct = call.argument<Int>("percent") ?: 50
                    val maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                    val vol = (pct * maxVol / 100).coerceIn(0, maxVol)
                    am.setStreamVolume(AudioManager.STREAM_MUSIC, vol, 0)
                    result.success(null)
                }
                "getAndroidSdkVersion" -> {
                    result.success(android.os.Build.VERSION.SDK_INT)
                }
                "startBluetoothSco" -> {
                    am.startBluetoothSco()
                    am.isBluetoothScoOn = true
                    result.success(null)
                }
                "stopBluetoothSco" -> {
                    am.stopBluetoothSco()
                    am.isBluetoothScoOn = false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        audioManager?.registerAudioDeviceCallback(deviceCallback, mainHandler)
        requestAudioFocus()
    }

    override fun onPause() {
        super.onPause()
        audioManager?.unregisterAudioDeviceCallback(deviceCallback)
        // Released on pause rather than on destroy: holding focus while
        // backgrounded would keep every other app silenced.
        abandonAudioFocus()
    }

    /// Human-readable label for an [AudioDeviceInfo.type] constant.
    private fun deviceTypeString(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in Mic"
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in Speaker"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Built-in Earpiece"
        AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth SCO"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth A2DP"
        AudioDeviceInfo.TYPE_USB_DEVICE -> "USB Device"
        AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Headset"
        AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB Accessory"
        AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
        AudioDeviceInfo.TYPE_TELEPHONY -> "Telephony"
        AudioDeviceInfo.TYPE_BUS -> "Bus"
        AudioDeviceInfo.TYPE_LINE_ANALOG -> "Line Analog"
        AudioDeviceInfo.TYPE_LINE_DIGITAL -> "Line Digital"
        AudioDeviceInfo.TYPE_AUX_LINE -> "Aux Line"
        AudioDeviceInfo.TYPE_HEARING_AID -> "Hearing Aid"
        AudioDeviceInfo.TYPE_HDMI -> "HDMI"
        AudioDeviceInfo.TYPE_HDMI_ARC -> "HDMI ARC"
        AudioDeviceInfo.TYPE_DOCK -> "Dock"
        else -> "Type $type"
    }

    private fun enumerateDevices(devices: Array<AudioDeviceInfo>, direction: String): List<Map<String, Any>> {
        return devices.map { device ->
            val typeString = deviceTypeString(device.type)
            val displayName = "${device.productName} ($typeString)"

            mapOf(
                "id" to device.id,
                "name" to displayName,
                "type" to device.type,
                "isBluetooth" to (device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP)
            )
        }
    }
}
