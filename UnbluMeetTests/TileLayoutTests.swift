import Testing
import CoreGraphics
@testable import UnbluMeet

@Test func emptyParticipantsProduceNoTiles() {
    let tiles = TileLayout.layout(mode: .grid, participantIDs: [], focusID: nil, aspect: 16.0 / 9.0)
    #expect(tiles.isEmpty)
}

@Test func gridProducesOneTilePerParticipant() {
    let ids = ["a", "b", "c", "d", "e"]
    let tiles = TileLayout.layout(mode: .grid, participantIDs: ids, focusID: nil, aspect: 16.0 / 9.0)
    #expect(tiles.count == 5)
    #expect(Set(tiles.map(\.participantID)) == Set(ids))
}

@Test func gridTilesStayInsideUnitSquare() {
    let ids = (0 ..< 9).map { "p\($0)" }
    for tile in TileLayout.layout(mode: .grid, participantIDs: ids, focusID: nil, aspect: 16.0 / 9.0) {
        #expect(tile.rect.minX >= -0.0001)
        #expect(tile.rect.minY >= -0.0001)
        #expect(tile.rect.maxX <= 1.0001)
        #expect(tile.rect.maxY <= 1.0001)
    }
}

@Test func gridTilesDoNotOverlap() {
    let ids = (0 ..< 6).map { "p\($0)" }
    let tiles = TileLayout.layout(mode: .grid, participantIDs: ids, focusID: nil, aspect: 16.0 / 9.0)
    for i in 0 ..< tiles.count {
        for j in (i + 1) ..< tiles.count {
            #expect(!tiles[i].rect.intersects(tiles[j].rect))
        }
    }
}

@Test func fourParticipantsFormTwoByTwo() {
    let tiles = TileLayout.layout(mode: .grid, participantIDs: ["a", "b", "c", "d"],
                                  focusID: nil, aspect: 16.0 / 9.0)
    #expect(tiles.count == 4)
    let distinctX = Set(tiles.map { ($0.rect.minX * 1000).rounded() })
    let distinctY = Set(tiles.map { ($0.rect.minY * 1000).rounded() })
    #expect(distinctX.count == 2)
    #expect(distinctY.count == 2)
}

@Test func speakerModeGivesFocusTheLargestTile() {
    let tiles = TileLayout.layout(mode: .speaker, participantIDs: ["a", "b", "c"],
                                  focusID: "b", aspect: 16.0 / 9.0)
    let focus = tiles.first { $0.participantID == "b" }!
    let others = tiles.filter { $0.participantID != "b" }
    for other in others {
        #expect(focus.rect.width * focus.rect.height > other.rect.width * other.rect.height)
    }
}

@Test func speakerModeWithoutFocusFallsBackToFirstParticipant() {
    let tiles = TileLayout.layout(mode: .speaker, participantIDs: ["a", "b", "c"],
                                  focusID: nil, aspect: 16.0 / 9.0)
    let a = tiles.first { $0.participantID == "a" }!
    let b = tiles.first { $0.participantID == "b" }!
    #expect(a.rect.width * a.rect.height > b.rect.width * b.rect.height)
}

@Test func gridPaginationLimitsTileCount() {
    let ids = (0 ..< 100).map { "p\($0)" }
    let tiles = TileLayout.layout(mode: .grid, participantIDs: ids, focusID: nil,
                                  aspect: 16.0 / 9.0, page: 0, pageSize: 25)
    #expect(tiles.count == 25)
    #expect(tiles.first?.participantID == "p0")
    #expect(tiles.last?.participantID == "p24")
}

@Test func secondPageShowsNextParticipants() {
    let ids = (0 ..< 100).map { "p\($0)" }
    let tiles = TileLayout.layout(mode: .grid, participantIDs: ids, focusID: nil,
                                  aspect: 16.0 / 9.0, page: 1, pageSize: 25)
    #expect(tiles.count == 25)
    #expect(tiles.first?.participantID == "p25")
}

