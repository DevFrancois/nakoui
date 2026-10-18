import MetalKit
import UIKit
import SwiftUI

/// Only immutable CPU metadata is retained. Drawable callbacks can arrive on
/// arbitrary threads; simulation and UIKit consume their results on the main thread.
nonisolated final class CarouselPresentationLedger {
    private struct Submission: Hashable {
        let generation: Int
        let sequence: Int
    }
    struct Snapshot {
        let generation: Int
        let sequence: Int
        let frame: CarouselFrame
        let focusedIndex: Int?
        let presentedTime: TimeInterval
    }

    private let lock = NSLock()
    private var generation = 0
    private var pending: [Int: Snapshot] = [:]
    private var latestPresented: Snapshot?
    private var unconsumed: Snapshot?
    private var gpuPending: Set<Submission> = []

    func submit(generation: Int, sequence: Int, frame: CarouselFrame, focusedIndex: Int?) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == self.generation,
              sequence > (latestPresented?.sequence ?? -1) else { return }
        pending[sequence] = Snapshot(generation: generation, sequence: sequence,
                                     frame: frame, focusedIndex: focusedIndex, presentedTime: 0)
        gpuPending.insert(Submission(generation: generation, sequence: sequence))
    }

    func recordPresented(generation: Int, sequence: Int, time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard generation == self.generation, let snapshot = pending.removeValue(forKey: sequence) else { return }
        guard time.isFinite, time > 0, time >= (latestPresented?.presentedTime ?? 0),
              sequence > (latestPresented?.sequence ?? -1) else { return }
        let presented = Snapshot(generation: snapshot.generation, sequence: snapshot.sequence,
            frame: snapshot.frame, focusedIndex: snapshot.focusedIndex, presentedTime: time)
        latestPresented = presented
        unconsumed = presented
        // A later presented drawable on this command queue supersedes every
        // earlier submission, including one whose skipped callback never arrived.
        pending = pending.filter { $0.key > sequence }
    }

    func discardPresentation(generation: Int, sequence: Int) {
        lock.lock()
        defer { lock.unlock() }
        if generation == self.generation { pending.removeValue(forKey: sequence) }
    }

    func recordCompletion(generation: Int, sequence: Int, succeeded: Bool) {
        lock.lock()
        defer { lock.unlock() }
        // Resource completion survives lifecycle invalidation. A presentation
        // mode change must not race older GPU work, even from a hidden epoch.
        gpuPending.remove(Submission(generation: generation, sequence: sequence))
        if generation == self.generation, !succeeded { pending.removeValue(forKey: sequence) }
    }

    func consume() -> Snapshot? {
        lock.lock()
        defer { lock.unlock() }
        defer { unconsumed = nil }
        return unconsumed
    }

    func isResolved(through fence: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !pending.keys.contains(where: { $0 <= fence })
    }

    func canPresentCompanions(through fence: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return latestPresented != nil && !pending.keys.contains(where: { $0 <= fence })
    }

    func shouldRecoverCatch(through fence: Int, startedAt: TimeInterval, now: TimeInterval) -> Bool {
        now.isFinite && startedAt.isFinite && now - startedAt >= 0.35 && !isResolved(through: fence)
    }

    var isGPUIdle: Bool {
        lock.lock()
        defer { lock.unlock() }
        return gpuPending.isEmpty
    }

    func canChangePresentation(through fence: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return gpuPending.isEmpty && !pending.keys.contains(where: { $0 <= fence })
    }

    func reset(generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        self.generation = generation
        pending.removeAll(keepingCapacity: true)
        latestPresented = nil
        unconsumed = nil
    }
}

/// Buffered touches keep their original timestamps, including the end of a
/// quick tap, while already-submitted drawables finish their presentation.
struct CarouselTouchReplayBuffer {
    struct Sample: Equatable {
        let point: CGPoint
        let time: TimeInterval
    }

    let begin: Sample
    private(set) var moves: [Sample] = []
    private(set) var endEvent: Sample?
    private(set) var isCancelled = false

    init(begin point: CGPoint, time: TimeInterval) {
        begin = Sample(point: point, time: time)
    }

    mutating func move(at point: CGPoint, time: TimeInterval) {
        guard endEvent == nil, !isCancelled, valid(point, time: time),
              time >= (moves.last?.time ?? begin.time) else { return }
        let sample = Sample(point: point, time: time)
        if moves.last?.time == time { moves[moves.count - 1] = sample }
        else { moves.append(sample) }
    }

    mutating func end(at point: CGPoint, time: TimeInterval, cancelled: Bool) {
        guard endEvent == nil, !isCancelled else { return }
        if cancelled { isCancelled = true; return }
        guard valid(point, time: time), time >= (moves.last?.time ?? begin.time) else { return }
        endEvent = Sample(point: point, time: time)
    }

    private func valid(_ point: CGPoint, time: TimeInterval) -> Bool {
        time.isFinite && point.x.isFinite && point.y.isFinite && time >= begin.time
    }
}

/// One display link owns both simulation and explicit Metal drawing.
public final class CarouselMetalView: MTKView, MTKViewDelegate, UIGestureRecognizerDelegate {
    var isHostActive = true {
        didSet {
            if isHostActive != oldValue { requestFrame() }
        }
    }
    private let engine: CarouselEngine
    private var renderer: CarouselRenderer?
    private var imageNames: [String]
    private var cards: CarouselCards?
    /// Back faces (`cardBack`): the selected card turns over to show one.
    private var back: ((Int) -> AnyView)?
    /// Back videos (`cardBackVideo`): one player for every card, made on first use.
    private var backVideo: ((Int) -> URL?)?
    private var backVideoPlayback: CarouselBackVideoPlayback?
    private var featureMedia: [Int: CarouselFeatureMedia] = [:]
    private var featureVideoPlayback: CarouselFeatureVideoPlayback?
    /// The video fetch path of the last tick; a change drops frames fetched by the other.
    private var fetchesVideoFramesInBackground = false
    private var companionOverlay: CarouselCompanionOverlay?
    private var companionConfiguration = CarouselCompanionConfiguration()
    private var hasCompanionProvider = false
    private var companionGrace: Double = 0
    // Reading time after a card gesture pauses feature holds, never release inertia.
    private var cardAutoplayGrace: Double = 0
    private var hasAutoplayGrace: Bool { companionGrace > 0 || cardAutoplayGrace > 0 }
    private var companionWasBlocking = false
    private var hasSynchronizedOverlays: Bool {
        !liveCards.isEmpty || companionOverlay?.requiresSynchronizedPresentation == true
    }

    /// The card last selected while it had a video, so a new selection restarts its video.
    private var backVideoSelection: Int?
    /// When the current frame will show, for reading the video frame it shows.
    private var frameTargetTimestamp: CFTimeInterval = 0
    /// The 3D cards whose backs are printed, and what those pictures were drawn for.
    private var backPictureIndices: Set<Int> = []
    private var staleBackPictureIndices: Set<Int> = []
    private var backPicturePrewarm: DispatchWorkItem?
    private var backPictureKey: BackPictureKey?
    private struct BackPictureKey: Equatable {
        var size: CGSize
        var scale: CGFloat
        var dark: Bool
        var layouts: [CarouselCardLayout]
    }
    private var flipBacks: [Int: CarouselFlipBack] = [:]
    private let flipHaptics = CarouselFlipHaptics()
    /// The wheel drops in once it has a size, before its first frame is drawn.
    private var entrancePending = true
    /// Pixel size the card pictures were drawn at, so only a size change redraws them.
    private var posterPixels: CGSize?
    private var posterLayouts: [CarouselCardLayout] = []
    private var cardTouches = Set<UITouch>()
    /// The settled selected card's live view, and earlier ones fading to their stills.
    private var liveCard: CarouselLiveCard?
    private var leavingCards: [CarouselLiveCard] = []
    private var frontCards: CarouselFrontCardsView?
    /// Tests turn the front layer off to draw the same frame entirely in the main drawable.
    internal var usesFrontLayer = true
    private weak var controller: CardCarouselController?
    private var onReady: (() -> Void)?
    private var renderTextureReceiver: ((MTLTexture, MTLCommandBuffer, UIView) -> Void)?
    private var renderTextureUnavailable: ((UIView) -> Void)?
    private var hasSharedRenderTexture = false
    private var ready = false
    private var renderGeneration = 0
    private var renderSequence = 0
    private var presentedSequence = 0
    private let presentationLedger = CarouselPresentationLedger()
    private typealias AcquiredDrawables = [ObjectIdentifier: CAMetalDrawable]
    private let drawableBroker = CarouselDrawableBroker<AcquiredDrawables>()
    private var responsiveRendering = false
    private var responsivePresentationSwitch: CarouselPresentationSwitch?
    private var packetRevision: UInt64 = 0
    private var drawRequestRevision: UInt64 = 0
    private var encodedRequestRevision: UInt64?
    private var unpublishedSubmissions: [Int: () -> Void] = [:]
    private var motionResolution = CarouselMotionResolution()
    private var previousQualityFrame: CarouselFrame?
    internal var motionRenderScaleSnapshot: Double { motionResolution.scale }
    internal var drawableAcquisitionPendingSnapshot: Bool { drawableBroker.isBusy }
    internal var presentationFenceResolvedSnapshot: Bool {
        presentationLedger.isResolved(through: renderSequence)
    }

    private let glassOverlay = CarouselNativeGlassOverlay()
    private var presentationStyle: CarouselGlassStyle = .metal
    private var presentationSwitch: CarouselPresentationSwitch?
    private var retiringNativeLayers = false
    private var overlayPresentationSwitch: CarouselPresentationSwitch?
    private struct PendingCatch {
        var capture: CarouselTapCapture
        var touches: CarouselTouchReplayBuffer
        let fence: Int
        let generation: Int
        let startedAt: TimeInterval
    }
    private var pendingCatch: PendingCatch?
    private var presentationActive = false
    private var stopped = false
    private var displayedFocusedIndex: Int?
    private var displayLink: CADisplayLink?
    private var displayTarget: CarouselDisplayTarget?
    private var configuredFrameRateRange: CAFrameRateRange?
    private var clock = CarouselAnimationClock()
    private var displayStarvation = CarouselDisplayStarvation()
    /// The opaque reference path adapts only before iOS 26. Responsive rendering
    /// always composites so direct scanout cannot hold its next destination texture.
    private static var adaptsLayerOpacity: Bool {
        if #available(iOS 26.0, *) { return false }
        return true
    }
    private var autoplayWork: DispatchWorkItem?
    private var autoplayStartedAt: TimeInterval?
    private var dirty = true
    private var companionDirty = true
    /// Geometry is independent of video pixels and companion motion. Only a card
    /// simulation step or external invalidation rebuilds this immutable snapshot.
    private var retainedSceneFrame: CarouselFrame?
    private var tickSceneFrame: CarouselFrame?
    private var lastLayoutBounds: CGRect?
    private var lastLayoutFrame: CGRect?
    private var lastLayoutSafeAreaInsets: UIEdgeInsets?
    private var companionPresentationWaitStartedAt: TimeInterval?
    internal private(set) var sceneSubmissionCount = 0
    internal private(set) var sceneFrameBuildCount = 0
    internal private(set) var companionPresentationCount = 0
    internal private(set) var companionOnlyPresentationCount = 0
    private var activeTouch: UITouch?
    /// Every finger of a selected-card pinch in arrival order, `activeTouch` first.
    private var pinchTouches: [UITouch] = []
    private var isApplicationActive = true
    private var isSceneActive = true
    private var observers: [NSObjectProtocol] = []
    private var visibilityObservations: [NSKeyValueObservation] = []
    private var accessibilityCardsByIndex: [Int: CarouselAccessibilityCard] = [:]
    private var accessibilityBoundsByIndex: [Int: CGRect] = [:]
    private var accessibilityCards: [CarouselAccessibilityCard] = []
    private var accessibilitySequence = -1

    internal var configurationSnapshot: CarouselConfiguration { engine.configuration }
    internal var displayFrameRateRangeSnapshot: CAFrameRateRange? { displayLink?.preferredFrameRateRange }
    internal var displayLinkPausedSnapshot: Bool { displayLink?.isPaused ?? true }
    internal var displayedFrameSnapshot: CarouselFrame? { engine.displayedFrame }
    internal var liveCardIndexSnapshot: Int? { liveCard?.index }
    internal var liveCardViewSnapshot: UIView? { liveCard?.container }
    internal var liveCardContentSnapshot: UIView? { liveCard?.content }
    internal var leavingCardIndicesSnapshot: [Int] { leavingCards.map(\.index) }
    internal var leavingCardViewsSnapshot: [UIView] { leavingCards.map(\.container) }
    internal var frontCardsVisibleSnapshot: Bool { frontCards.map { !$0.isHidden && $0.superview != nil } ?? false }
    internal var presentsWithTransactionSnapshot: Bool { (layer as? CAMetalLayer)?.presentsWithTransaction == true }
    internal var posterPixelsSnapshot: CGSize? { posterPixels }
    internal var backPictureIndicesSnapshot: Set<Int> { backPictureIndices }
    internal var featurePlaybackSnapshot: CarouselBackVideoPlayback.Snapshot? {
        engine.activeMediaIndex.flatMap { featureVideoPlayback?.snapshot(for: $0) }
    }
    internal var featurePlaybackSnapshots: [Int: CarouselBackVideoPlayback.Snapshot] {
        featureVideoPlayback?.snapshots ?? [:]
    }
    internal var activeFeaturePlaybackIndicesSnapshot: Set<Int> {
        featureVideoPlayback?.activeIndices ?? []
    }
    internal func featureFrameIdentitySnapshot(for index: Int) -> ObjectIdentifier? {
        renderer?.featureFrameIdentitySnapshot(for: index)
    }
    internal func featureFrameGenerationSnapshot(for index: Int) -> UInt64? {
        renderer?.featureFrameGenerationSnapshot(for: index)
    }
    internal var displayedAccessibilityCards: [UIAccessibilityElement] {
        currentAccessibilityCards().compactMap { $0 as? UIAccessibilityElement }
    }

