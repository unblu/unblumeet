import Foundation
import CoreGraphics

/// An annotation drawn over one participant's video.
struct Mark: Codable, Sendable, Identifiable, Equatable {
    /// LiveKit rejects data payloads over 15 KB; this cap keeps a mark far
    /// under it even before JSON overhead.
    static let maxPoints = 128

    let id: String
    let targetParticipantID: String
    let authorID: String
    let points: [CGPoint]
    let colorIndex: Int
    let createdAt: Double

    init(targetParticipantID: String,
         authorID: String,
         points: [CGPoint],
         colorIndex: Int,
         createdAt: Double,
         id: String = UUID().uuidString) {
        self.id = id
        self.targetParticipantID = targetParticipantID
        self.authorID = authorID
        self.points = Self.decimate(points).map {
            CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1))
        }
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }

    /// Evenly thins a long stroke instead of cutting its tail off.
    nonisolated static func decimate(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > maxPoints else { return points }
        let step = Double(points.count - 1) / Double(maxPoints - 1)
        return (0 ..< maxPoints).map { points[Int((Double($0) * step).rounded())] }
    }

    /// How long a mark stays on screen, and how much of that is spent fading.
    static let lifetime: TimeInterval = 8
    static let fadeDuration: TimeInterval = 2

    /// Opacity for a mark of the given age, 1 while fresh then easing to 0.
    static func opacity(age: TimeInterval) -> Double {
        guard age > 0 else { return 1 }
        guard age < lifetime else { return 0 }
        let fadeStart = lifetime - fadeDuration
        guard age > fadeStart else { return 1 }
        return 1 - (age - fadeStart) / fadeDuration
    }

    static func encode(_ mark: Mark) throws -> Data {
        try JSONEncoder().encode(mark)
    }

    static func decode(_ data: Data) throws -> Mark {
        try JSONDecoder().decode(Mark.self, from: data)
    }
}
