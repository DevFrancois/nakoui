//
//  PaneLayout.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics

/// Geometry of the top pane for a displayed sheet top.
///
/// The pane fills the space above the sheet and the bottom safe area, minus a gap, down to the medium detent. Above
/// it the frame holds its medium size, and the sheet's remaining travel to full drives `coverProgress` as the sheet
/// slides over the pane.
nonisolated struct PaneLayout: Equatable {
    /// Pane frame in window coordinates.
    var paneFrame: CGRect
    /// 0 at medium and below; rises to 1 as the sheet travels on to full, over the pane.
    var coverProgress: CGFloat

    /// - Parameters:
    ///   - holdTop: The sheet top above which the pane holds its frame: the medium detent's.
    ///   - coverEnd: The sheet top where it covers the pane: the full detent's.
    init?(sheetTop: CGFloat?, canvas: PaneCanvas, sideInset: CGFloat, holdTop: CGFloat, coverEnd: CGFloat) {
        guard let sheetTop, canvas.size.width > 0, canvas.size.height > 0 else {
            return nil
        }

        let gap = PaneLayout.gap(sideInset: sideInset)
        let paneTop = canvas.safeAreaTop + sideInset
        /// Never under the bottom safe area, which covers the tab bar's slot even while the bar is hidden: with the
        /// sheet hidden, the pane rests one gap above the bar.
        let trackedBottom = min(max(sheetTop, holdTop) - gap, canvas.size.height - canvas.safeAreaBottom - gap)
        let paneBottom = max(trackedBottom, paneTop + 1)

        paneFrame = CGRect(
            x: sideInset,
            y: paneTop,
            width: canvas.size.width - 2 * sideInset,
            height: paneBottom - paneTop
        )
        coverProgress = holdTop > coverEnd ? clipUnit(value: (holdTop - sheetTop) / (holdTop - coverEnd)) : 0
    }

    /// Floating sheets use their side inset as the gap, so all gutters match.
    static func gap(sideInset: CGFloat) -> CGFloat {
        sideInset > 0 ? sideInset : PaneMetrics.legacyGap
    }
}
