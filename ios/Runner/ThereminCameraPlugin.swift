import AVFoundation
import Flutter

/**
 * ThereminCameraPlugin — iOS side of the theremin focal-distance channel.
 *
 * Uses AVFoundation to stream the front camera's current lens position as a
 * normalized Double in [0.0, 1.0]:
 *   0.0 = hand far from camera (or no hand) → low pitch
 *   1.0 = hand at minimum focus distance    → high pitch
 *
 * **Autofocus mode** (default for AF-capable cameras):
 *   Reads AVCaptureDevice.lensPosition — already normalized to [0, 1] by iOS,
 *   where 0 = infinity and 1 = minimum focus distance.
 *
 * **Contrast mode** (automatic fallback for fixed-focus cameras):
 *   Computes the mean luminance of the center 50% of each YCbCr frame, applies
 *   a 60-frame rolling min/max normalization, then emits the normalized value.
 *   This works on any camera regardless of AF capability.
 *
 * An additional preview EventChannel emits 120×90 JPEG thumbnails at ≈ 5 fps
 * so the Dart UI can show a live semi-transparent camera feed.
 *
 * Limitations:
 *   - Requires NSCameraUsageDescription in Info.plist and user permission.
 *   - AF latency varies by device (iPhone 15: ~100 ms; older models: ~300 ms).
 */
class ThereminCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // ─── Channel names ────────────────────────────────────────────────────────

    static let methodChannelName = "com.grooveforge/theremin_camera"
    static let eventChannelName  = "com.grooveforge/theremin_camera_events"
    static let previewChannelName = "com.grooveforge/theremin_camera_preview"

    // ─── State ────────────────────────────────────────────────────────────────

    /** Delivers distance values to Dart; set by Flutter on EventChannel.listen. */
    private var eventSink: FlutterEventSink?

    /** Delivers JPEG preview thumbnails to Dart. */
    // fileprivate so PreviewStreamHandler (same file, different class) can write it.
    fileprivate var previewSink: FlutterEventSink?

    private var captureSession: AVCaptureSession?

    /** The active camera device; we read its lensPosition in AF mode each frame. */
    private var captureDevice: AVCaptureDevice?

    /** Serial queue for all Camera session / delegate calls. */
    private let captureQueue = DispatchQueue(
        label: "com.grooveforge.theremin.camera",
        qos: .userInteractive
    )

    // ─── Contrast-mode state ──────────────────────────────────────────────────

    /** True when the camera does not support continuousAutoFocus. */
    private var useContrastMode = false

    /**
     * Rolling luma history for min/max normalization (30 frames ≈ 1 s at 30 fps).
     * Halved from 60 so the plugin adapts to ambient lighting changes faster.
     */
    private var lumaHistory: [Double] = []

    /**
     * Shared CIContext for all preview-frame renders.
     *
     * Creating a CIContext is expensive (allocates a Metal/OpenGL pipeline).
     * Reusing a single instance avoids a large per-frame allocation that was
     * previously the dominant cost of sendPreviewFrame.
     */
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /** Frame counter for throttling preview to ≈ 10 fps. */
    private var frameCount = 0

    // ─── FlutterPlugin ────────────────────────────────────────────────────────

    static func register(with registrar: FlutterPluginRegistrar) {
        // On iOS, messenger() is a method; on macOS it is a property.
        // This file is compiled only for iOS — see macos/Runner/ for the macOS copy.
        let messenger: FlutterBinaryMessenger = registrar.messenger()

        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: messenger
        )
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: messenger
        )
        let previewChannel = FlutterEventChannel(
            name: previewChannelName,
            binaryMessenger: messenger
        )

        let instance = ThereminCameraPlugin()
        methodChannel.setMethodCallHandler(instance.handle(_:result:))
        eventChannel.setStreamHandler(instance)
        let previewHandler = PreviewStreamHandler(plugin: instance)
        previewChannel.setStreamHandler(previewHandler)
    }

    // ─── Method calls ─────────────────────────────────────────────────────────

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startCapture(result: result)
        case "stop":
            stopCapture()
            result(nil)
        case "isSupported":
            // iOS always supports this code path; AF support is checked
            // in startCapture, with graceful fallback to contrast mode.
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ─── FlutterStreamHandler (distance channel) ──────────────────────────────

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // ─── Capture session ──────────────────────────────────────────────────────

    /**
     * Configures and starts an AVCaptureSession with the front camera.
     *
     * If the camera supports continuousAutoFocus, enables AF and uses
     * lensPosition for distance. Otherwise falls back to contrast mode.
     * Calls result(nil) once the session is running; never returns a
     * FIXED_FOCUS error — that case is handled transparently.
     */
    private func startCapture(result: @escaping FlutterResult) {
        // Front-facing camera: faces the user, whose hand is in the same
        // plane — exactly the theremin geometry.
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) else {
            result(FlutterError(
                code: "NO_CAMERA",
                message: "No front-facing camera found",
                details: nil
            ))
            return
        }

        // Decide AF vs. contrast mode based on what this camera supports.
        if !device.isFocusModeSupported(.continuousAutoFocus) {
            // Fixed-focus camera: fall back to brightness/contrast analysis.
            useContrastMode = true
        } else {
            useContrastMode = false
            do {
                try device.lockForConfiguration()
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
            } catch {
                // AF config failed; fall back to contrast mode.
                useContrastMode = true
            }
        }

        captureDevice = device

        // Build the session on the background queue to avoid blocking the UI.
        captureQueue.async { [weak self] in
            guard let self = self else { return }
            self.buildAndStartSession(device: device, result: result)
        }
    }

    /**
     * Assembles the AVCaptureSession, adds input + output, and starts running.
     *
     * Separated from startCapture so it can run on the captureQueue.
     */
    private func buildAndStartSession(
        device: AVCaptureDevice,
        result: @escaping FlutterResult
    ) {
        let session = AVCaptureSession()
        // Lowest preset: in AF mode we only need the frame cadence to drive
        // lensPosition polling. In contrast mode low resolution is fine too.
        session.sessionPreset = .low

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "SESSION_ERROR",
                        message: "Cannot add camera input to session",
                        details: nil
                    ))
                }
                return
            }
            session.addInput(input)
        } catch {
            DispatchQueue.main.async {
                result(FlutterError(
                    code: "INPUT_ERROR",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
            return
        }

        // Video output drives the frame cadence; in AF mode we read lensPosition
        // in the per-frame delegate; in contrast mode we analyse the pixel buffer.
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            DispatchQueue.main.async {
                result(FlutterError(
                    code: "SESSION_ERROR",
                    message: "Cannot add video output to session",
                    details: nil
                ))
            }
            return
        }
        session.addOutput(output)

        self.captureSession = session
        session.startRunning()

        DispatchQueue.main.async { result(nil) }
    }

    /** Stops the capture session and releases all AVFoundation resources. */
    private func stopCapture() {
        captureQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
            self?.captureDevice = nil
        }
        frameCount = 0
        lumaHistory = []
    }

    // ─── Contrast analysis ────────────────────────────────────────────────────

    /**
     * Computes the mean luminance of the center 50% of [pixelBuffer] using
     * the Y plane of the YCbCr pixel format, normalized via a rolling 60-frame
     * min/max window so the value adapts to ambient lighting conditions.
     */
    private func computeNormalizedLuma(_ pixelBuffer: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return 0 }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let x0 = w / 4; let x1 = w * 3 / 4
        let y0 = h / 4; let y1 = h * 3 / 4
        var sum: Int = 0; var count = 0
        for row in y0..<y1 {
            for col in x0..<x1 {
                sum += Int(bytes[row * stride + col])
                count += 1
            }
        }
        let mean = count > 0 ? Double(sum) / Double(count) / 255.0 : 0.0
        if lumaHistory.count >= 30 { lumaHistory.removeFirst() }
        lumaHistory.append(mean)
        let minL = lumaHistory.min() ?? 0; let maxL = lumaHistory.max() ?? 1
        let range = maxL - minL
        return range < 0.02 ? 0.0 : max(0.0, min(1.0, (mean - minL) / range))
    }

    // ─── Preview thumbnail ────────────────────────────────────────────────────

    /**
     * Sends a 120×90 JPEG thumbnail to the preview EventChannel.
     *
     * Called every 3rd frame (≈ 10 fps) for a smoother live feel.
     *
     * Optimisations vs. previous implementation:
     *   - Uses the shared [ciContext] field instead of allocating a new
     *     CIContext on every call (CIContext construction sets up a Metal
     *     pipeline — the dominant cost of the previous implementation).
     *   - Applies a horizontal mirror so the front-camera image looks like a
     *     selfie rather than a laterally reversed photograph.
     */
    private func sendPreviewFrame(_ pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let targetSize = CGSize(width: 120, height: 90)
        let scaleX = targetSize.width  / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height

        // Scale then mirror horizontally (front-camera selfie convention).
        // CIImage uses bottom-left origin, so a -1 x-scale flips to negative x;
        // the subsequent translation moves it back into positive coordinates.
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let mirrored = scaled
            .transformed(by: CGAffineTransform(scaleX: -1, y: 1))
            .transformed(by: CGAffineTransform(translationX: scaled.extent.width, y: 0))

        guard let cgImage = ciContext.createCGImage(mirrored, from: mirrored.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.5) else { return }
        let flutterData = FlutterStandardTypedData(bytes: jpegData)
        DispatchQueue.main.async { [weak self] in self?.previewSink?(flutterData) }
    }
}

