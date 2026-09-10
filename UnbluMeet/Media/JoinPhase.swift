import Foundation

/// What the app is doing while a conference is being joined.
enum JoinPhase: Equatable {
    case idle
    case preparing
    case signingToken
    case connecting(host: String)
    case retrying
    case enablingMicrophone
    case syncing
    case ready
    case failed(String)

    var text: String {
        switch self {
        case .idle, .preparing: "Preparing session…"
        case .signingToken: "Signing an access token…"
        case .connecting(let host): "Connecting to \(host)…"
        case .retrying: "First attempt timed out — retrying…"
        case .enablingMicrophone: "Enabling the microphone…"
        case .syncing: "Syncing participants…"
        case .ready: "Ready"
        case .failed(let message): message
        }
    }

    /// Drives a determinate bar.
    var fraction: Double {
        switch self {
        case .idle: 0
        case .preparing: 0.1
        case .signingToken: 0.25
        case .connecting: 0.45
        case .retrying: 0.45
        case .enablingMicrophone: 0.75
        case .syncing: 0.9
        case .ready: 1
        case .failed: 1
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Host only — the full URL carries credentials-adjacent noise (ports,
    /// paths) that means nothing to someone waiting to join.
    nonisolated static func host(of urlString: String) -> String {
        URL(string: urlString)?.host() ?? urlString
    }
}
