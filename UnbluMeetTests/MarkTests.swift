import Testing
import Foundation
import CoreGraphics
@testable import UnbluMeet

private func makeMark(points: [CGPoint], id: String = "m1") -> Mark {
    Mark(targetParticipantID: "alice", authorID: "bob",
         points: points, colorIndex: 2, createdAt: 1000, id: id)
}

@Test func markRoundTripsThroughJSON() throws {
    let original = makeMark(points: [CGPoint(x: 0.1, y: 0.2), CGPoint(x: 0.3, y: 0.4)])
    let decoded = try Mark.decode(Mark.encode(original))
    #expect(decoded == original)
}

@Test func pointsAreClampedToTheUnitSquare() {
    let mark = makeMark(points: [CGPoint(x: -0.5, y: 1.8), CGPoint(x: 0.4, y: 0.4)])
    #expect(mark.points[0] == CGPoint(x: 0, y: 1))
    #expect(mark.points[1] == CGPoint(x: 0.4, y: 0.4))
}

@Test func pointCountIsCappedSoPayloadsStayUnderTheDataLimit() {
    let many = (0 ..< 5000).map { CGPoint(x: Double($0 % 100) / 100.0, y: 0.5) }
    let mark = makeMark(points: many)
    #expect(mark.points.count == Mark.maxPoints)
}

@Test func cappedMarkEncodesWellUnderFifteenKilobytes() throws {
    let many = (0 ..< 5000).map { CGPoint(x: Double($0 % 100) / 100.0, y: 0.5) }
    let data = try Mark.encode(makeMark(points: many))
    // LiveKit rejects data payloads over 15 KB.
    #expect(data.count < 15_000)
}

@Test func decodingGarbageThrows() {
    #expect(throws: (any Error).self) {
        _ = try Mark.decode(Data("not json".utf8))
    }
}

@Test func marksWithSameContentAreEqual() {
    let a = makeMark(points: [CGPoint(x: 0.5, y: 0.5)])
    let b = makeMark(points: [CGPoint(x: 0.5, y: 0.5)])
    #expect(a == b)
}

@Test func thickStripEmitsTwoVerticesPerPoint() {
    let points: [SIMD2<Float>] = [SIMD2(0.2, 0.5), SIMD2(0.5, 0.5), SIMD2(0.8, 0.5)]
    let strip = MetalCompositor.thickStrip(points: points, widthPx: 6,
                                           viewport: CGSize(width: 1000, height: 500))
    #expect(strip.count == points.count * 2)
}

@Test func thickStripStaysUniformOnANonSquareViewport() {
    // A horizontal line offsets vertically; on a 2:1 viewport the normalised
    // offset must be twice the horizontal one to look equally thick.
    let points: [SIMD2<Float>] = [SIMD2(0.2, 0.5), SIMD2(0.8, 0.5)]
    let strip = MetalCompositor.thickStrip(points: points, widthPx: 10,
                                           viewport: CGSize(width: 1000, height: 500))
    let spread = abs(strip[0].y - strip[1].y)
    #expect(abs(Double(spread) - 10.0 / 500.0) < 0.001)
}

@Test func thickStripNeedsAtLeastTwoPoints() {
    let strip = MetalCompositor.thickStrip(points: [SIMD2(0.5, 0.5)], widthPx: 6,
                                           viewport: CGSize(width: 100, height: 100))
    #expect(strip.isEmpty)
}

@Test func aFreshMarkIsFullyOpaque() {
    #expect(Mark.opacity(age: 0) == 1)
    #expect(Mark.opacity(age: 1) == 1)
}

@Test func aMarkStaysSolidUntilTheFadeBegins() {
    let justBeforeFade = Mark.lifetime - Mark.fadeDuration - 0.1
    #expect(Mark.opacity(age: justBeforeFade) == 1)
}

@Test func aMarkFadesToNothingByTheEndOfItsLife() {
    let halfway = Mark.lifetime - Mark.fadeDuration / 2
    let opacity = Mark.opacity(age: halfway)
    #expect(opacity > 0 && opacity < 1)
    #expect(Mark.opacity(age: Mark.lifetime) == 0)
    #expect(Mark.opacity(age: Mark.lifetime + 10) == 0)
}

@Test func expiredMarksAreDroppedFromTheStore() {
    let store = MarkStore()
    let mark = Mark(targetParticipantID: "alice", authorID: "bob",
                    points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)],
                    colorIndex: 0, createdAt: 0, id: "m1")
    store.add(mark, now: 1000)
    #expect(store.visibleMarks(for: "alice", now: 1001).count == 1)
    #expect(store.visibleMarks(for: "alice", now: 1000 + Mark.lifetime + 1).isEmpty)
}

@Test func marksFromDifferentMachinesAgeFromArrivalNotSenderClock() {
    // createdAt is deliberately far in the past; age must come from arrival.
    let store = MarkStore()
    let stale = Mark(targetParticipantID: "alice", authorID: "bob",
                     points: [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.2, y: 0.2)],
                     colorIndex: 0, createdAt: 0, id: "m2")
    store.add(stale, now: 5000)
    #expect(store.visibleMarks(for: "alice", now: 5001).count == 1)
}
