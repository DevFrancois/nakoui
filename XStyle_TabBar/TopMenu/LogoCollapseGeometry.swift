import CoreGraphics

/// Sizes the disappearing logo against its own row, independently of where
/// the system places bars or camera hardware.
struct LogoCollapseGeometry {
    let containerWidth: CGFloat

    func flight(wordmarkSize: CGSize) -> LogoFlight {
        guard containerWidth > 0, wordmarkSize != .zero else { return .none }

        let width = min(TopMenuMetrics.collapseTargetMaxWidth, containerWidth * TopMenuMetrics.collapseTargetWidthFraction)
        let height = TopMenuMetrics.logoRowHeight * TopMenuMetrics.collapseTargetHeightFraction
        let finalWidth = wordmarkSize.width + TopMenuMetrics.wordmarkFramePadding.width
        let finalHeight = wordmarkSize.height + TopMenuMetrics.wordmarkFramePadding.height

        return LogoFlight(scale: min(1, width / finalWidth, height / finalHeight))
    }
}
