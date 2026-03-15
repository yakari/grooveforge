package com.grooveforge.grooveforge

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
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
    }

    override fun onPause() {
        super.onPause()
        audioManager?.unregisterAudioDeviceCallback(deviceCallback)
    }

    private fun enumerateDevices(devices: Array<AudioDeviceInfo>, direction: String): List<Map<String, Any>> {
        return devices.map { device ->
            val typeString = when (device.type) {
                AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Built-in Mic"
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Built-in Speaker"
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
                else -> "Type ${device.type}"
            }
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
