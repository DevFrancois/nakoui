import Foundation

/// How `BubblePopLayout` places the bubbles. Nonisolated, like the layout.
nonisolated enum BubblePopArrangement {
    /// Rising through an area `height` points tall, `elapsed` seconds into
    /// the round, at about `speed` points per second.
    case floating(elapsed: TimeInterval, speed: Double, height: Double)
    /// Held still in centered rows that wrap, as tall as they need.
    case grid
}
