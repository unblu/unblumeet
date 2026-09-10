import Testing
import Foundation
@testable import UnbluMeet

@Test func speechRegistersWellAboveTheAudibleThreshold() {
    let meters = AudioMeters()
    // Levels observed from a live room: speech peaks around 0.4 to 0.7.
    meters.record(level: 0.6, for: "anna", now: 1000)
    #expect(meters.level(for: "anna", now: 1000) >= AudioLevelBars.audibleLevel)
}

@Test func digitalSilenceStaysBelowTheThreshold() {
    let meters = AudioMeters()
    meters.record(level: 0.004, for: "anna", now: 1000)
    #expect(!AudioLevelBars.isAudible(meters.level(for: "anna", now: 1000), speaking: true))
}

@Test func aParticipantWhoNeverSpokeHasNoLevel() {
    #expect(AudioMeters().level(for: "nobody", now: 1000) == 0)
}

@Test func levelsFallAwayOnceReadingsStopArriving() {
    // A safety net for a track that disappears between polls; normally the
    // statistics keep reporting and drop to zero on their own.
    let meters = AudioMeters()
    meters.record(level: 0.9, for: "anna", now: 1000)
    let immediately = meters.level(for: "anna", now: 1000)
    #expect(meters.level(for: "anna", now: 1000 + AudioMeters.silenceHalfLife) < immediately)
    #expect(meters.level(for: "anna", now: 1004) < AudioLevelBars.audibleLevel)
}

@Test func aHalfLifeHalvesTheLevel() {
    #expect(abs(AudioMeters.decayed(1, age: AudioMeters.silenceHalfLife) - 0.5) < 0.001)
    #expect(abs(AudioMeters.decayed(1, age: AudioMeters.silenceHalfLife * 2) - 0.25) < 0.001)
    #expect(AudioMeters.decayed(0.4, age: 0) == 0.4)
}

@Test func theMeterRisesAtOnceButFallsGently() {
    // A meter that drops instantly between syllables reads as broken.
    let meters = AudioMeters()
    meters.record(level: 0.6, for: "anna", now: 1000)
    let loud = meters.level(for: "anna", now: 1000)
    meters.record(level: 0, for: "anna", now: 1000)
    let after = meters.level(for: "anna", now: 1000)
    #expect(after < loud)
    #expect(after > 0)
}

@Test func participantsAreMeasuredIndependently() {
    // The whole complaint: one voice must not light up three meters.
    let meters = AudioMeters()
    meters.record(level: 0.68, for: "anna", now: 1000)
    meters.record(level: 0.006, for: "marek", now: 1000)
    let levels = meters.all(now: 1000)
    #expect(AudioLevelBars.isAudible(levels["anna"] ?? 0, speaking: true))
    #expect(!AudioLevelBars.isAudible(levels["marek"] ?? 0, speaking: true))
}

@Test func removingAParticipantForgetsTheirLevel() {
    let meters = AudioMeters()
    meters.record(level: 0.9, for: "anna", now: 1000)
    meters.remove("anna")
    #expect(meters.level(for: "anna", now: 1000) == 0)
}

@Test func metersReportWhetherTheyHaveEverHeardAnything() {
    // WebRTC feeds an audio sink only while playback runs.
    let meters = AudioMeters()
    #expect(!meters.hasReadings)
    meters.record(level: 0.4, for: "anna", now: 1000)
    #expect(meters.hasReadings)
    // Still true once the level has decayed away — the mechanism works, the
    // room is merely quiet.
    #expect(meters.level(for: "anna", now: 1020) < AudioLevelBars.audibleLevel)
    #expect(meters.hasReadings)
}

@Test func clearingResetsTheHavingHeardAnythingFlag() {
    let meters = AudioMeters()
    meters.record(level: 0.4, for: "anna", now: 1000)
    meters.clear()
    #expect(!meters.hasReadings)
}
