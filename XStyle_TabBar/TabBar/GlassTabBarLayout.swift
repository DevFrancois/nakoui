import SwiftUI

/// Geometry depends on the offered space and bar axis, never a device model
/// or a width/orientation guess about where the system puts its bars.
nonisolated struct GlassTabBarLayout {
    static let spacing: CGFloat = 10
    let frames: [CGRect]

    static func fittingSize(
        proposal: ProposedViewSize,
        axis: Axis,
        itemCount: Int,
        horizontalHeight: CGFloat
    ) -> CGSize {
        if axis == .vertical {
            // A native vertical bar has a fixed width. Use compact targets
            // and measure height from that width, not the horizontal bar's
            // scaled height; otherwise the panel keeps empty space at its ends.
            let diameter = max(0, min(proposal.width ?? 44, 44))
            let count = CGFloat(max(0, itemCount))
            let idealHeight = diameter * count + spacing * max(0, count - 1)
            return CGSize(
                width: diameter,
                height: max(0, min(proposal.height ?? idealHeight, idealHeight))
            )
        }
        return CGSize(width: max(0, min(proposal.width ?? 360, 460)), height: horizontalHeight)
    }

    init(
        bounds: CGRect,
        axis: Axis,
        itemCount: Int,
        selectedIndex: Int?,
        expandedWidth: CGFloat,
        isRightToLeft: Bool
    ) {
        guard itemCount > 0 else {
            frames = []
            return
        }

        let isVertical = axis == .vertical
        let length = max(0, isVertical ? bounds.height : bounds.width)
        let crossLength = max(0, isVertical ? bounds.width : bounds.height)
        let gapCount = CGFloat(itemCount - 1)
        let minimumItemLength = min(crossLength, 44)
        let gap = gapCount > 0
            ? min(Self.spacing, max(0, (length - CGFloat(itemCount) * minimumItemLength) / gapCount))
            : 0
        let usableLength = max(0, length - gap * gapCount)
        let diameter = min(crossLength, usableLength / CGFloat(itemCount))
        let expandsSelection = !isVertical && selectedIndex.map { (0..<itemCount).contains($0) } == true
        let selectedLength = expandsSelection
            ? min(max(diameter, expandedWidth), usableLength - diameter * gapCount)
            : diameter
        let totalLength = diameter * gapCount + selectedLength + gap * gapCount
        var position = (length - totalLength) / 2

        frames = (0..<itemCount).map { index in
            let itemLength = expandsSelection && index == selectedIndex ? selectedLength : diameter
            defer { position += itemLength + gap }

            if isVertical {
                return CGRect(
                    x: bounds.minX + (crossLength - diameter) / 2,
                    y: bounds.minY + position,
                    width: diameter,
                    height: itemLength
                )
            }
            return CGRect(
                x: bounds.minX + (isRightToLeft ? length - position - itemLength : position),
                y: bounds.minY + (crossLength - diameter) / 2,
                width: itemLength,
                height: diameter
            )
        }
    }
}
