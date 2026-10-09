import SwiftUI
import UIKit

private final class SideMenuPanGestureRecognizer: UIPanGestureRecognizer {
    /// Movement required before UIKit asks whether this pan should begin.
    /// UIPanGestureRecognizer alone decides after ~10pt, while a thumb's arc
    /// is often still mostly vertical, and a refusal lasts the whole touch.
    var decisionDistance: CGFloat = 20
    private var touchStart: CGPoint?

    /// Movement since touch-down, including the recognition hysteresis.
    var displacement: CGPoint {
        guard let touchStart, numberOfTouches > 0 else { return .zero }
        let location = location(in: view)
        return CGPoint(x: location.x - touchStart.x, y: location.y - touchStart.y)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if touchStart == nil { touchStart = touches.first?.location(in: view) }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let touchStart, let touch = touches.first {
            let location = touch.location(in: view)
            // Hold back short movements so the direction is clear when UIKit asks.
            if hypot(location.x - touchStart.x, location.y - touchStart.y) < decisionDistance { return }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        touchStart = nil
    }
}

struct CustomSideMenu<MenuContent: View, Content: View>: View {
    var isEnabled: Bool
    /// Asked as a touch begins.
    var canBeginOpening: () -> Bool
    /// Applies to touches outside horizontal scroll views, and over a free-scrolling
    /// one resting at its leading edge. Over a paging one, an opening swipe is
    /// accepted anywhere while its first page dominates. Asked as a touch
    /// begins, so the answer can follow a scroll without redrawing anything.
    var canOpenFromAnywhere: () -> Bool
    /// The menu's share of the screen's width, kept within the limits below,
    /// so it scales across phones but stays a sidebar on wide screens.
    var widthFraction: CGFloat
    var minimumWidth: CGFloat
    var maximumWidth: CGFloat
    var edgeActivationWidth: CGFloat
    @Binding var isExpanded: Bool
    var onDismissed: () -> Void
    @ViewBuilder var menuContent: (_ progress: CGFloat) -> MenuContent
    @ViewBuilder var content: (_ progress: CGFloat) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var progress: CGFloat
    @State private var xOffset: CGFloat
    @State private var dragStart: DragStart?
    @State private var settlingTarget: Bool?
    @State private var transitionID = 0
    @State private var hasReportedClosed: Bool
    @State private var haptics = false
    /// The screen's width, which the menu's width follows.
    @State private var containerWidth: CGFloat = 0

    init(
        isEnabled: Bool = true,
        canBeginOpening: @escaping () -> Bool = { true },
        canOpenFromAnywhere: @escaping () -> Bool = { false },
        widthFraction: CGFloat = 0.8,
        minimumWidth: CGFloat = 260,
        maximumWidth: CGFloat = 320,
        edgeActivationWidth: CGFloat = 24,
        isExpanded: Binding<Bool>,
        onDismissed: @escaping () -> Void = {},
        @ViewBuilder menuContent: @escaping (_ progress: CGFloat) -> MenuContent,
        @ViewBuilder content: @escaping (_ progress: CGFloat) -> Content
    ) {
        self.isEnabled = isEnabled
        self.canBeginOpening = canBeginOpening
        self.canOpenFromAnywhere = canOpenFromAnywhere
        self.widthFraction = widthFraction
        self.minimumWidth = minimumWidth
        self.maximumWidth = maximumWidth
        self.edgeActivationWidth = edgeActivationWidth
        self._isExpanded = isExpanded
        self.onDismissed = onDismissed
        self.menuContent = menuContent
        self.content = content
        self._progress = State(initialValue: isExpanded.wrappedValue ? 1 : 0)
        // Corrected once the screen's width is known.
        self._xOffset = State(initialValue: isExpanded.wrappedValue ? max(maximumWidth, 1) : 0)
        self._hasReportedClosed = State(initialValue: !isExpanded.wrappedValue)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            menuContent(progress)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .opacity(progress)
                .scaleEffect(reduceMotion ? 1 : 0.95 + 0.05 * progress)
                .allowsHitTesting(isExpanded && dragStart == nil && settlingTarget == nil)
                .accessibilityHidden(!isExpanded)

            content(progress)
                // Drained of color while the menu shows, so the menu holds
                // the color: washed lighter in light mode, darker in dark mode.
                .saturation(Double(1 - 0.85 * progress))
                .brightness(Double((colorScheme == .dark ? -0.15 : 0.15) * progress))
                .containerRelativeFrame(.horizontal)
                .frame(maxHeight: .infinity)
                .allowsHitTesting(!isModal)
                .accessibilityHidden(isModal)
                .background {
                    backgroundShape
                        .fill(.background)
                        .ignoresSafeArea()
                }
                .overlay {
                    // Closes the menu on a tap anywhere on the content.
                    Color.clear
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { settle(expanded: false) }
                        .allowsHitTesting(isModal)
                        .accessibilityHidden(true)
                }
                .mask {
                    backgroundShape
                        .ignoresSafeArea()
                }
                .compositingGroup()
                .overlay {
                    rim
                }
                .offset(x: xOffset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            containerWidthDidChange(to: newWidth)
        }
        .contentShape(.rect)
        .gesture(
            CustomSideMenuGesture(
                // A pan may interrupt a settle: .began takes over from it, and
                // the spring's long removal tail would otherwise drop drags.
                isEnabled: isEnabled,
                canBeginOpening: canBeginOpening,
                canOpenFromAnywhere: canOpenFromAnywhere,
                edgeActivationWidth: edgeActivationWidth,
                isExpanded: isExpanded,
                handle: handlePan
            )
        )
        .sensoryFeedback(.impact(weight: .light), trigger: haptics)
        .accessibilityAction(.escape) {
            if isModal { settle(expanded: false) }
        }
        .onChange(of: isExpanded) { _, expanded in
            // A pan's own binding write already has its settle animation running.
            guard settlingTarget != expanded else { return }
            settle(expanded: expanded)
        }
    }

