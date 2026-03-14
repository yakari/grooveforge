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
 * Technique:
 *   1. Opens an AVCaptureSession with the front-facing wide-angle camera.
 *   2. Enables AVCaptureFocusModeContinuousAutoFocus so the lens tracks the
 *      nearest subject (the player's hand).
 *   3. Adds an AVCaptureVideoDataOutput whose per-frame callback reads
 *      AVCaptureDevice.lensPosition — already normalized to [0, 1] by iOS,
 *      where 0 = infinity and 1 = minimum focus distance.
 *   4. Emits each lensPosition to Flutter via EventChannel on the main thread.
 *
 * AVCaptureDevice.lensPosition vs. LENS_FOCUS_DISTANCE (Android):
 *   Both measure where the AF motor currently sits. lensPosition is already
 *   dimensionless [0, 1]; no normalization needed on Apple platforms.
 *
 * Limitations:
 *   - Requires NSCameraUsageDescription in Info.plist and user permission.
 *   - Returns FIXED_FOCUS if the camera does not support continuousAutoFocus.
 *   - AF latency varies by device (iPhone 15: ~100 ms; older models: ~300 ms).
 */
class ThereminCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // ─── Channel names ────────────────────────────────────────────────────────

    static let methodChannelName = "com.grooveforge/theremin_camera"
    static let eventChannelName  = "com.grooveforge/theremin_camera_events"

    // ─── State ────────────────────────────────────────────────────────────────

    /** Delivers distance values to Dart; set by Flutter on EventChannel.listen. */
    private var eventSink: FlutterEventSink?

    private var captureSession: AVCaptureSession?

    /** The active camera device; we read its lensPosition each frame. */
    private var captureDevice: AVCaptureDevice?

    /** Serial queue for all Camera session / delegate calls. */
    private let captureQueue = DispatchQueue(
        label: "com.grooveforge.theremin.camera",
        qos: .userInteractive
    )

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

        let instance = ThereminCameraPlugin()
        methodChannel.setMethodCallHandler(instance.handleMethodCall(_:result:))
        eventChannel.setStreamHandler(instance)
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
            // iOS always supports this code path; actual AF support is checked
            // in startCapture and surfaced as a FIXED_FOCUS error if absent.
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // ─── FlutterStreamHandler ─────────────────────────────────────────────────

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
     * Calls result(nil) once the session is configured and streaming.
     * Returns a FlutterError via result if no AF-capable front camera is found.
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

        // Continuous AF is required: without it lensPosition stays fixed and
        // carries no hand-distance information.
        guard device.isFocusModeSupported(.continuousAutoFocus) else {
            result(FlutterError(
                code: "FIXED_FOCUS",
                message: "Front camera is fixed-focus; focal distance not available",
                details: nil
            ))
            return
        }

        do {
            try device.lockForConfiguration()
            device.focusMode = .continuousAutoFocus
            device.unlockForConfiguration()
        } catch {
            result(FlutterError(
                code: "CONFIG_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
            return
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
        // Lowest preset: we only need the frame cadence to drive lensPosition
        // polling — we never look at pixel data.
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

        // Video output drives the frame cadence; we read lensPosition in the
        // per-frame delegate and discard the pixel buffer itself.
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
    }
}

// ─── AVCaptureVideoDataOutputSampleBufferDelegate ─────────────────────────────

extension ThereminCameraPlugin: AVCaptureVideoDataOutputSampleBufferDelegate {

    /**
     * Called by AVFoundation once per video frame on [captureQueue].
     *
     * Reads AVCaptureDevice.lensPosition: a Float already normalized to
     * [0.0 = infinity, 1.0 = minimum focus distance]. This value changes as
     * the AF motor tracks the player's hand.
     *
     * Emits the value to Flutter on the main thread.
     */
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let device = captureDevice else { return }

        // lensPosition: 0 = infinity (far hand, low pitch),
        //               1 = closest focus (near hand, high pitch).
        let pos = Double(device.lensPosition)

        // EventSink must be called on the main thread.
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(pos)
        }
    }
}
