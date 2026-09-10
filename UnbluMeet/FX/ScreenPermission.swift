import CoreGraphics
import AppKit

/// Screen Recording permission, asked about directly instead of inferred from
/// a failed capture.
enum ScreenPermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Prompts if the user has never decided.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    @MainActor
    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// Why permission is missing, and what will actually fix it.
    nonisolated static func diagnosis(bundlePath: String) -> String {
        if bundlePath.contains("/AppTranslocation/") {
            return """
                macOS is running UnbluMeet from a temporary read-only copy, because the app \
                was downloaded or copied from another Mac. That copy gets a new location on \
                every launch, so a Screen Recording grant can never stick to it.

                Fix: quit UnbluMeet, drag UnbluMeet.app into /Applications, and launch it \
                from there. If it still fails, run in Terminal:

                xattr -dr com.apple.quarantine /Applications/UnbluMeet.app
                """
        }
        return """
            Screen Recording is not granted to this build.

            If UnbluMeet already appears enabled in System Settings → Privacy & Security → \
            Screen & System Audio Recording, the entry is stale — it was granted to an \
            earlier build of the binary. Quit UnbluMeet and run in Terminal:

            tccutil reset ScreenCapture com.unblu.UnbluMeet

            then launch UnbluMeet and allow the prompt.
            """
    }

    /// The running bundle's path, for the diagnosis above.
    nonisolated static var bundlePath: String { Bundle.main.bundleURL.path }
}