    init(images: [String], configuration: CarouselConfiguration) {
        imageNames = images
        engine = CarouselEngine(count: images.count, configuration: configuration)
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        isPaused = true
        enableSetNeedsDisplay = false
        autoResizeDrawable = false
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(white: 242 / 255, alpha: 1)
        isOpaque = true
        clipsToBounds = true
        delegate = self
        renderer = CarouselRenderer(view: self)
        renderer?.setImages(images)
        responsiveRendering = configuration.validated.rendering.responsiveRendering
        (layer as? CAMetalLayer)?.presentsWithTransaction = responsiveRendering
        // Composited presentation keeps scanout from owning the texture that
        // Metal needs for its next scene. The renderer still fills opaque pixels.
        isOpaque = !responsiveRendering
        layer.isOpaque = !responsiveRendering
        drawableBroker.onIdle = { [weak self] in
            guard let self, !self.stopped, self.dirty else { return }
            self.wakeDisplayClock()
        }
        accessibilityIdentifier = "carousel.preview"
        isAccessibilityElement = false
        // iOS 17's query blocks keep accessibility geometry current without
        // computing every card's bounds on every frame.
        accessibilityElementsBlock = { [weak self] in (self?.currentAccessibilityCards() ?? []) + (self?.companionOverlay?.visibleAccessibilityElements ?? []) }
        automationElementsBlock = { [weak self] in (self?.currentAccessibilityCards() ?? []) + (self?.companionOverlay?.visibleAccessibilityElements ?? []) }
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) {
            (view: CarouselMetalView, _: UITraitCollection) in view.requestFrame()
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.willResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.setApplicationActive(false)
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.setApplicationActive(true)
        })
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIScene.didEnterBackgroundNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self, let scene = notification.object as? UIScene,
                      scene === self.window?.windowScene else { return }
                self.isSceneActive = notification.name == UIScene.didActivateNotification
                self.requestFrame()
            })
        }
        // Re-read screen support when power mode changes. iOS controls any power
        // or thermal throttling; the carousel adds no temperature-based limit.
        observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange,
                                            object: ProcessInfo.processInfo, queue: .main) { [weak self] _ in
            // Adjust the existing link without waking a settled preview or
            // restarting the animation clock.
            self?.configureDisplayLink()
        })
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.allowedTouchTypes = []
        scroll.allowedScrollTypesMask = .all
        scroll.delegate = self
        addGestureRecognizer(scroll)
    }

    required init(coder: NSCoder) { fatalError("Use CardCarousel's SwiftUI initializer") }

    deinit {
        displayLink?.invalidate()
        autoplayWork?.cancel()
        backPicturePrewarm?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func update(images: [String], cards: CarouselCards? = nil, back: ((Int) -> AnyView)? = nil,
                backVideo: ((Int) -> URL?)? = nil, layouts: [CarouselCardLayout] = [],
                featureMedia: ((Int) -> CarouselFeatureMedia?)? = nil, holdIntervals: [Double] = [],
                companions: ((Int) -> CarouselCompanionContent?)? = nil,
                companionConfiguration: CarouselCompanionConfiguration = .init(),
                configuration: CarouselConfiguration,
                controller: CardCarouselController?, onReady: (() -> Void)?,
                onIndexChange: ((Int) -> Void)?,
                onRenderTexture: ((MTLTexture, MTLCommandBuffer, UIView) -> Void)? = nil,
                onTextureUnavailable: ((UIView) -> Void)? = nil) {
        cancelAutoplayWake()
        invalidateRenderPackets()
        if onRenderTexture == nil {
            invalidateSharedRenderTexture()
            if renderTextureReceiver != nil, configuration.rendering.motionScale >= 1 {
                renderer?.releaseMotionResources()
            }
        }
        renderTextureReceiver = onRenderTexture
        renderTextureUnavailable = onTextureUnavailable
        // A new SwiftUI update can change the back builder without changing card
        // identity. Refresh existing pictures when idle, keeping them usable during motion.
        staleBackPictureIndices.formUnion(backPictureIndices)
        self.back = back
        self.backVideo = back == nil ? nil : backVideo
        if self.backVideo == nil, backVideoPlayback != nil {
            backVideoPlayback?.stop()
            backVideoPlayback = nil
        }
        engine.flipsEnabled = back != nil || featureMedia != nil
        let haptics = configuration.validated.haptics
        if back != nil, haptics.isEnabled {
            switch haptics.style {
            case .pattern:
                flipHaptics.prepare()
                engine.onFlip = { [weak self] in self?.flipHaptics.play() }
            case .tap:
                flipHaptics.prepareTap()
                engine.onFlip = { [weak self] in self?.flipHaptics.tap() }
            }
        } else {
            engine.onFlip = nil
        }
        // A swipe that changes the selection without a visible turn taps instead.
        if haptics.isEnabled {
            flipHaptics.prepareTap()
            engine.onSwipeSelection = { [weak self] in self?.flipHaptics.tap() }
        } else {
            engine.onSwipeSelection = nil
        }
        // View cards never change once shown; the same names keep their pictures.
        let images = cards?.names ?? images
        self.cards = cards
        if imageNames != images {
            cancelActiveTouch(redraw: false)
            companionOverlay?.removeAll()
            renderer?.clearFeatureMedia()
            featureVideoPlayback?.stop()
            featureVideoPlayback = nil
            self.featureMedia.removeAll()
            invalidatePresentation()
            activeTouch = nil
            imageNames = images
            engine.replaceImages(count: images.count)
            renderer?.setImages(images)
            removeLiveCards()
            removeFlipBack()
            posterPixels = nil
            entrancePending = true
            accessibilityCardsByIndex.removeAll()
            accessibilityBoundsByIndex.removeAll()
            accessibilityCards.removeAll()
            accessibilitySequence = -1
            displayedFocusedIndex = nil
            ready = false
            glassOverlay.removeAll()
        }
        engine.cardLayouts = layouts
        engine.autoplayIntervals = holdIntervals
        let media = Dictionary(uniqueKeysWithValues: images.indices.compactMap { index in
            featureMedia?(index).map { (index, $0) }
        })
        if self.featureMedia != media {
            invalidateRenderPackets()
            backVideoPlayback?.stop()
            featureVideoPlayback?.stop()
            featureVideoPlayback = nil
            renderer?.clearFeatureMedia()
            self.featureMedia = media
            for (index, source) in media {
                renderer?.setFeaturePoster(UIImage(named: images[index])?.cgImage, media: source, index: index)
            }
        }
        configureCompanions(content: companions, configuration: companionConfiguration)
        if engine.configuration != configuration.validated {
            invalidateRenderPackets()
            engine.configuration = configuration
            if engine.configuration.rendering.motionScale >= 1 { renderer?.releaseMotionResources() }
            dirty = true
        }
        if self.controller !== controller {
            if self.controller?.engine === engine {
                self.controller?.engine = nil
                self.controller?.wake = nil
            }
            self.controller = controller
        }
        controller?.engine = engine
        controller?.wake = { [weak self] in
            self?.invalidateRenderPackets()
            self?.cancelActiveTouch(redraw: false, recatchPending: false)
            self?.companionOverlay?.cancelInteraction()
            self?.requestFrame()
        }
        self.onReady = onReady
        engine.onIndexChange = onIndexChange
        renderPostersIfNeeded()
        beginEntranceIfPending()
        requestFrame()
    }

    private func beginEntranceIfPending() {
        guard entrancePending, engine.size.width > 0, engine.size.height > 0 else { return }
        entrancePending = false
        if engine.configuration.entrance.isEnabled { engine.beginEntrance() }
    }

    /// Draws each view card once as a picture at the selected card's size. Only a new
    /// size (rotation, padding) draws them again; the names stay, so motion is kept.
    private func renderPostersIfNeeded() {
        guard let cards, bounds.width > 0, bounds.height > 0 else { return }
        let pose = engine.focusedPose(for: 0)
        let scale = max(1, window?.screen.scale ?? traitCollection.displayScale)
        let size = CGSize(width: pose.width, height: pose.height)
        let pixels = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        guard pixels.width >= 1, pixels.height >= 1,
              pixels != posterPixels || posterLayouts != engine.cardLayouts else { return }
        posterPixels = pixels
        posterLayouts = engine.cardLayouts
        removeLiveCards()
        var rendered: [String: CGImage] = [:]
        for (index, name) in cards.names.enumerated() {
            let item = engine.focusedPose(for: index)
            if let image = cards.poster(index: index, size: CGSize(width: item.width, height: item.height), scale: scale) { rendered[name] = image }
        }
        renderer?.setImages(cards.names, rendered: rendered)
        dirty = true
    }

    /// Shows the live view once the selected card rests where the screen shows it. A
    /// finger may already rest on it; the live view then follows any drag.
    private func showLiveCardIfSettled() {
        guard liveCard == nil, let cards, pendingCatch == nil, posterPixels != nil,
              let index = engine.settledFocusedIndex, let frame = engine.displayedFrame,
              let shown = frame.promoted.first(where: { $0.index == index }) else { return }
        let target = engine.focusedPose(for: index)
        guard abs(shown.pose.x - target.x) < 0.25, abs(shown.pose.y - target.y) < 0.25,
              abs(shown.pose.height - target.height) < 0.25, shown.pose.promotion > 0.999 else { return }
        // In plain Metal the live view appears only once frames present through Core
        // Animation, so a drag that starts at once still follows on the same frames.
        // Switching needs an empty pipeline; until then the still stays, and the next
        // presented or completed frame retries.
        if presentationStyle == .metal, let metal = layer as? CAMetalLayer, !metal.presentsWithTransaction {
            guard presentationSwitch == nil, overlayPresentationSwitch == nil, !retiringNativeLayers,
                  !drawableBroker.isBusy,
                  presentationLedger.canChangePresentation(through: renderSequence) else { return }
            metal.presentsWithTransaction = true
        }
        invalidateRenderPackets()
        // Another card still fading would sit above this card's still; it is nearly done.
        leavingCards.removeAll { card in
            guard card.index != index else { return false }
            card.dispose()
            return true
        }
        // A new live view each time: selecting a card again starts it from the beginning.
        let live = CarouselLiveCard(cards: cards, index: index,
                                    size: CGSize(width: target.width, height: target.height))
        live.place(shown, frame: frame, host: self, below: frontCards,
                   glassContent: glassContent(for: index), glassAvailable: presentationStyle == .liquidGlass)
        live.fadeIn()
        liveCard = live
        updateLiveSync()
    }

    private var liveCards: [CarouselLiveCard] { leavingCards + (liveCard.map { [$0] } ?? []) }

    private func glassContent(for index: Int) -> UIView? {
        presentationStyle == .liquidGlass ? glassOverlay.contentView(for: index) : nil
    }

    /// The highest promoted card with a live view decides what Metal draws in front of it.
    private func topLiveCardPosition(in frame: CarouselFrame) -> Int? {
        let indices = Set(liveCards.map(\.index))
        guard !indices.isEmpty else { return nil }
        return frame.promoted.lastIndex { indices.contains($0.index) }
    }

    enum FrontPassPreparation {
        case ready(CarouselFrontPass?)
        case needsLayerPreparation
    }

    /// Metal surfaces that can sit in front of live content go to its front layer.
    /// The scene path chooses them by physical depth; legacy cards keep painter order.
    /// A newly required layer must be prepared by the next acquisition, never
    /// mistaken for an unnecessary pass while an acquired packet is handed off.
    func frontPass(for frame: CarouselFrame, prepareLayers: Bool = true) -> FrontPassPreparation {
        guard usesFrontLayer, liveCard != nil || !leavingCards.isEmpty, presentationStyle == .metal, let renderer,
              let top = topLiveCardPosition(in: frame) else { return .ready(nil) }
        let sceneIndices: Set<Int>?
        if CarouselGeometry.usesSceneDepth(frame) {
            let live = frame.promoted[top]
            let camera = CarouselSceneCamera(size: frame.size)
            let surface = CarouselSceneCardGeometry(pose: live.pose, padding: frame.glass.padding,
                                                     card3D: frame.card3D, camera: camera)
            var nearCandidates = Set<Int>()
            var backmostLivePoint = Double.infinity
            for x in [-surface.half.x, surface.half.x] {
                for y in [-surface.half.y, surface.half.y] {
                    backmostLivePoint = min(backmostLivePoint,
                        surface.transform.worldPoint(SIMD3(x, y, surface.build.paperTop)).z)
                }
            }
            for card in frame.wheel + frame.promoted where card.index != live.index && card.pose.opacity > 0.001 {
                let geometry = CarouselSceneCardGeometry(pose: card.pose, padding: frame.glass.padding,
                                                         card3D: frame.card3D, camera: camera)
                var frontmostPoint = -Double.infinity
                for x in [-geometry.half.x, geometry.half.x] {
                    for y in [-geometry.half.y, geometry.half.y] {
                        for z in [0, -geometry.build.thickness] {
                            frontmostPoint = max(frontmostPoint,
                                geometry.transform.worldPoint(SIMD3(x, y, z)).z)
                        }
                    }
                }
                if frontmostPoint >= backmostLivePoint - 0.001 { nearCandidates.insert(card.index) }
            }
            guard !nearCandidates.isEmpty else { return .ready(nil) }
            sceneIndices = nearCandidates
        } else {
            guard top + 1 < frame.promoted.count else { return .ready(nil) }
            sceneIndices = nil
        }
        let front: CarouselFrontCardsView
        if let existing = frontCards, existing.superview === self {
            front = existing
        } else {
            guard prepareLayers else { return .needsLayerPreparation }
            front = CarouselFrontCardsView(frame: bounds)
            addSubview(front)
            frontCards = front
        }
        if prepareLayers {
            if front.frame != bounds { front.frame = bounds }
            if front.contentScaleFactor != contentScaleFactor { front.contentScaleFactor = contentScaleFactor }
            renderer.configureFrontLayer(front.metalLayer, drawableSize: drawableSize,
                synchronized: (layer as? CAMetalLayer)?.presentsWithTransaction == true)
        }
        return .ready(CarouselFrontPass(layer: front.metalLayer, firstCard: top + 1, sceneIndices: sceneIndices))
    }

    /// Runs inside the frame's presentation: live views follow exactly the poses Metal
    /// draws, and fade to their stills once their card loses focus.
    private func updateLiveCards(frame: CarouselFrame, focusedIndex: Int?, frontDrawn: Bool) {
        guard liveCard != nil || !leavingCards.isEmpty else {
            if let front = frontCards, !front.isHidden { front.isHidden = true }
            return
        }
        if let live = liveCard, focusedIndex != live.index {
            liveCard = nil
            leavingCards.append(live)
            live.leave { [weak self, weak live] in
                guard let self, let live, self.leavingCards.contains(where: { $0 === live }) else { return }
                self.finishLeaving(live)
            }
        }
        let positions = Dictionary(frame.promoted.enumerated().map { ($1.index, $0) },
                                   uniquingKeysWith: { first, _ in first })
        // A card gone from the promoted cards has docked into the wheel or faded out.
        for card in liveCards where positions[card.index] == nil { finishLeaving(card, sync: false) }
        // Only the top live card can be stacked exactly; a lower one is already fading.
        if let top = topLiveCardPosition(in: frame) {
            let topIndex = frame.promoted[top].index
            for card in liveCards where card.index != topIndex { finishLeaving(card, sync: false) }
        }
        let glass = presentationStyle == .liquidGlass
        for card in liveCards {
            guard let position = positions[card.index] else { continue }
            card.place(frame.promoted[position], frame: frame, host: self, below: frontCards,
                       glassContent: glassContent(for: card.index), glassAvailable: glass)
        }
        if let front = frontCards, front.isHidden == frontDrawn { front.isHidden = !frontDrawn }
    }

    /// `sync` is false inside a frame's presentation; the next tick re-checks the mode.
    private func finishLeaving(_ card: CarouselLiveCard, sync: Bool = true) {
        if sync { invalidateRenderPackets(); requestFrame() }
        card.dispose()
        if liveCard === card { liveCard = nil }
        leavingCards.removeAll { $0 === card }
        if liveCard == nil && leavingCards.isEmpty { renderer?.releaseFrontResources() }
        if sync { updateLiveSync() }
    }

    /// Runs inside the frame's presentation: the back face of a turning flat card follows
    /// the pose Metal draws, shown once the card has turned past a quarter. A 3D card's back
    /// is `printed` on it instead (prepareBackPictures).
    private func updateFlipBack(frame: CarouselFrame, printed: Bool, focusedSizes: [Int: CGSize]? = nil) {
        let turning = back == nil || printed ? [] : frame.promoted.filter { $0.pose.turn != 0 }
        let indices = Set(turning.map(\.index))
        for (index, face) in flipBacks where !indices.contains(index) {
            face.dispose()
            flipBacks[index] = nil
        }
        guard let back else { return }
        // The back is the same card: laid out at the selected card's size.
        for card in turning {
            let size = focusedSizes?[card.index] ?? {
                let focused = engine.focusedPose(for: card.index)
                return CGSize(width: focused.width, height: focused.height)
            }()
            // A back face is built once its card first faces away, and again at a new size.
            if let face = flipBacks[card.index], face.size != size {
                face.dispose()
                flipBacks[card.index] = nil
            }
            guard flipBacks[card.index] != nil || cos(card.pose.turn) < 0 else { continue }
            let content = AnyView(back(card.index).environment(\.carouselBackVideo,
                backVideoPlayback.map { .hosted($0, index: card.index) }))
            let face = flipBacks[card.index] ?? CarouselFlipBack(index: card.index, content: content, size: size)
            flipBacks[card.index] = face
            face.place(card, frame: frame, host: self, below: frontCards,
                       glassContent: glassContent(for: card.index), glassAvailable: presentationStyle == .liquidGlass)
        }
    }

    private func removeFlipBack() {
        flipBacks.values.forEach { $0.dispose() }
        flipBacks.removeAll()
        removeBackPictures()
        backVideoPlayback?.stop()
        backVideoSelection = nil
    }

    /// Runs before each frame is encoded. The selected card's back video, if it has one,
    /// loads paused on its first frame as the card starts turning, plays from it once the
    /// card shows its back, and pauses on its frame when the card turns away. A new
    /// selection restarts it. On 3D cards its newest frame is printed on the card.
    private func updateBackVideo(frame: CarouselFrame, printed: Bool) {
        guard let backVideo else { return }
        if !engine.configuration.focus.rotatesOnSelection, engine.focusedIndex != nil {
            // Front-only selection hides the video without discarding its loaded frame.
            // A different selection still restarts it when rotation is enabled again.
            backVideoPlayback?.pause()
            return
        }
        let playback = backVideoPlayback ?? CarouselBackVideoPlayback()
        if backVideoPlayback == nil {
            playback.onPoster = { [weak self] in self?.requestFrame() }
            backVideoPlayback = playback
            // Every video's first frame is ready before its card first shows its back.
            for index in imageNames.indices { if let url = backVideo(index) { _ = playback.poster(for: url) } }
        }
        if engine.focusedIndex == nil { backVideoSelection = nil }
        // Every card showing its back holds a still of its own video; only the selected plays.
        for card in frame.promoted where card.pose.turn != 0 {
            guard let url = backVideo(card.index) else { continue }
            playback.register(url, for: card.index)
            if printed { renderer?.setBackVideoStill(playback.poster(for: url), index: card.index) }
        }
        let sceneBackFacing: ((CarouselRenderedCard) -> Bool)?
        if CarouselGeometry.usesSceneDepth(frame) {
            let camera = CarouselSceneCamera(size: frame.size)
            sceneBackFacing = { card in
                let geometry = CarouselSceneCardGeometry(pose: card.pose, padding: frame.glass.padding,
                                                         card3D: frame.card3D, camera: camera)
                return geometry.transform.localPoint(camera.eye).z < geometry.build.paperBottom
            }
        } else {
            sceneBackFacing = nil
        }
        switch CarouselBackVideoPlan.make(focusedIndex: engine.focusedIndex, promoted: frame.promoted,
                                          hasVideo: { backVideo($0) != nil }, lastSelection: backVideoSelection,
                                          isBackFacing: sceneBackFacing) {
        case .show(let index, let restart, let playing):
            if let url = backVideo(index), playback.load(url, index: index, restart: restart) {
                renderer?.clearBackVideoFrame(index: index)
            }
            backVideoSelection = index
            if playing { playback.play() } else { playback.pause() }
        case .paused:
            playback.pause()
        case .none:
            // Back on the wheel, nothing shows a back any more.
            if playback.index != nil { playback.stop() }
        }
        // Frames are read in either style: a flat card's panel holds the last one when it stops.
        guard let index = playback.index else { return }
        let time = frameTargetTimestamp > 0 ? frameTargetTimestamp : CACurrentMediaTime()
        if let buffer = playback.newFrame(forHostTime: time), printed { renderer?.setBackVideoFrame(buffer, index: index) }
    }

    /// Turning cards must have a printed back before encoding. Keep neighboring backs
    /// too: their pictures are prepared while the selected card rests, before a swipe.
    private func prepareBackPictures(frame: CarouselFrame, printed: Bool) {
        guard hasLegacyBackPictures, printed else { removeBackPictures(); return }
        let keepsPausedBacks = !engine.configuration.focus.rotatesOnSelection && engine.focusedIndex != nil
        let turning = Set(frame.promoted.filter {
            featureMedia[$0.index] == nil &&
                ($0.pose.turn != 0 || (keepsPausedBacks && backPictureIndices.contains($0.index)))
        }.map(\.index))
        let key = currentBackPictureKey
        if backPictureKey != key {
            removeBackPictures()
            backPictureKey = key
        }
        let retained = retainedBackPictureIndices(frame: frame)
        for index in backPictureIndices.subtracting(retained) { renderer?.setBackPicture(nil, index: index) }
        backPictureIndices.formIntersection(retained)
        staleBackPictureIndices.formIntersection(retained)
        for index in turning.subtracting(backPictureIndices).sorted() { renderBackPicture(index, key: key) }
    }

    private var currentBackPictureKey: BackPictureKey {
        let focused = engine.focusedPose(for: 0)
        return BackPictureKey(size: CGSize(width: focused.width, height: focused.height),
            scale: max(1, window?.screen.scale ?? traitCollection.displayScale),
            dark: traitCollection.userInterfaceStyle == .dark, layouts: engine.cardLayouts)
    }

    private func retainedBackPictureIndices(frame: CarouselFrame) -> Set<Int> {
        var indices = Set(frame.promoted.map(\.index))
        if let focused = engine.focusedIndex, !imageNames.isEmpty {
            for offset in -1...1 {
                indices.insert(CarouselGeometry.wrappedIndex(focused + offset, count: imageNames.count))
            }
        }
        return indices.filter { featureMedia[$0] == nil }
    }

    private func removeBackPictures() {
        backPicturePrewarm?.cancel()
        backPicturePrewarm = nil
        guard backPictureKey != nil || !backPictureIndices.isEmpty else { return }
        renderer?.removeBackPictures()
        backPictureKey = nil
        backPictureIndices.removeAll()
        staleBackPictureIndices.removeAll()
    }

    @discardableResult
    private func renderBackPicture(_ index: Int, key: BackPictureKey) -> Bool {
        var key = key
        let target = engine.focusedPose(for: index)
        key.size = CGSize(width: target.width, height: target.height)
        guard let back, let renderer, key.size.width >= 1, key.size.height >= 1 else { return false }
        // A back video's panel notes where it lies while the still is drawn.
        let recorder = CarouselBackVideoRecorder()
        let content = ZStack {
            Color(uiColor: .secondarySystemBackground)
            back(index)
        }
        .frame(width: key.size.width, height: key.size.height)
        .coordinateSpace(.named(CarouselBackVideoContext.space))
        .environment(\.colorScheme, key.dark ? .dark : .light)
        .environment(\.carouselBackVideo, backVideo?(index) == nil ? nil : .printed(recorder))
        let picture = ImageRenderer(content: content)
        picture.scale = key.scale
        picture.proposedSize = ProposedViewSize(key.size)
        guard let image = picture.cgImage else { return false }
        renderer.setBackPicture(image, index: index)
        renderer.setBackVideoPanel(recorder.frame, cornerRadius: recorder.cornerRadius,
                                  backSize: key.size, index: index)
        backPictureIndices.insert(index)
        staleBackPictureIndices.remove(index)
        // Each prepared video panel keeps its own poster; prewarming never starts playback.
        if let url = backVideo?(index), let playback = backVideoPlayback {
            playback.register(url, for: index)
            renderer.setBackVideoStill(playback.poster(for: url), index: index)
        }
        return true
    }

    private var hasLegacyBackPictures: Bool { back != nil && featureMedia.count < imageNames.count }

    private var canPrewarmBackPictures: Bool {
        canDraw && hasLegacyBackPictures && renderer != nil && engine.configuration.card3D.isEnabled &&
            !engine.configuration.usesNativeGlass && engine.configuration.focus.rotatesOnSelection &&
            activeTouch == nil && pendingCatch == nil && !engine.needsAnimation &&
            engine.settledFocusedIndex != nil
    }

    /// ImageRenderer stays on the main thread, one resting-card picture per turn of
    /// the run loop. A touch or transition cancels the opportunity before work begins.
    private func scheduleBackPicturePrewarm() {
        guard backPicturePrewarm == nil, canPrewarmBackPictures,
              let key = backPictureKey, key == currentBackPictureKey else { return }
        let retained = retainedBackPictureIndices(frame: engine.frame())
        let missing = retained.subtracting(backPictureIndices).union(staleBackPictureIndices.intersection(retained))
        guard !missing.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.backPicturePrewarm = nil
            guard self.canPrewarmBackPictures, self.backPictureKey == key,
                  self.currentBackPictureKey == key else { return }
            let retained = self.retainedBackPictureIndices(frame: self.engine.frame())
            let missing = retained.subtracting(self.backPictureIndices)
                .union(self.staleBackPictureIndices.intersection(retained))
            guard let index = missing.contains(self.engine.focusedIndex ?? -1) ?
                    self.engine.focusedIndex : missing.sorted().first else { return }
            guard self.renderBackPicture(index, key: key) else { return }
            if self.engine.frame().promoted.contains(where: { $0.index == index }) { self.requestFrame() }
            self.scheduleBackPicturePrewarm()
        }
        backPicturePrewarm = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60, execute: work)
    }

    private func removeLiveCards() {
        liveCards.forEach { $0.dispose() }
        liveCard = nil
        leavingCards.removeAll()
        frontCards?.isHidden = true
        renderer?.releaseFrontResources()
    }

    /// Only visible native content needs transactional presentation. Fence both
    /// directions of a mode change before revealing a companion over a card.
    private func updateLiveSync() {
        guard presentationStyle == .metal, presentationSwitch == nil, overlayPresentationSwitch == nil,
              !retiringNativeLayers, let metal = layer as? CAMetalLayer,
              metal.presentsWithTransaction != (responsiveRendering || hasSynchronizedOverlays) else { return }
        if !hasSynchronizedOverlays {
            guard activeTouch == nil, pendingCatch == nil,
                  engine.animationActivity != .interactive else { return }
        }
        if !drawableBroker.isBusy && presentationLedger.canChangePresentation(through: renderSequence) {
            metal.presentsWithTransaction = responsiveRendering || hasSynchronizedOverlays
        } else {
            // Stop submissions briefly so the old presentation mode can drain.
            overlayPresentationSwitch = CarouselPresentationSwitch(fence: renderSequence,
                startedAt: ProcessInfo.processInfo.systemUptime)
        }
    }

    override public func didMoveToWindow() {
        super.didMoveToWindow()
        observeVisibility()
        if window == nil {
            requestFrame()
        } else {
            isApplicationActive = UIApplication.shared.applicationState == .active
            isSceneActive = window?.windowScene?.activationState == .foregroundActive
            configureDisplayLink()
            renderPostersIfNeeded()
            requestFrame()
        }
    }

    override public func didMoveToSuperview() {
        super.didMoveToSuperview()
        observeVisibility()
        requestFrame()
    }

    private func observeVisibility() {
        visibilityObservations.removeAll()
        var ancestor = superview
        while let view = ancestor {
            visibilityObservations.append(view.observe(\.isHidden, options: [.new]) { [weak self] _, _ in
                self?.requestFrame()
            })
            visibilityObservations.append(view.observe(\.alpha, options: [.new]) { [weak self] _, _ in
                self?.requestFrame()
            })
            if let scroll = view as? UIScrollView {
                visibilityObservations.append(scroll.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
                    self?.requestFrame()
                })
            }
            ancestor = view.superview
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()
        // Moving a native bubble also asks its superview to lay out. That does
        // not change card pixels or geometry; only host layout invalidates them.
        let changed = lastLayoutBounds != bounds || lastLayoutFrame != frame ||
            lastLayoutSafeAreaInsets != safeAreaInsets
        lastLayoutBounds = bounds
        lastLayoutFrame = frame
        lastLayoutSafeAreaInsets = safeAreaInsets
        if engine.size != bounds.size { engine.size = bounds.size }
        beginEntranceIfPending()
        renderPostersIfNeeded()
        configureDisplayLink()
        if changed {
            invalidateRenderPackets()
            requestFrame()
        }
        else if dirty { wakeDisplayClock() }
    }

    override public var isHidden: Bool {
        didSet { requestFrame() }
    }

    override public var alpha: CGFloat {
        didSet { requestFrame() }
    }

    private var canDraw: Bool {
        guard isHostActive, !stopped, let window, isApplicationActive, isSceneActive, !isHidden, alpha > 0.001,
              bounds.width > 0, bounds.height > 0 else { return false }
        var visible = convert(bounds, to: window).intersection(window.bounds)
        guard !visible.isEmpty else { return false }
        var ancestor: UIView? = superview
        while let view = ancestor {
            if view.isHidden || view.alpha < 0.001 { return false }
            if view.clipsToBounds {
                visible = visible.intersection(view.convert(view.bounds, to: window))
                if visible.isEmpty { return false }
            }
            ancestor = view.superview
        }
        return true
    }

    private func configureDisplayLink() {
        guard !stopped, let window else { return }
        if !drawableBroker.isBusy, contentScaleFactor != window.screen.scale {
            contentScaleFactor = window.screen.scale
        }
        if displayLink == nil {
            let target = CarouselDisplayTarget(view: self)
            displayTarget = target
            let link = CADisplayLink(target: target, selector: #selector(CarouselDisplayTarget.tick(_:)))
            link.add(to: .main, forMode: .common)
            link.isPaused = true
            displayLink = link
        }
        let activity: CarouselAnimationActivity = !cardTouches.isEmpty || activeTouch != nil || pendingCatch != nil || companionOverlay?.needsAnimation == true || companionOverlay?.isInteracting == true ?
            .interactive : engine.animationActivity
        let screenMaximum = Float(window.screen.maximumFramesPerSecond)
        let steadySpinMaximum: Float = engine.configuration.spin.prefersMaximumFrameRate ? screenMaximum : 60
        let range = CarouselFrameRatePolicy.range(screenMaximum: screenMaximum, activity: activity,
            steadySpinMaximum: steadySpinMaximum,
            videoFrameRate: max(featureVideoPlayback?.frameRate ?? 0,
                backVideoPlayback?.isPlaying == true ? backVideoPlayback?.frameRate ?? 0 : 0))
        if configuredFrameRateRange?.minimum != range.minimum ||
            configuredFrameRateRange?.maximum != range.maximum ||
            configuredFrameRateRange?.preferred != range.preferred {
            displayLink?.preferredFrameRateRange = range
            configuredFrameRateRange = range
        }
    }

    private func requestFrame() {
        dirty = true
        retainedSceneFrame = nil
        wakeDisplayClock()
    }

    private func requestCompanionFrame() {
        companionDirty = true
        wakeDisplayClock()
    }

    private func wakeDisplayClock() {
        guard canDraw else {
            invalidateSharedRenderTexture()
            cancelActiveTouch(redraw: false)
            cardTouches.removeAll()
            companionOverlay?.cancelInteraction(preservingTouchOwnership: false)
            if presentationActive { invalidatePresentation() }
            backVideoPlayback?.pause()
            featureVideoPlayback?.pause()
            pauseClock()
            return
        }
        presentationActive = true
        cancelAutoplayWake()
        if pendingCatch != nil, engine.focusedIndex != nil { cancelActiveTouch(redraw: false) }
        configureDisplayLink()
        if displayLink?.isPaused == true {
            clock.reset()
            displayLink?.isPaused = false
        }
    }

    private func invalidateSharedRenderTexture() {
        guard hasSharedRenderTexture else { return }
        hasSharedRenderTexture = false
        renderTextureUnavailable?(self)
    }

    private func pauseClock() {
        cancelAutoplayWake()
        displayLink?.isPaused = true
        clock.reset()
        displayStarvation.interrupt()
    }

    private func invalidateRenderPackets() {
        packetRevision &+= 1
        drawableBroker.invalidate()
        let discarded = unpublishedSubmissions.values
        unpublishedSubmissions.removeAll()
        discarded.forEach { $0() }
    }

    private func invalidatePresentation() {
        invalidateRenderPackets()
        _ = motionResolution.reset()
        previousQualityFrame = nil
        renderGeneration += 1
        presentationLedger.reset(generation: renderGeneration)
        presentationActive = false
        retainedSceneFrame = nil
        companionPresentationWaitStartedAt = nil
        presentationSwitch = nil
        renderer?.invalidateNativeImages()
        // Inactivity (including a partial Control Center gesture) pauses time,
        // but keeps the last native cards visible, like the Metal drawable.
        // Image replacement and teardown explicitly remove obsolete cards.
        clock.reset()
    }

    fileprivate func tick(_ link: CADisplayLink) {
        guard canDraw else { requestFrame(); return }
        autoreleasepool {
            // Keep the display target current while a catch waits for its
            // presentation fence. Resuming must not integrate that waiting time.
            frameTargetTimestamp = link.targetTimestamp
            consumePresentedFrames()
            configureDisplayLink()
            if let pending = pendingCatch {
                clock.reset()
                if presentationLedger.shouldRecoverCatch(through: pending.fence,
                    startedAt: pending.startedAt, now: ProcessInfo.processInfo.systemUptime) {
                    // A driver that omits presentation callbacks must not leave
                    // input frozen forever. Cancel from the last confirmed pose;
                    // completion itself is never promoted to a device display ack.
                    abortPendingCatch()
                    dirty = true
                } else {
                    return
                }
            }
            guard preparePresentationStyle() else { clock.reset(); return }
            let wasSceneAnimating = engine.needsAnimation
            let wasCompanionAnimating = companionOverlay?.needsAnimation == true
            // All scene-source feature movies and the optional legacy back video
            // share this display clock and draw only newly decoded frames.
            let fetchesInBackground = engine.configuration.rendering.fetchesVideoFramesInBackground
            if fetchesInBackground != fetchesVideoFramesInBackground {
                fetchesVideoFramesInBackground = fetchesInBackground
                featureVideoPlayback?.discardFetchedFrames()
            }
            if backVideoPlayback?.hasNewFrame(forHostTime: link.targetTimestamp) == true ||
               (fetchesInBackground ? featureVideoPlayback?.hasFetchedFrames == true :
                featureVideoPlayback?.hasNewFrame(forHostTime: link.targetTimestamp) == true) { dirty = true }
            if fetchesInBackground {
                // Fetch for the next refresh; this one uses what the last fetch delivered.
                featureVideoPlayback?.fetchFrames(forHostTime: link.targetTimestamp +
                    max(0, link.targetTimestamp - link.timestamp))
            }
            // Advance to this frame's intended presentation time. Unlike the
            // preceding v-sync timestamp, this stays smooth across rate changes.
            let dt = clock.delta(at: link.targetTimestamp)
            featureVideoPlayback?.advance(by: dt)
            let blocked = companionOverlay?.isBlockingAutoplay == true
            if companionWasBlocking && !blocked { companionGrace = 2.5 }
            companionWasBlocking = blocked
            companionGrace = max(0, companionGrace - dt)
            cardAutoplayGrace = max(0, cardAutoplayGrace - dt)
            let pausesFeatureHold = !engine.configuration.spin.automatic &&
                (!cardTouches.isEmpty || cardAutoplayGrace > 0)
            engine.autoplaySuspended = blocked || companionGrace > 0 || pausesFeatureHold ||
                (!featureMedia.isEmpty && UIAccessibility.isReduceMotionEnabled)
            engine.advance(by: dt)
            if wasSceneAnimating || engine.needsAnimation { retainedSceneFrame = nil }
            let frame = retainedSceneFrame ?? makeSceneFrame()
            retainedSceneFrame = frame
            tickSceneFrame = frame
            defer { tickSceneFrame = nil }
            let geometryChanged = previousQualityFrame.map {
                $0.wheel != frame.wheel || $0.promoted != frame.promoted || $0.scrimOpacity != frame.scrimOpacity
            } ?? false
            previousQualityFrame = frame
            if motionResolution.advance(by: dt, activity: engine.animationActivity,
                isCardDragging: engine.isInteracting, geometryChanged: geometryChanged,
                motionScale: engine.configuration.rendering.motionScale,
                isLaminated: frame.card3D.isEnabled && !engine.configuration.usesNativeGlass) {
                dirty = true
            }
            advanceCompanions(frame: frame, dt: dt)
            updateLiveSync()
            configureDisplayLink()
            // Live views present through Core Animation on purpose; that latency is not starvation.
            if Self.adaptsLayerOpacity, (layer as? CAMetalLayer)?.presentsWithTransaction != true {
                displayStarvation.record(timestamp: link.timestamp, interval: link.targetTimestamp - link.timestamp,
                                         steady: engine.animationActivity == .automatic)
                if displayStarvation.needsCompositing, layer.isOpaque {
                    // The view's flag alone does not reach the Metal layer.
                    isOpaque = false
                    layer.isOpaque = false
                }
            }
            // A settled initial wheel still needs a confirmed presentation.
            // Retry if its first drawable was skipped instead of pausing before
            // onReady and displayed hit geometry can ever become available.
            if dirty || !ready || wasSceneAnimating || engine.needsAnimation {
                draw()
            } else if companionDirty || wasCompanionAnimating || companionOverlay?.needsAnimation == true {
                presentCompanionsWithoutRedrawingCards()
            }
            if ready && !engine.needsAnimation && !motionResolution.needsAnimation && !drawableBroker.isBusy && companionOverlay?.needsAnimation != true && !hasAutoplayGrace && !dirty && !companionDirty && overlayPresentationSwitch == nil,
               backVideoPlayback?.isPlaying != true && featureVideoPlayback?.isPlaying != true {
                pauseClock()
                scheduleAutoplayWake()
            }
        }
    }

    public func draw(in view: MTKView) {
        guard canDraw, pendingCatch == nil, preparePresentationStyle() else { dirty = true; return }
        drawRequestRevision &+= 1
        guard responsiveRendering else {
            encodeFrame(in: view)
            return
        }
        // Preparing a request is deferred until the previous handoff ends. No
        // CAMetalLayer property can change underneath a worker acquisition.
        drawableBroker.request(prepare: { [weak self] in
            guard let self, self.canDraw, self.pendingCatch == nil,
                  self.dirty || self.encodedRequestRevision != self.drawRequestRevision,
                  self.preparePresentationStyle(), let renderer = self.renderer,
                  let mainLayer = self.layer as? CAMetalLayer else { return nil }
            let frame = self.retainedSceneFrame ?? self.makeSceneFrame()
            let surfaces = self.glassOverlay.surfaces(frame: frame, in: self, renderer: renderer)
            guard case let .ready(front) = surfaces == nil ? self.frontPass(for: frame) : .ready(nil) else {
                self.dirty = true
                return nil
            }
            var targets = renderer.drawableTargets(frame: frame, nativeSurfaces: surfaces,
                front: front, mainLayer: mainLayer)
            // Video/opacity may change while acquisition waits. Reserve each
            // native image that the latest compatible scene could need.
            for surface in surfaces ?? [] where !targets.contains(where: { $0 === surface.layer }) {
                targets.append(surface.layer)
            }
            return {
                var acquired: AcquiredDrawables = [:]
                for target in targets {
                    guard let drawable = target.nextDrawable() else { return nil }
                    acquired[ObjectIdentifier(target)] = drawable
                }
                return acquired
            }
        }, consume: { [weak self] acquired, finish in
            guard let self, self.canDraw, self.pendingCatch == nil else { finish(); return }
            // Simulation kept advancing while the driver waited. Encode its
            // current snapshot, not the state from the acquisition request.
            self.encodeFrame(in: self, acquired: acquired, finish: finish)
        })
    }

    private func encodeFrame(in view: MTKView, acquired: AcquiredDrawables? = nil,
                             finish: (() -> Void)? = nil) {
        guard canDraw, pendingCatch == nil, let renderer else { finish?(); return }
        let frame = tickSceneFrame ?? retainedSceneFrame ?? makeSceneFrame()
        let focusedIndex = engine.focusedIndex
        let generation = renderGeneration
        let revision = packetRevision
        renderSequence += 1
        let sequence = renderSequence
        let ledger = presentationLedger
        let surfaces = glassOverlay.surfaces(frame: frame, in: self, renderer: renderer,
                                             prepareLayers: acquired == nil)
        if engine.configuration.usesNativeGlass && surfaces == nil {
            dirty = true
            finish?()
            return
        }
        guard case let .ready(front) = surfaces == nil ?
            frontPass(for: frame, prepareLayers: acquired == nil) : .ready(nil) else {
            dirty = true
            finish?()
            return
        }
        if let acquired, let mainLayer = layer as? CAMetalLayer {
            let targets = renderer.drawableTargets(frame: frame, nativeSurfaces: surfaces,
                front: front, mainLayer: mainLayer)
            guard targets.allSatisfy({ target in
                guard let image = acquired[ObjectIdentifier(target)] else { return false }
                return image.texture.width == Int(target.drawableSize.width) &&
                    image.texture.height == Int(target.drawableSize.height)
            }) else { dirty = true; finish?(); return }
        }
        // Metal draws 3D cards whole, their backs printed on them; native glass stays flat.
        let printsBacks = surfaces == nil && frame.card3D.isEnabled
        prepareBackPictures(frame: frame, printed: printsBacks)
        if featureMedia.isEmpty { updateBackVideo(frame: frame, printed: printsBacks) }
        else { updateFeatureVideo(frame: frame) }
        let companionSnapshot = companionOverlay?.capturePresentation()
        let capturedOverlay = companionOverlay
        let capturedLiveIdentities = liveCards.map(ObjectIdentifier.init)
        let focusedSizes = Dictionary(uniqueKeysWithValues: frame.promoted.map { card in
            let target = engine.focusedPose(for: card.index)
            return (card.index, CGSize(width: target.width, height: target.height))
        })
        let isResponsiveSubmission = acquired != nil
        let submit: ((MTLCommandBuffer, @escaping () -> Void) -> Void)? = !isResponsiveSubmission ? nil : {
            [weak self] command, present in
            guard let self else {
                // enqueue() already reserved this command's place. It must be
                // committed even when the host disappears; completion owns GPU resources.
                DispatchQueue.global(qos: .userInteractive).async { command.commit() }
                return
            }
            self.unpublishedSubmissions[sequence] = {
                ledger.discardPresentation(generation: generation, sequence: sequence)
            }
            // The error fallback can outlive scheduling. Release drawable-owning
            // presentation closures as soon as this packet resolves; command
            // buffers independently retain the textures required by the GPU.
            var pendingPresentation: (() -> Void)? = present
            let resolve: (Bool) -> Void = { [weak self] scheduled in
                guard let presentation = pendingPresentation else { return }
                pendingPresentation = nil
                defer { finish?() }
                guard let self else {
                    ledger.discardPresentation(generation: generation, sequence: sequence)
                    return
                }
                self.unpublishedSubmissions.removeValue(forKey: sequence)
                let validCompanion = companionSnapshot.map {
                    capturedOverlay?.isPresentationValid($0) == true
                } ?? true
                guard scheduled, self.canDraw, self.renderGeneration == generation,
                      self.packetRevision == revision, validCompanion,
                      self.liveCards.map(ObjectIdentifier.init) == capturedLiveIdentities else {
                    ledger.discardPresentation(generation: generation, sequence: sequence)
                    self.dirty = true
                    return
                }
                presentation()
            }
            command.addScheduledHandler { _ in DispatchQueue.main.async { resolve(true) } }
            command.addCompletedHandler { buffer in
                if buffer.status != .completed { DispatchQueue.main.async { resolve(false) } }
            }
            self.drawableBroker.submit { command.commit() }
        }
        let receiveTexture: ((MTLTexture, MTLCommandBuffer) -> Void)? = renderTextureReceiver.map { receive in
            { [weak self] texture, command in
                guard let self, self.canDraw else { return }
                self.hasSharedRenderTexture = true
                receive(texture, command, self)
            }
        }
        let submitted = renderer.draw(frame: frame, in: view, nativeSurfaces: surfaces, front: front,
            synchronizeLayers: (layer as? CAMetalLayer)?.presentsWithTransaction == true,
            acquiredDrawables: acquired, motionScale: motionResolution.scale,
            skipsHiddenShading: engine.configuration.rendering.skipHiddenShading,
            onRenderTexture: receiveTexture, submit: submit,
            updateLayers: { [weak self] in
                guard let self else { return }
                self.glassOverlay.update(frame: frame, in: self)
                self.updateLiveCards(frame: frame, focusedIndex: focusedIndex, frontDrawn: front != nil)
                self.updateFlipBack(frame: frame, printed: printsBacks, focusedSizes: focusedSizes)
                if let companionSnapshot, let capturedOverlay,
                   capturedOverlay.applyPresentation(companionSnapshot, in: self) {
                    self.companionPresentationCount += 1
                }
                // Physics may have advanced since encoding. Let the next tick
                // present that newer bubble state after this card frame appears.
                if !isResponsiveSubmission { self.companionDirty = false }
                self.companionPresentationWaitStartedAt = nil
            }, onSubmitted: { [weak self] in
                self?.sceneSubmissionCount += 1
                ledger.submit(generation: generation, sequence: sequence, frame: frame, focusedIndex: focusedIndex)
            }, onPresented: { [weak self] time in
                ledger.recordPresented(generation: generation, sequence: sequence, time: time)
                DispatchQueue.main.async { self?.consumePresentedFrames() }
            }, onCompleted: { [weak self] succeeded in
                ledger.recordCompletion(generation: generation, sequence: sequence, succeeded: succeeded)
                DispatchQueue.main.async {
                    guard let self, self.renderGeneration == generation else { return }
                    self.consumePresentedFrames()
                    if !succeeded { self.requestFrame() }
                }
            })
        if submitted {
            // Acquisition may have spanned another display tick. The scene just
            // encoded already includes that tick's pending request; do not draw
            // it twice unless a newer request arrives during scheduling.
            encodedRequestRevision = drawRequestRevision
            dirty = false
            if retiringNativeLayers {
                if !responsiveRendering && !hasSynchronizedOverlays {
                    overlayPresentationSwitch = CarouselPresentationSwitch(fence: sequence,
                        startedAt: ProcessInfo.processInfo.systemUptime)
                }
                retiringNativeLayers = false
                clock.reset()
            }
        } else {
            ledger.recordCompletion(generation: generation, sequence: sequence, succeeded: false)
            dirty = true
            finish?()
        }
    }

    private func makeSceneFrame() -> CarouselFrame {
        sceneFrameBuildCount += 1
        return engine.frame()
    }

    private func applyCompanionPresentation() {
        if let companionOverlay {
            companionOverlay.applyPresentation(in: self)
            companionPresentationCount += 1
        }
        companionDirty = false
        companionPresentationWaitStartedAt = nil
    }

    /// Keep the last Metal image while only a bubble moves. Never advance its
    /// native geometry past a card frame that has not actually reached display.
    private func presentCompanionsWithoutRedrawingCards() {
        guard !drawableBroker.isBusy, preparePresentationStyle(), !dirty else { companionDirty = true; return }
        guard presentationLedger.canPresentCompanions(through: renderSequence) else {
            companionDirty = true
            let now = ProcessInfo.processInfo.systemUptime
            let started = companionPresentationWaitStartedAt ?? now
            companionPresentationWaitStartedAt = started
            if presentationLedger.shouldRecoverCatch(through: renderSequence, startedAt: started, now: now) {
                // Supersede an omitted callback with a fresh synchronized frame;
                // GPU completion alone never authorizes native geometry changes.
                dirty = true
            }
            return
        }
        consumePresentedFrames()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyCompanionPresentation()
        companionOnlyPresentationCount += 1
        CATransaction.commit()
    }

    /// Style changes stop submissions until both actual presentations and GPU
    /// ownership resolve. This never turns resource completion into a display ack.
    private func preparePresentationStyle() -> Bool {
        let desiredResponsive = engine.configuration.rendering.responsiveRendering
        if desiredResponsive != responsiveRendering {
            if responsivePresentationSwitch == nil {
                responsivePresentationSwitch = CarouselPresentationSwitch(fence: renderSequence,
                    startedAt: ProcessInfo.processInfo.systemUptime)
            }
            guard !drawableBroker.isBusy, let change = responsivePresentationSwitch else { return false }
            if !presentationLedger.canChangePresentation(through: change.fence) {
                guard change.canRecover(now: ProcessInfo.processInfo.systemUptime,
                                        gpuIdle: presentationLedger.isGPUIdle) else { return false }
                invalidatePresentation()
                dirty = true
                presentationActive = true
            }
            responsiveRendering = desiredResponsive
            responsivePresentationSwitch = nil
            (layer as? CAMetalLayer)?.presentsWithTransaction = responsiveRendering ||
                presentationStyle == .liquidGlass || hasSynchronizedOverlays
            let opaque = !responsiveRendering && !displayStarvation.needsCompositing
            isOpaque = opaque
            layer.isOpaque = opaque
        } else {
            responsivePresentationSwitch = nil
        }
        let scale = window?.screen.scale ?? contentScaleFactor
        let pixels = CGSize(width: max(1, (bounds.width * scale).rounded()),
                            height: max(1, (bounds.height * scale).rounded()))
        if drawableSize != pixels {
            guard !drawableBroker.isBusy, presentationLedger.isGPUIdle else { return false }
            drawableSize = pixels
        }
        if let change = overlayPresentationSwitch {
            guard !drawableBroker.isBusy,
                  presentationLedger.canChangePresentation(through: change.fence) ||
                    change.canRecover(now: ProcessInfo.processInfo.systemUptime,
                                      gpuIdle: presentationLedger.isGPUIdle) else { return false }
            if !presentationLedger.isResolved(through: change.fence) {
                invalidatePresentation()
                dirty = true
                presentationActive = true
            }
            overlayPresentationSwitch = nil
            (layer as? CAMetalLayer)?.presentsWithTransaction = responsiveRendering || hasSynchronizedOverlays
            clock.reset()
        }
        // Without padding, Liquid Glass cards are plain Metal and need no transaction.
        let desired: CarouselGlassStyle = engine.configuration.usesNativeGlass ? .liquidGlass : .metal
        guard desired != presentationStyle else {
            presentationSwitch = nil
            return true
        }
        if presentationSwitch == nil {
            presentationSwitch = CarouselPresentationSwitch(fence: renderSequence,
                startedAt: ProcessInfo.processInfo.systemUptime)
        }
        guard let change = presentationSwitch, !drawableBroker.isBusy else { return false }
        if !presentationLedger.canChangePresentation(through: change.fence) {
            if change.canRecover(now: ProcessInfo.processInfo.systemUptime,
                                 gpuIdle: presentationLedger.isGPUIdle) {
                // A skipped callback can be superseded by a fresh drawable once
                // GPU work is finished. Do not invent displayed metadata.
                invalidatePresentation()
                dirty = true
                presentationActive = true
            } else {
                return false
            }
        }
        let wasTransactional = (layer as? CAMetalLayer)?.presentsWithTransaction == true
        presentationStyle = desired
        presentationSwitch = nil
        retiringNativeLayers = desired == .metal && wasTransactional
        (layer as? CAMetalLayer)?.presentsWithTransaction = desired == .liquidGlass || wasTransactional
        clock.reset()
        return true
    }

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        engine.size = bounds.size
        requestFrame()
    }

    private func consumePresentedFrames(resolveCatch: Bool = true) {
        guard canDraw else { return }
        if let shown = presentationLedger.consume(), shown.generation == renderGeneration,
           shown.sequence > presentedSequence {
            presentedSequence = shown.sequence
            displayedFocusedIndex = shown.focusedIndex
            engine.displayedFrame = shown.frame
            if !ready { ready = true; onReady?() }
        }
        showLiveCardIfSettled()
        scheduleBackPicturePrewarm()
        updateLiveSync()
        if resolveCatch, let pending = pendingCatch, pending.generation == renderGeneration,
           presentationLedger.isResolved(through: pending.fence) {
            completePendingCatch()
        }
    }

    private func beginInput(at point: CGPoint, time: TimeInterval) {
        invalidateRenderPackets()
        consumePresentedFrames()
        if let capture = engine.captureTap(at: point) {
            pendingCatch = PendingCatch(capture: capture,
                touches: CarouselTouchReplayBuffer(begin: point, time: time), fence: renderSequence,
                generation: renderGeneration, startedAt: ProcessInfo.processInfo.systemUptime)
            // Keep the display link alive solely to poll the finite presentation
            // fence. No simulation time or new submission passes this barrier.
            clock.reset()
            if presentationLedger.isResolved(through: renderSequence) { completePendingCatch() }
        } else {
            engine.touchBegan(at: point, time: time)
        }
        requestFrame()
    }

    private func moveInput(at point: CGPoint, time: TimeInterval) {
        if pendingCatch != nil { pendingCatch?.touches.move(at: point, time: time) }
        else { engine.touchMoved(at: point, time: time) }
        requestFrame()
    }

    private func endInput(at point: CGPoint, time: TimeInterval) {
        invalidateRenderPackets()
        if pendingCatch != nil { pendingCatch?.touches.end(at: point, time: time, cancelled: false) }
        else { engine.touchEnded(at: point, time: time, cancelled: false) }
        requestFrame()
    }

    private func completePendingCatch() {
        guard var pending = pendingCatch else { return }
        pendingCatch = nil
        clock.reset()
        guard pending.generation == renderGeneration, !pending.touches.isCancelled,
              let frame = engine.displayedFrame else { return }
        pending.capture.frame = frame
        engine.touchBegan(at: pending.touches.begin.point, time: pending.touches.begin.time,
                          capture: pending.capture)
        for sample in pending.touches.moves { engine.touchMoved(at: sample.point, time: sample.time) }
        if let end = pending.touches.endEvent {
            engine.touchEnded(at: end.point, time: end.time, cancelled: false)
        }
        if responsiveRendering, displayLink?.isPaused == false,
           frameTargetTimestamp.isFinite, frameTargetTimestamp > 0 {
            clock.reset(at: frameTargetTimestamp)
        }
        requestFrame()
        // The presentation barrier is resolved. Start acquiring this confirmed
        // catch immediately instead of waiting another refresh before the worker
        // can start. Simulation still advances only on the existing display link.
        if responsiveRendering { draw() }
    }

    private func abortPendingCatch(recatch: Bool = true) {
        guard var pending = pendingCatch else { return }
        pendingCatch = nil
        clock.reset()
        if recatch, pending.generation == renderGeneration, let frame = engine.displayedFrame {
            pending.capture.frame = frame
            engine.touchBegan(at: pending.touches.begin.point, time: pending.touches.begin.time,
                              capture: pending.capture)
            engine.touchEnded(at: pending.touches.begin.point, time: pending.touches.begin.time,
                              cancelled: true)
        }
        activeTouch = nil
    }

    private func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
        requestFrame()
    }

    func stop() {
        stopped = true
        invalidateSharedRenderTexture()
        renderTextureReceiver = nil
        renderTextureUnavailable = nil
        cancelActiveTouch(redraw: false)
        cardTouches.removeAll()
        invalidatePresentation()
        glassOverlay.removeAll()
        removeLiveCards()
        removeFlipBack()
        backVideoPlayback = nil
        featureVideoPlayback?.stop()
        featureVideoPlayback = nil
        companionOverlay?.removeAll(preservingTouchOwnership: false)
        companionOverlay = nil
        frontCards?.removeFromSuperview()
        frontCards = nil
        displayLink?.invalidate()
        cancelAutoplayWake()
        displayLink = nil
        displayTarget = nil
        configuredFrameRateRange = nil
        if controller?.engine === engine { controller?.engine = nil; controller?.wake = nil }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        visibilityObservations.removeAll()
    }

    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        consumePresentedFrames()
        guard companionOverlay?.isInteracting != true else { return }
        let alreadyOwned = !cardTouches.isEmpty
        cardTouches.formUnion(touches)
        if alreadyOwned {
            joinPinch(touches)
            return
        }
        guard activeTouch == nil, pendingCatch == nil, engine.displayedFrame != nil,
              let touch = touches.first else { return }
        cancelAutoplayWake()
        activeTouch = touch
        cardAutoplayGrace = featureMedia.isEmpty ? 0 : 2.5
        beginInput(at: touch.location(in: self), time: touch.timestamp)
        joinPinch(touches.subtracting([touch]))
    }

    /// Extra fingers on a selected card pinch and rotate it. Refused fingers stay
    /// owned and ignored, as before, until they lift.
    private func joinPinch(_ touches: Set<UITouch>) {
        guard let primary = activeTouch, pendingCatch == nil, !touches.isEmpty else { return }
        let fingers = (pinchTouches.isEmpty ? [primary] : pinchTouches) +
            touches.sorted { $0.timestamp < $1.timestamp }
        let points = fingers.map { $0.location(in: self) }
        let time = touches.map(\.timestamp).max() ?? primary.timestamp
        if !pinchTouches.isEmpty {
            engine.pinchMoved(points: points, time: time)
        } else if engine.beginPinch(points: points, time: time) {
            invalidateRenderPackets()
        } else {
            return
        }
        pinchTouches = fingers
        requestFrame()
    }

    private func movePinch(at time: TimeInterval) {
        engine.pinchMoved(points: pinchTouches.map { $0.location(in: self) }, time: time)
        requestFrame()
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !pinchTouches.isEmpty {
            guard pinchTouches.contains(where: touches.contains) else { return }
            movePinch(at: touches.map(\.timestamp).max() ?? 0)
            return
        }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            moveInput(at: sample.location(in: self), time: sample.timestamp)
        }
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        cardTouches.subtract(touches)
        if cardTouches.isEmpty {
            cardAutoplayGrace = featureMedia.isEmpty ? 0 : 2.5
            requestFrame()
        }
        if !pinchTouches.isEmpty, pinchTouches.contains(where: touches.contains) {
            // Lifting any pinching finger ends the pinch and the card springs back to rest.
            // The other fingers stay owned and ignored until they lift.
            let time = touches.map(\.timestamp).max() ?? 0
            movePinch(at: time)
            pinchTouches.removeAll()
            if let touch = activeTouch {
                endInput(at: touch.location(in: self), time: time)
                activeTouch = nil
                cardAutoplayGrace = featureMedia.isEmpty ? 0 : 2.5
                requestFrame()
            }
            return
        }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        endInput(at: touch.location(in: self), time: touch.timestamp)
        activeTouch = nil
        cardAutoplayGrace = featureMedia.isEmpty ? 0 : 2.5
        requestFrame()
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cardTouches.subtract(touches)
        cancelActiveTouch()
    }

    private func cancelActiveTouch(redraw: Bool = true, recatchPending: Bool = true) {
        if pendingCatch != nil || activeTouch != nil { invalidateRenderPackets() }
        consumePresentedFrames(resolveCatch: false)
        pinchTouches.removeAll()
        if pendingCatch != nil {
            abortPendingCatch(recatch: recatchPending)
        } else if let touch = activeTouch {
            engine.touchEnded(at: touch.location(in: self), time: touch.timestamp, cancelled: true)
            activeTouch = nil
        }
        if redraw { requestFrame() }
    }

    @objc private func handleScroll(_ recognizer: UIPanGestureRecognizer) {
        let delta = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        guard pendingCatch == nil, companionOverlay?.isInteracting != true,
              companionOverlay?.containsDisplayedPoint(recognizer.location(in: self), in: self) != true else { return }
        if recognizer.state == .began { invalidateRenderPackets() }
        cancelAutoplayWake()
        cardAutoplayGrace = featureMedia.isEmpty ? 0 : 2.5
        engine.scroll(by: delta, time: ProcessInfo.processInfo.systemUptime)
        requestFrame()
    }

    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled, bounds.contains(point) else { return nil }
        if let interaction = companionOverlay?.interactionView { return interaction }
        if !cardTouches.isEmpty || activeTouch != nil || pendingCatch != nil { return self }
        if let hit = companionOverlay?.hitView(at: point, in: self) { return hit }
        return super.hitTest(point, with: event)
    }

    override public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        companionOverlay?.isInteracting != true &&
            companionOverlay?.containsDisplayedPoint(gestureRecognizer.location(in: self), in: self) != true
    }

    private func configureCompanions(content: ((Int) -> CarouselCompanionContent?)?,
                                     configuration: CarouselCompanionConfiguration) {
        companionConfiguration = configuration.validated
        hasCompanionProvider = content != nil
        guard content != nil, configuration.isEnabled else {
            companionOverlay?.configure(content: nil, configuration: companionConfiguration)
            if companionOverlay?.isInteracting != true { companionOverlay = nil }
            engine.autoplaySuspended = false
            companionWasBlocking = false
            updateLiveSync()
            return
        }
        if companionOverlay == nil {
            let overlay = CarouselCompanionOverlay()
            overlay.presentationInvalidated = { [weak self] in self?.invalidateRenderPackets() }
            overlay.requestFrame = { [weak self] in self?.requestCompanionFrame() }
            overlay.ownershipBegan = { [weak self] in
                guard let self else { return }
                self.cancelAutoplayWake()
                self.engine.resetAutoplayHold()
                self.engine.autoplaySuspended = true
                self.requestCompanionFrame()
            }
            overlay.ownershipEnded = { [weak self] in
                guard let self else { return }
                if !self.hasCompanionProvider || !self.companionConfiguration.isEnabled {
                    self.companionOverlay = nil
                    self.updateLiveSync()
                }
                self.companionGrace = self.featureMedia.isEmpty ? 0 : 2.5
                self.requestCompanionFrame()
            }
            companionOverlay = overlay
        }
        companionOverlay?.configure(content: content, configuration: companionConfiguration)
        updateLiveSync()
    }

    private func advanceCompanions(frame: CarouselFrame, dt: Double) {
        guard let companionOverlay else { return }
        let active = CarouselCompanionOverlay.revealIndex(frame: frame, focusedIndex: engine.focusedIndex,
            focusedTarget: engine.focusedIndex.map { engine.focusedPose(for: $0) },
            wheelIndex: engine.activeMediaIndex, count: imageNames.count,
            selectedOnly: companionConfiguration.selectedCardsOnly)
        companionOverlay.advance(frame: frame, activeIndex: active, dragging: engine.isInteracting, dt: dt)
    }

    private func updateFeatureVideo(frame: CarouselFrame) {
        let playback = featureVideoPlayback ?? CarouselFeatureVideoPlayback()
        if featureVideoPlayback == nil {
            playback.onFrameNeeded = { [weak self] in self?.requestFrame() }
            featureVideoPlayback = playback
        }
        playback.update(frame: frame, media: featureMedia)
        let time = frameTargetTimestamp > 0 ? frameTargetTimestamp : CACurrentMediaTime()
        // One command buffer can carry every video's new frame for this refresh.
        let batched = engine.configuration.rendering.batchesVideoFrames
        if batched { renderer?.beginFeatureVideoFrames() }
        let prepare = { [featureMedia, renderer] (index: Int, buffer: CVPixelBuffer) in
            guard let source = featureMedia[index] else { return }
            // One prepared frame per source is shared by both card faces and
            // every reflection/refraction sample, including covered wheel cards.
            renderer?.setFeatureVideoFrame(buffer, media: source, index: index)
        }
        if engine.configuration.rendering.fetchesVideoFramesInBackground {
            playback.fetchedFrames(consume: prepare)
        } else {
            playback.newFrames(forHostTime: time, consume: prepare)
        }
        if batched { renderer?.commitFeatureVideoFrames() }
    }

    private func cancelAutoplayWake() {
        autoplayWork?.cancel()
        autoplayWork = nil
        if let started = autoplayStartedAt {
            autoplayStartedAt = nil
            engine.advanceAutoplay(by: max(0, ProcessInfo.processInfo.systemUptime - started))
        }
    }

    private func scheduleAutoplayWake() {
        guard canDraw, autoplayWork == nil, let delay = engine.autoplayDelay else { return }
        autoplayStartedAt = ProcessInfo.processInfo.systemUptime
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.autoplayWork = nil
            let elapsed = ProcessInfo.processInfo.systemUptime - (self.autoplayStartedAt ?? ProcessInfo.processInfo.systemUptime)
            self.autoplayStartedAt = nil
            self.engine.advanceAutoplay(by: elapsed)
            self.requestFrame()
        }
        autoplayWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func currentAccessibilityCards() -> [Any] {
        guard let frame = engine.displayedFrame else { return [] }
        guard accessibilitySequence != presentedSequence else { return accessibilityCards }
        let candidates = displayedFocusedIndex == nil ? frame.wheel + frame.promoted : frame.promoted
        var elements: [CarouselAccessibilityCard] = []
        var boundsByIndex: [Int: CGRect] = [:]
        elements.reserveCapacity(candidates.count)
        // Left to right, whatever the stacking direction.
        for card in candidates.sorted(by: { $0.pose.x < $1.pose.x }) where card.pose.opacity > 0.1 {
            let bounds = CarouselAccessibilityGeometry.bounds(of: card.pose, in: frame)
            guard !bounds.isEmpty else { continue }
            let element = accessibilityCard(for: card.index)
            elements.append(element)
            boundsByIndex[card.index] = bounds
            element.accessibilityFrameInContainerSpace = bounds
        }
        accessibilityCards = elements
        accessibilityBoundsByIndex = boundsByIndex
        accessibilitySequence = presentedSequence
        return elements
    }

    private func accessibilityCard(for index: Int) -> CarouselAccessibilityCard {
        if let element = accessibilityCardsByIndex[index] { return element }
        let element = CarouselAccessibilityCard(accessibilityContainer: self)
        element.accessibilityLabel = "Card \(index + 1)"
        element.accessibilityTraits = .button
        element.accessibilityFrameBlock = { [weak self] in
            guard let self else { return .zero }
            // VoiceOver can retain an element and query it without re-querying
            // its container. Resolve its geometry against the latest display.
            _ = self.currentAccessibilityCards()
            guard let bounds = self.accessibilityBoundsByIndex[index] else { return .zero }
            return UIAccessibility.convertToScreenCoordinates(bounds, in: self)
        }
        element.accessibilityValueBlock = { [weak self] in
            guard let self, self.displayedFocusedIndex == index else { return "On wheel" }
            return self.engine.isFlipped ? "Showing back" : "Enlarged"
        }
        element.activate = { [weak self] in
            guard let self, self.activeTouch == nil, self.pendingCatch == nil else { return false }
            self.consumePresentedFrames()
            guard let current = self.engine.displayedFrame else { return false }
            let pose = current.promoted.first(where: { $0.index == index })?.pose
                ?? current.wheel.first(where: { $0.index == index })?.pose
            guard let pose else { return false }
            let point = CGPoint(x: pose.x, y: pose.y)
            let time = ProcessInfo.processInfo.systemUptime
            self.beginInput(at: point, time: time)
            self.endInput(at: point, time: time + 0.01)
            return true
        }
        accessibilityCardsByIndex[index] = element
        return element
    }
}

