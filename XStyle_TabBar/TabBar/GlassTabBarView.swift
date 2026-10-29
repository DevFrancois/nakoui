import UIKit

/// One native glass capsule owns press feedback for the whole menu. The single
/// selection fill and its release shimmer travel with the native content.
final class GlassTabBarView: UIView, UIGestureRecognizerDelegate {
    var onSelect: ((RootTab) -> Void)?
    /// A release or tap on the tab that already shows, such as to take it
    /// back to its main view.
    var onReselect: ((RootTab) -> Void)?
    /// Opens on holding a tab that offers one; nil leaves holds to preview.
    weak var quickSwitch: TabQuickSwitchMenu? {
        willSet {
            if quickSwitch !== newValue { abandonQuickSwitch() }
        }
    }

    private let containerView = UIView()
    private let glassView = GlassTabBarNativeGlassView()
    private let backingView = UIView()
    private let dimmingView = UIView()
    private let reflectionLayer = GlassTabBarReflectionLayer()
    private weak var reflectionSourceView: UIView?
    private var reflectionUpdateLink: UIUpdateLink?
    private var glassConfiguration: GlassConfiguration?
    private let presentation: GlassTabBarPresentation
    private let selectionView = GlassTabBarHighlight()
    private let buttons = RootTab.allCases.map { GlassTabBarButton(tab: $0) }
    private let touchRecognizer = GlassTabBarTouchRecognizer()
    private lazy var releaseFeedback = UIImpactFeedbackGenerator(style: .light, view: self)
    private lazy var holdFeedback = UIImpactFeedbackGenerator(style: .medium, view: self)
    private lazy var menuFeedback = UISelectionFeedbackGenerator(view: self)
    /// When the finger's hold may open its tab's menu; see `openQuickSwitch`.
    private(set) var quickSwitchHold = TabQuickSwitchHold()
    /// Wakes when the hold has lasted.
    private var holdTask: Task<Void, Never>?
    /// The window as the finger came down. A hold or menu outlives no resize,
    /// rotation or safe-area change.
    private var quickSwitchWindow: QuickSwitchWindow?
    /// Whether holds may open menus: the bar shows, and the app is active.
    private var isQuickSwitchAvailable = true
    private var quickSwitchPreferences: QuickSwitchPreferences?
    private var interaction: GlassTabBarInteraction
    private var reduceMotion = false
    private var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    private var lastGeometry: GlassTabBarInteraction.Geometry?
    private var environmentInputs: EnvironmentInputs?
    private weak var trackingCoordinateView: UIView?
    private var restingSelectionColor = UIColor.tertiarySystemFill
    private var trackingSelectionColor = UIColor.secondarySystemFill

    func setReflectionSource(_ view: UIView?) {
        reflectionSourceView = view
        updateReflectionSource()
    }

    func updateReflection(_ configuration: GlassTabBarReflectionConfiguration) {
        reflectionLayer.updateConfiguration(configuration)
        updateReflectionSource()
    }

    private func updateReflectionSource(usePresentation: Bool = false) {
        guard let source = reflectionSourceView, let window,
              source.window === window, !isDescendant(of: source), !source.isDescendant(of: self) else {
            reflectionLayer.setSourceLayer(nil)
            return
        }
        let sourceLayer: CALayer
        let targetLayer: CALayer
        if usePresentation, let sourcePresentation = source.layer.presentation(),
           let targetPresentation = glassView.contentView.layer.presentation() {
            sourceLayer = sourcePresentation
            targetLayer = targetPresentation
        } else {
            sourceLayer = source.layer
            targetLayer = glassView.contentView.layer
        }
        let origin = sourceLayer.bounds.origin
        let geometry = GlassTabBarReflectionGeometry(
            sourceBounds: sourceLayer.bounds, viewportBounds: bounds,
            sourceOrigin: targetLayer.convert(origin, from: sourceLayer),
            sourceXAxis: targetLayer.convert(CGPoint(x: origin.x + 1, y: origin.y), from: sourceLayer),
            sourceYAxis: targetLayer.convert(CGPoint(x: origin.x, y: origin.y + 1), from: sourceLayer),
            axis: layoutAxis
        )
        reflectionLayer.setSourceLayer(source.layer, geometry: geometry)
    }

