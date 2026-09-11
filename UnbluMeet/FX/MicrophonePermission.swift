import AVFoundation

/// Microphone access, asked for up front rather than when a call starts.
enum MicrophonePermission {
    static var isGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// nonisolated: the completion arrives on an arbitrary queue, and a closure
    /// written in a @MainActor type would assert isolation and trap.
    @discardableResult
    nonisolated static func request() async -> Bool {
        if isGranted { return true }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
        }
    }
}
