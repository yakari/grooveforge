package com.grooveforge.grooveforge

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.media.ImageReader
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * ThereminCameraPlugin — Android side of the theremin focal-distance channel.
 *
 * Uses the Camera2 API to stream the front camera's current focus distance
 * as a normalized [Double] in [0.0, 1.0]:
 *   0.0 = hand far from camera (or no hand) → low pitch
 *   1.0 = hand as close as the lens can focus  → high pitch
 *
 * Technique:
 *   1. Opens the front-facing camera with CONTROL_AF_MODE_CONTINUOUS_PICTURE
 *      so the lens actively tracks the nearest subject (the hand).
 *   2. Reads TotalCaptureResult.LENS_FOCUS_DISTANCE (in diopters) from every
 *      completed frame capture.
 *   3. Normalizes by LENS_INFO_MINIMUM_FOCUS_DISTANCE (= maximum diopter
 *      value = closest focus). Result: closer hand → higher normalized value.
 *   4. Emits each value to Flutter via EventChannel.
 *
 * Threading:
 *   Camera2 callbacks run on [cameraHandler] (background HandlerThread).
 *   EventSink emissions are always posted to the main thread, as required
 *   by the Flutter EventChannel API.
 *
 * Limitations:
 *   - Requires CAMERA permission and a front-facing autofocus camera.
 *   - Returns FIXED_FOCUS error on devices without AF (minFocusDist == 0).
 *   - Focus distance changes lag behind actual hand position by ~100–400 ms
 *     depending on the device's AF speed. Dart-side EMA smoothing reduces
 *     jitter further.
 */
class ThereminCameraPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "ThereminCamera"

        /** MethodChannel name for start / stop / isSupported calls. */
        const val METHOD_CHANNEL = "com.grooveforge/theremin_camera"

        /** EventChannel name for the streaming normalized distance values. */
        const val EVENT_CHANNEL = "com.grooveforge/theremin_camera_events"
    }

    // ─── EventChannel sink (set by Flutter runtime on subscription) ───────────

    /** Receives normalized distance values and forwards them to Dart. */
    private var eventSink: EventChannel.EventSink? = null

    /** Posts events to the main thread to satisfy Flutter EventChannel requirements. */
    private val mainHandler = Handler(Looper.getMainLooper())

    // ─── Camera2 session objects ──────────────────────────────────────────────

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null

    /**
     * Minimal ImageReader used as the required Camera2 output surface.
     *
     * Camera2 mandates at least one output surface per capture session.
     * We use a tiny 320×240 YUV reader and immediately discard each image —
     * only the CaptureResult metadata (LENS_FOCUS_DISTANCE) matters here.
     */
    private var imageReader: ImageReader? = null

    /** Background thread that runs Camera2 callbacks. */
    private var cameraThread: android.os.HandlerThread? = null
    private var cameraHandler: Handler? = null

    /**
     * Maximum diopter value reported by this device = at its closest focus.
     *
     * Used to normalize LENS_FOCUS_DISTANCE to [0, 1].
     * LENS_FOCUS_DISTANCE (diopters) / minFocusDist → 0 (far) … 1 (close).
     */
    private var minFocusDist: Float = 0f

    // ─── MethodChannel.MethodCallHandler ──────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> startCamera(result)
            "stop" -> {
                stopCamera()
                result.success(null)
            }
            "isSupported" -> result.success(hasCameraPermission())
            else -> result.notImplemented()
        }
    }

    // ─── EventChannel.StreamHandler ───────────────────────────────────────────

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ─── Permission check ─────────────────────────────────────────────────────

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED

    // ─── Camera lifecycle ─────────────────────────────────────────────────────

    /**
     * Opens the front-facing camera and starts a continuous AF repeating
     * capture request. Calls [result.success] once the session is running,
     * or [result.error] if anything fails.
     */
    private fun startCamera(result: MethodChannel.Result) {
        if (!hasCameraPermission()) {
            result.error("NO_PERMISSION", "Camera permission not granted", null)
            return
        }

        // Camera2 callbacks need their own background thread to avoid blocking UI.
        val thread = android.os.HandlerThread("ThereminCameraThread").also { it.start() }
        cameraThread = thread
        val handler = Handler(thread.looper)
        cameraHandler = handler

        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

        // Front-facing camera: faces the user, who holds their hand in front of
        // it — exactly the theremin geometry.
        val frontId = manager.cameraIdList.firstOrNull { id ->
            manager.getCameraCharacteristics(id)
                .get(CameraCharacteristics.LENS_FACING) ==
                    CameraCharacteristics.LENS_FACING_FRONT
        }

        if (frontId == null) {
            result.error("NO_CAMERA", "No front-facing camera found", null)
            return
        }

        val chars = manager.getCameraCharacteristics(frontId)

        // LENS_INFO_MINIMUM_FOCUS_DISTANCE = max diopters at the device's
        // closest focus distance. 0 means fixed-focus (infinity only).
        minFocusDist = chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
        if (minFocusDist <= 0f) {
            result.error(
                "FIXED_FOCUS",
                "Front camera is fixed-focus; focal distance not available",
                null
            )
            return
        }

        try {
            @Suppress("MissingPermission") // already checked above
            manager.openCamera(frontId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    createCaptureSession(camera, handler)
                    // Report success to Dart now that the device is open; the
                    // session setup is asynchronous but the user can expect
                    // distance events to start flowing within ~200 ms.
                    result.success(null)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    cameraDevice = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    cameraDevice = null
                    Log.e(TAG, "CameraDevice error: $error")
                }
            }, handler)
        } catch (e: SecurityException) {
            result.error("SECURITY", e.message, null)
        }
    }

    /**
     * Creates a CameraCaptureSession with a dummy ImageReader surface and
     * starts a repeating request that drives continuous autofocus.
     */
    private fun createCaptureSession(camera: CameraDevice, handler: Handler) {
        // Smallest viable resolution to minimise memory bandwidth; we never
        // look at the pixel data, only at the CaptureResult metadata.
        val reader = ImageReader.newInstance(320, 240, ImageFormat.YUV_420_888, 2)
        reader.setOnImageAvailableListener({ r ->
            // Discard every image immediately — we only need CaptureResult.
            r.acquireLatestImage()?.close()
        }, handler)
        imageReader = reader

        camera.createCaptureSession(
            listOf(reader.surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    captureSession = session
                    startRepeatingRequest(session, handler)
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    Log.e(TAG, "CaptureSession configuration failed")
                }
            },
            handler
        )
    }

    /**
     * Starts a repeating capture request with continuous AF and registers a
     * [CameraCaptureSession.CaptureCallback] that reads LENS_FOCUS_DISTANCE
     * from every TotalCaptureResult and emits the normalized value to Dart.
     */
    private fun startRepeatingRequest(session: CameraCaptureSession, handler: Handler) {
        val requestBuilder = session.device
            .createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            .apply {
                addTarget(imageReader!!.surface)
                // Continuous AF: the lens actively tracks the nearest subject
                // (the player's hand) and updates LENS_FOCUS_DISTANCE each frame.
                set(
                    CaptureRequest.CONTROL_AF_MODE,
                    CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE
                )
                set(
                    CaptureRequest.CONTROL_AE_MODE,
                    CaptureRequest.CONTROL_AE_MODE_ON
                )
            }

        session.setRepeatingRequest(
            requestBuilder.build(),
            object : CameraCaptureSession.CaptureCallback() {
                override fun onCaptureCompleted(
                    s: CameraCaptureSession,
                    r: CaptureRequest,
                    result: TotalCaptureResult,
                ) {
                    // LENS_FOCUS_DISTANCE: actual current focus distance in
                    // diopters (D = 1/meters). Higher diopters = closer object.
                    val focusDist = result.get(CaptureResult.LENS_FOCUS_DISTANCE) ?: return

                    // Normalize to [0.0, 1.0]: 0 = far (low diopters), 1 = close.
                    val normalized = (focusDist / minFocusDist).coerceIn(0f, 1f).toDouble()

                    // EventSink must be called on the main thread.
                    mainHandler.post { eventSink?.success(normalized) }
                }
            },
            handler
        )
    }

    /**
     * Releases all Camera2 resources and shuts down the background thread.
     *
     * Safe to call multiple times or when nothing is open.
     */
    private fun stopCamera() {
        captureSession?.close(); captureSession = null
        cameraDevice?.close();   cameraDevice = null
        imageReader?.close();    imageReader = null
        cameraThread?.quitSafely(); cameraThread = null
        cameraHandler = null
    }
}
