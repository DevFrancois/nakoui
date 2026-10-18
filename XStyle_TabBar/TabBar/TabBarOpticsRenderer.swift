import MetalKit

/// Both ordinary UI and live GPU scenes feed the same custom optical material.
/// Borrowed Carousel textures are copied on their producer's command buffer;
/// only bounded, consumer-owned crops survive that submission.
@MainActor
final class TabBarOpticsRenderer: NSObject, MTKViewDelegate {
    private struct Uniforms {
        var geometry: SIMD4<Float>
        var capture: SIMD4<Float>
        var material: SIMD4<Float>
        var visibleRect: SIMD4<Float>
        var previousCapture: SIMD4<Float>
        var sceneRect: SIMD4<Float>
        var feed: SIMD4<Float>
    }

    private final class SceneSlot {
        var texture: MTLTexture?
        var rect: CGRect = .zero
        var copying = false
        var readers = 0
    }

    private final class DecodedUI {
        var frame: TabBarUITextureCapture.Frame?
        var texture: MTLTexture?
        var readers = 0
    }

    private struct PreparedUI {
        let slot: DecodedUI
        let frame: TabBarUITextureCapture.Frame
    }

    var currentUI: TabBarUITextureCapture.Frame?
    var previousUI: TabBarUITextureCapture.Frame?
    var capsuleInWindow: CGRect = .zero
    var darkMode = false
    var reduceTransparency = false
    var presentationTime: CFTimeInterval = 0
    var onGPUFrame: ((Double) -> Void)?

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let opticsPipeline: MTLRenderPipelineState
    private let copyPipeline: MTLRenderPipelineState
    private let prepareUIPipeline: MTLRenderPipelineState
    private let emptyTexture: MTLTexture
    private let slots = (0..<3).map { _ in SceneSlot() }
    // Two visible UI frames plus two possible in-flight readers. Never wait or
    // allocate beyond this bounded pool when a capture arrives ahead of the GPU.
    private let decodedUI = (0..<4).map { _ in DecodedUI() }
    private var latestScene: SceneSlot?
    private var revision: UInt64 = 0
    private var sequence: UInt64 = 0
    private var completedSequence: UInt64 = 0
    private var framesInFlight = 0

