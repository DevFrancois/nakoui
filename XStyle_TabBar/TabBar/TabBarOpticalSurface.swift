import MetalKit
import os
import UIKit

/// A single custom Metal surface. Ordinary UI uses a small reusable shared
/// texture; Carousel supplies GPU crops directly, including animated video.
final class TabBarOpticalSurface: UIView, TabBarReflectionConsumer {
    var reflectionSettings: TabBarReflectionSettings {
        get { renderer?.settings ?? .defaults }
        set {
            let value = newValue.sanitized()
            guard renderer?.settings != value else { return }
            interactionWarmupEnds = 0
            // The existing display link picks up the snapshot next frame.
            // Capture history, cadence, and Carousel leases remain intact.
            renderer?.settings = value
            #if DEBUG
            TabBarPerformanceProbe.shared.settingsChanged()
            #endif
            markContentChanged()
        }
    }

    weak var reflectionSource: TabBarReflectionSource? {
        didSet {
            guard oldValue !== reflectionSource else { return }
            oldValue?.disconnect(self)
            if window != nil { reflectionSource?.connect(self) }
            resetAppearance()
        }
    }

    private final class DisplayTarget: NSObject {
        weak var surface: TabBarOpticalSurface?
        @objc func tick(_ link: CADisplayLink) { surface?.tick(link) }
    }

    private let metalView: MTKView
    private let renderer: TabBarOpticsRenderer?
    private let capture: TabBarUITextureCapture?
    private var cadence = TabBarCaptureSchedule()
    private var displayLink: CADisplayLink?
    private let drawableBroker = CarouselDrawableBroker<CAMetalDrawable>(
        worker: DispatchQueue(label: "tabbar.drawable-broker", qos: .userInteractive))
    private let presentationGate = TabBarPresentationGate()
    private var presentationTime: CFTimeInterval = 0
    private weak var displayLinkScene: UIWindowScene?
    private weak var producerView: UIView?
    private var producerGeometry: TabBarReflectionGeometry?
    private var previousSize: CGSize = .zero
    private var previousCapsule: CGRect = .zero
    // Changed inputs bump contentRevision. Input preparation can also warm the
    // layer before a gesture moves; steady rendering deduplicates revisions.
    private var contentRevision: UInt64 = 1
    private var presentationState = TabBarPresentationState()
    // Until this time, a touch that has not scrolled yet re-encodes identical
    // content to keep Metal awake. Bounded so a long press cannot hold
    // full-rate GPU work for content that never changes.
    private var interactionWarmupEnds: CFTimeInterval = 0
    private static let interactionWarmup: CFTimeInterval = 0.5
    private var isLinkIdle = false
    private var activity = TabBarRenderActivity()
    private lazy var interactionObserver: TabBarInteractionObserver = {
        let observer = TabBarInteractionObserver()
        observer.cancelsTouchesInView = false
        observer.delaysTouchesBegan = false
        observer.delaysTouchesEnded = false
        observer.onActivity = { [weak self] touching, beganAt in
            guard let self else { return }
            self.activity.isInteracting = touching
            if !touching { self.interactionWarmupEnds = 0 }
            guard self.canDraw else { return }
            if let beganAt {
                #if DEBUG
                TabBarPerformanceProbe.shared.interactionBegan(at: beganAt)
                #endif
                // Keep Metal awake while UIKit waits for the scroll threshold.
                // A single warm frame can age out during a slow held gesture.
                self.interactionWarmupEnds = CACurrentMediaTime() + Self.interactionWarmup
                self.markContentChanged()
            } else {
                self.wakeForActivity()
            }
        }
        return observer
    }()
    private var lastSceneDelivery: CFTimeInterval = 0
    // Set when geometry changed after the producer's last delivered frame.
    private var needsProducerFrame = false
    // Hit tested once per tick, then reused by Carousel callbacks.
    private var isCapsuleOccluded = false
    #if DEBUG
    private var uiMotionReason = "initial"
    private let logsMetrics = ProcessInfo.processInfo.environment["TABBAR_METRICS"] == "1"
    private let skipsUICapture = ProcessInfo.processInfo.environment["TABBAR_SKIP_UI_CAPTURE"] == "1"
    private var metricStart: CFTimeInterval = 0
    private var metricTicks = 0
    private var metricFrames = 0
    private var metricCaptures = 0
    private var metricCaptureCost: Double = 0
    private var metricCapturePeak: Double = 0
    private var metricGPUCost: Double = 0
    private var metricLongFrames = 0
    private var metricLastTick: CFTimeInterval = 0
    private var metricDrawCost: Double = 0
    private var metricDrawPeak: Double = 0
    private var metricDraws = 0
    private var metricEntryHeadroom: Double = 0
    private var metricCaptureHeadroom: Double = 0
    private var metricUpdateHeadroom: Double = 0
    private var metricUpdateCount = 0
    private var metricAcquisitionCost: Double = 0
    private var metricAcquisitionPeak: Double = 0
    private var metricEncodingCost: Double = 0
    private var metricSubmissions = 0
    private var metricAppearanceResets = 0
    private var metricGeometryResets = 0
    // Opt-in fault injection waits for static content, then drops one new
    // revision of those same inputs. It never changes saved tuning or captures.
    private let presentationFault = ProcessInfo.processInfo.environment["TABBAR_TEST_DROP_FINAL_FRAME"]
    private let presentationFaultStart = CACurrentMediaTime()
    private var faultRevision: UInt64?
    private var faultSubmitted = false
    private var faultConfirmed = false
    private var faultSettled = false
    #endif

