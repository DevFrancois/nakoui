import CoreVideo
import MetalKit
import QuartzCore
import simd

/// Everything constant across a card is resolved here, once per draw.
private struct CarouselCardUniforms {
    var viewport: SIMD2<Float>
    var center: SIMD2<Float>
    var rotation: SIMD2<Float>
    var quadCenter: SIMD2<Float>
    var quadHalf: SIMD2<Float>
    var imageHalf: SIMD2<Float>
    var frameHalf: SIMD2<Float>
    var uvScale: SIMD2<Float>
    var shadowOffset: SIMD2<Float>
    var imageRadius: Float
    var frameRadius: Float
    var edgeWidth: Float
    var opacity: Float
    var tint: Float
    var shadowAlpha: Float
    var shadowFalloff: Float
    var occlusion: Float
    var occluderCount: UInt32
    /// Turn about the card's vertical axis, radians (0 for a flat card).
    var turn: Float = 0
    /// Press tilt after the turn: bottom edge away (x), right edge away (y), radians.
    var tiltX: Float = 0
    var tiltY: Float = 0
}

private struct CarouselOccluderUniforms {
    var center: SIMD2<Float>
    var cardSize: SIMD2<Float>
    var rotation: SIMD2<Float>
    var opacity: Float
    var cornerRadius: Float = 0
}

/// Shared by every 3D card in a frame. Metal twin: CarouselSlabUniforms, 96 bytes.
private struct CarouselSlabUniforms {
    var stock: SIMD4<Float>
    var absorption: SIMD4<Float>
    /// The camera lighting every card, in screen points, z toward the viewer.
    var eye: SIMD4<Float>
    var thicknessRatio: Float
    var bevelFraction: Float
    var exponent: Float
    var highlight: Float
    var roughness: Float
    var maxLod: Float
    var marginRatio: Float
    var aboveRatio: Float
    var paperRatio: Float
    var refractiveIndex: Float
    /// `CarouselCardLighting`'s index, and its turn about the screen's centre in radians.
    var lighting: Float
    var lightAngle: Float
}

/// Shared full-card color coating. Metal twin: 96 bytes; absent for uncolored cards.
private struct CarouselCardColorUniforms {
    var color0: SIMD4<Float>
    var color1: SIMD4<Float>
    var color2: SIMD4<Float>
    var parameters: SIMD4<Float>
    var linearGeometry: SIMD4<Float>
    var radialGeometry: SIMD4<Float>

    private static func opacity(_ value: Double) -> Float {
        Float(value.isFinite ? min(1, max(0, value)) : 1)
    }

    static func effectiveStyle(_ card3D: CarouselConfiguration.Card3D) -> CarouselCardColorStyle {
        guard card3D.colorStyle != .none, card3D.colorStrength > 0 else { return .none }
        let gradient = card3D.colorGradient
        if card3D.colorStyle == .solid {
            return opacity(gradient.middle.opacity) > 0 ? .solid : .none
        }
        return opacity(gradient.start.opacity) > 0 || opacity(gradient.middle.opacity) > 0 ||
            opacity(gradient.end.opacity) > 0 ? card3D.colorStyle : .none
    }

    init?(_ card3D: CarouselConfiguration.Card3D) {
        guard Self.effectiveStyle(card3D) != .none else { return nil }
        let gradient = card3D.colorGradient
        func bounded(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        func custom(_ stop: CarouselCardColorStop) -> SIMD3<Float> {
            SIMD3(Float(bounded(stop.red, 0...1, 0)), Float(bounded(stop.green, 0...1, 0)),
                  Float(bounded(stop.blue, 0...1, 0)))
        }
        let stops = gradient.usesCustomColors ? (custom(gradient.start), custom(gradient.middle), custom(gradient.end))
            : card3D.colorPalette.sRGBStops
        func linear(_ color: SIMD3<Float>, opacity: Double) -> SIMD4<Float> {
            func channel(_ value: Float) -> Float {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            let alpha = Self.opacity(opacity)
            return SIMD4(channel(color.x) * alpha, channel(color.y) * alpha, channel(color.z) * alpha, alpha)
        }
        color0 = linear(stops.0, opacity: gradient.start.opacity)
        color1 = linear(stops.1, opacity: gradient.middle.opacity)
        color2 = linear(stops.2, opacity: gradient.end.opacity)
        let start = bounded(gradient.startLocation, 0...0.99, 0)
        let end = max(start + 0.01, bounded(gradient.endLocation, 0.01...1, 1))
        parameters = SIMD4(Float(min(1, max(0, card3D.colorStrength))), Float(start),
                           Float(bounded(gradient.middleLocation, 0.05...0.95, 0.5)), Float(end))
        let angle = Float(bounded(gradient.linearAngle, -180...180, 45) * .pi / 180)
        let cosine = cos(angle), sine = sin(angle)
        linearGeometry = SIMD4(cosine, sine, 1 / max(abs(cosine) + abs(sine), 1e-5), 0)
        radialGeometry = SIMD4(Float(2 * bounded(gradient.radialCenterX, 0...1, 0.5) - 1),
                               Float(2 * bounded(gradient.radialCenterY, 0...1, 0.5) - 1),
                               Float(bounded(gradient.radialRadius, 0.05...3, 1)), 0)
    }
}

/// A 3D card's back video: its panel in the back view's points and the video's aspect
/// fill. A zero `backSize` shows no video. Metal twin: 48 bytes.
private struct CarouselBackVideoUniforms {
    var backSize: SIMD2<Float> = .zero
    var panelCenter: SIMD2<Float> = .zero
    var panelHalf: SIMD2<Float> = .zero
    var fit: SIMD2<Float> = SIMD2(1, 1)
    var radius: Float = 0
    var padding0: Float = 0
    var padding1: Float = 0
    var padding2: Float = 0
}

/// A card near a 3D card, whose colours bleed into its edge. Metal twin: 48 bytes.
private struct CarouselBleedNeighbour {
    var center: SIMD2<Float> = .zero
    var rotation: SIMD2<Float> = SIMD2(1, 0)
    var halfSize: SIMD2<Float> = .zero
    var uvScale: SIMD2<Float> = .zero
    var radius: Float = 0
    var opacity: Float = 0
    var lodBias: Float = 0
    var padding: Float = 0
}

/// A 3D card's edge bleed: its neighbours, in draw order. Metal twin: 208 bytes.
private struct CarouselBleedUniforms {
    var count: UInt32 = 0
    var strength: Float = 0
    var height: Float = 0
    var blur: Float = 0
    var neighbours = (CarouselBleedNeighbour(), CarouselBleedNeighbour(), CarouselBleedNeighbour(),
                      CarouselBleedNeighbour())
}

/// Opaque paper above a source face in the promoted stack. Metal twin: 48 bytes.
private struct CarouselRefractionMask {
    var center: SIMD2<Float> = .zero
    var rotation: SIMD2<Float> = SIMD2(1, 0)
    var paperHalf: SIMD2<Float> = .zero
    var turn: SIMD2<Float> = SIMD2(1, 0)
    var distance: Float = 1
    var depth: Float = 0
    var radius: Float = 0
    var opacity: Float = 0
}

/// Actual printed neighbour faces, present only in the improved refraction variant.
/// Metal twin: 448 bytes; the original 48-byte bleed neighbours remain unchanged.
private struct CarouselRefractionNeighbour {
    var imageHalf: SIMD2<Float> = .zero
    var paperHalf: SIMD2<Float> = .zero
    var uvScale: SIMD2<Float> = .zero
    var turn: SIMD2<Float> = SIMD2(1, 0)
    var distance: Float = 1
    var depth: Float = 0
    var paperRadius: Float = 0
    var imageRadius: Float = 0
    var lodBias: Float = 0
    var foreground: Float = 0
    var occlusion: Float = 0
    var occluderCount: UInt32 = 0
    var video = CarouselBackVideoUniforms()
    var occluders = (CarouselRefractionNeighbour.emptyOccluder, CarouselRefractionNeighbour.emptyOccluder,
                     CarouselRefractionNeighbour.emptyOccluder, CarouselRefractionNeighbour.emptyOccluder)
    var promotedMaskCount: UInt32 = 0
    var padding0: Float = 0
    var padding1: Float = 0
    var padding2: Float = 0
    var promotedMasks = (CarouselRefractionMask(), CarouselRefractionMask(),
                         CarouselRefractionMask(), CarouselRefractionMask())

    private static var emptyOccluder: CarouselOccluderUniforms {
        CarouselOccluderUniforms(center: .zero, cardSize: .zero, rotation: SIMD2(1, 0), opacity: 0)
    }
}

/// Metal twin: 1792 bytes. Not bound or prepared by the original refraction variant.
private struct CarouselRefractionUniforms {
    var neighbours = (CarouselRefractionNeighbour(), CarouselRefractionNeighbour(),
                      CarouselRefractionNeighbour(), CarouselRefractionNeighbour())
}

/// A double-sided radiance layer on the paper's screen-visible face. Swift/Metal: 192 bytes.
private struct CarouselSceneSource {
    var sceneToSlab = matrix_identity_float4x4
    var imageHalf: SIMD2<Float> = .zero
    var paperHalf: SIMD2<Float> = .zero
    var uvScale: SIMD2<Float> = .zero
    var paperRadius: Float = 0
    var imageRadius: Float = 0
    var depth: Float = 0
    var opacity: Float = 0
    var lodBias: Float = 0
    var tint: Float = 1
    var index: UInt32 = 0
    var margin: Float = 0
    var video = CarouselBackVideoUniforms()
    /// x: visible-face fade; y: 1 + wheel occlusion for promoted sources, otherwise 0.
    var radiance: SIMD2<Float> = .zero
    var visibilityMask: UInt32 = 0
    var outerRadius: Float = 0
}

/// A shared camera and physical paper scene. Swift/Metal: 1696 bytes.
private struct CarouselSceneUniforms {
    var receiverToScene = matrix_identity_float4x4
    var sceneToReceiver = matrix_identity_float4x4
    var eye: SIMD4<Float> = .zero
    var count: UInt32 = 0
    var receiverIndex: UInt32 = 0
    var beam: SIMD2<Float> = .zero
    var sources = (CarouselSceneSource(), CarouselSceneSource(), CarouselSceneSource(), CarouselSceneSource(),
                   CarouselSceneSource(), CarouselSceneSource(), CarouselSceneSource(), CarouselSceneSource())
}

private struct CarouselSceneDraw {
    let camera: CarouselSceneCamera
    var uniforms: CarouselSceneUniforms
    let images: [MTLTexture]
    let videos: [MTLTexture]
    let foregroundEmitterIndices: Set<UInt32>
}

/// The 3D cards' pipelines and their studio light, made once, on the first 3D frame.
private struct CarouselSlabResources {
    /// The studio prefiltered for the clear coat: one mip level per roughness step.
    let studio: MTLTexture
    /// Diffuse light by surface direction, 1 for a face looking at the screen.
    let irradiance: MTLTexture
}

/// Only requested combinations are compiled. The studio survives comparison changes.
private struct CarouselSlabAppearance: Hashable {
    let material: CarouselCardMaterial
    let colorStyle: CarouselCardColorStyle
    let refinedReflections: Bool
    let refractiveEdges: Bool
    let foregroundReflections: Bool
    let sceneDepth: Bool
    let paperShading: Bool
    let softShadows: Bool
    let skipsHiddenShading: Bool

    init(_ card3D: CarouselConfiguration.Card3D, skipsHiddenShading: Bool) {
        material = card3D.material
        colorStyle = CarouselCardColorUniforms.effectiveStyle(card3D)
        refinedReflections = card3D.refinedReflections
        refractiveEdges = card3D.refractiveEdges
        foregroundReflections = card3D.sceneDepth && card3D.refractiveEdges && card3D.foregroundReflections
        sceneDepth = card3D.sceneDepth
        paperShading = card3D.paperShading
        softShadows = card3D.softShadows
        self.skipsHiddenShading = card3D.sceneDepth && skipsHiddenShading
    }
}

private struct CarouselSlabPipelines {
    let wheel: MTLRenderPipelineState
    let lifted: MTLRenderPipelineState
}

private struct CarouselSlabDraw {
    let resources: CarouselSlabResources
    let pipelines: CarouselSlabPipelines
    let uniforms: CarouselSlabUniforms
    let colorUniforms: CarouselCardColorUniforms?
}

private struct CarouselCardEncodingState {
    var cardPipeline: MTLRenderPipelineState?
    var samplerBound = false
    /// Set when this frame draws its cards as 3D slabs; bound on the first one.
    var slab: CarouselSlabDraw?
    var slabBound = false
    var scene: CarouselSceneDraw?
    var sceneTexturesBound = false
}

/// Native glass owns the card hierarchy; this layer draws only its clean image.
struct CarouselNativeImageSurface {
    let card: CarouselRenderedCard
    let layer: CAMetalLayer
    let size: CGSize
}

/// Cards drawn into `layer` above a live view: physical scene indices, or the
/// legacy promoted suffix beginning at `firstCard`.
struct CarouselFrontPass {
    let layer: CAMetalLayer
    let firstCard: Int
    var sceneIndices: Set<Int>? = nil
}

/// Accepted image appearances contain no layer, texture, or drawable references.
struct CarouselNativeImageCache {
    struct Appearance: Equatable {
        let imageIndex: Int
        let imageGeneration: Int
        let surfaceGeneration: Int
        let size: CGSize
        let pixels: CGSize
        let opacity: Double
        let scrimOpacity: Double
        var featureGeneration: Int = 0
    }

    private var appearances: [ObjectIdentifier: Appearance] = [:]
    var count: Int { appearances.count }

    func contains(layerID: ObjectIdentifier, appearance: Appearance) -> Bool {
        appearances[layerID] == appearance
    }

    mutating func accept(_ frame: [ObjectIdentifier: Appearance]) { appearances = frame }
    mutating func invalidate() { appearances.removeAll(keepingCapacity: true) }
}

/// Native glass and its image change stacking as one card. Unlike the Metal
/// layout, native docking has a whole-card crossover instead of partial cuts.
enum CarouselNativeCardStack {
    static func cards(in frame: CarouselFrame) -> [CarouselRenderedCard] {
        let promotedIndices = Set(frame.promoted.map(\.index))
        var seen: Set<Int> = []
        var ordered = frame.wheel.filter {
            !promotedIndices.contains($0.index) && seen.insert($0.index).inserted
        }
        let wheelIndices = Set(ordered.map(\.index))
        for card in frame.promoted {
            // A promoted pose is authoritative if an externally supplied frame
            // also contains its wheel pose. Never create two surfaces per card.
            ordered.removeAll { $0.index == card.index }
            if card.occlusion > 0.5,
               let position = ordered.firstIndex(where: {
                   wheelIndices.contains($0.index) && card.occluderIndices.contains($0.index)
               }) {
                ordered.insert(card, at: position)
            } else {
                ordered.append(card)
            }
        }
        return ordered
    }
}

/// A target slot is leased until GPU completion, independently of presentation.
/// One slot per allowed in-flight frame prevents unbounded allocations under load.
nonisolated private final class CarouselRenderTargetPool {
    final class Slot {
        var scene: MTLTexture?
        var front: MTLTexture?
        fileprivate var busy = false
    }

    private let lock = NSLock()
    private let slots = (0..<3).map { _ in Slot() }
    private var keepsScene = false
    private var keepsFront = false

    func acquire() -> Slot? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = slots.first(where: { !$0.busy }) else { return nil }
        slot.busy = true
        return slot
    }

    func release(_ slot: Slot) {
        lock.lock()
        if !keepsScene { slot.scene = nil }
        if !keepsFront { slot.front = nil }
        slot.busy = false
        lock.unlock()
    }

    func retainTargets(scene: Bool = false, front: Bool = false) {
        lock.lock()
        if scene { keepsScene = true }
        if front { keepsFront = true }
        lock.unlock()
    }

    /// In-flight commands retain their resources. Do not mutate their leased slots.
    func discardUnused(scene: Bool = true, front: Bool = true) {
        lock.lock()
        defer { lock.unlock() }
        if scene { keepsScene = false }
        if front { keepsFront = false }
        for slot in slots where !slot.busy {
            if scene { slot.scene = nil }
            if front { slot.front = nil }
        }
    }
}

#if targetEnvironment(simulator)
/// Simulator has no drawable presentation callback. Its explicit approximation
/// requires both submission completion and a requested presentation, so obsolete
/// packets that only finish GPU work never become hit-test geometry.
private final class CarouselSimulatorPresentation {
    private let lock = NSLock()
    private var completed = false
    private var requested = false
    private var acknowledged = false
    private let callback: ((TimeInterval) -> Void)?

