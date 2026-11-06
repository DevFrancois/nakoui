import SwiftUI
import UIKit

/// One native glass card is retained while the finger explores the bar.
/// SwiftUI supplies row content; UIKit owns its geometry and transition clock.
struct TabQuickSwitchListPresenter: UIViewControllerRepresentable {
    let menu: TabQuickSwitchMenu
    let presentation: TabQuickSwitchMenu.Presentation?
    let area: CGRect
    let contentDirection: LayoutDirection
    let animations: TabQuickSwitchListAnimationSettings

    func makeUIViewController(context: Context) -> TabQuickSwitchListController {
        TabQuickSwitchListController()
    }

    func updateUIViewController(_ controller: TabQuickSwitchListController, context: Context) {
        controller.update(menu: menu, presentation: presentation, area: area, direction: contentDirection,
                          animations: animations, environment: context.environment)
    }

    static func dismantleUIViewController(_ controller: TabQuickSwitchListController, coordinator: ()) {
        controller.tearDown()
    }
}

@MainActor
final class TabQuickSwitchListController: UIViewController, TabQuickSwitchListDisplaying {
    private let glass = UIVisualEffectView(effect: nil)
    private let viewport = UIView()
    private let rowsView = UIView()
    private let upperHint = UIHostingController(rootView: TabQuickSwitchScrollHint(symbol: "chevron.compact.up"))
    private let lowerHint = UIHostingController(rootView: TabQuickSwitchScrollHint(symbol: "chevron.compact.down"))
    private weak var menu: TabQuickSwitchMenu?
    private var transition = TabQuickSwitchListTransition()
    private var pending: PreparedList?
    private var displayed: PreparedList?
    private(set) var animator: UIViewPropertyAnimator?
    private var displayLink: CADisplayLink?
    private var animations = TabQuickSwitchListAnimationSettings.defaults
    private var reduceMotion = false
    private var scrollOffset: CGFloat = 0
    private var scrollLimit: CGFloat = 0
    private var highlighted: TabQuickSwitchDestination?
    private var displayFence = TabQuickSwitchListDisplayFence()
    private var closingStartOpacity: CGFloat = 1

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        glass.isHidden = true
        glass.isUserInteractionEnabled = false
        glass.cornerConfiguration = .corners(radius: .fixed(Double(TabQuickSwitchMetrics.listCornerRadius)))
        view.addSubview(glass)
        // Never mask an ancestor of UIVisualEffectView: only its content clips.
        viewport.clipsToBounds = true
        viewport.layer.cornerRadius = TabQuickSwitchMetrics.listCornerRadius
        viewport.layer.cornerCurve = .continuous
        glass.contentView.addSubview(viewport)
        viewport.addSubview(rowsView)
        for hint in [upperHint, lowerHint] {
            hint.safeAreaRegions = []
            hint.view.backgroundColor = .clear
            hint.view.isUserInteractionEnabled = false
            hint.view.accessibilityElementsHidden = true
            addChild(hint)
            viewport.addSubview(hint.view)
            hint.didMove(toParent: self)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutCardContent()
    }

    func update(menu: TabQuickSwitchMenu, presentation: TabQuickSwitchMenu.Presentation?, area: CGRect,
                direction: LayoutDirection, animations: TabQuickSwitchListAnimationSettings,
                environment: EnvironmentValues) {
        loadViewIfNeeded()
        self.menu = menu
        self.animations = animations
        reduceMotion = environment.accessibilityReduceMotion
        overrideUserInterfaceStyle = environment.colorScheme == .dark ? .dark : .light
        guard presentation?.id != transition.requestedID else { return }
        if let presentation {
            pending = prepare(presentation, area: area, direction: direction, environment: environment)
        } else {
            pending = nil
        }
        let reversingClose = transition.stage == .closing && animator?.state == .active
            && scrollOffset == 0 && displayed.map { shown in pending.map { shown.matches($0) } ?? false } == true
        let style: TabQuickSwitchListSwitchStyle = reduceMotion && animations.switchStyle != .immediate
            ? .sequentialFade : animations.switchStyle
        guard transition.request(presentation?.id, style: style) else { return }
        if reversingClose, let pending, let displayed, let animator {
            // Keep the actual native effect interpolation and row hierarchy.
            // Replaying a fresh entrance here would first reset them to zero.
            let adopted = PreparedList(presentation: pending.presentation, snapshot: pending.snapshot,
                                       hosts: displayed.hosts, environment: displayed.environment)
            self.pending = adopted
            self.displayed = adopted
            displayFence.install(adopted.snapshot.presentationID)
            publish(adopted.snapshot)
            reverseClose(animator)
            return
        }
        // Invalidate the old completion before stopping its animator.
        freezeDisplayedPose()
        if let pending { publish(pending.snapshot) }
        performStage()
    }

