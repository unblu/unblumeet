import SwiftUI
import MetalKit

struct CompositorView: NSViewRepresentable {
    let compositor: MetalCompositor
    let participantIDs: [String]
    let mode: LayoutMode
    let focusID: String?
    let stripOffset: Int
    let onScrollZoom: (String, CGFloat, CGPoint) -> Void
    let onStripScroll: (CGFloat) -> Void
    let onPin: (String) -> Void
    /// (participant, points, strokeID, isFinal) — called continuously while
    /// drawing so the line appears under the cursor rather than on release.
    let onDraw: (String, [CGPoint], String, Bool) -> Void
    let tool: MarkTool
    let markColorIndex: Int
    let onCallout: (String, CGRect) -> Void
    /// Dragging one participant onto another rearranges them.
    let onReorder: (String, String) -> Void

    func makeNSView(context: Context) -> MTKView {
        let view = InteractiveMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0.08, 0.08, 0.09, 1.0)
        view.preferredFramesPerSecond = 30
        view.delegate = compositor
        view.compositor = compositor
        view.onScrollZoom = onScrollZoom
        view.onStripScroll = onStripScroll
        view.onPin = onPin
        view.onDraw = onDraw
        view.onCallout = onCallout
        view.onReorder = onReorder
        view.tool = tool
        compositor.localMarkColorIndex = markColorIndex
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        // Reassigned on every update, not just at creation: a closure
        // captures the view's state by value, so a stale one recomputes from
        // whatever the arrangement was when the view was first made.
        if let view = nsView as? InteractiveMTKView {
            view.tool = tool
            view.onScrollZoom = onScrollZoom
            view.onStripScroll = onStripScroll
            view.onPin = onPin
            view.onDraw = onDraw
            view.onCallout = onCallout
            view.onReorder = onReorder
        }
        compositor.localMarkColorIndex = markColorIndex
        compositor.updateLayout(participantIDs: participantIDs, mode: mode,
                                focusID: focusID, stripOffset: stripOffset)
    }
}

/// AppKit rather than SwiftUI gestures: we need the exact point in view
/// coordinates to invert the tile transform, which SwiftUI's DragGesture
/// makes awkward inside an NSViewRepresentable.
final class InteractiveMTKView: MTKView {
    var compositor: MetalCompositor?
    var onScrollZoom: ((String, CGFloat, CGPoint) -> Void)?
    var onStripScroll: ((CGFloat) -> Void)?
    var onPin: ((String) -> Void)?
    var onDraw: ((String, [CGPoint], String, Bool) -> Void)?
    var onCallout: ((String, CGRect) -> Void)?
    var onReorder: ((String, String) -> Void)?
    var tool: MarkTool = .pen

    private var strokeParticipant: String?
    private var strokePoints: [CGPoint] = []
    private var strokeID = UUID().uuidString
    private var calloutStart: CGPoint?
    private var dragSource: String?
    private var draggingPreview = false
    private var dragGrabOffset: CGSize = .zero

    override func scrollWheel(with event: NSEvent) {
        let point = flip(convert(event.locationInWindow, from: nil))

        // Over the speaker strip, scrolling pages the thumbnails; anywhere
        // else it zooms the tile under the cursor.
        if compositor?.isStripRegion(at: point, viewportSize: bounds.size) == true {
            let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            onStripScroll?(delta)
            return
        }

        guard let hit = compositor?.tileHit(at: point, viewportSize: bounds.size) else { return }

        // A mouse wheel reports about one unit per notch, a trackpad many
        // small ones.
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 0.02 : 0.25
        onScrollZoom?(hit.participantID, event.scrollingDeltaY * scale, hit.framePoint)
    }

    override func mouseDown(with event: NSEvent) {
        let point = flip(convert(event.locationInWindow, from: nil))
        let normalised = normalise(point)

        // The preview gets first claim on the click, so dragging it never
        // starts a mark on whatever is underneath.
        if let preview = compositor?.localPreviewRect(viewportSize: bounds.size),
           preview.contains(normalised) {
            draggingPreview = true
            dragGrabOffset = CGSize(width: normalised.x - preview.minX,
                                    height: normalised.y - preview.minY)
            return
        }

        guard let hit = compositor?.tileHit(at: point, viewportSize: bounds.size) else { return }

        if event.clickCount == 2 {
            onPin?(hit.participantID)
            return
        }

        // Annotation is for the thing being presented.
        guard RoomController.isScreenKey(hit.participantID) else {
            dragSource = hit.participantID
            compositor?.setDraggedTile(hit.participantID)
            return
        }

        strokeParticipant = hit.participantID
        strokePoints = [hit.framePoint]
        strokeID = UUID().uuidString
        calloutStart = tool == .callout ? hit.framePoint : nil
    }

    override func mouseDragged(with event: NSEvent) {
        let point = flip(convert(event.locationInWindow, from: nil))

        if draggingPreview {
            let normalised = normalise(point)
            compositor?.moveLocalPreview(toTopLeft:
                CGPoint(x: normalised.x - dragGrabOffset.width,
                        y: normalised.y - dragGrabOffset.height))
            return
        }

        if let source = dragSource {
            let target = compositor?.tileHit(at: point, viewportSize: bounds.size)?.participantID
            compositor?.setDropTarget(target == source ? nil : target)
            return
        }

        guard let participant = strokeParticipant,
              let hit = compositor?.tileHit(at: point, viewportSize: bounds.size),
              hit.participantID == participant else { return }

        if let start = calloutStart {
            compositor?.setPendingCallout(participantID: participant,
                                          region: Self.rect(from: start, to: hit.framePoint))
            return
        }
        strokePoints.append(hit.framePoint)
        if strokePoints.count >= 2 {
            onDraw?(participant, strokePoints, strokeID, false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            strokeParticipant = nil
            strokePoints = []
            calloutStart = nil
            draggingPreview = false
            dragSource = nil
            compositor?.setDraggedTile(nil)
            compositor?.setDropTarget(nil)
            compositor?.setPendingCallout(participantID: nil, region: .zero)
        }

        if let source = dragSource {
            let point = flip(convert(event.locationInWindow, from: nil))
            if let hit = compositor?.tileHit(at: point, viewportSize: bounds.size),
               hit.participantID != source {
                onReorder?(source, hit.participantID)
            }
            return
        }

        guard !draggingPreview, let participant = strokeParticipant else { return }

        if let start = calloutStart {
            let point = flip(convert(event.locationInWindow, from: nil))
            guard let hit = compositor?.tileHit(at: point, viewportSize: bounds.size),
                  hit.participantID == participant else { return }
            let region = Self.rect(from: start, to: hit.framePoint)
            guard Callout.isUsable(region) else { return }
            onCallout?(participant, region)
            return
        }

        guard strokePoints.count >= 2 else { return }
        onDraw?(participant, strokePoints, strokeID, true)
    }

    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    private func normalise(_ point: CGPoint) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        return CGPoint(x: point.x / bounds.width, y: point.y / bounds.height)
    }

    /// AppKit's origin is bottom-left; tile rects are top-left.
    private func flip(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
