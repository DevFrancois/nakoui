import Foundation

/// Sizes and timings for Who Am I?
enum MysteryPetMetrics {
    static let portraitSize = 64.0
    static let revealBadgeSize = 56.0
    static let clueSpacing = 12.0
    /// How close glass must come before it blends. No more than
    /// `clueSpacing`, so resting speech bubbles and answers keep their own
    /// shapes, while a bubble on the move blends with its neighbors as it
    /// morphs out of the clue button.
    static let glassSpacing = clueSpacing
    /// The height of the clue button and of the points meter beside it.
    static let controlHeight = 52.0
    /// The small corner of a clue bubble: its tail, toward the mystery pet.
    static let bubbleTailRadius = 6.0
    /// How high a paw hops in the typing bubble.
    static let typingHop = 3.0
    /// How long the pet "types" before a new clue lands.
    static let typingDuration = Duration.milliseconds(700)
    /// How long the reveal settles before it's scrolled into view.
    static let revealScrollDelay = Duration.milliseconds(450)
}
