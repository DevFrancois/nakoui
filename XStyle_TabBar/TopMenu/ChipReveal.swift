import CoreGraphics

/// Keeps the selection clear of the chip strip's edges. Ported from
/// ZoomInUIKit's `chipFrame(for:)` and `keepChipVisible`.
enum ChipReveal {
    /// - Parameters:
    ///   - selection: Fractional chip index; between two chips while the pager moves.
    ///   - chipFrames: Every chip's frame in the strip's content, in order.
    /// - Returns: The offset to scroll the strip to, or `nil` if it can stay put.
    static func targetOffset(
        selection: CGFloat,
        chipFrames: [CGRect],
        geometry: ChipStripGeometry
    ) -> CGFloat? {
        guard geometry.viewportWidth > 0,
              geometry.contentWidth > geometry.viewportWidth,
              let frame = selectionFrame(selection, chipFrames: chipFrames) else { return nil }

        let padding = TopMenuMetrics.chipRevealPadding
        let visibleMinX = geometry.offset + padding
        let visibleMaxX = geometry.offset + geometry.viewportWidth - padding
        var target = geometry.offset

        if frame.minX < visibleMinX {
            target = frame.minX - padding
        } else if frame.maxX > visibleMaxX {
            target = frame.maxX - geometry.viewportWidth + padding
        }

        let maxOffset = max(0, geometry.contentWidth - geometry.viewportWidth)
        target = min(max(target, 0), maxOffset)
        return abs(target - geometry.offset) > 0.5 ? target : nil
    }

    /// The selection's frame, interpolated between the two chips around it.
    private static func selectionFrame(_ selection: CGFloat, chipFrames: [CGRect]) -> CGRect? {
        guard !chipFrames.isEmpty else { return nil }

        let lowerIndex = min(max(Int(selection.rounded(.down)), 0), chipFrames.count - 1)
        let upperIndex = min(lowerIndex + 1, chipFrames.count - 1)
        let fraction = min(max(selection - CGFloat(lowerIndex), 0), 1)
        let lower = chipFrames[lowerIndex]
        let upper = chipFrames[upperIndex]

        return CGRect(
            x: lower.minX + (upper.minX - lower.minX) * fraction,
            y: lower.minY + (upper.minY - lower.minY) * fraction,
            width: lower.width + (upper.width - lower.width) * fraction,
            height: lower.height + (upper.height - lower.height) * fraction
        )
    }
}
