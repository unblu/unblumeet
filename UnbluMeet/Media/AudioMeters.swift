import Foundation
import AVFoundation
import LiveKit

/// Per-participant audio levels, smoothed for display.
///
/// From inbound-RTP statistics, which WebRTC computes locally per receiver.
/// The server's speaker updates are useless for publishers that send no
/// ssrc-audio-level header extension, and a per-track AudioRenderer only ever
/// delivered silence.
final class AudioMeters: @unchecked Sendable {
    private struct Reading {
        var level: Float
        var at: TimeInterval
    }

    private var readings: [String: Reading] = [:]
    private var everMeasured = false
    private let lock = NSLock()

    /// Whether any statistics have ever arrived, so callers can fall back to
    /// the server's numbers rather than showing nothing.
    var hasReadings: Bool {
        lock.lock()
        defer { lock.unlock() }
        return everMeasured
    }

    /// How quickly a level falls once readings stop arriving — a safety net
    /// for a track that goes away between polls, not the normal path.
    static let silenceHalfLife: TimeInterval = 0.5

    /// `level` is already 0…1, as inbound-RTP statistics report it.
    func record(level: Float, for participantID: String, now: TimeInterval = Date().timeIntervalSince1970) {
        let scaled = min(max(level, 0), 1)
        lock.lock()
        everMeasured = true
        let previous = readings[participantID]?.level ?? 0
        // Fast attack, slow release: a meter that drops instantly between
        // syllables reads as broken.
        let smoothed = scaled > previous ? scaled : previous * 0.7 + scaled * 0.3
        readings[participantID] = Reading(level: smoothed, at: now)
        lock.unlock()
    }

    func level(for participantID: String, now: TimeInterval = Date().timeIntervalSince1970) -> Float {
        lock.lock()
        defer { lock.unlock() }
        guard let reading = readings[participantID] else { return 0 }
        return Self.decayed(reading.level, age: now - reading.at)
    }

    func all(now: TimeInterval = Date().timeIntervalSince1970) -> [String: Float] {
        lock.lock()
        defer { lock.unlock() }
        return readings.mapValues { Self.decayed($0.level, age: now - $0.at) }
    }

    func remove(_ participantID: String) {
        lock.lock()
        readings[participantID] = nil
        lock.unlock()
    }

    func clear() {
        lock.lock()
        readings.removeAll()
        everMeasured = false
        lock.unlock()
    }

    nonisolated static func decayed(_ level: Float, age: TimeInterval) -> Float {
        guard age > 0 else { return level }
        let halfLives = age / silenceHalfLife
        return level * powf(0.5, Float(halfLives))
    }
}
