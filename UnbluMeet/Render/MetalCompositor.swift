import Foundation
import Metal
import MetalKit
import CoreVideo
import simd
import os

private struct TileUniforms {
    var rect: SIMD4<Float>
    var uvRect: SIMD4<Float>
    var sizePx: SIMD2<Float>
    var radiusPx: Float
    var blurPx: Float
}

/// Frames arrive in either layout depending on the decoder that produced them.
private enum FrameTextures {
    case bgra(MTLTexture)
    case nv12(y: MTLTexture, cbcr: MTLTexture)
    case i420(y: MTLTexture, u: MTLTexture, v: MTLTexture)
}

/// Draws every visible tile into a single MTKView.
final class MetalCompositor: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let bgraPipeline: MTLRenderPipelineState
    private let nv12Pipeline: MTLRenderPipelineState
    private let i420Pipeline: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache
    private let store: FrameStore
    private let markStore: MarkStore
    private let markPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let logger = Logger(subsystem: "com.unblu.UnbluMeet", category: "MetalCompositor")
    private let loggedUnsupported = OSAllocatedUnfairLock(initialState: false)
    private let loggedUploadPath = OSAllocatedUnfairLock(initialState: Set<String>())

    /// How many tiles actually rendered on the last frame.
    private let renderedCountLock = OSAllocatedUnfairLock(initialState: 0)

    /// The tiles actually drawn on the last frame.
    private let drawnTilesLock = OSAllocatedUnfairLock(initialState: [Tile]())
    var drawnTiles: [Tile] { drawnTilesLock.withLock { $0 } }

    /// Of the drawn tiles, the ones that actually had a frame this pass.
    private let renderedIDsLock = OSAllocatedUnfairLock(initialState: Set<String>())
    var renderedIDs: Set<String> { renderedIDsLock.withLock { $0 } }

    /// The box being dragged right now, before it is published.
    private let pendingLock = OSAllocatedUnfairLock(
        initialState: (participantID: String?, region: CGRect)(nil, .zero))
    func setPendingCallout(participantID: String?, region: CGRect) {
        pendingLock.withLock { $0 = (participantID, region) }
    }
    private var pendingCallout: (participantID: String?, region: CGRect) {
        pendingLock.withLock { $0 }
    }

    private let draggedLock = OSAllocatedUnfairLock(initialState: String?.none)
    func setDraggedTile(_ participantID: String?) {
        draggedLock.withLock { $0 = participantID }
    }
    private var draggedTile: String? { draggedLock.withLock { $0 } }

    private let dropLock = OSAllocatedUnfairLock(initialState: String?.none)
    func setDropTarget(_ participantID: String?) {
        dropLock.withLock { $0 = participantID }
    }
    private var dropTarget: String? { dropLock.withLock { $0 } }

    /// Colour index of the local author, so the selection box matches the
    /// marks this person draws instead of being an anonymous white outline
    /// that disappears against pale content.
    private let localColorLock = OSAllocatedUnfairLock(initialState: 0)
    var localMarkColorIndex: Int {
        get { localColorLock.withLock { $0 } }
        set { localColorLock.withLock { $0 = newValue } }
    }
    var renderedCount: Int { renderedCountLock.withLock { $0 } }

    // Written by the UI thread via updateLayout, read by the render thread.
    private let layoutLock = NSLock()
    private var participantIDs: [String] = []
    private var mode: LayoutMode = .grid
    private var focusID: String?
    private var zooms: [String: ZoomState] = [:]
    private var localPreviewID: String?
    private var localPreviewOrigin: CGPoint?
    private var stripOffset = 0

    init?(store: FrameStore, markStore: MarkStore) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { return nil }

        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess,
              let textureCache = cache
        else { return nil }

        func makePipeline(fragment: String) -> MTLRenderPipelineState? {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "tile_vertex")
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            // Needed for antialiased rounded corners and the preview's shadow.
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try? device.makeRenderPipelineState(descriptor: descriptor)
        }

        guard let bgra = makePipeline(fragment: "tile_fragment_bgra"),
              let nv12 = makePipeline(fragment: "tile_fragment"),
              let i420 = makePipeline(fragment: "tile_fragment_i420"),
              let shadow = makePipeline(fragment: "tile_fragment_shadow")
        else { return nil }

        let markDescriptor = MTLRenderPipelineDescriptor()
        markDescriptor.vertexFunction = library.makeFunction(name: "mark_vertex")
        markDescriptor.fragmentFunction = library.makeFunction(name: "mark_fragment")
        markDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let marks = try? device.makeRenderPipelineState(descriptor: markDescriptor) else { return nil }

        self.device = device
        self.commandQueue = queue
        self.bgraPipeline = bgra
        self.nv12Pipeline = nv12
        self.i420Pipeline = i420
        self.markPipeline = marks
        self.shadowPipeline = shadow
        self.textureCache = textureCache
        self.store = store
        self.markStore = markStore
        super.init()
    }

    /// Publishes the participants that *should* be on screen.
    func updateLayout(participantIDs: [String], mode: LayoutMode, focusID: String?, stripOffset: Int = 0) {
        layoutLock.lock()
        self.participantIDs = participantIDs
        self.mode = mode
        self.focusID = focusID
        self.stripOffset = stripOffset
        layoutLock.unlock()
    }

    /// True when the point falls in the speaker strip, where scrolling should
    /// page the thumbnails instead of zooming a tile.
    func isStripRegion(at point: CGPoint, viewportSize: CGSize) -> Bool {
        guard viewportSize.height > 0 else { return false }
        layoutLock.lock()
        let isSpeaker = mode == .speaker
        layoutLock.unlock()
        guard isSpeaker else { return false }
        return point.y / viewportSize.height > 0.8
    }

    /// Drawn last, at a fixed corner, and excluded from the tile layout.
    func setLocalPreview(participantID: String?) {
        layoutLock.lock()
        localPreviewID = participantID
        layoutLock.unlock()
    }

    /// 16:9, sized as a fraction of the viewport.
    static func localPreviewRect(viewport: CGSize,
                                 origin: CGPoint? = nil,
                                 widthFraction: CGFloat = 0.18,
                                 margin: CGFloat = 0.02) -> CGRect {
        guard viewport.width > 0, viewport.height > 0 else { return .zero }
        let width = widthFraction
        let heightPixels = (width * viewport.width) * 9.0 / 16.0
        let height = heightPixels / viewport.height

        guard let origin else {
            return CGRect(x: 1 - width - margin, y: 1 - height - margin,
                          width: width, height: height)
        }
        // Clamped so the preview can never be dragged off the edge.
        return CGRect(x: min(max(origin.x, 0), 1 - width),
                      y: min(max(origin.y, 0), 1 - height),
                      width: width, height: height)
    }

    /// Where the preview currently sits, honouring any drag.
    func localPreviewRect(viewportSize: CGSize) -> CGRect {
        layoutLock.lock()
        let origin = localPreviewOrigin
        let id = localPreviewID
        layoutLock.unlock()
        guard id != nil else { return .zero }
        return Self.localPreviewRect(viewport: viewportSize, origin: origin)
    }

    func moveLocalPreview(toTopLeft origin: CGPoint) {
        layoutLock.lock()
        localPreviewOrigin = origin
        layoutLock.unlock()
    }

    func setZoom(_ zoom: ZoomState?, for participantID: String) {
        layoutLock.lock()
        zooms[participantID] = zoom
        layoutLock.unlock()
    }

    private var currentStripOffset: Int {
        layoutLock.lock()
        defer { layoutLock.unlock() }
        return stripOffset
    }

    private var currentLayoutInputs: (ids: [String], mode: LayoutMode, focusID: String?, zooms: [String: ZoomState], localID: String?) {
        layoutLock.lock()
        defer { layoutLock.unlock() }
        return (participantIDs, mode, focusID, zooms, localPreviewID)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        let drawableSize = view.drawableSize

        // Every participant gets a cell, with or without a frame.
        let (allIDs, mode, focus, zooms, localID) = currentLayoutInputs
        let ids = allIDs.filter { $0 != localID }
        var texturesByID: [String: FrameTextures] = [:]
        for id in ids {
            guard let pixelBuffer = store.latest(for: id),
                  let textures = makeTextures(from: pixelBuffer)
            else { continue }
            texturesByID[id] = textures
        }

        let renderedSet = Set(texturesByID.keys)
        renderedCountLock.withLock { $0 = renderedSet.count }

        // No stripOffset here: the caller already sliced participantIDs to
        // the visible window.
        let tiles = TileLayout.layout(mode: mode, participantIDs: ids,
                                      focusID: focus, aspect: 16.0 / 9.0)
        drawnTilesLock.withLock { $0 = tiles }
        renderedIDsLock.withLock { $0 = renderedSet }

        for tile in tiles {
            guard let textures = texturesByID[tile.participantID] else { continue }

            let frameSize = Self.textureSize(textures)
            let tilePixels = CGSize(width: tile.rect.width * drawableSize.width,
                                    height: tile.rect.height * drawableSize.height)
            let aspect = Self.aspectFillRect(frameSize: frameSize, tileSize: tilePixels)
            let uv = Self.compose(aspect: aspect,
                                  zoom: (zooms[tile.participantID] ?? .identity).uvRect)
            var uniforms = TileUniforms(
                rect: SIMD4<Float>(Float(tile.rect.origin.x), Float(tile.rect.origin.y),
                                   Float(tile.rect.width), Float(tile.rect.height)),
                uvRect: SIMD4<Float>(Float(uv.origin.x), Float(uv.origin.y),
                                     Float(uv.width), Float(uv.height)),
                sizePx: SIMD2<Float>(Float(tile.rect.width * drawableSize.width),
                                     Float(tile.rect.height * drawableSize.height)),
                radiusPx: 0, blurPx: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)

            switch textures {
            case let .bgra(color):
                encoder.setRenderPipelineState(bgraPipeline)
                encoder.setFragmentTexture(color, index: 0)
            case let .nv12(y, cbcr):
                encoder.setRenderPipelineState(nv12Pipeline)
                encoder.setFragmentTexture(y, index: 0)
                encoder.setFragmentTexture(cbcr, index: 1)
            case let .i420(y, u, v):
                encoder.setRenderPipelineState(i420Pipeline)
                encoder.setFragmentTexture(y, index: 0)
                encoder.setFragmentTexture(u, index: 1)
                encoder.setFragmentTexture(v, index: 2)
            }

            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Local preview: drawn after the grid so it sits on top, at a fixed
        // corner rather than participating in the layout.
        if let localID,
           let buffer = store.latest(for: localID),
           let textures = makeTextures(from: buffer) {
            let rect = localPreviewRect(viewportSize: drawableSize)
            let frameSize = Self.textureSize(textures)
            let pixels = CGSize(width: rect.width * drawableSize.width,
                                height: rect.height * drawableSize.height)
            let uv = Self.aspectFillRect(frameSize: frameSize, tileSize: pixels)

            // Soft shadow first, on a rect expanded by the blur radius.
            let blur: CGFloat = 18
            let grow = CGSize(width: blur / drawableSize.width, height: blur / drawableSize.height)
            var shadowUniforms = TileUniforms(
                rect: SIMD4<Float>(Float(rect.origin.x - grow.width), Float(rect.origin.y - grow.height),
                                   Float(rect.width + grow.width * 2), Float(rect.height + grow.height * 2)),
                uvRect: SIMD4<Float>(0, 0, 1, 1),
                sizePx: SIMD2<Float>(Float(pixels.width + blur * 2), Float(pixels.height + blur * 2)),
                radiusPx: 14 + Float(blur), blurPx: Float(blur))
            encoder.setRenderPipelineState(shadowPipeline)
            encoder.setVertexBytes(&shadowUniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

            var uniforms = TileUniforms(
                rect: SIMD4<Float>(Float(rect.origin.x), Float(rect.origin.y),
                                   Float(rect.width), Float(rect.height)),
                uvRect: SIMD4<Float>(Float(uv.origin.x), Float(uv.origin.y),
                                     Float(uv.width), Float(uv.height)),
                sizePx: SIMD2<Float>(Float(pixels.width), Float(pixels.height)),
                radiusPx: 14, blurPx: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
            switch textures {
            case let .bgra(color):
                encoder.setRenderPipelineState(bgraPipeline)
                encoder.setFragmentTexture(color, index: 0)
            case let .nv12(y, cbcr):
                encoder.setRenderPipelineState(nv12Pipeline)
                encoder.setFragmentTexture(y, index: 0)
                encoder.setFragmentTexture(cbcr, index: 1)
            case let .i420(y, u, v):
                encoder.setRenderPipelineState(i420Pipeline)
                encoder.setFragmentTexture(y, index: 0)
                encoder.setFragmentTexture(u, index: 1)
                encoder.setFragmentTexture(v, index: 2)
            }
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        // Callout insets first: they use the texture pipelines, and doing
        // them here avoids switching pipeline state per callout inside the
        // mark pass.
        for tile in tiles {
            guard let textures = texturesByID[tile.participantID] else { continue }
            let frameSize = Self.textureSize(textures)
            let tilePixels = CGSize(width: tile.rect.width * drawableSize.width,
                                    height: tile.rect.height * drawableSize.height)
            let uv = Self.compose(aspect: Self.aspectFillRect(frameSize: frameSize, tileSize: tilePixels),
                                  zoom: (zooms[tile.participantID] ?? .identity).uvRect)

            for (callout, _) in markStore.visibleCallouts(for: tile.participantID) {
                guard let regionInTile = Self.regionInTile(callout.region, visible: uv) else { continue }
                let inset = Callout.insetRect(regionInTile: regionInTile)
                guard inset.width > 0, inset.height > 0 else { continue }

                let rect = CGRect(x: tile.rect.minX + inset.minX * tile.rect.width,
                                  y: tile.rect.minY + inset.minY * tile.rect.height,
                                  width: inset.width * tile.rect.width,
                                  height: inset.height * tile.rect.height)
                let insetPixels = CGSize(width: rect.width * drawableSize.width,
                                         height: rect.height * drawableSize.height)

                // Soft shadow first, so the inset reads as floating above the
                // video rather than punched into it.
                let blur: CGFloat = 16
                let grow = CGSize(width: blur / drawableSize.width,
                                  height: blur / drawableSize.height)
                var shadowUniforms = TileUniforms(
                    rect: SIMD4<Float>(Float(rect.origin.x - grow.width),
                                       Float(rect.origin.y - grow.height),
                                       Float(rect.width + grow.width * 2),
                                       Float(rect.height + grow.height * 2)),
                    uvRect: SIMD4<Float>(0, 0, 1, 1),
                    sizePx: SIMD2<Float>(Float(insetPixels.width + blur * 2),
                                         Float(insetPixels.height + blur * 2)),
                    radiusPx: Float(Self.calloutCornerPx) + Float(blur), blurPx: Float(blur))
                encoder.setRenderPipelineState(shadowPipeline)
                encoder.setVertexBytes(&shadowUniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
                encoder.setFragmentBytes(&shadowUniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

                // The region is already in the texture's own uv space, so it
                // is the crop — no conversion, and no image ever left the
                // sender.
                var uniforms = TileUniforms(
                    rect: SIMD4<Float>(Float(rect.origin.x), Float(rect.origin.y),
                                       Float(rect.width), Float(rect.height)),
                    uvRect: SIMD4<Float>(Float(callout.region.origin.x),
                                         Float(callout.region.origin.y),
                                         Float(callout.region.width),
                                         Float(callout.region.height)),
                    sizePx: SIMD2<Float>(Float(rect.width * drawableSize.width),
                                         Float(rect.height * drawableSize.height)),
                    radiusPx: Float(Self.calloutCornerPx), blurPx: 0)
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<TileUniforms>.stride, index: 0)
                switch textures {
                case let .bgra(color):
                    encoder.setRenderPipelineState(bgraPipeline)
                    encoder.setFragmentTexture(color, index: 0)
                case let .nv12(y, cbcr):
                    encoder.setRenderPipelineState(nv12Pipeline)
                    encoder.setFragmentTexture(y, index: 0)
                    encoder.setFragmentTexture(cbcr, index: 1)
                case let .i420(y, u, v):
                    encoder.setRenderPipelineState(i420Pipeline)
                    encoder.setFragmentTexture(y, index: 0)
                    encoder.setFragmentTexture(u, index: 1)
                    encoder.setFragmentTexture(v, index: 2)
                }
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }

        // Marks are stored in frame coordinates, so they run through the same
        // tile rect and zoom rect as the video and therefore track both.
        let palette: [SIMD4<Float>] = [
            SIMD4(1, 0.23, 0.19, 1), SIMD4(1, 0.8, 0, 1),
            SIMD4(0.2, 0.78, 0.35, 1), SIMD4(0.35, 0.34, 0.84, 1),
        ]

        encoder.setRenderPipelineState(markPipeline)
        for tile in tiles {
            guard let textures = texturesByID[tile.participantID] else { continue }
            let frameSize = Self.textureSize(textures)
            let tilePixels = CGSize(width: tile.rect.width * drawableSize.width,
                                    height: tile.rect.height * drawableSize.height)
            let uv = Self.compose(aspect: Self.aspectFillRect(frameSize: frameSize, tileSize: tilePixels),
                                  zoom: (zooms[tile.participantID] ?? .identity).uvRect)
            for (mark, opacity) in markStore.visibleMarks(for: tile.participantID) {
                let screenPoints: [SIMD2<Float>] = mark.points.compactMap { point in
                    guard uv.contains(point) else { return nil }
                    let u = (point.x - uv.minX) / uv.width
                    let v = (point.y - uv.minY) / uv.height
                    return SIMD2(Float(tile.rect.minX + u * tile.rect.width),
                                 Float(tile.rect.minY + v * tile.rect.height))
                }
                guard screenPoints.count >= 2 else { continue }

                // Metal line primitives are always one pixel wide, so a thick
                // stroke has to be expanded into a triangle strip by hand.
                let ribbon = Self.thickStrip(points: screenPoints,
                                             widthPx: 6,
                                             viewport: drawableSize)
                guard ribbon.count >= 4 else { continue }

                var color = palette[abs(mark.colorIndex) % palette.count]
                color.w = 0.75 * Float(opacity)   // translucent, and fading out
                guard color.w > 0.01 else { continue }
                encoder.setVertexBytes(ribbon,
                                       length: MemoryLayout<SIMD2<Float>>.stride * ribbon.count,
                                       index: 0)
                encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: ribbon.count)
            }

            // Where the dragged tile will land.
            if dropTarget == tile.participantID {
                let outline = Self.roundedOutlinePoints(
                    tile.rect.insetBy(dx: tile.rect.width * 0.02, dy: tile.rect.height * 0.02),
                    radius: Self.cornerRadiusInTile(pixels: Self.calloutCornerPx,
                                                    tile: CGRect(x: 0, y: 0, width: 1, height: 1),
                                                    viewport: drawableSize)
                ).map { SIMD2<Float>(Float($0.x), Float($0.y)) }
                let ribbon = Self.thickStrip(points: outline, widthPx: 6, viewport: drawableSize)
                if ribbon.count >= 4 {
                    var color = palette[abs(localMarkColorIndex) % palette.count]
                    color.w = 0.95
                    encoder.setVertexBytes(ribbon,
                                           length: MemoryLayout<SIMD2<Float>>.stride * ribbon.count,
                                           index: 0)
                    encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: ribbon.count)
                }
            }

            // The tile being dragged to a new position.
            if draggedTile == tile.participantID {
                let outline = Self.roundedOutlinePoints(
                    tile.rect,
                    radius: Self.cornerRadiusInTile(pixels: Self.calloutCornerPx,
                                                    tile: CGRect(x: 0, y: 0, width: 1, height: 1),
                                                    viewport: drawableSize)
                ).map { SIMD2<Float>(Float($0.x), Float($0.y)) }
                let ribbon = Self.thickStrip(points: outline, widthPx: 4, viewport: drawableSize)
                if ribbon.count >= 4 {
                    var color = SIMD4<Float>(1, 1, 1, 0.85)
                    encoder.setVertexBytes(ribbon,
                                           length: MemoryLayout<SIMD2<Float>>.stride * ribbon.count,
                                           index: 0)
                    encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: ribbon.count)
                }
            }

            // The box currently being dragged.
            let pending = pendingCallout
            if pending.participantID == tile.participantID,
               let regionInTile = Self.regionInTile(pending.region, visible: uv) {
                let points = Self.roundedOutlinePoints(
                    regionInTile,
                    radius: Self.cornerRadiusInTile(pixels: Self.calloutCornerPx,
                                                    tile: tile.rect,
                                                    viewport: drawableSize)
                ).map { point in
                    SIMD2<Float>(Float(tile.rect.minX + point.x * tile.rect.width),
                                 Float(tile.rect.minY + point.y * tile.rect.height))
                }
                let ribbon = Self.thickStrip(points: points, widthPx: 3, viewport: drawableSize)
                if ribbon.count >= 4 {
                    var color = palette[abs(localMarkColorIndex) % palette.count]
                    color.w = 0.95
                    encoder.setVertexBytes(ribbon,
                                           length: MemoryLayout<SIMD2<Float>>.stride * ribbon.count,
                                           index: 0)
                    encoder.setFragmentBytes(&color, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
                    encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: ribbon.count)
                }
            }
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// A frame-space rect expressed in tile-local coordinates, or nil when
    /// the current crop and zoom have left it off screen.
    static func regionInTile(_ region: CGRect, visible uv: CGRect) -> CGRect? {
        guard uv.width > 0, uv.height > 0 else { return nil }
        let clipped = region.intersection(uv)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return CGRect(x: (clipped.minX - uv.minX) / uv.width,
                      y: (clipped.minY - uv.minY) / uv.height,
                      width: clipped.width / uv.width,
                      height: clipped.height / uv.height)
    }

    /// Corner radius of a callout, in drawable pixels.
    static let calloutCornerPx: CGFloat = 12

    /// That radius expressed as a fraction of the tile, separately per axis —
    /// a tile is rarely square, so one number would skew the corners.
    static func cornerRadiusInTile(pixels: CGFloat, tile: CGRect, viewport: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0,
              tile.width > 0, tile.height > 0 else { return .zero }
        return CGSize(width: pixels / (tile.width * viewport.width),
                      height: pixels / (tile.height * viewport.height))
    }

    /// Closed rounded rectangle as a point list, for thickStrip.
    static func roundedOutlinePoints(_ rect: CGRect, radius: CGSize,
                                     segmentsPerCorner: Int = 5) -> [CGPoint] {
        let rx = min(max(radius.width, 0), rect.width / 2)
        let ry = min(max(radius.height, 0), rect.height / 2)
        guard rx > 0, ry > 0 else {
            return [CGPoint(x: rect.minX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.minX, y: rect.minY)]
        }

        // Centre of each corner arc, with the angle sweep that traces it.
        let corners: [(centre: CGPoint, start: Double)] = [
            (CGPoint(x: rect.maxX - rx, y: rect.minY + ry), -.pi / 2),
            (CGPoint(x: rect.maxX - rx, y: rect.maxY - ry), 0),
            (CGPoint(x: rect.minX + rx, y: rect.maxY - ry), .pi / 2),
            (CGPoint(x: rect.minX + rx, y: rect.minY + ry), .pi),
        ]

        var points: [CGPoint] = []
        for corner in corners {
            for step in 0 ... segmentsPerCorner {
                let angle = corner.start + (.pi / 2) * Double(step) / Double(segmentsPerCorner)
                points.append(CGPoint(x: corner.centre.x + rx * cos(angle),
                                      y: corner.centre.y + ry * sin(angle)))
            }
        }
        if let first = points.first { points.append(first) }
        return points
    }

    /// Centred crop of the source that matches the tile's shape, so video
    /// fills the tile without stretching.
    static func aspectFillRect(frameSize: CGSize, tileSize: CGSize) -> CGRect {
        guard frameSize.width > 0, frameSize.height > 0,
              tileSize.width > 0, tileSize.height > 0
        else { return CGRect(x: 0, y: 0, width: 1, height: 1) }

        let frameAspect = frameSize.width / frameSize.height
        let tileAspect = tileSize.width / tileSize.height

        if frameAspect > tileAspect {
            // Source is wider than the tile: trim the sides.
            let width = tileAspect / frameAspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        } else {
            // Source is taller: trim top and bottom.
            let height = frameAspect / tileAspect
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
    }

    private static func compose(aspect: CGRect, zoom: CGRect) -> CGRect {
        CGRect(x: aspect.minX + zoom.minX * aspect.width,
               y: aspect.minY + zoom.minY * aspect.height,
               width: aspect.width * zoom.width,
               height: aspect.height * zoom.height)
    }

    /// Inverse of the vertex shader: view point → participant under the
    /// cursor plus the position within that participant's video frame.
    func tileHit(at point: CGPoint, viewportSize: CGSize) -> (participantID: String, framePoint: CGPoint)? {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }
        let normalised = CGPoint(x: point.x / viewportSize.width, y: point.y / viewportSize.height)

        let (allIDs, mode, focus, zooms, localID) = currentLayoutInputs
        // Same list as draw(), frame or not — otherwise a click lands on a
        // different tile than the one under the cursor.
        let ready = allIDs.filter { $0 != localID }
        let tiles = TileLayout.layout(mode: mode, participantIDs: ready,
                                      focusID: focus, aspect: 16.0 / 9.0)

        guard let tile = tiles.first(where: { $0.rect.contains(normalised) }) else { return nil }

        let u = (normalised.x - tile.rect.minX) / tile.rect.width
        let v = (normalised.y - tile.rect.minY) / tile.rect.height

        // Must compose aspect crop and zoom exactly as draw() does, or marks
        // land in the wrong place.
        var frameSize = CGSize(width: 16, height: 9)
        if let buffer = store.latest(for: tile.participantID) {
            frameSize = CGSize(width: CVPixelBufferGetWidth(buffer),
                               height: CVPixelBufferGetHeight(buffer))
        }
        let tilePixels = CGSize(width: tile.rect.width * viewportSize.width,
                                height: tile.rect.height * viewportSize.height)
        let uv = Self.compose(aspect: Self.aspectFillRect(frameSize: frameSize, tileSize: tilePixels),
                              zoom: (zooms[tile.participantID] ?? .identity).uvRect)
        return (tile.participantID,
                CGPoint(x: uv.minX + u * uv.width, y: uv.minY + v * uv.height))
    }

    /// Decoded frames arrive in three shapes, all of which must be handled:
    /// hardware H.264 gives native NV12 (2 planes); software VP8/VP9 is
    /// converted by toCVPixelBuffer() into packed BGRA (0 planes); native
    /// I420 (3 planes) is handled for completeness.
    private func makeTextures(from pixelBuffer: CVPixelBuffer) -> FrameTextures? {
        switch CVPixelBufferGetPlaneCount(pixelBuffer) {
        case 0:
            // Packed, non-planar.
            guard let color = plane(pixelBuffer, index: 0, format: .bgra8Unorm) else { return nil }
            noteFormat("bgra")
            return .bgra(color)

        case 2:
            guard let y = plane(pixelBuffer, index: 0, format: .r8Unorm),
                  let cbcr = plane(pixelBuffer, index: 1, format: .rg8Unorm)
            else { return nil }
            noteFormat("nv12")
            return .nv12(y: y, cbcr: cbcr)

        case 3:
            guard let y = plane(pixelBuffer, index: 0, format: .r8Unorm),
                  let u = plane(pixelBuffer, index: 1, format: .r8Unorm),
                  let v = plane(pixelBuffer, index: 2, format: .r8Unorm)
            else { return nil }
            noteFormat("i420")
            return .i420(y: y, u: u, v: v)

        default:
            let shouldLog = loggedUnsupported.withLock { logged -> Bool in
                guard !logged else { return false }
                logged = true
                return true
            }
            if shouldLog {
                logger.error("Unsupported pixel buffer: \(CVPixelBufferGetPlaneCount(pixelBuffer)) plane(s), format \(CVPixelBufferGetPixelFormatType(pixelBuffer))")
            }
            return nil
        }
    }

    /// Expands a polyline into a triangle strip of uniform pixel width.
    static func thickStrip(points: [SIMD2<Float>],
                           widthPx: CGFloat,
                           viewport: CGSize) -> [SIMD2<Float>] {
        guard points.count >= 2, viewport.width > 0, viewport.height > 0 else { return [] }

        let halfX = Float(widthPx / 2 / viewport.width)
        let halfY = Float(widthPx / 2 / viewport.height)

        var strip: [SIMD2<Float>] = []
        strip.reserveCapacity(points.count * 2)

        for index in points.indices {
            // Average the neighbouring segment directions so joints do not gap.
            let previous = index > 0 ? points[index - 1] : points[index]
            let next = index < points.count - 1 ? points[index + 1] : points[index]

            var direction = SIMD2<Float>(next.x - previous.x, next.y - previous.y)
            // Measure direction in pixels, or thickness skews on non-square tiles.
            direction.x *= Float(viewport.width)
            direction.y *= Float(viewport.height)

            let length = max(sqrt(direction.x * direction.x + direction.y * direction.y), 0.0001)
            let normal = SIMD2<Float>(-direction.y / length, direction.x / length)

            let offset = SIMD2<Float>(normal.x * halfX, normal.y * halfY)
            strip.append(SIMD2<Float>(points[index].x + offset.x, points[index].y + offset.y))
            strip.append(SIMD2<Float>(points[index].x - offset.x, points[index].y - offset.y))
        }
        return strip
    }

    private static func textureSize(_ textures: FrameTextures) -> CGSize {
        switch textures {
        case let .bgra(t):        return CGSize(width: t.width, height: t.height)
        case let .nv12(y, _):     return CGSize(width: y.width, height: y.height)
        case let .i420(y, _, _):  return CGSize(width: y.width, height: y.height)
        }
    }

    private func noteFormat(_ format: String) {
        let shouldLog = loggedUploadPath.withLock { seen -> Bool in
            guard !seen.contains(format) else { return false }
            seen.insert(format)
            return true
        }
        if shouldLog { logger.info("Frame format in use: \(format, privacy: .public)") }
    }

    /// Zero-copy via the texture cache when the buffer is IOSurface-backed,
    /// otherwise a CPU copy.
    private func plane(_ pixelBuffer: CVPixelBuffer, index: Int, format: MTLPixelFormat) -> MTLTexture? {
        // Non-planar buffers report 0 planes and must use the whole-buffer
        // accessors; the per-plane ones return 0 for them.
        let isPlanar = CVPixelBufferGetPlaneCount(pixelBuffer) > 0
        let width = isPlanar ? CVPixelBufferGetWidthOfPlane(pixelBuffer, index)
                             : CVPixelBufferGetWidth(pixelBuffer)
        let height = isPlanar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, index)
                              : CVPixelBufferGetHeight(pixelBuffer)

        if CVPixelBufferGetIOSurface(pixelBuffer) != nil {
            var textureRef: CVMetalTexture?
            let result = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault, textureCache, pixelBuffer, nil,
                format, width, height, index, &textureRef
            )
            if result == kCVReturnSuccess, let ref = textureRef,
               let texture = CVMetalTextureGetTexture(ref) {
                noteUploadPath("iosurface")
                return texture
            }
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let base = isPlanar ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, index)
                            : CVPixelBufferGetBaseAddress(pixelBuffer)
        guard let base else { return nil }
        let bytesPerRow = isPlanar ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, index)
                                   : CVPixelBufferGetBytesPerRow(pixelBuffer)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared

        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0, withBytes: base, bytesPerRow: bytesPerRow)
        noteUploadPath("cpu-copy")
        return texture
    }

    private func noteUploadPath(_ path: String) {
        let shouldLog = loggedUploadPath.withLock { seen -> Bool in
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            return true
        }
        if shouldLog { logger.info("Texture upload path in use: \(path, privacy: .public)") }
    }
}
