import Foundation

/// Marks grouped by the participant whose video they annotate.
final class MarkStore: @unchecked Sendable {
    /// Age is measured from arrival, not from the sender's createdAt: two
    /// Macs do not share a clock, and skew would expire marks early or late.
    private struct Stored {
        let mark: Mark
        let receivedAt: TimeInterval
    }

    private struct StoredCallout {
        let callout: Callout
        let receivedAt: TimeInterval
    }

    private var byParticipant: [String: [Stored]] = [:]
    private var calloutsByParticipant: [String: [StoredCallout]] = [:]
    private let lock = NSLock()

    func add(_ mark: Mark, now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        var existing = byParticipant[mark.targetParticipantID] ?? []
        // Replace rather than ignore: a stroke in progress is republished
        // under the same id as it grows, and the newest version is the live
        // one.
        if let index = existing.firstIndex(where: { $0.mark.id == mark.id }) {
            existing[index] = Stored(mark: mark, receivedAt: now)
        } else {
            existing.append(Stored(mark: mark, receivedAt: now))
        }
        byParticipant[mark.targetParticipantID] = existing
        lock.unlock()
    }

    /// Marks still worth drawing, each with the opacity for its age.
    func visibleMarks(for participantID: String,
                      now: TimeInterval = Date().timeIntervalSince1970) -> [(mark: Mark, opacity: Double)] {
        lock.lock()
        defer { lock.unlock() }

        let stored = byParticipant[participantID] ?? []
        let alive = stored.filter { now - $0.receivedAt < Mark.lifetime }
        if alive.count != stored.count {
            byParticipant[participantID] = alive.isEmpty ? nil : alive
        }
        return alive.map { ($0.mark, Mark.opacity(age: now - $0.receivedAt)) }
    }

    func add(_ callout: Callout, now: TimeInterval = Date().timeIntervalSince1970) {
        lock.lock()
        var existing = calloutsByParticipant[callout.targetParticipantID] ?? []
        if !existing.contains(where: { $0.callout.id == callout.id }) {
            existing.append(StoredCallout(callout: callout, receivedAt: now))
        }
        calloutsByParticipant[callout.targetParticipantID] = existing
        lock.unlock()
    }

    func visibleCallouts(for participantID: String,
                         now: TimeInterval = Date().timeIntervalSince1970) -> [(callout: Callout, opacity: Double)] {
        lock.lock()
        defer { lock.unlock() }

        let stored = calloutsByParticipant[participantID] ?? []
        let alive = stored.filter { now - $0.receivedAt < Callout.lifetime }
        if alive.count != stored.count {
            calloutsByParticipant[participantID] = alive.isEmpty ? nil : alive
        }
        return alive.map { ($0.callout, Callout.opacity(age: now - $0.receivedAt)) }
    }

    func marks(for participantID: String) -> [Mark] {
        visibleMarks(for: participantID).map(\.mark)
    }

    func clear(participantID: String) {
        lock.lock()
        byParticipant[participantID] = nil
        calloutsByParticipant[participantID] = nil
        lock.unlock()
    }

    func clearAll() {
        lock.lock()
        byParticipant.removeAll()
        calloutsByParticipant.removeAll()
        lock.unlock()
    }
}
