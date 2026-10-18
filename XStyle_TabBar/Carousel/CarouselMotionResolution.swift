import Foundation

/// Driven only by the carousel's display clock. Resolution never changes its
/// point-space geometry, and companion activity is deliberately absent here.
struct CarouselMotionResolution {
    private(set) var scale: Double = 1
    private var cooldownRemaining: TimeInterval = 0

    /// Keeps the existing clock alive long enough to submit a final sharp frame.
    var needsAnimation: Bool { cooldownRemaining > 0 }

    /// Returns true when the renderer needs a frame at a different resolution.
    @discardableResult
    mutating func advance(by seconds: TimeInterval, activity: CarouselAnimationActivity,
                          isCardDragging: Bool, geometryChanged: Bool,
                          motionScale: Double, isLaminated: Bool) -> Bool {
        let requestedScale = motionScale.isFinite ? min(1, max(0.75, motionScale)) : 1
        guard isLaminated, requestedScale < 1 else { return reset() }

        let previousScale = scale
        if activity == .interactive || (isCardDragging && geometryChanged) {
            cooldownRemaining = 0.15
            scale = requestedScale
        } else if cooldownRemaining > 0 {
            let elapsed = seconds.isFinite ? max(0, seconds) : 0
            cooldownRemaining = max(0, cooldownRemaining - elapsed)
            // Avoid keeping the display clock awake for a floating-point residue.
            if cooldownRemaining < 0.000_000_001 { cooldownRemaining = 0 }
            scale = cooldownRemaining > 0 ? requestedScale : 1
        } else {
            scale = 1
        }
        return scale != previousScale
    }

    /// Backgrounding and disabling the feature discard the cooldown rather than
    /// carrying elapsed wall time into the next active display-clock tick.
    @discardableResult
    mutating func reset() -> Bool {
        let changed = scale != 1
        scale = 1
        cooldownRemaining = 0
        return changed
    }
}
