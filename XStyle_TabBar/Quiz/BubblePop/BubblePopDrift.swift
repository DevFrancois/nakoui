import Foundation

/// How one bubble rises and sways: a small head start up the play area, and
/// a wobble of its own. Picked at random when a round begins and never
/// changed, so a bubble's position depends only on the time. Nonisolated so
/// it can be a layout value.
nonisolated struct BubblePopDrift {
    /// Extra height at the start, as a fraction of the gap to the next bubble
    /// in its column. Kept small, so neighbors never touch.
    let lift: Double
    /// Side-to-side swings per second.
    let wobbleRate: Double
    /// Where in its swing the bubble starts, in radians.
    let wobbleOffset: Double

    static let still = BubblePopDrift(lift: 0, wobbleRate: 0, wobbleOffset: 0)

    static func random() -> BubblePopDrift {
        BubblePopDrift(
            lift: .random(in: 0...0.15),
            wobbleRate: .random(in: 0.25...0.5),
            wobbleOffset: .random(in: 0...(2 * .pi))
        )
    }
}
