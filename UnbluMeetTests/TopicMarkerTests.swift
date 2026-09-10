import Testing
@testable import UnbluMeet

@Test func markedTopicCarriesTheMarker() {
    let marked = ConferenceDirectory.markedTopic("Standup")
    #expect(marked.contains(ConferenceDirectory.topicMarker))
    #expect(marked.contains("Standup"))
}

@Test func displayStripsTheMarker() {
    let marked = ConferenceDirectory.markedTopic("Standup")
    #expect(ConferenceDirectory.displayTopic(marked) == "Standup")
}

@Test func displayLeavesForeignTopicsAlone() {
    // A conversation created outside UnbluMeet keeps its topic verbatim.
    #expect(ConferenceDirectory.displayTopic("Customer chat") == "Customer chat")
}

@Test func displayHandlesAMissingTopic() {
    #expect(ConferenceDirectory.displayTopic(nil) == "(no topic)")
}

@Test func markingIsIdempotentThroughDisplay() {
    let once = ConferenceDirectory.markedTopic("Design review")
    #expect(ConferenceDirectory.displayTopic(once) == "Design review")
}
