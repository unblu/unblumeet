import Testing
import CoreGraphics
@testable import UnbluMeet

private let screen = CGSize(width: 1920, height: 1080)

@Test func theCutOutIsScaledToAShareOfTheScreenHeight() {
    let person = CGSize(width: 1280, height: 720)
    let transform = PresenterOverlay.placement(person: person, screen: screen)
    let placed = CGRect(origin: .zero, size: person).applying(transform)
    #expect(abs(placed.height - screen.height * PresenterOverlay.heightFraction) < 0.5)
}

@Test func theCutOutKeepsItsAspectRatio() {
    let person = CGSize(width: 1280, height: 720)
    let placed = CGRect(origin: .zero, size: person)
        .applying(PresenterOverlay.placement(person: person, screen: screen))
    #expect(abs(placed.width / placed.height - person.width / person.height) < 0.001)
}

@Test func theCutOutSitsInTheBottomRightWithAMargin() {
    // CoreImage's origin is bottom-left, so a small y is the bottom edge.
    let person = CGSize(width: 1280, height: 720)
    let placed = CGRect(origin: .zero, size: person)
        .applying(PresenterOverlay.placement(person: person, screen: screen))
    let margin = screen.height * PresenterOverlay.marginFraction
    #expect(abs(placed.minY - margin) < 0.5)
    #expect(abs(screen.width - placed.maxX - margin) < 0.5)
}

@Test func aPortraitCameraStillFitsInsideTheScreen() {
    let person = CGSize(width: 720, height: 1280)
    let placed = CGRect(origin: .zero, size: person)
        .applying(PresenterOverlay.placement(person: person, screen: screen))
    #expect(placed.minX >= 0)
    #expect(placed.maxX <= screen.width)
    #expect(placed.maxY <= screen.height)
}

@Test func anEmptyCameraFrameIsNotDividedBy() {
    #expect(PresenterOverlay.placement(person: .zero, screen: screen) == .identity)
    #expect(PresenterOverlay.placement(person: CGSize(width: 100, height: 100),
                                       screen: .zero) == .identity)
}
