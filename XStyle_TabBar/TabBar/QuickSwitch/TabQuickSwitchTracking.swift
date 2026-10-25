import CoreGraphics

/// Follows the finger over an open menu. The finger is in the overlay's
/// space; items report their frames as they lay out, which can be after the
/// finger has moved, in a space whose origin sits at `origin` in the
/// overlay's: a list's content, which scrolls, or the overlay itself.
struct TabQuickSwitchTracking: Equatable {
    private(set) var frames: [TabQuickSwitchDestination: CGRect] = [:]
    private(set) var origin = CGPoint.zero
    /// Only points inside reach an item: a list's visible card.
    private(set) var clip: CGRect?
    /// Points on it never reach an item: the bar, held tab and all.
    let excluded: CGRect
    private(set) var point: CGPoint?
    /// The item under the finger.
    private(set) var highlighted: TabQuickSwitchDestination?

    init(excluding excluded: CGRect = .null) {
        self.excluded = excluded
    }

    mutating func setFrame(_ frame: CGRect?, for destination: TabQuickSwitchDestination) {
        frames[destination] = frame
        updateHighlight()
    }

    /// Where the items' space sits in the overlay, and what part shows.
    mutating func setViewport(origin: CGPoint, clip: CGRect?) {
        self.origin = origin
        self.clip = clip
        updateHighlight()
    }

    mutating func move(to point: CGPoint) {
        self.point = point
        updateHighlight()
    }

    /// The item the finger lifts on, once: tracking starts over afterwards.
    mutating func release(at point: CGPoint) -> TabQuickSwitchDestination? {
        move(to: point)
        defer { self = TabQuickSwitchTracking(excluding: excluded) }
        return highlighted
    }

    private mutating func updateHighlight() {
        guard let point, !excluded.contains(point), clip?.contains(point) ?? true else {
            highlighted = nil
            return
        }
        let local = CGPoint(x: point.x - origin.x, y: point.y - origin.y)
        highlighted = frames.first { $0.value.contains(local) }?.key
    }
}
