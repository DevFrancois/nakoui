import UIKit

/// App-owned tab containment. SwiftUI hosts are installed once, in RootTab order;
/// changing selection uses UIKit's public tab-transition delegate.
@MainActor
final class RootTabController: UITabBarController, UITabBarControllerDelegate {
    private(set) var committedSelection: RootTab
    private(set) var transitionRequestCount = 0
    private(set) var activeAnimator: RootTabAnimator?
    /// SwiftUI's outer NavigationStack owns the visible toolbar. Its insets
    /// must reach the child hosts even though this controller's own bar is hidden.
    var contentSafeAreaInsets: UIEdgeInsets = .zero {
        didSet { updateContentSafeArea() }
    }

    private var layoutAxis: NSLayoutConstraint.Axis = .horizontal
    private var isRightToLeft = false
    private var reduceMotion = false
    private var contentIsEnabled = true
    private var contentIsVisible = true
    private var animateNextTransition = false
    private var transitionOrigin: RootTab
    private var settlingAnimator: RootTabAnimator?
    private var isUpdatingSelection = false
    private var outgoingSnapshot: UIView?
    private var previousSize: CGSize?

    init(viewControllers: [UIViewController], selection: RootTab) {
        precondition(viewControllers.count == RootTab.allCases.count)
        committedSelection = selection
        transitionOrigin = selection
        super.init(nibName: nil, bundle: nil)
        mode = .tabBar
        setViewControllers(viewControllers, animated: false)
        selectedIndex = RootTab.allCases.firstIndex(of: selection)!
        delegate = self
        setTabBarHidden(true, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(viewControllers:selection:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.clipsToBounds = true
        updatePageAccess()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateContentSafeArea()
        if let previousSize, previousSize != view.bounds.size {
            settleTransition()
        }
        previousSize = view.bounds.size
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateContentSafeArea()
    }

    private func updateContentSafeArea() {
        guard isViewLoaded else { return }
        let current = view.safeAreaInsets
        let extra = additionalSafeAreaInsets
        // Preserve insets UIKit already supplies; add only the missing portion.
        let missing = UIEdgeInsets(
            top: max(0, contentSafeAreaInsets.top - max(0, current.top - extra.top)),
            left: max(0, contentSafeAreaInsets.left - max(0, current.left - extra.left)),
            bottom: max(0, contentSafeAreaInsets.bottom - max(0, current.bottom - extra.bottom)),
            right: max(0, contentSafeAreaInsets.right - max(0, current.right - extra.right))
        )
        if extra != missing { additionalSafeAreaInsets = missing }
    }

    override func viewWillDisappear(_ animated: Bool) {
        settleTransition()
        super.viewWillDisappear(animated)
    }

    func update(
        selection: RootTab,
        layoutAxis: NSLayoutConstraint.Axis,
        isRightToLeft: Bool,
        reduceMotion: Bool,
        isEnabled: Bool,
        isVisible: Bool,
        animated: Bool
    ) {
        isUpdatingSelection = true
        defer {
            isUpdatingSelection = false
            synchronizeNativeSelection()
            updatePageAccess()
        }
        let mustSettle = self.layoutAxis != layoutAxis || self.isRightToLeft != isRightToLeft
            || reduceMotion || !isVisible || !isEnabled
        self.layoutAxis = layoutAxis
        self.isRightToLeft = isRightToLeft
        self.reduceMotion = reduceMotion
        contentIsEnabled = isEnabled
        contentIsVisible = isVisible

        guard selection != committedSelection else {
            if mustSettle { settleTransition() }
            return
        }

        let shouldAnimate = animated && !reduceMotion && isVisible && isEnabled && viewIfLoaded?.window != nil
        transitionOrigin = committedSelection
        committedSelection = selection
        animateNextTransition = shouldAnimate
        finishCurrentTransition(capturePresentation: shouldAnimate && !mustSettle)
    }

    func tabBarController(
        _ tabBarController: UITabBarController,
        animationControllerForTransitionFrom fromVC: UIViewController,
        to toVC: UIViewController
    ) -> (any UIViewControllerAnimatedTransitioning)? {
        guard let controllers = viewControllers,
              controllers.contains(where: { $0 === fromVC }),
              let newIndex = controllers.firstIndex(where: { $0 === toVC }) else { return nil }
        transitionRequestCount += 1
        let motion = RootTabAnimator.Motion(
            from: transitionOrigin,
            to: RootTab.allCases[newIndex],
            axis: layoutAxis,
            isRightToLeft: isRightToLeft
        )
        let animator = RootTabAnimator(motion: motion, animated: canAnimatePendingTransition,
                                       outgoingSnapshot: canAnimatePendingTransition ? outgoingSnapshot : nil)
        outgoingSnapshot = nil
        animator.onCompletion = { [weak self] finished in
            guard let self else { return }
            if self.activeAnimator === finished { self.activeAnimator = nil }
            let settledPendingTransition = self.settlingAnimator === finished
            if settledPendingTransition { self.settlingAnimator = nil }
            if !self.isUpdatingSelection {
                if settledPendingTransition {
                    // This completion can run inside UIKit's initial
                    // animateTransition callback. Let that callback return
                    // before requesting a new native transition.
                    DispatchQueue.main.async { [weak self] in self?.synchronizeNativeSelection() }
                } else {
                    self.synchronizeNativeSelection()
                }
            }
            self.updatePageAccess()
        }
        activeAnimator = animator
        return animator
    }

    private func settleTransition() {
        finishCurrentTransition(capturePresentation: false)
        outgoingSnapshot?.removeFromSuperview()
        outgoingSnapshot = nil
    }

    private func finishCurrentTransition(capturePresentation: Bool) {
        guard let animator = activeAnimator else { return }
        activeAnimator = nil
        settlingAnimator = animator
        if capturePresentation {
            // The native context may not exist until the next run-loop turn.
            // The controller view still captures the currently displayed page.
            let presentation = view.snapshotView(afterScreenUpdates: false)
            outgoingSnapshot = animator.finishForRetargeting() ?? presentation
        } else {
            animator.finishImmediately()
        }
    }

    private func synchronizeNativeSelection() {
        // UIKit defers supplying a newly requested transition's context. Accept
        // the latest selection immediately, then apply just that destination
        // once the preceding context has been properly completed. No sequence
        // of superseded tab selections is queued or animated.
        guard settlingAnimator == nil else { return }
        let index = RootTab.allCases.firstIndex(of: committedSelection)!
        guard selectedIndex != index else {
            // Coalescing may end on the destination UIKit already selected.
            // Its interruption snapshot must not leak into a future switch.
            outgoingSnapshot?.removeFromSuperview()
            outgoingSnapshot = nil
            return
        }
        if canAnimatePendingTransition {
            selectedIndex = index
        } else {
            outgoingSnapshot?.removeFromSuperview()
            outgoingSnapshot = nil
            UIView.performWithoutAnimation { self.selectedIndex = index }
        }
    }

    private var canAnimatePendingTransition: Bool {
        // Environment can change after a selection was committed but before
        // UIKit supplies the previous transition's context.
        animateNextTransition && !reduceMotion && contentIsVisible && contentIsEnabled
            && viewIfLoaded?.window != nil
    }

    private func updatePageAccess() {
        for (index, controller) in (viewControllers ?? []).enumerated() {
            guard let page = controller.viewIfLoaded else { continue }
            let isSelected = RootTab.allCases[index] == committedSelection
            page.isUserInteractionEnabled = isSelected && contentIsEnabled && contentIsVisible
            page.accessibilityElementsHidden = !isSelected || !contentIsVisible
        }
    }
}
