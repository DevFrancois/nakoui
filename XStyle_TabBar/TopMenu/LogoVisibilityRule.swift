import CoreGraphics

/// Decides when the logo row hides or returns, from two consecutive vertical
/// offsets of the selected page. Ported from ZoomInUIKit's `desiredLogoVisibility`.
enum LogoVisibilityRule {
    /// - Parameters:
    ///   - previousOffset: The offset from the top of the content at the previous update.
    ///   - offset: The offset from the top of the content now.
    /// - Returns: The logo row's new visibility, or `nil` to keep the current one.
    static func visibility(previousOffset: CGFloat, offset: CGFloat) -> Bool? {
        if offset <= TopMenuMetrics.logoTopZone {
            return true
        }

        let delta = offset - previousOffset
        if delta > TopMenuMetrics.logoScrollThreshold {
            return false
        }
        if delta < -TopMenuMetrics.logoScrollThreshold {
            return true
        }
        return nil
    }
}
