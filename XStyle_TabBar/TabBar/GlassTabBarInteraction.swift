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
        /// Where the toolbar placed the bar in its window.
        let placement: CGPoint?
        /// Vertical menus open inward from the rail's physical screen edge.
        var menuOpensRight = true
    }

    enum Phase {
        case pendingHold, barBrowsing, submenuBrowsing
    }

    enum Movement: Equatable {
        case none, restartHold, cancelHold, openMenu(RootTab), collapseMenu
    }

    struct Tracking {
        let geometry: Geometry
        var candidate: RootTab?
        var position: CGFloat
        var point: CGPoint
        var holdOrigin: CGPoint
        var holdTab: RootTab?
        var phase: Phase = .pendingHold
        /// Opening on the bar isn't a return. Require a real outward trip.
        var hasExcursion = false
        var hasSubmenu = true

        var isQuickSwitchActive: Bool { phase != .pendingHold }
        var menuTab: RootTab? { phase == .submenuBrowsing ? candidate : nil }
    }

    private(set) var selection: RootTab
    private(set) var tracking: Tracking?

    mutating func begin(at point: CGPoint, geometry: Geometry) {
        tracking = nil
        guard !geometry.items.isEmpty, geometry.bounds.contains(point) else { return }
        tracking = Tracking(geometry: geometry, candidate: nil, position: 0,
                            point: point, holdOrigin: point)
        move(to: point)
    }

    /// Only a physical hit may switch tabs after activation. Before activation
    /// ordinary drag selection still projects onto the bar's axis off-screen.
    @discardableResult
    mutating func move(to point: CGPoint, allowableMovement: CGFloat = 10) -> Movement {
        guard var tracking else { return .none }
        tracking.point = point
        let physicalTab = Self.tab(at: point, in: tracking.geometry)
        let isVertical = tracking.geometry.axis == .vertical
        let position = isVertical ? point.y : point.x
        let centers = tracking.geometry.items.map { isVertical ? $0.frame.midY : $0.frame.midX }
        var movement: Movement = .none

        if !tracking.isQuickSwitchActive {
            if let lower = centers.min(), let upper = centers.max() {
                tracking.position = (lower...upper).clamp(position)
            }
            tracking.candidate = tracking.geometry.items.min {
                abs((isVertical ? $0.frame.midY : $0.frame.midX) - position)
                    < abs((isVertical ? $1.frame.midY : $1.frame.midX) - position)
            }?.tab
            if physicalTab != tracking.holdTab ||
                hypot(point.x - tracking.holdOrigin.x, point.y - tracking.holdOrigin.y) > allowableMovement {
                tracking.holdOrigin = point
                tracking.holdTab = physicalTab
                movement = physicalTab == nil ? .cancelHold : .restartHold
            }
        } else if let physicalTab {
            if physicalTab != tracking.candidate {
                tracking.candidate = physicalTab
                tracking.phase = .submenuBrowsing
                tracking.hasExcursion = false
                tracking.hasSubmenu = true
                movement = .openMenu(physicalTab)
            } else if tracking.phase == .submenuBrowsing && tracking.hasExcursion {
                tracking.phase = .barBrowsing
                tracking.hasExcursion = false
                movement = .collapseMenu
            }
            if let item = tracking.geometry.items.first(where: { $0.tab == physicalTab }) {
                tracking.position = isVertical ? item.frame.midY : item.frame.midX
            }
        } else {
            let outward: CGFloat
            if isVertical {
                outward = tracking.geometry.menuOpensRight
                    ? point.x - tracking.geometry.bounds.maxX : tracking.geometry.bounds.minX - point.x
            } else {
                outward = tracking.geometry.bounds.minY - point.y
            }
            if outward >= 8 {
                tracking.hasExcursion = true
                if tracking.phase == .barBrowsing, tracking.hasSubmenu, let tab = tracking.candidate {
                    tracking.phase = .submenuBrowsing
                    movement = .openMenu(tab)
                }
            }
        }
        self.tracking = tracking
        return movement
    }

    /// The tab under the current stationary hold anchor. Timer generations in
    /// the view enforce the fresh dwell after moving or crossing tabs.
    func canOpenMenu(allowableMovement: CGFloat) -> RootTab? {
        guard let tracking, !tracking.isQuickSwitchActive, let tab = tracking.holdTab,
              Self.tab(at: tracking.point, in: tracking.geometry) == tab,
              hypot(tracking.point.x - tracking.holdOrigin.x,
                    tracking.point.y - tracking.holdOrigin.y) <= allowableMovement else { return nil }
        return tab
    }

    @discardableResult
    mutating func openMenu(allowableMovement: CGFloat) -> RootTab? {
        guard let tab = canOpenMenu(allowableMovement: allowableMovement) else { return nil }
        tracking?.candidate = tab
        tracking?.phase = .submenuBrowsing
        tracking?.hasExcursion = false
        return tab
    }

    /// Used for a tab without choices, without ending the active session.
    mutating func collapseMenu() {
        guard tracking?.isQuickSwitchActive == true else { return }
        tracking?.phase = .barBrowsing
        tracking?.hasSubmenu = false
    }

    func tab(at point: CGPoint) -> RootTab? {
        tracking.flatMap { Self.tab(at: point, in: $0.geometry) }
    }

    private static func tab(at point: CGPoint, in geometry: Geometry) -> RootTab? {
        guard geometry.bounds.contains(point) else { return nil }
        return geometry.items.first { $0.frame.contains(point) }?.tab
    }

    /// Active sessions accept only physical bar releases here; submenu release
    /// is handled by the menu. Ordinary dragging retains its axis projection.
    mutating func release(at point: CGPoint) -> RootTab? {
        move(to: point)
        let candidate = tracking?.isQuickSwitchActive == true ? tab(at: point) : tracking?.candidate
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

    mutating func cancel() { tracking = nil }

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
