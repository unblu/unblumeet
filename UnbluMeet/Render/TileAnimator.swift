import CoreGraphics
import Foundation

/// Moves tiles to their new positions over a moment instead of snapping.
///
/// Layout is recomputed from scratch every frame, so nothing remembers where a
/// tile used to be — this does, per participant, and hands the compositor the
/// rect to draw right now.
struct TileAnimator {
    static let duration: TimeInterval = 0.3

    private struct Move {
        var from: CGRect
        var to: CGRect
        var startedAt: TimeInterval
    }

    private var moves: [String: Move] = [:]

    /// The rects to draw now, given where each tile is headed.
    mutating func resolve(targets: [Tile], now: TimeInterval) -> [Tile] {
        var resolved: [Tile] = []
        resolved.reserveCapacity(targets.count)

        for tile in targets {
            let move = moves[tile.participantID]

            if let move, move.to == tile.rect {
                resolved.append(Tile(participantID: tile.participantID,
                                     rect: Self.position(move, now: now)))
                continue
            }

            // A tile that is new to the layout starts where it belongs; only
            // one that was already on screen has somewhere to travel from.
            let from = move.map { Self.position($0, now: now) } ?? tile.rect
            moves[tile.participantID] = Move(from: from, to: tile.rect, startedAt: now)
            resolved.append(Tile(participantID: tile.participantID, rect: from))
        }

        let present = Set(targets.map(\.participantID))
        moves = moves.filter { present.contains($0.key) }
        return resolved
    }

    private static func position(_ move: Move, now: TimeInterval) -> CGRect {
        let elapsed = now - move.startedAt
        guard elapsed < duration else { return move.to }
        return interpolate(move.from, move.to, ease(max(0, elapsed) / duration))
    }

    nonisolated static func ease(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    nonisolated static func interpolate(_ from: CGRect, _ to: CGRect, _ t: Double) -> CGRect {
        let t = CGFloat(min(max(t, 0), 1))
        return CGRect(x: from.minX + (to.minX - from.minX) * t,
                      y: from.minY + (to.minY - from.minY) * t,
                      width: from.width + (to.width - from.width) * t,
                      height: from.height + (to.height - from.height) * t)
    }
}
