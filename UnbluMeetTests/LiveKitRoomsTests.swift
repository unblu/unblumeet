import Testing
import Foundation
@testable import UnbluMeet

@Test func theWebsocketUrlBecomesAnHttpOne() {
    // The media URL is wss; the server API is not.
    #expect(LiveKitRooms.httpURL(from: "wss://ch.sfu.example.app")?.absoluteString
            == "https://ch.sfu.example.app")
    #expect(LiveKitRooms.httpURL(from: "ws://localhost:7880")?.absoluteString
            == "http://localhost:7880")
}

@Test func aTrailingSlashIsNotCarriedIntoThePath() {
    #expect(LiveKitRooms.httpURL(from: "wss://ch.sfu.example.app/")?.absoluteString
            == "https://ch.sfu.example.app")
}

@Test func anHttpUrlIsLeftAlone() {
    #expect(LiveKitRooms.httpURL(from: "https://ch.sfu.example.app")?.absoluteString
            == "https://ch.sfu.example.app")
}

@Test func anAdminTokenAsksForListingRatherThanJoining() {
    let signer = TokenSigner(apiKey: "devkey", apiSecret: "secret-secret-secret-secret")
    let parts = signer.signAdmin(ttl: 60).split(separator: ".")
    #expect(parts.count == 3)
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    while payload.count % 4 != 0 { payload += "=" }
    let json = try! JSONSerialization.jsonObject(
        with: Data(base64Encoded: payload)!) as! [String: Any]
    let video = json["video"] as! [String: Any]
    #expect(video["roomList"] as? Bool == true)
    #expect(video["roomJoin"] == nil)
}

@Test func countsAreReadFromTheProtoFieldNames() {
    // This server sends num_participants; reading only numParticipants made
    // every room look empty and the lobby fell back to membership.
    let json = Data("""
        {"rooms":[{"sid":"RM_a","name":"yRs2TdXiQhGmFy1cDMC-1g","num_participants":3,
                   "num_publishers":3}]}
        """.utf8)
    #expect(LiveKitRooms.occupancy(fromListRooms: json) == ["yRs2TdXiQhGmFy1cDMC-1g": 3])
}

@Test func theCamelCasedFormIsAlsoUnderstood() {
    let json = Data(#"{"rooms":[{"name":"room-a","numParticipants":5}]}"#.utf8)
    #expect(LiveKitRooms.occupancy(fromListRooms: json) == ["room-a": 5])
}

@Test func aCountSentAsAStringStillCounts() {
    let json = Data(#"{"rooms":[{"name":"room-a","num_participants":"7"}]}"#.utf8)
    #expect(LiveKitRooms.occupancy(fromListRooms: json) == ["room-a": 7])
}

@Test func aRoomWithNoCountAtAllReadsAsEmpty() {
    let json = Data(#"{"rooms":[{"name":"room-a"}]}"#.utf8)
    #expect(LiveKitRooms.occupancy(fromListRooms: json) == ["room-a": 0])
}

@Test func nonsenseDoesNotThrowAwayTheLobby() {
    #expect(LiveKitRooms.occupancy(fromListRooms: Data("not json".utf8)).isEmpty)
}
