import Testing
import Foundation
@testable import UnbluMeet

@Test func clampKeepsTheBarReachable() {
    // Dragged fully off screen it could never be dragged back.
    let bounds = CGSize(width: 1000, height: 600)
    let far = BarPosition.clamp(CGSize(width: 9000, height: 9000), within: bounds)
    #expect(far.width == 500)
    #expect(far.height == 300)
}

@Test func clampIsSymmetric() {
    let bounds = CGSize(width: 1000, height: 600)
    let far = BarPosition.clamp(CGSize(width: -9000, height: -9000), within: bounds)
    #expect(far.width == -500)
    #expect(far.height == -300)
}

@Test func clampLeavesModestOffsetsAlone() {
    let bounds = CGSize(width: 1000, height: 600)
    let modest = CGSize(width: 40, height: -25)
    #expect(BarPosition.clamp(modest, within: bounds) == modest)
}

@Test func clampIsANoOpBeforeTheStageHasASize() {
    let offset = CGSize(width: 120, height: 80)
    #expect(BarPosition.clamp(offset, within: .zero) == offset)
}
