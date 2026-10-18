import MetalKit
import UIKit

/// A single custom Metal surface. Ordinary UI uses a small reusable shared
/// texture; Carousel supplies GPU crops directly, including animated video.
final class TabBarOpticalSurface: UIView, TabBarReflectionConsumer {
    var reflectionSettings: TabBarReflectionSettings {
        get { renderer?.settings ?? .defaults }
        set {
            let value = newValue.sanitized()
            guard renderer?.settings != value else { return }
            // The existing display link picks up the snapshot next frame.
            // Capture history, cadence, and Carousel leases remain intact.
            renderer?.settings = value
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
    private var cadence = TabBarCaptureCadence()
    private var displayLink: CADisplayLink?
    private let drawableBroker = CarouselDrawableBroker<CAMetalDrawable>(
        worker: DispatchQueue(label: "tabbar.drawable-broker", qos: .userInteractive))
    private var presentationRevision: UInt64 = 0
    private var presentationTime: CFTimeInterval = 0
    private weak var displayLinkScene: UIWindowScene?
    private weak var producerView: UIView?
    private var producerGeometry: TabBarReflectionGeometry?
    private var previousSize: CGSize = .zero
    private var previousCapsule: CGRect = .zero
    #if DEBUG
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
    #endif

    override init(frame: CGRect) {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            layer.maximumDrawableCount = 3
            layer.presentsWithTransaction = true
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
        if window == nil { reflectionSource?.disconnect(self) }
        else { reflectionSource?.connect(self) }
        resetAppearance()
    }

    @objc private func resetAppearance() {
        #if DEBUG
        metricAppearanceResets += 1
        #endif
        invalidatePresentation()
        renderer?.clearScene()
        renderer?.currentUI = nil
        renderer?.previousUI = nil
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
            let maximum = Float(window?.screen.maximumFramesPerSecond ?? 60)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, maximum), maximum: maximum, preferred: maximum)
            link.add(to: .main, forMode: .common)
            displayLink = link
            displayLinkScene = scene
        }
        reflectionSource?.requestFrame()
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
        presentationRevision &+= 1
        drawableBroker.invalidate()
    }

    private func requestDraw() {
        // Carousel's bounded broker replaces pending requests. A blocked driver
        // can neither block UIKit nor accumulate obsolete reflection frames.
        drawableBroker.request(prepare: { [weak self] in
            guard let self, self.canDraw, let layer = self.metalView.layer as? CAMetalLayer else { return nil }
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
        renderer.currentUI = capture?.current
        renderer.previousUI = capture?.previous
        renderer.presentationTime = presentationTime
        renderer.darkMode = traitCollection.userInterfaceStyle == .dark
        renderer.reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        #if DEBUG
        let started = CACurrentMediaTime()
        #endif
        let revision = presentationRevision
        let broker = drawableBroker
        let submitted = autoreleasepool {
            renderer.draw(in: metalView, drawable: drawable) { [weak self] command, present in
                var pendingPresentation: (() -> Void)? = present
                let resolve: (Bool) -> Void = { [weak self] scheduled in
                    guard let presentation = pendingPresentation else { return }
                    pendingPresentation = nil
                    defer { finish() }
                    guard let self, scheduled, self.canDraw,
                          self.presentationRevision == revision else { return }
                    presentation()
                }
                command.addScheduledHandler { _ in DispatchQueue.main.async { resolve(true) } }
                command.addCompletedHandler { buffer in
                    if buffer.status != .completed { DispatchQueue.main.async { resolve(false) } }
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
        synchronizeGeometry(window: window, renderer: renderer)
        let capsule = renderer.capsuleInWindow
        renderer.reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        presentationTime = link.targetTimestamp
        // One scene clock drives both capture and rendering. Capture is admitted
        // before requesting a drawable, and all driver waits stay on the worker.
        let now = CACurrentMediaTime()
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
        if shouldCaptureUI, let capture,
           cadence.shouldCapture(at: now, deadline: captureDeadline, force: capture.current == nil),
           capture.capture(window: window, rect: capsule.insetBy(dx: -104, dy: -104), excluding: capsule, at: link.targetTimestamp) {
            cadence.recordCapture(duration: capture.lastCaptureDuration, at: now)
            #if DEBUG
            metricCaptures += 1
            metricCaptureCost += capture.lastCaptureDuration
            metricCapturePeak = max(metricCapturePeak, capture.lastCaptureDuration)
            #endif
        }
        requestDraw()
        #if DEBUG
        logMetrics(link)
        #endif
    }

    private func synchronizeGeometry(window: UIWindow, renderer: TabBarOpticsRenderer) {
        let capsule = convert(bounds, to: window)
        if capsule != previousCapsule {
            #if DEBUG
            metricGeometryResets += 1
            #endif
            invalidatePresentation()
            previousCapsule = capsule
            renderer.clearScene()
            capture?.reset()
            cadence.reset()
            reflectionSource?.requestFrame()
        }
        renderer.capsuleInWindow = capsule
        if let producerView {
            let geometry = reflectionGeometry(from: producerView)
            if geometry != producerGeometry {
                invalidatePresentation()
                producerGeometry = geometry
                renderer.clearScene()
                reflectionSource?.requestFrame()
            }
        }
    }

    func clearReflection(from view: UIView?) {
        guard view == nil || producerView === view else { return }
        invalidatePresentation()
        producerView = nil
        producerGeometry = nil
        renderer?.clearScene()
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
        renderer.capsuleInWindow = convert(bounds, to: window)
        let source = view.convert(view.bounds, to: window)
        let visible = geometry.visibleRect.offsetBy(dx: source.minX, dy: source.minY)
        renderer.encodeScene(texture: texture, commandBuffer: commandBuffer,
                             sourceInWindow: source, visibleInWindow: visible) { [weak self, weak view] in
            guard let self, let view else { return false }
            return self.producerView === view && self.reflectionGeometry(from: view) == geometry
        }
    }

    private func reflectionGeometry(from view: UIView) -> TabBarReflectionGeometry? {
        guard let window, view.window === window,
              window.windowScene?.activationState == .foregroundActive,
              isVisibleInWindow(self), isVisibleInWindow(view),
              let menu = superview,
              let hit = window.hitTest(convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window), with: nil),
              hit.isDescendant(of: menu) else { return nil }
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
