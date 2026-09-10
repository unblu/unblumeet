import ScreenCaptureKit
import CoreGraphics
import Observation

/// What can be shared, with previews.
@Observable
@MainActor
final class ShareCatalog {
    private(set) var targets: [ShareTarget] = []
    private(set) var thumbnails: [String: CGImage] = [:]
    private(set) var error: String?
    private(set) var isLoading = false
    /// Set when the failure is a permission problem, so the picker can offer
    /// the System Settings button instead of a bare error.
    private(set) var needsPermission = false

    private var loadTask: Task<Void, Never>?

    var screens: [ShareTarget] { targets.filter { $0.kind == .display } }
    var windows: [ShareTarget] { targets.filter { $0.kind == .window } }

    func load() {
        loadTask?.cancel()
        loadTask = Task { await run() }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func run() async {
        isLoading = true
        error = nil
        needsPermission = false
        defer { isLoading = false }

        // Ask TCC directly first.
        if !ScreenPermission.isGranted, !ScreenPermission.request() {
            needsPermission = true
            error = ScreenPermission.diagnosis(bundlePath: ScreenPermission.bundlePath)
            return
        }

        let content: SCShareableContent
        do {
            content = try await ScreenCapture.shareableContent()
            targets = try await ScreenCapture.availableTargets()
        } catch {
            needsPermission = true
            self.error = """
                \(ScreenPermission.diagnosis(bundlePath: ScreenPermission.bundlePath))

                \(error.localizedDescription)
                """
            return
        }

        // Displays first: they are the common case and the only ones that
        // support a region, so they should be usable before the window
        // thumbnails finish.
        for target in targets {
            if Task.isCancelled { return }
            let width = target.kind == .display ? 480 : 320
            if let image = await ScreenCapture.thumbnail(for: target, in: content, maxWidth: width) {
                thumbnails[target.id] = image
            }
        }
    }
}
