import Testing
import CoreGraphics
@testable import UnbluMeet

@Test func initialsUseUpToTwoWords() {
    #expect(TileCard.initials(of: "Denis Mikaya") == "DM")
}

@Test func initialsHandleASingleName() {
    #expect(TileCard.initials(of: "daos") == "D")
}

@Test func initialsIgnoreExtraNames() {
    #expect(TileCard.initials(of: "Ada Grace Byron King") == "AG")
}

@Test func initialsFallBackWhenThereIsNoName() {
    #expect(TileCard.initials(of: "") == "?")
    #expect(TileCard.initials(of: "   ") == "?")
}

@Test func joinPhasesAdvanceMonotonically() {
    let ordered: [JoinPhase] = [.idle, .preparing, .signingToken,
                                .connecting(host: "livekit.local"),
                                .enablingMicrophone, .syncing, .ready]
    for (earlier, later) in zip(ordered, ordered.dropFirst()) {
        #expect(earlier.fraction <= later.fraction)
    }
    #expect(ordered.last?.fraction == 1)
}

@Test func retryingDoesNotLoseGroundAgainstConnecting() {
    // The retry re-runs the connect step; the bar should hold, not rewind.
    #expect(JoinPhase.retrying.fraction == JoinPhase.connecting(host: "h").fraction)
}

@Test func connectingPhaseNamesTheHostNotTheWholeURL() {
    #expect(JoinPhase.host(of: "wss://livekit.example.com:7880/rtc") == "livekit.example.com")
    #expect(JoinPhase.connecting(host: "livekit.example.com").text.contains("livekit.example.com"))
}

@Test func aMalformedURLFallsBackToItself() {
    #expect(JoinPhase.host(of: "not a url") == "not a url")
}

@Test func onlyFailureReportsAsFailure() {
    #expect(JoinPhase.failed("boom").isFailure)
    #expect(JoinPhase.failed("boom").text == "boom")
    #expect(!JoinPhase.ready.isFailure)
}

@Test func regionIsClampedToTheDisplay() {
    let rect = RegionSelector.rect(from: CGPoint(x: -50, y: -50),
                                   to: CGPoint(x: 400, y: 300),
                                   within: CGSize(width: 1512, height: 982))
    #expect(rect?.origin == CGPoint(x: 0, y: 0))
    #expect(rect?.width == 400)
    #expect(rect?.height == 300)
}

@Test func regionDimensionsAreEvenForTheEncoder() {
    let rect = RegionSelector.rect(from: CGPoint(x: 10, y: 10),
                                   to: CGPoint(x: 111, y: 143),
                                   within: CGSize(width: 1512, height: 982))
    #expect(rect.map { Int($0.width) % 2 } == 0)
    #expect(rect.map { Int($0.height) % 2 } == 0)
}

@Test func aTinyDragIsNotASelection() {
    // A click without a drag would otherwise share a few pixels.
    #expect(RegionSelector.rect(from: CGPoint(x: 100, y: 100),
                                to: CGPoint(x: 104, y: 108),
                                within: CGSize(width: 1512, height: 982)) == nil)
}

@Test func draggingUpAndLeftStillProducesAPositiveRect() {
    let rect = RegionSelector.rect(from: CGPoint(x: 500, y: 400),
                                   to: CGPoint(x: 200, y: 100),
                                   within: CGSize(width: 1512, height: 982))
    #expect(rect == CGRect(x: 200, y: 100, width: 300, height: 300))
}

@Test func aRegionTargetSaysSoInItsLabel() {
    var target = ShareTarget(id: "d1", name: "Display 1", kind: .display,
                             displayID: 1, windowID: nil,
                             size: CGSize(width: 1512, height: 982))
    #expect(target.label == "Display 1")
    target.region = CGRect(x: 0, y: 0, width: 800, height: 600)
    #expect(target.label == "Display 1 — region 800×600")
}

@Test func translocationIsDiagnosedSeparatelyFromAStaleGrant() {
    // Same symptom, opposite fixes: one needs moving the app, the other needs
    // the TCC entry cleared.
    let translocated = ScreenPermission.diagnosis(
        bundlePath: "/private/var/folders/qr/x/T/AppTranslocation/ABC/d/UnbluMeet.app")
    #expect(translocated.contains("/Applications"))
    #expect(!translocated.contains("tccutil"))

    let normal = ScreenPermission.diagnosis(bundlePath: "/Applications/UnbluMeet.app")
    #expect(normal.contains("tccutil reset ScreenCapture com.unblu.UnbluMeet"))
}

@Test func captionHistoryKeepsTheLastFewUtterances() {
    let lines = [CaptionService.Line(speaker: "Anna", text: "we should ship it"),
                 CaptionService.Line(speaker: "Marek", text: "I will write the docs")]
    #expect(lines.last?.speaker == "Marek")
    #expect(lines.first?.text == "we should ship it")
}

private struct FakeError: Error, CustomStringConvertible { let description: String }

@Test func aServerRefusalIsNotReportedAsAnAudioDeviceProblem() {
    // Blaming CoreAudio for a permissions refusal sends people to the wrong
    // place entirely.
    let refusal = FakeError(description: "Unknown(Participant does not have permission to publish)")
    #expect(!RoomController.isAudioDeviceFailure(refusal))
    let message = RoomController.explainMicrophone(refusal)
    #expect(message.contains("refused"))
    #expect(!message.contains("virtual audio driver"))
}

@Test func aTimeoutStillPointsAtTheAudioDevice() {
    let timeout = FakeError(description: "Error Domain=io.livekit.swift-sdk Code=101 \"Timed out\"")
    #expect(RoomController.isAudioDeviceFailure(timeout))
    #expect(RoomController.explainMicrophone(timeout).contains("virtual audio driver"))
}

@Test func theSessionIdentityIsUniquePerJoinByDefault() {
    // An identity is exclusive, and a stale one from a crash blocks rejoining.
    let a = RoomController.sessionIdentity(for: "person-1")
    let b = RoomController.sessionIdentity(for: "person-1")
    #expect(a != b)
    #expect(a.hasPrefix("person-1~"))
}

@Test func theExactIdentityIsTheBarePersonId() {
    // What Unblu's call UI matches against.
    #expect(RoomController.sessionIdentity(for: "person-1", exact: true) == "person-1")
}