    init(callback: ((TimeInterval) -> Void)?) { self.callback = callback }

    func complete() { acknowledge(completed: true, requested: false) }
    func present() { acknowledge(completed: false, requested: true) }

    private func acknowledge(completed: Bool, requested: Bool) {
        lock.lock()
        self.completed = self.completed || completed
        self.requested = self.requested || requested
        let ready = self.completed && self.requested && !acknowledged
        if ready { acknowledged = true }
        lock.unlock()
        if ready { callback?(CACurrentMediaTime()) }
    }
}
#endif

/// GPU resources survive all live configuration and presentation changes.
final class CarouselRenderer {
    static let outputPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
    /// The front layer holds encoded sRGB, which Core Animation composites as is.
    static let frontPixelFormat: MTLPixelFormat = .bgra8Unorm
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let library: MTLLibrary
    private let wheelCardPipeline: MTLRenderPipelineState
    private let framedWheelCardPipeline: MTLRenderPipelineState
    private let liftedCardPipeline: MTLRenderPipelineState
    private let framedLiftedCardPipeline: MTLRenderPipelineState
    private let shadowPipeline: MTLRenderPipelineState
    private let backgroundPipeline: MTLRenderPipelineState
    private let frontCompositePipeline: MTLRenderPipelineState
    private let sceneCompositePipeline: MTLRenderPipelineState
    private var reflectionCompositePipeline: MTLRenderPipelineState?
    private var reflectionCompositeUnavailable = false
    private let renderTargets = CarouselRenderTargetPool()
    private(set) var lastSceneRenderSize: CGSize = .zero
    private let sampler: MTLSamplerState
    private let textureStore: CarouselTextureStore
    private var slabResources: CarouselSlabResources?
    private var slabUnavailable = false
    private var slabPipelines: [CarouselSlabAppearance: CarouselSlabPipelines] = [:]
    private var unavailableSlabAppearances: Set<CarouselSlabAppearance> = []
    /// Counts material combinations, each with a wheel and lifted variant.
    var slabPipelineVariantCount: Int { slabPipelines.count }
    /// 3D cards' backs: the pictures printed on their papers' backs, by card index.
    private var backPictures: [Int: MTLTexture] = [:]
    /// A back without a picture shows the bare paper.
    private let noBackPicture: MTLTexture
    /// 3D cards' back videos: where each back shows its video, its newest frame (with the
    /// pixel buffer behind it, which must outlive the texture), and until it has one, a
    /// still of its video. The frames a submission samples stay alive until it completes.
    private var backVideoPanels: [Int: (rect: CGRect, radius: CGFloat, backSize: CGSize)] = [:]
    private var backVideoFrames: [Int: (texture: CVMetalTexture, buffer: CVPixelBuffer)] = [:]
    private var backVideoStills: [Int: (image: CGImage, texture: MTLTexture)] = [:]
    private var videoTextureCache: CVMetalTextureCache?
    private var videoFramesInFlight: [(texture: CVMetalTexture, buffer: CVPixelBuffer)] = []
    private var featurePreparer: CarouselFeatureFramePreparer?
    /// Set between `beginFeatureVideoFrames()` and `commitFeatureVideoFrames()`.
    private var batchesFeatureVideoFrames = false
    private var featurePosters: [Int: (image: CGImage, media: CarouselFeatureMedia, framed: Bool, texture: MTLTexture)] = [:]
    private var featureFrames: [Int: MTLTexture] = [:]
    func featureFrameIdentitySnapshot(for index: Int) -> ObjectIdentifier? {
        featureFrames[index].map(ObjectIdentifier.init)
    }
    private var featureGenerations: [Int: Int] = [:]
    func featureFrameGenerationSnapshot(for index: Int) -> UInt64? {
        featureGenerations[index].map { UInt64(truncatingIfNeeded: $0) }
    }
    private let inFlight = DispatchSemaphore(value: 3)
    private var nativeImages = CarouselNativeImageCache()
    private var imageGeneration = 0
    private var nextSurfaceGeneration = 0
    private var surfaceGenerations: [ObjectIdentifier: Int] = [:]
    private(set) var lastNativeImageDrawCount = 0
    /// Tests compare each card's tight quad with one 64 points larger on every side.
    var optimizesCardDraws = true