/// Bounds are evaluated on accessibility queries, never in the render loop.
enum CarouselAccessibilityGeometry {
    static func bounds(of pose: CarouselPose, in frame: CarouselFrame) -> CGRect {
        let cosine = abs(cos(pose.angle)), sine = abs(sin(pose.angle))
        let outer = pose.outerSize(padding: frame.glass.padding)
        let halfWidth = (cosine * outer.width + sine * outer.height) / 2
        let halfHeight = (sine * outer.width + cosine * outer.height) / 2
        return CGRect(x: pose.x - halfWidth, y: pose.y - halfHeight,
                      width: halfWidth * 2, height: halfHeight * 2)
            .intersection(CGRect(origin: .zero, size: frame.size))
    }
}

private final class CarouselDisplayTarget {
    weak var view: CarouselMetalView?
    init(view: CarouselMetalView) { self.view = view }
    @objc func tick(_ link: CADisplayLink) { view?.tick(link) }
}

private final class CarouselAccessibilityCard: UIAccessibilityElement {
    var activate: (() -> Bool)?
    override func accessibilityActivate() -> Bool { activate?() ?? false }
}

/// Pure timing hints preserve fast interaction while limiting unattended work.
/// Power and thermal throttling are left to iOS; the app adds no thermal cap.
enum CarouselFrameRatePolicy {
    /// `videoFrameRate` is a playing back video's (0 for none): with nothing else moving,
    /// the link runs at 30 or 60 fps, whichever covers it.
    static func range(screenMaximum: Float, activity: CarouselAnimationActivity,
                      steadySpinMaximum: Float = 60,
                      videoFrameRate: Float = 0) -> CAFrameRateRange {
        let available = screenMaximum.isFinite && screenMaximum > 0 ? screenMaximum : 60
        let steady = steadySpinMaximum.isFinite && steadySpinMaximum > 0 ? steadySpinMaximum : 60
        let video: Float = videoFrameRate.isFinite && videoFrameRate > 0 ? (videoFrameRate <= 30 ? 30 : 60) : 0
        let requested: Float = activity == .interactive ? available
            : activity == .idle && video > 0 ? video : steady
        let maximum = min(available, requested)
        let minimum = min(maximum, activity == .interactive || maximum > 60 ? 60 : 30)
        return CAFrameRateRange(minimum: minimum, maximum: maximum, preferred: maximum)
    }
}

