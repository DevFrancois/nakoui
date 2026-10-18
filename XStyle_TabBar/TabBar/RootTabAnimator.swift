import UIKit

/// The tab controller supplies containment; this object only animates its two
/// page views. The system-managed toolbar is outside the transition container.
@MainActor
final class RootTabAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    static let fadeDuration: TimeInterval = 0.20
    static let slideDuration: TimeInterval = 0.30
    static let travel: CGFloat = 30

    struct Motion: Equatable {
        let x: CGFloat
        let y: CGFloat

        init(from: RootTab, to: RootTab, axis: NSLayoutConstraint.Axis, isRightToLeft: Bool) {
            let oldIndex = RootTab.allCases.firstIndex(of: from)!
            let newIndex = RootTab.allCases.firstIndex(of: to)!
            var direction: CGFloat = newIndex == oldIndex ? 0 : (newIndex > oldIndex ? 1 : -1)
            if axis == .horizontal && isRightToLeft { direction *= -1 }
            x = axis == .horizontal ? direction * RootTabAnimator.travel : 0
            y = axis == .vertical ? direction * RootTabAnimator.travel : 0
        }

        var incomingTransform: CGAffineTransform { .init(translationX: x, y: y) }
        var outgoingTransform: CGAffineTransform { .init(translationX: -x, y: -y) }
    }

    let motion: Motion
    let isAnimated: Bool
    var usesPresentationSnapshot: Bool { outgoingSnapshot != nil }
    var onCompletion: ((RootTabAnimator) -> Void)?

    private var outgoingSnapshot: UIView?
    private var transitionContext: (any UIViewControllerContextTransitioning)?
    private var translationAnimator: UIViewPropertyAnimator?
    private var opacityAnimator: UIViewPropertyAnimator?
    private weak var fromView: UIView?
    private weak var toView: UIView?
    private var didComplete = false
    private var finishWhenStarted = false

    init(motion: Motion, animated: Bool, outgoingSnapshot: UIView? = nil) {
        self.motion = motion
        isAnimated = animated
        self.outgoingSnapshot = outgoingSnapshot
    }

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        isAnimated && !finishWhenStarted ? Self.slideDuration : 0
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        let animator = interruptibleAnimator(using: transitionContext)
        if finishWhenStarted {
            finishImmediately()
            return
        }
        opacityAnimator?.startAnimation()
        animator.startAnimation()
    }

    func interruptibleAnimator(using context: any UIViewControllerContextTransitioning) -> any UIViewImplicitlyAnimating {
        if let translationAnimator { return translationAnimator }
        transitionContext = context
        let shouldAnimate = isAnimated && !finishWhenStarted
        let translation = UIViewPropertyAnimator(duration: shouldAnimate ? Self.slideDuration : 0, curve: .easeOut)
        translationAnimator = translation

        guard let from = context.view(forKey: .from),
              let to = context.view(forKey: .to),
              let toController = context.viewController(forKey: .to) else {
            translation.addCompletion { [weak self] _ in self?.complete() }
            return translation
        }

        fromView = from
        toView = to
        let container = context.containerView
        container.clipsToBounds = true
        to.frame = context.finalFrame(for: toController)
        container.addSubview(to)

        let outgoing: UIView
        if let snapshot = outgoingSnapshot {
            // A snapshot exists only when a preceding native transition was
            // interrupted. It preserves its displayed frame while UIKit closes
            // that transition and starts this one with the new destination.
            snapshot.frame = container.bounds
            container.addSubview(snapshot)
            from.alpha = 0
            outgoing = snapshot
        } else {
            outgoing = from
        }

        UIView.performWithoutAnimation {
            to.transform = shouldAnimate ? self.motion.incomingTransform : .identity
            to.alpha = shouldAnimate ? 0 : 1
        }

        let outgoingTransform = shouldAnimate ? motion.outgoingTransform : .identity
        translation.addAnimations {
            to.transform = .identity
            outgoing.transform = outgoingTransform
        }
        let opacity = UIViewPropertyAnimator(duration: shouldAnimate ? Self.fadeDuration : 0, curve: .easeOut)
        opacity.addAnimations {
            to.alpha = 1
            outgoing.alpha = 0
        }
        opacityAnimator = opacity
        translation.addCompletion { [weak self] _ in self?.complete() }
        return translation
    }

    /// End the current UIKit transition before changing its destination. A
    /// transient image of the presentation is handed to the next animator;
    /// child controllers themselves are never kept in an overlay hierarchy.
    func finishForRetargeting() -> UIView? {
        let snapshot = transitionContext?.containerView.snapshotView(afterScreenUpdates: false)
        finishImmediately()
        return snapshot
    }

    func finishImmediately() {
        guard !didComplete else { return }
        // UITabBarController requests its animator before supplying a context.
        // A resize or another selection can arrive in that interval. We must
        // complete the native context when it arrives, never orphan it here.
        finishWhenStarted = true
        guard transitionContext != nil else { return }
        if translationAnimator?.state == .active { translationAnimator?.stopAnimation(true) }
        if opacityAnimator?.state == .active { opacityAnimator?.stopAnimation(true) }
        complete()
    }

    private func complete() {
        guard !didComplete else { return }
        didComplete = true
        if opacityAnimator?.state == .active { opacityAnimator?.stopAnimation(true) }
        UIView.performWithoutAnimation {
            self.fromView?.transform = .identity
            self.fromView?.alpha = 1
            self.toView?.transform = .identity
            self.toView?.alpha = 1
            self.outgoingSnapshot?.removeFromSuperview()
        }
        if let context = transitionContext {
            context.completeTransition(!context.transitionWasCancelled)
        }
        transitionContext = nil
        outgoingSnapshot = nil
        translationAnimator = nil
        opacityAnimator = nil
        onCompletion?(self)
    }
}
