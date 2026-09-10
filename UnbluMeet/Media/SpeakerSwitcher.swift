import Foundation

/// Chooses whose video fills the large tile in speaker mode.
struct SpeakerSwitcher {
    /// How long a new voice must hold the floor before the layout follows it.
    static let dwell: TimeInterval = 1.2

    private(set) var current: String?
    private var candidate: String?
    private var candidateSince: TimeInterval = 0

    mutating func update(speaking: String?, now: TimeInterval) -> String? {
        guard let speaking else {
            // Silence keeps the last speaker on screen.
            candidate = nil
            return current
        }

        if speaking == current {
            candidate = nil
            return current
        }

        if speaking != candidate {
            candidate = speaking
            candidateSince = now
            return current
        }

        if now - candidateSince >= Self.dwell {
            current = speaking
            candidate = nil
        }
        return current
    }
}
