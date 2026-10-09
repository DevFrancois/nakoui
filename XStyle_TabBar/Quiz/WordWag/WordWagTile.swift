import Foundation

/// One letter of the word. Its ID is its index in the word, which is also
/// its glass effect ID, so each tile keeps one piece of glass wherever it goes.
struct WordWagTile: Identifiable {
    let id: Int
    let letter: String
}