/// Detects starvation in the opaque reference path before iOS 26. Earlier XR
/// recordings settled at 40 fps with main-thread drawable waits; compositing
/// restored 60 fps. Responsive rendering uses compositing from its first frame.
/// The compositor's additional GPU work must still be measured on each device.
struct CarouselDisplayStarvation {
    private(set) var needsCompositing = false
    private var previous: CFTimeInterval?
    private var ticks = 0
    private var late = 0

    /// Feed every display-link callback; `interval` is the link's current frame duration.
    mutating func record(timestamp: CFTimeInterval, interval: CFTimeInterval, steady: Bool) {
        guard !needsCompositing else { return }
        guard steady, timestamp.isFinite, interval.isFinite, interval > 0 else {
            previous = nil
            return
        }
        defer { previous = timestamp }
        guard let previous, timestamp > previous else { return }
        ticks += 1
        if timestamp - previous > 1.5 * interval { late += 1 }
        guard ticks >= 90 else { return }
        // A quarter of steady refreshes missed is starvation, not an occasional hitch.
        needsCompositing = late * 4 >= ticks
        ticks = 0
        late = 0
    }

    /// A paused or hidden link resumes without counting the pause as missed refreshes.
    mutating func interrupt() { previous = nil }
}

/// Resetting on every visibility change prevents hidden time entering physics.
struct CarouselAnimationClock {
    private var previous: TimeInterval?
    mutating func reset(at timestamp: TimeInterval? = nil) {
        previous = timestamp.flatMap { $0.isFinite ? $0 : nil }
    }
    mutating func delta(at timestamp: TimeInterval) -> Double {
        guard timestamp.isFinite else { return 0 }
        if let previous, timestamp < previous { return 0 }
        defer { previous = timestamp }
        guard let previous else { return 0 }
        return min(0.1, max(0, timestamp - previous))
    }
}

