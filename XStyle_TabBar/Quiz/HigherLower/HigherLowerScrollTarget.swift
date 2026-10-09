import Foundation

/// Where Higher or Lower scrolls to: the top for each new matchup, and the
/// Next button, which brings the verdict and fact above it into view.
nonisolated enum HigherLowerScrollTarget: Hashable {
    case top
    case next
}
