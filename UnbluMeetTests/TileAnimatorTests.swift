import Testing
import CoreGraphics
import Foundation
@testable import UnbluMeet

private func tile(_ id: String, _ rect: CGRect) -> Tile {
    Tile(participantID: id, rect: rect)
}

private let left = CGRect(x: 0, y: 0, width: 0.5, height: 1)
private let right = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)

@Test func aTileNewToTheLayoutStartsWhereItBelongs() {
    // Somebody joining should appear in place, not fly in from a corner.
    var animator = TileAnimator()
    #expect(animator.resolve(targets: [tile("anna", left)], now: 100) == [tile("anna", left)])
}

@Test func aMovedTileTravelsRatherThanSnapping() {
    var animator = TileAnimator()
    _ = animator.resolve(targets: [tile("anna", left)], now: 100)
    let started = animator.resolve(targets: [tile("anna", right)], now: 101)
    #expect(started == [tile("anna", left)])   // begins where it was

    let midway = animator.resolve(targets: [tile("anna", right)], now: 101 + TileAnimator.duration / 2)
    let x = midway[0].rect.minX
    #expect(x > left.minX && x < right.minX)
}

@Test func aTileArrivesExactlyAndStaysPut() {
    var animator = TileAnimator()
    _ = animator.resolve(targets: [tile("anna", left)], now: 100)
    _ = animator.resolve(targets: [tile("anna", right)], now: 100)
    #expect(animator.resolve(targets: [tile("anna", right)], now: 100 + TileAnimator.duration) == [tile("anna", right)])
    #expect(animator.resolve(targets: [tile("anna", right)], now: 200) == [tile("anna", right)])
}

@Test func aSecondMoveStartsFromWhereTheTileCurrentlyIs() {
    // Changing layout twice quickly must not jump back to the old position.
    var animator = TileAnimator()
    _ = animator.resolve(targets: [tile("anna", left)], now: 100)
    _ = animator.resolve(targets: [tile("anna", right)], now: 100)
    let midway = animator.resolve(targets: [tile("anna", right)], now: 100 + TileAnimator.duration / 2)[0].rect

    let redirected = animator.resolve(targets: [tile("anna", left)], now: 100 + TileAnimator.duration / 2)
    #expect(abs(redirected[0].rect.minX - midway.minX) < 0.0001)
}

@Test func sizeIsInterpolatedAsWellAsPosition() {
    // Grid to speaker is mostly a change of size.
    let small = CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
    let large = CGRect(x: 0, y: 0, width: 1, height: 1)
    let half = TileAnimator.interpolate(small, large, 0.5)
    #expect(half.width > small.width && half.width < large.width)
    #expect(half.height > small.height && half.height < large.height)
}

@Test func theEaseStartsAndEndsGently() {
    #expect(TileAnimator.ease(0) == 0)
    #expect(TileAnimator.ease(1) == 1)
    #expect(TileAnimator.ease(0.5) == 0.5)
    #expect(TileAnimator.ease(0.1) < 0.1)   // slow to start
    #expect(TileAnimator.ease(0.9) > 0.9)   // and to settle
}

@Test func aDepartedTileIsForgotten() {
    // Otherwise the map grows for the life of the call.
    var animator = TileAnimator()
    _ = animator.resolve(targets: [tile("anna", left), tile("marek", right)], now: 100)
    let remaining = animator.resolve(targets: [tile("anna", left)], now: 101)
    #expect(remaining.count == 1)
    // Rejoining is treated as new, so no travel from a stale position.
    #expect(animator.resolve(targets: [tile("anna", left), tile("marek", right)], now: 102)
            == [tile("anna", left), tile("marek", right)])
}