    func tearDown() {
        animator?.stopAnimation(true)
        animator = nil
        stopDisplayLink()
        removeRows()
        pending = nil
        menu = nil
    }

    private func prepare(_ presentation: TabQuickSwitchMenu.Presentation, area: CGRect,
                         direction: LayoutDirection, environment: EnvironmentValues) -> PreparedList {
        let rowEnvironment = RowEnvironment(direction: direction, dynamicTypeSize: environment.dynamicTypeSize,
                                            colorScheme: environment.colorScheme, locale: environment.locale)
        let hosts = presentation.items.map { item in
            let host = UIHostingController(rootView: HostedRow(item: item, highlighted: false, idealWidth: true,
                                                               environment: rowEnvironment))
            host.safeAreaRegions = []
            host.view.backgroundColor = .clear
            host.view.isUserInteractionEnabled = false
            host.view.accessibilityElementsHidden = true
            return host
        }
        let inset = TabQuickSwitchMetrics.listInset
        let scale = max(1, environment.displayScale)
        let maximumCardWidth = TabQuickSwitchListSnapshot.maximumCardWidth(
            area: area, bar: presentation.barFrame, vertical: presentation.axis == .vertical
        )
        let maximumRowWidth = max(1, maximumCardWidth - inset * 2)
        let measure = CGSize(width: maximumRowWidth, height: 10_000)
        let idealWidth = hosts.map { $0.sizeThatFits(in: measure).width }.max() ?? 44
        let cardWidth = min(max(44, idealWidth + inset * 2), maximumCardWidth)
        let rowWidth = max(1, cardWidth - inset * 2)
        var nextYPixels = Int((inset * scale).rounded())
        var rows: [TabQuickSwitchListSnapshot.Row] = []
        for (item, host) in zip(presentation.items, hosts) {
            host.rootView = HostedRow(item: item, highlighted: false, idealWidth: false, environment: rowEnvironment)
            let measuredHeight = host.sizeThatFits(in: CGSize(width: rowWidth, height: 10_000)).height
            let heightPixels = Int(ceil(max(GlassTabBarMetrics.minimumTapSize, measuredHeight) * scale))
            let height = CGFloat(heightPixels) / scale
            rows.append(.init(destination: item.id,
                              frame: CGRect(x: inset, y: CGFloat(nextYPixels) / scale, width: rowWidth, height: height)))
            nextYPixels += heightPixels
        }
        let contentHeight = CGFloat(nextYPixels + Int((inset * scale).rounded())) / scale
        var frame = TabQuickSwitchPlacement.listFrame(size: CGSize(width: cardWidth, height: contentHeight),
                                                     tab: presentation.tabFrame, bar: presentation.barFrame,
                                                     area: area, axis: presentation.axis,
                                                     spacing: TabQuickSwitchMetrics.spacing)
        // Fractional-point layout noise must not create a scrollable sliver.
        if contentHeight - frame.height > 0, contentHeight - frame.height < 1 / scale {
            let difference = contentHeight - frame.height
            if presentation.axis == .horizontal { frame.origin.y -= difference }
            frame.size.height = contentHeight
        }
        let snapshot = TabQuickSwitchListSnapshot(presentationID: presentation.id, cardFrame: frame,
                                                  rows: rows, contentHeight: contentHeight)
        return PreparedList(presentation: presentation, snapshot: snapshot, hosts: hosts, environment: rowEnvironment)
    }

    private func publish(_ snapshot: TabQuickSwitchListSnapshot) {
        // Representable updates must not publish observable changes during
        // SwiftUI's own update pass. The model rejects obsolete generations.
        Task { @MainActor [weak self] in
            guard let self, self.transition.requestedID == snapshot.presentationID, let menu = self.menu else { return }
            menu.setListDisplay(self, presentationID: snapshot.presentationID)
            for row in snapshot.rows {
                menu.setFrame(row.frame, for: row.destination, presentationID: snapshot.presentationID)
            }
            menu.setListViewport(snapshot.cardFrame, contentHeight: snapshot.contentHeight,
                                 presentationID: snapshot.presentationID)
            menu.setFocusFrame(snapshot.cardFrame, presentationID: snapshot.presentationID)
            menu.listDisplayDidUpdate(presentationID: snapshot.presentationID)
        }
    }

