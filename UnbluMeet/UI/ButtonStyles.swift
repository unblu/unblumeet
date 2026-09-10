import SwiftUI

/// Press feedback for the floating controls.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.65 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.55),
                       value: configuration.isPressed)
    }
}

extension View {
    /// Makes the whole frame clickable, not just the glyph inside it.
    func hitArea(width: CGFloat, height: CGFloat) -> some View {
        frame(width: width, height: height).contentShape(Rectangle())
    }
}
