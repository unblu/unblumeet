import SwiftUI
import Observation

/// Where the control bar has been dragged to.
@Observable
@MainActor
final class BarPosition {
    var offset: CGSize = .zero
    private var base: CGSize = .zero

    func drag(_ translation: CGSize, within bounds: CGSize) {
        offset = Self.clamp(CGSize(width: base.width + translation.width,
                                   height: base.height + translation.height),
                            within: bounds)
    }

    func endDrag() {
        base = offset
    }

    /// Keeps the bar reachable: dragged fully off screen it could never be
    /// dragged back.
    nonisolated static func clamp(_ offset: CGSize, within bounds: CGSize) -> CGSize {
        guard bounds.width > 0, bounds.height > 0 else { return offset }
        let limitX = bounds.width / 2
        let limitY = bounds.height / 2
        return CGSize(width: min(max(offset.width, -limitX), limitX),
                      height: min(max(offset.height, -limitY), limitY))
    }
}

/// Applies the drag offset in a leaf view, so the surrounding hierarchy is
/// not invalidated while dragging.
struct MovableBar<Content: View>: View {
    let position: BarPosition
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .offset(position.offset)
            // No implicit animation: the bar should track the pointer exactly
            // rather than easing towards it a frame behind.
            .transaction { $0.animation = nil }
    }
}