    init?(view: MTKView) {
        assert(MemoryLayout<CarouselCardUniforms>.stride == 120)
        assert(MemoryLayout<CarouselOccluderUniforms>.stride == 32)
        assert(MemoryLayout<CarouselSlabUniforms>.stride == 96)
        assert(MemoryLayout<CarouselCardColorUniforms>.stride == 96)
        assert(MemoryLayout<CarouselBleedNeighbour>.stride == 48)
        assert(MemoryLayout<CarouselBleedUniforms>.stride == 208)
        assert(MemoryLayout<CarouselRefractionMask>.stride == 48)
        assert(MemoryLayout<CarouselRefractionNeighbour>.stride == 448)
        assert(MemoryLayout<CarouselRefractionUniforms>.stride == 1792)
        assert(MemoryLayout<CarouselSceneSource>.stride == 192)
        assert(MemoryLayout<CarouselSceneUniforms>.stride == 1696)
        assert(MemoryLayout<CarouselBackVideoUniforms>.stride == 48)
        guard let device = MTLCreateSystemDefaultDevice() else {
            Self.reportInitializationFailure("no Metal device")
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            Self.reportInitializationFailure("command queue creation")
            return nil
        }
        guard let library = device.makeDefaultLibrary() else {
            Self.reportInitializationFailure("default shader library")
            return nil
        }
        guard let vertex = library.makeFunction(name: "carouselFullscreenVertex") else {
            Self.reportInitializationFailure("carouselFullscreenVertex function")
            return nil
        }
        guard let cardVertex = library.makeFunction(name: "carouselCardVertex") else {
            Self.reportInitializationFailure("carouselCardVertex function")
            return nil
        }
        let fragments: [MTLFunction]
        do {
            fragments = try [(false, false, false), (true, false, false), (false, true, false),
                             (true, true, false), (false, true, true)].map {
                try Self.cardFragment(library: library, framed: $0.0, promoted: $0.1, shadowOnly: $0.2)
            }
        } catch {
            Self.reportInitializationFailure("carouselCardFragment function: \(error)")
            return nil
        }
        guard let backgroundFragment = library.makeFunction(name: "carouselBackgroundFragment") else {
            Self.reportInitializationFailure("carouselBackgroundFragment function")
            return nil
        }
        guard let frontFragment = library.makeFunction(name: "carouselFrontCompositeFragment") else {
            Self.reportInitializationFailure("carouselFrontCompositeFragment function")
            return nil
        }
        guard let sceneFragment = library.makeFunction(name: "carouselSceneCompositeFragment") else {
            Self.reportInitializationFailure("carouselSceneCompositeFragment function")
            return nil
        }
        guard let store = CarouselTextureStore(device: device, queue: queue) else {
            Self.reportInitializationFailure("texture store creation")
            return nil
        }
        let clear = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: 1, height: 1,
                                                             mipmapped: false)
        clear.usage = .shaderRead
        guard let blank = device.makeTexture(descriptor: clear) else {
            Self.reportInitializationFailure("blank texture")
            return nil
        }
        var transparent: [UInt8] = [0, 0, 0, 0]
        blank.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: &transparent, bytesPerRow: 4)
        blank.label = "Carousel blank card back"
        noBackPicture = blank
        self.device = device
        self.queue = queue
        self.library = library
        textureStore = store
        view.device = device
        view.colorPixelFormat = Self.outputPixelFormat
        view.clearColor = MTLClearColor(red: 0.539479489, green: 0.672443157, blue: 0.973445290, alpha: 1)
        view.framebufferOnly = true
        view.sampleCount = 1
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.maximumDrawableCount = 3
        }

        let cards = zip(["Carousel wheel card", "Carousel framed wheel card", "Carousel lifted card",
                         "Carousel framed lifted card", "Carousel card shadow"], fragments).map {
            Self.cardDescriptor(label: $0.0, vertex: cardVertex, fragment: $0.1)
        }
        let background = MTLRenderPipelineDescriptor()
        background.label = "Carousel preview gradient"
        background.vertexFunction = vertex
        background.fragmentFunction = backgroundFragment
        background.colorAttachments[0].pixelFormat = view.colorPixelFormat
        let frontComposite = MTLRenderPipelineDescriptor()
        frontComposite.label = "Carousel front cards for Core Animation"
        frontComposite.vertexFunction = vertex
        frontComposite.fragmentFunction = frontFragment
        frontComposite.colorAttachments[0].pixelFormat = Self.frontPixelFormat
        let sceneComposite = MTLRenderPipelineDescriptor()
        sceneComposite.label = "Carousel moving scene upscale"
        sceneComposite.vertexFunction = vertex
        sceneComposite.fragmentFunction = sceneFragment
        sceneComposite.colorAttachments[0].pixelFormat = Self.outputPixelFormat
        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.mipFilter = .linear
        sampling.sAddressMode = .clampToEdge
        sampling.tAddressMode = .clampToEdge
        do {
            wheelCardPipeline = try device.makeRenderPipelineState(descriptor: cards[0])
            framedWheelCardPipeline = try device.makeRenderPipelineState(descriptor: cards[1])
            liftedCardPipeline = try device.makeRenderPipelineState(descriptor: cards[2])
            framedLiftedCardPipeline = try device.makeRenderPipelineState(descriptor: cards[3])
            shadowPipeline = try device.makeRenderPipelineState(descriptor: cards[4])
            backgroundPipeline = try device.makeRenderPipelineState(descriptor: background)
            frontCompositePipeline = try device.makeRenderPipelineState(descriptor: frontComposite)
            sceneCompositePipeline = try device.makeRenderPipelineState(descriptor: sceneComposite)
            guard let sampler = device.makeSamplerState(descriptor: sampling) else {
                Self.reportInitializationFailure("sampler creation")
                return nil
            }
            self.sampler = sampler
        } catch {
            print("Carousel Metal pipeline error: \(error)")
            return nil
        }
    }

    /// Cards blend premultiplied over the drawable, or over the front cards' target. A 3D
    /// card's clear plastic keeps a share of what lies behind it per channel: its second
    /// output (dual-source blending).
    private static func cardDescriptor(label: String, vertex: MTLFunction, fragment: MTLFunction,
                                       clear: Bool = false) -> MTLRenderPipelineDescriptor {
        let card = MTLRenderPipelineDescriptor()
        card.label = label
        card.vertexFunction = vertex
        card.fragmentFunction = fragment
        card.colorAttachments[0].pixelFormat = outputPixelFormat
        card.colorAttachments[0].isBlendingEnabled = true
        card.colorAttachments[0].rgbBlendOperation = .add
        card.colorAttachments[0].alphaBlendOperation = .add
        card.colorAttachments[0].sourceRGBBlendFactor = .one
        card.colorAttachments[0].sourceAlphaBlendFactor = .one
        card.colorAttachments[0].destinationRGBBlendFactor = clear ? .source1Color : .oneMinusSourceAlpha
        card.colorAttachments[0].destinationAlphaBlendFactor = clear ? .source1Alpha : .oneMinusSourceAlpha
        return card
    }

    /// The 3D cards' pipelines and studio light, made on the first frame that draws them:
    /// the studio is baked into two small cubes by compute, in a command buffer committed
    /// ahead of that frame's own. Nothing of it exists while 3D cards are off.
    private func prepareSlabResources() -> CarouselSlabResources? {
        if let slabResources { return slabResources }
        guard !slabUnavailable else { return nil }
        slabUnavailable = true
        guard let prefilterFunction = library.makeFunction(name: "carouselStudioPrefilter"),
              let referenceFunction = library.makeFunction(name: "carouselStudioReference"),
              let irradianceFunction = library.makeFunction(name: "carouselStudioIrradiance") else {
            Self.reportInitializationFailure("3D card functions")
            return nil
        }
        do {
            let prefilter = try device.makeComputePipelineState(function: prefilterFunction)
            let reference = try device.makeComputePipelineState(function: referenceFunction)
            let diffuse = try device.makeComputePipelineState(function: irradianceFunction)
            // 64-point faces down to 2: the clear coat's roughness steps by a fifth per level.
            let studioDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba16Float,
                                                                              size: 64, mipmapped: true)
            studioDescriptor.mipmapLevelCount = 6
            studioDescriptor.usage = [.shaderRead, .shaderWrite]
            studioDescriptor.storageMode = .private
            // An odd size puts a texel centre exactly on the face looking at the screen.
            let irradianceDescriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .r16Float,
                                                                                  size: 17, mipmapped: false)
            irradianceDescriptor.usage = [.shaderRead, .shaderWrite]
            irradianceDescriptor.storageMode = .private
            guard let studio = device.makeTexture(descriptor: studioDescriptor),
                  let irradiance = device.makeTexture(descriptor: irradianceDescriptor) else { return nil }
            let levels = (0..<studio.mipmapLevelCount).compactMap {
                studio.makeTextureView(pixelFormat: studio.pixelFormat, textureType: .typeCube,
                                       levels: $0..<($0 + 1), slices: 0..<6)
            }
            guard levels.count == studio.mipmapLevelCount,
                  let faceLight = device.makeBuffer(length: MemoryLayout<Float>.stride, options: .storageModePrivate),
                  let command = queue.makeCommandBuffer(),
                  let encoder = command.makeComputeCommandEncoder() else { return nil }
            studio.label = "Carousel 3D card studio"
            irradiance.label = "Carousel 3D card diffuse light"
            command.label = "Carousel 3D card studio"
            encoder.label = "Carousel 3D card studio"
            let group = MTLSize(width: 8, height: 8, depth: 1)
            func groups(_ side: Int) -> MTLSize { MTLSize(width: (side + 7) / 8, height: (side + 7) / 8, depth: 6) }
            encoder.setComputePipelineState(prefilter)
            for (level, target) in levels.enumerated() {
                var roughness = Float(level) / Float(levels.count - 1)
                encoder.setTexture(target, index: 0)
                encoder.setBytes(&roughness, length: MemoryLayout<Float>.stride, index: 0)
                encoder.dispatchThreadgroups(groups(max(1, studio.width >> level)), threadsPerThreadgroup: group)
            }
            // The light on a face looking at the screen, then every direction's relative to it.
            encoder.setComputePipelineState(reference)
            encoder.setBuffer(faceLight, offset: 0, index: 0)
            encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            encoder.setComputePipelineState(diffuse)
            encoder.setTexture(irradiance, index: 0)
            encoder.dispatchThreadgroups(groups(irradiance.width), threadsPerThreadgroup: group)
            encoder.endEncoding()
            command.commit()
            let resources = CarouselSlabResources(studio: studio, irradiance: irradiance)
            slabResources = resources
            return resources
        } catch {
            Self.reportInitializationFailure("3D card pipelines: \(error)")
            return nil
        }
    }

    private func prepareSlabPipelines(_ appearance: CarouselSlabAppearance) -> CarouselSlabPipelines? {
        if let pipelines = slabPipelines[appearance] { return pipelines }
        guard !unavailableSlabAppearances.contains(appearance),
              let vertex = library.makeFunction(name: "carouselSlabVertex") else { return nil }
        do {
            func pipeline(promoted: Bool, label: String) throws -> MTLRenderPipelineState {
                let values = MTLFunctionConstantValues()
                var promoted = promoted
                var reflections = appearance.refinedReflections
                var edges = appearance.refractiveEdges
                var foreground = appearance.foregroundReflections
                var sceneDepth = appearance.sceneDepth
                var skipsHiddenShading = appearance.skipsHiddenShading
                var paper = appearance.paperShading
                var shadows = appearance.softShadows
                var material = UInt32(CarouselCardMaterial.allCases.firstIndex(of: appearance.material) ?? 0)
                var colorStyle = UInt32(CarouselCardColorStyle.allCases.firstIndex(of: appearance.colorStyle) ?? 0)
                values.setConstantValue(&promoted, type: .bool, index: 1)
                values.setConstantValue(&reflections, type: .bool, index: 5)
                values.setConstantValue(&edges, type: .bool, index: 6)
                values.setConstantValue(&paper, type: .bool, index: 7)
                values.setConstantValue(&shadows, type: .bool, index: 8)
                values.setConstantValue(&material, type: .uint, index: 9)
                values.setConstantValue(&colorStyle, type: .uint, index: 10)
                values.setConstantValue(&foreground, type: .bool, index: 11)
                values.setConstantValue(&sceneDepth, type: .bool, index: 12)
                values.setConstantValue(&skipsHiddenShading, type: .bool, index: 13)
                let fragment = try library.makeFunction(name: "carouselSlabFragment", constantValues: values)
                return try device.makeRenderPipelineState(descriptor: Self.cardDescriptor(label: label,
                    vertex: vertex, fragment: fragment, clear: true))
            }
            let pipelines = try CarouselSlabPipelines(
                wheel: pipeline(promoted: false, label: "Carousel 3D wheel · \(appearance.material.title)"),
                lifted: pipeline(promoted: true, label: "Carousel 3D lifted · \(appearance.material.title)"))
            slabPipelines[appearance] = pipelines
            return pipelines
        } catch {
            unavailableSlabAppearances.insert(appearance)
            Self.reportInitializationFailure("3D card material: \(error)")
            return nil
        }
    }

    /// Each variant compiles only its parts: the Metal frame ring, the lifted card's
    /// shadow and occlusion fade, or a native card's shadow without its image.
    private static func cardFragment(library: MTLLibrary, framed: Bool, promoted: Bool,
                                     shadowOnly: Bool) throws -> MTLFunction {
        let values = MTLFunctionConstantValues()
        var framed = framed, promoted = promoted, shadowOnly = shadowOnly
        values.setConstantValue(&framed, type: .bool, index: 0)
        values.setConstantValue(&promoted, type: .bool, index: 1)
        values.setConstantValue(&shadowOnly, type: .bool, index: 2)
        return try library.makeFunction(name: "carouselCardFragment", constantValues: values)
    }

    private static func reportInitializationFailure(_ stage: String) {
#if DEBUG
        print("Carousel Metal initialization failed: \(stage)")
#endif
    }

    func setImages(_ images: [String], rendered: [String: CGImage] = [:]) {
        guard images != textureStore.images || !rendered.isEmpty else { return }
        textureStore.setImages(images, rendered: rendered)
        imageGeneration &+= 1
        invalidateNativeImages()
    }

    /// Feature media is printed on both sides of the same card. Other cards keep their
    /// prepared poster; live frames never replace or invalidate the ordinary image list.
    func setFeaturePoster(_ image: CGImage?, media: CarouselFeatureMedia, index: Int, framed: Bool = true) {
        guard let image else {
            if featurePosters.removeValue(forKey: index) != nil {
                featureGenerations[index, default: 0] &+= 1
            }
            return
        }
        if let previous = featurePosters[index], previous.image === image,
           previous.media == media, previous.framed == framed { return }
        if featurePreparer == nil {
            featurePreparer = CarouselFeatureFramePreparer(device: device, queue: queue, library: library)
        }
        guard let source = textureStore.texture(from: image, label: "Carousel feature poster"),
              let prepared = featurePreparer?.prepare(poster: source, media: media, index: index, framed: framed) else { return }
        featurePosters[index] = (image, media, framed, prepared)
        featureGenerations[index, default: 0] &+= 1
    }

    func setFeatureVideoFrame(_ buffer: CVPixelBuffer, media: CarouselFeatureMedia, index: Int) {
        if featurePreparer == nil {
            featurePreparer = CarouselFeatureFramePreparer(device: device, queue: queue, library: library)
        }
        guard let texture = featurePreparer?.prepare(buffer: buffer, media: media, index: index,
                                                      batched: batchesFeatureVideoFrames) else { return }
        featureFrames[index] = texture
        featureGenerations[index, default: 0] &+= 1
    }

    /// Until `commitFeatureVideoFrames()`, new feature video frames share one command buffer.
    func beginFeatureVideoFrames() { batchesFeatureVideoFrames = true }

    /// Commits the batched frames before any scene that samples them is encoded.
    func commitFeatureVideoFrames() {
        batchesFeatureVideoFrames = false
        featurePreparer?.commitBatch()
    }

