//
//  SheetGeometry.swift
//  MapsIOS26BottomSheet
//

import CoreGraphics

/// Surface shape for one sheet top. Only the surface morphs; the column inside keeps one size.
nonisolated struct SheetGeometry: Equatable {
    /// Glass or material frame, in window coordinates.
    var surface: CGRect
    /// Fixed column size: the canvas width × the sheet's height at full.
    var contentSize: CGSize
    /// Horizontal padding that keeps the header inside the surface and aligned with the content.
    var headerInset: CGFloat
    /// Dimming behind the sheet: 0 at medium and below, `SheetMetrics.dimmingAtFull` at full.
    var dimOpacity: CGFloat
    /// Hide scroll content in the collapsed sheet's bottom safe-area strip; shown as soon as the sheet rises.
    /// A switch, not a fade: a fractional opacity would composite the whole column offscreen every frame.
    var showsContent: Bool

    init(sheetTop: CGFloat, canvas: PaneCanvas, metrics: SheetMetrics, tops: DetentValues) {
        let side = metrics.sideInset.value(at: sheetTop, tops: tops)
        let bottom = metrics.bottomInset.value(at: sheetTop, tops: tops)
        /// Below collapsed the surface slides down whole instead of shrinking, like the native sheet.
        let collapsedHeight = canvas.size.height - metrics.bottomInset.collapsed - tops.collapsed
        surface = CGRect(
            x: side,
            y: sheetTop,
            width: max(canvas.size.width - 2 * side, 0),
            height: max(canvas.size.height - bottom - sheetTop, collapsedHeight, 0)
        )
        contentSize = CGSize(width: canvas.size.width, height: max(canvas.size.height - tops.full, 0))
        headerInset = max(side, metrics.sideInset.medium) + SheetMetrics.contentPadding
        let towardFull = tops.medium > tops.full
            ? clipUnit(value: (tops.medium - sheetTop) / (tops.medium - tops.full))
            : 0
        dimOpacity = SheetMetrics.dimmingAtFull * towardFull
        showsContent = sheetTop < tops.collapsed - SheetTuning.edgeTolerance
    }

    /// The column's frame: top-aligned and centered in the surface, so it overhangs it at partial detents.
    var column: CGRect {
        CGRect(
            x: surface.midX - contentSize.width / 2,
            y: surface.minY,
            width: contentSize.width,
            height: contentSize.height
        )
    }
}
