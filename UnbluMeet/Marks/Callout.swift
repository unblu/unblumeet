import Foundation
import CoreGraphics

/// A "look at this" marker: a region of someone's video, plus a magnified
/// inset of that region drawn beside it.
struct Callout: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let targetParticipantID: String
    let authorID: String
    /// In frame coordinates (0…1 of the source video), like Mark.points, so
    /// it tracks the tile through layout changes and zoom.
    let region: CGRect
    let colorIndex: Int
    let createdAt: Double

    /// Smaller than this and it is a stray click, not a selection.
    static let minimumSide: CGFloat = 0.01

    /// Longer than a stroke: a callout is meant to be read, not glanced at.
    static let lifetime: TimeInterval = 20
    static let fadeDuration: TimeInterval = 3

    init(targetParticipantID: String,
         authorID: String,
         region: CGRect,
         colorIndex: Int,
         createdAt: Double,
         id: String = UUID().uuidString) {
        self.id = id
        self.targetParticipantID = targetParticipantID
        self.authorID = authorID
        self.region = Self.clamp(region)
        self.colorIndex = colorIndex
        self.createdAt = createdAt
    }

    /// Normalised, positive, and inside the frame.
    nonisolated static func clamp(_ rect: CGRect) -> CGRect {
        let standard = rect.standardized
        let clamped = standard.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return clamped.isNull ? .zero : clamped
    }

    nonisolated static func isUsable(_ rect: CGRect) -> Bool {
        let clamped = clamp(rect)
        return clamped.width >= minimumSide && clamped.height >= minimumSide
    }

    nonisolated static func opacity(age: TimeInterval) -> Double {
        guard age > 0 else { return 1 }
        guard age < lifetime else { return 0 }
        let fadeStart = lifetime - fadeDuration
        guard age > fadeStart else { return 1 }
        return 1 - (age - fadeStart) / fadeDuration
    }

    /// Where to draw the magnified inset, in the same tile-local space as
    /// `regionInTile` (0…1 across the tile).
    nonisolated static func insetRect(regionInTile region: CGRect,
                                      magnification: CGFloat = 3,
                                      maxWidth: CGFloat = 0.5,
                                      maxHeight: CGFloat = 0.55,
                                      gap: CGFloat = 0.025) -> CGRect {
        guard region.width > 0, region.height > 0 else { return .zero }

        // Region and inset share a coordinate space, so scaling both sides
        // equally preserves the region's on-screen shape.
        var width = min(region.width * magnification, maxWidth)
        var height = width * (region.height / region.width)
        if height > maxHeight {
            let shrink = maxHeight / height
            width *= shrink
            height = maxHeight
        }

        let x = min(max(region.midX - width / 2, 0.02), max(0.02, 0.98 - width))

        let below = region.maxY + gap
        let above = region.minY - gap - height
        let y: CGFloat
        if below + height <= 0.98 {
            y = below
        } else if above >= 0.02 {
            y = above
        } else {
            // Neither side fits: pin to the bottom and let it overlap.
            y = max(0.02, 0.98 - height)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    nonisolated static func encode(_ callout: Callout) throws -> Data {
        try JSONEncoder().encode(callout)
    }

    nonisolated static func decode(_ data: Data) throws -> Callout {
        try JSONDecoder().decode(Callout.self, from: data)
    }
}

/// What a drag on a tile does.
enum MarkTool: String, CaseIterable, Identifiable, Sendable {
    case pen
    case callout

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pen: "scribble"
        case .callout: "rectangle.and.text.magnifyingglass"
        }
    }

    var help: String {
        switch self {
        case .pen: "Draw a line everyone can see"
        case .callout: "Drag a box — everyone sees it magnified"
        }
    }
}
