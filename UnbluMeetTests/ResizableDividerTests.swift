import Testing
import Foundation
@testable import UnbluMeet

@Test func widthIsClampedToTheAllowedRange() {
    #expect(ResizableDivider.clampWidth(50, in: 220 ... 640) == 220)
    #expect(ResizableDivider.clampWidth(9000, in: 220 ... 640) == 640)
}

@Test func widthInsideTheRangeIsUnchanged() {
    #expect(ResizableDivider.clampWidth(380, in: 220 ... 640) == 380)
}

@Test func rangeBoundsAreThemselvesValid() {
    #expect(ResizableDivider.clampWidth(220, in: 220 ... 640) == 220)
    #expect(ResizableDivider.clampWidth(640, in: 220 ... 640) == 640)
}
