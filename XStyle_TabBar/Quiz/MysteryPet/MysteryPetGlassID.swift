import Foundation

/// The pieces of glass that morph in Who Am I?'s glass containers.
/// Nonisolated so it can serve as a glass effect ID, which must be sendable.
nonisolated enum MysteryPetGlassID: Hashable {
    case clue(Int)
    case moreClues
    case meter
    case choice(Int)
    case reveal
    case fact
}
