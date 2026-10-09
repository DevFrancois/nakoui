import Foundation

/// One Paw Pairs board: a theme, the pairs hidden in it, and a fun fact for
/// when it's cleared.
struct PawPairsBoard {
    let title: LocalizedStringResource
    let prompt: LocalizedStringResource
    let symbol: String
    let pairs: [PawPairsPair]
    let fact: LocalizedStringResource

    /// The most moves that still earn the board's point: two per pair, with
    /// a little room for bad luck. Going over never stops the board.
    var par: Int {
        pairs.count * 2 + 2
    }
}
