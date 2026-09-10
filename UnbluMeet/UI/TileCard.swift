import SwiftUI

/// What a grid cell shows when its participant has no video.
struct TileCard: View {
    let name: String
    let speaking: Bool
    let muted: Bool
    var level: Float = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.07))

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.3))
                    Text(Self.initials(of: name))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)

                if muted {
                    Image(systemName: "mic.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                } else if AudioLevelBars.isAudible(level, speaking: speaking) {
                    AudioLevelBars(level: level, height: 14)
                } else {
                    Image(systemName: "video.slash")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(speaking ? Color.green : .clear, lineWidth: 3)
        )
    }

    /// Up to two initials, so a cell is identifiable without a camera.
    nonisolated static func initials(of name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "?" : letters.joined().uppercased()
    }
}

/// Step-by-step progress while joining.
struct JoinProgressView: View {
    let topic: String
    let phase: JoinPhase
    /// Only offered once something has gone wrong; a failure with no way
    /// forward leaves the window as a dead end.
    var onRetry: (() -> Void)?
    var onLeave: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(phase.isFailure ? "Could not join \(topic)" : "Joining \(topic)")
                .font(.headline)

            ProgressView(value: phase.fraction)
                .progressViewStyle(.linear)
                .frame(width: 320)

            HStack(spacing: 8) {
                if !phase.isFailure {
                    ProgressView().controlSize(.small)
                }
                Text(phase.text)
                    .font(.callout)
                    .foregroundStyle(phase.isFailure ? .orange : .secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 320, alignment: .leading)

            if phase.isFailure, onRetry != nil || onLeave != nil {
                HStack {
                    if let onRetry {
                        Button("Try again", action: onRetry)
                            .keyboardShortcut(.defaultAction)
                    }
                    if let onLeave {
                        Button("Leave", action: onLeave)
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Shown once connected and alone in the room.
struct EmptyRoomView: View {
    let topic: String
    let cameraOn: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text("You're the only one in \(topic)")
                .font(.title3.weight(.medium))

            Text(cameraOn
                 ? "Waiting for others to join."
                 : "Waiting for others to join. Your camera is off — turn it on below to be seen.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .foregroundStyle(.white)
        .padding(26)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}
