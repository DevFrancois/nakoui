//
//  SheetConstants.swift
//  MapsIOS26BottomSheet
//
//  Values marked "SplitPaneKit" are adapted from SplitPaneKit, Copyright (c) 2025 Joseph Smith.
//  MIT — see THIRD_PARTY_NOTICES.md.
//

import CoreGraphics
import Foundation

/// Native sheet geometry, measured on 402 × 874 pt simulators (62 pt top / 34 pt bottom safe area).
nonisolated struct SheetMetrics: Equatable, Sendable {
    /// Screen bottom to sheet top at the collapsed and medium detents.
    var collapsedOffset: CGFloat
    var mediumOffset: CGFloat
    /// Sheet top at full, below the top safe area.
    var fullTopInset: CGFloat
    /// Gaps between the surface and the screen's side and bottom edges.
    var sideInset: DetentValues
    var bottomInset: DetentValues
    /// Continuous top corner radius; the pane's bottom corners mirror it.
    var topCornerRadius: CGFloat
    /// The native iOS 26 sheet turns opaque (elevated system background) as it reaches full.
    var fadesToOpaqueAtFull: Bool
    /// The surface's visible height at the collapsed detent; the header fills it.
    var headerHeight: CGFloat
    /// The pane's side inset; `PaneLayout.gap` derives the pane–sheet gap from it (8 pt, or 10 pt when 0).
    var paneSideInset: CGFloat

    /// Padding between the surface edge and the header or content.
    static let contentPadding: CGFloat = 18
    static let minimumBottomCornerRadius: CGFloat = 20
    /// The glass sheet's grouped backing below full: enough that the camera or map behind barely tints the sheet, so
    /// its opaque cards always sit on a neutral surface; the glass still shows at the edges and in its highlights.
    static let frostedBackingOpacity: CGFloat = 0.7
    /// Black over everything behind the sheet at full, like the native sheet's dimming; none at medium.
    static let dimmingAtFull: CGFloat = 0.2

    /// Horizontal padding of the scrolling content, which is laid out once at the canvas width.
    var scrollContentPadding: CGFloat {
        sideInset.medium + Self.contentPadding
    }

    func tops(for canvas: PaneCanvas) -> DetentValues {
        DetentValues(
            /// The surface's top at the screen's bottom edge: all of it below the screen.
            hidden: canvas.size.height,
            collapsed: canvas.size.height - collapsedOffset,
            medium: canvas.size.height - mediumOffset,
            full: canvas.safeAreaTop + fullTopInset
        )
    }

    /// iOS 26 and later: Liquid Glass floating at partial detents (measured on iOS 26.2 and 27.2).
    static let floating = SheetMetrics(
        collapsedOffset: 99.3,
        mediumOffset: 376.72,
        fullTopInset: 0,
        /// Below collapsed the surface keeps its collapsed shape, so `hidden` repeats it.
        sideInset: DetentValues(hidden: 28, collapsed: 28, medium: 8, full: 0),
        bottomInset: DetentValues(hidden: 25.85, collapsed: 25.85, medium: 8, full: 0),
        topCornerRadius: 37,
        fadesToOpaqueAtFull: true,
        headerHeight: 73.45,
        paneSideInset: 8
    )

    /// iOS 18: material, edge-attached, `presentationCornerRadius(30)` (measured on iOS 18.5).
    static let edgeAttached = SheetMetrics(
        collapsedOffset: 116.5,
        mediumOffset: 384,
        fullTopInset: 10,
        sideInset: .constant(0),
        bottomInset: .constant(0),
        topCornerRadius: 30,
        fadesToOpaqueAtFull: false,
        headerHeight: 82.5,
        paneSideInset: 0
    )

    static var current: SheetMetrics {
        if #available(iOS 26, *) {
            return .floating
        }

        return .edgeAttached
    }
}

/// Settle springs, driven by Wave so a touch can catch them mid-flight.
nonisolated enum SheetSprings {
    /// SplitPaneKit-like: its `UIViewPropertyAnimator(duration: 0.45, dampingRatio: 0.7)` settles in about 0.45 s.
    static let bouncy = WaveSpring(dampingRatio: 0.7, response: 0.32)
    /// The sheet bounce debug setting off: the same response without overshoot.
    static let settled = WaveSpring(dampingRatio: 1.0, response: 0.32)
    /// The full-sheet surface fade, like Apple Maps: about 0.2 s, starting when the target detent changes.
    static let surface = WaveSpring(dampingRatio: 1.0, response: 0.28)
    /// Replaces the settle springs under Reduce Motion.
    static let reducedMotion = WaveSpring(dampingRatio: 1.0, response: 0.35)
}

nonisolated enum SheetTuning {
    /// SplitPaneKit `dragThreshold`: travel that moves the sheet to the next detent.
    static let nextDetentDistance: CGFloat = 70
    /// SplitPaneKit `velocityThreshold`, in pt/s.
    static let nextDetentVelocity: CGFloat = 300
    /// SplitPaneKit ignores a detent closer than 1 % of the height in the direction of travel.
    static let nextDetentTolerance: CGFloat = 0.01
    /// How far the sheet can be pulled past an end detent (Wave `rubberband` interval).
    static let rubberBandInterval: CGFloat = 80
    /// UIScrollView's rubber-band constant, used by Wave's `rubberband`.
    static let rubberBandConstant: CGFloat = 0.55
    static let maxReleaseVelocity: CGFloat = 6000
    /// Distance within which the sheet counts as at full.
    static let edgeTolerance: CGFloat = 0.5
}
