import Testing
import Foundation
@testable import UnbluMeet

@Test func theFirstVoiceTakesTheFloorAfterTheDwell() {
    var switcher = SpeakerSwitcher()
    #expect(switcher.update(speaking: "anna", now: 0) == nil)
    #expect(switcher.update(speaking: "anna", now: 0.5) == nil)
    #expect(switcher.update(speaking: "anna", now: SpeakerSwitcher.dwell) == "anna")
}

@Test func aBackChannelInterjectionDoesNotStealTheLayout() {
    // Someone saying "mhm" while another person talks must not throw the big
    // tile across the room.
    var switcher = SpeakerSwitcher()
    _ = switcher.update(speaking: "anna", now: 0)
    #expect(switcher.update(speaking: "anna", now: 2) == "anna")
    #expect(switcher.update(speaking: "marek", now: 2.1) == "anna")
    #expect(switcher.update(speaking: "marek", now: 2.5) == "anna")   // too brief
    #expect(switcher.update(speaking: "anna", now: 2.6) == "anna")
}

@Test func aSustainedNewSpeakerTakesOver() {
    var switcher = SpeakerSwitcher()
    _ = switcher.update(speaking: "anna", now: 0)
    _ = switcher.update(speaking: "anna", now: 2)
    _ = switcher.update(speaking: "marek", now: 3)
    #expect(switcher.update(speaking: "marek", now: 3 + SpeakerSwitcher.dwell) == "marek")
}

@Test func silenceKeepsTheLastSpeakerOnScreen() {
    // Otherwise the layout empties in every pause.
    var switcher = SpeakerSwitcher()
    _ = switcher.update(speaking: "anna", now: 0)
    _ = switcher.update(speaking: "anna", now: 2)
    #expect(switcher.update(speaking: nil, now: 3) == "anna")
    #expect(switcher.update(speaking: nil, now: 30) == "anna")
}

@Test func silenceAlsoCancelsAHalfFinishedTakeover() {
    var switcher = SpeakerSwitcher()
    _ = switcher.update(speaking: "anna", now: 0)
    _ = switcher.update(speaking: "anna", now: 2)
    _ = switcher.update(speaking: "marek", now: 3)      // starts the clock
    _ = switcher.update(speaking: nil, now: 3.2)        // stops talking
    #expect(switcher.update(speaking: "marek", now: 4.0) == "anna")
}
