import CoreImage
import CoreVideo
import Vision
import os

/// Cuts the presenter out of the camera and draws them over the shared screen,
/// so people see who is talking without a separate tile taking space.
///
/// The composite happens before publishing, so it is what everyone receives
/// rather than a local decoration.
final class PresenterOverlay: @unchecked Sendable {
    /// Fraction of the shared screen's height the person occupies.
    static let heightFraction: CGFloat = 0.32
    /// Margin from the corner, as a fraction of the screen's height.
    static let marginFraction: CGFloat = 0.03
    /// Segmentation is the expensive part; the screen composites at full rate
    /// against whatever the last cut-out was.
    static let segmentEveryNthCameraFrame = 3

    private let context = CIContext()
    private let request = VNGeneratePersonSegmentationRequest()
    private let personLock = OSAllocatedUnfairLock(initialState: CIImage?.none)
    private let enabledLock = OSAllocatedUnfairLock(initialState: false)
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "PresenterOverlay")

    private var frameCount = 0
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    var isEnabled: Bool {
        get { enabledLock.withLock { $0 } }
        set {
            enabledLock.withLock { $0 = newValue }
            if !newValue { personLock.withLock { $0 = nil } }
        }
    }

    var hasPerson: Bool { personLock.withLock { $0 != nil } }

    init() {
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    /// Called with every camera frame.
    func update(camera pixelBuffer: CVPixelBuffer) {
        guard isEnabled else { return }
        frameCount += 1
        guard frameCount % Self.segmentEveryNthCameraFrame == 0 else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("Segmentation failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let maskBuffer = request.results?.first?.pixelBuffer else { return }

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        var mask = CIImage(cvPixelBuffer: maskBuffer)
        mask = mask.transformed(by: CGAffineTransform(
            scaleX: source.extent.width / mask.extent.width,
            y: source.extent.height / mask.extent.height))
        // Softened so the cut-out does not have a hard jagged edge against
        // whatever is behind it.
        mask = mask.clampedToExtent()
            .applyingGaussianBlur(sigma: 2)
            .cropped(to: source.extent)

        let cutOut = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: source,
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])?.outputImage?.cropped(to: source.extent)

        personLock.withLock { $0 = cutOut }
    }

    /// Draws the cut-out over a screen frame, or returns it untouched.
    func compose(onto screen: CVPixelBuffer) -> CVPixelBuffer {
        guard isEnabled, let person = personLock.withLock({ $0 }) else { return screen }

        let background = CIImage(cvPixelBuffer: screen)
        let placed = person.transformed(by: Self.placement(person: person.extent.size,
                                                           screen: background.extent.size))
        guard let composed = CIFilter(name: "CISourceOverCompositing", parameters: [
            kCIInputImageKey: placed,
            kCIInputBackgroundImageKey: background,
        ])?.outputImage?.cropped(to: background.extent),
            let output = makePixelBuffer(size: background.extent.size)
        else { return screen }

        context.render(composed, to: output)
        return output
    }

    /// Scaled to a share of the screen height and pinned to the bottom-right.
    /// CoreImage's origin is bottom-left, so the margin is added directly.
    nonisolated static func placement(person: CGSize, screen: CGSize) -> CGAffineTransform {
        guard person.width > 0, person.height > 0, screen.height > 0 else { return .identity }
        let scale = (screen.height * heightFraction) / person.height
        let margin = screen.height * marginFraction
        let x = screen.width - person.width * scale - margin
        return CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: x, y: margin))
    }

    private func makePixelBuffer(size: CGSize) -> CVPixelBuffer? {
        if pool == nil || poolSize != size {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            ]
            var newPool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &newPool)
            pool = newPool
            poolSize = size
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        return buffer
    }
}
