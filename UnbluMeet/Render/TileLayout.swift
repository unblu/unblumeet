import CoreGraphics
import Foundation

enum LayoutMode: String, CaseIterable {
    case grid, speaker, pinned
}

struct Tile: Equatable {
    let participantID: String
    /// Normalised 0–1 within the compositor viewport, origin top-left.
    let rect: CGRect
}

/// Pure layout arithmetic.
enum TileLayout {
    /// Rendering more than `pageSize` tiles is a non-goal: a Mac cannot
    /// decode that many streams.
    static let stripCapacity = 8

    static func layout(mode: LayoutMode,
                       participantIDs: [String],
                       focusID: String?,
                       aspect: CGFloat,
                       page: Int = 0,
                       pageSize: Int = 25,
                       stripOffset: Int = 0) -> [Tile] {
        guard !participantIDs.isEmpty else { return [] }

        switch mode {
        case .grid:
            let start = page * pageSize
            guard start < participantIDs.count else { return [] }
            let end = min(start + pageSize, participantIDs.count)
            return grid(Array(participantIDs[start ..< end]))
        case .speaker:
            return speaker(participantIDs, focusID: focusID, stripOffset: stripOffset)
        case .pinned:
            return pinned(participantIDs, focusID: focusID)
        }
    }

    /// Largest valid strip offset — the strip stops rather than scrolling
    /// past the last thumbnail.
    static func maxStripOffset(participantCount: Int) -> Int {
        max(0, (participantCount - 1) - stripCapacity)
    }

    static func pageCount(participantCount: Int, mode: LayoutMode, pageSize: Int = 25) -> Int {
        guard mode == .grid, participantCount > 0 else { return 1 }
        return Int(ceil(Double(participantCount) / Double(pageSize)))
    }

    private static func grid(_ ids: [String]) -> [Tile] {
        let columns = Int(ceil(sqrt(Double(ids.count))))
        let rows = Int(ceil(Double(ids.count) / Double(columns)))
        let cellWidth = 1.0 / CGFloat(columns)
        let cellHeight = 1.0 / CGFloat(rows)

        return ids.enumerated().map { index, id in
            let column = index % columns
            let row = index / columns
            return Tile(participantID: id,
                        rect: CGRect(x: CGFloat(column) * cellWidth,
                                     y: CGFloat(row) * cellHeight,
                                     width: cellWidth,
                                     height: cellHeight))
        }
    }

    private static func speaker(_ ids: [String], focusID: String?, stripOffset: Int = 0) -> [Tile] {
        let focus = focusID.flatMap { ids.contains($0) ? $0 : nil } ?? ids[0]
        let all = ids.filter { $0 != focus }
        let start = min(max(stripOffset, 0), max(0, all.count - 1))
        let others = Array(all.dropFirst(start).prefix(stripCapacity))
        guard !others.isEmpty else {
            return [Tile(participantID: focus, rect: CGRect(x: 0, y: 0, width: 1, height: 1))]
        }

        let stripHeight: CGFloat = 0.2
        var tiles = [Tile(participantID: focus,
                          rect: CGRect(x: 0, y: 0, width: 1, height: 1 - stripHeight))]

        let cellWidth = 1.0 / CGFloat(others.count)
        for (index, id) in others.enumerated() {
            tiles.append(Tile(participantID: id,
                              rect: CGRect(x: CGFloat(index) * cellWidth,
                                           y: 1 - stripHeight,
                                           width: cellWidth,
                                           height: stripHeight)))
        }
        return tiles
    }

    /// Falls back to the first participant only when no focus was requested.
    private static func pinned(_ ids: [String], focusID: String?) -> [Tile] {
        let focus: String
        if let focusID {
            guard ids.contains(focusID) else { return [] }
            focus = focusID
        } else {
            focus = ids[0]
        }
        return [Tile(participantID: focus, rect: CGRect(x: 0, y: 0, width: 1, height: 1))]
    }
}

/// Per-tile zoom, expressed as the sub-rectangle of the video frame to
/// sample.
struct ZoomState: Equatable, Sendable {
    var scale: CGFloat
    var center: CGPoint

    static let identity = ZoomState(scale: 1, center: CGPoint(x: 0.5, y: 0.5))

    /// The 0–1 sub-rectangle of the frame visible at this zoom, clamped so
    /// the window never runs off the edge of the video.
    static func uvRect(scale: CGFloat, center: CGPoint) -> CGRect {
        let effective = max(scale, 1)
        let size = 1.0 / effective
        let x = min(max(center.x - size / 2, 0), 1 - size)
        let y = min(max(center.y - size / 2, 0), 1 - size)
        return CGRect(x: x, y: y, width: size, height: size)
    }

    var uvRect: CGRect { Self.uvRect(scale: scale, center: center) }
}
