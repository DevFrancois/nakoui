import CoreGraphics

/// Scrolls a list taller than the room past the bar. The bar keeps the touch,
/// so the finger can't drag the list: resting near the visible card's top or
/// bottom edge scrolls it instead, faster nearer the edge.
struct TabQuickSwitchListScroll: Equatable {
    /// The visible card, in the overlay's space.
    private(set) var viewport: CGRect
    /// The whole list's height.
    private(set) var contentHeight: CGFloat
    /// How far the content has moved up.
    private(set) var offset: CGFloat = 0

    init(viewport: CGRect, contentHeight: CGFloat) {
        self.viewport = viewport
        self.contentHeight = contentHeight
    }

    var maximumOffset: CGFloat {
        max(0, contentHeight - viewport.height)
    }

    /// Points a second, positive towards later rows. Only a finger inside the
    /// card, near an edge with rows past it, scrolls.
    func velocity(at point: CGPoint) -> CGFloat {
        guard maximumOffset > 0, viewport.contains(point) else { return 0 }
        let band = min(TabQuickSwitchMetrics.listScrollBand, viewport.height / 3)
        let speed = TabQuickSwitchMetrics.listScrollSpeed
        if point.y < viewport.minY + band, offset > 0 {
            return -speed * (1 - (point.y - viewport.minY) / band)
        }
        if point.y > viewport.maxY - band, offset < maximumOffset {
            return speed * (1 - (viewport.maxY - point.y) / band)
        }
        return 0
    }

    /// Moves within the list's range; returns whether it moved.
    @discardableResult
    mutating func scroll(by distance: CGFloat) -> Bool {
        let clamped = min(max(offset + distance, 0), maximumOffset)
        guard clamped != offset else { return false }
        offset = clamped
        return true
    }

    /// A new layout keeps the offset, within its own range.
    mutating func update(viewport: CGRect, contentHeight: CGFloat) {
        self.viewport = viewport
        self.contentHeight = contentHeight
        offset = min(offset, maximumOffset)
    }
}