    init?(view: MTKView) {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "tabBarOpticsVertex"),
              let optics = library.makeFunction(name: "tabBarOpticsFragment"),
              let copy = library.makeFunction(name: "tabBarSceneCopyFragment"),
              let prepareUI = library.makeFunction(name: "tabBarPrepareUIFragment") else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        do {
            descriptor.label = "Tab bar whole UI optical material"
            descriptor.fragmentFunction = optics
            opticsPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.label = "Tab bar owned Carousel crop"
            descriptor.fragmentFunction = copy
            copyPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            descriptor.label = "Tab bar decode UI capture once"
            descriptor.fragmentFunction = prepareUI
            descriptor.colorAttachments[0].pixelFormat = .rgba16Float
            prepareUIPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Tab bar optics pipeline failed: %@", String(describing: error))
            return nil
        }
        let emptyDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: view.colorPixelFormat, width: 1, height: 1, mipmapped: false)
        emptyDescriptor.storageMode = .shared
        emptyDescriptor.usage = .shaderRead
        guard let empty = device.makeTexture(descriptor: emptyDescriptor) else { return nil }
        var transparent: UInt32 = 0
        empty.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                      withBytes: &transparent, bytesPerRow: 4)
        emptyTexture = empty
        self.device = device
        self.queue = queue
        super.init()
        view.delegate = self
    }

    func clearScene() {
        revision &+= 1
        latestScene = nil
        // In-flight slots keep their leases until both queues finish using them.
    }

    func encodeScene(texture: MTLTexture, commandBuffer: MTLCommandBuffer,
                     sourceInWindow: CGRect, visibleInWindow: CGRect,
                     canPublish: @escaping @MainActor () -> Bool) {
        guard texture.device.registryID == device.registryID,
              commandBuffer.device.registryID == device.registryID,
              commandBuffer.status == .notEnqueued || commandBuffer.status == .enqueued,
              sourceInWindow.width > 0, sourceInWindow.height > 0 else { return }
        let crop = visibleInWindow.intersection(capsuleInWindow.insetBy(dx: -104, dy: -104))
        guard !crop.isNull, crop.width > 0, crop.height > 0,
              let slot = slots.first(where: { !$0.copying && $0.readers == 0 && $0 !== latestScene }) else { return }
        let scale = min(1, 320 / max(crop.width, crop.height))
        let width = max(1, Int(ceil(crop.width * scale)))
        let height = max(1, Int(ceil(crop.height * scale)))
        if slot.texture?.width != width || slot.texture?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            slot.texture = device.makeTexture(descriptor: descriptor)
            slot.texture?.label = "Tab bar owned nearby Carousel colors"
        }
        guard let output = slot.texture else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var sourceRect = SIMD4<Float>(
            Float((crop.minX - sourceInWindow.minX) / sourceInWindow.width),
            Float((crop.minY - sourceInWindow.minY) / sourceInWindow.height),
            Float(crop.width / sourceInWindow.width), Float(crop.height / sourceInWindow.height))
        encoder.label = "Copy live Carousel colors without CPU readback"
        encoder.setRenderPipelineState(copyPipeline)
        encoder.setFragmentBytes(&sourceRect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        slot.copying = true
        slot.rect = crop
        sequence &+= 1
        let frameSequence = sequence, frameRevision = revision
        commandBuffer.addCompletedHandler { [weak self, slot] command in
            let succeeded = command.status == .completed
            Task { @MainActor [weak self, slot] in
                slot.copying = false
                guard let self, succeeded, self.revision == frameRevision,
                      frameSequence > self.completedSequence, canPublish() else { return }
                self.completedSequence = frameSequence
                self.latestScene = slot
            }
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        // Drop rather than block the main thread when the GPU is behind.
        guard framesInFlight < 2, view.bounds.width > 0, view.bounds.height > 0,
              let command = queue.makeCommandBuffer() else { return }
        let current = reduceTransparency ? nil : currentUI
        let previous = reduceTransparency ? nil : (previousUI ?? current)
        let scene = latestScene
        let captureRect = current?.rectInWindow ?? capsuleInWindow.insetBy(dx: -104, dy: -104)
        guard captureRect.width > 0, captureRect.height > 0 else { return }
        let oldRect = previous?.rectInWindow ?? captureRect
        let duration = min(1.0 / 30, max(1.0 / 120,
            (current?.captureTime ?? 0) - (previous?.captureTime ?? 0)))
        let blend = current === previous ? 1 : min(1, max(0,
            (presentationTime - (current?.captureTime ?? 0)) / duration))
        var uniforms = Uniforms(
            geometry: SIMD4(Float(view.bounds.width), Float(view.bounds.height),
                            Float(view.drawableSize.width / view.bounds.width), darkMode ? 1 : 0),
            capture: SIMD4(Float(capsuleInWindow.minX - captureRect.minX),
                           Float(capsuleInWindow.minY - captureRect.minY),
                           Float(captureRect.width), Float(captureRect.height)),
            material: SIMD4(-25 * .pi / 180, 2, 96, reduceTransparency ? 1 : 0),
            visibleRect: current == nil ? .zero : SIMD4(0, 0, Float(captureRect.width), Float(captureRect.height)),
            previousCapture: vector(oldRect), sceneRect: vector(scene?.rect ?? .zero),
            feed: SIMD4(Float(captureRect.minX), Float(captureRect.minY), Float(blend), scene == nil ? 0 : 1))
        // Acquire the drawable before encoding preparation, so an unavailable
        // drawable cannot leave an unsubmitted decoded frame in the cache.
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }
        var prepared: [PreparedUI] = []
        var submitted = false
        defer {
            if !submitted {
                for item in prepared where item.slot.frame === item.frame { item.slot.frame = nil }
            }
        }
        let currentDecoded: DecodedUI?
        if let current {
            guard let decoded = prepare(current, keeping: [current, previous].compactMap { $0 },
                                        command: command, prepared: &prepared) else { return }
            currentDecoded = decoded
        } else { currentDecoded = nil }
        let previousDecoded: DecodedUI?
        if let previous {
            guard let decoded = prepare(previous, keeping: [current, previous].compactMap { $0 },
                                        command: command, prepared: &prepared) else { return }
            previousDecoded = decoded
        } else { previousDecoded = nil }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        // Only new captures are read by the GPU. Later display frames reuse the
        // decoded textures without leasing or reading Core Video storage again.
        for item in prepared { item.frame.retainGPURead() }
        currentDecoded?.readers += 1
        if previousDecoded !== currentDecoded { previousDecoded?.readers += 1 }
        scene?.readers += 1
        framesInFlight += 1
        command.label = "Tab bar whole UI optics"
        encoder.setRenderPipelineState(opticsPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(previousDecoded?.texture ?? emptyTexture, index: 0)
        encoder.setFragmentTexture(currentDecoded?.texture ?? emptyTexture, index: 1)
        encoder.setFragmentTexture(scene?.texture ?? emptyTexture, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        command.addCompletedHandler { [weak self, prepared, currentDecoded, previousDecoded, scene] completed in
            let duration = completed.gpuEndTime - completed.gpuStartTime
            let succeeded = completed.status == .completed
            Task { @MainActor [weak self, prepared, currentDecoded, previousDecoded, scene] in
                for item in prepared {
                    item.frame.releaseGPURead()
                    if !succeeded, item.slot.frame === item.frame { item.slot.frame = nil }
                }
                currentDecoded?.readers -= 1
                if previousDecoded !== currentDecoded { previousDecoded?.readers -= 1 }
                scene?.readers -= 1
                guard let self else { return }
                self.framesInFlight -= 1
                self.onGPUFrame?(duration)
            }
        }
        // Preparation and optics share this queue/submission. Subsequent cached
        // reads on the same queue are ordered after the preparing command too.
        submitted = true
        command.commit()
    }

    private func prepare(_ frame: TabBarUITextureCapture.Frame,
                         keeping frames: [TabBarUITextureCapture.Frame],
                         command: MTLCommandBuffer, prepared: inout [PreparedUI]) -> DecodedUI? {
        if let cached = decodedUI.first(where: { $0.frame === frame }) { return cached }
        guard let slot = decodedUI.first(where: { candidate in
            candidate.readers == 0 && !frames.contains(where: { candidate.frame === $0 })
        }) else { return nil }
        let width = frame.texture.width, height = frame.texture.height
        if slot.texture?.width != width || slot.texture?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
            descriptor.storageMode = .private
            descriptor.usage = [.renderTarget, .shaderRead]
            slot.texture = device.makeTexture(descriptor: descriptor)
            slot.texture?.label = "Tab bar cached linear UI colors"
        }
        guard let output = slot.texture else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        encoder.label = "Decode one UI crop for all future reflection taps"
        encoder.setRenderPipelineState(prepareUIPipeline)
        encoder.setFragmentTexture(frame.texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        slot.frame = frame
        prepared.append(PreparedUI(slot: slot, frame: frame))
        return slot
    }

    private func vector(_ rect: CGRect) -> SIMD4<Float> {
        SIMD4(Float(rect.minX), Float(rect.minY), Float(rect.width), Float(rect.height))
    }
}