    private func performStage() {
        let generation = transition.generation
        switch transition.stage {
        case .hidden:
            glass.isHidden = true
            removeRows()
            stopDisplayLink()
        case .visible:
            if displayed?.snapshot.presentationID != transition.displayedID { installPending() }
            UIView.performWithoutAnimation {
                self.glass.transform = .identity
                self.glass.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                if let frame = self.displayedFrame { self.glass.frame = frame }
                self.glass.effect = self.regularGlass()
                self.glass.isHidden = false
                self.viewport.alpha = 1
                self.layoutCardContent()
            }
            notifyDisplayChanged()
            if let id = transition.displayedID, displayFence.permits(id) { stopDisplayLink() }
            else { startDisplayLink() }
        case .entrance:
            installPending()
            guard let displayed, let frame = displayedFrame else { return }
            let entrance = reduceMotion ? TabQuickSwitchListEntranceStyle.fade : animations.entranceStyle
            UIView.performWithoutAnimation {
                self.glass.transform = .identity
                self.glass.layer.anchorPoint = TabQuickSwitchListSnapshot.entranceAnchor(
                    tab: displayed.presentation.tabFrame, card: displayed.snapshot.cardFrame,
                    bar: displayed.presentation.barFrame, vertical: displayed.presentation.axis == .vertical
                )
                self.glass.frame = frame
                self.glass.effect = nil
                self.viewport.alpha = 0
                self.glass.isHidden = false
                self.layoutCardContent()
                switch entrance {
                case .fade: break
                case .scale: self.glass.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                case .slide:
                    if displayed.presentation.axis == .horizontal {
                        self.glass.transform = CGAffineTransform(translationX: 0, y: 8)
                    } else {
                        let sign: CGFloat = displayed.snapshot.cardFrame.midX > displayed.presentation.barFrame.midX ? -1 : 1
                        self.glass.transform = CGAffineTransform(translationX: sign * 8, y: 0)
                    }
                }
            }
            animate(duration: entranceDuration, generation: generation) {
                self.glass.transform = .identity
                self.glass.effect = self.regularGlass()
                self.viewport.alpha = 1
            }
        case .moveFadeOut:
            animate(duration: animations.switchDuration * 0.2, generation: generation) {
                self.viewport.alpha = 0
            }
        case .moving:
            let startingFrame = glass.frame
            installPending()
            guard let target = displayedFrame else { return }
            UIView.performWithoutAnimation {
                self.glass.transform = .identity
                self.glass.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                self.glass.frame = startingFrame
                self.glass.effect = self.regularGlass()
                self.viewport.alpha = 0
                self.glass.isHidden = false
            }
            animate(duration: animations.switchDuration * 0.6, generation: generation) {
                self.glass.frame = target
                self.layoutCardContent()
            }
        case .moveFadeIn:
            animate(duration: animations.switchDuration * 0.2, generation: generation) {
                self.viewport.alpha = 1
            }
        case .sequentialFadeOut:
            animate(duration: replacementFadeDuration, generation: generation) {
                self.viewport.alpha = 0
                self.glass.effect = nil
            }
        case .sequentialFadeIn:
            installPending()
            guard let frame = displayedFrame else { return }
            UIView.performWithoutAnimation {
                self.glass.transform = .identity
                self.glass.layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                self.glass.frame = frame
                self.glass.effect = nil
                self.viewport.alpha = 0
                self.glass.isHidden = false
                self.layoutCardContent()
            }
            animate(duration: replacementFadeDuration, generation: generation) {
                self.glass.effect = self.regularGlass()
                self.viewport.alpha = 1
            }
        case .closing:
            closingStartOpacity = viewport.alpha
            animate(duration: min(0.1, entranceDuration), generation: generation) {
                self.viewport.alpha = 0
                self.glass.effect = nil
            }
        }
    }

    private var entranceDuration: TimeInterval { reduceMotion ? min(0.15, animations.entranceDuration) : animations.entranceDuration }
    private var replacementFadeDuration: TimeInterval { reduceMotion ? 0.075 : animations.switchDuration / 2 }

    private func regularGlass() -> UIGlassEffect { UIGlassEffect(style: .regular) }

