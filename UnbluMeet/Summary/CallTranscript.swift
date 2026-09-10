import Foundation

struct TranscriptLine: Sendable, Equatable {
    let speaker: String
    let text: String
    let at: TimeInterval
}

/// What has been said, as recognised speech.
final class CallTranscript: @unchecked Sendable {
    private var lines: [TranscriptLine] = []
    private let lock = NSLock()

    func append(speaker: String, text: String, at: TimeInterval = Date().timeIntervalSince1970) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        // Speech recognition re-reports a growing transcript for one
        // utterance; the last line is replaced when the new text extends it
        // rather than appending the same sentence half a dozen times.
        if let last = lines.last, last.speaker == speaker, trimmed.hasPrefix(last.text) {
            // Timestamped now, not when the utterance began: the summariser
            // takes lines after a cursor, so a line that keeps its original
            // time would never be offered again once a cycle had passed it,
            // and everything said after that point in the same breath would
            // be silently dropped.
            lines[lines.count - 1] = TranscriptLine(speaker: speaker, text: trimmed, at: at)
        } else {
            lines.append(TranscriptLine(speaker: speaker, text: trimmed, at: at))
        }
        lock.unlock()
    }

    func lines(after cursor: TimeInterval) -> [TranscriptLine] {
        lock.lock()
        defer { lock.unlock() }
        return lines.filter { $0.at > cursor }
    }

    var latestTimestamp: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return lines.last?.at ?? 0
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return lines.isEmpty
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }

    nonisolated static func format(_ lines: [TranscriptLine]) -> String {
        lines.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
    }

    nonisolated static func wordCount(_ lines: [TranscriptLine]) -> Int {
        lines.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
    }

    /// Keeps the most recent words, dropping whole lines from the front.
    nonisolated static func trimmed(_ lines: [TranscriptLine], toWords limit: Int) -> [TranscriptLine] {
        guard wordCount(lines) > limit else { return lines }
        var kept: [TranscriptLine] = []
        var total = 0
        for line in lines.reversed() {
            let words = line.text.split(whereSeparator: \.isWhitespace).count
            if total + words > limit, !kept.isEmpty { break }
            kept.insert(line, at: 0)
            total += words
        }
        return kept
    }
}
