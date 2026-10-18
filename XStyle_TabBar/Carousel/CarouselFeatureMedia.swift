import CoreGraphics
import CoreVideo
import Foundation
import Metal

/// An optional card-specific shape. Width is relative to the wheel's ordinary card;
/// selected cards fit the viewport while retaining their own aspect ratio.
public struct CarouselCardLayout: Equatable {
    public var aspectRatio: Double
    public var relativeWidth: Double

    public init(aspectRatio: Double, relativeWidth: Double = 1) {
        self.aspectRatio = aspectRatio
        self.relativeWidth = relativeWidth
    }

    func validated(fallbackAspect: Double) -> CarouselCardLayout {
        .init(aspectRatio: aspectRatio.isFinite && aspectRatio > 0 ? min(10, max(0.1, aspectRatio)) : fallbackAspect,
              relativeWidth: relativeWidth.isFinite && relativeWidth > 0 ? min(2, max(0.1, relativeWidth)) : 1)
    }
}

/// A local feature recording and the viewport within its padded source image.
/// Crop coordinates may extend outside the image; those pixels stay transparent.
public struct CarouselFeatureMedia: Equatable {
    public var url: URL
    public var normalizedCrop: CGRect
    public var aspectRatio: Double

    public init(url: URL, normalizedCrop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
                aspectRatio: Double) {
        self.url = url
        self.normalizedCrop = normalizedCrop
        self.aspectRatio = aspectRatio
    }

    var validCrop: CGRect {
        let rect = normalizedCrop
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return rect
    }

    func textureSize(sourceWidth: Int, sourceHeight: Int, framed: Bool = false) -> CGSize {
        let sourceAspect = Double(max(1, sourceWidth)) / Double(max(1, sourceHeight))
        let aspect = aspectRatio.isFinite && aspectRatio > 0 ? min(10, max(0.1, aspectRatio)) : sourceAspect
        let crop = framed ? CGRect(x: 0, y: 0, width: 1, height: 1) : validCrop
        let width = max(1, Double(sourceWidth) * Double(crop.width))
        let height = width / aspect
        let scale = min(1, 2048 / max(width, height))
        return CGSize(width: max(1, (width * scale).rounded()), height: max(1, (height * scale).rounded()))
    }
}

/// The sole renderer queue prepares a fresh video frame before any card samples it.
/// Its mipmapped, linear-premultiplied result is shared by both faces and refraction.
final class CarouselFeatureFramePreparer {
    private struct Uniforms {
        var crop: SIMD4<Float>
        /// 0: linear-premultiplied poster, 1: encoded-premultiplied video, 2: encoded-straight video.
        var alphaMode: UInt32
        var padding0: UInt32 = 0
        var padding1: UInt32 = 0
        var padding2: UInt32 = 0
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private var cache: CVMetalTextureCache?
    private var targets: [Int: MTLTexture] = [:]
    /// Batched video frames encode here, in preparation order, until `commitBatch`.
    private var batch: MTLCommandBuffer?
    private var batchRetained: [(CVMetalTexture, CVPixelBuffer)] = []
#if DEBUG
    private(set) var committedCommandBuffersSnapshot = 0
#endif

    init?(device: MTLDevice, queue: MTLCommandQueue, library: MTLLibrary) {
        self.device = device
        self.queue = queue
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Carousel feature viewport"
        descriptor.vertexFunction = library.makeFunction(name: "carouselFullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "carouselFeatureViewportFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.sAddressMode = .clampToZero
        sampling.tAddressMode = .clampToZero
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let sampler = device.makeSamplerState(descriptor: sampling) else { return nil }
        self.pipeline = pipeline
        self.sampler = sampler
    }

    func clear() { targets.removeAll() }

    func clearVideoFrame(index: Int) { targets[index] = nil }

    func prepare(poster: MTLTexture, media: CarouselFeatureMedia, index: Int, framed: Bool) -> MTLTexture? {
        prepare(source: poster, media: media, index: -index - 1, alphaMode: 0, framed: framed, retained: nil)
    }

    /// A batched frame is encoded into the shared command buffer and committed by `commitBatch`.
    func prepare(buffer: CVPixelBuffer, media: CarouselFeatureMedia, index: Int, batched: Bool = false) -> MTLTexture? {
        if cache == nil { CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) }
        guard let cache else { return nil }
        var image: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer), 0, &image) == kCVReturnSuccess,
            let image, let source = CVMetalTextureGetTexture(image) else { return nil }
        let alpha = CVBufferCopyAttachment(buffer, kCVImageBufferAlphaChannelModeKey, nil) as? String
        let mode: UInt32 = alpha == (kCVImageBufferAlphaChannelMode_StraightAlpha as String) ? 2 : 1
        return prepare(source: source, media: media, index: index, alphaMode: mode,
                       framed: false, retained: (image, buffer), batched: batched)
    }

    /// Commits the frames batched since the last call, in the order they were prepared.
    /// Nothing reads their targets before this, so queue order matches unbatched commits.
    func commitBatch() {
        guard let command = batch else { return }
        let retained = batchRetained
        batch = nil
        batchRetained.removeAll(keepingCapacity: true)
        command.addCompletedHandler { _ in withExtendedLifetime(retained) {} }
        command.commit()
#if DEBUG
        committedCommandBuffersSnapshot += 1
#endif
    }

    private func prepare(source: MTLTexture, media: CarouselFeatureMedia, index: Int,
                         alphaMode: UInt32, framed: Bool,
                         retained: (CVMetalTexture, CVPixelBuffer)?, batched: Bool = false) -> MTLTexture? {
        let size = media.textureSize(sourceWidth: source.width, sourceHeight: source.height, framed: framed)
        let width = Int(size.width), height = Int(size.height)
        let target: MTLTexture
        if let previous = targets[index], previous.width == width, previous.height == height {
            target = previous
        } else {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb,
                width: width, height: height, mipmapped: true)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            guard let made = device.makeTexture(descriptor: descriptor) else { return nil }
            made.label = "Carousel feature \(index)"
            target = made
        }
        let command: MTLCommandBuffer
        if batched, let open = batch {
            command = open
        } else {
            guard let made = queue.makeCommandBuffer() else { return nil }
            made.label = batched ? "Carousel feature frame preparation batch" : "Carousel feature frame preparation"
            command = made
            if batched { batch = made }
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        let crop = framed ? CGRect(x: 0, y: 0, width: 1, height: 1) : media.validCrop
        var uniforms = Uniforms(crop: SIMD4(Float(crop.minX), Float(crop.minY), Float(crop.width), Float(crop.height)),
                                alphaMode: alphaMode)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        guard let blit = command.makeBlitCommandEncoder() else { return nil }
        blit.generateMipmaps(for: target)
        blit.endEncoding()
        if batched {
            if let retained { batchRetained.append(retained) }
        } else {
            command.addCompletedHandler { _ in withExtendedLifetime(retained) {} }
            command.commit()
#if DEBUG
            committedCommandBuffersSnapshot += 1
#endif
        }
        targets[index] = target
        return target
    }
}
