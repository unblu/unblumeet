import Testing
import CoreVideo
@testable import UnbluMeet

private func makePixelBuffer(width: Int = 16, height: Int = 16) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                        nil, &pb)
    return pb!
}

@Test func storesAndRetrievesLatestFrame() {
    let store = FrameStore()
    let buffer = makePixelBuffer()
    store.store(buffer, for: "alice")
    #expect(store.latest(for: "alice") === buffer)
}

@Test func latestWinsOverEarlierFrame() {
    let store = FrameStore()
    let first = makePixelBuffer(width: 16, height: 16)
    let second = makePixelBuffer(width: 32, height: 32)
    store.store(first, for: "alice")
    store.store(second, for: "alice")
    #expect(store.latest(for: "alice") === second)
}

@Test func unknownParticipantReturnsNil() {
    let store = FrameStore()
    #expect(store.latest(for: "nobody") == nil)
}

@Test func removeDropsTheParticipant() {
    let store = FrameStore()
    store.store(makePixelBuffer(), for: "alice")
    store.remove(participantID: "alice")
    #expect(store.latest(for: "alice") == nil)
    #expect(store.participantIDs.isEmpty)
}

@Test func concurrentWritesDoNotCrash() async {
    let store = FrameStore()
    await withTaskGroup(of: Void.self) { group in
        for i in 0 ..< 8 {
            group.addTask {
                for _ in 0 ..< 200 {
                    store.store(makePixelBuffer(), for: "p\(i)")
                    _ = store.latest(for: "p\(i)")
                }
            }
        }
    }
    #expect(store.participantIDs.count == 8)
}
