import Testing
import CoreGraphics
@testable import UnbluMeet

/// Fixtures are real rows observed from SCShareableContent on this machine:
/// 69 on-screen windows, of which 8 were things anyone would call a window.
private func window(_ title: String?, _ app: String?, _ bundle: String?,
                    layer: Int, onScreen: Bool = true,
                    size: CGSize = CGSize(width: 1200, height: 800)) -> ScreenCapture.WindowCandidate {
    ScreenCapture.WindowCandidate(title: title, appName: app, bundleID: bundle,
                                  layer: layer, isOnScreen: onScreen, size: size)
}

@Test func ordinaryApplicationWindowsAreShareable() {
    #expect(ScreenCapture.isShareableWindow(
        window("UnbluMeet — UnbluMeet.xcodeproj", "Xcode", "com.apple.dt.Xcode", layer: 0)))
    #expect(ScreenCapture.isShareableWindow(
        window("daos — -zsh — 179×68", "Terminal", "com.apple.Terminal", layer: 0)))
}

@Test func menuBarExtrasAreNotWindows() {
    // Control Center owns ~40 of these; they are what filled the old list.
    #expect(!ScreenCapture.isShareableWindow(
        window("Battery", "Control Center", "com.apple.controlcenter",
               layer: 25, size: CGSize(width: 70, height: 30))))
}

@Test func notificationCentreWidgetsAreNotWindows() {
    // Big enough to pass a size check, so the layer is what rejects them.
    #expect(!ScreenCapture.isShareableWindow(
        window("Up Next", "Notification Center", "com.apple.notificationcenterui",
               layer: -2147483601, size: CGSize(width: 360, height: 360))))
}

@Test func overlayPanelsAboveTheDocumentLayerAreRejected() {
    // Superhuman's Grammarly strip: real title, 35×1850, layer 5.
    #expect(!ScreenCapture.isShareableWindow(
        window("Grammarly", "Superhuman Web UI", "com.superhuman.web-client",
               layer: 5, size: CGSize(width: 35, height: 1850))))
}

@Test func untitledAndTinyHelperWindowsAreRejected() {
    // BetterDisplay keeps a 1×1 untitled window at layer 0.
    #expect(!ScreenCapture.isShareableWindow(
        window("", "BetterDisplay", "pro.betterdisplay.BetterDisplay",
               layer: 0, size: CGSize(width: 1, height: 1))))
    #expect(!ScreenCapture.isShareableWindow(
        window("   ", "Some App", "com.example.app", layer: 0)))
    #expect(!ScreenCapture.isShareableWindow(
        window("Tooltip", "Some App", "com.example.app",
               layer: 0, size: CGSize(width: 90, height: 40))))
}

@Test func offscreenWindowsAreRejected() {
    #expect(!ScreenCapture.isShareableWindow(
        window("Minimised", "Notes", "com.apple.Notes", layer: 0, onScreen: false)))
}

@Test func ourOwnWindowIsRejected() {
    // Sharing it back into the call mirrors the call into itself.
    #expect(!ScreenCapture.isShareableWindow(
        window("Topic 2", "UnbluMeet", "com.unblu.UnbluMeet", layer: 0)))
}
