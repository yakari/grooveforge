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
 * **Autofocus mode** (default for AF-capable cameras):
 *   Reads TotalCaptureResult.LENS_FOCUS_DISTANCE (in diopters) from every
 *   completed frame capture, normalizes by LENS_INFO_MINIMUM_FOCUS_DISTANCE,
 *   and emits the result to Flutter via the main EventChannel.
 *
 * **Contrast mode** (automatic fallback for fixed-focus cameras / webcams):
 *   Computes the mean luminance of the center 50% of each YUV frame, applies
 *   a 60-frame rolling min/max normalization, then emits the normalized value.
 *   This technique works on any camera regardless of AF capability.
 *
 * Threading:
 *   Camera2 callbacks run on [cameraHandler] (background HandlerThread).
 *   EventSink emissions are always posted to the main thread, as required
 *   by the Flutter EventChannel API.
 */
class ThereminCameraPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val TAG = "ThereminCamera"

        /** MethodChannel name for start / stop / isSupported calls. */
        const val METHOD_CHANNEL = "com.grooveforge/theremin_camera"

        /** EventChannel name for the streaming normalized distance values. */
        const val EVENT_CHANNEL = "com.grooveforge/theremin_camera_events"

        /** EventChannel name for the 5 fps grayscale JPEG preview thumbnails. */
        const val PREVIEW_CHANNEL = "com.grooveforge/theremin_camera_preview"
    }

    // ─── EventChannel sinks ───────────────────────────────────────────────────

    /** Receives normalized distance values and forwards them to Dart. */
    private var eventSink: EventChannel.EventSink? = null

    /** Receives JPEG preview thumbnails for the pad background overlay. */
    private var previewSink: EventChannel.EventSink? = null

    /** Posts events to the main thread to satisfy Flutter EventChannel requirements. */
    private val mainHandler = Handler(Looper.getMainLooper())

    // ─── Camera2 session objects ──────────────────────────────────────────────

    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null

    /**
     * ImageReader providing the YUV frame stream.
     *
     * In AF mode: pixel data is discarded; only CaptureResult metadata is used.
     * In contrast mode: Y-plane luminance is sampled from each frame.
     */
    private var imageReader: ImageReader? = null

    /** Background thread that runs Camera2 callbacks. */
    private var cameraThread: android.os.HandlerThread? = null
    private var cameraHandler: Handler? = null

    /**
     * Maximum diopter value reported by this device (closest focus point).
     *
     * Used in AF mode to normalize LENS_FOCUS_DISTANCE to [0, 1].
     * Zero on fixed-focus cameras, which triggers [useContrastMode].
     */
    private var minFocusDist: Float = 0f

    /**
     * True when the camera does not support autofocus.
     *
     * In this mode the plugin analyses per-frame luminance instead of reading
     * LENS_FOCUS_DISTANCE. Works on any camera — fixed-focus webcams, older
     * Android devices, etc.
     */
    private var useContrastMode = false

    // ─── Contrast-mode state ──────────────────────────────────────────────────

    /**
     * Rolling history of mean luma values for min/max normalization.
     *
     * 30 frames ≈ 1 s at 30 fps — half the original window so the plugin
     * adapts to changing ambient lighting twice as quickly without sacrificing
     * normalization stability.
     */
    private val lumaHistory = ArrayDeque<Double>()

    /**
     * Pre-allocated pixel buffer for the 120×90 preview thumbnail.
     *
     * Reusing this array across frames avoids an IntArray(10 800) allocation
     * on every call to [sendPreviewFrame], reducing GC pressure.
     */
    private val previewPixels = IntArray(120 * 90)

    /**
     * Clockwise degrees the sensor image must be rotated so it appears upright
     * when the device is in portrait orientation.
     *
     * Read from [CameraCharacteristics.SENSOR_ORIENTATION] once at camera-open
     * time. For front cameras this is typically 270°; for back cameras 90°.
     * Applied when building the JPEG preview thumbnail.
     */
    private var sensorOrientation: Int = 0

    /** Frame counter used to throttle the preview thumbnail to ≈ 10 fps. */
    private var frameCount = 0

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

    // ─── EventChannel.StreamHandler (distance stream) ─────────────────────────

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ─── Preview stream handler ───────────────────────────────────────────────

    /** StreamHandler for the camera preview EventChannel. */
    inner class PreviewStreamHandler : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
            previewSink = sink
        }
        override fun onCancel(arguments: Any?) {
            previewSink = null
        }
    }

    /** Returns the [PreviewStreamHandler] to register on the preview EventChannel. */
    fun previewStreamHandler(): PreviewStreamHandler = PreviewStreamHandler()

    // ─── Permission check ─────────────────────────────────────────────────────

    private fun hasCameraPermission(): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED

    // ─── Camera lifecycle ─────────────────────────────────────────────────────

    /**
     * Opens the front-facing camera and starts a capture session.
     *
     * If the camera supports autofocus, uses AF + LENS_FOCUS_DISTANCE.
     * If the camera is fixed-focus (minFocusDist ≤ 0), falls back to
     * brightness/contrast analysis of the YUV frames — no error is returned.
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

        // LENS_INFO_MINIMUM_FOCUS_DISTANCE = max diopters at the device's closest
        // focus distance. 0 means fixed-focus (infinity only) — fall back to
        // contrast mode rather than returning an error.
        minFocusDist = chars.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE) ?: 0f
        useContrastMode = (minFocusDist <= 0f)

        // SENSOR_ORIENTATION: degrees the raw sensor image is rotated clockwise
        // relative to the device's natural (portrait) orientation.
        // Stored so sendPreviewFrame can rotate thumbnails correctly.
        sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0

        if (useContrastMode) {
            Log.i(TAG, "Fixed-focus camera detected; using contrast mode.")
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
     * Creates a CameraCaptureSession with an ImageReader surface that handles
     * both AF-mode (discard pixels, use CaptureResult) and contrast-mode
     * (read Y-plane luminance for hand detection).
     */
    private fun createCaptureSession(camera: CameraDevice, handler: Handler) {
        val reader = ImageReader.newInstance(320, 240, ImageFormat.YUV_420_888, 2)
        reader.setOnImageAvailableListener({ r ->
            val img = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                if (useContrastMode) {
                    // Contrast mode: emit the raw normalized luma directly.
                    // EMA smoothing is applied once on the Dart side
                    // (ThereminDistanceService._smooth) — no double-smoothing.
                    val value = computeNormalizedLuma(img)
                    mainHandler.post { eventSink?.success(value) }
                }
                // Preview thumbnail: send a JPEG at ≈ 10 fps regardless of mode.
                frameCount++
                if (frameCount % 3 == 0) sendPreviewFrame(img)
            } finally {
                // Always release the image to prevent camera buffer starvation.
                img.close()
            }
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
     *
     * In contrast mode the CaptureCallback emits nothing — the ImageReader
     * listener handles all distance events instead.
     */
    private fun startRepeatingRequest(session: CameraCaptureSession, handler: Handler) {
        val requestBuilder = session.device
            .createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
            .apply {
                addTarget(imageReader!!.surface)
                // Continuous AF: the lens actively tracks the nearest subject
                // (the player's hand) and updates LENS_FOCUS_DISTANCE each frame.
                // In contrast mode this is a no-op but causes no harm.
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
                    // AF mode only: read the physical lens position from metadata.
                    // In contrast mode, the ImageReader listener does the work.
                    if (useContrastMode) return

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

    // ─── Contrast analysis ────────────────────────────────────────────────────

    /**
     * Computes the mean luminance of the center 50% of [image] using the Y
     * plane of its YUV_420_888 pixel format, then normalizes via a rolling
     * 60-frame min/max window so the value adapts to ambient lighting.
     *
     * Sampling only the center region focuses attention on the player's hand
     * while ignoring bright/dark backgrounds at the frame edges.
     */
    private fun computeNormalizedLuma(image: android.media.Image): Double {
        val yPlane  = image.planes[0]
        val yBuffer = yPlane.buffer
        val yStride = yPlane.rowStride
        val w = image.width
        val h = image.height
        // Sample only the center 50% region to focus on the player's hand.
        val x0 = w / 4; val x1 = w * 3 / 4
        val y0 = h / 4; val y1 = h * 3 / 4
        var sum = 0L; var count = 0
        for (row in y0 until y1) {
            for (col in x0 until x1) {
                sum += (yBuffer.get(row * yStride + col).toInt() and 0xFF).toLong()
                count++
            }
        }
        val mean = if (count > 0) sum.toDouble() / count / 255.0 else 0.0
        // Rolling min/max normalization over ≈ 1 s window (30 frames).
        if (lumaHistory.size >= 30) lumaHistory.removeFirst()
        lumaHistory.addLast(mean)
        val minL = lumaHistory.minOrNull() ?: 0.0
        val maxL = lumaHistory.maxOrNull() ?: 1.0
        val range = maxL - minL
        return if (range < 0.02) 0.0 else ((mean - minL) / range).coerceIn(0.0, 1.0)
    }

    // ─── Preview thumbnail ────────────────────────────────────────────────────

    /**
     * Downscales [image] to a 120×90 grayscale JPEG, corrects orientation,
     * and horizontally mirrors it (front-camera selfie effect), then sends it
     * to the preview EventChannel.
     *
     * Called every 3rd frame (≈ 10 fps at 30 fps) for a smoother live feel.
     *
     * Optimisations vs. the previous implementation:
     *   - [previewPixels] is pre-allocated once as a class field to avoid a
     *     10 800-element IntArray allocation on every call.
     *   - Rotation and horizontal mirror are combined into a single [Matrix]
     *     pass so only one extra [Bitmap] is ever created per preview frame.
     */
    private fun sendPreviewFrame(image: android.media.Image) {
        try {
            val yPlane  = image.planes[0]
            val yBuffer = yPlane.buffer.duplicate()
            val yStride = yPlane.rowStride
            val srcW = image.width; val srcH = image.height
            val dstW = 120; val dstH = 90

            // ── Downsample Y-plane to 120×90 grayscale ──────────────────────
            // Reuse the pre-allocated pixel buffer to avoid per-frame GC pressure.
            for (row in 0 until dstH) {
                val srcRow = row * srcH / dstH
                for (col in 0 until dstW) {
                    val y = yBuffer.get(srcRow * yStride + col * srcW / dstW).toInt() and 0xFF
                    previewPixels[row * dstW + col] = (0xFF shl 24) or (y shl 16) or (y shl 8) or y
                }
            }
            val raw = android.graphics.Bitmap.createBitmap(
                previewPixels, dstW, dstH, android.graphics.Bitmap.Config.ARGB_8888)

            // ── Compute display-adjusted rotation ───────────────────────────
            // sensorOrientation: CW degrees the raw frame needs to appear upright
            //   in portrait (typically 270° for front cameras).
            // displayRotation: current CCW rotation of the display from portrait.
            // Combined formula for front cameras: (sensor + display) % 360.
            @Suppress("DEPRECATION") // defaultDisplay deprecated at API 30; still correct here
            val displayRotation =
                (context.getSystemService(android.content.Context.WINDOW_SERVICE)
                    as android.view.WindowManager).defaultDisplay.rotation * 90
            val rotateDeg = (sensorOrientation + displayRotation) % 360

            // ── Single-pass: rotation + horizontal mirror ────────────────────
            // Combining both transforms into one Matrix avoids an intermediate
            // Bitmap allocation.  The horizontal flip uses the source bitmap
            // centre as the pivot (dstW/2, dstH/2) so the image stays centred.
            val matrix = android.graphics.Matrix().apply {
                if (rotateDeg != 0) postRotate(rotateDeg.toFloat())
                // Mirror: flip around the vertical axis at the source centre.
                // Front cameras should show a "selfie" mirror image.
                postScale(-1f, 1f, dstW / 2f, dstH / 2f)
            }
            val bmp = android.graphics.Bitmap.createBitmap(raw, 0, 0, dstW, dstH, matrix, false)
            raw.recycle()

            val out = java.io.ByteArrayOutputStream()
            bmp.compress(android.graphics.Bitmap.CompressFormat.JPEG, 60, out)
            bmp.recycle()
            mainHandler.post { previewSink?.success(out.toByteArray()) }
        } catch (_: Exception) { /* ignore preview errors — never crash the audio path */ }
    }

    // ─── Camera teardown ──────────────────────────────────────────────────────

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
        frameCount = 0
    }
}
