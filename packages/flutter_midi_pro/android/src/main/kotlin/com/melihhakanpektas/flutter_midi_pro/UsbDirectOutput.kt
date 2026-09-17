package com.melihhakanpektas.flutter_midi_pro

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * Optional direct USB output: plays GrooveForge through a USB DAC that
 * Android has dropped.
 *
 * Android routes audio to a single USB audio device. With a USB microphone and
 * a USB DAC on the same hub, the one that enumerated last wins and the other
 * disappears from the audio system; a hub's built-in DAC typically loses to a
 * wireless mic receiver, and the phone falls back to its speaker. The DAC is
 * still attached as a USB device, so this class opens it through [UsbManager]
 * and the native streamer (usb_direct_output_android.cpp) sends the audio to it
 * directly.
 *
 * It only engages when all of these hold, and otherwise stays out of the way:
 *  - the user enabled the preference (off by default);
 *  - Android is not already routing to a USB output — if it is, the normal
 *    AAudio path already reaches the DAC and nothing needs replacing;
 *  - an attached device has a USB Audio Class 1 playback interface, and its
 *    format works at the bus sample rate.
 *
 * Once engaged it stays engaged until the device is unplugged, the stream
 * fails, or the preference is turned off. A device that failed, was declined
 * permission, or has no usable format is not retried until it is replugged, so
 * a bad device cannot cause a retry loop.
 *
 * All methods run on the main thread.
 */
class UsbDirectOutput(private val context: Context) {

    /** What the direct output is doing, as reported to Dart. */
    enum class State(val code: String) {
        /** The preference is off. */
        OFF("off"),
        /** Enabled, but no attached device has a USB playback interface. */
        NO_DEVICE("noDevice"),
        /** Enabled, but Android already plays to a USB output. */
        ANDROID_ROUTES("androidRoutes"),
        /** Waiting for the user to answer the USB permission dialog. */
        PERMISSION("permission"),
        /** The user declined USB permission for the device. */
        DENIED("denied"),
        /** Streaming to the DAC. */
        ACTIVE("active"),
        /** The device has no playback format this driver can use. */
        UNSUPPORTED("unsupported"),
        /** Opening or streaming failed. */
        ERROR("error"),
    }

    companion object {
        private const val TAG = "UsbDirectOutput"

        /** Broadcast our own permission PendingIntent delivers. */
        private const val ACTION_USB_PERMISSION =
            "com.melihhakanpektas.flutter_midi_pro.USB_DIRECT_PERMISSION"

        /** How often an engaged stream is checked for having stopped itself. */
        private const val POLL_INTERVAL_MS = 2000L

        /**
         * Settling time after a USB or audio route change before deciding.
         *
         * Plugging a hub enumerates its devices one after another — measured
         * on a Galaxy Z Fold 6, a hub DAC was routed by Android for 630 ms
         * before a wireless mic receiver enumerated and displaced it. Deciding
         * on the first event would see "Android routes USB" and do nothing.
         */
        private const val SETTLE_MS = 1000L

        /** USB Audio streaming interface subclass. */
        private const val AUDIO_SUBCLASS_STREAMING = 2

        /** UAC1 interface protocol; UAC2 interfaces report 0x20. */
        private const val UAC1_PROTOCOL = 0

        /** Result codes of nativeStart, mirrored from usb_direct_output_android.h. */
        private const val NATIVE_OK = 0

        // UAC1 SET_CUR on an endpoint's sampling-frequency control.
        private const val REQ_TYPE_CLASS_ENDPOINT_OUT = 0x22
        private const val REQ_SET_CUR = 0x01
        private const val SAMPLING_FREQ_CONTROL = 0x0100
        private const val CONTROL_TIMEOUT_MS = 1000

        init {
            // Already loaded by FlutterMidiProPlugin; repeated loads are no-ops,
            // and this keeps the class usable on its own.
            System.loadLibrary("native-lib")
        }

        /**
         * Picks the playback format for [sampleRate]. Returns
         * [interfaceNumber, altSetting, endpointAddress, hasFreqControl,
         * channels, bitResolution], or null when none is usable.
         */
        @JvmStatic
        private external fun nativeDescribe(raw: ByteArray, sampleRate: Int): IntArray?

        /** The rate the audio bus renders at. */
        @JvmStatic
        private external fun nativeBusSampleRate(): Int

        /** Starts streaming; returns 0 or a negative UsbDirectResult. */
        @JvmStatic
        private external fun nativeStart(fd: Int, raw: ByteArray, sampleRate: Int): Int

        /** Stops streaming and hands the bus back to AAudio. */
        @JvmStatic
        private external fun nativeStop()

        /** False once the stream stopped, including by itself. */
        @JvmStatic
        private external fun nativeIsRunning(): Boolean
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())