    private func reverseClose(_ animator: UIViewPropertyAnimator) {
        let generation = transition.generation
        let needsEntranceCompletion = closingStartOpacity < 0.999
        animator.pauseAnimation()
        // UIKit complements the fraction when the direction changes. Inspect
        // the forward close's progress before reversing it.
        let closingProgress = animator.fractionComplete
        animator.isReversed = true
        animator.addCompletion { [weak self] _ in
            guard let self, self.transition.generation == generation,
                  self.transition.stage == .entrance else { return }
            self.animator = nil
            if needsEntranceCompletion {
                // The close may itself have interrupted an entrance. Reverse
                // to that displayed pose, then finish it without a reset.
                self.animate(duration: self.entranceDuration, generation: generation) {
                    self.glass.transform = .identity
                    self.glass.effect = self.regularGlass()
                    self.viewport.alpha = 1
                }
            } else if self.transition.complete(generation: generation) {
                self.performStage()
            }
        }
        startDisplayLink()
        if closingProgress == 0 {
            // A close can be reopened before its first rendered frame. There
            // is no reverse distance to animate, and continuing at zero can
            // leave UIKit's animator active without delivering a completion.
            // Finish at the original pose through the same guarded completion.
            animator.stopAnimation(false)
            animator.finishAnimation(at: .start)
        } else {
            animator.continueAnimation(withTimingParameters: nil, durationFactor: 1)
        }
        notifyDisplayChanged()
    }

    private func animate(duration: TimeInterval, generation: UInt64, changes: @escaping () -> Void) {
        let animator = UIViewPropertyAnimator(duration: max(0, duration), curve: .easeInOut, animations: changes)
        animator.isManualHitTestingEnabled = true
        animator.flushUpdates = true
        self.animator = animator
        animator.addCompletion { [weak self] _ in
            guard let self, self.transition.complete(generation: generation) else { return }
            self.animator = nil
            self.performStage()
        }
        startDisplayLink()
        animator.startAnimation()
        notifyDisplayChanged()
    }

    /// Keep the visible pose when a new request interrupts an animation.
    private func freezeDisplayedPose() {
        guard let animator else { return }
        let layer = glass.layer.presentation()
        let bounds = layer?.bounds ?? glass.bounds
        let position = layer?.position ?? glass.layer.position
        let transform = layer?.affineTransform() ?? glass.transform
        let opacity = viewport.layer.presentation()?.opacity ?? Float(viewport.alpha)
        animator.stopAnimation(false)
        animator.finishAnimation(at: .current)
        self.animator = nil
        UIView.performWithoutAnimation {
            self.glass.bounds = bounds
            self.glass.layer.position = position
            self.glass.transform = transform
            self.viewport.alpha = CGFloat(opacity)
        }
    }

    private var displayedFrame: CGRect? {
        guard let frame = displayed?.snapshot.cardFrame else { return nil }
        return menu?.coordinateView.map { view.convert(frame, from: $0) } ?? frame
    }

    private func installPending() {
        guard let pending, pending.snapshot.presentationID == transition.displayedID else { return }
        if displayed === pending { return }
        removeRows()
        displayed = pending
        displayFence.install(pending.snapshot.presentationID)
        scrollOffset = 0
        scrollLimit = max(0, pending.snapshot.contentHeight - pending.snapshot.cardFrame.height)
        highlighted = nil
        for (host, row) in zip(pending.hosts, pending.snapshot.rows) {
            addChild(host)
            rowsView.addSubview(host.view)
            host.view.frame = row.frame
            host.didMove(toParent: self)
        }
        layoutCardContent()
    }

    private func removeRows() {
        for host in displayed?.hosts ?? [] {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        }
        displayed = nil
    }

    private func layoutCardContent() {
        glass.layoutIfNeeded()
        viewport.frame = glass.contentView.bounds
        rowsView.frame = CGRect(x: 0, y: -scrollOffset, width: viewport.bounds.width,
                                height: displayed?.snapshot.contentHeight ?? 0)
        let upperSize = upperHint.sizeThatFits(in: CGSize(width: 80, height: 40))
        let lowerSize = lowerHint.sizeThatFits(in: CGSize(width: 80, height: 40))
        upperHint.view.frame = CGRect(x: viewport.bounds.midX - upperSize.width / 2, y: 0,
                                      width: upperSize.width, height: upperSize.height)
        lowerHint.view.frame = CGRect(x: viewport.bounds.midX - lowerSize.width / 2,
                                      y: viewport.bounds.maxY - lowerSize.height,
                                      width: lowerSize.width, height: lowerSize.height)
        upperHint.view.isHidden = scrollOffset <= 0
        lowerHint.view.isHidden = scrollOffset >= scrollLimit
    }

