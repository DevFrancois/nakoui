import CoreGraphics

/// Where the logo row's items go when it collapses: the physical pill at the
/// top centre of the screen, the Dynamic Island or the notch area. Ported from
/// ZoomInUIKit's `devicePillTargetFrame` and `logoRiseGeometry`.
struct DevicePillGeometry {
    /// The safe-area top, which is also the menu's top edge.
    let safeAreaTop: CGFloat
    let containerWidth: CGFloat

    var frame: CGRect {
        let hasIsland = safeAreaTop >= TopMenuMetrics.islandSafeAreaTop
        let height = hasIsland ? TopMenuMetrics.pillHeightWithIsland : TopMenuMetrics.pillHeightWithoutIsland
        let width = min(TopMenuMetrics.pillWidth, containerWidth * TopMenuMetrics.pillMaximumWidthFraction)

        return CGRect(
            x: (containerWidth - width) / 2,
            y: max(TopMenuMetrics.pillMinimumTop, (safeAreaTop - height) / 2),
            width: width,
            height: height
        )
    }

    /// The travel and scale that take the wordmark, centred in the logo row,
    /// into the pill. The row's other items share them, so the whole row
    /// leaves as one gesture.
    func flight(wordmarkSize: CGSize) -> LogoFlight {
        guard containerWidth > 0, wordmarkSize != .zero else { return .none }

        let pill = frame
        let finalWidth = wordmarkSize.width + TopMenuMetrics.wordmarkFramePadding.width
        let finalHeight = wordmarkSize.height + TopMenuMetrics.wordmarkFramePadding.height
        let rowMidY = safeAreaTop + TopMenuMetrics.logoRowHeight / 2

        return LogoFlight(
            travel: pill.midY - rowMidY,
            scale: min(pill.width / finalWidth, pill.height / finalHeight)
        )
    }
}
