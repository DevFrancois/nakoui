import UIKit

/// Persistent controls and touch tracking. The enclosing SwiftUI view supplies
/// the glass and scales the visual subtree without changing touch coordinates.
final class GlassTabBarView: UIView {
    var onSelect: ((RootTab) -> Void)?

    private let containerView = UIView()
    private let presentation: GlassTabBarPresentation
    private let selectionView = GlassTabBarHighlight()
    private var shimmerDirection: CGFloat = 1
    private let buttons = RootTab.allCases.map { GlassTabBarButton(tab: $0) }
    private let touchRecognizer = GlassTabBarTouchRecognizer()
    private lazy var releaseFeedback = UIImpactFeedbackGenerator(style: .light, view: self)
    private var interaction: GlassTabBarInteraction
    private var reduceMotion = false
    private var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    private var lastGeometry: GlassTabBarInteraction.Geometry?
    private var environmentInputs: EnvironmentInputs?
    private weak var trackingCoordinateView: UIView?

    convenience init(selection: RootTab) {
        self.init(selection: selection, presentation: GlassTabBarPresentation())
    }

    init(selection: RootTab, presentation: GlassTabBarPresentation) {
        self.presentation = presentation
        interaction = GlassTabBarInteraction(selection: selection)
        super.init(frame: .zero)
        isOpaque = false
        isAccessibilityElement = false
        accessibilityTraits = .tabBar
        accessibilityElements = buttons

        addSubview(containerView)
        containerView.addSubview(selectionView)
        for button in buttons {
            containerView.addSubview(button)
            button.isSelected = button.tab == selection
            button.addTarget(self, action: #selector(selectButton(_:)), for: .touchUpInside)
            button.onSizeChange = { [weak self] in
                self?.invalidateIntrinsicContentSize()
                self?.setNeedsLayout()
            }
        }
        touchRecognizer.onBegin = { [weak self] point in
            guard let self else { return }
            self.layoutIfNeeded()
            guard let point = self.trackingPoint(point) else { return }
            self.trackingCoordinateView = self.presentation.coordinateSpace(for: self)
            self.interaction.begin(at: point, geometry: self.currentGeometry)
            if self.interaction.tracking != nil { self.releaseFeedback.prepare() }
            self.showTracking()
            if let candidate = self.interaction.tracking?.candidate, candidate != self.interaction.selection {
                self.shimmerHighlight()
            }
        }
        touchRecognizer.addTarget(self, action: #selector(trackTouch(_:)))
        touchRecognizer.delaysTouchesBegan = true
        touchRecognizer.cancelsTouchesInView = true
        addGestureRecognizer(touchRecognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateEnvironment(
        locale: Locale,
        contentSizeCategory: UIContentSizeCategory,
        layoutDirection: UIUserInterfaceLayoutDirection,
        layoutAxis: NSLayoutConstraint.Axis,
        reduceMotion: Bool,
        isEnabled: Bool
    ) {
        // SwiftUI updates on every selection and parent pass; only a changed
        // input needs the bar re-measured.
        let inputs = EnvironmentInputs(locale: locale, contentSizeCategory: contentSizeCategory,
                                       layoutDirection: layoutDirection, layoutAxis: layoutAxis,
                                       reduceMotion: reduceMotion, isEnabled: isEnabled)
        guard inputs != environmentInputs else { return }
        environmentInputs = inputs
        let semantic: UISemanticContentAttribute = layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        if self.layoutAxis != layoutAxis || semanticContentAttribute != semantic || !isEnabled {
            cancelTracking(animated: false)
        }
        // Never read an unset override. Apply traits before SwiftUI measures
        // the bar, including when it has not entered a window yet.
        traitOverrides.preferredContentSizeCategory = contentSizeCategory
        updateTraitsIfNeeded()
        semanticContentAttribute = semantic
        self.layoutAxis = layoutAxis
        let motionWasReduced = self.reduceMotion
        self.reduceMotion = reduceMotion
        if touchRecognizer.isEnabled != isEnabled { touchRecognizer.isEnabled = isEnabled }
        for button in buttons {
            button.layoutAxis = layoutAxis
            button.updateTitle(locale: locale)
            button.isEnabled = isEnabled
        }
        if reduceMotion && !motionWasReduced {
            stopMotion()
            if interaction.tracking != nil {
                showTracking()
            } else {
                showSelection(animated: false)
            }
        }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private struct EnvironmentInputs: Equatable {
        let locale: Locale
        let contentSizeCategory: UIContentSizeCategory
        let layoutDirection: UIUserInterfaceLayoutDirection
        let layoutAxis: NSLayoutConstraint.Axis
        let reduceMotion: Bool
        let isEnabled: Bool
    }

    func fittingSize(proposedWidth: CGFloat?) -> CGSize {
        let preferredWidth: CGFloat
        if layoutAxis == .vertical {
            preferredWidth = GlassTabBarMetrics.preferredVerticalWidth
        } else {
            // Equal-width items need room for the widest localized, scaled title.
            // The reference width is a preference; content may justify more.
            let itemWidth = buttons.map(\.preferredWidth).max() ?? GlassTabBarMetrics.minimumTapSize
            preferredWidth = max(GlassTabBarMetrics.preferredHorizontalWidth,
                                 itemWidth * CGFloat(buttons.count) + GlassTabBarMetrics.contentInset * 2)
        }
        // Zero probes the minimum, nil the ideal, and infinity the maximum.
        // This capsule's ideal and maximum both follow its content preference.
        // Never compress the controls below 44 points,
        // even if a parent proposes less than the menu's required minimum.
        let width = proposedWidth.flatMap { $0.isFinite ? min(preferredWidth, max(minimumContentWidth, $0)) : nil }
            ?? preferredWidth
        return CGSize(width: width, height: fittingHeight(for: width))
    }

    private var minimumContentWidth: CGFloat {
        layoutAxis == .vertical ? GlassTabBarMetrics.minimumTapSize : GlassTabBarMetrics.minimumHorizontalWidth
    }

    private func horizontalInset(for width: CGFloat) -> CGFloat {
        min(GlassTabBarMetrics.contentInset, max(0, (width - minimumContentWidth) / 2))
    }

    func fittingHeight(for width: CGFloat) -> CGFloat {
        if layoutAxis == .vertical {
            return CGFloat(buttons.count) * GlassTabBarMetrics.minimumTapSize + GlassTabBarMetrics.contentInset * 2
        }
        let itemWidth = max(0, width - horizontalInset(for: width) * 2) / CGFloat(buttons.count)
        let itemHeight = buttons.map { $0.sizeThatFits(CGSize(width: itemWidth, height: .greatestFiniteMagnitude)).height }.max() ?? 0
        return max(GlassTabBarMetrics.minimumHeight, itemHeight + GlassTabBarMetrics.contentInset * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.frame = bounds
        let content = bounds.insetBy(dx: horizontalInset(for: bounds.width), dy: GlassTabBarMetrics.contentInset)
        let isVertical = layoutAxis == .vertical
        let itemWidth = max(0, content.width) / (isVertical ? 1 : CGFloat(buttons.count))
        let itemHeight = max(0, content.height) / (isVertical ? CGFloat(buttons.count) : 1)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (index, button) in buttons.enumerated() {
            let visualIndex = !isVertical && isRightToLeft ? buttons.count - 1 - index : index
            button.frame = CGRect(
                x: content.minX + (isVertical ? 0 : CGFloat(visualIndex) * itemWidth),
                y: content.minY + (isVertical ? CGFloat(visualIndex) * itemHeight : 0),
                width: itemWidth,
                height: itemHeight
            )
        }
        let geometry = currentGeometry
        if lastGeometry != geometry {
            lastGeometry = geometry
            let wasTracking = interaction.tracking != nil
            interaction.validateGeometry(geometry)
            if wasTracking { resetRecognizerIfNeeded() }
            stopMotion()
            showSelection(animated: false)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelTracking(animated: false)
            stopMotion()
        }
    }

    func select(_ tab: RootTab, animated: Bool) {
        guard interaction.select(tab) else { return }
        resetRecognizerIfNeeded()
        layoutIfNeeded()
        showSelection(animated: animated)
    }

    private var currentGeometry: GlassTabBarInteraction.Geometry {
        .init(
            bounds: bounds,
            axis: layoutAxis,
            items: buttons.map { .init(tab: $0.tab, frame: $0.frame) },
            placement: presentation.placement(for: self)
        )
    }

    /// The finger against the capsule as drawn while pressed. The tabs grow
    /// with the capsule about its center, so a point left unscaled would pick
    /// the tab short of the finger near a boundary, further out toward either
    /// end. The pressed scale is fixed for the whole hold, so a still finger
    /// never changes tab while the capsule grows.
    private func trackingPoint(_ point: CGPoint) -> CGPoint? {
        guard let coordinateView = presentation.coordinateSpace(for: self) else { return nil }
        let unscaled = convert(point, to: coordinateView)
        let scale = pressedScale
        let center = CGPoint(x: coordinateView.bounds.midX, y: coordinateView.bounds.midY)
        return CGPoint(x: center.x + (unscaled.x - center.x) / scale.width,
                       y: center.y + (unscaled.y - center.y) / scale.height)
    }

    @objc private func trackTouch(_ recognizer: GlassTabBarTouchRecognizer) {
        switch recognizer.state {
        case .changed:
            guard validateTrackingGeometry(), let point = trackingPoint(recognizer.touchLocation) else { return }
            interaction.move(to: point)
            showTracking()
        case .ended:
            guard validateTrackingGeometry(), let point = trackingPoint(recognizer.touchLocation) else { return }
            interaction.move(to: point)
            // A valid release rebounds even on the current tab; cancellations
            // and outside releases must remain silent.
            let acceptedRelease = interaction.tracking?.candidate != nil
            let destination = interaction.release(at: point)
            showSelection(animated: true)
            if destination != nil {
                shimmerHighlight()
            } else {
                selectionView.stopShimmer()
            }
            if acceptedRelease { releaseFeedback.impactOccurred() }
            if let destination { onSelect?(destination) }
        case .cancelled, .failed:
            interaction.cancel()
            selectionView.stopShimmer()
            showSelection(animated: true)
        default:
            break
        }
    }

    private func validateTrackingGeometry() -> Bool {
        layoutIfNeeded()
        guard let tracking = interaction.tracking else { return false }
        // A toolbar can move without resizing this item. Do not let a finger
        // started in the old placement commit a destination in the new one.
        guard let coordinateView = presentation.coordinateSpace(for: self),
              coordinateView === trackingCoordinateView,
              tracking.geometry == currentGeometry else {
            cancelTracking(animated: false)
            return false
        }
        return true
    }

    @objc private func selectButton(_ button: GlassTabBarButton) {
        guard button.isEnabled else { return }
        let changed = interaction.select(button.tab)
        // Direct accessibility/keyboard activation uses the same single commit.
        interaction.cancel()
        resetRecognizerIfNeeded()
        showSelection(animated: true)
        if changed {
            shimmerHighlight()
        } else {
            selectionView.stopShimmer()
        }
        releaseFeedback.impactOccurred()
        if changed { onSelect?(button.tab) }
    }

    private func cancelTracking(animated: Bool) {
        guard interaction.tracking != nil else { return }
        interaction.cancel()
        selectionView.stopShimmer()
        resetRecognizerIfNeeded()
        showSelection(animated: animated)
    }

    private func resetRecognizerIfNeeded() {
        guard interaction.tracking == nil,
              touchRecognizer.state == .began || touchRecognizer.state == .changed else { return }
        touchRecognizer.isEnabled = false
        touchRecognizer.isEnabled = true
    }

    private func showTracking() {
        guard let tracking = interaction.tracking else { return }
        if tracking.candidate == nil || tracking.candidate == interaction.selection {
            selectionView.stopShimmer()
        }
        for button in buttons {
            button.updateTrackingCandidate(button.tab == tracking.candidate)
        }
        // The highlight covers a whole tab: the one under the finger, or,
        // while the finger is off the bar, the one a release there keeps.
        let tab = tracking.candidate ?? interaction.selection
        guard let item = tracking.geometry.items.first(where: { $0.tab == tab }) else { return }
        let canAnimate = !reduceMotion && window != nil
        presentation.track(scale: pressedScale, animated: canAnimate)
        moveHighlight(to: item.frame, color: tracking.candidate == nil ? .tertiarySystemFill : .secondarySystemFill,
                      animated: canAnimate)
    }

    private func showSelection(animated: Bool) {
        for button in buttons {
            button.isSelected = button.tab == interaction.selection
            button.updateTrackingCandidate(nil)
        }
        guard let selectedButton = buttons.first(where: { $0.tab == interaction.selection }) else { return }
        let canAnimate = animated && !reduceMotion && window != nil
        if !canAnimate { stopMotion() }
        moveHighlight(to: selectedButton.frame, color: .tertiarySystemFill, animated: canAnimate)
        if canAnimate { presentation.release(animated: true) }
    }

    /// Slides the highlight onto a whole tab. Only a new tab starts a spring:
    /// restarting one on every touch sample would keep it from ever settling.
    private func moveHighlight(to frame: CGRect, color: UIColor, animated: Bool) {
        guard frame != selectionView.frame else {
            selectionView.backgroundColor = color
            return
        }
        if !selectionView.frame.isEmpty {
            // Follow the previous tab, even when its slide has not finished.
            // A presentation frame can still be at the next destination (or
            // overshoot it), incorrectly keeping or reversing the old direction.
            let origin = selectionView.frame
            let delta = layoutAxis == .vertical ? frame.midY - origin.midY : frame.midX - origin.midX
            if abs(delta) > 0.5 { shimmerDirection = delta > 0 ? 1 : -1 }
        }
        let update = {
            self.selectionView.frame = frame
            self.selectionView.backgroundColor = color
        }
        // The first placement has nothing to slide from.
        guard animated, let spring = presentation.motion.highlightSpring, !selectionView.frame.isEmpty else {
            UIView.performWithoutAnimation(update)
            return
        }
        UIView.animate(springDuration: spring.duration, bounce: spring.bounce, initialSpringVelocity: 0, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction], animations: update)
    }

    private func shimmerHighlight() {
        guard !reduceMotion, window != nil else { return }
        // The release keeps the press's direction even after the capsule arrives.
        selectionView.playShimmer(axis: layoutAxis, direction: shimmerDirection)
    }

    private var pressedScale: CGSize {
        guard !reduceMotion, let window, bounds.width > 0, bounds.height > 0,
              let coordinateView = presentation.coordinateSpace(for: self) else {
            return CGSize(width: 1, height: 1)
        }
        let frame = coordinateView.convert(coordinateView.bounds, to: window)
        let available = window.safeAreaLayoutGuide.layoutFrame
        let horizontalRoom = max(0, min(frame.minX - available.minX, available.maxX - frame.maxX))
        let verticalRoom = max(0, min(frame.minY - available.minY, available.maxY - frame.maxY))
        let grow = presentation.motion.pressedScale
        let scaleX = layoutAxis == .vertical ? 1 : min(grow, 1 + 2 * horizontalRoom / bounds.width)
        let scaleY = min(grow, 1 + 2 * verticalRoom / bounds.height)
        return CGSize(width: scaleX, height: scaleY)
    }

    private func stopMotion() {
        selectionView.stopShimmer()
        selectionView.layer.removeAllAnimations()
        presentation.resetAfterLayout()
    }
}