/// Presentation callbacks can be skipped; recovery requires resource completion
/// but never fabricates a display acknowledgement.
struct CarouselPresentationSwitch {
    let fence: Int
    let startedAt: TimeInterval

    func canRecover(now: TimeInterval, gpuIdle: Bool) -> Bool {
        gpuIdle && now.isFinite && startedAt.isFinite && now - startedAt >= 0.35
    }
}

/// Each native card owns its glass backing and a Metal image above the material.
/// The glass never overlays the image; no animated annular mask is needed.
@MainActor
final class CarouselNativeCardImageView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("Native card images are renderer-owned") }
}

@MainActor
final class CarouselNativeGlassOverlay {
    @MainActor
    private final class Entry {
        let view: UIVisualEffectView
        let dimming = UIView()
        let image = CarouselNativeCardImageView(frame: .zero)
        var materialAnimator: UIViewPropertyAnimator?
        var radius: Double?
        var dimmingOpacity: Double?

        init(view: UIVisualEffectView) {
            self.view = view
            dimming.isUserInteractionEnabled = false
            view.contentView.addSubview(dimming)
            view.contentView.addSubview(image)
        }

        func dispose() {
            materialAnimator?.stopAnimation(true)
            materialAnimator = nil
            view.removeFromSuperview()
        }