    func updateGlass(_ appearance: GlassTabBarAppearance, interactive: Bool) {
        let configuration = GlassConfiguration(material: appearance.material,
                                               tint: appearance.tintEnabled ? appearance.tintColor : nil,
                                               tintOpacity: appearance.tintOpacity,
                                               interactive: interactive && !reduceMotion && (environmentInputs?.isEnabled ?? true))
        if glassConfiguration != configuration {
            glassConfiguration = configuration
            glassView.effect = makeGlassEffect(configuration)
        }
        let backing = appearance.backingEnabled
            ? appearance.backingColor.uiColor(opacity: appearance.backingOpacity) : UIColor.clear
        backingView.backgroundColor = appearance.backingInsideGlass ? .clear : backing
        dimmingView.backgroundColor = appearance.backingInsideGlass ? backing : .clear
        glassView.suppressInteractionGlow()
    }

    private struct GlassConfiguration: Equatable {
        let material: GlassTabBarAppearance.Material
        let tint: GlassTabBarAppearance.RGB?
        let tintOpacity: Double
        let interactive: Bool
    }

    private func makeGlassEffect(_ configuration: GlassConfiguration) -> UIGlassEffect {
        let effect = UIGlassEffect(style: configuration.material == .clear ? .clear : .regular)
        effect.tintColor = configuration.tint?.uiColor(opacity: configuration.tintOpacity)
        effect.isInteractive = configuration.interactive
        return effect
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Let the native surface respond to the same hold; the tab tracker
        // remains responsible for preview and the one navigation on release.
        otherGestureRecognizer.view?.isDescendant(of: glassView) == true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled,
              touchRecognizer.isEnabled, self.point(inside: point, with: event) else { return nil }
        // One native touch owner survives tab changes and a drag off the rail.
        // The root recognizer still owns thresholding and the release commit.
        glassView.suppressInteractionGlow()
        return glassView.contentView
    }

    func updateAppearance(_ appearance: GlassTabBarAppearance, defaults: GlassTabBarAppearance) {
        let selected = appearance.selectedIconColor == defaults.selectedIconColor
            ? nil : appearance.selectedIconColor.uiColor()
        let inactive = appearance.inactiveIconColor == defaults.inactiveIconColor
            && appearance.inactiveIconOpacity == defaults.inactiveIconOpacity
            ? nil : appearance.inactiveIconColor.uiColor(opacity: appearance.inactiveIconOpacity)
        for button in buttons { button.updateForeground(selected: selected, inactive: inactive) }
        let style: UIUserInterfaceStyle = defaults == .dark ? .dark : .light
        overrideUserInterfaceStyle = style
        let systemSelection = GlassTabBarAppearance.RGB(.tertiarySystemFill, style: style)
        let traits = UITraitCollection(userInterfaceStyle: style)
        restingSelectionColor = appearance.selectionColor == systemSelection
            && appearance.selectionOpacity == UIColor.tertiarySystemFill.resolvedColor(with: traits).cgColor.alpha
            ? .tertiarySystemFill : appearance.selectionColor.uiColor(opacity: appearance.selectionOpacity)
        trackingSelectionColor = appearance.selectionColor == systemSelection
            && appearance.trackingSelectionOpacity == UIColor.secondarySystemFill.resolvedColor(with: traits).cgColor.alpha
            ? .secondarySystemFill : appearance.selectionColor.uiColor(opacity: appearance.trackingSelectionOpacity)
        // Appearance edits never reset geometry, a preview, or a pending release.
        selectionView.backgroundColor = interaction.tracking?.candidate == nil
            ? restingSelectionColor : trackingSelectionColor
    }

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

