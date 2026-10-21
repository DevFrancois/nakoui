//
//  PaneConstants.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics
import Foundation

/// Layout constants for the top pane.
nonisolated enum PaneMetrics {
    /// Gap between the pane and the sheet when the sheet is edge-attached (iOS 18).
    /// Floating sheets (iOS 26+) use their own side inset instead, so every gutter matches.
    static let legacyGap: CGFloat = 10
    /// The scanner viewport's continuous corner radius, on all four corners. Separate from the sheet's.
    static let viewportCornerRadius: CGFloat = 60
    /// The white edge around the viewport in dark mode, so it stands out from the black background.
    static let darkEdgeOpacity = 0.15
}

/// Wave springs used by the top pane.
nonisolated enum PaneSprings {
    /// Wave's interactive examples use a short response for tracking and retain velocity when retargeting.
    /// Cache each spring so switching the smoothing does not allocate physics objects on every frame.
    static func stretch(isSmoothed: Bool) -> WaveSpring {
        isSmoothed ? smoothed : standard
    }

    private static let standard = WaveSpring(dampingRatio: 0.76, response: 0.28)
    /// Critically damped: follows the speed without overshooting it, so it never wobbles.
    private static let smoothed = WaveSpring(dampingRatio: 1.0, response: 0.28)
}

/// Tuning of the pane's velocity stretch, and of the sheet sliding over it.
nonisolated enum PaneTuning {
    /// The sheet velocity counts as stale (the finger stopped) after this long without an update.
    static let freshInterval: CFTimeInterval = 0.05
    /// Velocity (pt/s) that produces the full stretch.
    static let stretchReferenceVelocity: CGFloat = 2400
    /// Horizontal squash at full stretch.
    static let maxSquash: CGFloat = 0.035
    /// Time constant of the speed filter used by the smoothed stretch.
    static let velocitySmoothing: CFTimeInterval = 0.06
    /// The pane's scale once the sheet covers it at full: pushed back a little, like the content under a stacked
    /// sheet.
    static let coveredScale: CGFloat = 0.94
    /// The receding pane's scale with the sheet at each detent, linear between them.
    static let recedingScale = DetentValues(hidden: 1, medium: 0.95, full: 0.9)
}
