/// The digit(s) a 7-module character can be, given its like-edge distances.
///
/// With the character's elements e0...e3 in reading order and S their sum, T1 = 7(e0+e1)/S and
/// T2 = 7(e1+e2)/S are edge-to-same-edge distances in modules. They do not change when every bar
/// grows by the same amount (ink spread, blur, exposure), and rounded to 2...5 they identify the
/// digit, except for 1/7 and 2/8, which share a cell and are told apart by the bars' total width.
/// Space-first characters (left half) use the L set in cells with T1+T2 even and the G set in
/// the others; bar-first characters (right half, R set) only use the even cells.
struct CharacterCandidates {
    /// The digit, or -1 when no character has these distances.
    var digit: Int
    /// Nominal bar modules of `digit`.
    var bars: Int
    /// The other digit sharing the cell (-1 when the cell is unambiguous) and its bar modules.
    var tieDigit: Int
    var tieBars: Int
    /// Whether the character belongs to the even (G) set.
    var isEven: Bool

    private init(_ digit: Int, _ bars: Int, _ tieDigit: Int = -1, _ tieBars: Int = 0, even: Bool = false) {
        self.digit = digit
        self.bars = bars
        self.tieDigit = tieDigit
        self.tieBars = tieBars
        isEven = even
    }

    static let invalid = CharacterCandidates(-1, 0)

    /// A digit decided by another classifier.
    static func fixed(_ digit: Int, even: Bool) -> CharacterCandidates { CharacterCandidates(digit, 0, even: even) }

    /// Candidates for rounded distances `t1`, `t2` in 2...5.
    static func lookup(t1: Int, t2: Int, barFirst: Bool) -> CharacterCandidates {
        if barFirst {
            switch (t1, t2) {
            case (2, 2): return .init(6, 2)
            case (2, 4): return .init(4, 4)
            case (3, 3): return .init(2, 4, 8, 2)
            case (3, 5): return .init(5, 4)
            case (4, 2): return .init(9, 4)
            case (4, 4): return .init(1, 4, 7, 2)
            case (5, 3): return .init(0, 4)
            case (5, 5): return .init(3, 2)
            default: return .invalid
            }
        }
        switch (t1, t2) {
        case (2, 2): return .init(6, 5)
        case (2, 3): return .init(0, 4, even: true)
        case (2, 4): return .init(4, 3)
        case (2, 5): return .init(3, 2, even: true)
        case (3, 2): return .init(9, 4, even: true)
        case (3, 3): return .init(2, 3, 8, 5)
        case (3, 4): return .init(1, 4, 7, 2, even: true)
        case (3, 5): return .init(5, 3)
        case (4, 2): return .init(9, 3)
        case (4, 3): return .init(2, 4, 8, 2, even: true)
        case (4, 4): return .init(1, 3, 7, 5)
        case (4, 5): return .init(5, 4, even: true)
        case (5, 2): return .init(6, 2, even: true)
        case (5, 3): return .init(0, 3)
        case (5, 4): return .init(4, 4, even: true)
        case (5, 5): return .init(3, 5)
        default: return .invalid
        }
    }
}