        backingView.cornerConfiguration = .capsule()
        backingView.isUserInteractionEnabled = false
        backingView.accessibilityElementsHidden = true
        glassView.cornerConfiguration = .capsule()
        dimmingView.cornerConfiguration = .capsule()
        dimmingView.layer.name = "tabBar.materialBacking"
        dimmingView.isUserInteractionEnabled = false
        dimmingView.accessibilityElementsHidden = true
        addSubview(backingView)
        addSubview(glassView)
        glassView.contentView.addSubview(dimmingView)
        glassView.contentView.layer.addSublayer(reflectionLayer)
        glassView.contentView.addSubview(containerView)
        containerView.addSubview(selectionView)
        for button in buttons {
            containerView.addSubview(button)
            button.isSelected = button.tab == selection
            button.addTarget(self, action: #selector(selectButton(_:)), for: .touchUpInside)
            button.onSizeChange = { [weak self] in
                self?.invalidateIntrinsicContentSize()
                self?.setNeedsLayout()
            }
            button.quickSwitchActions = { [weak self, tab = button.tab] in
                self?.quickSwitchActions(for: tab) ?? []
            }
        }
        touchRecognizer.onBegin = { [weak self] point in
            guard let self else { return }
            self.layoutIfNeeded()
            guard let point = self.trackingPoint(point) else { return }
            self.trackingCoordinateView = self.presentation.coordinateSpace(for: self)
            self.closeQuickSwitch()
            self.interaction.begin(at: point, geometry: self.currentGeometry)
            if self.interaction.tracking != nil {
                self.releaseFeedback.prepare()
                self.scheduleQuickSwitch()
            }
            self.showTracking()
        }
        touchRecognizer.addTarget(self, action: #selector(trackTouch(_:)))
        touchRecognizer.delaysTouchesBegan = false
        touchRecognizer.cancelsTouchesInView = false
        touchRecognizer.delegate = self
        addGestureRecognizer(touchRecognizer)

        // Fold/toolbar placement and native press transforms may change without
        // relaying out this view. Observe actual UI updates; don't drive an idle
        // display loop or alter the native interaction's transforms.
        let updateLink = UIUpdateLink(view: self)
        updateLink.addAction(to: .beforeCATransactionCommit) { [weak self] _, _ in
            self?.updateReflectionSource(usePresentation: true)
            // A rotation may move nothing under a still finger, so its touch
            // never reports it. Cancel after this commit, not during it.
            if self?.isQuickSwitchWindowCurrent == false {
                DispatchQueue.main.async { [weak self] in
                    // A new touch may have begun since this invalidation was
                    // queued; an old session must never cancel its successor.
                    guard let self, !self.isQuickSwitchWindowCurrent else { return }
                    self.abandonQuickSwitch()
                }
            }
        }
        reflectionUpdateLink = updateLink
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
        // A menu laid out for other text, language or motion settings would
        // move under the finger.
        if environmentInputs != nil { abandonQuickSwitch() }
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
            button.reduceMotion = reduceMotion
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
        let preferredInset = layoutAxis == .vertical
            ? GlassTabBarMetrics.verticalHorizontalInset : GlassTabBarMetrics.contentInset
        return min(preferredInset, max(0, (width - minimumContentWidth) / 2))
    }

    func fittingHeight(for width: CGFloat) -> CGFloat {
        if layoutAxis == .vertical {
            return CGFloat(buttons.count) * GlassTabBarMetrics.verticalItemHeight + GlassTabBarMetrics.contentInset * 2
        }
        let itemWidth = max(0, width - horizontalInset(for: width) * 2) / CGFloat(buttons.count)
        let itemHeight = buttons.map { $0.sizeThatFits(CGSize(width: itemWidth, height: .greatestFiniteMagnitude)).height }.max() ?? 0
        return max(GlassTabBarMetrics.minimumHeight, itemHeight + GlassTabBarMetrics.contentInset * 2)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backingView.frame = bounds
        glassView.bounds = bounds
        glassView.center = CGPoint(x: bounds.midX, y: bounds.midY)
        glassView.layoutIfNeeded()
        dimmingView.frame = glassView.contentView.bounds
        reflectionLayer.updateLayout(bounds: bounds, axis: layoutAxis, scale: traitCollection.displayScale)
        updateReflectionSource()
        containerView.bounds = bounds
        containerView.center = CGPoint(x: bounds.midX, y: bounds.midY)
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
        if let scan = buttons.first(where: { $0.tab == .scanner }), bounds.width > 0, bounds.height > 0 {
            // From centres and bounds, which a pressed button's transform leaves alone.
            scan.layoutIfNeeded()
            let symbol = scan.symbolCenter
            let center = CGPoint(x: scan.center.x - scan.bounds.midX + symbol.x, y: scan.center.y - scan.bounds.midY + symbol.y)
            presentation.setScanSymbol(x: center.x / bounds.width, y: center.y / bounds.height)
        }
        let geometry = currentGeometry
        if lastGeometry != geometry {
            lastGeometry = geometry
            let wasTracking = interaction.tracking != nil
            interaction.validateGeometry(geometry)
            if wasTracking {
                if interaction.tracking == nil { closeQuickSwitch() }
                resetRecognizerIfNeeded()
            }
            stopMotion()
            showSelection(animated: false)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        reflectionUpdateLink?.isEnabled = window != nil
        updateReflectionSource()
        if window == nil {
            cancelTracking(animated: false)
            closeQuickSwitch()
            stopMotion()
        }
    }

    func select(_ tab: RootTab, animated: Bool) {
        guard interaction.select(tab) else { return }
        closeQuickSwitch()
        resetRecognizerIfNeeded()
        layoutIfNeeded()
        showSelection(animated: animated)
    }

    private var currentGeometry: GlassTabBarInteraction.Geometry {
        .init(
            bounds: containerView.bounds,
            axis: layoutAxis,
            items: buttons.map { .init(tab: $0.tab, frame: $0.frame) },
            placement: presentation.placement(for: self),
            menuOpensRight: layoutAxis != .vertical ||
                (window.map { convert(CGPoint(x: bounds.midX, y: bounds.midY), to: $0).x < $0.bounds.midX } ?? true)
        )
    }

    /// Native glass can deform its child controls independently of this root.
    private func trackingPoint(_ point: CGPoint) -> CGPoint? {
        guard presentation.coordinateSpace(for: self) != nil else { return nil }
        return containerView.convert(point, from: self)
    }

    @objc private func trackTouch(_ recognizer: GlassTabBarTouchRecognizer) {
        trackTouch(state: recognizer.state, at: recognizer.touchLocation)
    }

    func trackTouch(state: UIGestureRecognizer.State, at location: CGPoint) {
        switch state {
        case .changed:
            guard validateTrackingGeometry(), let point = trackingPoint(location) else { return }
            moveTracking(to: point, windowPoint: convert(location, to: nil))
        case .ended:
            guard validateTrackingGeometry(), let point = trackingPoint(location) else { return }
            cancelHold()
            quickSwitchWindow = nil
            if interaction.tracking?.isQuickSwitchActive == true {
                if interaction.tab(at: point) != nil {
                    // A physical bar release selects/reselects that root, even
                    // when its submenu is expanded or has no choices.
                    quickSwitch?.cancel()
                } else {
                    let item = quickSwitch?.release(at: convert(location, to: nil))
                    interaction.cancel()
                    if let item {
                        commitQuickSwitch(item)
                    } else {
                        selectionView.stopShimmer()
                        showSelection(animated: true)
                    }
                    return
                }
            }
            interaction.move(to: point)
            // The bar owns the finger until release, even outside its bounds.
            // A valid release rebounds even on the current tab.
            let acceptedRelease = interaction.tracking?.candidate != nil
            let previousSelection = interaction.selection
            let destination = interaction.release(at: point)
            showSelection(animated: true)
            if let destination {
                shimmerHighlight(from: previousSelection, to: destination)
            } else {
                selectionView.stopShimmer()
            }
            if acceptedRelease { releaseFeedback.impactOccurred() }
            if let destination {
                onSelect?(destination)
            } else if acceptedRelease {
                onReselect?(previousSelection)
            }
        case .cancelled, .failed:
            interaction.cancel()
            closeQuickSwitch()
            selectionView.stopShimmer()
            showSelection(animated: true)
        default:
            break
        }
    }

    private func moveTracking(to point: CGPoint, windowPoint: CGPoint) {
        let movement = interaction.move(to: point, allowableMovement: presentation.motion.quickSwitchAllowableMovement)
        switch movement {
        case .restartHold:
            scheduleQuickSwitch()
        case .cancelHold:
            cancelHold()
            quickSwitchWindow = nil
        case .openMenu(let tab):
            presentQuickSwitch(for: tab)
        case .collapseMenu:
            quickSwitch?.collapse()
        case .none:
            break
        }
        if interaction.tracking?.isQuickSwitchActive == true {
            quickSwitch?.move(to: windowPoint)
        }
        showTracking()
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
        guard isQuickSwitchWindowCurrent else {
            abandonQuickSwitch()
            return interaction.tracking != nil
        }
        return true
    }

    @objc private func selectButton(_ button: GlassTabBarButton) {
        guard button.isEnabled else { return }
        let previousSelection = interaction.selection
        let changed = interaction.select(button.tab)
        // Direct accessibility/keyboard activation uses the same single commit.
        interaction.cancel()
        closeQuickSwitch()
        resetRecognizerIfNeeded()
        showSelection(animated: true)
        if changed {
            shimmerHighlight(from: previousSelection, to: button.tab)
        } else {
            selectionView.stopShimmer()
        }
        releaseFeedback.impactOccurred()
        if changed {
            onSelect?(button.tab)
        } else {
            onReselect?(button.tab)
        }
    }

    /// Holds may open menus only while the bar shows and the app is active.
    /// Losing either ends a hold, and an open menu with its touch.
    func updateQuickSwitchAvailability(_ isAvailable: Bool) {
        guard isQuickSwitchAvailable != isAvailable else { return }
        isQuickSwitchAvailable = isAvailable
        if !isAvailable { abandonQuickSwitch() }
    }

    func updateQuickSwitchPreferences(layout: TabQuickSwitchLayout, holdDuration: TimeInterval,
                                      spotlightDuration: TimeInterval,
                                      listAnimations: TabQuickSwitchListAnimationSettings = .defaults) {
        let preferences = QuickSwitchPreferences(layout: layout, holdDuration: holdDuration,
                                                spotlightDuration: spotlightDuration, listAnimations: listAnimations)
        guard preferences != quickSwitchPreferences else { return }
        if quickSwitchPreferences != nil { abandonQuickSwitch() }
        quickSwitchPreferences = preferences
    }

    private struct QuickSwitchPreferences: Equatable {
        let layout: TabQuickSwitchLayout
        let holdDuration: TimeInterval
        let spotlightDuration: TimeInterval
        let listAnimations: TabQuickSwitchListAnimationSettings
    }

    /// A fresh dwell starts after crossing tabs or leaving the movement radius.
    private func scheduleQuickSwitch() {
        cancelHold()
        quickSwitchWindow = nil
        guard let quickSwitch, isQuickSwitchAvailable, let window,
              let tab = interaction.canOpenMenu(allowableMovement: presentation.motion.quickSwitchAllowableMovement),
              quickSwitch.items(for: tab, selectedTab: interaction.selection) != nil else { return }
        holdFeedback.prepare()
        quickSwitchWindow = QuickSwitchWindow(window)
        let duration = presentation.motion.quickSwitchHoldDuration
        let generation = quickSwitchHold.begin(at: ProcessInfo.processInfo.systemUptime, duration: duration)
        startHoldTimer(generation: generation, after: duration)
    }

    private func startHoldTimer(generation: UInt64, after delay: TimeInterval) {
        holdTask?.cancel()
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.openQuickSwitch(generation: generation, at: ProcessInfo.processInfo.systemUptime)
        }
    }

    /// Opens the held tab's menu once the hold of `generation` has lasted.
    /// Takes the time, so tests can open it without waiting.
    func openQuickSwitch(generation: UInt64, at time: TimeInterval) {
        if let pending = quickSwitchHold.pending, pending.generation == generation, time < pending.deadline {
            // Woken early: wait out the rest.
            startHoldTimer(generation: generation, after: pending.deadline - time)
            return
        }
        guard quickSwitchHold.fire(generation: generation, at: time) else { return }
        holdTask?.cancel()
        holdTask = nil
        let allowableMovement = presentation.motion.quickSwitchAllowableMovement
        guard let quickSwitch, isQuickSwitchAvailable, quickSwitch.canOpen,
              let window, quickSwitchWindow == QuickSwitchWindow(window), validateTrackingGeometry(),
              let tab = interaction.canOpenMenu(allowableMovement: allowableMovement),
              quickSwitch.items(for: tab, selectedTab: interaction.selection) != nil else { return }
        interaction.openMenu(allowableMovement: allowableMovement)
        presentQuickSwitch(for: tab)
        if let point = interaction.tracking?.point {
            quickSwitch.move(to: containerView.convert(point, to: nil))
        }
        holdFeedback.impactOccurred()
        menuFeedback.prepare()
    }

    /// Replaces just the choices. The existing session owns the spotlight and
    /// pointer until the touch ends, including on tabs with no submenu.
    private func presentQuickSwitch(for tab: RootTab) {
        guard let quickSwitch, let coordinateView = trackingCoordinateView,
              let button = buttons.first(where: { $0.tab == tab }) else { return }
        guard let items = quickSwitch.items(for: tab, selectedTab: interaction.selection) else {
            interaction.collapseMenu()
            quickSwitch.collapse()
            return
        }
        quickSwitch.open(tab: tab, items: items, tabFrame: coordinateView.convert(button.frame, to: nil),
                         barFrame: coordinateView.convert(coordinateView.bounds, to: nil), axis: layoutAxis)
        quickSwitch.onReachItem = { [weak self] in
            self?.menuFeedback.selectionChanged()
            self?.menuFeedback.prepare()
        }
    }

    /// Takes the item's tab to it, then switches to that tab, as a release
    /// on the tab would.
    private func commitQuickSwitch(_ item: TabQuickSwitchItem) {
        let previousSelection = interaction.selection
        let changed = interaction.select(item.tab)
        // VoiceOver's actions arrive the same way, finger or not.
        interaction.cancel()
        closeQuickSwitch()
        quickSwitch?.apply(item, isTabShown: !changed)
        resetRecognizerIfNeeded()
        showSelection(animated: true)
        if changed {
            shimmerHighlight(from: previousSelection, to: item.tab)
        } else {
            selectionView.stopShimmer()
        }
        releaseFeedback.impactOccurred()
        if changed { onSelect?(item.tab) }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        quickSwitchHold.cancel()
    }

    private func closeQuickSwitch() {
        cancelHold()
        quickSwitchWindow = nil
        quickSwitch?.cancel()
    }

    /// Ends a hold before its menu opens, leaving the finger to preview tabs
    /// as usual. An open menu takes its whole touch along, so lifting it does
    /// nothing.
    private func abandonQuickSwitch() {
        if interaction.tracking?.isQuickSwitchActive == true {
            cancelTracking(animated: true)
        } else {
            closeQuickSwitch()
        }
    }

    /// False once the window has changed under a hold or an open menu.
    private var isQuickSwitchWindowCurrent: Bool {
        // Overlay detachment or cancellation must also end a collapsed touch;
        // it must never reopen a new session from its next movement callback.
        if interaction.tracking?.isQuickSwitchActive == true,
           quickSwitch?.isActive != true || quickSwitch?.canOpen != true { return false }
        if let tracking = interaction.tracking,
           tracking.isQuickSwitchActive || quickSwitchHold.pending != nil {
            guard let coordinateView = presentation.coordinateSpace(for: self),
                  coordinateView === trackingCoordinateView,
                  tracking.geometry == currentGeometry else { return false }
        }
        guard let quickSwitchWindow, quickSwitchHold.pending != nil || interaction.tracking?.isQuickSwitchActive == true else {
            return true
        }
        return window.map { QuickSwitchWindow($0) } == quickSwitchWindow
    }

    private struct QuickSwitchWindow: Equatable {
        let identity: ObjectIdentifier
        let bounds: CGRect
        let safeAreaInsets: UIEdgeInsets

        init(_ window: UIWindow) {
            identity = ObjectIdentifier(window)
            bounds = window.bounds
            safeAreaInsets = window.safeAreaInsets
        }
    }

    /// VoiceOver reaches a tab's menu items as its custom actions.
    private func quickSwitchActions(for tab: RootTab) -> [UIAccessibilityCustomAction] {
        guard isQuickSwitchAvailable, environmentInputs?.isEnabled ?? true,
              let items = quickSwitch?.items(for: tab, selectedTab: interaction.selection) else { return [] }
        return items.map { item in
            UIAccessibilityCustomAction(name: item.title, image: UIImage(systemName: item.symbol)) { [weak self] _ in
                guard let self else { return false }
                self.commitQuickSwitch(item)
                return true
            }
        }
    }

    private func cancelTracking(animated: Bool) {
        guard interaction.tracking != nil else { return }
        interaction.cancel()
        closeQuickSwitch()
        selectionView.stopShimmer()
        resetRecognizerIfNeeded()
        showSelection(animated: animated)
    }

    private func resetRecognizerIfNeeded() {
        guard interaction.tracking == nil,
              touchRecognizer.state == .began || touchRecognizer.state == .changed else { return }
        // Abandon UIKit's simultaneous press too, so a layout or external
        // selection change cannot leave the capsule in its held state.
        glassView.isUserInteractionEnabled = false
        glassView.effect = nil
        if let configuration = glassConfiguration {
            glassView.effect = makeGlassEffect(configuration)
        }
        glassView.isUserInteractionEnabled = true
        touchRecognizer.isEnabled = false
        touchRecognizer.isEnabled = true
    }

    private func showTracking() {
        guard let tracking = interaction.tracking else { return }
        glassView.suppressInteractionGlow()
        // A hold only previews. Stop any previous release's ripple as well.
        selectionView.stopShimmer()
        for button in buttons {
            button.updateTrackingCandidate(button.tab == tracking.candidate)
        }
        // Hold the highlight on a whole tab until the finger crosses into the
        // next tab's region, including while the finger is outside the bar.
        let tab = tracking.candidate ?? interaction.selection
        guard let item = tracking.geometry.items.first(where: { $0.tab == tab }) else { return }
        let canAnimate = !reduceMotion && window != nil
        moveHighlight(to: item.frame, color: tracking.candidate == nil ? restingSelectionColor : trackingSelectionColor,
                      animated: canAnimate)
    }

    private func showSelection(animated: Bool) {
        let canAnimate = animated && !reduceMotion && window != nil
        let updateButtons = {
            for button in self.buttons {
                button.isSelected = button.tab == self.interaction.selection
                button.updateTrackingCandidate(nil)
            }
        }
        if canAnimate {
            updateButtons()
        } else {
            UIView.performWithoutAnimation(updateButtons)
        }
        guard let selectedButton = buttons.first(where: { $0.tab == interaction.selection }) else { return }
        if !canAnimate { stopMotion() }
        moveHighlight(to: selectedButton.frame, color: restingSelectionColor, animated: canAnimate)
    }

    /// Only crossing into another tab starts a spring. Movement within the same
    /// tab leaves its highlight in place without restarting the animation.
    private func moveHighlight(to frame: CGRect, color: UIColor, animated: Bool) {
        guard frame != selectionView.frame else {
            selectionView.backgroundColor = color
            return
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

    private func shimmerHighlight(from previousSelection: RootTab, to selection: RootTab) {
        guard !reduceMotion, window != nil,
              let previousButton = buttons.first(where: { $0.tab == previousSelection }),
              let selectedButton = buttons.first(where: { $0.tab == selection }) else { return }
        // Follow the committed tab change, never the finger's last movement or
        // the highlight's snap back to center. Actual centers also account for RTL.
        let distance = layoutAxis == .vertical
            ? selectedButton.center.y - previousButton.center.y
            : selectedButton.center.x - previousButton.center.x
        guard distance != 0 else { return }
        selectionView.playShimmer(axis: layoutAxis, direction: distance > 0 ? 1 : -1)
    }

    private func stopMotion() {
        selectionView.stopShimmer()
        selectionView.layer.removeAllAnimations()
    }
}
