import Foundation
import CoreVideo
import LiveKit
import os

/// Receives decoded frames for one remote video track and files them in the
/// FrameStore.
final class TrackRenderer: NSObject, VideoRenderer {
    private let participantID: String
    private let store: FrameStore
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "TrackRenderer")
    private let formatLogged = OSAllocatedUnfairLock(initialState: false)

    @MainActor var tileSize: CGSize = CGSize(width: 320, height: 180)

    init(participantID: String, store: FrameStore) {
        self.participantID = participantID
        self.store = store
        super.init()
    }

    @MainActor var isAdaptiveStreamEnabled: Bool { true }
    @MainActor var adaptiveStreamSize: CGSize { tileSize }

    nonisolated func set(size: CGSize) {}

    nonisolated func render(frame: VideoFrame) {
        guard let pixelBuffer = frame.toCVPixelBuffer() else {
            logger.error("Frame for \(self.participantID, privacy: .public) could not convert to CVPixelBuffer")
            return
        }

        let shouldLog = formatLogged.withLock { logged -> Bool in
            guard !logged else { return false }
            logged = true
            return true
        }
        if shouldLog {
            let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
            let planes = CVPixelBufferGetPlaneCount(pixelBuffer)
            logger.info("First frame for \(self.participantID, privacy: .public): \(frame.dimensions.width)x\(frame.dimensions.height), pixel format \(format, privacy: .public), planes \(planes, privacy: .public)")
        }

        store.store(pixelBuffer, for: participantID)
    }
}
