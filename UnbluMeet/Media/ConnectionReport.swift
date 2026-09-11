import Foundation
import LiveKit

/// A snapshot of how the call is actually going, for the connection panel.
struct ConnectionReport: Sendable, Equatable {
    struct Line: Sendable, Equatable, Identifiable {
        let id: String
        let label: String
        let value: String
        var warning = false
    }
    struct Section: Sendable, Equatable, Identifiable {
        let id: String
        let title: String
        let lines: [Line]
    }

    var sections: [Section] = []

    var plainText: String {
        sections.map { section in
            ([section.title] + section.lines.map { "  \($0.label): \($0.value)" })
                .joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    // MARK: - Formatting

    nonisolated static func bitrate(bytes: UInt64?, over seconds: TimeInterval) -> String {
        guard let bytes, seconds > 0 else { return "—" }
        return format(bitsPerSecond: Double(bytes) * 8 / seconds)
    }

    nonisolated static func format(bitsPerSecond bits: Double?) -> String {
        guard let bits else { return "—" }
        if bits >= 1_000_000 { return String(format: "%.1f Mbps", bits / 1_000_000) }
        if bits >= 1_000 { return String(format: "%.0f kbps", bits / 1_000) }
        return String(format: "%.0f bps", bits)
    }

    nonisolated static func milliseconds(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        return String(format: "%.0f ms", seconds * 1000)
    }

    /// Round-trip time worth worrying about. Anything past a fifth of a second
    /// is audible as delay in a conversation.
    nonisolated static func isSlow(roundTrip seconds: Double?) -> Bool {
        guard let seconds else { return false }
        return seconds > 0.2
    }

    /// Packet loss as a share of what was expected.
    nonisolated static func lossPercent(lost: UInt64?, received: UInt64?) -> Double? {
        guard let lost, let received else { return nil }
        let total = Double(lost) + Double(received)
        guard total > 0 else { return nil }
        return Double(lost) / total * 100
    }

    nonisolated static func lossText(lost: UInt64?, received: UInt64?) -> String {
        guard let percent = lossPercent(lost: lost, received: received) else { return "—" }
        return String(format: "%.1f%% (%llu lost)", percent, lost ?? 0)
    }

    /// One percent starts to be audible; five is a bad call.
    nonisolated static func isLossy(lost: UInt64?, received: UInt64?) -> Bool {
        (lossPercent(lost: lost, received: received) ?? 0) >= 1
    }

    nonisolated static func describe(_ quality: ConnectionQuality) -> String {
        switch quality {
        case .excellent: "excellent"
        case .good: "good"
        case .poor: "poor"
        case .lost: "lost"
        case .unknown: "unknown"
        @unknown default: "unknown"
        }
    }

    nonisolated static func isPoor(_ quality: ConnectionQuality) -> Bool {
        quality == .poor || quality == .lost
    }

    /// "relay" means the media is going through a TURN server rather than
    /// directly, which usually shows up as extra latency.
    nonisolated static func describeCandidate(_ candidate: IceCandidateStatistics?) -> String {
        guard let candidate else { return "—" }
        let type = candidate.candidateType.map { "\($0)" } ?? "?"
        let address = candidate.address ?? "?"
        let port = candidate.port.map { ":\($0)" } ?? ""
        let transport = candidate.protocol ?? ""
        return "\(type) \(address)\(port) \(transport)".trimmingCharacters(in: .whitespaces)
    }

    /// How media reaches the server.
    ///
    /// LiveKit is an SFU, so media always passes through it — there is no
    /// peer-to-peer path to report. What the candidates tell you is how this
    /// client reaches that server.
    nonisolated static func describePath(local: IceCandidateStatistics?,
                                         remote: IceCandidateStatistics?) -> String {
        if isRelayed(local) || isRelayed(remote) {
            return "via TURN relay to the SFU"
        }
        switch local?.candidateType {
        case .host: return "direct to the SFU (same network)"
        case .srflx, .prflx: return "direct to the SFU (through NAT)"
        case .relay: return "via TURN relay to the SFU"
        case .none: return "—"
        @unknown default: return "—"
        }
    }

    /// Transport encryption, which WebRTC always applies, plus whether the
    /// media itself is additionally end-to-end encrypted.
    nonisolated static func describeEncryption(dtlsState: String?,
                                               cipher: String?,
                                               tlsVersion: String?,
                                               endToEnd: Bool) -> String {
        var parts: [String] = []
        parts.append(endToEnd ? "end-to-end + DTLS-SRTP" : "DTLS-SRTP (hop by hop)")
        if let cipher { parts.append(cipher) }
        if let tlsVersion { parts.append("TLS \(tlsVersion)") }
        if let dtlsState, dtlsState != "connected" { parts.append("dtls \(dtlsState)") }
        return parts.joined(separator: "  ")
    }

    /// Without end-to-end encryption the server can read the media. True of
    /// every ordinary SFU call, and worth saying rather than implying.
    nonisolated static func isReadableByServer(endToEnd: Bool) -> Bool { !endToEnd }

    nonisolated static func isRelayed(_ candidate: IceCandidateStatistics?) -> Bool {
        guard let type = candidate?.candidateType else { return false }
        return "\(type)".lowercased().contains("relay")
    }
}
