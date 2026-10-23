import CoreGraphics
import Observation

/// Shares only the once-per-launch decision; each window owns its own presentation.
final class ScannerViewportEntranceSession {
    fileprivate var isConsumed = false
}

/// Owns one window's scanner entrance, including interrupted entrances.
@Observable
final class ScannerViewportEntrance {
    private(set) var progress: CGFloat = 0
    private(set) var hasAppeared = false
    /// The scanner tab's center in this window's coordinate space.
    var sourcePoint: CGPoint?

    @ObservationIgnored private let session: ScannerViewportEntranceSession
    @ObservationIgnored private let animator: SpringAnimator<CGFloat>

    init(
        session: ScannerViewportEntranceSession = ScannerViewportEntranceSession(),
        animator: SpringAnimator<CGFloat> = SpringAnimator(
            spring: WaveSpring(dampingRatio: 0.82, response: 0.34),
            value: 0,
            target: 1
        )
    ) {
        self.session = session
        self.animator = animator
        animator.valueChanged = { [weak self] value in
            guard let self else { return }
            guard value.isFinite else {
                finish()
                return
            }
            // Keep the spring's small overshoot while bounding unexpected display-link steps.
            progress = min(max(value, -0.1), 1.1)
        }
    }

    /// Already open, with no entrance to play, such as for previews.
    static func settled() -> ScannerViewportEntrance {
        let entrance = ScannerViewportEntrance()
        entrance.hasAppeared = true
        entrance.progress = 1
        return entrance
    }

    func update(isActive: Bool, reduceMotion: Bool) {
        guard isActive else {
            finish()
            return
        }

        guard !hasAppeared else {
            if reduceMotion { finish() }
            return
        }

        // Consume the entrance when it starts so leaving early cannot replay it.
        hasAppeared = true
        guard !session.isConsumed else {
            finish()
            return
        }
        session.isConsumed = true
        guard !reduceMotion else {
            finish()
            return
        }

        progress = 0
        animator.target = 1
        animator.restart(value: 0, velocity: 0)
    }

    func finish() {
        // A prewarmed scanner can disappear before the user has ever selected it.
        guard hasAppeared else { return }
        // Keep the animator ended until Wave removes it from its display-link controller.
        animator.stop()
        animator.value = 1
        animator.target = 1
        animator.velocity = 0
        progress = 1
    }
}
