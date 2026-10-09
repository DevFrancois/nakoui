/// One character of a symbol being decoded: its candidates and measured bar width.
struct CharacterReading {
    var candidates: CharacterCandidates
    /// Total bar width in modules of the character's own width (7 modules).
    var bars: Float
    var digit: Int
    var isEven: Bool
}