#if DEBUG
    var featurePreparationCommitsSnapshot: Int { featurePreparer?.committedCommandBuffersSnapshot ?? 0 }
#endif

    func clearFeatureVideoFrame(index: Int) {
        guard featureFrames.removeValue(forKey: index) != nil else { return }
        featurePreparer?.clearVideoFrame(index: index)
        featureGenerations[index, default: 0] &+= 1
    }

    func clearFeatureMedia() {
        guard !featureFrames.isEmpty || !featurePosters.isEmpty else { return }
        featureFrames.removeAll()
        featurePosters.removeAll()
        featureGenerations.removeAll()
        featurePreparer?.clear()
        featurePreparer = nil
        imageGeneration &+= 1
        invalidateNativeImages()
    }

    private func featureTexture(for index: Int) -> MTLTexture? {
        featureFrames[index] ?? featurePosters[index]?.texture
    }

    private func frontTexture(for index: Int) -> MTLTexture {
        featureTexture(for: index) ?? textureStore.textures[index]
    }

    private func backTexture(for index: Int) -> MTLTexture {
        featureTexture(for: index) ?? backPictures[index] ?? noBackPicture
    }

    /// Prints `image` on the back of card `index`'s paper, for 3D cards; nil leaves it bare.
    func setBackPicture(_ image: CGImage?, index: Int) {
        backPictures[index] = image.flatMap { textureStore.texture(from: $0, label: "Carousel card back") }
        if image == nil {
            backVideoPanels[index] = nil
            backVideoFrames[index] = nil
            backVideoStills[index] = nil
        }
    }

    func removeBackPictures() {
        backPictures.removeAll()
        backVideoPanels.removeAll()
        backVideoFrames.removeAll()
        backVideoStills.removeAll()
    }

    /// Where card `index`'s printed back shows its video, in the points of the back view
    /// laid out at `backSize`; nil for none.
    func setBackVideoPanel(_ rect: CGRect?, cornerRadius: CGFloat, backSize: CGSize, index: Int) {
        backVideoPanels[index] = rect.flatMap { $0.width > 0 && $0.height > 0 ? ($0, cornerRadius, backSize) : nil }
    }

    /// Card `index`'s newest back video frame, printed in its panel until the next one.
    func setBackVideoFrame(_ buffer: CVPixelBuffer, index: Int) {
        if videoTextureCache == nil {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &videoTextureCache)
        }
        guard let cache = videoTextureCache else { return }
        var texture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, buffer, nil, .bgra8Unorm_srgb,
                                                        CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer),
                                                        0, &texture) == kCVReturnSuccess, let texture else { return }
        backVideoFrames[index] = (texture, buffer)
    }

    /// What card `index`'s panel shows until it has a frame: a still of its video.
    func setBackVideoStill(_ image: CGImage?, index: Int) {
        guard backVideoStills[index]?.image !== image else { return }
        backVideoStills[index] = image.flatMap { image in
            textureStore.texture(from: image, label: "Carousel card back video still").map { (image, $0) }
        }
    }

    /// Card `index`'s video starts again: its still shows until the first new frame.
    func clearBackVideoFrame(index: Int) {
        backVideoFrames[index] = nil
    }

    /// A resumed or reattached layer must not rely on old presented contents.
    func invalidateNativeImages() {
        nativeImages.invalidate()
        surfaceGenerations.removeAll(keepingCapacity: true)
    }

    func configureNativeSurface(layer: CAMetalLayer) {
        let layerID = ObjectIdentifier(layer)
        // iOS already assigns a device to a new CAMetalLayer. That does not
        // configure its default non-sRGB drawable for our sRGB pipelines.
        let drawableChanged = layer.device !== device || layer.pixelFormat != Self.outputPixelFormat ||
            !layer.framebufferOnly || layer.maximumDrawableCount != 3
        if layer.device !== device { layer.device = device }
        if layer.pixelFormat != Self.outputPixelFormat { layer.pixelFormat = Self.outputPixelFormat }
        if layer.colorspace?.name != CGColorSpace.sRGB {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        if !layer.framebufferOnly { layer.framebufferOnly = true }
        if layer.maximumDrawableCount != 3 { layer.maximumDrawableCount = 3 }
        if !layer.allowsNextDrawableTimeout { layer.allowsNextDrawableTimeout = true }
        if !layer.presentsWithTransaction { layer.presentsWithTransaction = true }
        if layer.isOpaque { layer.isOpaque = false }
        // Allocation serials prevent reused object addresses matching the old
        // layer's appearance. Ordinary preparation preserves cache identity.
        if surfaceGenerations[layerID] == nil || drawableChanged {
            nextSurfaceGeneration &+= 1
            surfaceGenerations[layerID] = nextSurfaceGeneration
        }
    }

    /// The transparent layer above a live card's view: it holds the promoted cards drawn
    /// after that card, so they stay in front of the live view.
    func configureFrontLayer(_ layer: CAMetalLayer, drawableSize: CGSize, synchronized: Bool) {
        if layer.device !== device { layer.device = device }
        if layer.pixelFormat != Self.frontPixelFormat { layer.pixelFormat = Self.frontPixelFormat }
        if layer.colorspace?.name != CGColorSpace.sRGB {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        if !layer.framebufferOnly { layer.framebufferOnly = true }
        if layer.maximumDrawableCount != 3 { layer.maximumDrawableCount = 3 }
        if !layer.allowsNextDrawableTimeout { layer.allowsNextDrawableTimeout = true }
        if layer.isOpaque { layer.isOpaque = false }
        if layer.presentsWithTransaction != synchronized { layer.presentsWithTransaction = synchronized }
        if layer.drawableSize != drawableSize { layer.drawableSize = drawableSize }
    }

    /// Frees the front cards' target once no live view needs it.
    func releaseFrontResources() {
        renderTargets.discardUnused(scene: false)
    }

    /// Drops cached intermediate targets after the corresponding feature is disabled.
    /// Leased targets are retained until their command buffers complete.
    func releaseMotionResources() {
        renderTargets.discardUnused(front: false)
    }

    private func appearance(for surface: CarouselNativeImageSurface, frame: CarouselFrame)
        -> CarouselNativeImageCache.Appearance {
        let layerID = ObjectIdentifier(surface.layer)
        if surfaceGenerations[layerID] == nil {
            nextSurfaceGeneration &+= 1
            surfaceGenerations[layerID] = nextSurfaceGeneration
        }
        let promotion = min(1, max(0, surface.card.pose.promotion))
        return CarouselNativeImageCache.Appearance(imageIndex: surface.card.index,
            imageGeneration: imageGeneration, surfaceGeneration: surfaceGenerations[layerID]!,
            size: surface.size, pixels: surface.layer.drawableSize, opacity: surface.card.pose.opacity,
            scrimOpacity: frame.scrimOpacity * (1 - promotion),
            featureGeneration: featureGenerations[surface.card.index, default: 0])
    }

    private func effectiveFront(_ front: CarouselFrontPass?, frame: CarouselFrame,
                                native: Bool) -> CarouselFrontPass? {
        guard !native, let front else { return nil }
        if frame.card3D.isEnabled && frame.card3D.sceneDepth, let indices = front.sceneIndices {
            return indices.isEmpty ? nil : front
        }
        return front.firstCard >= 0 && front.firstCard < frame.promoted.count ? front : nil
    }

    /// Main-thread preparation only. The broker acquires these layers on its worker.
    /// Recompute this against the newest scene at handoff; a missing target rejects
    /// the packet instead of falling back to acquisition on the touch thread.
    func drawableTargets(frame: CarouselFrame, nativeSurfaces: [CarouselNativeImageSurface]? = nil,
                         front: CarouselFrontPass? = nil, mainLayer: CAMetalLayer) -> [CAMetalLayer] {
        var result = [mainLayer]
        for surface in nativeSurfaces ?? [] {
            let key = ObjectIdentifier(surface.layer)
            if !nativeImages.contains(layerID: key, appearance: appearance(for: surface, frame: frame)) {
                result.append(surface.layer)
            }
        }
        if let front = effectiveFront(front, frame: frame, native: nativeSurfaces != nil) {
            result.append(front.layer)
        }
        return result
    }

    private func makeTarget(existing: MTLTexture?, width: Int, height: Int, label: String) -> MTLTexture? {
        if let existing, existing.width == width, existing.height == height { return existing }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: Self.outputPixelFormat,
            width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    /// Only texture consumers with a split front layer need this blend pass.
    private func prepareReflectionCompositePipeline() -> MTLRenderPipelineState? {
        if let reflectionCompositePipeline { return reflectionCompositePipeline }
        guard !reflectionCompositeUnavailable else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Carousel reflected front cards"
        descriptor.vertexFunction = library.makeFunction(name: "carouselFullscreenVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "carouselSceneCompositeFragment")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = Self.outputPixelFormat
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            reflectionCompositePipeline = pipeline
            return pipeline
        } catch {
            reflectionCompositeUnavailable = true
            print("Carousel reflection composite pipeline error: \(error)")
            return nil
        }
    }

    /// Called only by the host's display link through MTKView.draw().
    /// `front` moves its scene indices, or its legacy promoted suffix, into
    /// `front.layer`, drawn in the same submission and presented with it.
    @discardableResult
    func draw(frame: CarouselFrame, in view: MTKView,
              nativeSurfaces: [CarouselNativeImageSurface]? = nil,
              front: CarouselFrontPass? = nil,
              synchronizeLayers: Bool = false,
              acquiredDrawables: [ObjectIdentifier: CAMetalDrawable]? = nil,
              motionScale: Double = 1,
              skipsHiddenShading: Bool = false,
              onRenderTexture: ((MTLTexture, MTLCommandBuffer) -> Void)? = nil,
              submit: ((MTLCommandBuffer, @escaping () -> Void) -> Void)? = nil,
              updateLayers: (() -> Void)? = nil,
              onSubmitted: (() -> Void)? = nil,
              onPresented: ((TimeInterval) -> Void)? = nil,
              onCompleted: ((Bool) -> Void)? = nil) -> Bool {
        let native = nativeSurfaces != nil
        if !native && (nativeImages.count > 0 || !surfaceGenerations.isEmpty) { invalidateNativeImages() }
        videoFramesInFlight.removeAll(keepingCapacity: true)
        var submitted = false
        defer { if !submitted { invalidateNativeImages() } }
        guard frame.size.width > 0, frame.size.height > 0,
              inFlight.wait(timeout: .now()) == .success else { return false }
        defer { if !submitted { inFlight.signal() } }
        guard let targetSlot = renderTargets.acquire() else { return false }
        defer { if !submitted { renderTargets.release(targetSlot) } }
        let frame = CarouselGeometry.applyingSceneDepth(to: frame)
        // 3D cards are Metal's own: native glass cards stay flat. One camera, above the
        // screen's centre, lights them all.
        let slab = frame.card3D.isEnabled && !native ? prepareSlabResources().flatMap { resources -> CarouselSlabDraw? in
            let card3D = frame.card3D
            guard let pipelines = prepareSlabPipelines(CarouselSlabAppearance(card3D, skipsHiddenShading: skipsHiddenShading)) else { return nil }
            let layers = CarouselSlab.layers(thickness: card3D.thickness)
            let width = Double(frame.size.width), height = Double(frame.size.height)
            return CarouselSlabDraw(resources: resources, pipelines: pipelines, uniforms: CarouselSlabUniforms(
                stock: SIMD4(SIMD3(repeating: CarouselSlab.stock), 1),
                absorption: SIMD4(CarouselSlab.absorption, 0),
                eye: SIMD4(Float(width / 2), Float(height / 2), Float(1.2 * max(width, height)), 1),
                thicknessRatio: Float(card3D.thickness / CarouselSlab.cardWidthMillimeters),
                bevelFraction: Float(card3D.bevelFraction),
                exponent: Float(CarouselSlab.exponent(card3D)),
                highlight: Float(card3D.highlight), roughness: Float(card3D.roughness),
                maxLod: Float(resources.studio.mipmapLevelCount - 1),
                marginRatio: Float(card3D.margin / CarouselSlab.cardWidthMillimeters),
                aboveRatio: Float(layers.above / CarouselSlab.cardWidthMillimeters),
                paperRatio: Float(layers.paper / CarouselSlab.cardWidthMillimeters),
                refractiveIndex: CarouselSlab.refractiveIndex,
                lighting: Float(CarouselCardLighting.allCases.firstIndex(of: card3D.lighting) ?? 0),
                lightAngle: Float(card3D.lightAngle * .pi / 180)),
                colorUniforms: CarouselCardColorUniforms(card3D))
        } : nil
        let scene = slab != nil && frame.card3D.sceneDepth ? prepareScene(frame: frame) : nil
        guard let mainLayer = view.layer as? CAMetalLayer else { return false }
        func acquire(_ layer: CAMetalLayer) -> CAMetalDrawable? {
            if let acquiredDrawables { return acquiredDrawables[ObjectIdentifier(layer)] }
            return layer.nextDrawable()
        }
        guard let drawable = acquire(mainLayer),
              drawable.texture.pixelFormat == Self.outputPixelFormat,
              drawable.texture.width == Int(mainLayer.drawableSize.width),
              drawable.texture.height == Int(mainLayer.drawableSize.height),
              let command = queue.makeCommandBuffer() else { return false }
        var imageDrawables: [(CarouselNativeImageSurface, CAMetalDrawable)] = []
        var appearances: [ObjectIdentifier: CarouselNativeImageCache.Appearance] = [:]
        for surface in nativeSurfaces ?? [] {
            guard surface.size.width > 0, surface.size.height > 0,
                  surface.size.width.isFinite, surface.size.height.isFinite else { return false }
            let layerID = ObjectIdentifier(surface.layer)
            let appearance = appearance(for: surface, frame: frame)
            appearances[layerID] = appearance
            if nativeImages.contains(layerID: layerID, appearance: appearance) { continue }
            guard let image = acquire(surface.layer),
                  image.texture.pixelFormat == Self.outputPixelFormat,
                  image.texture.width == Int(surface.layer.drawableSize.width),
                  image.texture.height == Int(surface.layer.drawableSize.height) else { return false }
            imageDrawables.append((surface, image))
        }
        let front = effectiveFront(front, frame: frame, native: native)
        let scale = slab == nil || !motionScale.isFinite ? 1 : min(1, max(0.75, motionScale))
        let width = max(1, Int((Double(drawable.texture.width) * scale).rounded()))
        let height = max(1, Int((Double(drawable.texture.height) * scale).rounded()))
        let destination = MTLRenderPassDescriptor()
        let sceneTarget: MTLTexture?
        if scale < 1 || onRenderTexture != nil {
            renderTargets.retainTargets(scene: true)
            guard let texture = makeTarget(existing: targetSlot.scene, width: width, height: height,
                                            label: "Carousel sampleable moving scene") else { return false }
            targetSlot.scene = texture
            sceneTarget = texture
            destination.colorAttachments[0].texture = texture
        } else {
            sceneTarget = nil
            destination.colorAttachments[0].texture = drawable.texture
            // Keep the reduced target for the next gesture. The host explicitly
            // releases it when the motion-resolution feature is disabled.
        }
        var frontDrawable: CAMetalDrawable?
        var frontCards: MTLTexture?
        if let front {
            renderTargets.retainTargets(front: true)
            guard let image = acquire(front.layer),
                  image.texture.pixelFormat == Self.frontPixelFormat,
                  image.texture.width == drawable.texture.width,
                  image.texture.height == drawable.texture.height,
                  let texture = makeTarget(existing: targetSlot.front, width: width, height: height,
                    label: "Carousel cards in front of a live card") else { return false }
            targetSlot.front = texture
            frontCards = texture
            frontDrawable = image
        } else {
            targetSlot.front = nil
            renderTargets.discardUnused(scene: false)
        }
        command.label = native ? "Carousel native glass images and shadows" : "Carousel direct frame"
        // The opaque gradient covers the complete drawable.
        destination.colorAttachments[0].loadAction = .dontCare
        destination.colorAttachments[0].storeAction = .store
        guard let output = command.makeRenderCommandEncoder(descriptor: destination) else { return false }
        output.label = native ? "Carousel native glass backdrop and shadows" : "Carousel wheel and promoted cards"
        var outputState = CarouselCardEncodingState(slab: slab, scene: scene)
        output.setRenderPipelineState(backgroundPipeline)
        var scrimOpacity = Float(frame.scrimOpacity)
        output.setFragmentBytes(&scrimOpacity, length: MemoryLayout<Float>.stride, index: 0)
        output.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        let sceneFrontIndices = scene != nil ? front?.sceneIndices : nil
        for card in frame.wheel where sceneFrontIndices?.contains(card.index) != true {
            draw(card, frame: frame, promoted: false, pixelWidth: width, pixelHeight: height,
                 shadowOnly: native, state: &outputState, encoder: output)
        }
        let backCards = sceneFrontIndices.map { indices in frame.promoted.filter { !indices.contains($0.index) } } ??
            (front.map { Array(frame.promoted.prefix($0.firstCard)) } ?? frame.promoted)
        for card in backCards {
            draw(card, frame: frame, promoted: true, pixelWidth: width, pixelHeight: height,
                 shadowOnly: native, state: &outputState, encoder: output)
        }
        output.endEncoding()
        if let sceneTarget {
            let composite = MTLRenderPassDescriptor()
            composite.colorAttachments[0].texture = drawable.texture
            composite.colorAttachments[0].loadAction = .dontCare
            composite.colorAttachments[0].storeAction = .store
            guard let encoder = command.makeRenderCommandEncoder(descriptor: composite) else { return false }
            encoder.label = "Carousel moving scene upscale"
            encoder.setRenderPipelineState(sceneCompositePipeline)
            encoder.setFragmentTexture(sceneTarget, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        if let front, let frontDrawable, let frontCards {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = frontCards
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.label = "Carousel cards in front of a live card"
            var state = CarouselCardEncodingState(slab: slab, scene: scene)
            if let indices = sceneFrontIndices {
                for card in frame.wheel where indices.contains(card.index) {
                    draw(card, frame: frame, promoted: false, pixelWidth: width, pixelHeight: height,
                         state: &state, encoder: encoder)
                }
            }
            let cardsAboveLive = sceneFrontIndices.map { indices in frame.promoted.filter { indices.contains($0.index) } } ??
                Array(frame.promoted[front.firstCard...])
            for card in cardsAboveLive {
                draw(card, frame: frame, promoted: true, pixelWidth: width, pixelHeight: height,
                     state: &state, encoder: encoder)
            }
            encoder.endEncoding()
            let composite = MTLRenderPassDescriptor()
            composite.colorAttachments[0].texture = frontDrawable.texture
            composite.colorAttachments[0].loadAction = .dontCare
            composite.colorAttachments[0].storeAction = .store
            guard let output = command.makeRenderCommandEncoder(descriptor: composite) else { return false }
            output.label = "Carousel front cards for Core Animation"
            output.setRenderPipelineState(frontCompositePipeline)
            output.setFragmentTexture(frontCards, index: 0)
            output.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            output.endEncoding()
        }
        for (surface, image) in imageDrawables {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = image.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.label = "Carousel native glass card \(surface.card.index) image"
            var state = CarouselCardEncodingState()
            let card = surface.card
            let promotion = min(1, max(0, card.pose.promotion))
            let localFrame = CarouselFrame(size: surface.size, wheel: [], promoted: [],
                scrimOpacity: frame.scrimOpacity * (1 - promotion),
                glass: .init(style: .liquidGlass, padding: 0))
            let localCard = CarouselRenderedCard(index: card.index,
                pose: .init(x: Double(surface.size.width) / 2, y: Double(surface.size.height) / 2,
                            height: Double(surface.size.height), opacity: card.pose.opacity,
                            aspect: Double(surface.size.width / max(1, surface.size.height))))
            // The image fades in Metal; the native material scrubs its effect.
            // Docking reorders that whole node; image-only cuts would expose its
            // glass backing above the nearer wheel card.
            draw(localCard, frame: localFrame, promoted: true,
                 pixelWidth: image.texture.width, pixelHeight: image.texture.height,
                 state: &state, encoder: encoder)
            encoder.endEncoding()
        }
        if let onRenderTexture, let sceneTarget {
            // The ordinary drawable has already consumed sceneTarget. Complete the
            // exported image now without changing Carousel's UIKit layer ordering.
            // Native glass's main pass contains shadows, so explicitly draw the card
            // imagery here; live UIKit overlays themselves are never captured.
            if native {
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = sceneTarget
                pass.colorAttachments[0].loadAction = .dontCare
                pass.colorAttachments[0].storeAction = .store
                guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
                encoder.label = "Carousel native card imagery for reflections"
                encoder.setRenderPipelineState(backgroundPipeline)
                encoder.setFragmentBytes(&scrimOpacity, length: MemoryLayout<Float>.stride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                var state = CarouselCardEncodingState()
                for card in frame.wheel {
                    draw(card, frame: frame, promoted: false, pixelWidth: width, pixelHeight: height,
                         state: &state, encoder: encoder)
                }
                for card in frame.promoted {
                    draw(card, frame: frame, promoted: true, pixelWidth: width, pixelHeight: height,
                         state: &state, encoder: encoder)
                }
                encoder.endEncoding()
            } else if let frontCards {
                guard let pipeline = prepareReflectionCompositePipeline() else { return false }
                let pass = MTLRenderPassDescriptor()
                pass.colorAttachments[0].texture = sceneTarget
                pass.colorAttachments[0].loadAction = .load
                pass.colorAttachments[0].storeAction = .store
                guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return false }
                encoder.label = "Carousel full scene for reflections"
                encoder.setRenderPipelineState(pipeline)
                encoder.setFragmentTexture(frontCards, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                encoder.endEncoding()
            }
            // Consumers append work to this submission. The target slot and current
            // video pixel buffers remain alive until every appended pass completes.
            onRenderTexture(sceneTarget, command)
        }
        let videoFrames = videoFramesInFlight
        command.addCompletedHandler { [inFlight, renderTargets, targetSlot, weak self] buffer in
            withExtendedLifetime(videoFrames) {}
            renderTargets.release(targetSlot)
            inFlight.signal()
            if buffer.status != .completed {
                DispatchQueue.main.async {
                    self?.invalidateNativeImages()
                    onCompleted?(false)
                }
            } else {
                onCompleted?(true)
            }
        }
        // Presentation acknowledges displayed transforms; GPU completion only
        // releases resources and reports failure. Simulator's Metal headers omit
        // drawable presentation notifications, so its approximation is explicit.
#if targetEnvironment(simulator)
        let simulatorPresentation = CarouselSimulatorPresentation(callback: onPresented)
        command.addCompletedHandler { buffer in
            if buffer.status == .completed { simulatorPresentation.complete() }
        }
#else
        drawable.addPresentedHandler { shown in
            onPresented?(shown.presentedTime)
        }
#endif
        // The frame is fully encoded and has no remaining rejection path.
        // Register CPU metadata before commit can trigger a driver callback.
        onSubmitted?()
        let acceptNativeImages = { [weak self] in
            guard native, let self else { return }
            self.nativeImages.accept(appearances)
            self.surfaceGenerations = self.surfaceGenerations.filter { appearances[$0.key] != nil }
        }
        let present = {
            // The broker invokes this on main after scheduling and generation
            // validation. Its captured native snapshot belongs to this GPU frame.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updateLayers?()
            imageDrawables.forEach { $0.1.present() }
            drawable.present()
            frontDrawable?.present()
            acceptNativeImages()
            CATransaction.commit()
#if targetEnvironment(simulator)
            simulatorPresentation.present()
#endif
        }
        if let submit {
            // Reserve ordering before the next main-thread video preparation can
            // overwrite a shared feature texture. Commit itself runs on the worker.
            command.enqueue()
            submit(command, present)
        } else if synchronizeLayers || native {
            // Deliberate synchronous debug/test reference path.
            command.commit()
            command.waitUntilScheduled()
            present()
        } else {
            updateLayers?()
            command.present(drawable)
            if let frontDrawable { command.present(frontDrawable) }
            command.commit()
            acceptNativeImages()
#if targetEnvironment(simulator)
            simulatorPresentation.present()
#endif
        }
        lastSceneRenderSize = CGSize(width: width, height: height)
        lastNativeImageDrawCount = imageDrawables.count
        submitted = true
        return true
    }

    private func draw(_ card: CarouselRenderedCard, frame: CarouselFrame, promoted: Bool,
                      pixelWidth: Int, pixelHeight: Int, shadowOnly: Bool = false,
                      state: inout CarouselCardEncodingState, encoder: MTLRenderCommandEncoder) {
        guard card.index >= 0, card.index < textureStore.textures.count,
              card.pose.opacity > 0.001, card.pose.height > 0 else { return }
        let texture = frontTexture(for: card.index)
        let pose = card.pose
        // Once a turning card faces away, its back face (a view above) covers it: a flat
        // card draws only its shadow, a 3D card its whole slab, whose edge shows around it.
        let slab = shadowOnly ? nil : state.slab
        let shadowOnly = shadowOnly || (slab == nil && cos(pose.turn) < 0)
        let amount = promoted ? min(1, max(0, pose.promotion)) : 0
        guard !shadowOnly || amount > 0 else { return }
        let padding = max(0, frame.glass.padding)
        let build = slab == nil ? nil : CarouselSlab.build(pose: pose, padding: padding, card3D: frame.card3D)
        let thickness = build?.thickness ?? 0
        let shadow = CarouselCardShadow(promotion: amount, softShadows: slab != nil && frame.card3D.softShadows)
        // Cards wholly outside the viewport, shadow included, are not drawn.
        if state.scene == nil {
            guard CarouselRasterBounds.scissor(pose: pose, size: frame.size, pixelWidth: pixelWidth,
                                               pixelHeight: pixelHeight, promotion: amount,
                                               padding: padding, thickness: thickness, shadow: shadow) != nil else { return }
        }
        let occluders = state.scene == nil && promoted && card.occlusion > 0 ? frame.wheel.filter {
            card.occluderIndices.contains($0.index) && $0.pose.opacity > 0.001
        }.prefix(32).map {
            let outer = $0.pose.outerSize(padding: padding)
            let corner = slab == nil ? $0.pose.outerCornerRadius(padding: padding)
                : CarouselSlab.cornerRadius(pose: $0.pose, padding: padding, card3D: frame.card3D)
            return CarouselOccluderUniforms(center: SIMD2(Float($0.pose.x), Float($0.pose.y)),
                                           cardSize: SIMD2(Float(outer.width), Float(outer.height)),
                                           rotation: SIMD2(Float(cos($0.pose.angle)), Float(sin($0.pose.angle))),
                                           opacity: Float($0.pose.opacity),
                                           cornerRadius: Float(corner))
        } : []
        // Plain wheel cards, the default, run no frame, shadow or occlusion code.
        let framed = !shadowOnly && frame.glass.style == .metal && padding > 0
        let lifted = shadowOnly || amount > 0 || !occluders.isEmpty
        // A 3D card's frame is part of its slab, so slabs need no framed variants.
        let pipeline = slab.map { lifted ? $0.pipelines.lifted : $0.pipelines.wheel } ??
            (shadowOnly ? shadowPipeline : lifted
                ? (framed ? framedLiftedCardPipeline : liftedCardPipeline)
                : (framed ? framedWheelCardPipeline : wheelCardPipeline))
        if state.cardPipeline !== pipeline {
            encoder.setRenderPipelineState(pipeline)
            state.cardPipeline = pipeline
        }
        let cosine = cos(pose.angle), sine = sin(pose.angle)
        let opacity = min(1, max(0, pose.opacity))
        let frameHalf = SIMD2(pose.width / 2, pose.height / 2) + padding
        // A 3D card's image fills its paper, inside the clear margin.
        let inset = build.map { max(0, $0.margin - padding) } ?? 0
        let width = pose.width - 2 * inset, height = pose.height - 2 * inset
        let imageHalf = SIMD2(width / 2, height / 2)
        let corner = slab == nil ? pose.imageCornerRadius : CarouselSlab.imageCornerRadius(pose: pose, card3D: frame.card3D)
        let imageRadius = max(0, corner - inset)
        // Aspect-fill the image: the longer side is cropped evenly.
        let imageAspect = Double(texture.width) / Double(texture.height), cardAspect = width / height
        let fit = featureTexture(for: card.index) != nil ? SIMD2<Double>(1, 1) :
            (imageAspect > cardAspect ? SIMD2(cardAspect / imageAspect, 1) : SIMD2(1, imageAspect / cardAspect))
        let blur = shadow.blur
        let shadowOffset = SIMD2(shadow.offset * sine, shadow.offset * cosine)
        // A lifted card's quad is its shadow's box: four standard deviations fall below
        // the fragment cutoff and already include the image's antialiasing margin.
        var quadCenter = SIMD2<Double>.zero
        let margin = CarouselRasterBounds.antialiasingMargin(size: frame.size, pixelWidth: pixelWidth,
                                                             pixelHeight: pixelHeight)
        var quadHalf = frameHalf + margin
        if shadow.alpha > 0 {
            quadCenter = shadowOffset
            quadHalf = frameHalf + 4 * blur
        }
        // A turning slab's quad lies on the screen: its projected box and shadow.
        let sceneGeometry = state.scene.map {
            CarouselSceneCardGeometry(pose: pose, padding: padding, card3D: frame.card3D, camera: $0.camera)
        }
        if let geometry = sceneGeometry {
            var bounds = geometry.projectedBounds(margin: margin)
            if shadow.alpha > 0 {
                let half = frameHalf + 4 * blur
                for x in [-half.x, half.x] {
                    for y in [-half.y, half.y] {
                        let point = geometry.project(SIMD3(x + shadowOffset.x, y + shadowOffset.y, 0))
                        bounds = bounds.union(CGRect(x: point.x - margin, y: point.y - margin,
                                                     width: 2 * margin, height: 2 * margin))
                    }
                }
            }
            guard bounds.intersects(CGRect(origin: .zero, size: frame.size)) else { return }
            quadCenter = SIMD2(Double(bounds.midX) - pose.x, Double(bounds.midY) - pose.y)
            quadHalf = SIMD2(Double(bounds.width) / 2, Double(bounds.height) / 2)
        } else if slab != nil, pose.turn != 0 {
            let box = CarouselSlab.screenBox(half: frameHalf, thickness: thickness, turn: pose.turn,
                distance: CarouselGeometry.turnDistance(outer: pose.outerSize(padding: padding)),
                shadowCenter: shadow.alpha > 0 ? shadowOffset : nil, shadowHalf: frameHalf + 4 * blur,
                margin: margin)
            quadCenter = box.center
            quadHalf = box.half
        }
        if !optimizesCardDraws { quadHalf += 64 }
        var uniforms = CarouselCardUniforms(
            viewport: SIMD2(Float(frame.size.width), Float(frame.size.height)),
            center: SIMD2(Float(pose.x), Float(pose.y)),
            rotation: state.scene == nil ? SIMD2(Float(cosine), Float(sine)) : SIMD2(1, 0),
            quadCenter: SIMD2<Float>(quadCenter), quadHalf: SIMD2<Float>(quadHalf),
            imageHalf: SIMD2<Float>(imageHalf), frameHalf: SIMD2<Float>(frameHalf),
            uvScale: SIMD2(Float(fit.x / width), Float(fit.y / height)),
            shadowOffset: SIMD2<Float>(shadowOffset),
            imageRadius: Float(imageRadius),
            frameRadius: Float(min(min(frameHalf.x, frameHalf.y), corner + padding)),
            edgeWidth: Float(height * 0.005), opacity: Float(opacity),
            tint: Float(1 - frame.scrimOpacity * (promoted ? 1 - amount : 1)),
            shadowAlpha: Float(shadow.alpha * opacity), shadowFalloff: Float(1 / (2 * blur * blur)),
            occlusion: Float(card.occlusion), occluderCount: UInt32(occluders.count),
            turn: Float(pose.turn), tiltX: Float(pose.tiltX), tiltY: Float(pose.tiltY))
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<CarouselCardUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CarouselCardUniforms>.stride, index: 0)
        if !shadowOnly {
            if !state.samplerBound {
                encoder.setFragmentSamplerState(sampler, index: 0)
                state.samplerBound = true
            }
            encoder.setFragmentTexture(texture, index: 0)
        }
        if let slab, !state.slabBound {
            var constants = slab.uniforms
            encoder.setFragmentBytes(&constants, length: MemoryLayout<CarouselSlabUniforms>.stride, index: 2)
            if var color = slab.colorUniforms {
                encoder.setFragmentBytes(&color, length: MemoryLayout<CarouselCardColorUniforms>.stride, index: 5)
            }
            encoder.setFragmentTexture(slab.resources.studio, index: 1)
            encoder.setFragmentTexture(slab.resources.irradiance, index: 2)
            encoder.setFragmentTexture(noBackPicture, index: 3)
            var noVideo = CarouselBackVideoUniforms()
            encoder.setFragmentBytes(&noVideo, length: MemoryLayout<CarouselBackVideoUniforms>.stride, index: 4)
            encoder.setFragmentTexture(noBackPicture, index: 8)
            state.slabBound = true
        }
        // Only a lifted card turns far enough to show its back, and its back video.
        if slab != nil, lifted {
            encoder.setFragmentTexture(backTexture(for: card.index), index: 3)
            var video = CarouselBackVideoUniforms()
            var videoTexture: MTLTexture?
            let frame = backVideoFrames[card.index]
            if featureTexture(for: card.index) == nil, let panel = backVideoPanels[card.index],
               let texture = frame.flatMap({ CVMetalTextureGetTexture($0.texture) }) ?? backVideoStills[card.index]?.texture {
                let fit = CarouselBackVideoFit.fill(panel: panel.rect.size,
                                                    video: CGSize(width: texture.width, height: texture.height))
                video = CarouselBackVideoUniforms(
                    backSize: SIMD2(Float(panel.backSize.width), Float(panel.backSize.height)),
                    panelCenter: SIMD2(Float(panel.rect.midX), Float(panel.rect.midY)),
                    panelHalf: SIMD2(Float(panel.rect.width / 2), Float(panel.rect.height / 2)),
                    fit: SIMD2<Float>(fit), radius: Float(min(panel.radius, min(panel.rect.width, panel.rect.height) / 2)))
                videoTexture = texture
                if let frame { videoFramesInFlight.append(frame) }
            }
            encoder.setFragmentBytes(&video, length: MemoryLayout<CarouselBackVideoUniforms>.stride, index: 4)
            encoder.setFragmentTexture(videoTexture ?? noBackPicture, index: 8)
        }
        if slab != nil, state.scene != nil {
            let height = frame.card3D.bleedReach * Double(pose.outerSize(padding: padding).width) /
                CarouselSlab.cardWidthMillimeters
            var optical = CarouselBleedUniforms(strength: Float(frame.card3D.bleed * 0.675),
                height: Float(height), blur: Float(height * 0.5))
            encoder.setFragmentBytes(&optical, length: MemoryLayout<CarouselBleedUniforms>.stride, index: 3)
        } else if slab != nil {
            var (bleed, images, refraction, videos) = bleed(for: card, frame: frame, padding: padding)
            encoder.setFragmentBytes(&bleed, length: MemoryLayout<CarouselBleedUniforms>.stride, index: 3)
            for slot in 0..<4 {
                encoder.setFragmentTexture(slot < images.count ? images[slot] : noBackPicture, index: 4 + slot)
            }
            if var refraction {
                encoder.setFragmentBytes(&refraction, length: MemoryLayout<CarouselRefractionUniforms>.stride, index: 6)
                for slot in 0..<4 {
                    encoder.setFragmentTexture(slot < videos.count ? videos[slot] : noBackPicture, index: 9 + slot)
                }
            }
        }
        if var scene = state.scene, let geometry = sceneGeometry {
            scene.uniforms.receiverToScene = Self.floatMatrix(geometry.transform.slabToScene)
            scene.uniforms.sceneToReceiver = Self.floatMatrix(geometry.transform.sceneToSlab)
            scene.uniforms.receiverIndex = UInt32(card.index)
            if !scene.foregroundEmitterIndices.contains(where: { $0 != scene.uniforms.receiverIndex }) {
                scene.uniforms.eye.w = 0
            }
            encoder.setFragmentBytes(&scene.uniforms, length: MemoryLayout<CarouselSceneUniforms>.stride, index: 7)
            if !state.sceneTexturesBound {
                for slot in 0..<8 {
                    encoder.setFragmentTexture(slot < scene.images.count ? scene.images[slot] : noBackPicture, index: 13 + slot)
                    encoder.setFragmentTexture(slot < scene.videos.count ? scene.videos[slot] : noBackPicture, index: 21 + slot)
                }
                state.sceneTexturesBound = true
            }
        }
        if lifted {
            if occluders.isEmpty {
                var empty = CarouselOccluderUniforms(center: .zero, cardSize: .zero, rotation: SIMD2(1, 0), opacity: 0)
                encoder.setFragmentBytes(&empty, length: MemoryLayout<CarouselOccluderUniforms>.stride, index: 1)
            } else {
                occluders.withUnsafeBytes {
                    encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 1)
                }
            }
        }
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

extension CarouselRenderer {
    private static func floatMatrix(_ matrix: simd_double4x4) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(matrix.columns.0), SIMD4<Float>(matrix.columns.1),
                               SIMD4<Float>(matrix.columns.2), SIMD4<Float>(matrix.columns.3)))
    }

    /// Every drawn paper is an actual surface in the common optical scene. Its
    /// screen-visible print is used as radiance on either side, allowing the raised
    /// selected UI to light the wheel below without a second UI snapshot or capture.
    private func prepareScene(frame: CarouselFrame) -> CarouselSceneDraw {
        let camera = CarouselSceneCamera(size: frame.size)
        let card3D = frame.card3D
        let padding = max(0, frame.glass.padding)
        var uniforms = CarouselSceneUniforms()
        uniforms.eye = SIMD4(SIMD3<Float>(camera.eye), Float(card3D.bleed * 0.675))
        uniforms.beam = SIMD2(Float(frame.wheelCardWidth * card3D.bleedDepth / CarouselSlab.cardWidthMillimeters), 0)
        let promoted = Set(frame.promoted.map(\.index))
        let drawn = frame.wheel.filter { !promoted.contains($0.index) }.map { ($0, false) } +
            frame.promoted.map { ($0, true) }
        var sources: [CarouselSceneSource] = []
        var images: [MTLTexture] = []
        var videos: [MTLTexture] = []
        for (card, isPromoted) in drawn.suffix(8) {
            guard card.index >= 0, card.index < textureStore.textures.count,
                  card.pose.opacity > 0.001, card.pose.height > 0 else { continue }
            let pose = card.pose
            let outer = pose.outerSize(padding: padding)
            let build = CarouselSlab.build(pose: pose, padding: padding, card3D: card3D)
            let transform = CarouselSceneCardTransform(pose: pose, padding: padding, camera: camera)
            let localEye = transform.localPoint(camera.eye)
            let facingAway = localEye.z < -build.thickness * 0.5
            let image = facingAway ? backTexture(for: card.index) : frontTexture(for: card.index)
            let paperHalf = SIMD2(Double(outer.width) / 2, Double(outer.height) / 2) - build.margin
            let inset = max(0, build.margin - padding)
            let imageHalf = SIMD2(pose.width / 2 - inset, pose.height / 2 - inset)
            let imageAspect = Double(image.width) / Double(max(1, image.height))
            let printAspect = max(1, 2 * imageHalf.x) / max(1, 2 * imageHalf.y)
            let fit = featureTexture(for: card.index) != nil ? SIMD2<Double>(1, 1) :
                (imageAspect > printAspect ? SIMD2(printAspect / imageAspect, 1) : SIMD2(1, imageAspect / printAspect))
            let scale = facingAway ? SIMD2(-0.5, 0.5) / pointwiseMax(paperHalf, SIMD2(repeating: 1)) :
                fit / pointwiseMax(2 * imageHalf, SIMD2(repeating: 1))
            let amount = isPromoted ? min(1, max(0, pose.promotion)) : 0
            var source = CarouselSceneSource(sceneToSlab: Self.floatMatrix(transform.sceneToSlab),
                imageHalf: SIMD2<Float>(imageHalf), paperHalf: SIMD2<Float>(paperHalf), uvScale: SIMD2<Float>(scale),
                paperRadius: Float(CarouselSlab.paperCornerRadius(pose: pose, padding: padding, card3D: card3D)),
                imageRadius: Float(max(0, CarouselSlab.imageCornerRadius(pose: pose, card3D: card3D) - inset)),
                depth: Float(facingAway ? build.paperBottom : build.paperTop),
                opacity: Float(min(1, max(0, pose.opacity))),
                lodBias: Float(log2(max(1e-3, max(Double(image.width) * abs(scale.x), Double(image.height) * abs(scale.y))))),
                tint: Float(1 - frame.scrimOpacity * (isPromoted ? 1 - amount : 1)), index: UInt32(card.index),
                margin: Float(build.margin))
            // Fade radiance before the visible face changes at a grazing turn.
            let localView = localEye - SIMD3(0, 0, (build.paperTop + build.paperBottom) * 0.5)
            let cosine = abs(localView.z) / max(simd_length(localView), 1e-6)
            let face = min(1, max(0, (cosine - 0.025) / 0.095))
            let faceFade = face * face * (3 - 2 * face)
            source.radiance = SIMD2(Float(faceFade), isPromoted ? 1 + Float(card.occlusion) : 0)
            source.outerRadius = Float(CarouselSlab.cornerRadius(pose: pose, padding: padding, card3D: card3D))
            var videoImage = noBackPicture
            if facingAway, featureTexture(for: card.index) == nil, let panel = backVideoPanels[card.index] {
                let current = backVideoFrames[card.index]
                if let texture = current.flatMap({ CVMetalTextureGetTexture($0.texture) }) ?? backVideoStills[card.index]?.texture {
                    let fit = CarouselBackVideoFit.fill(panel: panel.rect.size,
                        video: CGSize(width: texture.width, height: texture.height))
                    source.video = CarouselBackVideoUniforms(
                        backSize: SIMD2(Float(panel.backSize.width), Float(panel.backSize.height)),
                        panelCenter: SIMD2(Float(panel.rect.midX), Float(panel.rect.midY)),
                        panelHalf: SIMD2(Float(panel.rect.width / 2), Float(panel.rect.height / 2)),
                        fit: SIMD2<Float>(fit), radius: Float(min(panel.radius, min(panel.rect.width, panel.rect.height) / 2)))
                    videoImage = texture
                    if let current { videoFramesInFlight.append(current) }
                }
            }
            sources.append(source)
            images.append(image)
            videos.append(videoImage)
        }
        let foregroundEmitterIndices = Set(sources.filter { $0.radiance.y > 0 && $0.radiance.x > 0 }.map(\.index))
        if foregroundEmitterIndices.isEmpty { uniforms.eye.w = 0 }
        uniforms.count = UInt32(sources.count)
        withUnsafeMutableBytes(of: &uniforms.sources) { memory in
            sources.withUnsafeBytes { memory.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(memory.count))) }
        }
        return CarouselSceneDraw(camera: camera, uniforms: uniforms, images: images, videos: videos,
                                 foregroundEmitterIndices: foregroundEmitterIndices)
    }

    /// A 3D card's edge bleed: the (at most four) nearest cards whose blurred colours it
    /// can pick up, as Liquid Glass picks up what is around it, in draw order so that the
    /// shader stacks them as the screen does. A card facing away shows its back picture.
    fileprivate func bleed(for card: CarouselRenderedCard, frame: CarouselFrame,
                           padding: Double) -> (CarouselBleedUniforms, [MTLTexture], CarouselRefractionUniforms?, [MTLTexture]) {
        let card3D = frame.card3D
        let outer = card.pose.outerSize(padding: padding)
        let height = card3D.bleedReach * Double(outer.width) / CarouselSlab.cardWidthMillimeters
        let blur = 0.5 * height
        var uniforms = CarouselBleedUniforms(strength: Float(card3D.bleed * 0.675), height: Float(height),
                                             blur: Float(blur))
        var refraction: CarouselRefractionUniforms? = card3D.refractiveEdges ? .init() : nil
        guard card3D.bleed > 0 else { return (uniforms, [], refraction, []) }
        func reach(_ pose: CarouselPose) -> Double {
            let size = pose.outerSize(padding: padding)
            return hypot(Double(size.width), Double(size.height)) / 2
        }
        let promotedIndices = Set(frame.promoted.map(\.index))
        let drawn = frame.wheel.filter { !promotedIndices.contains($0.index) }.map { ($0, false) } +
            frame.promoted.map { ($0, true) }
        let nearest = drawn.enumerated().compactMap { order, entry -> (order: Int, gap: Double)? in
            let other = entry.0
            guard other.index != card.index, other.pose.opacity > 0.01, other.pose.height > 0,
                  other.index >= 0, other.index < textureStore.textures.count else { return nil }
            let gap = hypot(other.pose.x - card.pose.x, other.pose.y - card.pose.y) - reach(card.pose) - reach(other.pose)
            return gap < height + blur ? (order, gap) : nil
        }.sorted { $0.gap < $1.gap }.prefix(4).sorted { $0.order < $1.order }
        var neighbours: [CarouselBleedNeighbour] = []
        var images: [MTLTexture] = []
        var printedNeighbours: [CarouselRefractionNeighbour] = []
        var videos: [MTLTexture] = []
        for (order, _) in nearest {
            let (other, promoted) = drawn[order]
            let pose = other.pose
            let facingAway = cos(pose.turn) < 0
            let image = featureTexture(for: other.index) ?? (facingAway ? backPictures[other.index] ??
                (card3D.refractiveEdges ? noBackPicture : textureStore.textures[other.index]) : textureStore.textures[other.index])
            let size = pose.outerSize(padding: padding)
            let width = Double(size.width), heightPoints = Double(size.height)
            let imageAspect = Double(image.width) / Double(max(1, image.height)), cardAspect = width / max(1, heightPoints)
            let fit = featureTexture(for: other.index) != nil ? SIMD2<Double>(1, 1) :
                (imageAspect > cardAspect ? SIMD2(cardAspect / imageAspect, 1) : SIMD2(1, imageAspect / cardAspect))
            let amount = promoted ? min(1, max(0, pose.promotion)) : 0
            let tint = 1 - frame.scrimOpacity * (promoted ? 1 - amount : 1)
            neighbours.append(CarouselBleedNeighbour(
                center: SIMD2(Float(pose.x), Float(pose.y)),
                rotation: SIMD2(Float(cos(pose.angle)), Float(sin(pose.angle))),
                halfSize: SIMD2(Float(width / 2 * max(0.05, abs(cos(pose.turn)))), Float(heightPoints / 2)),
                uvScale: SIMD2(Float((facingAway ? -fit.x : fit.x) / width), Float(fit.y / heightPoints)),
                radius: Float(CarouselSlab.cornerRadius(pose: pose, padding: padding, card3D: card3D)),
                opacity: Float(min(1, max(0, pose.opacity)) * tint),
                lodBias: Float(log2(max(1e-3, Double(image.width) * fit.x / max(1, width))))))
            images.append(image)
            guard card3D.refractiveEdges else { continue }
            let build = CarouselSlab.build(pose: pose, padding: padding, card3D: card3D)
            let paperHalf = SIMD2(width / 2, heightPoints / 2) - build.margin
            let inset = max(0, build.margin - padding)
            let imageHalf = SIMD2(pose.width / 2 - inset, pose.height / 2 - inset)
            let printedAspect = max(1, 2 * imageHalf.x) / max(1, 2 * imageHalf.y)
            let printedFit = featureTexture(for: other.index) != nil ? SIMD2<Double>(1, 1) :
                (imageAspect > printedAspect ? SIMD2(printedAspect / imageAspect, 1) : SIMD2(1, imageAspect / printedAspect))
            let scale = facingAway ? SIMD2(-0.5, 0.5) / pointwiseMax(paperHalf, SIMD2(repeating: 1)) :
                printedFit / pointwiseMax(2 * imageHalf, SIMD2(repeating: 1))
            var printed = CarouselRefractionNeighbour(
                imageHalf: SIMD2<Float>(imageHalf), paperHalf: SIMD2<Float>(paperHalf), uvScale: SIMD2<Float>(scale),
                turn: SIMD2(Float(cos(pose.turn)), Float(sin(pose.turn))),
                distance: Float(CarouselGeometry.turnDistance(outer: size)),
                depth: Float(facingAway ? build.paperBottom : pose.turn == 0 ? 0 : build.paperTop),
                paperRadius: Float(CarouselSlab.paperCornerRadius(pose: pose, padding: padding, card3D: card3D)),
                imageRadius: Float(max(0, CarouselSlab.imageCornerRadius(pose: pose, card3D: card3D) - inset)),
                lodBias: Float(log2(max(1e-3, max(Double(image.width) * abs(scale.x), Double(image.height) * abs(scale.y))))),
                occlusion: Float(other.occlusion))
            let occluders = promoted && other.occlusion > 0 ? frame.wheel.filter {
                other.occluderIndices.contains($0.index) && $0.pose.opacity > 0.001
            }.prefix(4).map { occluder -> CarouselOccluderUniforms in
                let outer = occluder.pose.outerSize(padding: padding)
                return CarouselOccluderUniforms(center: SIMD2(Float(occluder.pose.x), Float(occluder.pose.y)),
                    cardSize: SIMD2(Float(outer.width), Float(outer.height)),
                    rotation: SIMD2(Float(cos(occluder.pose.angle)), Float(sin(occluder.pose.angle))),
                    opacity: Float(occluder.pose.opacity),
                    cornerRadius: Float(CarouselSlab.cornerRadius(pose: occluder.pose, padding: padding, card3D: card3D)))
            } : []
            printed.occluderCount = UInt32(occluders.count)
            withUnsafeMutableBytes(of: &printed.occluders) { memory in
                occluders.withUnsafeBytes { memory.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(memory.count))) }
            }
            let covering = drawn.dropFirst(order + 1).filter { entry in
                let cover = entry.0
                return entry.1 && cover.pose.opacity > 0.001 && cover.pose.height > 0 &&
                    hypot(cover.pose.x - pose.x, cover.pose.y - pose.y) < reach(cover.pose) + reach(pose)
            }.sorted {
                hypot($0.0.pose.x - pose.x, $0.0.pose.y - pose.y) - reach($0.0.pose) <
                    hypot($1.0.pose.x - pose.x, $1.0.pose.y - pose.y) - reach($1.0.pose)
            }.prefix(4).map { entry -> CarouselRefractionMask in
                let pose = entry.0.pose
                let outer = pose.outerSize(padding: padding)
                let build = CarouselSlab.build(pose: pose, padding: padding, card3D: card3D)
                return CarouselRefractionMask(center: SIMD2(Float(pose.x), Float(pose.y)),
                    rotation: SIMD2(Float(cos(pose.angle)), Float(sin(pose.angle))),
                    paperHalf: SIMD2(Float(outer.width / 2 - build.margin), Float(outer.height / 2 - build.margin)),
                    turn: SIMD2(Float(cos(pose.turn)), Float(sin(pose.turn))),
                    distance: Float(CarouselGeometry.turnDistance(outer: outer)),
                    depth: Float(cos(pose.turn) < 0 ? build.paperBottom : pose.turn == 0 ? 0 : build.paperTop),
                    radius: Float(CarouselSlab.paperCornerRadius(pose: pose, padding: padding, card3D: card3D)),
                    opacity: Float(min(1, max(0, pose.opacity))))
            }
            printed.promotedMaskCount = UInt32(covering.count)
            withUnsafeMutableBytes(of: &printed.promotedMasks) { memory in
                covering.withUnsafeBytes { memory.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(memory.count))) }
            }
            var videoImage = noBackPicture
            if facingAway, featureTexture(for: other.index) == nil, let panel = backVideoPanels[other.index] {
                let current = backVideoFrames[other.index]
                if let texture = current.flatMap({ CVMetalTextureGetTexture($0.texture) }) ?? backVideoStills[other.index]?.texture {
                    let fit = CarouselBackVideoFit.fill(panel: panel.rect.size,
                                                       video: CGSize(width: texture.width, height: texture.height))
                    printed.video = CarouselBackVideoUniforms(
                        backSize: SIMD2(Float(panel.backSize.width), Float(panel.backSize.height)),
                        panelCenter: SIMD2(Float(panel.rect.midX), Float(panel.rect.midY)),
                        panelHalf: SIMD2(Float(panel.rect.width / 2), Float(panel.rect.height / 2)),
                        fit: SIMD2<Float>(fit), radius: Float(min(panel.radius, min(panel.rect.width, panel.rect.height) / 2)))
                    videoImage = texture
                    if let current { videoFramesInFlight.append(current) }
                }
            }
            printedNeighbours.append(printed)
            videos.append(videoImage)
        }
        uniforms.count = UInt32(neighbours.count)
        withUnsafeMutableBytes(of: &uniforms.neighbours) { memory in
            neighbours.withUnsafeBytes { memory.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(memory.count))) }
        }
        if var actual = refraction {
            withUnsafeMutableBytes(of: &actual.neighbours) { memory in
                printedNeighbours.withUnsafeBytes { memory.copyMemory(from: UnsafeRawBufferPointer(rebasing: $0.prefix(memory.count))) }
            }
            refraction = actual
        }
        return (uniforms, images, refraction, videos)
    }
}