    /// The menu's width: a share of the screen, within its limits. Also how
    /// far the content slides, and the drag distance that decides a release.
    private var width: CGFloat {
        guard containerWidth > 0 else { return max(maximumWidth, 1) }
        return max(min(max(containerWidth * widthFraction, minimumWidth), maximumWidth), 1)
    }

    /// Keeps an open menu's content against the menu's new edge when the
    /// screen's width changes, as on rotation or unfolding an iPhone Duo.
    private func containerWidthDidChange(to newWidth: CGFloat) {
        guard containerWidth != newWidth else { return }
        containerWidth = newWidth
        guard dragStart == nil, isExpanded, progress == 1 else { return }
        withoutAnimation {
            xOffset = width
        }
    }

    /// Light catching the content's rounded edge while the menu shows,
    /// brightest at the top corner, like the rim of a glass pane. Outside the
    /// mask, so the line isn't cut in half.
    private var rim: some View {
        backgroundShape
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0.25)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.5
            )
            .opacity(progress)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var isModal: Bool {
        // Closing hands control back at once; waiting for the spring's long
        // removal tail would block the content right after it reappears.
        isExpanded || progress > 0 || dragStart != nil || settlingTarget == true
    }

    /// Fully closed and settled, so the content covers the whole screen.
    private var isAtRest: Bool {
        hasReportedClosed
    }

    private var backgroundShape: AnyShape {
        // Round the content only while the menu shows. At rest the display's
        // own corners round it, and a mask would cut them out of screenshots.
        isAtRest ? AnyShape(Rectangle()) : AnyShape(ConcentricRectangle(corners: .concentric, isUniform: true))
    }

    private func handlePan(
        _ state: UIGestureRecognizer.State,
        _ translation: CGPoint,
        _ velocity: CGPoint
    ) {
        switch state {
        case .began:
            transitionID += 1
            settlingTarget = nil
            dragStart = DragStart(offset: xOffset, wasExpanded: isExpanded)
            hasReportedClosed = false
            updateDrag(translation.x)
        case .changed:
            updateDrag(translation.x)
        case .ended:
            guard dragStart != nil else { return }
            settle(expanded: xOffset + velocity.x / 5 > width / 2)
        case .cancelled, .failed:
            guard let dragStart else { return }
            // Disabling the recognizer for navigation must respect the new binding.
            settle(expanded: isEnabled ? dragStart.wasExpanded : isExpanded)
        default:
            break
        }
    }

    private func updateDrag(_ translation: CGFloat) {
        guard let dragStart else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            xOffset = min(max(dragStart.offset + translation, 0), width)
            progress = xOffset / width
        }
    }

    private func settle(expanded: Bool) {
        if dragStart == nil, settlingTarget == expanded { return }

        let targetOffset = expanded ? width : 0
        if dragStart == nil, settlingTarget == nil,
           xOffset == targetOffset, progress == (expanded ? 1 : 0) {
            reportDismissalIfNeeded()
            return
        }

        let wasExpanded = dragStart?.wasExpanded ?? (progress == 1)
        dragStart = nil
        transitionID += 1
        let identifier = transitionID
        settlingTarget = expanded
        if expanded { hasReportedClosed = false }
        if expanded != wasExpanded { haptics.toggle() }

        let updates = {
            xOffset = targetOffset
            progress = expanded ? 1 : 0
            isExpanded = expanded
        }

        if reduceMotion {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction, updates)
            finishSettling(identifier: identifier)
        } else {
            withAnimation(.interactiveSpring(duration: 0.2, extraBounce: 0.02), completionCriteria: .removed) {
                updates()
            } completion: {
                finishSettling(identifier: identifier)
            }
        }
    }

    private func finishSettling(identifier: Int) {
        guard transitionID == identifier, dragStart == nil else { return }
        settlingTarget = nil
        reportDismissalIfNeeded()
    }

    private func reportDismissalIfNeeded() {
        guard !isExpanded, progress == 0, xOffset == 0,
              dragStart == nil, settlingTarget == nil, !hasReportedClosed else { return }
        hasReportedClosed = true
        onDismissed()
    }

    private struct DragStart {
        let offset: CGFloat
        let wasExpanded: Bool
    }
}

