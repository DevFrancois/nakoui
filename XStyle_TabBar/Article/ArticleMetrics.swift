import Foundation

/// Shared sizes so the feed thumbnail and the article view stay visually consistent.
enum ArticleMetrics {
    static let thumbnailHeight = 180.0
    static let thumbnailCornerRadius = 16.0
    static let heroCornerRadius = 24.0
    /// The square hero stops growing past this width, on iPad and wide windows.
    static let heroMaxWidth = 600.0
    /// How far down the page the backdrop's lights reach, as a multiple of its height.
    static let backdropCoverage = 1.4
    /// Matches a navigation bar button, and Apple's minimum tap size.
    static let barButtonSize = 44.0
}