    func destination(at point: CGPoint, presentationID: UInt64) -> TabQuickSwitchDestination? {
        let contentPresentation = viewport.layer.presentation()
        let glassPresentation = glass.layer.presentation()
        guard displayFence.permits(presentationID),
              transition.acceptsRows(presentationID: presentationID,
                                     contentOpacity: contentPresentation?.opacity ?? Float(viewport.alpha),
                                     hasPresentationLayer: contentPresentation != nil && glassPresentation != nil),
              let displayed, displayed.snapshot.presentationID == presentationID,
              !glass.isHidden, !viewport.isHidden else { return nil }
        let overlayPoint = menu?.coordinateView.map { view.convert(point, from: $0) } ?? point
        let local: CGPoint
        if let presentation = glassPresentation {
            local = presentation.convert(overlayPoint, from: view.layer.presentation() ?? view.layer)
        } else {
            local = glass.convert(overlayPoint, from: view)
        }
        return displayed.snapshot.destination(at: local, scrollOffset: scrollOffset)
    }

    func canAutoscroll(presentationID: UInt64) -> Bool {
        transition.stage == .visible && transition.requestedID == presentationID
            && displayed?.snapshot.presentationID == presentationID && !glass.isHidden && displayFence.permits(presentationID)
    }

    func setScrollOffset(_ offset: CGFloat, limit: CGFloat, presentationID: UInt64) {
        guard displayed?.snapshot.presentationID == presentationID else { return }
        scrollOffset = offset
        scrollLimit = limit
        UIView.performWithoutAnimation { self.layoutCardContent() }
    }

    func setHighlighted(_ destination: TabQuickSwitchDestination?, presentationID: UInt64) {
        guard let displayed, displayed.snapshot.presentationID == presentationID, highlighted != destination else { return }
        highlighted = destination
        for (item, host) in zip(displayed.presentation.items, displayed.hosts) {
            host.rootView = HostedRow(item: item, highlighted: item.id == destination, idealWidth: false,
                                      environment: displayed.environment)
        }
    }

    private func notifyDisplayChanged() {
        guard let id = transition.requestedID else { return }
        menu?.listDisplayDidUpdate(presentationID: id)
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let target = ListDisplayLinkTarget { [weak self] link in self?.displayTick(link) }
        let link = CADisplayLink(target: target, selector: #selector(ListDisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    private func displayTick(_ link: CADisplayLink) {
        if transition.permitsVisibleRows, let id = transition.displayedID {
            displayFence.tick(at: link.timestamp, presentationID: id)
            if transition.stage == .visible, displayFence.permits(id) { stopDisplayLink() }
        }
        notifyDisplayChanged()
    }
}

private struct RowEnvironment: Equatable {
    let direction: LayoutDirection
    let dynamicTypeSize: DynamicTypeSize
    let colorScheme: ColorScheme
    let locale: Locale
}

private struct HostedRow: View {
    let item: TabQuickSwitchItem
    let highlighted: Bool
    let idealWidth: Bool
    let environment: RowEnvironment

    var body: some View {
        TabQuickSwitchRow(item: item, isHighlighted: highlighted)
            .fixedSize(horizontal: idealWidth, vertical: true)
            .environment(\.layoutDirection, environment.direction)
            .environment(\.dynamicTypeSize, environment.dynamicTypeSize)
            .environment(\.colorScheme, environment.colorScheme)
            .environment(\.locale, environment.locale)
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
    }
}

private final class PreparedList {
    let presentation: TabQuickSwitchMenu.Presentation
    let snapshot: TabQuickSwitchListSnapshot
    let hosts: [UIHostingController<HostedRow>]
    let environment: RowEnvironment

    init(presentation: TabQuickSwitchMenu.Presentation, snapshot: TabQuickSwitchListSnapshot,
         hosts: [UIHostingController<HostedRow>], environment: RowEnvironment) {
        self.presentation = presentation
        self.snapshot = snapshot
        self.hosts = hosts
        self.environment = environment
    }

    func matches(_ other: PreparedList) -> Bool {
        presentation.tab == other.presentation.tab && presentation.items == other.presentation.items
            && snapshot.cardFrame == other.snapshot.cardFrame && snapshot.rows == other.snapshot.rows
            && snapshot.contentHeight == other.snapshot.contentHeight && environment == other.environment
    }
}

private final class ListDisplayLinkTarget: NSObject {
    let action: (CADisplayLink) -> Void
    init(action: @escaping (CADisplayLink) -> Void) { self.action = action }
    @objc func tick(_ link: CADisplayLink) { action(link) }
}
