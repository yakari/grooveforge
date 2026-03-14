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
 *
 * Works with any autofocus-capable webcam or built-in FaceTime camera.
 * Many older USB webcams are fixed-focus; in that case startCapture returns
 * a FIXED_FOCUS error and the slot UI falls back to touch-pad mode.
 *
 * See ios/Runner/ThereminCameraPlugin.swift for full technique documentation.
 */
class ThereminCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    // ─── Channel names ────────────────────────────────────────────────────────

    static let methodChannelName = "com.grooveforge/theremin_camera"
    static let eventChannelName  = "com.grooveforge/theremin_camera_events"

    // ─── State ────────────────────────────────────────────────────────────────

    private var eventSink: FlutterEventSink?
    private var captureSession: AVCaptureSession?
    private var captureDevice: AVCaptureDevice?
    private let captureQueue = DispatchQueue(
        label: "com.grooveforge.theremin.camera",
        qos: .userInteractive
    )

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

        guard device.isFocusModeSupported(.continuousAutoFocus) else {
            result(FlutterError(
                code: "FIXED_FOCUS",
                message: "Camera is fixed-focus; focal distance not available. " +
                         "Try a webcam with autofocus (e.g. Logitech BRIO).",
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
    }
}

// ─── AVCaptureVideoDataOutputSampleBufferDelegate ─────────────────────────────

extension ThereminCameraPlugin: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let device = captureDevice else { return }
        let pos = Double(device.lensPosition)
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(pos)
        }
    }
}
