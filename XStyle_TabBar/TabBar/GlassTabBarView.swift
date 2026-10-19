import UIKit

/// One persistent native glass platter. Navigation commits on release; the
/// finger's candidate and native material remain separate from page state.
final class GlassTabBarView: UIView {
    var onSelect: ((RootTab) -> Void)?

    private let containerView = UIVisualEffectView(effect: UIGlassContainerEffect())
    private let glassView = UIVisualEffectView()
    private let selectionView = UIView()
    private let buttons = RootTab.allCases.map { GlassTabBarButton(tab: $0) }
    private let touchRecognizer = GlassTabBarTouchRecognizer()
    private var interaction: GlassTabBarInteraction
    private var reduceMotion = false
    private var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    private var lastGeometry: GlassTabBarInteraction.Geometry?
    private var materialIsDark: Bool?
    private var environmentInputs: EnvironmentInputs?
    private var motionGeneration = 0

    init(selection: RootTab) {
        interaction = GlassTabBarInteraction(selection: selection)
        super.init(frame: .zero)
        isOpaque = false
        isAccessibilityElement = false
        accessibilityTraits = .tabBar
        accessibilityElements = buttons

        glassView.cornerConfiguration = .capsule()
        addSubview(containerView)
        containerView.contentView.addSubview(glassView)
        selectionView.backgroundColor = .tertiarySystemFill
        selectionView.cornerConfiguration = .capsule()
        selectionView.isUserInteractionEnabled = false
        glassView.contentView.addSubview(selectionView)
        for button in buttons {
            glassView.contentView.addSubview(button)
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
            self.interaction.begin(at: point, geometry: self.currentGeometry)
            self.showTracking(previousPosition: nil)
        }
        touchRecognizer.addTarget(self, action: #selector(trackTouch(_:)))
        touchRecognizer.delaysTouchesBegan = true
        touchRecognizer.cancelsTouchesInView = true
        addGestureRecognizer(touchRecognizer)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: GlassTabBarView, _) in
            view.updateMaterial()
        }
        updateMaterial()
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
        // Frame is undefined while transformed. Bounds and center keep the
        // toolbar's layout independent of the temporary press deformation.
        containerView.bounds = bounds
        containerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        glassView.frame = containerView.bounds
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
        .init(
            bounds: bounds,
            axis: layoutAxis,
            items: buttons.map { .init(tab: $0.tab, frame: $0.frame) },
            frameInWindow: window.map { convert(bounds, to: $0) }
        )
    }

    private func updateMaterial() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        guard materialIsDark != isDark else { return }
        materialIsDark = isDark
        let glass = UIGlassEffect(style: .regular)
        // The shared tracker supplies the whole-capsule press/release response.
        glass.isInteractive = false
        glass.tintColor = isDark ? UIColor.black.withAlphaComponent(0.25) : nil
        glassView.effect = glass
    }

    @objc private func trackTouch(_ recognizer: GlassTabBarTouchRecognizer) {
        switch recognizer.state {
        case .changed:
            guard validateTrackingGeometry() else { return }
            let previousPosition = interaction.tracking?.position
            interaction.move(to: recognizer.touchLocation)
            showTracking(previousPosition: previousPosition)
        case .ended:
            guard validateTrackingGeometry() else { return }
            let destination = interaction.release(at: recognizer.touchLocation)
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
        guard tracking.geometry == currentGeometry else {
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
        let update = {
            self.selectionView.frame = target
            self.selectionView.backgroundColor = tracking.candidate == nil ? .tertiarySystemFill : .secondarySystemFill
            self.containerView.transform = self.pressedTransform
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
            self.containerView.transform = .identity
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
        UIView.animate(
            withDuration: GlassTabBarMetrics.releaseDuration,
            delay: 0,
            usingSpringWithDamping: 0.45,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: { self.containerView.transform = .identity }
        )
    }

    private var pressedTransform: CGAffineTransform {
        guard !reduceMotion, let window, bounds.width > 0, bounds.height > 0 else { return .identity }
        let frame = convert(bounds, to: window)
        let available = window.safeAreaLayoutGuide.layoutFrame
        let horizontalRoom = max(0, min(frame.minX - available.minX, available.maxX - frame.maxX))
        let verticalRoom = max(0, min(frame.minY - available.minY, available.maxY - frame.maxY))
        let scaleX = layoutAxis == .vertical ? 1 : min(GlassTabBarMetrics.pressedScale, 1 + 2 * horizontalRoom / bounds.width)
        let scaleY = min(GlassTabBarMetrics.pressedScale, 1 + 2 * verticalRoom / bounds.height)
        return CGAffineTransform(scaleX: scaleX, y: scaleY)
    }

    private func stopMotion() {
        motionGeneration += 1
        selectionView.layer.removeAllAnimations()
        containerView.layer.removeAllAnimations()
        containerView.transform = .identity
    }
}
