import Foundation

/// Where Paw Pairs scrolls to: the board's header when a new board starts,
/// and the verdict or Next once a board is cleared.
nonisolated enum PawPairsScrollTarget: Hashable {
    case top
    case verdict
    case next
}
