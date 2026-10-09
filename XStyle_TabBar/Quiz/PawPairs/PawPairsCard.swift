import Foundation

/// One card on the table: a face of one of the board's pairs, and where it
/// was dealt.
struct PawPairsCard: Identifiable {
    let id = UUID()
    /// The pair this card belongs to; its match has the same one.
    let pairID: Int
    let face: PawPairsFace
    /// Where the card was dealt, counting from 1. Names it for VoiceOver
    /// while it's face down.
    let number: Int
    /// Where the card sits in the board's own order, each animal just before
    /// its match, so a cleared board can line up in pairs.
    let boardIndex: Int
}