    private var enabled = false
    private var state = State.OFF

    /** Label of the device the current state is about, for the UI. */
    private var deviceLabel: String? = null

    // ── Engaged device ──────────────────────────────────────────────────────
    private var connection: UsbDeviceConnection? = null
    private var activeDevice: UsbDevice? = null
    private var streamingInterface: UsbInterface? = null
    private var idleInterface: UsbInterface? = null
    private var sampleRate = 0
    private var channels = 0
    private var bitResolution = 0

    /** Device names not to retry until they are unplugged. */
    private val rejectedDevices = mutableSetOf<String>()

    /** Device name whose permission dialog is showing, if any. */
    private var permissionPendingFor: String? = null

    private var listening = false

    // ── Public API ──────────────────────────────────────────────────────────

    /** Turns the direct output on or off. Off releases the DAC immediately. */
    fun setEnabled(on: Boolean) {
        if (on == enabled) return
        enabled = on
        Log.i(TAG, "Direct USB output ${if (on) "enabled" else "disabled"}")

        if (on) {
            startListening()
            evaluate()
            return
        }

        release()
        stopListening()
        rejectedDevices.clear()
        permissionPendingFor = null
        setState(State.OFF, null)
    }

    /** Current status for the preferences screen. */
    fun status(): Map<String, Any?> = mapOf(
        "state" to state.code,
        "device" to deviceLabel,
        "sampleRate" to sampleRate,
        "channels" to channels,
        "bits" to bitResolution,
    )

    /** Releases everything; call when the plugin detaches. */
    fun dispose() = setEnabled(false)

    // ── Decision ────────────────────────────────────────────────────────────

    /**
     * Decides whether to engage, stay engaged, or wait. Called on every USB,
     * audio-route and permission event, and periodically while enabled.
     */
    private fun evaluate() {
        if (!enabled) return

        if (connection != null) {
            checkEngagedStream()
            return
        }
        if (permissionPendingFor != null) return

        // Android already reaches a USB DAC: the normal path is the better one.
        if (androidRoutesUsbOutput()) {
            setState(State.ANDROID_ROUTES, null)
            return
        }

        val device = findCandidate()
        if (device == null) {
            // Keep reporting why a still-attached device was set aside;
            // otherwise there is simply nothing to play to.
            if (!rejectedDeviceAttached()) setState(State.NO_DEVICE, null)
            return
        }

        if (!usbManager.hasPermission(device)) {
            requestPermission(device)
            return
        }
        engage(device)
    }

    /** Notices a stream that stopped by itself (unplug, transfer failure). */
    private fun checkEngagedStream() {
        if (nativeIsRunning()) return
        val name = activeDevice?.deviceName
        Log.w(TAG, "The direct USB stream stopped by itself")
        release()
        if (name != null) rejectedDevices.add(name)
        setState(State.ERROR, deviceLabel)
    }

    /** Whether Android currently has a USB output it can play to. */
    private fun androidRoutesUsbOutput(): Boolean =
        audioManager.getDevices(AudioManager.GET_DEVICES_ALL).any {
            it.isSink && (it.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                it.type == AudioDeviceInfo.TYPE_USB_HEADSET)
        }

    /** First attached device with a UAC1 playback interface not set aside. */
    private fun findCandidate(): UsbDevice? =
        usbManager.deviceList.values.firstOrNull {
            it.deviceName !in rejectedDevices && hasUac1Playback(it)
        }

    private fun rejectedDeviceAttached(): Boolean =
        usbManager.deviceList.keys.any { it in rejectedDevices }