        deinit {
            let animator = materialAnimator
            if Thread.isMainThread {
                MainActor.assumeIsolated { animator?.stopAnimation(true) }
            } else {
                DispatchQueue.main.async { animator?.stopAnimation(true) }
            }
        }
    }

    private var entries: [Int: Entry] = [:]
    private var spareEntries: [Entry] = []
    private var displayedOrder: [ObjectIdentifier] = []
    /// False while every effect view is hidden, so frames without system glass skip updates.
    private var showsGlass = false

    private func visibleCards(in frame: CarouselFrame) -> [CarouselRenderedCard] {
        let viewport = CGRect(origin: .zero, size: frame.size)
        return CarouselNativeCardStack.cards(in: frame).filter {
            $0.pose.height > 0 && $0.pose.opacity > 0.001 &&
                CarouselGeometry.outerBounds(pose: $0.pose, padding: frame.glass.padding).intersects(viewport)
        }
    }

    /// Prepare resources without moving any displayed card. Geometry changes
    /// happen only inside the renderer's successful presentation transaction.
    func surfaces(frame: CarouselFrame, in host: UIView, renderer: CarouselRenderer,
                  prepareLayers: Bool = true) -> [CarouselNativeImageSurface]? {
        guard #available(iOS 26.0, *), frame.glass.style == .liquidGlass,
              frame.glass.padding > 0 else { return nil }
        let cards = visibleCards(in: frame)
        if !prepareLayers {
            guard cards.allSatisfy({ entries[$0.index] != nil }) else { return nil }
            return cards.map { card in
                CarouselNativeImageSurface(card: card, layer: entries[card.index]!.image.metalLayer,
                    size: CGSize(width: card.pose.width, height: card.pose.height))
            }
        }
        let preparedIndices = Set(cards.map(\.index))
        // A rejected GPU submission must not retain an ever-growing set of
        // never-displayed cards. Preserve every currently displayed entry.
        for index in Array(entries.keys) where !preparedIndices.contains(index) {
            guard let entry = entries[index], entry.view.isHidden else { continue }
            entries.removeValue(forKey: index)
            if spareEntries.count < 4 { spareEntries.append(entry) }
            else { entry.dispose() }
        }
        let scale = host.contentScaleFactor
        var maximumLayout = CarouselConfiguration.Layout()
        maximumLayout.cardScale = 1.3
        return cards.map { card in
            let aspect = card.pose.aspect
            maximumLayout.cardAspect = aspect
            let maximumHeight = max(CarouselGeometry.focusedPose(size: frame.size, glass: frame.glass, aspect: aspect).height * 1.10,
                CarouselGeometry.cardHeight(size: frame.size, layout: maximumLayout) * 1.04)
            let height = max(1, min(4096 / max(1, aspect), ceil(maximumHeight * Double(scale))))
            let pixels = CGSize(width: max(1, ceil(height * aspect)), height: height)
            let entry = ensureEntry(index: card.index, in: host)
            let layer = entry.image.metalLayer
            renderer.configureNativeSurface(layer: layer)
            if layer.drawableSize != pixels { layer.drawableSize = pixels }
            return CarouselNativeImageSurface(card: card, layer: layer,
                size: CGSize(width: card.pose.width, height: card.pose.height))
        }
    }

