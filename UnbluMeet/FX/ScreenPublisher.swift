import Foundation
import LiveKit
import CoreVideo

/// Screen or window → LiveKit, published as a screen-share track.
@MainActor
final class ScreenPublisher {
    private let room: Room
    private let frameStore: FrameStore
    private let localScreenID: String

    private var capture: ScreenCapture?
    private var track: LocalVideoTrack?
    private var publication: LocalTrackPublication?

    private(set) var isSharing = false

    private let presenterOverlay: PresenterOverlay?

    init(room: Room, frameStore: FrameStore, localScreenID: String,
         presenterOverlay: PresenterOverlay? = nil) {
        self.room = room
        self.frameStore = frameStore
        self.localScreenID = localScreenID
        self.presenterOverlay = presenterOverlay
    }

    func start(target: ShareTarget) async throws {
        await stop()

        let videoTrack = LocalVideoTrack.createBufferTrack(
            name: "screen",
            source: .screenShareVideo,
            options: BufferCaptureOptions(),
            reportStatistics: false
        )
        guard let bufferCapturer = videoTrack.capturer as? BufferCapturer else { return }

        // Same frame to LiveKit and to our own store, so the sharer sees
        // their own share in the grid like everyone else.
        let frameStore = self.frameStore
        let localScreenID = self.localScreenID
        let overlay = self.presenterOverlay
        let capture = ScreenCapture { pixelBuffer in
            // Composited before publishing, so everyone sees the presenter,
            // not just this Mac.
            let framed = overlay?.compose(onto: pixelBuffer) ?? pixelBuffer
            bufferCapturer.capture(framed)
            frameStore.store(framed, for: localScreenID)
        }

        try await capture.start(target: target)

        self.capture = capture
        self.track = videoTrack

        // Dimensions resolve at publish time, so let a frame land first.
        try? await Task.sleep(for: .milliseconds(300))
        publication = try? await room.localParticipant.publish(videoTrack: videoTrack)
        isSharing = true
    }

    func stop() async {
        await capture?.stop()
        capture = nil
        frameStore.remove(participantID: localScreenID)
        if let publication {
            try? await room.localParticipant.unpublish(publication: publication)
        }
        publication = nil
        track = nil
        isSharing = false
    }
}
