import SwiftUI

/// Sizes, thresholds and timings of the top menu, matching ZoomInUIKit's.
enum TopMenuMetrics {
    // MARK: Rows

    static let logoRowHeight: CGFloat = 40
    static let chipRowHeight = chipHeight + chipVerticalInset * 2
    /// The menu's height with the logo row shown. Content keeps this inset even
    /// when the row collapses, so scrolling cannot feed back into the menu.
    static let expandedHeight = logoRowHeight + chipRowHeight
    /// Space between the menu and the first row of content.
    static let contentTopPadding: CGFloat = 10
    static let logoRowHorizontalPadding: CGFloat = 15
    static let minimumTapSize: CGFloat = 44

    // MARK: Wordmark

    static let wordmarkFont = Font.system(size: 30, weight: .regular, design: .serif)
    static let wordmarkKerning: CGFloat = -2

    // MARK: Chips

    static let chipHeight: CGFloat = 44
    static let chipVerticalInset: CGFloat = 4
    static let chipCornerRadius: CGFloat = 12
    static let chipSpacing: CGFloat = 5
    static let chipRowSideInset: CGFloat = 16
    static let chipLeadingPadding: CGFloat = 10
    static let chipIconTitleSpacing: CGFloat = 6
    static let chipTrailingPadding: CGFloat = 14
    static let chipTitleFont = Font.system(size: 15, weight: .semibold)
    static let chipIconFont = Font.system(size: 17, weight: .semibold)
    /// The selected chip is kept at least this far from the row's edges.
    static let chipRevealPadding: CGFloat = 44
    /// Light mode only; dark glass is untinted.
    static let lightGlassTint = Color.black.opacity(0.06)
    static let lightPlatter = Color.white
    static let darkPlatter = Color(white: 0.30)

    // MARK: Scroll behaviour

    /// Movement between two scroll updates that hides (down) or shows (up) the
    /// logo row. Per update, not accumulated, so slow drags leave it alone.
    static let logoScrollThreshold: CGFloat = 4
    /// Within this distance of the top, the logo row is always shown.
    static let logoTopZone: CGFloat = 6

    // MARK: Device pill

    static let pillWidth: CGFloat = 126
    static let pillMaximumWidthFraction: CGFloat = 0.34
    static let pillHeightWithIsland: CGFloat = 36
    static let pillHeightWithoutIsland: CGFloat = 28
    /// Safe-area tops at least this tall belong to Dynamic Island devices.
    static let islandSafeAreaTop: CGFloat = 50
    static let pillMinimumTop: CGFloat = 6
    /// Padding around the wordmark's text when sizing it into the pill.
    static let wordmarkFramePadding = CGSize(width: 24, height: 4)

    // MARK: Animations

    static let collapseAnimation = Animation.easeOut(duration: 0.15)
    static let flightAnimation = Animation.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.22)
    static let selectionAnimation = Animation.easeOut(duration: 0.22)
    static let revealAnimation = Animation.smooth(duration: 0.3)
}
