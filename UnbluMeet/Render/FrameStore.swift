import Foundation
import CoreVideo

/// Holds the most recent decoded frame for each participant.
final class FrameStore: @unchecked Sendable {
    private var frames: [String: CVPixelBuffer] = [:]
    private let lock = NSLock()

    func store(_ pixelBuffer: CVPixelBuffer, for participantID: String) {
        lock.lock()
        frames[participantID] = pixelBuffer
        lock.unlock()
    }

    func latest(for participantID: String) -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return frames[participantID]
    }

    func remove(participantID: String) {
        lock.lock()
        frames.removeValue(forKey: participantID)
        lock.unlock()
    }

    var participantIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(frames.keys)
    }
}
