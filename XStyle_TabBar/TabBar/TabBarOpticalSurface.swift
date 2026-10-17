import MetalKit
import UIKit

/// A custom translucent capsule whose rim picks up the actual UI around it.
/// Captures are small and capped at 15 Hz; Metal draws only when one arrives.
final class TabBarOpticalSurface: UIView {
    private final class DisplayLinkTarget: NSObject {
        weak var surface: TabBarOpticalSurface?

        @objc func tick(_ link: CADisplayLink) {
            surface?.refreshBackdrop()
        }
    }

    private let metalView: MTKView
    private let renderer: TabBarOpticsRenderer?
    private let capture = TabBarBackdropCapture()
    private let displayLinkTarget = DisplayLinkTarget()
    private var displayLink: CADisplayLink?

    override init(frame: CGRect) {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm_srgb
        if let layer = view.layer as? CAMetalLayer {
            layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.autoResizeDrawable = true
        metalView = view
        renderer = TabBarOpticsRenderer(view: view)
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        addSubview(metalView)
        displayLinkTarget.surface = self
        NotificationCenter.default.addObserver(self, selector: #selector(resumeClock),
                                              name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pauseClock),
                                              name: UIApplication.willResignActiveNotification, object: nil)
        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitDisplayScale.self]) {
            (view: TabBarOpticalSurface, _: UITraitCollection) in view.setNeedsLayout()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        displayLink?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalView.frame = bounds
        metalView.contentScaleFactor = traitCollection.displayScale
        // No capture during layout: the hierarchy must first finish its frame.
        // A neutral fallback still leaves all destinations usable without Metal.
        backgroundColor = renderer == nil ? .secondarySystemBackground : .clear
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil, renderer != nil else { return }
        let link = CADisplayLink(target: displayLinkTarget, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 15, preferred: 15)
        link.add(to: .main, forMode: .common)
        displayLink = link
        link.isPaused = UIApplication.shared.applicationState != .active
    }

    @objc private func resumeClock() {
        displayLink?.isPaused = false
    }

    @objc private func pauseClock() {
        displayLink?.isPaused = true
    }

    private func refreshBackdrop() {
        guard let renderer, !renderer.isRendering, let window,
              window.windowScene?.activationState == .foregroundActive,
              bounds.width > 0, bounds.height > 0 else { return }
        var ancestor: UIView? = self
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            // Snapshots contain presented pixels, while convert(_:to:) uses
            // the destination geometry of an animation. Keep the last optical
            // frame until those agree, so an old menu position never becomes
            // a neighboring color during selection or window resizing.
            if let displayed = view.layer.presentation(),
               geometryDiffers(displayed, from: view.layer) { return }
            ancestor = view.superview
        }
        // A pushed screen or sheet may cover the bar without detaching it.
        // The containing menu owns all hits in the capsule, including its gaps.
        let center = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: window)
        guard let menu = superview, let hit = window.hitTest(center, with: nil),
              hit.isDescendant(of: menu),
              let frame = capture.capture(around: self) else { return }
        renderer.display(frame, in: metalView,
                         darkMode: traitCollection.userInterfaceStyle == .dark,
                         reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)
    }

    private func geometryDiffers(_ displayed: CALayer, from model: CALayer) -> Bool {
        abs(displayed.position.x - model.position.x) > 0.5
            || abs(displayed.position.y - model.position.y) > 0.5
            || abs(displayed.bounds.minX - model.bounds.minX) > 0.5
            || abs(displayed.bounds.minY - model.bounds.minY) > 0.5
            || abs(displayed.bounds.width - model.bounds.width) > 0.5
            || abs(displayed.bounds.height - model.bounds.height) > 0.5
            || !CATransform3DEqualToTransform(displayed.transform, model.transform)
    }
}
