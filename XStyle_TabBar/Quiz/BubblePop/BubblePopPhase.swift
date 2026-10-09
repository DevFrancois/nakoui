import Foundation

/// Where a Bubble Pop round stands.
enum BubblePopPhase: Equatable {
    /// Counting down to the start: 3, 2, 1, then 0 for "Pop!".
    case countingIn(Int)
    case playing
    /// Decided, and holding still for a moment so the last pop plays out.
    case frozen
    /// Settled into the verdict.
    case over
}
