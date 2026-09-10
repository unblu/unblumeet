import AppKit
import CoreGraphics

/// Drag-to-pick a rectangle on a real display, like the system screenshot
/// tool.
@MainActor
enum RegionSelector {
    /// Returns the chosen rect in display points from the top-left corner —
    /// the space SCStreamConfiguration.sourceRect uses — or nil if cancelled.
    static func selectRegion(displayID: CGDirectDisplayID) async -> CGRect? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
            let window = OverlayWindow(contentRect: screen.frame,
                                       styleMask: .borderless,
                                       backing: .buffered,
                                       defer: false)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            var resumed = false
            let view = SelectionView(bounds: CGRect(origin: .zero, size: screen.frame.size)) { rect in
                guard !resumed else { return }
                resumed = true
                window.orderOut(nil)
                continuation.resume(returning: rect)
            }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            window.makeFirstResponder(view)
        }
    }

    /// Rect between two drag points, clamped to the display and rejected if
    /// it is too small to be a deliberate selection.
    nonisolated static func rect(from start: CGPoint, to end: CGPoint,
                                 within bounds: CGSize,
                                 minimumSide: CGFloat = 24) -> CGRect? {
        let raw = CGRect(x: min(start.x, end.x),
                         y: min(start.y, end.y),
                         width: abs(end.x - start.x),
                         height: abs(end.y - start.y))
        let clamped = raw.intersection(CGRect(origin: .zero, size: bounds))
        guard clamped.width >= minimumSide, clamped.height >= minimumSide else { return nil }

        // Even pixel dimensions: video encoders reject odd ones.
        return CGRect(x: clamped.origin.x.rounded(.down),
                      y: clamped.origin.y.rounded(.down),
                      width: (clamped.width / 2).rounded(.down) * 2,
                      height: (clamped.height / 2).rounded(.down) * 2)
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

/// Borderless windows refuse key status by default, which would swallow Escape.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let onFinish: (CGRect?) -> Void
    private let selectableBounds: CGRect
    private var start: CGPoint?
    private var current: CGPoint?

    init(bounds: CGRect, onFinish: @escaping (CGRect?) -> Void) {
        self.onFinish = onFinish
        self.selectableBounds = bounds
        super.init(frame: bounds)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Top-left origin, so a rect here is already in sourceRect's space.
    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let start, let current else { return onFinish(nil) }
        onFinish(RegionSelector.rect(from: start, to: current,
                                     within: selectableBounds.size))
    }

    override func keyDown(with event: NSEvent) {
        // 53 is Escape.
        if event.keyCode == 53 { onFinish(nil) } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.45).setFill()
        bounds.fill()

        guard let start, let current else {
            drawHint()
            return
        }
        let selection = CGRect(x: min(start.x, current.x),
                               y: min(start.y, current.y),
                               width: abs(current.x - start.x),
                               height: abs(current.y - start.y))

        NSGraphicsContext.current?.compositingOperation = .clear
        selection.fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        NSColor.white.setStroke()
        let border = NSBezierPath(rect: selection)
        border.lineWidth = 2
        border.stroke()

        let label = "\(Int(selection.width)) × \(Int(selection.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        let origin = CGPoint(x: selection.midX - size.width / 2,
                             y: max(4, selection.minY - size.height - 6))
        NSColor.black.withAlphaComponent(0.7).setFill()
        CGRect(origin: CGPoint(x: origin.x - 6, y: origin.y - 3),
               size: CGSize(width: size.width + 12, height: size.height + 6)).fill()
        label.draw(at: origin, withAttributes: attributes)
    }

    private func drawHint() {
        let hint = "Drag to choose the area to share — Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = hint.size(withAttributes: attributes)
        hint.draw(at: CGPoint(x: bounds.midX - size.width / 2,
                              y: bounds.midY - size.height / 2),
                  withAttributes: attributes)
    }
}
