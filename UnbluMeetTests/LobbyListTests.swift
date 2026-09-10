import Testing
import Foundation
@testable import UnbluMeet

private func conversation(participants: Int, bots: Int, created: Date?, host: String? = nil) -> ConversationData {
    let recipient = host.map { #"{"id":"h1","displayName":"\#($0)","personType":"AGENT"}"# } ?? "null"
    let json = """
    {"id":"c1","topic":"[UnbluMeet] Standup","state":"ACTIVE",
     "creationTimestamp":\(created.map { String(Int64($0.timeIntervalSince1970 * 1000)) } ?? "null"),
     "participants":[\((0..<participants).map { _ in #"{"personId":"p","state":"ACTIVE"}"# }.joined(separator: ","))],
     "botParticipants":[\((0..<bots).map { _ in #"{"personId":"b"}"# }.joined(separator: ","))],
     "recipient":\(recipient)}
    """
    return try! JSONDecoder().decode(ConversationData.self, from: Data(json.utf8))
}

@Test func memberCountAddsAgentsAndBots() {
    // UnbluMeet users join as bot persons, so both lists count.
    #expect(conversation(participants: 1, bots: 2, created: nil).memberCount == 3)
}

@Test func missingParticipantListsCountAsZero() {
    let json = #"{"id":"c2","topic":null,"state":null,"creationTimestamp":null}"#
    let conv = try! JSONDecoder().decode(ConversationData.self, from: Data(json.utf8))
    #expect(conv.memberCount == 0)
}

@Test func hostComesFromTheSearchResponse() {
    #expect(conversation(participants: 1, bots: 0, created: nil, host: "Super Admin").hostName == "Super Admin")
}

@Test func hostFallsBackWhenTheResponseOmitsIt() {
    #expect(conversation(participants: 1, bots: 0, created: nil).hostName == "—")
}

@Test func memberColumnUsesSingularForOnePerson() {
    #expect(ConferenceRow.peopleText(1) == "1 person")
    #expect(ConferenceRow.peopleText(3) == "3 people")
}

@Test func ageColumnShowsADashWhenTheTimestampIsMissing() {
    #expect(ConferenceRow.ageText(nil) == "—")
    #expect(ConferenceRow.ageText(Date().addingTimeInterval(-3600)) != "—")
}

@Test func avatarInitialsComeFromTheFirstTwoWords() {
    #expect(ConferenceRow.initials(forTopic: "Daily Standup Meeting") == "DS")
    #expect(ConferenceRow.initials(forTopic: "Topic1") == "T")
    #expect(ConferenceRow.initials(forTopic: "") == "#")
}

@Test func avatarTintIsStableForTheSameConversation() {
    // Deliberately not String.hashValue: it is seeded per process, so colours
    // would change between launches.
    #expect(ConferenceRow.tint(for: "wH0ySAL0RcCUhb8g370rew") == ConferenceRow.tint(for: "wH0ySAL0RcCUhb8g370rew"))
}
