import Testing
import CoreGraphics
@testable import UnbluMeet

@Test func previewSitsInTheBottomRightCorner() {
    let rect = MetalCompositor.localPreviewRect(viewport: CGSize(width: 1600, height: 900))
    #expect(rect.maxX <= 1.0001)
    #expect(rect.maxY <= 1.0001)
    #expect(rect.minX > 0.5)
    #expect(rect.minY > 0.5)
}

@Test func previewKeepsSixteenByNine() {
    let viewport = CGSize(width: 1600, height: 900)
    let rect = MetalCompositor.localPreviewRect(viewport: viewport)
    let pixelAspect = (rect.width * viewport.width) / (rect.height * viewport.height)
    #expect(abs(pixelAspect - 16.0 / 9.0) < 0.01)
}

@Test func previewStaysSixteenByNineOnATallWindow() {
    let viewport = CGSize(width: 800, height: 1400)
    let rect = MetalCompositor.localPreviewRect(viewport: viewport)
    let pixelAspect = (rect.width * viewport.width) / (rect.height * viewport.height)
    #expect(abs(pixelAspect - 16.0 / 9.0) < 0.01)
}

@Test func previewLeavesAMarginFromTheEdges() {
    let rect = MetalCompositor.localPreviewRect(viewport: CGSize(width: 1600, height: 900),
                                                margin: 0.02)
    #expect(abs(rect.maxX - 0.98) < 0.0001)
    #expect(abs(rect.maxY - 0.98) < 0.0001)
}

@Test func degenerateViewportGivesAnEmptyRect() {
    #expect(MetalCompositor.localPreviewRect(viewport: .zero) == .zero)
}

@Test func draggedPreviewHonoursTheGivenOrigin() {
    let rect = MetalCompositor.localPreviewRect(viewport: CGSize(width: 1600, height: 900),
                                                origin: CGPoint(x: 0.1, y: 0.2))
    #expect(abs(rect.minX - 0.1) < 0.0001)
    #expect(abs(rect.minY - 0.2) < 0.0001)
}

@Test func draggingPastTheLeftOrTopEdgeIsClamped() {
    let rect = MetalCompositor.localPreviewRect(viewport: CGSize(width: 1600, height: 900),
                                                origin: CGPoint(x: -0.5, y: -0.5))
    #expect(abs(rect.minX) < 0.0001)
    #expect(abs(rect.minY) < 0.0001)
}

@Test func draggingPastTheRightOrBottomEdgeIsClamped() {
    let rect = MetalCompositor.localPreviewRect(viewport: CGSize(width: 1600, height: 900),
                                                origin: CGPoint(x: 5, y: 5))
    #expect(rect.maxX <= 1.0001)
    #expect(rect.maxY <= 1.0001)
    #expect(abs(rect.width - 0.18) < 0.0001)
}

@Test func draggedPreviewKeepsItsSize() {
    let viewport = CGSize(width: 1600, height: 900)
    let parked = MetalCompositor.localPreviewRect(viewport: viewport)
    let dragged = MetalCompositor.localPreviewRect(viewport: viewport,
                                                   origin: CGPoint(x: 0.3, y: 0.3))
    #expect(abs(parked.width - dragged.width) < 0.0001)
    #expect(abs(parked.height - dragged.height) < 0.0001)
}