    override init(frame: CGRect) {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.maximumDrawableCount = 3
            layer.presentsWithTransaction = false
        }
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.framebufferOnly = true
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        // Only the broker's preparation phase changes drawableSize. A layout
        // update must never reconfigure it while nextDrawable runs off-main.
        view.autoResizeDrawable = false
        metalView = view
        renderer = TabBarOpticsRenderer(view: view)
        capture = view.device.flatMap { TabBarUITextureCapture(device: $0) }
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        addSubview(metalView)
        renderer?.onSceneUpdate = { [weak self] in
            self?.interactionWarmupEnds = 0
            #if DEBUG
            TabBarPerformanceProbe.shared.scenePublished()
            #endif
            self?.markContentChanged()
        }
        #if DEBUG
        renderer?.onGPUFrame = { [weak self] duration in
            guard let self, self.logsMetrics else { return }
            self.metricFrames += 1
            self.metricGPUCost += max(0, duration)
        }
        if logsMetrics {
            renderer?.onCPUFrame = { [weak self] acquisition, encoding in
                guard let self else { return }
                self.metricAcquisitionCost += acquisition
                self.metricAcquisitionPeak = max(self.metricAcquisitionPeak, acquisition)
                self.metricEncodingCost += encoding
                self.metricSubmissions += 1
            }
        }
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(resetAppearance),
                                              name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetAppearance),
                                              name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resetAppearance),
                                              name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) {
            (view: TabBarOpticalSurface, _: UITraitCollection) in view.resetAppearance()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if metalView.frame != bounds { metalView.frame = bounds }
        if metalView.contentScaleFactor != traitCollection.displayScale {
            metalView.contentScaleFactor = traitCollection.displayScale
        }
        let radius = min(bounds.width, bounds.height) / 2
        if layer.cornerRadius != radius { layer.cornerRadius = radius }
        if previousSize != bounds.size {
            previousSize = bounds.size
            resetAppearance()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if interactionObserver.view !== window {
            interactionObserver.view?.removeGestureRecognizer(interactionObserver)
            activity.isInteracting = false
            window?.addGestureRecognizer(interactionObserver)
        }
        if window == nil { reflectionSource?.disconnect(self) }
        else { reflectionSource?.connect(self) }
        resetAppearance()
    }

    @objc private func resetAppearance() {
        #if DEBUG
        metricAppearanceResets += 1
        #endif
        invalidatePresentation()
        contentRevision &+= 1
        activity = TabBarRenderActivity()
        interactionWarmupEnds = 0
        activity.noteChange(at: CACurrentMediaTime())
        renderer?.clearScene()
        renderer?.currentUI = nil
        capture?.reset()
        cadence.reset()
        previousCapsule = .zero
        let scene = window?.windowScene
        let shouldAnimate = window != nil && UIApplication.shared.applicationState == .active
        if !shouldAnimate || displayLinkScene !== scene {
            displayLink?.invalidate()
            displayLink = nil
            displayLinkScene = nil
        }
        if shouldAnimate, displayLink == nil {
            let target = DisplayTarget()
            target.surface = self
            let selector = #selector(DisplayTarget.tick(_:))
            let link: CADisplayLink
            if #available(iOS 27.0, *), let scene {
                // Target this view's display and follow its scene between
                // displays instead of assuming the main display's timeline.
                link = scene.displayLink(target: target, selector: selector)
                    ?? CADisplayLink(target: target, selector: selector)
            } else {
                link = CADisplayLink(target: target, selector: selector)
            }
            link.add(to: .main, forMode: .common)
            displayLink = link
            displayLinkScene = scene
            isLinkIdle = true
            setLinkIdle(false)
        }
        reflectionSource?.requestFrame()
    }

    private func markContentChanged() {
        contentRevision &+= 1
        wakeForActivity(drawChangedContent: true)
    }

    func uiDidMove() {
        guard canDraw else { return }
        interactionWarmupEnds = 0
        cadence.noteUIMotion(at: CACurrentMediaTime())
        #if DEBUG
        uiMotionReason = "scroll"
        #endif
        wakeForActivity()
    }

    private func wakeForActivity(drawChangedContent: Bool = false) {
        activity.noteChange(at: CACurrentMediaTime())
        let wasIdle = isLinkIdle
        setLinkIdle(false)
        // Published GPU crops/settings may arrive just after the display tick.
        // Let the bounded broker consume them immediately; its encoding guard
        // rejects duplicate tick requests for the same content revision.
        if wasIdle || drawChangedContent, canDraw { requestDraw() }
    }

    /// While nothing changes, ticks only look for UI changes at a low rate and
    /// leave the display free to drop its refresh rate.
    private func setLinkIdle(_ idle: Bool) {
        guard let displayLink, idle != isLinkIdle else { return }
        isLinkIdle = idle
        let maximum = Float(window?.screen.maximumFramesPerSecond ?? 60)
        displayLink.preferredFrameRateRange = idle
            ? CAFrameRateRange(minimum: min(10, maximum), maximum: min(30, maximum), preferred: min(30, maximum))
            : CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
    }

    private var canDraw: Bool {
        window?.windowScene?.activationState == .foregroundActive && isVisibleInWindow(self)
    }

    private var desiredDrawableSize: CGSize {
        let scale = traitCollection.displayScale
        return CGSize(width: max(1, (bounds.width * scale).rounded(.up)),
                      height: max(1, (bounds.height * scale).rounded(.up)))
    }

    private func invalidatePresentation() {
        presentationGate.advance()
        presentationState.invalidate()
        drawableBroker.invalidate()
    }

    private var isWarmingInteraction: Bool {
        CACurrentMediaTime() < interactionWarmupEnds
    }

    /// Content already submitted needs no new frame, except to warm an
    /// interaction that has not moved yet.
    private var needsEncoding: Bool {
        presentationState.needsEncoding(contentRevision) || isWarmingInteraction
    }

    private func requestDraw() {
        // Carousel's bounded broker replaces pending requests. A blocked driver
        // can neither block UIKit nor accumulate obsolete reflection frames.
        drawableBroker.request(prepare: { [weak self] in
            // Reject duplicate requests before acquiring a drawable, so ticks
            // that only keep the clock awake cost no driver work.
            guard let self, self.canDraw, self.needsEncoding,
                  let layer = self.metalView.layer as? CAMetalLayer else { return nil }
            let size = self.desiredDrawableSize
            if layer.drawableSize != size { layer.drawableSize = size }
            return { layer.nextDrawable() }
        }, consume: { [weak self] drawable, finish in
            guard let self, self.canDraw,
                  drawable.texture.width == Int(self.desiredDrawableSize.width),
                  drawable.texture.height == Int(self.desiredDrawableSize.height) else { finish(); return }
            self.draw(drawable, finish: finish)
        })
    }

    private func draw(_ drawable: CAMetalDrawable, finish: @escaping () -> Void) {
        guard let window, let renderer else { finish(); return }
        // The UI may move while acquisition waits. Use the latest textures,
        // geometry and tuning at handoff, never the request's older snapshot.
        synchronizeGeometry(window: window, renderer: renderer)
        guard needsEncoding else { finish(); return }
        renderer.currentUI = capture?.current
        renderer.darkMode = traitCollection.userInterfaceStyle == .dark
        renderer.reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        #if DEBUG
        let started = CACurrentMediaTime()
        #endif
        let gate = presentationGate
        let revision = gate.current
        let encodedRevision = contentRevision
        let encodedTime = presentationTime
        let broker = drawableBroker
        let submitted = autoreleasepool {
            renderer.draw(in: metalView, drawable: drawable) { [weak self] command in
                guard let self else { finish(); return }
                let ticket = self.presentationState.submit(encodedRevision, at: CACurrentMediaTime())
                #if DEBUG
                let recordPresentation = TabBarPerformanceProbe.shared.presentationRecorder(
                    current: self.capture?.current, previous: self.capture?.current, targetTime: encodedTime)
                let forcedDrop = self.faultRevision == encodedRevision && !self.faultSubmitted
                let silentDrop = forcedDrop && self.presentationFault == "silent"
                if forcedDrop {
                    self.faultSubmitted = true
                    print("TABBAR_PRESENTATION_FAULT event=dropped revision=\(encodedRevision) ticket=\(ticket.id) mode=\(self.presentationFault ?? "")")
                }
                #else
                let forcedDrop = false
                let silentDrop = false
                #endif
                // Release acquisition on scheduling, not display acknowledgement:
                // waiting for presentation would serialize the rendering pipeline.
                var released = false
                let release = {
                    guard !released else { return }
                    released = true
                    finish()
                }
                let acknowledge: (CFTimeInterval) -> Void = { [weak self] time in
                    guard let self else { return }
                    let presented = time.isFinite && time > 0
                    let retry = self.presentationState.resolve(ticket, presented: presented)
                    #if DEBUG
                    if self.faultRevision == encodedRevision, presented, !self.faultConfirmed,
                       self.presentationGate.current == revision {
                        self.faultConfirmed = true
                        print("TABBAR_PRESENTATION_FAULT event=confirmed revision=\(encodedRevision) ticket=\(ticket.id) sameContent=\(self.contentRevision == encodedRevision) time=\(time)")
                    }
                    #endif
                    if retry { self.wakeForActivity(drawChangedContent: true) }
                }
                #if !targetEnvironment(simulator)
                if !forcedDrop {
                    drawable.addPresentedHandler { presented in
                        let time = presented.presentedTime
                        DispatchQueue.main.async {
                            #if DEBUG
                            // Count the drawable callback once, independently
                            // of earlier generation/command failure reports.
                            recordPresentation?(time)
                            #endif
                            acknowledge(time)
                        }
                    }
                }
                #endif
                command.addScheduledHandler { _ in
                    // Present from Metal's scheduling thread: no main-thread hop
                    // or Core Animation transaction delays a rendered frame, and
                    // a frame encoded before a reset never reaches the screen.
                    let accepted = !forcedDrop && gate.present(drawable, ifCurrent: revision)
                    DispatchQueue.main.async {
                        #if DEBUG
                        #if targetEnvironment(simulator)
                        if accepted { recordPresentation?(CACurrentMediaTime()) }
                        #endif
                        #endif
                        if !accepted, !forcedDrop { acknowledge(0) }
                        release()
                    }
                }
                command.addCompletedHandler { buffer in
                    if buffer.status != .completed || (forcedDrop && !silentDrop) {
                        DispatchQueue.main.async {
                            acknowledge(0)
                            release()
                        }
                        return
                    }
                    #if targetEnvironment(simulator)
                    if !silentDrop {
                        // Simulator lacks drawable presentation callbacks. Its
                        // fallback acknowledges GPU completion after the gated
                        // present request, not verified onscreen presentation.
                        let accepted = gate.current == revision
                        DispatchQueue.main.async { acknowledge(accepted ? CACurrentMediaTime() : 0) }
                    }
                    #endif
                }
                broker.submit { command.commit() }
            }
        }
        if !submitted { finish() }
        #if DEBUG
        if logsMetrics {
            let duration = CACurrentMediaTime() - started
            metricDrawCost += duration
            metricDrawPeak = max(metricDrawPeak, duration)
            metricDraws += 1
        }
        #endif
    }

    private func tick(_ link: CADisplayLink) {
        guard let window, let renderer, isVisibleInWindow(self),
              window.windowScene?.activationState == .foregroundActive else { return }
        #if DEBUG
        let tickStart = CACurrentMediaTime()
        #endif
        updateOcclusion(window: window)
        synchronizeGeometry(window: window, renderer: renderer)
        if needsProducerFrame, producerView != nil { requestProducerFrameIfSettled() }
        let capsule = renderer.capsuleInWindow
        renderer.reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        presentationTime = link.targetTimestamp
        // One scene clock drives both capture and rendering. Capture is admitted
        // before requesting a drawable, and all driver waits stay on the worker.
        let now = CACurrentMediaTime()
        if let timedOut = presentationState.retryUnacknowledged(at: now) {
            activity.noteChange(at: now)
            #if DEBUG
            if faultRevision == timedOut.revision {
                print("TABBAR_PRESENTATION_FAULT event=timeout revision=\(timedOut.revision) ticket=\(timedOut.id)")
            }
            #endif
        }
        let updateDeadline = UIUpdateInfo.current(for: self)?.completionDeadlineTime
        let captureDeadline = TabBarCaptureCadence.submissionDeadline(
            displayTarget: link.targetTimestamp, uiCompletion: updateDeadline)
        #if DEBUG
        if logsMetrics {
            metricEntryHeadroom += link.targetTimestamp - tickStart
            metricCaptureHeadroom += link.targetTimestamp - now
            if let updateDeadline {
                metricUpdateHeadroom += updateDeadline - now
                metricUpdateCount += 1
            }
        }
        #endif
        var shouldCaptureUI = !renderer.reduceTransparency
        #if DEBUG
        shouldCaptureUI = shouldCaptureUI && !skipsUICapture
        #endif
        // A finger can be held on a static page while the display clock is
        // active. Its costly idle checks must not overwrite scrolling history.
        let isIdleCapture = !cadence.hasUIMotion(at: now)
        let captureAdmitted = shouldCaptureUI && cadence.shouldCapture(
            at: now, deadline: captureDeadline, isIdle: isIdleCapture, force: capture?.current == nil)
        #if DEBUG
        if shouldCaptureUI, !captureAdmitted {
            TabBarPerformanceProbe.shared.captureDeferred(
                estimatedDuration: cadence.estimatedDuration(isIdle: isIdleCapture),
                headroom: captureDeadline - now)
        }
        if captureAdmitted { TabBarPerformanceProbe.shared.captureAttemptBegan() }
        #endif
        if captureAdmitted, let capture,
           capture.capture(window: window, rect: capsule.insetBy(dx: -TabBarReflectionSettings.captureMargin,
                                                                 dy: -TabBarReflectionSettings.captureMargin),
                           excluding: capsule, at: link.targetTimestamp) {
            cadence.recordCapture(duration: capture.lastCaptureDuration, at: now,
                                  isIdle: isIdleCapture)
            if capture.lastCaptureChanged {
                contentRevision &+= 1
                activity.noteChange(at: now)
            }
            #if DEBUG
            TabBarPerformanceProbe.shared.captureMeasured(duration: capture.lastCaptureDuration,
                isIdle: isIdleCapture,
                reason: uiMotionReason, changed: capture.lastCaptureChanged)
            if let frame = capture.current {
                TabBarPerformanceProbe.shared.uiCaptured(frame, changed: capture.lastCaptureChanged)
            }
            metricCaptures += 1
            metricCaptureCost += capture.lastCaptureDuration
            metricCapturePeak = max(metricCapturePeak, capture.lastCaptureDuration)
            #endif
        }
        // Keep the broker supplied throughout motion, including clean ticks
        // between asynchronous producer callbacks. Static content still idles.
        #if DEBUG
        if (presentationFault == "drop" || presentationFault == "silent"), faultRevision == nil,
           now - presentationFaultStart > 2, !activity.isActive(at: now),
           presentationState.presentedRevision == contentRevision {
            contentRevision &+= 1
            faultRevision = contentRevision
            activity.noteChange(at: now)
            print("TABBAR_PRESENTATION_FAULT event=armed revision=\(contentRevision)")
        }
        #endif
        let needsDraw = contentRevision != presentationState.presentedRevision || activity.isActive(at: now)
        setLinkIdle(!needsDraw)
        if needsDraw { requestDraw() }
        #if DEBUG
        if faultConfirmed, !needsDraw, !faultSettled {
            faultSettled = true
            print("TABBAR_PRESENTATION_FAULT event=settled revision=\(contentRevision) sameContent=\(contentRevision == faultRevision)")
        }
        logMetrics(link)
        #endif
    }

    private func updateOcclusion(window: UIWindow) {
        // Only a GPU producer needs this check; ordinary UI capture excludes
        // the capsule itself. Without a hit (for example while a transition
        // disables hit testing), nothing is known to cover the menu.
        guard producerView != nil, let menu = superview else { isCapsuleOccluded = false; return }
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        isCapsuleOccluded = window.hitTest(center, with: nil).map { !$0.isDescendant(of: menu) } ?? false
    }

    /// A settled producer pauses its clock; one moving on its own needs no extra
    /// frame. A request deferred while it delivers is retried on later ticks,
    /// so a producer that pauses right after a geometry change still recrops.
    private func requestProducerFrameIfSettled() {
        needsProducerFrame = true
        guard CACurrentMediaTime() - lastSceneDelivery > 0.1 else { return }
        needsProducerFrame = false
        reflectionSource?.requestFrame()
    }

    private func synchronizeGeometry(window: UIWindow, renderer: TabBarOpticsRenderer) {
        let capsule = convert(bounds, to: window)
        if capsule != previousCapsule {
            #if DEBUG
            metricGeometryResets += 1
            #endif
            // Captures and crops are placed in window space, so they remain
            // valid while the capsule moves. The cadence keeps its cost budget.
            previousCapsule = capsule
            cadence.noteUIMotion(at: CACurrentMediaTime())
            #if DEBUG
            uiMotionReason = "capsule"
            #endif
            contentRevision &+= 1
            requestProducerFrameIfSettled()
        }
        renderer.capsuleInWindow = capsule
        if let producerView {
            let geometry = reflectionGeometry(from: producerView)
            if geometry != producerGeometry {
                producerGeometry = geometry
                contentRevision &+= 1
                // The window-space crop stays usable while the producer moves.
                if geometry == nil { renderer.clearScene() } else { requestProducerFrameIfSettled() }
            }
        }
    }

    func clearReflection(from view: UIView?) {
        guard view == nil || producerView === view else { return }
        invalidatePresentation()
        producerView = nil
        producerGeometry = nil
        needsProducerFrame = false
        renderer?.clearScene()
        contentRevision &+= 1
        // Ordinary UI keeps reflecting when a GPU producer disappears or a tab changes.
        cadence.reset()
    }

    func receive(texture: MTLTexture, commandBuffer: MTLCommandBuffer, from view: UIView) {
        guard let window, let renderer, let geometry = reflectionGeometry(from: view) else {
            clearReflection(from: view)
            return
        }
        producerView = view
        producerGeometry = geometry
        lastSceneDelivery = CACurrentMediaTime()
        // A crop may complete just after this display tick. Keep the clock
        // active while the producer works, not only after its copy is published.
        wakeForActivity()
        #if DEBUG
        TabBarPerformanceProbe.shared.sceneDelivered()
        #endif
        // This frame is cropped with the current geometry.
        needsProducerFrame = false
        renderer.capsuleInWindow = convert(bounds, to: window)
        let source = view.convert(view.bounds, to: window)
        let visible = geometry.visibleRect.offsetBy(dx: source.minX, dy: source.minY)
        renderer.encodeScene(texture: texture, commandBuffer: commandBuffer,
                             sourceInWindow: source, visibleInWindow: visible) { [weak self, weak view] in
            guard let self, let view else { return false }
            // Losing the producer clears it; renderer revisions reject stale copies.
            return self.producerView === view && !self.isCapsuleOccluded
        }
    }

    private func reflectionGeometry(from view: UIView) -> TabBarReflectionGeometry? {
        guard let window, view.window === window,
              window.windowScene?.activationState == .foregroundActive,
              isVisibleInWindow(self), isVisibleInWindow(view), !isCapsuleOccluded else { return nil }
        let sourceRect = view.convert(view.bounds, to: window)
        var visibleRect = sourceRect.intersection(window.bounds)
        var ancestor = view.superview
        while let current = ancestor {
            if current.clipsToBounds {
                visibleRect = visibleRect.intersection(current.convert(current.bounds, to: window))
            }
            ancestor = current.superview
        }
        return TabBarReflectionGeometry(capsuleInWindow: convert(bounds, to: window),
            sourceInWindow: sourceRect, visibleSourceInWindow: visibleRect)
    }

    private func isVisibleInWindow(_ view: UIView) -> Bool {
        guard let window = view.window, view.bounds.width > 0, view.bounds.height > 0,
              view.convert(view.bounds, to: window).intersects(window.bounds) else { return false }
        var ancestor: UIView? = view
        while let current = ancestor {
            guard !current.isHidden, current.alpha > 0.01 else { return false }
            ancestor = current.superview
        }
        return true
    }

    #if DEBUG
    private func logMetrics(_ link: CADisplayLink) {
        guard logsMetrics else { return }
        let now = CACurrentMediaTime()
        if metricStart == 0 { metricStart = now }
        // Use display timestamps, not the varying time when capture finishes.
        // Measuring here with `now` would report a false hitch whenever a cheap
        // frame followed a frame that performed a capture.
        if metricLastTick > 0, link.timestamp - metricLastTick > (link.targetTimestamp - link.timestamp) * 1.5 {
            metricLongFrames += 1
        }
        metricLastTick = link.timestamp
        metricTicks += 1
        let elapsed = now - metricStart
        guard elapsed >= 2 else { return }
        TabBarPerformanceProbe.shared.report(elapsed: elapsed)
        print(String(format: "TABBAR_METRICS ticks=%.1f gpuFPS=%.1f captures=%.1f captureMeanMS=%.2f captureMaxMS=%.2f gpuMS=%.2f drawMeanMS=%.2f drawMaxMS=%.2f entryHeadroomMS=%.2f captureHeadroomMS=%.2f updateHeadroomMS=%.2f updateSamples=%d longFrames=%d acquisitionMeanMS=%.2f acquisitionMaxMS=%.2f encodingMeanMS=%.2f appearanceResets=%d geometryResets=%d thermalState=%d scene=%@",
                     Double(metricTicks) / elapsed, Double(metricFrames) / elapsed,
                     Double(metricCaptures) / elapsed, metricCaptureCost * 1000 / Double(max(1, metricCaptures)),
                     metricCapturePeak * 1000, metricGPUCost * 1000 / Double(max(1, metricFrames)),
                     metricDrawCost * 1000 / Double(max(1, metricDraws)), metricDrawPeak * 1000,
                     metricEntryHeadroom * 1000 / Double(max(1, metricTicks)),
                     metricCaptureHeadroom * 1000 / Double(max(1, metricTicks)),
                     metricUpdateHeadroom * 1000 / Double(max(1, metricUpdateCount)), metricUpdateCount,
                     metricLongFrames,
                     metricAcquisitionCost * 1000 / Double(max(1, metricSubmissions)), metricAcquisitionPeak * 1000,
                     metricEncodingCost * 1000 / Double(max(1, metricSubmissions)),
                     metricAppearanceResets, metricGeometryResets, ProcessInfo.processInfo.thermalState.rawValue,
                     producerView == nil ? "UI" : "Carousel+UI"))
        metricStart = now
        metricTicks = 0; metricFrames = 0; metricCaptures = 0
        metricCaptureCost = 0; metricCapturePeak = 0; metricGPUCost = 0; metricLongFrames = 0
        metricDrawCost = 0; metricDrawPeak = 0; metricEntryHeadroom = 0; metricCaptureHeadroom = 0
        metricDraws = 0
        metricUpdateHeadroom = 0; metricUpdateCount = 0
        metricAcquisitionCost = 0; metricAcquisitionPeak = 0; metricEncodingCost = 0; metricSubmissions = 0
        metricAppearanceResets = 0; metricGeometryResets = 0
    }
    #endif
}

