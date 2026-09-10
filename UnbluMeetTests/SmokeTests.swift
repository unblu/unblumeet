import Testing
import LiveKit
@testable import UnbluMeet

@Test func liveKitIsLinked() {
    let options = RoomOptions(adaptiveStream: true, dynacast: true)
    #expect(options.adaptiveStream)
    #expect(options.dynacast)
}
