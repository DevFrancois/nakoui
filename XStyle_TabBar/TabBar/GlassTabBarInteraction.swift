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
        /// Where the toolbar placed the bar in its window; see
        /// `GlassTabBarPresentation.placement(for:)`.
        let placement: CGPoint?
    }

    struct Tracking {
        let geometry: Geometry
        var candidate: RootTab?
        var position: CGFloat
        /// Where the finger came down, and the tab under it then.
        let origin: CGPoint
        var originTab: RootTab?
        /// The farthest the finger has been from `origin`.
        var travel: CGFloat = 0
        /// The tab whose quick switch menu is open; see `openMenu`.
        var menuTab: RootTab?
    }

    private(set) var selection: RootTab
    private(set) var tracking: Tracking?

    mutating func begin(at point: CGPoint, geometry: Geometry) {
        tracking = nil
        guard !geometry.items.isEmpty, geometry.bounds.contains(point) else { return }
        tracking = Tracking(geometry: geometry, candidate: nil, position: 0, origin: point)
        move(to: point)
        let originTab = tracking?.candidate
        tracking?.originTab = originTab
    }

    mutating func move(to point: CGPoint) {
        guard var tracking else { return }
        tracking.travel = max(tracking.travel, hypot(point.x - tracking.origin.x, point.y - tracking.origin.y))
        // An open menu follows the finger itself. The bar keeps its tab.
        guard tracking.menuTab == nil else {
            self.tracking = tracking
            return
        }
        let isVertical = tracking.geometry.axis == .vertical
        let position = isVertical ? point.y : point.x
        let centers = tracking.geometry.items.map { isVertical ? $0.frame.midY : $0.frame.midX }
        guard let lower = centers.min(), let upper = centers.max() else { return }
        tracking.position = (lower...upper).clamp(position)
        // Only touch-down must be inside the bar. Once it owns the finger,
        // keep projecting its position onto the bar's axis anywhere on screen.
        tracking.candidate = tracking.geometry.items.min {
            abs((isVertical ? $0.frame.midY : $0.frame.midX) - position)
                < abs((isVertical ? $1.frame.midY : $1.frame.midX) - position)
        }?.tab
        self.tracking = tracking
    }

    /// Whether a hold could open the held tab's menu now: the finger is still
    /// on the tab it came down on, within `allowableMovement` of where it did.
    func canOpenMenu(allowableMovement: CGFloat) -> RootTab? {
        guard let tracking, tracking.menuTab == nil, let tab = tracking.candidate,
              tab == tracking.originTab, tracking.travel <= allowableMovement else { return nil }
        return tab
    }

    /// Hands the finger to the held tab's menu. From then on the bar never
    /// commits a tab on release; the menu decides.
    @discardableResult
    mutating func openMenu(allowableMovement: CGFloat) -> RootTab? {
        guard let tab = canOpenMenu(allowableMovement: allowableMovement) else { return nil }
        tracking?.menuTab = tab
        return tab
    }

    /// Returns a newly committed destination once; a hold, cancellation, or
    /// release on the current destination never emits a navigation change.
    /// Nor does a release with a menu open, which picks from the menu instead.
    mutating func release(at point: CGPoint) -> RootTab? {
        move(to: point)
        let candidate = tracking?.menuTab == nil ? tracking?.candidate : nil
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
/// Physical touches belong to the native glass content; this simultaneous
/// tracker previews tabs and commits exactly once when the finger releases.
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
