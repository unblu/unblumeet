import Foundation
import CoreGraphics
import LiveKit

/// Subscribes only to what is on screen, and tells LiveKit how large each
/// tile is so it can pick an appropriate simulcast layer.
@MainActor
final class SubscriptionPolicy {
    private let controller: RoomController
    private var subscribed: Set<String> = []
    private var applyTask: Task<Void, Never>?

    init(controller: RoomController) {
        self.controller = controller
    }

    func apply(tiles: [Tile], viewportSize: CGSize) {
        let visible = Set(tiles.map(\.participantID))

        // Report each visible tile's pixel size so adaptive stream picks a layer.
        for tile in tiles {
            guard let renderer = controller.renderers[tile.participantID] else { continue }
            renderer.tileSize = CGSize(width: tile.rect.width * viewportSize.width,
                                       height: tile.rect.height * viewportSize.height)
        }

        guard visible != subscribed else { return }

        // Collect first, then apply in one ordered task.
        var changes: [(publication: RemoteTrackPublication, subscribe: Bool)] = []

        for participant in controller.room.remoteParticipants.values {
            let identity = RoomController.identityKey(for: participant)

            for publication in participant.videoTracks {
                guard let remote = publication as? RemoteTrackPublication else { continue }

                // Per track, not per participant: a participant can publish a
                // camera and a screen, and those are separate tiles with
                // separate keys.
                let key = remote.source == .screenShareVideo
                    ? RoomController.screenKey(for: identity)
                    : identity

                changes.append((remote, visible.contains(key)))
            }
        }

        // Subscribes first: a tile the user is now looking at should start
        // arriving before bandwidth is reclaimed from the ones they left.
        changes.sort { $0.subscribe && !$1.subscribe }

        applyTask?.cancel()
        applyTask = Task { [controller] in
            for change in changes {
                if Task.isCancelled { return }
                try? await change.publication.set(subscribed: change.subscribe)
            }
            guard !Task.isCancelled else { return }
            // Delegate callbacks only fire on a change; a track that stayed
            // subscribed gets none, so reconcile explicitly.
            await MainActor.run { controller.reconcileRenderers() }
        }

        subscribed = visible
    }
}
