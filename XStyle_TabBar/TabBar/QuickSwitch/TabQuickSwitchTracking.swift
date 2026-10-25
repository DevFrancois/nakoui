import CoreGraphics

/// Follows the finger over an open menu. The finger and the items' frames
/// are in the overlay's space; frames arrive as the menu lays out, which can
/// be after the finger has moved.
struct TabQuickSwitchTracking: Equatable {
    private(set) var frames: [TabQuickSwitchDestination: CGRect] = [:]
    private(set) var point: CGPoint?
    /// The item under the finger.
    private(set) var highlighted: TabQuickSwitchDestination?

    mutating func setFrame(_ frame: CGRect?, for destination: TabQuickSwitchDestination) {
        frames[destination] = frame
        updateHighlight()
    }

    mutating func move(to point: CGPoint) {
        self.point = point
        updateHighlight()
    }

    /// The item the finger lifts on, once: tracking starts over afterwards.
    mutating func release(at point: CGPoint) -> TabQuickSwitchDestination? {
        move(to: point)
        defer { self = TabQuickSwitchTracking() }
        return highlighted
    }

    private mutating func updateHighlight() {
        guard let point else {
            highlighted = nil
            return
        }
        highlighted = frames.first { $0.value.contains(point) }?.key
    }
}
