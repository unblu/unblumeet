import CoreImage
import CoreVideo
import Vision
import os

enum BackgroundMode: String, CaseIterable, Sendable {
    case none, blur, image
}

/// Segments the person out of a camera frame and composites them over a
/// blurred copy or a flat colour.
final class BackgroundReplacer: @unchecked Sendable {
    private let context = CIContext()
    private let request = VNGeneratePersonSegmentationRequest()
    private let modeLock = OSAllocatedUnfairLock(initialState: BackgroundMode.none)
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "BackgroundReplacer")
    private var pool: CVPixelBufferPool?
    private var poolSize: CGSize = .zero

    var mode: BackgroundMode {
        get { modeLock.withLock { $0 } }
        set { modeLock.withLock { $0 = newValue } }
    }

    init() {
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func process(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer {
        let mode = self.mode
        guard mode != .none else { return pixelBuffer }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logger.error("Segmentation failed: \(error.localizedDescription, privacy: .public)")
            return pixelBuffer
        }

        guard let maskBuffer = request.results?.first?.pixelBuffer else { return pixelBuffer }

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        var mask = CIImage(cvPixelBuffer: maskBuffer)

        // The mask comes back at Vision's own resolution; scale it onto the frame.
        let scale = CGAffineTransform(scaleX: source.extent.width / mask.extent.width,
                                      y: source.extent.height / mask.extent.height)
        mask = mask.transformed(by: scale)

        let background: CIImage
        switch mode {
        case .blur:
            background = source
                .clampedToExtent()
                .applyingGaussianBlur(sigma: 18)
                .cropped(to: source.extent)
        case .image:
            background = CIImage(color: CIColor(red: 0.10, green: 0.13, blue: 0.22))
                .cropped(to: source.extent)
        case .none:
            return pixelBuffer
        }

        let blended = CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: source,
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask,
        ])?.outputImage

        guard let blended,
              let output = makePixelBuffer(size: source.extent.size)
        else { return pixelBuffer }

        context.render(blended, to: output)
        return output
    }

    /// Pooled so a 30fps pipeline is not allocating a full frame every tick.
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
