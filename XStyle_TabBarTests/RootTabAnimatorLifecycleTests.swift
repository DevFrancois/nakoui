import Testing
import UIKit
@testable import XStyle_TabBar

@MainActor
@Suite(.serialized)
struct RootTabAnimatorLifecycleTests {
    @Test("Natural completion completes the native context exactly once")
    func naturalCompletionIsIdempotent() async throws {
        try await withFixture { fixture in
            let context = fixture.context()
            let animator = makeAnimator()
            var callbackCount = 0
            animator.onCompletion = { _ in callbackCount += 1 }
            animator.animateTransition(using: context)

            try #require(await eventually { context.completions == [true] })
            animator.finishImmediately()
            animator.finishImmediately()
            try await Task.sleep(for: .milliseconds(50))
            #expect(context.completions == [true])
            #expect(callbackCount == 1)
            expectRestored(context)
        }
    }

    @Test("Early settlement cleans up once, including when requested before the context", arguments: [false, true])
    func earlySettlementIsIdempotent(beforeContext: Bool) async throws {
        try await withFixture { fixture in
            let context = fixture.context()
            let animator = makeAnimator()
            var callbackCount = 0
            animator.onCompletion = { _ in callbackCount += 1 }

            if beforeContext {
                animator.finishImmediately()
                animator.finishImmediately()
                #expect(context.completions.isEmpty)
                #expect(animator.transitionDuration(using: context) == 0)
            }
            animator.animateTransition(using: context)
            if !beforeContext { try await Task.sleep(for: .milliseconds(45)) }
            animator.finishImmediately()
            animator.finishImmediately()

            #expect(context.completions == [true])
            #expect(callbackCount == 1)
            expectRestored(context)
            try await Task.sleep(for: .milliseconds(350))
            #expect(context.completions == [true], "Late animation callbacks must not complete a settled context again")
            #expect(callbackCount == 1)
        }
    }

    @Test("Native cancellation is reported as an unsuccessful transition")
    func cancellationIsConveyedToContext() async throws {
        try await withFixture { fixture in
            let context = fixture.context()
            let animator = makeAnimator()
            animator.animateTransition(using: context)
            try await Task.sleep(for: .milliseconds(45))
            context.transitionWasCancelled = true
            animator.finishImmediately()
            #expect(context.completions == [false])
            expectRestored(context)
        }
    }

    @Test("Removing active animations still completes the native context")
    func removedAnimationsDoNotOrphanContext() async throws {
        try await withFixture { fixture in
            let context = fixture.context()
            let animator = makeAnimator()
            animator.animateTransition(using: context)
            try await Task.sleep(for: .milliseconds(45))
            context.from.view.layer.removeAllAnimations()
            context.to.view.layer.removeAllAnimations()

            try #require(await eventually { !context.completions.isEmpty })
            animator.finishImmediately()
            #expect(context.completions == [true])
            expectRestored(context)
        }
    }