/// Conservative pixel bounds of a rounded card and the shader's soft shadow. Cards
/// whose bounds miss the viewport are not drawn.
enum CarouselRasterBounds {
    /// Antialiasing allowance around a card's outer frame: two pixels, at least one point.
    /// Plain wheel-card quads extend this far beyond the frame.
    static func antialiasingMargin(size: CGSize, pixelWidth: Int, pixelHeight: Int) -> Double {
        guard pixelWidth > 0, pixelHeight > 0, size.width > 0, size.height > 0 else { return 1 }
        return max(1, 2 / min(Double(pixelWidth) / Double(size.width), Double(pixelHeight) / Double(size.height)))
    }

    /// `thickness` is a 3D card's: its back plane lies that far behind its face.
    static func scissor(pose: CarouselPose, size: CGSize, pixelWidth: Int, pixelHeight: Int,
                        promotion: Double, padding: Double = 0, thickness: Double = 0,
                        shadow: CarouselCardShadow? = nil) -> MTLScissorRect? {
        guard pixelWidth > 0, pixelHeight > 0, size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite, promotion.isFinite, padding.isFinite,
              thickness.isFinite,
              pose.x.isFinite, pose.y.isFinite, pose.height.isFinite, pose.angle.isFinite,
              pose.height > 0 else { return nil }
        let promotion = min(1, max(0, promotion))
        let thickness = max(0, thickness)
        let shadow = shadow ?? CarouselCardShadow(promotion: promotion, softShadows: false)
        let shadowExtent = shadow.alpha > 0 ? 4 * shadow.blur : 0
        let scaleX = Double(pixelWidth) / Double(size.width)
        let scaleY = Double(pixelHeight) / Double(size.height)
        let cosine = abs(cos(pose.angle)), sine = abs(sin(pose.angle))
        let outer = pose.outerSize(padding: max(0, padding))
        // In perspective, a turning card's near edge grows: by at most this factor. A
        // turned slab's back plane comes nearer by up to its thickness.
        let reach = Double(outer.width) / 2 + (shadow.alpha > 0 ? shadowExtent + 12 : 4)
        let distance = CarouselGeometry.turnDistance(outer: outer)
        let reachY = Double(outer.height) / 2 + (shadow.alpha > 0 ? shadowExtent + 12 : 4)
        let near = pose.turn == 0 && !pose.isTilted ? 1 :
            distance / max(1, distance - reach * (abs(sin(pose.turn)) + abs(sin(pose.tiltY))) -
                           reachY * abs(sin(pose.tiltX)) - thickness * abs(cos(pose.turn)))
        // Turned, a slab's side reaches its thickness beyond its face.
        let width = Double(outer.width) + (pose.turn == 0 ? 0 : 2 * thickness)
        let halfX = near * (width * cosine + Double(outer.height) * sine) / 2
        let halfY = near * (width * sine + Double(outer.height) * cosine) / 2
        let aa = near * antialiasingMargin(size: size, pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        // At four standard deviations the strongest shadow contributes <0.0001
        // alpha, below the fragment's 0.0005 cutoff. Include its downward offset.
        let shadowRadius = near * shadowExtent
        let left = pose.x - halfX - aa - shadowRadius
        let right = pose.x + halfX + aa + shadowRadius
        let top = pose.y - halfY - aa - shadowRadius
        let bottom = pose.y + halfY + aa + shadowRadius + shadow.offset
        let x0 = Int(floor(max(0, min(Double(pixelWidth), left * scaleX))))
        let y0 = Int(floor(max(0, min(Double(pixelHeight), top * scaleY))))
        let x1 = Int(ceil(max(0, min(Double(pixelWidth), right * scaleX))))
        let y1 = Int(ceil(max(0, min(Double(pixelHeight), bottom * scaleY))))
        guard x1 > x0, y1 > y0 else { return nil }
        return MTLScissorRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
