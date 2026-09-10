import Foundation

/// A participant order the user has arranged by dragging tiles around.
enum TileOrder {
    /// Applies a saved arrangement to the current tiles.
    nonisolated static func apply(_ order: [String], to ids: [String]) -> [String] {
        guard !order.isEmpty else { return ids }
        let ranked = order.enumerated().reduce(into: [String: Int]()) { $0[$1.element] = $1.offset }
        let known = ids.filter { ranked[$0] != nil }.sorted { (ranked[$0] ?? 0) < (ranked[$1] ?? 0) }
        let unknown = ids.filter { ranked[$0] == nil }
        return known + unknown
    }

    /// The arrangement after dragging one tile onto another.
    nonisolated static func moving(_ source: String,
                                   onto target: String,
                                   in ids: [String]) -> [String] {
        guard source != target,
              let from = ids.firstIndex(of: source),
              let to = ids.firstIndex(of: target) else { return ids }
        var result = ids
        result.remove(at: from)
        result.insert(source, at: to)
        return result
    }
}
