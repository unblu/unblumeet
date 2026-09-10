import Testing
import CoreGraphics
@testable import UnbluMeet

@Test func unzoomedCoversTheWholeFrame() {
    let rect = ZoomState.uvRect(scale: 1, center: CGPoint(x: 0.5, y: 0.5))
    #expect(abs(rect.origin.x) < 0.0001)
    #expect(abs(rect.origin.y) < 0.0001)
    #expect(abs(rect.width - 1) < 0.0001)
    #expect(abs(rect.height - 1) < 0.0001)
}

@Test func doubleZoomSamplesHalfTheFrame() {
    let rect = ZoomState.uvRect(scale: 2, center: CGPoint(x: 0.5, y: 0.5))
    #expect(abs(rect.width - 0.5) < 0.0001)
    #expect(abs(rect.height - 0.5) < 0.0001)
    #expect(abs(rect.midX - 0.5) < 0.0001)
    #expect(abs(rect.midY - 0.5) < 0.0001)
}

@Test func zoomWindowStaysInsideTheFrameNearAnEdge() {
    let rect = ZoomState.uvRect(scale: 2, center: CGPoint(x: 0.05, y: 0.05))
    #expect(rect.minX >= -0.0001)
    #expect(rect.minY >= -0.0001)
    #expect(rect.maxX <= 1.0001)
    #expect(rect.maxY <= 1.0001)
}

@Test func zoomWindowStaysInsideTheFrameNearTheOppositeEdge() {
    let rect = ZoomState.uvRect(scale: 4, center: CGPoint(x: 0.99, y: 0.99))
    #expect(rect.maxX <= 1.0001)
    #expect(rect.maxY <= 1.0001)
    #expect(abs(rect.width - 0.25) < 0.0001)
}

@Test func scaleBelowOneIsTreatedAsNoZoom() {
    let rect = ZoomState.uvRect(scale: 0.3, center: CGPoint(x: 0.5, y: 0.5))
    #expect(abs(rect.width - 1) < 0.0001)
}
