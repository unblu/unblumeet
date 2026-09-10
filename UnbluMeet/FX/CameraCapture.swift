import AVFoundation
import CoreVideo
import os

/// Owns the camera.
final class CameraCapture: NSObject, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.unblu.UnbluMeet.camera")
    private let onFrame: @Sendable (CVPixelBuffer) -> Void
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "CameraCapture")

    var isRunning: Bool { session.isRunning }

    /// Cameras available for selection, ordered by how reliably they produce
    /// frames: built-in, then other physical cameras, then virtual ones.
    static func availableDevices() -> [AVCaptureDevice] {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        return devices.sorted { rank($0) < rank($1) }
    }

    private static func rank(_ device: AVCaptureDevice) -> Int {
        if isVirtual(device) { return 2 }
        return device.deviceType == .builtInWideAngleCamera ? 0 : 1
    }

    static func isVirtual(_ device: AVCaptureDevice) -> Bool {
        isVirtualName(device.localizedName)
    }

    nonisolated static func isVirtualName(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.contains("virtual") || lowered.contains("obs") || lowered.contains("camo")
    }

    /// The camera to use when none has been chosen: a real one if there is one.
    static func preferredDefault() -> AVCaptureDevice? {
        availableDevices().first ?? AVCaptureDevice.default(for: .video)
    }

    init(deviceID: String?, onFrame: @escaping @Sendable (CVPixelBuffer) -> Void) {
        self.onFrame = onFrame
        super.init()
        configure(deviceID: deviceID)
    }

    /// Swaps the camera without tearing down the whole capture pipeline, so
    /// the published track survives the change.
    func switchDevice(to deviceID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            if let device = Self.availableDevices().first(where: { $0.uniqueID == deviceID }),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
        // Log the device actually opened: a virtual camera can win the
        // default and then produce nothing, which looks exactly like a broken
        // camera.
        logger.info("Capturing from \(device.localizedName, privacy: .public)")
            }
            session.commitConfiguration()
        }
    }

    private func configure(deviceID: String?) {
        session.beginConfiguration()
        session.sessionPreset = .high

        let device = Self.availableDevices().first { $0.uniqueID == deviceID }
            ?? AVCaptureDevice.default(for: .video)

        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            logger.error("No usable camera device")
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // BGRA keeps the Core Image and Metal paths simple; the compositor
        // already handles packed BGRA for remote frames.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }

        session.commitConfiguration()
    }

    func start() {
        queue.async { [session] in
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [session] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }
}

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame(pixelBuffer)
    }
}