private struct CustomSideMenuGesture: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var canBeginOpening: () -> Bool
    var canOpenFromAnywhere: () -> Bool
    var edgeActivationWidth: CGFloat
    var isExpanded: Bool
    var handle: (UIGestureRecognizer.State, CGPoint, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = SideMenuPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.converter = context.converter
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        if recognizer.state == .began {
            context.coordinator.snapPagerToLeadingEdge()
        }
        handle(
            recognizer.state,
            context.converter.localTranslation ?? .zero,
            context.converter.localVelocity ?? .zero
        )
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(parent: self, converter: converter)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CustomSideMenuGesture
        var converter: CoordinateSpaceConverter
        /// The horizontal scroll view under the current touch, if any.
        private weak var horizontalScrollView: UIScrollView?
        private weak var pagerToSnap: UIScrollView?

        init(parent: CustomSideMenuGesture, converter: CoordinateSpaceConverter) {
            self.parent = parent
            self.converter = converter
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard parent.isEnabled, gestureRecognizer.numberOfTouches == 0 else { return false }
            horizontalScrollView = nil
            pagerToSnap = nil
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.isEnabled else { return false }
            // Decide when UIKit is ready to begin, using the latest pager state.
            // A touch can arrive while the previous scroll is still settling.
            // UIKit keeps the winning recognizer in control until this pan ends.
            // Judge the whole movement since touch-down: the pan's own translation
            // excludes its hysteresis and instantaneous velocity is noisy.
            let direction = (gestureRecognizer as? SideMenuPanGestureRecognizer)?.displacement
                ?? converter.localTranslation ?? .zero
            // Up to ~55° from horizontal, so a thumb's natural arc still counts.
            guard abs(direction.x) > abs(direction.y) * 0.7 else { return false }

            if parent.isExpanded { return direction.x < 0 }
            guard parent.canBeginOpening(), direction.x > 0 else { return false }

            let startX = converter.localLocation.x - direction.x
            let startsAtEdge = startX >= 0 && startX <= parent.edgeActivationWidth
            guard let scrollView = horizontalScrollView else {
                return startsAtEdge || parent.canOpenFromAnywhere()
            }

            // Read UIKit's live scroll state: SwiftUI's copy of the pager can lag
            // a frame behind, so a swipe right after landing on the first page
            // would otherwise be refused and rubber-band the scroll view instead.
            let offset = scrollView.contentOffset.x + scrollView.adjustedContentInset.left
            if scrollView.isPagingEnabled {
                // While the first page dominates, including while a swipe back to
                // it is still gliding in or rubber-banding, a rightward drag means
                // the menu. The pager is snapped onto that page once the pan begins.
                if offset <= scrollView.bounds.width * 0.5 {
                    pagerToSnap = abs(offset) > 0.5 ? scrollView : nil
                    return true
                }
            } else if offset <= 0.5 {
                // A free-scrolling row (the category chips) at its leading edge
                // cannot use a rightward drag; treat it like the content beneath
                // and never move it.
                return startsAtEdge || parent.canOpenFromAnywhere()
            }
            return startsAtEdge && !scrollView.isDragging && !scrollView.isDecelerating
        }

        /// Stops a pager that the menu pan took over while it was still settling.
        func snapPagerToLeadingEdge() {
            guard let scrollView = pagerToSnap else { return }
            pagerToSnap = nil
            let leading = CGPoint(x: -scrollView.adjustedContentInset.left, y: scrollView.contentOffset.y)
            scrollView.setContentOffset(leading, animated: false)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Only horizontal scroll views compete with the menu. Vertical ones
            // must start at once instead of waiting out the decision distance.
            guard parent.isEnabled,
                  let scrollView = otherGestureRecognizer.view as? UIScrollView,
                  otherGestureRecognizer === scrollView.panGestureRecognizer,
                  scrollView.contentSize.width > scrollView.bounds.width + 0.5 else { return false }
            horizontalScrollView = scrollView
            // The scroll pan waits only until shouldBegin accepts or rejects this drag.
            return true
        }

    }
}