@Test func lastPageMayBePartial() {
    let ids = (0 ..< 30).map { "p\($0)" }
    let tiles = TileLayout.layout(mode: .grid, participantIDs: ids, focusID: nil,
                                  aspect: 16.0 / 9.0, page: 1, pageSize: 25)
    #expect(tiles.count == 5)
}

@Test func pageBeyondTheEndIsEmpty() {
    let ids = (0 ..< 10).map { "p\($0)" }
    let tiles = TileLayout.layout(mode: .grid, participantIDs: ids, focusID: nil,
                                  aspect: 16.0 / 9.0, page: 5, pageSize: 25)
    #expect(tiles.isEmpty)
}

@Test func pageCountRoundsUp() {
    #expect(TileLayout.pageCount(participantCount: 100, mode: .grid, pageSize: 25) == 4)
    #expect(TileLayout.pageCount(participantCount: 101, mode: .grid, pageSize: 25) == 5)
    #expect(TileLayout.pageCount(participantCount: 0, mode: .grid, pageSize: 25) == 1)
    #expect(TileLayout.pageCount(participantCount: 100, mode: .pinned, pageSize: 25) == 1)
}

@Test func pinnedModeShowsOnlyTheFocusedParticipant() {
    let tiles = TileLayout.layout(mode: .pinned, participantIDs: ["a", "b", "c"],
                                  focusID: "c", aspect: 16.0 / 9.0)
    #expect(tiles.count == 1)
    #expect(tiles[0].participantID == "c")
    #expect(tiles[0].rect == CGRect(x: 0, y: 0, width: 1, height: 1))
}

@Test func speakerStripIsCappedAtCapacity() {
    let ids = (0 ..< 50).map { "p\($0)" }
    let tiles = TileLayout.layout(mode: .speaker, participantIDs: ids,
                                  focusID: "p0", aspect: 16.0 / 9.0)
    // One focus tile plus at most stripCapacity thumbnails.
    #expect(tiles.count == TileLayout.stripCapacity + 1)
}

@Test func stripOffsetShiftsWhichThumbnailsShow() {
    let ids = (0 ..< 50).map { "p\($0)" }
    let first = TileLayout.layout(mode: .speaker, participantIDs: ids,
                                  focusID: "p0", aspect: 16.0 / 9.0, stripOffset: 0)
    let shifted = TileLayout.layout(mode: .speaker, participantIDs: ids,
                                    focusID: "p0", aspect: 16.0 / 9.0, stripOffset: 3)
    let firstStrip = first.filter { $0.participantID != "p0" }.map(\.participantID)
    let shiftedStrip = shifted.filter { $0.participantID != "p0" }.map(\.participantID)
    #expect(firstStrip.first == "p1")
    #expect(shiftedStrip.first == "p4")
}

@Test func stripOffsetIsClampedAndNeverEmpties() {
    let ids = (0 ..< 50).map { "p\($0)" }
    let tiles = TileLayout.layout(mode: .speaker, participantIDs: ids,
                                  focusID: "p0", aspect: 16.0 / 9.0, stripOffset: 999)
    #expect(tiles.count >= 2)
}

@Test func maxStripOffsetLeavesAFullStrip() {
    // 50 participants, one focused, 8 visible → last offset is 41.
    #expect(TileLayout.maxStripOffset(participantCount: 50) == 41)
    #expect(TileLayout.maxStripOffset(participantCount: 3) == 0)
    #expect(TileLayout.maxStripOffset(participantCount: 0) == 0)
}

@Test func pinnedWithAMissingFocusShowsNothingRatherThanSomeoneElse() {
    // Silently pinning a different participant is how a screen share ended up
    // showing an unrelated black tile.
    let tiles = TileLayout.layout(mode: .pinned, participantIDs: ["a", "b"],
                                  focusID: "gone", aspect: 16.0 / 9.0)
    #expect(tiles.isEmpty)
}

@Test func pinnedWithoutAFocusStillFallsBackToTheFirst() {
    let tiles = TileLayout.layout(mode: .pinned, participantIDs: ["a", "b"],
                                  focusID: nil, aspect: 16.0 / 9.0)
    #expect(tiles.count == 1)
    #expect(tiles[0].participantID == "a")
}