/// Observes window input without recognizing, preventing or delaying another
/// gesture. This wakes the reflection clock before a scroll's first pixel change.
private final class TabBarInteractionObserver: UIGestureRecognizer {
    var onActivity: ((_ touching: Bool, _ beganAt: CFTimeInterval?) -> Void)?
    private var touchCount = 0

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        let first = touchCount == 0
        touchCount += touches.count
        onActivity?(true, first ? touches.map(\.timestamp).min() : nil)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        onActivity?(true, nil)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches)
    }

    override func reset() {
        super.reset()
        if touchCount > 0 { onActivity?(false, nil) }
        touchCount = 0
    }

    private func finish(_ touches: Set<UITouch>) {
        touchCount = max(0, touchCount - touches.count)
        onActivity?(touchCount > 0, nil)
        if touchCount == 0 { state = .failed }
    }
}

/// The presentation revision, readable from Metal's scheduling thread. A reset
/// advances it on main; frames encoded under an older revision are dropped.
nonisolated private final class TabBarPresentationGate: Sendable {
    private let revision = OSAllocatedUnfairLock(initialState: UInt64(0))

    var current: UInt64 { revision.withLock { $0 } }

    func advance() { revision.withLock { $0 &+= 1 } }

    /// Holding the lock keeps a reset from landing between the check and present.
    func present(_ drawable: MTLDrawable, ifCurrent expected: UInt64) -> Bool {
        revision.withLockUnchecked { current in
            guard current == expected else { return false }
            drawable.present()
            return true
        }
    }
}
