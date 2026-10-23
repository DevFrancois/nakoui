import CoreGraphics
import Testing
@testable import XStyle_TabBar

@MainActor
struct ScannerViewportEntranceTests {
    @Test("Prewarming and disappearing before selection preserve the first entrance")
    func inactivePrewarmDoesNotConsumeEntrance() {
        let entrance = ScannerViewportEntrance()
        entrance.update(isActive: false, reduceMotion: false)
        entrance.finish()
        entrance.update(isActive: false, reduceMotion: true)
        #expect(!entrance.hasAppeared)
        #expect(entrance.progress == 0)

        entrance.update(isActive: true, reduceMotion: false)
        defer { entrance.finish() }
        #expect(entrance.hasAppeared)
        #expect(entrance.progress == 0)
    }

    @Test("Repeated active updates preserve the running entrance and its velocity")
    func activeUpdatesDoNotRestartEntrance() {
        let (entrance, animator) = makeEntrance()
        entrance.update(isActive: true, reduceMotion: false)
        defer { entrance.finish() }
        animator.updateAnimation(dt: 0.1)
        let progress = entrance.progress
        let velocity = animator.velocity
        #expect(progress > 0 && progress < 1)

        entrance.update(isActive: true, reduceMotion: false)
        #expect(entrance.hasAppeared)
        #expect(entrance.progress == progress)
        #expect(animator.velocity == velocity)
        #expect(animator.state == .running)
    }

    @Test("Leaving during the entrance settles it and later visits do not replay", arguments: [true, false])
    func interruptionSettlesWithoutReplay(byDeactivating: Bool) {
        let (entrance, animator) = makeEntrance()
        entrance.update(isActive: true, reduceMotion: false)
        animator.updateAnimation(dt: 0.1)
        #expect(entrance.progress > 0 && entrance.progress < 1)

        if byDeactivating {
            entrance.update(isActive: false, reduceMotion: false)
        } else {
            entrance.finish()
        }
        #expect(entrance.progress == 1)
        #expect(animator.value == 1 && animator.target == 1 && animator.velocity == 0)
        #expect(animator.state == .ended)

        entrance.update(isActive: true, reduceMotion: false)
        #expect(entrance.hasAppeared)
        #expect(entrance.progress == 1)
        #expect(animator.state == .ended)
    }

    @Test("Reduce Motion consumes the first entrance without deforming the viewport")
    func reducedMotionSkipsEntrance() {
        let (entrance, animator) = makeEntrance()
        entrance.update(isActive: true, reduceMotion: true)
        #expect(entrance.hasAppeared)
        #expect(entrance.progress == 1)
        #expect(animator.state == .ended)

        entrance.update(isActive: true, reduceMotion: false)
        #expect(entrance.progress == 1)
        #expect(animator.state == .ended)
    }

    @Test("Enabling Reduce Motion during the entrance immediately settles it")
    func reducedMotionSettlesRunningEntrance() {
        let (entrance, animator) = makeEntrance()
        entrance.update(isActive: true, reduceMotion: false)
        animator.updateAnimation(dt: 0.1)
        #expect(entrance.progress > 0 && entrance.progress < 1)

        entrance.update(isActive: true, reduceMotion: true)
        #expect(entrance.progress == 1)
        #expect(animator.value == 1 && animator.target == 1 && animator.velocity == 0)
        #expect(animator.state == .ended)
    }

    @Test("A new app session gets its own first entrance")
    func freshSessionsAreIndependent() {
        let previousSession = ScannerViewportEntrance()
        previousSession.update(isActive: true, reduceMotion: true)
        let freshSession = ScannerViewportEntrance()
        #expect(!freshSession.hasAppeared)
        #expect(freshSession.progress == 0)

        freshSession.update(isActive: true, reduceMotion: false)
        defer { freshSession.finish() }
        #expect(freshSession.hasAppeared)
        #expect(freshSession.progress == 0)
        #expect(previousSession.progress == 1)
    }

    @Test("A second window cannot cancel the running entrance or replay it")
    func windowsShareConsumptionWithoutSharingMotion() {
        let session = ScannerViewportEntranceSession()
        let (first, firstAnimator) = makeEntrance(session: session)
        let (second, secondAnimator) = makeEntrance(session: session)
        first.update(isActive: true, reduceMotion: false)
        defer { first.finish() }
        firstAnimator.updateAnimation(dt: 0.1)
        let progress = first.progress
        let velocity = firstAnimator.velocity
        #expect(progress > 0 && progress < 1)

        second.update(isActive: false, reduceMotion: false)
        second.finish()
        #expect(!second.hasAppeared)
        #expect(second.progress == 0)
        #expect(first.progress == progress)
        #expect(firstAnimator.state == .running)

        second.update(isActive: true, reduceMotion: false)
        #expect(second.hasAppeared)
        #expect(second.progress == 1)
        #expect(secondAnimator.state == .ended)
        #expect(first.progress == progress)
        #expect(firstAnimator.velocity == velocity)
        #expect(firstAnimator.state == .running)
    }

    private func makeEntrance(
        session: ScannerViewportEntranceSession = ScannerViewportEntranceSession()
    ) -> (ScannerViewportEntrance, SpringAnimator<CGFloat>) {
        let animator = SpringAnimator<CGFloat>(
            spring: WaveSpring(dampingRatio: 0.75, response: 0.8),
            value: 0,
            target: 1
        )
        return (ScannerViewportEntrance(session: session, animator: animator), animator)
    }
}
