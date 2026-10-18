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
    private let animationKeyPrefix = "rootTabTransition.\(UUID().uuidString)."
    private var ownedAnimations: [(layer: CALayer, key: String)] = []
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

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard transitionContext == nil, !didComplete else { return }
        transitionContext = context
        let shouldAnimate = isAnimated && !finishWhenStarted
        guard let from = context.view(forKey: .from),
              let to = context.view(forKey: .to),
              let toController = context.viewController(forKey: .to) else {
            complete()
            return
        }

        fromView = from
        toView = to
        CATransaction.begin()
        CATransaction.setDisableActions(true)
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
        CATransaction.commit()

        guard shouldAnimate else {
            complete()
            return
        }

        // Model values describe the settled destination. Only these four
        // explicit animations supply the presentation between the endpoints.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            // Core Animation invokes this on the main thread after this
            // group's animations finish or are removed. Early settlement may
            // already have completed UIKit and started a newer transition.
            self?.complete()
        }
        to.transform = .identity
        to.alpha = 1
        outgoing.transform = motion.outgoingTransform
        outgoing.alpha = 0
        addAnimation(to.layer, name: "incoming.transform", keyPath: "transform",
                     from: NSValue(caTransform3D: CATransform3DMakeAffineTransform(motion.incomingTransform)),
                     to: NSValue(caTransform3D: CATransform3DIdentity), duration: Self.slideDuration)
        addAnimation(outgoing.layer, name: "outgoing.transform", keyPath: "transform",
                     from: NSValue(caTransform3D: CATransform3DIdentity),
                     to: NSValue(caTransform3D: CATransform3DMakeAffineTransform(motion.outgoingTransform)),
                     duration: Self.slideDuration)
        addAnimation(to.layer, name: "incoming.opacity", keyPath: "opacity",
                     from: 0, to: 1, duration: Self.fadeDuration)
        addAnimation(outgoing.layer, name: "outgoing.opacity", keyPath: "opacity",
                     from: 1, to: 0, duration: Self.fadeDuration)
        CATransaction.commit()
    }

    private func addAnimation(_ layer: CALayer, name: String, keyPath: String,
                              from: Any, to: Any, duration: TimeInterval) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        let key = animationKeyPrefix + name
        ownedAnimations.append((layer, key))
        layer.add(animation, forKey: key)
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
        complete()
    }

    private func complete() {
        guard !didComplete, let context = transitionContext else { return }
        // Mark completion before removing keys: removal can deliver the old
        // transaction's callback while a newer animator uses these same layers.
        didComplete = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (layer, key) in ownedAnimations {
            layer.removeAnimation(forKey: key)
        }
        fromView?.transform = .identity
        fromView?.alpha = 1
        toView?.transform = .identity
        toView?.alpha = 1
        outgoingSnapshot?.removeFromSuperview()
        CATransaction.commit()
        ownedAnimations.removeAll()
        transitionContext = nil
        outgoingSnapshot = nil
        fromView = nil
        toView = nil
        let completion = onCompletion
        onCompletion = nil
        context.completeTransition(!context.transitionWasCancelled)
        completion?(self)
    }
}
