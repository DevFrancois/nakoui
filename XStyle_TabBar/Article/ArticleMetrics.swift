import Foundation

/// Shared sizes so the feed thumbnail and the article view stay visually consistent.
enum ArticleMetrics {
    static let thumbnailHeight = 180.0
    static let thumbnailCornerRadius = 16.0
    static let heroCornerRadius = 24.0
    /// The square hero stops growing past this width, on iPad and wide windows.
    static let heroMaxWidth = 600.0
    /// How far down the page the backdrop's top lights reach, as a multiple of its height.
    static let backdropCoverage = 1.4
    /// How far up the page the bottom lights reach. Shorter than the top, so the
    /// middle of the page, where the text starts, stays close to the base.
    static let backdropBottomCoverage = 1.0
    static let galleryDotSize = 7.0
    static let galleryCurrentDotWidth = 20.0
    static let galleryDotSpacing = 6.0
    static let galleryIndicatorPadding = 8.0
}
