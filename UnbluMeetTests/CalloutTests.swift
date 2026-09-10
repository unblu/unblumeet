import Testing
import Foundation
import CoreGraphics
@testable import UnbluMeet

@Test func aCalloutFitsFarInsideTheDataChannelBudget() throws {
    // The whole point of sending a rect instead of an image: a JPEG crop sits
    // right at LiveKit's 15 KB cap on a lossy channel.
    let callout = Callout(targetParticipantID: "p1#screen", authorID: "p2",
                          region: CGRect(x: 0.31, y: 0.42, width: 0.12, height: 0.08),
                          colorIndex: 1, createdAt: 1_700_000_000)
    #expect(try Callout.encode(callout).count < 400)
}

@Test func regionIsClampedIntoTheFrame() {
    let callout = Callout(targetParticipantID: "p", authorID: "a",
                          region: CGRect(x: -0.2, y: 0.9, width: 0.5, height: 0.5),
                          colorIndex: 0, createdAt: 0)
    #expect(callout.region.minX >= 0)
    #expect(callout.region.maxY <= 1)
}

@Test func aStrayClickIsNotACallout() {
    #expect(!Callout.isUsable(CGRect(x: 0.5, y: 0.5, width: 0.002, height: 0.002)))
    #expect(Callout.isUsable(CGRect(x: 0.5, y: 0.5, width: 0.05, height: 0.03)))
}

@Test func theInsetSitsBelowTheRegionWhenThereIsRoom() {
    let region = CGRect(x: 0.4, y: 0.1, width: 0.1, height: 0.05)
    let inset = Callout.insetRect(regionInTile: region)
    #expect(inset.minY > region.maxY)
    #expect(inset.width > region.width)   // magnified
}

@Test func theInsetFlipsAboveWhenTheRegionIsNearTheBottom() {
    let region = CGRect(x: 0.4, y: 0.85, width: 0.1, height: 0.05)
    let inset = Callout.insetRect(regionInTile: region)
    #expect(inset.maxY < region.minY)
}

@Test func theInsetStaysInsideTheTile() {
    for x in stride(from: 0.0, through: 0.9, by: 0.1) {
        for y in stride(from: 0.0, through: 0.9, by: 0.1) {
            let inset = Callout.insetRect(
                regionInTile: CGRect(x: x, y: y, width: 0.08, height: 0.06))
            #expect(inset.minX >= 0)
            #expect(inset.maxX <= 1.001)
            #expect(inset.minY >= 0)
            #expect(inset.maxY <= 1.001)
        }
    }
}

@Test func theInsetKeepsTheRegionsShape() {
    let region = CGRect(x: 0.3, y: 0.2, width: 0.2, height: 0.05)
    let inset = Callout.insetRect(regionInTile: region)
    let regionAspect = region.width / region.height
    let insetAspect = inset.width / inset.height
    #expect(abs(regionAspect - insetAspect) < 0.001)
}

@Test func aVeryTallRegionIsCappedRatherThanOverflowing() {
    let inset = Callout.insetRect(regionInTile: CGRect(x: 0.4, y: 0.05, width: 0.05, height: 0.3))
    #expect(inset.height <= 0.55)
}

@Test func calloutsOutliveMarks() {
    // A callout is meant to be read, not glanced at.
    #expect(Callout.lifetime > Mark.lifetime)
    #expect(Callout.opacity(age: 0) == 1)
    #expect(Callout.opacity(age: Callout.lifetime + 1) == 0)
    #expect(Callout.opacity(age: Callout.lifetime - Callout.fadeDuration / 2) < 1)
}

@Test func regionMapsIntoTileSpaceThroughTheVisibleCrop() {
    // Half the frame visible: a region at its centre lands at the tile centre.
    let uv = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    let mapped = MetalCompositor.regionInTile(
        CGRect(x: 0.45, y: 0.45, width: 0.1, height: 0.1), visible: uv)
    #expect(abs((mapped?.midX ?? 0) - 0.5) < 0.0001)
    #expect(abs((mapped?.width ?? 0) - 0.2) < 0.0001)
}

@Test func aRegionScrolledOutOfViewIsNotDrawn() {
    let uv = CGRect(x: 0.6, y: 0.6, width: 0.4, height: 0.4)
    #expect(MetalCompositor.regionInTile(
        CGRect(x: 0.0, y: 0.0, width: 0.1, height: 0.1), visible: uv) == nil)
}

