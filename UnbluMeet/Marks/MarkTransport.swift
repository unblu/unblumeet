import Foundation
import LiveKit
import os

/// Carries marks over the LiveKit data channel.
@MainActor
final class MarkTransport {
    /// nonisolated so the RoomDelegate's data callback, which is not on the
    /// main actor, can filter on it.
    nonisolated static let topic = "unblumeet.marks"
    /// A separate topic so a receiver on an older build ignores callouts
    /// instead of failing to decode them as marks.
    nonisolated static let calloutTopic = "unblumeet.callouts"

    private let room: Room
    private let store: MarkStore
    private let authorID: String
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "MarkTransport")

    /// In-progress strokes are republished while being drawn so other people
    /// see the line appear as it is made.
    private static let streamInterval: TimeInterval = 0.12
    private var lastStreamedAt: TimeInterval = 0

    init(room: Room, store: MarkStore, authorID: String) {
        self.room = room
        self.store = store
        self.authorID = authorID
    }

    func send(_ mark: Mark) async {
        store.add(mark)
        do {
            let data = try Mark.encode(mark)
            try await room.localParticipant.publish(
                data: data, options: DataPublishOptions(topic: Self.topic))
        } catch {
            logger.error("Failed to publish mark: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Shows the stroke locally at once, and publishes it at most every
    /// streamInterval.
    func stream(_ mark: Mark) async {
        store.add(mark)
        let now = Date().timeIntervalSince1970
        guard now - lastStreamedAt >= Self.streamInterval else { return }
        lastStreamedAt = now
        try? await room.localParticipant.publish(
            data: try Mark.encode(mark), options: DataPublishOptions(topic: Self.topic))
    }

    func send(_ callout: Callout) async {
        store.add(callout)
        do {
            let data = try Callout.encode(callout)
            try await room.localParticipant.publish(
                data: data, options: DataPublishOptions(topic: Self.calloutTopic))
        } catch {
            logger.error("Failed to publish callout: \(error.localizedDescription, privacy: .public)")
        }
    }
}