    @available(iOS 26.0, *)
    private func ensureEntry(index: Int, in host: UIView) -> Entry {
        if let existing = entries[index] { return existing }
        let entry: Entry
        if let spare = spareEntries.popLast() {
            entry = spare
        } else {
            let material = UIGlassEffect(style: .regular)
            material.isInteractive = false
            let view = UIVisualEffectView(effect: nil)
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.isHidden = true
            entry = Entry(view: view)
            host.addSubview(view)
            // Scrub the material itself, keeping native glass and its ancestors
            // at full alpha. No copied mask can clip or fade the Metal image.
            let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak view] in
                view?.effect = material
            }
            animator.pausesOnCompletion = true
            animator.scrubsLinearly = true
            animator.startAnimation()
            animator.pauseAnimation()
            entry.materialAnimator = animator
        }
        entries[index] = entry
        return entry
    }

    /// The visible glass view of card `index`, where its live view belongs.
    func contentView(for index: Int) -> UIView? {
        guard let entry = entries[index], !entry.view.isHidden else { return nil }
        return entry.view.contentView
    }

    func update(frame: CarouselFrame, in host: UIView) {
        guard showsGlass || Self.usesNativeGlass(frame) else { return }
        UIView.performWithoutAnimation { updateWithoutAnimation(frame: frame, in: host) }
    }

    private static func usesNativeGlass(_ frame: CarouselFrame) -> Bool {
        guard #available(iOS 26.0, *) else { return false }
        return frame.glass.style == .liquidGlass && frame.glass.padding > 0
    }

    private func updateWithoutAnimation(frame: CarouselFrame, in host: UIView) {
        guard #available(iOS 26.0, *), Self.usesNativeGlass(frame) else { hide(); return }
        let visible = visibleCards(in: frame)
        showsGlass = !visible.isEmpty
        let indices = Set(visible.map(\.index))
        for index in Array(entries.keys) where !indices.contains(index) {
            guard let entry = entries.removeValue(forKey: index) else { continue }
            entry.view.isHidden = true
            if spareEntries.count < 4 { spareEntries.append(entry) }
            else { entry.dispose() }
        }
        for card in visible {
            let entry = ensureEntry(index: card.index, in: host)
            var needsLayout = false
            let outer = CGRect(origin: .zero, size: card.pose.outerSize(padding: frame.glass.padding))
            if entry.view.bounds != outer {
                entry.view.bounds = outer
                needsLayout = true
            }
            let center = CGPoint(x: card.pose.x, y: card.pose.y)
            if entry.view.center != center { entry.view.center = center }
            if card.pose.turn == 0 && !card.pose.isTilted {
                let transform = CGAffineTransform(rotationAngle: card.pose.angle)
                if entry.view.transform != transform || !CATransform3DIsAffine(entry.view.transform3D) {
                    entry.view.transform = transform
                }
            } else {
                entry.view.transform3D = CarouselTurnTransform.make(turn: card.pose.turn, angle: card.pose.angle,
                    drawn: card.pose.outerSize(padding: frame.glass.padding),
                    tiltX: card.pose.tiltX, tiltY: card.pose.tiltY)
            }
            // Facing away, the glass shows its back face, not the front image.
            let backFacing = cos(card.pose.turn) < 0
            if entry.image.isHidden != backFacing { entry.image.isHidden = backFacing }
            let radius = card.pose.outerCornerRadius(padding: frame.glass.padding)
            if entry.radius != radius {
                entry.view.cornerConfiguration = .corners(radius: .fixed(radius))
                entry.radius = radius
                needsLayout = true
            }
            if entry.dimming.frame != outer { entry.dimming.frame = outer }
            if entry.dimming.layer.cornerRadius != radius { entry.dimming.layer.cornerRadius = radius }
            let opacity = min(1, max(0, card.pose.opacity))
            let dimmingOpacity = frame.scrimOpacity * (1 - min(1, max(0, card.pose.promotion))) * opacity
            if entry.dimmingOpacity != dimmingOpacity {
                entry.dimming.backgroundColor = UIColor.black.withAlphaComponent(dimmingOpacity)
                entry.dimmingOpacity = dimmingOpacity
            }
            let imageFrame = CGRect(x: frame.glass.padding, y: frame.glass.padding,
                width: card.pose.width, height: card.pose.height)
            if entry.image.frame != imageFrame { entry.image.frame = imageFrame }
            if entry.materialAnimator?.fractionComplete != CGFloat(opacity) {
                entry.materialAnimator?.fractionComplete = CGFloat(opacity)
                needsLayout = true
            }
            if entry.view.isHidden {
                entry.view.isHidden = false
                needsLayout = true
            }
            // Position and tilt only move the retained node. Flush the effect
            // subtree once after size or material changes, inside this frame's
            // shared presentation transaction.
            if needsLayout {
                entry.view.updatePropertiesIfNeeded()
                entry.view.layoutIfNeeded()
            }
        }
        let desired = visible.compactMap { entries[$0.index]?.view }
        let order = desired.map { ObjectIdentifier($0) }
        if displayedOrder != order {
            desired.forEach { host.bringSubviewToFront($0) }
            displayedOrder = order
        }
    }

    func hide() {
        UIView.performWithoutAnimation {
            entries.values.filter { !$0.view.isHidden }.forEach { $0.view.isHidden = true }
        }
        displayedOrder.removeAll(keepingCapacity: true)
        showsGlass = false
    }

    func removeAll() {
        entries.values.forEach { $0.dispose() }
        spareEntries.forEach { $0.dispose() }
        entries.removeAll()
        spareEntries.removeAll()
        displayedOrder.removeAll()
        showsGlass = false
    }
}

/// A transparent Metal layer above live card views. Metal draws the promoted cards that
/// stack in front of a live card here instead of in the main drawable, so a live view
/// never covers them. Hidden whenever no card is in front.
@MainActor
final class CarouselFrontCardsView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("The front cards layer is renderer-owned") }
}

/// Runs a closure when a Core Animation animation ends.
private final class CarouselAnimationCompletion: NSObject, CAAnimationDelegate {
    private var done: (() -> Void)?
    init(_ done: @escaping () -> Void) { self.done = done }
    func animationDidStop(_ animation: CAAnimation, finished: Bool) {
        let done = self.done
        self.done = nil
        done?()
    }
}

/// One card's live view. It is laid out once at the selected card's size, then moved,
/// tilted, scaled and dimmed with the card Metal draws under it, on the same frames. It
/// never takes touches or accessibility focus.
@MainActor
final class CarouselLiveCard {
    static let fadeInDuration: TimeInterval = 0.15
    /// After the card leaves focus, the live view fades to the still under it.
    static let fadeOutDuration: TimeInterval = 0.3