// ─── Preview stream handler ────────────────────────────────────────────────────

/** StreamHandler for the camera preview EventChannel. */
private class PreviewStreamHandler: NSObject, FlutterStreamHandler {
    weak var plugin: ThereminCameraPlugin?
    init(plugin: ThereminCameraPlugin) { self.plugin = plugin }

    func onListen(withArguments arguments: Any?,
                  eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.previewSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.previewSink = nil
        return nil
    }
}

// ─── AVCaptureVideoDataOutputSampleBufferDelegate ─────────────────────────────

extension ThereminCameraPlugin: AVCaptureVideoDataOutputSampleBufferDelegate {

    /**
     * Called by AVFoundation once per video frame on [captureQueue].
     *
     * In AF mode: reads lensPosition (already normalized [0,1]) and emits it.
     * In contrast mode: analyses the Y-plane luminance and emits a normalized
     * brightness value that tracks the hand's distance from the camera.
     *
     * Also sends a JPEG preview thumbnail every 3rd frame (≈ 10 fps).
     */
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1

        // Distance signal.
        if useContrastMode {
            // Emit the raw normalized luma — EMA smoothing is applied once on
            // the Dart side (ThereminDistanceService._smooth).  The previous
            // double-EMA (native + Dart) doubled the lag.
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let val = computeNormalizedLuma(pixelBuffer)
                DispatchQueue.main.async { [weak self] in self?.eventSink?(val) }
            }
        } else {
            guard let device = captureDevice else { return }
            // lensPosition: 0 = infinity (far hand, low pitch),
            //               1 = closest focus (near hand, high pitch).
            let pos = Double(device.lensPosition)
            DispatchQueue.main.async { [weak self] in self?.eventSink?(pos) }
        }

        // Preview thumbnail every 3rd frame (≈ 10 fps).
        if frameCount % 3 == 0, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            sendPreviewFrame(pixelBuffer)
        }
    }
}
