import Foundation
import LiveKit
import CoreVideo
import AVFoundation
import os

/// Camera → optional background replacement → LiveKit.
@MainActor
final class CameraPublisher {
    private let room: Room
    private let frameStore: FrameStore
    private let localIdentity: String
    private let replacer = BackgroundReplacer()
    private var capture: CameraCapture?
    private var track: LocalVideoTrack?
    private var publication: LocalTrackPublication?
    private(set) var cameraDeviceID: String?
    /// Why the camera did not start, if it did not.
    private(set) var failure: String?
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "CameraPublisher")

    var backgroundMode: BackgroundMode {
        get { replacer.mode }
        set { replacer.mode = newValue }
    }

    private let presenterOverlay: PresenterOverlay?

    init(room: Room, frameStore: FrameStore, localIdentity: String, cameraDeviceID: String?,
         presenterOverlay: PresenterOverlay? = nil) {
        self.room = room
        self.frameStore = frameStore
        self.localIdentity = localIdentity
        self.cameraDeviceID = cameraDeviceID
        self.presenterOverlay = presenterOverlay
    }

    /// nonisolated: the completion arrives on an arbitrary queue, and a
    /// closure written in a @MainActor class would assert isolation and trap.
    private nonisolated static func requestCameraAccess() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { return true }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() async {
        guard track == nil else { return }
        failure = nil

        guard await Self.requestCameraAccess() else {
            failure = "Camera access is denied. Enable UnbluMeet under Privacy & Security > Camera."
            logger.error("Camera access denied")
            return
        }

        guard !CameraCapture.availableDevices().isEmpty else {
            failure = "No camera was found on this Mac."
            logger.error("No camera devices")
            return
        }

        // Source must be .camera — createBufferTrack defaults to
        // .screenShareVideo, which would publish into the wrong slot.
        let videoTrack = LocalVideoTrack.createBufferTrack(
            name: "camera",
            source: .camera,
            options: BufferCaptureOptions(),
            reportStatistics: false
        )
        guard let bufferCapturer = videoTrack.capturer as? BufferCapturer else {
            failure = "Could not create the camera track."
            logger.error("createBufferTrack did not yield a BufferCapturer")
            return
        }

        // The same processed frame goes to LiveKit and to our own FrameStore,
        // so you can see your own background replacement without a second
        // Mac.
        let replacer = self.replacer
        let frameStore = self.frameStore
        let localIdentity = self.localIdentity
        let overlay = self.presenterOverlay
        let capture = CameraCapture(deviceID: cameraDeviceID) { pixelBuffer in
            let processed = replacer.process(pixelBuffer)
            overlay?.update(camera: processed)
            bufferCapturer.capture(processed)
            frameStore.store(processed, for: localIdentity)
        }

        self.track = videoTrack
        self.capture = capture
        capture.start()

        // At least one frame must be captured before publishing, since the
        // track's dimensions are resolved at publish time.
        try? await Task.sleep(for: .milliseconds(300))
        do {
            publication = try await room.localParticipant.publish(videoTrack: videoTrack)
            logger.info("Camera published")
        } catch {
            failure = "Publishing the camera failed: \(error.localizedDescription)"
            logger.error("Publish failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func selectCamera(_ deviceID: String) {
        cameraDeviceID = deviceID
        capture?.switchDevice(to: deviceID)
    }

    func stop() async {
        capture?.stop()
        capture = nil
        frameStore.remove(participantID: localIdentity)
        if let publication {
            try? await room.localParticipant.unpublish(publication: publication)
        }
        publication = nil
        track = nil
    }
}
