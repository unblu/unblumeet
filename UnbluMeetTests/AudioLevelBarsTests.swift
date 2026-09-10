import Testing
import Foundation
import CoreGraphics
@testable import UnbluMeet

@Test func aMeterNeedsBothSoundAndAnActiveSpeaker() {
    // A stale level on a participant the server no longer counts as speaking
    // is what made several meters animate while one person talked.
    #expect(!AudioLevelBars.isAudible(0.8, speaking: false))
    // And an active speaker sending nothing audible gets no meter either.
    #expect(!AudioLevelBars.isAudible(0, speaking: true))
    #expect(!AudioLevelBars.isAudible(0.01, speaking: true))
    #expect(AudioLevelBars.isAudible(0.2, speaking: true))
    #expect(AudioLevelBars.isAudible(1, speaking: true))
}

@Test func everyBarStaysWithinItsTrack() {
    for level in stride(from: Float(-1), through: 3, by: 0.25) {
        for phase in stride(from: 0.0, through: 6.0, by: 0.25) {
            for height in AudioLevelBars.heights(for: level, phase: phase) {
                #expect(height >= 0.2 && height <= 1)
            }
        }
    }
}

@Test func theMeterMovesOverTimeRatherThanHoldingStill() {
    // The whole point: server levels arrive about twice a second and hardly
    // vary, so a meter plotted straight from them looks frozen.
    let first = AudioLevelBars.heights(for: 0.5, phase: 0)
    let later = AudioLevelBars.heights(for: 0.5, phase: 0.2)
    #expect(first != later)
}

@Test func barsDoNotMoveAsOneBlock() {
    // Same height on every bar reads as a graphic, not a meter.
    let heights = AudioLevelBars.heights(for: 0.8, phase: 1.3)
    #expect(Set(heights.map { Int($0 * 1000) }).count == heights.count)
}

@Test func aLouderVoiceSwingsFurtherThanAQuietOne() {
    func range(_ level: Float) -> CGFloat {
        let samples = stride(from: 0.0, through: 4.0, by: 0.02)
            .flatMap { AudioLevelBars.heights(for: level, phase: $0) }
        return samples.max()! - samples.min()!
    }
    #expect(range(1.0) > range(0.4))
}

@Test func aBarelyAudibleVoiceBarelyMoves() {
    // Swing tracks the level with no floor under it, so quiet reads as quiet
    // rather than as an idle animation.
    func range(_ level: Float) -> CGFloat {
        let samples = stride(from: 0.0, through: 4.0, by: 0.02)
            .flatMap { AudioLevelBars.heights(for: level, phase: $0) }
        return samples.max()! - samples.min()!
    }
    #expect(range(0.06) < 0.1)
    #expect(range(0.9) > 0.5)
}