    let index: Int
    /// Clips, positions and scales the live view; its opacity follows the card's.
    let container = UIView()
    /// Fades in when the card goes live and out when it leaves focus.
    private let fader = UIView()
    private let dimming = UIView()
    let content: UIView
    /// Keeps a SwiftUI card's hosting controller alive with its view.
    private let owner: AnyObject?
    private let size: CGSize
    private(set) var isLeaving = false
    private var isDisposed = false

    init(cards: CarouselCards, index: Int, size: CGSize) {
        self.index = index
        self.size = size
        let live = cards.liveView(index: index, size: size)
        content = live.view
        owner = live.owner
        for view in [container, fader, dimming, content] {
            view.isUserInteractionEnabled = false
            view.accessibilityElementsHidden = true
            view.isAccessibilityElement = false
        }
        UIView.performWithoutAnimation {
            container.bounds = CGRect(origin: .zero, size: size)
            container.clipsToBounds = true
            // Same circular corners as the shader; the scale transform keeps the ratio.
            container.layer.cornerRadius = size.width * 0.034
            container.layer.allowsEdgeAntialiasing = true
            fader.frame = container.bounds
            content.frame = fader.bounds
            dimming.frame = fader.bounds
            dimming.backgroundColor = .black
            dimming.alpha = 0
            fader.addSubview(content)
            fader.addSubview(dimming)
            container.addSubview(fader)
        }
    }

    /// Covers `card` as `frame` draws it. Inside `glassContent` (the card's own glass view,
    /// which already moves, tilts and stacks it) only the scale is applied; otherwise the
    /// view sits in `host`, below `front`.
    func place(_ card: CarouselRenderedCard, frame: CarouselFrame, host: UIView, below front: UIView?,
               glassContent: UIView?, glassAvailable: Bool) {
        guard !isDisposed else { return }
        UIView.performWithoutAnimation {
            let pose = card.pose
            let scale = CGFloat(max(0, pose.height)) / max(1, size.height)
            // A turning card may change shape as it grows into its back-face panel.
            let scaleX = CGFloat(max(0, pose.width)) / max(1, size.width)
            if let glassContent {
                if container.superview !== glassContent || glassContent.subviews.last !== container {
                    glassContent.addSubview(container)
                }
                // Native Liquid Glass keeps the front flat, including when this
                // retained live view previously covered a rounded 3D paper face.
                let radius = size.width * 0.034
                if container.layer.cornerRadius != radius { container.layer.cornerRadius = radius }
                let padding = CGFloat(frame.glass.padding)
                container.center = CGPoint(x: padding + CGFloat(pose.width) / 2,
                                           y: padding + CGFloat(pose.height) / 2)
                container.transform = CGAffineTransform(scaleX: pose.turn == 0 ? scale : scaleX, y: scale)
            } else {
                if container.superview !== host {
                    if let front, front.superview === host { host.insertSubview(container, belowSubview: front) }
                    else { host.addSubview(container) }
                } else if let front, front.superview === host,
                          let mine = host.subviews.firstIndex(of: container),
                          let theirs = host.subviews.firstIndex(of: front), mine > theirs {
                    host.insertSubview(container, belowSubview: front)
                }
                container.center = CGPoint(x: pose.x, y: pose.y)
                // On a 3D card it covers the paper, inside the clear margin.
                let inset = CarouselSlab.faceInset(pose: pose, padding: frame.glass.padding, card3D: frame.card3D)
                let faceScale = inset > 0 ? CGFloat(max(0, pose.height - 2 * inset)) / max(1, size.height) : scale
                let faceScaleX = inset > 0 ? CGFloat(max(0, pose.width - 2 * inset)) / max(1, size.width) : scaleX
                let radius = frame.card3D.isEnabled
                    ? CGFloat(CarouselSlab.paperCornerRadius(pose: pose, padding: frame.glass.padding,
                                                             card3D: frame.card3D)) / max(0.001, faceScaleX)
                    : size.width * 0.034
                if container.layer.cornerRadius != radius { container.layer.cornerRadius = radius }
                if frame.card3D.isEnabled && frame.card3D.sceneDepth {
                    let build = CarouselSlab.build(pose: pose, padding: frame.glass.padding,
                                                   card3D: frame.card3D)
                    container.transform3D = CarouselTurnTransform.scene(pose: pose,
                        padding: frame.glass.padding, card3D: frame.card3D,
                        camera: CarouselSceneCamera(size: frame.size),
                        scale: SIMD2(Double(faceScaleX), Double(faceScale)), planeDepth: build.paperTop)
                } else if pose.turn == 0 && !pose.isTilted {
                    container.transform = CGAffineTransform(rotationAngle: pose.angle)
                        .scaledBy(x: inset > 0 ? faceScaleX : faceScale, y: faceScale)
                } else {
                    container.transform3D = CarouselTurnTransform.make(turn: pose.turn, angle: pose.angle,
                        drawn: pose.outerSize(padding: frame.glass.padding),
                        scale: CGSize(width: faceScaleX, height: faceScale),
                        tiltX: pose.tiltX, tiltY: pose.tiltY)
                }
            }
            // In Liquid Glass a card without its glass view is off screen; a turned card
            // shows its back face instead.
            let frontVisible: Bool
            if glassContent == nil && frame.card3D.isEnabled && frame.card3D.sceneDepth {
                let camera = CarouselSceneCamera(size: frame.size)
                let geometry = CarouselSceneCardGeometry(pose: pose, padding: frame.glass.padding,
                                                         card3D: frame.card3D, camera: camera)
                frontVisible = geometry.transform.localPoint(camera.eye).z >= geometry.build.paperTop
            } else {
                frontVisible = cos(pose.turn) >= 0
            }
            container.isHidden = (glassAvailable && glassContent == nil) || !frontVisible
            // The scene front pass draws nearer paper over the live view. The legacy
            // renderer instead uses its wheel-docking fade; the fader still handles the
            // live-to-still transition independently in both modes.
            let reveal = CarouselGeometry.usesSceneDepth(frame) ? 1 : 1 - min(1, max(0, card.occlusion))
            container.alpha = CGFloat(min(1, max(0, pose.opacity)) * reveal)
            // Metal tints linear light by 1 - scrim * (1 - promotion); this black layer is
            // its mid-tone equivalent in encoded colour.
            let tint = frame.scrimOpacity * (1 - min(1, max(0, pose.promotion)))
            dimming.alpha = CGFloat(1 - pow(max(0, 1 - tint), 1 / 2.4))
        }
    }

    func fadeIn() {
        fade(to: 1, duration: Self.fadeInDuration, timing: .easeOut, completion: nil)
    }

    /// Fades to the still under the live view, then calls `done`.
    func leave(done: @escaping () -> Void) {
        guard !isLeaving, !isDisposed else { return }
        isLeaving = true
        fade(to: 0, duration: Self.fadeOutDuration, timing: .easeInEaseOut, completion: done)
    }

    /// Explicit animations: frames are placed inside a transaction that disables actions.
    private func fade(to target: Float, duration: TimeInterval, timing: CAMediaTimingFunctionName,
                      completion: (() -> Void)?) {
        let layer = fader.layer
        let current = layer.animation(forKey: "fade") == nil ? (target == 1 ? 0 : layer.opacity) :
            (layer.presentation()?.opacity ?? layer.opacity)
        layer.removeAnimation(forKey: "fade")
        layer.opacity = target
        let remaining = duration * Double(abs(target - current))
        guard remaining > 0.001 else { completion?(); return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = current
        animation.toValue = target
        animation.duration = remaining
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        if let completion { animation.delegate = CarouselAnimationCompletion(completion) }
        layer.add(animation, forKey: "fade")
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        fader.layer.removeAllAnimations()
        content.removeFromSuperview()
        container.removeFromSuperview()
    }
}

/// Core Animation's version of the card shader's turn: about the card's vertical axis,
/// seen in perspective from twice the larger side of the `drawn` card (m34 = -1/d), then
/// tilted in the screen plane. `scale` first maps a view laid out at another size.
enum CarouselTurnTransform {
    /// Places live content on the exact paper plane seen by Metal's shared scene camera.
    /// The layer's position remains at pose.xy; the homography supplies all perspective
    /// terms, including those of a turned card away from the camera's screen centre.
    static func scene(pose: CarouselPose, padding: Double,
                      card3D: CarouselConfiguration.Card3D, camera: CarouselSceneCamera,
                      scale: SIMD2<Double>, planeDepth: Double) -> CATransform3D {
        let geometry = CarouselSceneCardGeometry(pose: pose, padding: padding,
                                                 card3D: card3D, camera: camera)
        var matrix = geometry.screenHomography(depth: planeDepth)
        for column in 0..<3 {
            matrix[column].x -= pose.x * matrix[column].z
            matrix[column].y -= pose.y * matrix[column].z
        }
        let divisor = matrix.columns.2.z
        guard divisor.isFinite, abs(divisor) > 0.000001 else { return CATransform3DIdentity }
        matrix *= 1 / divisor
        matrix.columns.0 *= scale.x
        matrix.columns.1 *= scale.y
        var result = CATransform3DIdentity
        result.m11 = CGFloat(matrix.columns.0.x)
        result.m12 = CGFloat(matrix.columns.0.y)
        result.m14 = CGFloat(matrix.columns.0.z)
        result.m21 = CGFloat(matrix.columns.1.x)
        result.m22 = CGFloat(matrix.columns.1.y)
        result.m24 = CGFloat(matrix.columns.1.z)
        result.m41 = CGFloat(matrix.columns.2.x)
        result.m42 = CGFloat(matrix.columns.2.y)
        result.m44 = CGFloat(matrix.columns.2.z)
        return result
    }

    /// `tiltX`/`tiltY` press the card after its turn, as Metal does: layer y points down, so
    /// sending the bottom edge away is a negative rotation about x.
    static func make(turn: Double, angle: Double, drawn: CGSize,
                     scale: CGSize = CGSize(width: 1, height: 1),
                     tiltX: Double = 0, tiltY: Double = 0) -> CATransform3D {
        var transform = CATransform3DMakeScale(scale.width, scale.height, 1)
        transform = CATransform3DConcat(transform, CATransform3DMakeRotation(CGFloat(turn), 0, 1, 0))
        if tiltX != 0 { transform = CATransform3DConcat(transform, CATransform3DMakeRotation(CGFloat(-tiltX), 1, 0, 0)) }
        if tiltY != 0 { transform = CATransform3DConcat(transform, CATransform3DMakeRotation(CGFloat(tiltY), 0, 1, 0)) }
        var perspective = CATransform3DIdentity
        perspective.m34 = -1 / CGFloat(CarouselGeometry.turnDistance(outer: drawn))
        transform = CATransform3DConcat(transform, perspective)
        return CATransform3DConcat(transform, CATransform3DMakeRotation(CGFloat(angle), 0, 0, 1))
    }
}

/// The back face of the selected card (`cardBack`): laid out once at the selected card's
/// size, then turned, moved and scaled with the card, and shown only while it faces away.
/// In plain Metal it sits on its own rounded panel above the Metal view; in Liquid Glass,
/// inside the card's glass view. It never takes touches: a tap reaches the carousel and
/// turns the card back.
@MainActor
final class CarouselFlipBack {
    let index: Int
    private let container = UIView()
    private let host: UIHostingController<AnyView>
    let size: CGSize
    private var isDisposed = false

    init(index: Int, content: AnyView, size: CGSize) {
        self.index = index
        self.size = size
        host = UIHostingController(rootView: AnyView(content.frame(width: size.width, height: size.height)))
        host.view.backgroundColor = .clear
        for view in [container, host.view!] {
            view.isUserInteractionEnabled = false
        }
        UIView.performWithoutAnimation {
            container.bounds = CGRect(origin: .zero, size: size)
            container.clipsToBounds = true
            container.layer.cornerRadius = size.width * 0.034
            container.layer.allowsEdgeAntialiasing = true
            host.view.frame = container.bounds
            container.addSubview(host.view)
        }
    }

    func place(_ card: CarouselRenderedCard, frame: CarouselFrame, host parent: UIView, below front: UIView?,
               glassContent: UIView?, glassAvailable: Bool) {
        guard !isDisposed else { return }
        UIView.performWithoutAnimation {
            let pose = card.pose
            let scale = CGSize(width: max(0, pose.width) / max(1, Double(size.width)),
                               height: max(0, pose.height) / max(1, Double(size.height)))
            if let glassContent {
                // The glass view turns, and shows the panel's material; seen from behind it
                // mirrors, so the back face is mirrored once more to read the right way.
                if container.superview !== glassContent || glassContent.subviews.last !== container {
                    glassContent.addSubview(container)
                }
                container.backgroundColor = .clear
                let padding = CGFloat(frame.glass.padding)
                container.center = CGPoint(x: padding + CGFloat(pose.width) / 2,
                                           y: padding + CGFloat(pose.height) / 2)
                container.transform = CGAffineTransform(scaleX: -scale.width, y: scale.height)
            } else {
                if container.superview !== parent {
                    if let front, front.superview === parent { parent.insertSubview(container, belowSubview: front) }
                    else { parent.addSubview(container) }
                }
                container.backgroundColor = .secondarySystemBackground
                container.center = CGPoint(x: pose.x, y: pose.y)
                // Seen from the distance the shader turns the card's frame from.
                container.transform3D = CarouselTurnTransform.make(turn: pose.turn, angle: pose.angle,
                    drawn: pose.outerSize(padding: frame.glass.padding),
                    scale: CGSize(width: -scale.width, height: scale.height))
            }
            container.isHidden = (glassAvailable && glassContent == nil) || cos(pose.turn) >= 0
            container.alpha = CGFloat(min(1, max(0, pose.opacity)))
        }
    }

    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        container.removeFromSuperview()
    }
}
