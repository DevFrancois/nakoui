import Foundation

/// Where Line 'Em Up scrolls to on shorter phones and at large text sizes:
/// the top for each new round, and Next once a line-up is checked.
enum LineUpScrollTarget: Hashable {
    case top
    case next
}
