//
//  PaneLayout.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics

/// Geometry of the top pane for a displayed sheet top.
///
/// The pane fills the space above the sheet and the bottom safe area, minus a gap. Once it reaches its minimum height
/// the frame freezes and the sheet's remaining travel drives `collapseProgress` instead.
nonisolated struct PaneLayout: Equatable {
    /// Pane frame in window coordinates.
    var paneFrame: CGRect
    /// Screen safe-area inset used to locate the collapse destination above the card.
    var safeAreaTop: CGFloat
    /// 0 while the pane resizes; rises to 1 as the sheet travels from the collapse start to `.large`.
    var collapseProgress: CGFloat

    init?(sheetTop: CGFloat?, canvas: PaneCanvas, sideInset: CGFloat, collapseEnd: CGFloat, reduceMotion: Bool) {
        guard let sheetTop, canvas.size.width > 0, canvas.size.height > 0 else {
            return nil
        }

        let gap = PaneLayout.gap(sideInset: sideInset)
        let paneTop = canvas.safeAreaTop + sideInset
        let minPaneBottom = PaneLayout.minPaneBottom(canvas: canvas)
        let collapseStart = minPaneBottom + gap
        let collapseLimit = min(collapseEnd, collapseStart - 1)
        /// Never under the bottom safe area, which covers the tab bar's slot even while the bar is hidden: with the
        /// sheet hidden, the pane rests one gap above the bar.
        let trackedBottom = min(sheetTop - gap, canvas.size.height - canvas.safeAreaBottom - gap)
        let paneBottom: CGFloat
        if reduceMotion {
            /// No frozen frame under Reduce Motion: the pane keeps shrinking above the sheet while it fades.
            paneBottom = max(trackedBottom, paneTop + 1)
        } else {
            paneBottom = max(trackedBottom, minPaneBottom)
        }

        paneFrame = CGRect(
            x: sideInset,
            y: paneTop,
            width: canvas.size.width - 2 * sideInset,
            height: paneBottom - paneTop
        )
        safeAreaTop = canvas.safeAreaTop
        collapseProgress = clipUnit(value: (collapseStart - sheetTop) / (collapseStart - collapseLimit))
    }

    /// Floating sheets use their side inset as the gap, so all gutters match.
    static func gap(sideInset: CGFloat) -> CGFloat {
        sideInset > 0 ? sideInset : PaneMetrics.legacyGap
    }

    static func minPaneBottom(canvas: PaneCanvas) -> CGFloat {
        canvas.safeAreaTop + PaneMetrics.collapsedContentHeight
    }

    /// Sheet top below which the pane stops shrinking and starts collapsing.
    static func collapseStart(canvas: PaneCanvas, sideInset: CGFloat) -> CGFloat {
        minPaneBottom(canvas: canvas) + gap(sideInset: sideInset)
    }
}