    /**
     * Whether [device] exposes a USB Audio Class 1 streaming interface with an
     * isochronous OUT endpoint — i.e. something that plays audio. Readable
     * without permission, so no dialog is shown for microphones or keyboards.
     */
    private fun hasUac1Playback(device: UsbDevice): Boolean {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.interfaceClass != UsbConstants.USB_CLASS_AUDIO) continue
            if (intf.interfaceSubclass != AUDIO_SUBCLASS_STREAMING) continue
            if (intf.interfaceProtocol != UAC1_PROTOCOL) continue
            if (hasIsoOutEndpoint(intf)) return true
        }
        return false
    }

    private fun hasIsoOutEndpoint(intf: UsbInterface): Boolean {
        for (e in 0 until intf.endpointCount) {
            val ep = intf.getEndpoint(e)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_ISOC &&
                ep.direction == UsbConstants.USB_DIR_OUT
            ) return true
        }
        return false
    }

    // ── Permission ──────────────────────────────────────────────────────────

    private fun requestPermission(device: UsbDevice) {
        permissionPendingFor = device.deviceName
        setState(State.PERMISSION, labelOf(device))

        // Explicit (package-scoped) and mutable: UsbManager adds the device and
        // the grant as extras, which an immutable PendingIntent would drop.
        val intent = Intent(ACTION_USB_PERMISSION).setPackage(context.packageName)
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val pending = PendingIntent.getBroadcast(context, 0, intent, flags)
        usbManager.requestPermission(device, pending)
    }

    private fun onPermissionResult(intent: Intent) {
        val device = usbDeviceExtra(intent) ?: return
        permissionPendingFor = null
        val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
        if (!granted) {
            Log.i(TAG, "USB permission declined for ${device.deviceName}")
            rejectedDevices.add(device.deviceName)
            setState(State.DENIED, labelOf(device))
            return
        }
        evaluate()
    }

    // ── Engage / release ────────────────────────────────────────────────────

    /** Opens [device], prepares its playback interface and starts streaming. */
    private fun engage(device: UsbDevice) {
        val label = labelOf(device)
        val conn = usbManager.openDevice(device)
        val raw = conn?.rawDescriptors
        if (conn == null || raw == null) {
            conn?.close()
            reject(device, State.ERROR, "could not open the device")
            return
        }

        // Only the bus rate is acceptable: every instrument was built at it.
        val rate = nativeBusSampleRate()
        val format = nativeDescribe(raw, rate)
        if (format == null) {
            conn.close()
            reject(device, State.UNSUPPORTED, "no UAC1 playback format at $rate Hz")
            return
        }

        val interfaceNumber = format[0]
        val streaming = findInterface(device, interfaceNumber, format[1])
        val idle = findInterface(device, interfaceNumber, 0)
        if (streaming == null || !prepareInterface(conn, streaming, format, rate)) {
            conn.close()
            reject(device, State.ERROR, "could not prepare the playback interface")
            return
        }

        val result = nativeStart(conn.fileDescriptor, raw, rate)
        if (result != NATIVE_OK) {
            idle?.let { conn.setInterface(it) }
            conn.releaseInterface(streaming)
            conn.close()
            reject(device, State.ERROR, "the stream did not start ($result)")
            return
        }

        connection = conn
        activeDevice = device
        streamingInterface = streaming
        idleInterface = idle
        sampleRate = rate
        channels = format[4]
        bitResolution = format[5]
        setState(State.ACTIVE, label)
        Log.i(TAG, "Streaming to $label at $rate Hz, ${channels}ch, $bitResolution-bit")
    }

    /**
     * Claims the playback interface from the kernel's USB audio driver, selects
     * the streaming alternate and sets the sample rate on the endpoint.
     *
     * Claiming with force detaches the kernel driver, which removes the
     * device's ALSA card. That is harmless here: Android had already stopped
     * using it, which is the only reason this class got this far.
     */
    private fun prepareInterface(
        conn: UsbDeviceConnection,
        streaming: UsbInterface,
        format: IntArray,
        rate: Int,
    ): Boolean {
        if (!conn.claimInterface(streaming, true)) return false
        if (!conn.setInterface(streaming)) {
            conn.releaseInterface(streaming)
            return false
        }

        val hasFreqControl = format[3] == 1
        if (!hasFreqControl) return true

        // UAC1 §5.2.3.2.3.1: the rate as three little-endian bytes.
        val data = byteArrayOf(
            (rate and 0xFF).toByte(),
            ((rate shr 8) and 0xFF).toByte(),
            ((rate shr 16) and 0xFF).toByte(),
        )
        val sent = conn.controlTransfer(
            REQ_TYPE_CLASS_ENDPOINT_OUT, REQ_SET_CUR, SAMPLING_FREQ_CONTROL,
            format[2], data, data.size, CONTROL_TIMEOUT_MS,
        )
        // Single-rate devices often stall this request; the rate they play
        // at is the one they listed, so it is not a reason to give up.
        if (sent < 0) Log.w(TAG, "Setting the sample rate was refused; continuing")
        return true
    }

    /** Stops streaming and gives the interface back. Safe when not engaged. */
    private fun release() {
        val conn = connection ?: return
        nativeStop()
        // Alternate 0 has no endpoint: the device stops expecting audio.
        idleInterface?.let { conn.setInterface(it) }
        streamingInterface?.let { conn.releaseInterface(it) }
        conn.close()

        connection = null
        activeDevice = null
        streamingInterface = null
        idleInterface = null
        Log.i(TAG, "USB DAC released")
    }

    private fun reject(device: UsbDevice, newState: State, reason: String) {
        Log.w(TAG, "Not using ${device.deviceName}: $reason")
        rejectedDevices.add(device.deviceName)
        setState(newState, labelOf(device))
    }

    private fun findInterface(device: UsbDevice, number: Int, alt: Int): UsbInterface? {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            if (intf.id == number && intf.alternateSetting == alt) return intf
        }
        return null
    }

    // ── Events ──────────────────────────────────────────────────────────────

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                ACTION_USB_PERMISSION -> onPermissionResult(intent)
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> scheduleEvaluate()
                UsbManager.ACTION_USB_DEVICE_DETACHED -> onDetached(intent)
            }
        }
    }

    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) = scheduleEvaluate()
        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) = scheduleEvaluate()
    }

    private val evaluateRunnable = Runnable { evaluate() }

    private val pollRunnable = object : Runnable {
        override fun run() {
            if (!enabled) return
            evaluate()
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    /** Evaluates once events have stopped arriving for [SETTLE_MS]. */
    private fun scheduleEvaluate() {
        handler.removeCallbacks(evaluateRunnable)
        handler.postDelayed(evaluateRunnable, SETTLE_MS)
    }

    private fun onDetached(intent: Intent) {
        val device = usbDeviceExtra(intent) ?: return
        rejectedDevices.remove(device.deviceName)
        if (permissionPendingFor == device.deviceName) permissionPendingFor = null
        if (activeDevice?.deviceName == device.deviceName) {
            Log.i(TAG, "USB DAC unplugged")
            release()
            setState(State.NO_DEVICE, null)
        }
        scheduleEvaluate()
    }

    private fun startListening() {
        if (listening) return
        listening = true

        val filter = IntentFilter().apply {
            addAction(ACTION_USB_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        // Not exported: USB attach/detach come from the system and the
        // permission result from our own PendingIntent, both still delivered.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(usbReceiver, filter)
        }
        audioManager.registerAudioDeviceCallback(audioDeviceCallback, handler)
        handler.postDelayed(pollRunnable, POLL_INTERVAL_MS)
    }

    private fun stopListening() {
        if (!listening) return
        listening = false
        context.unregisterReceiver(usbReceiver)
        audioManager.unregisterAudioDeviceCallback(audioDeviceCallback)
        handler.removeCallbacks(pollRunnable)
        handler.removeCallbacks(evaluateRunnable)
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private fun setState(newState: State, label: String?) {
        if (newState != state) Log.i(TAG, "State: ${state.code} -> ${newState.code}")
        state = newState
        deviceLabel = label
    }

    /** Product name when readable, otherwise the USB vendor and product IDs. */
    private fun labelOf(device: UsbDevice): String {
        val name = try {
            device.productName
        } catch (e: SecurityException) {
            null
        }
        if (!name.isNullOrBlank()) return name
        return String.format("USB %04X:%04X", device.vendorId, device.productId)
    }

    @Suppress("DEPRECATION")
    private fun usbDeviceExtra(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
}
