import SwiftUI

/// A live level meter, shown on a tile while someone is talking.
struct AudioLevelBars: View {
    let level: Float
    var height: CGFloat = 11

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(Array(Self.heights(for: level, phase: phase).enumerated()), id: \.offset) { _, fraction in
                    Capsule()
                        .fill(.white)
                        .frame(width: 2.5, height: max(2, height * fraction))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
    }

    /// Per-bar height, 0…1.
    nonisolated static let audibleLevel: Float = 0.05

    /// Whether to show a meter at all.
    nonisolated static func isAudible(_ level: Float, speaking: Bool) -> Bool {
        speaking && level >= audibleLevel
    }

    nonisolated static func heights(for level: Float, phase: TimeInterval, bars: Int = 3) -> [CGFloat] {
        // Straight from the level, with no floor: the swing has to reflect
        // how loud they actually are, or every voice looks identical.
        let swing = CGFloat(min(max(level, 0), 1))
        let rates: [Double] = [7.3, 9.1, 5.7]
        let offsets: [Double] = [0, 1.7, 3.1]

        return (0 ..< bars).map { index in
            let wave = sin(phase * rates[index % rates.count] + offsets[index % offsets.count])
            let normalised = (wave + 1) / 2                       // 0…1
            return min(max(0.2 + CGFloat(normalised) * swing, 0.2), 1)
        }
    }
}
