import MetalKit

/// Both ordinary UI and live GPU scenes feed the same custom optical material.
/// Borrowed Carousel textures are copied on their producer's command buffer;
/// only bounded, consumer-owned crops survive that submission.
@MainActor
final class TabBarOpticsRenderer: NSObject {
    private struct Uniforms {
        var geometry: SIMD4<Float>
        var capture: SIMD4<Float>
        var material: SIMD4<Float>
        var visibleRect: SIMD4<Float>
        var previousCapture: SIMD4<Float>
        var sceneRect: SIMD4<Float>
        var feed: SIMD4<Float>
        var reflection: SIMD4<Float>
        var surface: SIMD4<Float>
        var lighting: SIMD4<Float>
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
    var capsuleInWindow: CGRect = .zero
    var darkMode = false
    var reduceTransparency = false
    /// Scales sampled reflection colors only, from 0 to 1, while they fade in.
    var presence: Double = 1
    /// Frozen inputs travel with the capsule while navigation moves its root.
    /// No texture copy or successive-capture interpolation is involved.
    private var anchors = TabBarReflectionAnchors()

    func retainInputCoordinates() {
        anchors.suspend(at: capsuleInWindow.origin, hasUI: currentUI != nil, hasScene: latestScene != nil)
    }

    func didCaptureUI() { anchors.replaceUI() }
    var settings: TabBarReflectionSettings {
        get { settingsValue }
        set { settingsValue = newValue.sanitized() }
    }
    var onGPUFrame: ((Double) -> Void)?
    /// Called when a newly copied Carousel crop becomes the latest scene.
    var onSceneUpdate: (() -> Void)?
    #if DEBUG
    var onCPUFrame: ((_ drawableAcquisition: Double, _ encoding: Double) -> Void)?
    #endif

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let opticsPipeline: MTLRenderPipelineState
    private let copyPipeline: MTLRenderPipelineState
    private let prepareUIPipeline: MTLRenderPipelineState
    private let washPipeline: MTLRenderPipelineState
    private let washTexture: MTLTexture
    private let emptyTexture: MTLTexture
    private let slots = (0..<3).map { _ in SceneSlot() }
    // Two visible UI frames plus two possible in-flight readers. Never wait or
    // allocate beyond this bounded pool when a capture arrives ahead of the GPU.
    private let decodedUI = (0..<4).map { _ in DecodedUI() }
    private var latestScene: SceneSlot?
    var hasScene: Bool { latestScene != nil }
    private var revision: UInt64 = 0
    private var sequence: UInt64 = 0
    private var completedSequence: UInt64 = 0
    private var framesInFlight = 0
    private var settingsValue = TabBarReflectionSettings.defaults

