import ScreenCaptureKit
import CoreVideo
import os

/// One thing the user can share: a whole display, part of one, or a window.
struct ShareTarget: Identifiable, Sendable, Equatable {
    enum Kind: Sendable { case display, window }

    let id: String
    let name: String
    let kind: Kind
    let displayID: CGDirectDisplayID?
    let windowID: CGWindowID?
    /// Size in points — of the display, or of the window's frame.
    let size: CGSize
    /// Sub-rectangle of the display to share, in points from its top-left
    /// corner.
    var region: CGRect?

    var label: String {
        guard let region else { return name }
        return "\(name) — region \(Int(region.width))×\(Int(region.height))"
    }
}

/// Captures a display or window with ScreenCaptureKit and emits
/// CVPixelBuffers, matching CameraCapture so the publish path can be shared.
final class ScreenCapture: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "com.unblu.UnbluMeet.screen")
    private let onFrame: @Sendable (CVPixelBuffer) -> Void
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "ScreenCapture")

    init(onFrame: @escaping @Sendable (CVPixelBuffer) -> Void) {
        self.onFrame = onFrame
        super.init()
    }

    /// One window as the filter below sees it.
    struct WindowCandidate: Sendable {
        let title: String?
        let appName: String?
        let bundleID: String?
        let layer: Int
        let isOnScreen: Bool
        let size: CGSize
    }

    /// Bundles that own on-screen windows nobody means to share: system
    /// chrome and our own window, which would mirror into itself.
    static let excludedBundleIDs: Set<String> = [
        "com.unblu.UnbluMeet",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.Spotlight",
        "com.apple.wallpaper.agent",
        "com.apple.screencaptureui",
    ]

    /// Whether a window is something a person would recognise and choose.
    nonisolated static func isShareableWindow(_ window: WindowCandidate) -> Bool {
        guard window.isOnScreen, window.layer == 0 else { return false }
        guard let title = window.title, !title.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
        guard let appName = window.appName, !appName.isEmpty else { return false }
        if let bundleID = window.bundleID, excludedBundleIDs.contains(bundleID) { return false }
        // Tooltips, badges and offscreen scratch windows.
        return window.size.width >= 120 && window.size.height >= 80
    }

    /// Displays and on-screen windows the user could share.
    static func availableTargets() async throws -> [ShareTarget] {
        let content = try await shareableContent()

        let displays = content.displays.enumerated().map { index, display in
            ShareTarget(id: "display-\(display.displayID)",
                        name: "Display \(index + 1) (\(display.width)×\(display.height))",
                        kind: .display,
                        displayID: display.displayID,
                        windowID: nil,
                        size: CGSize(width: display.width, height: display.height))
        }

        let windows = content.windows
            .filter {
                isShareableWindow(WindowCandidate(
                    title: $0.title,
                    appName: $0.owningApplication?.applicationName,
                    bundleID: $0.owningApplication?.bundleIdentifier,
                    layer: $0.windowLayer,
                    isOnScreen: $0.isOnScreen,
                    size: $0.frame.size))
            }
            // Grouped by app, largest first within an app: the main window is
            // almost always the biggest one.
            .sorted {
                let leftApp = $0.owningApplication?.applicationName ?? ""
                let rightApp = $1.owningApplication?.applicationName ?? ""
                if leftApp != rightApp {
                    return leftApp.localizedCaseInsensitiveCompare(rightApp) == .orderedAscending
                }
                return $0.frame.width * $0.frame.height > $1.frame.width * $1.frame.height
            }
            .map { window in
                ShareTarget(
                    id: "window-\(window.windowID)",
                    name: "\(window.owningApplication?.applicationName ?? "?") — \(window.title ?? "")",
                    kind: .window,
                    displayID: nil,
                    windowID: window.windowID,
                    size: window.frame.size)
            }

        return displays + windows
    }

    /// A still of one target, for the picker.
    static func thumbnail(for target: ShareTarget, in content: SCShareableContent,
                          maxWidth: Int) async -> CGImage? {
        let filter: SCContentFilter
        switch target.kind {
        case .display:
            guard let display = content.displays.first(where: { $0.displayID == target.displayID })
            else { return nil }
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        case .window:
            guard let window = content.windows.first(where: { $0.windowID == target.windowID })
            else { return nil }
            filter = SCContentFilter(desktopIndependentWindow: window)
        }

        let rect = filter.contentRect
        guard rect.width > 0, rect.height > 0 else { return nil }

        let configuration = SCStreamConfiguration()
        configuration.width = maxWidth
        configuration.height = max(1, Int(CGFloat(maxWidth) * rect.height / rect.width))
        configuration.showsCursor = false
        configuration.captureResolution = .nominal

        return try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                           configuration: configuration)
    }

    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    }

    func start(target: ShareTarget) async throws {
        let content = try await Self.shareableContent()

        let filter: SCContentFilter
        switch target.kind {
        case .display:
            guard let display = content.displays.first(where: { $0.displayID == target.displayID }) else {
                throw ScreenCaptureError.targetGone
            }
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        case .window:
            guard let window = content.windows.first(where: { $0.windowID == target.windowID }) else {
                throw ScreenCaptureError.targetGone
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
        }

        let configuration = SCStreamConfiguration()
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 5
        configuration.showsCursor = true
        let scale = CGFloat(filter.pointPixelScale)
        if let region = target.region, target.kind == .display {
            // sourceRect is in points from the display's top-left corner —
            // the same space RegionSelector reports.
            configuration.sourceRect = region
            configuration.width = Int(region.width * scale)
            configuration.height = Int(region.height * scale)
        } else {
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }
}

enum ScreenCaptureError: Error {
    case targetGone
}

extension ScreenCapture: SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        onFrame(pixelBuffer)
    }
}
