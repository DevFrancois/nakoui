import Foundation

/// Shared sizes so the feed thumbnail and the article view stay visually consistent.
enum ArticleMetrics {
    static let thumbnailHeight = 180.0
    static let thumbnailCornerRadius = 16.0
    /// Fraction of the visible height taken by the hero placeholder in the article view.
    static let heroHeightFraction = 0.42
    /// Matches a navigation bar button, and Apple's minimum tap size.
    static let barButtonSize = 44.0
}
