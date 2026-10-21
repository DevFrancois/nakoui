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
    /// Height kept below the top safe area once the pane stops shrinking and starts collapsing.
    static let collapsedContentHeight: CGFloat = 140
}

/// Wave springs used by the top pane.
nonisolated enum PaneSprings {
    /// Wave's interactive examples use a short response for tracking and retain velocity when retargeting.
    /// Cache each spring so updates to the selected effect do not allocate physics objects on every frame.
    static func stretch(effect: PaneEffect, isSmoothed: Bool) -> WaveSpring {
        if isSmoothed {
            return smoothed
        }
        switch effect {
        case .funnel: return funnel
        case .island: return island
        }
    }

    private static let funnel = WaveSpring(dampingRatio: 0.76, response: 0.28)
    private static let island = WaveSpring(dampingRatio: 0.82, response: 0.24)
    /// Critically damped: follows the speed without overshooting it, so it never wobbles.
    private static let smoothed = WaveSpring(dampingRatio: 1.0, response: 0.28)
}

/// Tuning of the pane's velocity stretch.
nonisolated enum PaneTuning {
    /// The sheet velocity counts as stale (the finger stopped) after this long without an update.
    static let freshInterval: CFTimeInterval = 0.05
    /// Velocity (pt/s) that produces the full stretch.
    static let stretchReferenceVelocity: CGFloat = 2400
    /// Horizontal squash at full stretch.
    static let maxSquash: CGFloat = 0.035
    /// Time constant of the speed filter used by the smoothed stretch.
    static let velocitySmoothing: CFTimeInterval = 0.06
}
