//
//  PaneLayout.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics

/// Geometry of the top pane for a displayed sheet top.
///
/// The pane fills the space above the sheet and the bottom safe area, minus a gap, down to the medium detent. Above
/// it the frame holds its medium size, and the sheet's remaining travel to full drives `coverProgress` as the sheet
/// slides over the pane. With the sheet hidden, it also leaves room for a footer above the bottom safe area; the room
/// closes as the sheet rises to collapsed, over the footer.
nonisolated struct PaneLayout: Equatable {
    /// Pane frame in window coordinates.
    var paneFrame: CGRect
    /// 0 at medium and below; rises to 1 as the sheet travels on to full, over the pane.
    var coverProgress: CGFloat
    /// The footer's bottom edge in window coordinates: one gap above the bottom safe area, wherever the sheet is.
    var footerBottom: CGFloat

    /// - Parameters:
    ///   - tops: The sheet's detent tops. The pane holds its frame above medium, and the sheet covers it at full.
    ///   - footerHeight: The measured height of what sits between the pane and the bottom safe area while the sheet
    ///     is hidden; 0 for none.
    init?(sheetTop: CGFloat?, canvas: PaneCanvas, sideInset: CGFloat, tops: DetentValues, footerHeight: CGFloat) {
        guard let sheetTop, canvas.size.width > 0, canvas.size.height > 0 else {
            return nil
        }

        let gap = PaneLayout.gap(sideInset: sideInset)
        let paneTop = canvas.safeAreaTop + sideInset
        /// Never under the bottom safe area, which covers the tab bar's slot even while the bar is hidden: with the
        /// sheet hidden, the pane rests one gap above the bar, or above its footer.
        let footerRoom = footerHeight > 0 ? footerHeight + gap : 0
        let footerShare = tops.hidden > tops.collapsed
            ? clipUnit(value: (sheetTop - tops.collapsed) / (tops.hidden - tops.collapsed))
            : 0
        let footerBottom = canvas.size.height - canvas.safeAreaBottom - gap
        let lowestBottom = footerBottom - footerRoom * footerShare
        let trackedBottom = min(max(sheetTop, tops.medium) - gap, lowestBottom)
        let paneBottom = max(trackedBottom, paneTop + 1)

        paneFrame = CGRect(
            x: sideInset,
            y: paneTop,
            width: canvas.size.width - 2 * sideInset,
            height: paneBottom - paneTop
        )
        coverProgress = tops.medium > tops.full
            ? clipUnit(value: (tops.medium - sheetTop) / (tops.medium - tops.full))
            : 0
        self.footerBottom = footerBottom
    }

    /// Floating sheets use their side inset as the gap, so all gutters match.
    static func gap(sideInset: CGFloat) -> CGFloat {
        sideInset > 0 ? sideInset : PaneMetrics.legacyGap
    }
}
