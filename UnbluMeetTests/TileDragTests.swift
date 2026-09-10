import Testing
import AppKit
import Foundation
@testable import UnbluMeet

/// Drives the real view with synthetic mouse events, because the drag logic
/// lives in AppKit event handling where a unit test of the pure parts would
/// prove nothing about whether a drag actually reaches it.
@MainActor
private func dragTest(from: CGPoint, to: CGPoint) -> (source: String, target: String)? {
    let view = InteractiveMTKView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless],
                          backing: .buffered, defer: false)
    window.contentView = view

    guard let compositor = MetalCompositor(store: FrameStore(), markStore: MarkStore()) else {
        return nil
    }
    compositor.updateLayout(participantIDs: ["anna", "marek", "sofia", "tomas"],
                            mode: .grid, focusID: nil)
    view.compositor = compositor

    var reordered: (String, String)?
    view.onReorder = { reordered = ($0, $1) }

    func event(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
        // AppKit's origin is bottom-left; the view flips for tile coordinates.
        NSEvent.mouseEvent(with: type,
                           location: CGPoint(x: point.x, y: view.bounds.height - point.y),
                           modifierFlags: [], timestamp: 0,
                           windowNumber: window.windowNumber, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    view.mouseDown(with: event(.leftMouseDown, from))
    view.mouseDragged(with: event(.leftMouseDragged, to))
    view.mouseUp(with: event(.leftMouseUp, to))
    return reordered
}

@MainActor
@Test func draggingOneTileOntoAnotherReportsBoth() {
    // Four tiles in a 2x2 grid over 800x600: top-left and bottom-right.
    let result = dragTest(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 600, y: 450))
    #expect(result != nil)
    #expect(result?.source != result?.target)
}

@MainActor
@Test func releasingOnTheSameTileChangesNothing() {
    #expect(dragTest(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 210, y: 160)) == nil)
}

@MainActor
@Test func draggingOutsideAnyTileChangesNothing() {
    #expect(dragTest(from: CGPoint(x: 200, y: 150), to: CGPoint(x: 5000, y: 5000)) == nil)
}

@MainActor
@Test func aSecondDragBuildsOnTheFirstRatherThanStartingOver() {
    // The arrangement lives in the view's state, and a callback captured once
    // at creation would recompute from the order as it was then.
    var order = ["anna", "marek", "sofia"]
    func drag(_ source: String, onto target: String) {
        order = TileOrder.moving(source, onto: target, in: TileOrder.apply(order, to: ["anna", "marek", "sofia"]))
    }
    drag("sofia", onto: "anna")
    #expect(order == ["sofia", "anna", "marek"])
    drag("marek", onto: "sofia")
    #expect(order == ["marek", "sofia", "anna"])
}
