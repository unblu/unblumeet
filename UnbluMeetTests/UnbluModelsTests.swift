import Testing
import Foundation
@testable import UnbluMeet

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

@Test func decodesBotPersonFromCreateOrUpdateBot() throws {
    // Captured from POST /persons/createOrUpdateBot
    let json = """
    {"$_type":"PersonData","id":"6nD26Li8QumI1YDkCc08bQ","accountId":"wZvcAnbBSpOps9oteH-Oxw",
     "personSource":"VIRTUAL","sourceId":"unblumeet-probe","firstName":"UnbluMeet",
     "lastName":"Probe","displayName":"UnbluMeet Probe","personType":"BOT",
     "authorizationRole":"REGISTERED_USER","archived":false}
    """
    let person = try decode(PersonData.self, json)
    #expect(person.id == "6nD26Li8QumI1YDkCc08bQ")
    #expect(person.displayName == "UnbluMeet Probe")
    #expect(person.personType == "BOT")
}

@Test func decodesAgentSearchResult() throws {
    // Captured from POST /persons/searchAgents
    let json = """
    {"$_type":"PersonResult","items":[
      {"$_type":"PersonData","id":"mvhynBX2RZKeRxSumW5INQ","displayName":"Super Admin","personType":"AGENT"},
      {"$_type":"PersonData","id":"CzeDlIO0S2y0HMaRTxp7_w","displayName":"John Doe","personType":"AGENT"}]}
    """
    let result = try decode(PersonResult.self, json)
    #expect(result.items.count == 2)
    #expect(result.items.first?.id == "mvhynBX2RZKeRxSumW5INQ")
    #expect(result.items.allSatisfy { $0.personType == "AGENT" })
}

@Test func decodesConversationSearchResult() throws {
    // Captured from POST /conversations/search
    let json = """
    {"$_type":"ConversationResult","hasMoreItems":true,"nextOffset":2,"items":[
      {"$_type":"ConversationData","id":"8KHb1FyCQjCb8MQBarOgog","topic":null,
       "creationTimestamp":1788708064387,"state":"QUEUED"}]}
    """
    let result = try decode(ConversationResult.self, json)
    #expect(result.hasMoreItems == true)
    #expect(result.items.first?.id == "8KHb1FyCQjCb8MQBarOgog")
    #expect(result.items.first?.topic == nil)
    #expect(result.items.first?.state == "QUEUED")
}

@Test func decodesSendMessageResult() throws {
    // Captured from POST /bots/sendMessage
    let json = #"{"$_type":"SendMessageResult","messageId":"WhqIR99gSUi8FO599m8sFQ"}"#
    #expect(try decode(SendMessageResult.self, json).messageId == "WhqIR99gSUi8FO599m8sFQ")
}

@Test func decodesMessageExportResultIncludingSystemMessages() throws {
    // Captured from POST /conversationhistory/{id}/exportMessageLog.
    let json = """
    {"$_type":"MessageExportResult","hasMoreItems":false,"items":[
      {"$_type":"ConversationHistoryMessageData","id":"1Lo9tY7gQKa2I-SV5_WIKw",
       "conversationId":"mKBJCuCqRWyS5xbkJrzlhQ","sendTimestamp":1788957595402,
       "senderPersonId":null,"type":"SYSTEM","internal":false},
      {"$_type":"ConversationHistoryMessageData","id":"WhqIR99gSUi8FO599m8sFQ",
       "conversationId":"mKBJCuCqRWyS5xbkJrzlhQ","sendTimestamp":1788957595500,
       "senderPersonId":"6nD26Li8QumI1YDkCc08bQ","type":"TEXT","text":"hello from UnbluMeet"}]}
    """
    let result = try decode(MessageExportResult.self, json)
    #expect(result.items.count == 2)
    #expect(result.items[0].senderPersonId == nil)
    #expect(result.items[0].type == "SYSTEM")
    #expect(result.items[1].text == "hello from UnbluMeet")
    #expect(result.items[1].senderPersonId == "6nD26Li8QumI1YDkCc08bQ")
}
