import SwiftUI
import AppKit

/// Draggable divider between the video stage and the chat panel.
struct ResizableDivider: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>

    /// Width when the current drag began.
    @State private var dragStart: CGFloat?

    /// Whether a resize cursor is currently pushed.
    @State private var cursorPushed = false

    var body: some View {
        Divider()
            // A one-pixel divider is a hard target; widen the hit area
            // without widening the line.
            .frame(width: 1)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside, !cursorPushed {
                    NSCursor.resizeLeftRight.push()
                    cursorPushed = true
                } else if !inside, cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .onDisappear {
                if cursorPushed {
                    NSCursor.pop()
                    cursorPushed = false
                }
            }
            .gesture(
                // Global space for the same reason as the control bar: this
                // divider moves as it is dragged, so a local origin would
                // shift underneath the gesture and the drag would fight
                // itself.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStart ?? width
                        if dragStart == nil { dragStart = start }
                        width = Self.clampWidth(start - value.translation.width, in: range)
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }

    nonisolated static func clampWidth(_ width: CGFloat,
                                       in range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(width, range.lowerBound), range.upperBound)
    }
}
