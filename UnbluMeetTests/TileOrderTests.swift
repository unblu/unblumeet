import Testing
@testable import UnbluMeet

@Test func anEmptyArrangementLeavesTilesAlone() {
    #expect(TileOrder.apply([], to: ["a", "b", "c"]) == ["a", "b", "c"])
}

@Test func tilesFollowTheArrangement() {
    #expect(TileOrder.apply(["c", "a", "b"], to: ["a", "b", "c"]) == ["c", "a", "b"])
}

@Test func someoneWhoLeftIsSimplyAbsent() {
    #expect(TileOrder.apply(["c", "gone", "a"], to: ["a", "c"]) == ["c", "a"])
}

@Test func aNewJoinerGoesToTheEndRatherThanTheFront() {
    // An arrangement should not be disturbed by somebody arriving.
    #expect(TileOrder.apply(["b", "a"], to: ["a", "b", "new"]) == ["b", "a", "new"])
}

@Test func newJoinersKeepTheirOwnRelativeOrder() {
    #expect(TileOrder.apply(["b"], to: ["a", "b", "c"]) == ["b", "a", "c"])
}

@Test func draggingATileTakesTheTargetsPlace() {
    #expect(TileOrder.moving("c", onto: "a", in: ["a", "b", "c"]) == ["c", "a", "b"])
    #expect(TileOrder.moving("a", onto: "c", in: ["a", "b", "c"]) == ["b", "c", "a"])
}

@Test func droppingATileOnItselfChangesNothing() {
    #expect(TileOrder.moving("b", onto: "b", in: ["a", "b", "c"]) == ["a", "b", "c"])
}

@Test func draggingSomethingNotInTheListChangesNothing() {
    #expect(TileOrder.moving("z", onto: "a", in: ["a", "b"]) == ["a", "b"])
}
