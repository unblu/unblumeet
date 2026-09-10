import SwiftUI

/// Annotation tools, shown only while a screen share is on the stage.
struct MarkToolbar: View {
    @Binding var tool: MarkTool
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            ForEach(MarkTool.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tool = option }
                } label: {
                    Image(systemName: option.symbol)
                        .hitArea(width: 32, height: 32)
                        .background(tool == option ? Color.accentColor : .clear, in: Circle())
                        .foregroundStyle(tool == option ? .white : .primary)
                }
                .buttonStyle(PressableButtonStyle())
                .help(option.help)
            }

            Divider().frame(width: 22)

            Button(action: onClear) {
                Image(systemName: "eraser")
                    .hitArea(width: 32, height: 32)
            }
            .buttonStyle(PressableButtonStyle())
            .help("Clear all marks")
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
