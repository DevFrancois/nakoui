import Foundation

/// Where something sits on the board. Nonisolated so it can serve as a
/// layout value and a view ID.
nonisolated enum WordWagSpot: Hashable {
    /// The whole row of answer slots, read by VoiceOver as one guess.
    case guess
    /// An answer slot, counting from the start of the word.
    case slot(Int)
    /// A place in the tray of scrambled letters.
    case tray(Int)

    /// VoiceOver's reading order, highest first: the guess, then the slots
    /// from the start of the word, then the tray from its first place.
    /// Without it, tiles could be read in the word's own order, which would
    /// spell out the breed.
    var accessibilitySortPriority: Double {
        switch self {
        case .guess: 1
        case .slot(let index): Double(-1 - index)
        case .tray(let position): Double(-1_000 - position)
        }
    }
}
