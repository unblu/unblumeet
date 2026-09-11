import Testing
import Foundation
@testable import UnbluMeet

@Test func bitrateIsReadableAtEveryScale() {
    #expect(ConnectionReport.bitrate(bytes: 250_000, over: 1) == "2.0 Mbps")
    #expect(ConnectionReport.bitrate(bytes: 4_000, over: 1) == "32 kbps")
    #expect(ConnectionReport.bitrate(bytes: 10, over: 1) == "80 bps")
}

@Test func aRateNeedsAnIntervalToDivideBy() {
    #expect(ConnectionReport.bitrate(bytes: 1_000, over: 0) == "—")
    #expect(ConnectionReport.bitrate(bytes: nil, over: 1) == "—")
}

@Test func aRateIsPerSecondNotPerSample() {
    // Two seconds of the same bytes is half the rate.
    #expect(ConnectionReport.bitrate(bytes: 250_000, over: 2) == "1.0 Mbps")
}

@Test func lossIsAShareOfWhatWasExpected() {
    #expect(ConnectionReport.lossPercent(lost: 5, received: 95) == 5)
    #expect(ConnectionReport.lossPercent(lost: 0, received: 100) == 0)
    #expect(ConnectionReport.lossPercent(lost: 0, received: 0) == nil)
    #expect(ConnectionReport.lossPercent(lost: nil, received: 100) == nil)
}

@Test func audibleLossIsFlagged() {
    // A percent starts to be audible; a tenth of one is not worth a warning.
    #expect(ConnectionReport.isLossy(lost: 2, received: 98))
    #expect(!ConnectionReport.isLossy(lost: 1, received: 9_999))
    #expect(!ConnectionReport.isLossy(lost: nil, received: nil))
}

@Test func slowRoundTripsAreFlagged() {
    #expect(ConnectionReport.isSlow(roundTrip: 0.25))
    #expect(!ConnectionReport.isSlow(roundTrip: 0.04))
    #expect(!ConnectionReport.isSlow(roundTrip: nil))
}

@Test func roundTripReadsInMilliseconds() {
    #expect(ConnectionReport.milliseconds(0.042) == "42 ms")
    #expect(ConnectionReport.milliseconds(nil) == "—")
}

@Test func theReportCopiesAsPlainText() {
    let report = ConnectionReport(sections: [
        .init(id: "s", title: "Server", lines: [
            .init(id: "a", label: "State", value: "connected"),
        ]),
    ])
    #expect(report.plainText == "Server\n  State: connected")
}

@Test func theHistoryStaysBounded() {
    // A call can run for hours; the charts only show the recent past.
    var history = ConnectionHistory()
    for i in 0 ..< (ConnectionHistory.capacity + 40) {
        history.record(at: Date(timeIntervalSince1970: Double(i)), inbound: 1, outbound: 1,
                       roundTrip: 0.02, loss: 0)
    }
    #expect(history.samples.count == ConnectionHistory.capacity)
    #expect(history.samples.first?.at == Date(timeIntervalSince1970: 40))
}

@Test func chartsLeaveHeadroomAboveThePeak() {
    // A line pinned to the top of the plot reads as clipped.
    #expect(ConnectionHistory.upperBound([40, 80], minimum: 10) == 100)
}

@Test func aQuietChartStillHasAScale() {
    #expect(ConnectionHistory.upperBound([], minimum: 100) == 100)
    #expect(ConnectionHistory.upperBound([1, 2], minimum: 100) == 100)
}

@Test func theHistorySummarisesWhatItHolds() {
    var history = ConnectionHistory()
    history.record(at: .now, inbound: 1_000, outbound: 500, roundTrip: 0.02, loss: 0)
    history.record(at: .now, inbound: 3_000, outbound: 900, roundTrip: 0.06, loss: 2.5)
    #expect(history.peakInbound == 3_000)
    #expect(history.peakOutbound == 900)
    #expect(abs((history.averageRoundTrip ?? 0) - 0.04) < 0.0001)
    #expect(history.worstLoss == 2.5)
}

@Test func gapsInMeasurementDoNotBreakTheAverages() {
    var history = ConnectionHistory()
    history.record(at: .now, inbound: 0, outbound: 0, roundTrip: nil, loss: nil)
    #expect(history.averageRoundTrip == nil)
    #expect(history.worstLoss == nil)
}

@Test func theMediaPathNamesTheServerRatherThanClaimingPeerToPeer() {
    // LiveKit is an SFU: media always passes through it. The candidates say
    // how this client reaches it, not whether it skipped it.
    #expect(ConnectionReport.describePath(local: nil, remote: nil) == "—")
}

@Test func encryptionAlwaysReportsTheTransportLayer() {
    // WebRTC encrypts in transit whether or not end-to-end is switched on.
    let hopByHop = ConnectionReport.describeEncryption(
        dtlsState: "connected", cipher: "AES_CM_128_HMAC_SHA1_80", tlsVersion: "1.2", endToEnd: false)
    #expect(hopByHop.contains("DTLS-SRTP"))
    #expect(hopByHop.contains("AES_CM_128_HMAC_SHA1_80"))

    let endToEnd = ConnectionReport.describeEncryption(
        dtlsState: "connected", cipher: nil, tlsVersion: nil, endToEnd: true)
    #expect(endToEnd.contains("end-to-end"))
}

@Test func anUnsettledDtlsStateIsSurfaced() {
    let connecting = ConnectionReport.describeEncryption(
        dtlsState: "connecting", cipher: nil, tlsVersion: nil, endToEnd: false)
    #expect(connecting.contains("connecting"))
}

@Test func whetherTheServerCanReadTheMediaIsStatedPlainly() {
    #expect(ConnectionReport.isReadableByServer(endToEnd: false))
    #expect(!ConnectionReport.isReadableByServer(endToEnd: true))
}

@Test func aRunningUnbluCallSharesThisRoom() {
    // Unblu names its LiveKit room after the conversation id as well, so its
    // participants arrive in the same place.
    let running = CallData(id: "c1", conversationId: "x", serviceProviderType: "LIVEKIT",
                           initiationTimestamp: 1, endTimestamp: nil)
    #expect(UnbluStatusProbe.describeCalls([running]) == "1 running — LIVEKIT")
}

@Test func endedCallsAreNotReportedAsRunning() {
    let ended = CallData(id: "c1", conversationId: "x", serviceProviderType: "LIVEKIT",
                         initiationTimestamp: 1, endTimestamp: 2)
    #expect(UnbluStatusProbe.describeCalls([ended]) == "none now (1 earlier)")
    #expect(UnbluStatusProbe.describeCalls([]) == "none")
}

@Test func aSlowConversationReadIsFlagged() {
    #expect(UnbluStatusProbe.isSluggish(0.9))
    #expect(!UnbluStatusProbe.isSluggish(0.2))
}