    init?(view: MTKView) {
        guard let device = view.device, let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "tabBarOpticsVertex"),
              let optics = library.makeFunction(name: "tabBarOpticsFragment"),
              let copy = library.makeFunction(name: "tabBarSceneCopyFragment"),
              let prepareUI = library.makeFunction(name: "tabBarPrepareUIFragment"),
              let wash = library.makeFunction(name: "tabBarWashFragment") else { return nil }
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
            descriptor.label = "Tab bar soft face color field"
            descriptor.fragmentFunction = wash
            washPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
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
        // This scratch field is written then sampled within each command on
        // this renderer's one Metal 3 queue. Tracked resource hazards order its
        // reuse between frames; no extra queue, CPU wait or per-frame allocation.
        let washDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: 64, height: 1, mipmapped: false)
        washDescriptor.storageMode = .private
        washDescriptor.hazardTrackingMode = .tracked
        washDescriptor.usage = [.renderTarget, .shaderRead]
        guard let washTexture = device.makeTexture(descriptor: washDescriptor) else { return nil }
        washTexture.label = "Tab bar 64-sample soft face tint"
        self.washTexture = washTexture
        self.device = device
        self.queue = queue
        super.init()
    }

    func clearScene() {
        revision &+= 1
        latestScene = nil
        anchors.replaceScene()
        // In-flight slots keep their leases until both queues finish using them.
    }

    func invalidateScenePublications() {
        revision &+= 1
        // Retain latestScene; outstanding writes/readers release normally.
    }

    func encodeScene(texture: MTLTexture, commandBuffer: MTLCommandBuffer,
                     sourceInWindow: CGRect, visibleInWindow: CGRect,
                     canPublish: @escaping @MainActor () -> Bool) {
        guard texture.device.registryID == device.registryID,
              commandBuffer.device.registryID == device.registryID,
              commandBuffer.status == .notEnqueued || commandBuffer.status == .enqueued,
              sourceInWindow.width > 0, sourceInWindow.height > 0 else { return }
        let crop = visibleInWindow.intersection(capsuleInWindow.insetBy(dx: -TabBarReflectionSettings.captureMargin, dy: -TabBarReflectionSettings.captureMargin))
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
                self.anchors.replaceScene()
                self.onSceneUpdate?()
            }
        }
    }

    func draw(in view: MTKView, drawable: CAMetalDrawable,
              submit: (MTLCommandBuffer) -> Void) -> Bool {
        // Drop rather than block the main thread when the GPU is behind.
        guard framesInFlight < 2, view.bounds.width > 0, view.bounds.height > 0,
              let command = queue.makeCommandBuffer() else { return false }
        let current = reduceTransparency ? nil : currentUI
        // Present the newest capture immediately. Fading from the old capture
        // added a frame of latency during motion and up to 33ms after idle.
        // The shader's completed-blend path also avoids the old texture's taps.
        let previous = current
        let scene = latestScene
        let offset = anchors.uiOffset(at: capsuleInWindow.origin)
        let sceneOffset = anchors.sceneOffset(at: capsuleInWindow.origin)
        let captureRect = current?.rectInWindow.offsetBy(dx: offset.x, dy: offset.y)
            ?? capsuleInWindow.insetBy(dx: -TabBarReflectionSettings.captureMargin, dy: -TabBarReflectionSettings.captureMargin)
        guard captureRect.width > 0, captureRect.height > 0 else { return false }
        let oldRect = captureRect
        var uniforms = Uniforms(
            geometry: SIMD4(Float(view.bounds.width), Float(view.bounds.height),
                            Float(CGFloat(drawable.texture.width) / view.bounds.width), darkMode ? 1 : 0),
            capture: SIMD4(Float(capsuleInWindow.minX - captureRect.minX),
                           Float(capsuleInWindow.minY - captureRect.minY),
                           Float(captureRect.width), Float(captureRect.height)),
            material: SIMD4(Float(settings.lightDirectionDegrees) * .pi / 180,
                            Float(settings.sharpHighlight), Float(settings.samplingDistance),
                            reduceTransparency ? 1 : 0),
            visibleRect: current == nil ? .zero : SIMD4(0, 0, Float(captureRect.width), Float(captureRect.height)),
            previousCapture: vector(oldRect), sceneRect: vector(scene?.rect.offsetBy(dx: sceneOffset.x, dy: sceneOffset.y) ?? .zero),
            feed: SIMD4(Float(captureRect.minX), Float(captureRect.minY), 1, scene == nil ? 0 : 1),
            reflection: SIMD4(Float(settings.reflectionStrength * presence), Float(settings.reflectionWidth),
                              Float(settings.saturation), Float(settings.softness)),
            surface: SIMD4(Float(settings.surfaceOpacity), Float(settings.faceWash * presence),
                           settings.mode == .faceAndEdges ? 1 : 0, Float(settings.edgeDarkening)),
            lighting: SIMD4(Float(settings.softGlow), Float(settings.sharpHighlightWidth),
                            Float(settings.softGlowWidth), Float(settings.warmCoolBalance)))
        // Carousel's broker supplies the drawable without blocking UIKit.
        // Encoding uses the latest capture and settings after that handoff.
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = view.clearColor
        #if DEBUG
        let encodingStart = onCPUFrame == nil ? 0 : CACurrentMediaTime()
        defer {
            onCPUFrame?(0, CACurrentMediaTime() - encodingStart)
        }
        #endif
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
                                        command: command, prepared: &prepared) else { return false }
            currentDecoded = decoded
        } else { currentDecoded = nil }
        let previousDecoded: DecodedUI?
        if let previous {
            guard let decoded = prepare(previous, keeping: [current, previous].compactMap { $0 },
                                        command: command, prepared: &prepared) else { return false }
            previousDecoded = decoded
        } else { previousDecoded = nil }
        if !reduceTransparency, settings.mode == .faceAndEdges, settings.faceWash > 0 {
            guard encodeWash(command: command, uniforms: &uniforms,
                             previous: previousDecoded?.texture ?? emptyTexture,
                             current: currentDecoded?.texture ?? emptyTexture,
                             scene: scene?.texture ?? emptyTexture) else { return false }
        }
        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return false }
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
        encoder.setFragmentTexture(washTexture, index: 3)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
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
        // `submit` presents `drawable` from this command's scheduled handler,
        // where it can still drop a frame encoded before a reset.
        command.enqueue()
        submit(command)
        return true
    }

    private func encodeWash(command: MTLCommandBuffer, uniforms: inout Uniforms,
                            previous: MTLTexture, current: MTLTexture, scene: MTLTexture) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = washTexture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
        encoder.label = "Prepare 64 soft face colors, nine feed samples each"
        encoder.setRenderPipelineState(washPipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(previous, index: 0)
        encoder.setFragmentTexture(current, index: 1)
        encoder.setFragmentTexture(scene, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
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
