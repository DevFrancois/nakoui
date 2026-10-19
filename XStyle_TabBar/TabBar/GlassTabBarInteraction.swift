import UIKit

/// Keeps finger feedback independent of navigation. Geometry is captured at
/// touch-down, so a changed layout can cancel the gesture before it commits.
struct GlassTabBarInteraction {
    struct Item: Equatable {
        let tab: RootTab
        let frame: CGRect
    }

    struct Geometry: Equatable {
        let bounds: CGRect
        let axis: NSLayoutConstraint.Axis
        let items: [Item]
        let frameInWindow: CGRect?
    }

    struct Tracking {
        let geometry: Geometry
        var candidate: RootTab?
        var position: CGFloat
    }

    private(set) var selection: RootTab
    private(set) var tracking: Tracking?

    mutating func begin(at point: CGPoint, geometry: Geometry) {
        tracking = nil
        guard !geometry.items.isEmpty, geometry.bounds.contains(point) else { return }
        tracking = Tracking(geometry: geometry, candidate: nil, position: 0)
        move(to: point)
    }

    mutating func move(to point: CGPoint) {
        guard var tracking else { return }
        let isVertical = tracking.geometry.axis == .vertical
        let position = isVertical ? point.y : point.x
        let centers = tracking.geometry.items.map { isVertical ? $0.frame.midY : $0.frame.midX }
        guard let lower = centers.min(), let upper = centers.max() else { return }
        tracking.position = (lower...upper).clamp(position)
        tracking.candidate = tracking.geometry.bounds.contains(point)
            ? tracking.geometry.items.min {
                abs((isVertical ? $0.frame.midY : $0.frame.midX) - position)
                    < abs((isVertical ? $1.frame.midY : $1.frame.midX) - position)
            }?.tab
            : nil
        self.tracking = tracking
    }

    /// Returns a newly committed destination once; a hold, cancellation, or
    /// release on the current destination never emits a navigation change.
    mutating func release(at point: CGPoint) -> RootTab? {
        move(to: point)
        let candidate = tracking?.candidate
        tracking = nil
        guard let candidate, candidate != selection else { return nil }
        selection = candidate
        return candidate
    }

    @discardableResult
    mutating func select(_ tab: RootTab) -> Bool {
        guard tab != selection else { return false }
        tracking = nil
        selection = tab
        return true
    }

    mutating func cancel() {
        tracking = nil
    }

    mutating func validateGeometry(_ geometry: Geometry) {
        if let tracking, tracking.geometry != geometry { cancel() }
    }
}

/// Recognizes immediately, without a long-press delay or a pan threshold.
/// Delaying button touches prevents individual controls from previewing or
/// committing while the shared tracker owns a finger moving between tabs.
final class GlassTabBarTouchRecognizer: UIGestureRecognizer {
    var onBegin: ((CGPoint) -> Void)?
    private var trackedTouch: UITouch?
    private(set) var touchLocation: CGPoint = .zero

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard trackedTouch == nil, let touch = touches.first else {
            for touch in touches { ignore(touch, for: event) }
            return
        }
        for extraTouch in touches where extraTouch !== touch {
            ignore(extraTouch, for: event)
        }
        trackedTouch = touch
        touchLocation = touch.location(in: view)
        // A quick tap can reach .ended before UIKit delivers the first
        // target-action callback. Capture touch-down before that coalescing.
        onBegin?(touchLocation)
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        touchLocation = trackedTouch.location(in: view)
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        touchLocation = trackedTouch.location(in: view)
        state = .ended
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        state = .cancelled
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
    }
}