@Test func aDragInAnyDirectionProducesAPositiveRect() {
    let up = InteractiveMTKView.rect(from: CGPoint(x: 0.6, y: 0.6), to: CGPoint(x: 0.2, y: 0.1))
    #expect(up.minX == 0.2)
    #expect(up.minY == 0.1)
    #expect(abs(up.width - 0.4) < 0.0001)
    #expect(abs(up.height - 0.5) < 0.0001)
}

@Test func storedCalloutsExpireOnTheirOwn() {
    let store = MarkStore()
    let callout = Callout(targetParticipantID: "t", authorID: "a",
                          region: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                          colorIndex: 0, createdAt: 0)
    store.add(callout, now: 1000)
    #expect(store.visibleCallouts(for: "t", now: 1001).count == 1)
    #expect(store.visibleCallouts(for: "t", now: 1000 + Callout.lifetime + 1).isEmpty)
}

@Test func clearingRemovesCalloutsAsWellAsMarks() {
    let store = MarkStore()
    store.add(Callout(targetParticipantID: "t", authorID: "a",
                      region: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                      colorIndex: 0, createdAt: 0), now: 1000)
    store.clearAll()
    #expect(store.visibleCallouts(for: "t", now: 1001).isEmpty)
}

@Test func aLongStrokeKeepsItsEndInsteadOfBeingCutOff() {
    // prefix() dropped everything drawn after the 128th point, so a slow drag
    // simply stopped growing part-way through.
    let points = (0 ..< 900).map { CGPoint(x: Double($0) / 899, y: 0.5) }
    let mark = Mark(targetParticipantID: "t", authorID: "a", points: points,
                    colorIndex: 0, createdAt: 0)
    #expect(mark.points.count == Mark.maxPoints)
    #expect(mark.points.first?.x == 0)
    #expect(mark.points.last?.x == 1)
}

@Test func shortStrokesAreLeftAlone() {
    let points = (0 ..< 10).map { CGPoint(x: Double($0) / 9, y: 0.5) }
    #expect(Mark.decimate(points).count == 10)
}

@Test func republishingAStrokeReplacesItRatherThanStacking() {
    // A stroke being drawn is sent repeatedly under one id as it grows.
    let store = MarkStore()
    let growing = { (count: Int) in
        Mark(targetParticipantID: "t", authorID: "a",
             points: (0 ..< count).map { CGPoint(x: Double($0) / 100, y: 0.5) },
             colorIndex: 0, createdAt: 0, id: "stroke-1")
    }
    store.add(growing(2), now: 1000)
    store.add(growing(9), now: 1000.2)
    let marks = store.visibleMarks(for: "t", now: 1000.3).map(\.mark)
    #expect(marks.count == 1)
    #expect(marks.first?.points.count == 9)
}

@Test func aRoundedOutlineStaysWithinItsRectangle() {
    let rect = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.2)
    let points = MetalCompositor.roundedOutlinePoints(
        rect, radius: CGSize(width: 0.05, height: 0.05))
    #expect(points.count > 8)
    for point in points {
        #expect(point.x >= rect.minX - 0.0001)
        #expect(point.x <= rect.maxX + 0.0001)
        #expect(point.y >= rect.minY - 0.0001)
        #expect(point.y <= rect.maxY + 0.0001)
    }
    #expect(points.first == points.last)   // closed
}

@Test func anOversizedRadiusCannotInvertTheCorners() {
    let rect = CGRect(x: 0, y: 0, width: 0.1, height: 0.1)
    let points = MetalCompositor.roundedOutlinePoints(
        rect, radius: CGSize(width: 5, height: 5))
    for point in points {
        #expect(point.x >= -0.0001 && point.x <= 0.1001)
        #expect(point.y >= -0.0001 && point.y <= 0.1001)
    }
}

@Test func cornerRadiusIsPerAxisSoWideTilesDoNotSkew() {
    // A 2:1 tile needs half the fraction horizontally to look square.
    let radius = MetalCompositor.cornerRadiusInTile(
        pixels: 12, tile: CGRect(x: 0, y: 0, width: 1, height: 0.5),
        viewport: CGSize(width: 1000, height: 1000))
    #expect(abs(radius.width - 0.012) < 0.0001)
    #expect(abs(radius.height - 0.024) < 0.0001)
}
