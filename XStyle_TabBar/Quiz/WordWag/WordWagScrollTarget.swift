import Foundation

/// Where Word Wag scrolls to: the top for each new word, and the Next
/// button, which brings the fact above it into view on short screens.
nonisolated enum WordWagScrollTarget: Hashable {
    case top
    case next
}
