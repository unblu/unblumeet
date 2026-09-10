import Testing
import CoreGraphics
@testable import UnbluMeet

@Test func matchingAspectNeedsNoCrop() {
    let rect = MetalCompositor.aspectFillRect(frameSize: CGSize(width: 1600, height: 900),
                                              tileSize: CGSize(width: 320, height: 180))
    #expect(abs(rect.width - 1) < 0.0001)
    #expect(abs(rect.height - 1) < 0.0001)
}

@Test func widerSourceIsCroppedHorizontally() {
    // 16:9 video into a 1:1 tile — trim the sides, keep full height.
    let rect = MetalCompositor.aspectFillRect(frameSize: CGSize(width: 1920, height: 1080),
                                              tileSize: CGSize(width: 400, height: 400))
    #expect(abs(rect.height - 1) < 0.0001)
    #expect(abs(rect.width - 9.0 / 16.0) < 0.0001)
    #expect(abs(rect.midX - 0.5) < 0.0001)
}

@Test func tallerSourceIsCroppedVertically() {
    // 3:4 video into a 16:9 tile — trim top and bottom, keep full width.
    let rect = MetalCompositor.aspectFillRect(frameSize: CGSize(width: 600, height: 800),
                                              tileSize: CGSize(width: 1600, height: 900))
    #expect(abs(rect.width - 1) < 0.0001)
    #expect(rect.height < 1)
    #expect(abs(rect.midY - 0.5) < 0.0001)
}

@Test func cropStaysInsideTheFrame() {
    let rect = MetalCompositor.aspectFillRect(frameSize: CGSize(width: 4000, height: 200),
                                              tileSize: CGSize(width: 100, height: 400))
    #expect(rect.minX >= -0.0001)
    #expect(rect.minY >= -0.0001)
    #expect(rect.maxX <= 1.0001)
    #expect(rect.maxY <= 1.0001)
}

@Test func degenerateSizesFallBackToTheWholeFrame() {
    let rect = MetalCompositor.aspectFillRect(frameSize: .zero, tileSize: CGSize(width: 10, height: 10))
    #expect(rect == CGRect(x: 0, y: 0, width: 1, height: 1))
}
