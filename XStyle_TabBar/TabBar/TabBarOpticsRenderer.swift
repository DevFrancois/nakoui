import MetalKit

/// Owns only the capsule's optics. The source is a cropped image of neighboring
/// content, so Carousel can later supply its rendered scene through the same path.
@MainActor
final class TabBarOpticsRenderer: NSObject, MTKViewDelegate {
    // Keep this layout in sync with TabBarOpticsUniforms in TabBarOptics.metal.
    private struct Uniforms {
        var geometry: SIMD4<Float>
        var capture: SIMD4<Float>
        var material: SIMD4<Float>
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var source: MTLTexture?
    private var uploadContext: CGContext?
    private var pendingFrame: TabBarBackdropCapture.Frame?
    private var darkMode = false
    private var reduceTransparency = false
    private(set) var isRendering = false

    init?(view: MTKView) {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "tabBarOpticsVertex"),
              let fragment = library.makeFunction(name: "tabBarOpticsFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Tab bar nearby colors and laminate rim"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Tab bar optics pipeline failed: %@", String(describing: error))
            return nil
        }
        self.device = device
        self.queue = queue
        super.init()
        view.delegate = self
    }

    func display(_ frame: TabBarBackdropCapture.Frame, in view: MTKView,
                 darkMode: Bool, reduceTransparency: Bool) {
        guard !isRendering else { return }
        pendingFrame = frame
        self.darkMode = darkMode
        self.reduceTransparency = reduceTransparency
        view.draw()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard !isRendering, let frame = pendingFrame else { return }
        pendingFrame = nil
        guard view.bounds.width > 0, view.bounds.height > 0,
              let source = upload(frame.image),
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let command = queue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        var uniforms = Uniforms(
            geometry: SIMD4(Float(view.bounds.width), Float(view.bounds.height),
                            Float(view.drawableSize.width / view.bounds.width), darkMode ? 1 : 0),
            capture: SIMD4(Float(frame.capsuleRect.minX), Float(frame.capsuleRect.minY),
                           Float(frame.cropSize.width), Float(frame.cropSize.height)),
            material: SIMD4(-25 * .pi / 180, 2, 96, reduceTransparency ? 1 : 0)
        )
        command.label = "Tab bar optics"
        encoder.label = "Colored capsule rim"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        isRendering = true
        // At most one submission owns the reusable source texture. Skip later
        // captures until completion instead of waiting for the GPU or
        // overwriting a texture it is still reading.
        command.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.isRendering = false }
        }
        command.commit()
    }

    private func upload(_ image: CGImage) -> MTLTexture? {
        let width = image.width, height = image.height
        if source?.width != width || source?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false
            )
            descriptor.storageMode = .shared
            descriptor.usage = .shaderRead
            source = device.makeTexture(descriptor: descriptor)
            source?.label = "Tab bar neighboring content"
            uploadContext = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: ((width * 4 + 255) / 256) * 256,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        }
        guard let source, let context = uploadContext, let data = context.data else { return nil }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        source.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                       withBytes: data, bytesPerRow: context.bytesPerRow)
        return source
    }
}
