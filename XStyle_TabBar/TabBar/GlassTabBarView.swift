import UIKit

/// Persistent controls and touch tracking. The enclosing SwiftUI view supplies
/// the glass and scales the visual subtree without changing touch coordinates.
final class GlassTabBarView: UIView {
    var onSelect: ((RootTab) -> Void)?

    private let containerView = UIView()
    private let presentation: GlassTabBarPresentation
    private let selectionView = UIView()
    private let buttons = RootTab.allCases.map { GlassTabBarButton(tab: $0) }
    private let touchRecognizer = GlassTabBarTouchRecognizer()
    private var interaction: GlassTabBarInteraction
    private var reduceMotion = false
    private var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    private var lastGeometry: GlassTabBarInteraction.Geometry?
    private var environmentInputs: EnvironmentInputs?
    private var motionGeneration = 0
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
        selectionView.backgroundColor = .tertiarySystemFill
        selectionView.cornerConfiguration = .capsule()
        selectionView.isUserInteractionEnabled = false
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
            self.showTracking(previousPosition: nil)
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
                showTracking(previousPosition: nil)
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

    func fittingHeight(for width: CGFloat) -> CGFloat {
        if layoutAxis == .vertical {
            return CGFloat(buttons.count) * GlassTabBarMetrics.minimumTapSize + GlassTabBarMetrics.contentInset * 2
        }
        let itemWidth = max(0, width - GlassTabBarMetrics.contentInset * 2) / CGFloat(buttons.count)
        let itemHeight = buttons.map { $0.sizeThatFits(CGSize(width: itemWidth, height: .greatestFiniteMagnitude)).height }.max() ?? 0
        return max(GlassTabBarMetrics.minimumHeight, itemHeight + GlassTabBarMetrics.contentInset * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        containerView.frame = bounds
        let content = bounds.insetBy(dx: GlassTabBarMetrics.contentInset, dy: GlassTabBarMetrics.contentInset)
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
        let coordinateView = presentation.coordinateSpace(for: self)
        return .init(
            bounds: bounds,
            axis: layoutAxis,
            items: buttons.map { .init(tab: $0.tab, frame: $0.frame) },
            frameInWindow: coordinateView.flatMap { anchor in
                window.map { anchor.convert(anchor.bounds, to: $0) }
            }
        )
    }

    private func trackingPoint(_ point: CGPoint) -> CGPoint? {
        guard let coordinateView = presentation.coordinateSpace(for: self) else { return nil }
        return convert(point, to: coordinateView)
    }

    @objc private func trackTouch(_ recognizer: GlassTabBarTouchRecognizer) {
        switch recognizer.state {
        case .changed:
            guard validateTrackingGeometry(), let point = trackingPoint(recognizer.touchLocation) else { return }
            let previousPosition = interaction.tracking?.position
            interaction.move(to: point)
            showTracking(previousPosition: previousPosition)
        case .ended:
            guard validateTrackingGeometry(), let point = trackingPoint(recognizer.touchLocation) else { return }
            let destination = interaction.release(at: point)
            showSelection(animated: true)
            if let destination { onSelect?(destination) }
        case .cancelled, .failed:
            interaction.cancel()
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
        if changed { onSelect?(button.tab) }
    }

    private func cancelTracking(animated: Bool) {
        guard interaction.tracking != nil else { return }
        interaction.cancel()
        resetRecognizerIfNeeded()
        showSelection(animated: animated)
    }

    private func resetRecognizerIfNeeded() {
        guard interaction.tracking == nil,
              touchRecognizer.state == .began || touchRecognizer.state == .changed else { return }
        touchRecognizer.isEnabled = false
        touchRecognizer.isEnabled = true
    }

    private func showTracking(previousPosition: CGFloat?) {
        guard let tracking = interaction.tracking,
              let item = tracking.geometry.items.first else { return }
        motionGeneration += 1
        let generation = motionGeneration
        for button in buttons {
            button.updateTrackingCandidate(button.tab == tracking.candidate)
        }
        var target = item.frame
        if layoutAxis == .vertical { target.origin.y = tracking.position - target.height / 2 }
        else { target.origin.x = tracking.position - target.width / 2 }
        let restingTarget = target
        if !reduceMotion, let previousPosition {
            let stretch = min(abs(tracking.position - previousPosition) * 0.15, 5)
            if layoutAxis == .vertical { target = target.insetBy(dx: 0, dy: -stretch / 2) }
            else { target = target.insetBy(dx: -stretch / 2, dy: 0) }
            target = target.intersection(bounds.insetBy(dx: 3, dy: 3))
        }
        let canAnimate = !reduceMotion && window != nil
        presentation.track(scale: pressedScale, animated: canAnimate)
        let update = {
            self.selectionView.frame = target
            self.selectionView.backgroundColor = tracking.candidate == nil ? .tertiarySystemFill : .secondarySystemFill
        }
        guard canAnimate else {
            UIView.performWithoutAnimation(update)
            return
        }
        UIView.animate(
            withDuration: GlassTabBarMetrics.trackingDuration,
            delay: 0,
            usingSpringWithDamping: 0.82,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: update
        ) { [weak self] _ in
            guard let self, self.motionGeneration == generation, self.interaction.tracking != nil else { return }
            UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.selectionView.frame = restingTarget
            }
        }
    }

    private func showSelection(animated: Bool) {
        motionGeneration += 1
        for button in buttons {
            button.isSelected = button.tab == interaction.selection
            button.updateTrackingCandidate(nil)
        }
        guard let selectedButton = buttons.first(where: { $0.tab == interaction.selection }) else { return }
        let update = {
            self.selectionView.frame = selectedButton.frame
            self.selectionView.backgroundColor = .tertiarySystemFill
        }
        guard animated, !reduceMotion, window != nil, !selectionView.frame.isEmpty else {
            stopMotion()
            UIView.performWithoutAnimation(update)
            return
        }
        // A slightly underdamped return supplies the reference's soft release
        // ripple without adding another glass surface or a circular overlay.
        UIView.animate(
            withDuration: GlassTabBarMetrics.selectionDuration,
            delay: 0,
            usingSpringWithDamping: 0.88,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                self.selectionView.frame = selectedButton.frame
                self.selectionView.backgroundColor = .tertiarySystemFill
            }
        )
        presentation.release(animated: true)
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
        let scaleX = layoutAxis == .vertical ? 1 : min(GlassTabBarMetrics.pressedScale, 1 + 2 * horizontalRoom / bounds.width)
        let scaleY = min(GlassTabBarMetrics.pressedScale, 1 + 2 * verticalRoom / bounds.height)
        return CGSize(width: scaleX, height: scaleY)
    }

    private func stopMotion() {
        motionGeneration += 1
        selectionView.layer.removeAllAnimations()
        presentation.resetAfterLayout()
    }
}