    @Test("Settlement removes transition animations while preserving unrelated layer animations")
    func cleanupOnlyRemovesOwnedAnimations() async throws {
        try await withFixture { fixture in
            let context = fixture.context()
            let key = "test.unrelated.cornerRadius"
            for view in [context.from.view!, context.to.view!] {
                let unrelated = CABasicAnimation(keyPath: "cornerRadius")
                unrelated.fromValue = 0
                unrelated.toValue = 8
                unrelated.duration = 10
                unrelated.repeatCount = .infinity
                view.layer.add(unrelated, forKey: key)
            }
            let animator = makeAnimator()
            animator.animateTransition(using: context)
            try await Task.sleep(for: .milliseconds(45))
            animator.finishImmediately()
            try await Task.sleep(for: .milliseconds(30))

            for view in [context.from.view!, context.to.view!] {
                #expect(view.layer.animation(forKey: key) != nil)
                #expect(Set(view.layer.animationKeys() ?? []) == [key],
                        "Only the animation added by the test should remain after transition cleanup")
                view.layer.removeAnimation(forKey: key)
            }
            #expect(context.completions == [true])
        }
    }

    @Test("An old animator's late completion cannot clean up the next transition")
    func oldCompletionDoesNotAffectNewTransition() async throws {
        try await withFixture { fixture in
            let oldContext = fixture.context()
            let oldAnimator = makeAnimator()
            oldAnimator.animateTransition(using: oldContext)
            try await Task.sleep(for: .milliseconds(45))
            oldAnimator.finishImmediately()

            // Reuse both real page layers in reverse order, as a rapid tab
            // reversal does. Any stale cleanup would touch the new animation.
            let newContext = fixture.context(from: fixture.second, to: fixture.first)
            let newAnimator = makeAnimator(from: .profile, to: .home)
            var newCompletionCount = 0
            newAnimator.onCompletion = { _ in newCompletionCount += 1 }
            newAnimator.animateTransition(using: newContext)
            try await Task.sleep(for: .milliseconds(45))
            oldAnimator.finishImmediately()
            oldAnimator.finishImmediately()
            try await Task.sleep(for: .milliseconds(45))

            #expect(oldContext.completions == [true])
            #expect(newContext.completions.isEmpty)
            #expect(newCompletionCount == 0)
            #expect(!(newContext.to.view.layer.animationKeys() ?? []).isEmpty,
                    "Old completion must leave the newer incoming page animation running")
            try #require(await eventually { newContext.completions == [true] })
            #expect(newCompletionCount == 1)
            expectRestored(newContext)
        }
    }

    @Test("Completed animators are released, including a pre-context settlement", arguments: [false, true])
    func animatorIsReleased(beforeContext: Bool) async throws {
        try await withFixture { fixture in
            let context = fixture.context()
            var animator: RootTabAnimator? = makeAnimator()
            weak let weakAnimator = animator
            if beforeContext { animator?.finishImmediately() }
            animator?.animateTransition(using: context)
            try #require(await eventually { context.completions == [true] })
            animator = nil
            try #require(await eventually { weakAnimator == nil },
                         "Animation callbacks must not form a retain cycle with their transition owner")
        }
    }

    private func makeAnimator(from: RootTab = .home, to: RootTab = .profile) -> RootTabAnimator {
        RootTabAnimator(motion: .init(from: from, to: to, axis: .horizontal, isRightToLeft: false), animated: true)
    }

    private func expectRestored(_ context: AnimatorTestContext) {
        for view in [context.from.view!, context.to.view!] {
            #expect(view.transform == .identity)
            #expect(view.alpha == 1)
        }
    }

    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<75 {
            try await Task.sleep(for: .milliseconds(20))
            if condition() { return true }
        }
        return false
    }

    private func withFixture(_ body: (AnimatorTestFixture) async throws -> Void) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let fixture = AnimatorTestFixture(scene: scene)
        defer { fixture.close() }
        try await Task.sleep(for: .milliseconds(30))
        try await body(fixture)
    }
}

@MainActor
private final class AnimatorTestFixture {
    let window: UIWindow
    let container = UIViewController()
    let first = UIViewController()
    let second = UIViewController()

    init(scene: UIWindowScene) {
        window = UIWindow(windowScene: scene)
        window.rootViewController = container
        window.isHidden = false
        window.layoutIfNeeded()
        container.view.backgroundColor = .systemBackground
        for page in [first, second] {
            container.addChild(page)
            page.view.frame = container.view.bounds
            page.view.backgroundColor = page === first ? .systemBlue : .systemOrange
            page.didMove(toParent: container)
        }
        container.view.addSubview(first.view)
        container.view.layoutIfNeeded()
    }

    func context(from: UIViewController? = nil, to: UIViewController? = nil) -> AnimatorTestContext {
        AnimatorTestContext(container: container.view, from: from ?? first, to: to ?? second)
    }

    func close() {
        first.view.layer.removeAllAnimations()
        second.view.layer.removeAllAnimations()
        window.isHidden = true
        window.rootViewController = nil
    }
}

@MainActor
private final class AnimatorTestContext: NSObject, UIViewControllerContextTransitioning {
    let containerView: UIView
    let from: UIViewController
    let to: UIViewController
    let isAnimated = true
    let isInteractive = false
    let presentationStyle: UIModalPresentationStyle = .custom
    let targetTransform = CGAffineTransform.identity
    var transitionWasCancelled = false
    private(set) var completions: [Bool] = []

    init(container: UIView, from: UIViewController, to: UIViewController) {
        containerView = container
        self.from = from
        self.to = to
    }

    func completeTransition(_ didComplete: Bool) { completions.append(didComplete) }
    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
        key == .from ? from : key == .to ? to : nil
    }
    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        key == .from ? from.view : key == .to ? to.view : nil
    }
    func initialFrame(for controller: UIViewController) -> CGRect { containerView.bounds }
    func finalFrame(for controller: UIViewController) -> CGRect { containerView.bounds }
    func updateInteractiveTransition(_ percentComplete: CGFloat) {}
    func finishInteractiveTransition() {}
    func cancelInteractiveTransition() { transitionWasCancelled = true }
    func pauseInteractiveTransition() {}
}
