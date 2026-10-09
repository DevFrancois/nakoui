import SwiftUI

/// A word as it plays in one round: how it drifts, how big it is, its tint,
/// and when it blows in.
struct BubblePopItem: Identifiable {
    let word: BubblePopWord
    let drift: BubblePopDrift
    /// Diameter relative to the standard bubble.
    let scale: Double
    let tint: Color
    /// Seconds after "Pop!" before this bubble blows in.
    let entranceDelay: Double

    var id: UUID {
        word.id
    }
}
