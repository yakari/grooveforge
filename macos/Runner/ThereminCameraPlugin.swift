import AVFoundation
import FlutterMacOS

/**
 * ThereminCameraPlugin — macOS side of the theremin focal-distance channel.
 *
 * Identical logic to ios/Runner/ThereminCameraPlugin.swift, with two
 * macOS-specific differences:
 *   1. Uses the default system camera (no front/back distinction on Mac).
 *   2. Uses `registrar.messenger` (property) instead of `registrar.messenger()`
 *      (method), as required by the FlutterMacOS SDK.
 *   3. Preview thumbnails use NSBitmapImageRep instead of UIImage.
 *
 * **Autofocus mode** (default for AF-capable cameras):
 *   Reads AVCaptureDevice.lensPosition each frame.
 *
 * **Contrast mode** (automatic fallback for fixed-focus webcams):
 *   Computes the mean luminance of the center 50% of each YCbCr frame, applies
 *   a 60-frame rolling min/max normalization, then emits the normalized value.
 *   Works on any webcam regardless of AF capability.
 *
 * See ios/Runner/ThereminCameraPlugin.swift for full technique documentation.
 */
class ThereminCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // ─── Channel names ────────────────────────────────────────────────────────

    static let methodChannelName = "com.grooveforge/theremin_camera"
    static let eventChannelName  = "com.grooveforge/theremin_camera_events"
    static let previewChannelName = "com.grooveforge/theremin_camera_preview"

    // ─── State ────────────────────────────────────────────────────────────────

    private var eventSink: FlutterEventSink?
    private var previewSink: FlutterEventSink?
    private var captureSession: AVCaptureSession?
    private var captureDevice: AVCaptureDevice?
    private let captureQueue = DispatchQueue(
        label: "com.grooveforge.theremin.camera",
        qos: .userInteractive
    )

    // ─── Contrast-mode state ──────────────────────────────────────────────────

    /** True when the camera does not support continuousAutoFocus. */
    private var useContrastMode = false

    /** EMA-smoothed contrast value emitted in contrast mode. */
    private var smoothedContrast: Double = 0.0

    /** Rolling luma history for 60-frame min/max normalization. */
    private var lumaHistory: [Double] = []

    /** Frame counter for throttling preview to ≈ 5 fps. */
    private var frameCount = 0

    // ─── FlutterPlugin ────────────────────────────────────────────────────────

    static func register(with registrar: FlutterPluginRegistrar) {
        // macOS SDK exposes messenger as a property (not a method call).
        let messenger: FlutterBinaryMessenger = registrar.messenger

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
        methodChannel.setMethodCallHandler(instance.handleMethodCall(_:result:))
        eventChannel.setStreamHandler(instance)
        let previewHandler = PreviewStreamHandler(plugin: instance)
        previewChannel.setStreamHandler(previewHandler)
    }

    // ─── Method calls ─────────────────────────────────────────────────────────

    func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            startCapture(result: result)
        case "stop":
            stopCapture()
            result(nil)
        case "isSupported":
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
     * Configures and starts an AVCaptureSession with the default camera.
     *
     * If the camera supports continuousAutoFocus, enables AF and uses
     * lensPosition for distance. Otherwise falls back to contrast mode.
     * Never returns a FIXED_FOCUS error — that case is handled transparently.
     */
    private func startCapture(result: @escaping FlutterResult) {
        // On macOS there is no front/back camera concept — just pick the
        // default video capture device (typically the built-in FaceTime HD
        // camera or the user's preferred webcam).
        guard let device = AVCaptureDevice.default(for: .video) else {
            result(FlutterError(
                code: "NO_CAMERA",
                message: "No camera found on this Mac",
                details: nil
            ))
            return
        }

        // Decide AF vs. contrast mode based on what this camera supports.
        if !device.isFocusModeSupported(.continuousAutoFocus) {
            // Fixed-focus camera (common for USB webcams): fall back to
            // brightness/contrast analysis.
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

        captureQueue.async { [weak self] in
            guard let self = self else { return }
            self.buildAndStartSession(device: device, result: result)
        }
    }

    private func buildAndStartSession(
        device: AVCaptureDevice,
        result: @escaping FlutterResult
    ) {
        let session = AVCaptureSession()
        session.sessionPreset = .low

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "SESSION_ERROR",
                        message: "Cannot add camera input",
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

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            DispatchQueue.main.async {
                result(FlutterError(
                    code: "SESSION_ERROR",
                    message: "Cannot add video output",
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

    private func stopCapture() {
        captureQueue.async { [weak self] in
            self?.captureSession?.stopRunning()
            self?.captureSession = nil
            self?.captureDevice = nil
        }
        frameCount = 0
        smoothedContrast = 0.0
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
        if lumaHistory.count >= 60 { lumaHistory.removeFirst() }
        lumaHistory.append(mean)
        let minL = lumaHistory.min() ?? 0; let maxL = lumaHistory.max() ?? 1
        let range = maxL - minL
        return range < 0.02 ? 0.0 : max(0.0, min(1.0, (mean - minL) / range))
    }

    // ─── Preview thumbnail ────────────────────────────────────────────────────

    /**
     * Sends a 120×90 JPEG grayscale thumbnail to the preview EventChannel.
     *
     * Uses NSBitmapImageRep for JPEG encoding (macOS equivalent of UIImage).
     */
    private func sendPreviewFrame(_ pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let targetSize = CGSize(width: 120, height: 90)
        let scaleX = targetSize.width  / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let ctx = CIContext()
        guard let cgImage = ctx.createCGImage(scaled, from: scaled.extent) else { return }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let jpegData = bitmapRep.representation(
            using: .jpeg, properties: [.compressionFactor: NSNumber(value: 0.5)]
        ) else { return }
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
     * Also sends a JPEG preview thumbnail every 6th frame (≈ 5 fps).
     */
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1

        // Distance signal.
        if useContrastMode {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                let luma = computeNormalizedLuma(pixelBuffer)
                smoothedContrast = smoothedContrast * 0.85 + luma * 0.15
                let val = smoothedContrast
                DispatchQueue.main.async { [weak self] in self?.eventSink?(val) }
            }
        } else {
            guard let device = captureDevice else { return }
            let pos = Double(device.lensPosition)
            DispatchQueue.main.async { [weak self] in self?.eventSink?(pos) }
        }

        // Preview thumbnail every 6th frame (≈ 5 fps).
        if frameCount % 6 == 0, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            sendPreviewFrame(pixelBuffer)
        }
    }
}
