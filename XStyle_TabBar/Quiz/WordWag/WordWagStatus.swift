import Foundation

/// Where a word stands.
enum WordWagStatus {
    /// Some slots are still empty.
    case playing
    /// Every slot is filled, but not with the breed. The letters stay so
    /// the player can fix them.
    case wrong
    case solved
    /// The player gave up and the breed was spelled out for them.
    case revealed
}
