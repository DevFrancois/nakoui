import Foundation

/// A breed to unscramble, with a clue that costs a point and a fact to
/// enjoy once it's settled.
struct WordWagPuzzle: Identifiable {
    let id = UUID()
    /// The breed in capitals, exactly as the tiles spell it. One word, so
    /// every letter gets a tile.
    let word: String
    let species: PetSpecies
    let clue: LocalizedStringResource
    let fact: LocalizedStringResource

    var prompt: LocalizedStringResource {
        switch species {
        case .dog: "Which dog breed is hiding in these letters?"
        case .cat: "Which cat breed is hiding in these letters?"
        }
    }

    /// One tile per letter, identified by its place in the word, so
    /// repeated letters such as the two Ls in RAGDOLL stay distinct.
    var tiles: [WordWagTile] {
        word.enumerated().map { WordWagTile(id: $0.offset, letter: String($0.element)) }
    }

    /// The breed as a word rather than capitals, so VoiceOver says it.
    var spokenName: String {
        word.localizedCapitalized
    }
}
