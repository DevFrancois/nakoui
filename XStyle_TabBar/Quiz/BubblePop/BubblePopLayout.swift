import SwiftUI

/// Places the bubbles. Floating, they rise in columns, each column at its own
/// pace and staggered so bubbles sharing a column never touch; each sways
/// within its column, leaves through the top and comes back in at the bottom.
/// In a grid, they sit in centered rows that wrap; the HUD uses the grid too
/// at accessibility text sizes. Positions depend only on the arrangement, so
/// a `TimelineView` can redraw them every frame, and switching arrangement
/// inside an animation glides every bubble into place.
nonisolated struct BubblePopLayout: Layout {
    let arrangement: BubblePopArrangement
    /// The gap between bubbles in the grid.
    let spacing: Double

    /// How much faster or slower each column rises than the round's speed.
    private static let columnPaces = [1.0, 0.84, 1.14, 0.93]
    /// Staggers where each column starts, as a fraction of a full rise.
    private static let columnOffset = 0.29
    /// Room left around the widest bubble when deciding how many columns fit.
    private static let columnRoom = 1.15
    /// Room between bubbles sharing a column, relative to the widest bubble.
    private static let rowRoom = 1.2
    /// The widest a bubble sways, in points.
    private static let maximumSway = 14.0
    /// How far past the edges a bubble wraps around, so it's never seen jump.
    private static let wrapMargin = 4.0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        switch arrangement {
        case .floating(_, _, let height):
            return CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: height)
        case .grid:
            // Unbounded, the rows run as wide as they like and report it.
            let width = proposal.width.map(Double.init) ?? .infinity
            let rows = grid(for: gridSizes(of: subviews, width: width), width: width)
            return CGSize(width: width.isFinite ? width : rows.width, height: rows.height)
        }
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes: [CGSize]
        let centers: [CGPoint]
        switch arrangement {
        case .floating(let elapsed, let speed, _):
            sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            let drifts = subviews.map { $0[BubblePopDriftKey.self] }
            centers = floatingCenters(sizes: sizes, drifts: drifts, in: bounds, elapsed: elapsed, speed: speed)
        case .grid:
            sizes = gridSizes(of: subviews, width: bounds.width)
            centers = grid(for: sizes, width: bounds.width).centers.map { center in
                CGPoint(x: bounds.minX + center.x, y: bounds.minY + center.y)
            }
        }

        for (index, subview) in subviews.enumerated() {
            let center = index < centers.count ? centers[index] : CGPoint(x: bounds.midX, y: bounds.midY)
            subview.place(at: center, anchor: .center, proposal: ProposedViewSize(sizes[index]))
        }
    }

    /// Each piece's size in the grid. Circles keep their own size; a bubble
    /// that fits its word, at accessibility text sizes, wraps at `width`
    /// rather than running off the side.
    private func gridSizes(of subviews: Subviews, width: Double) -> [CGSize] {
        let proposal = ProposedViewSize(width: width.isFinite ? width : nil, height: nil)
        return subviews.map { $0.sizeThatFits(proposal) }
    }

    /// Where each bubble is `elapsed` seconds into the round.
    private func floatingCenters(
        sizes: [CGSize],
        drifts: [BubblePopDrift],
        in bounds: CGRect,
        elapsed: TimeInterval,
        speed: Double
    ) -> [CGPoint] {
        let count = sizes.count
        let largest = Double(sizes.map(\.width).max() ?? 0)
        guard count > 0, largest > 0 else { return [] }

        let width = Double(bounds.width)
        let columns = min(max(Int(width / (largest * Self.columnRoom)), 2), count)
        let columnWidth = width / Double(columns)
        let rows = (count + columns - 1) / columns
        // One full rise, from just below the bottom edge to just above the
        // top, and long enough that bubbles sharing a column stay apart.
        let bottom = Double(bounds.maxY) + largest / 2 + Self.wrapMargin
        let rise = max(Double(bounds.height) + largest + 2 * Self.wrapMargin, Double(rows) * largest * Self.rowRoom)

        return (0..<count).map { index in
            let column = index % columns
            let row = index / columns
            let inColumn = (count - column + columns - 1) / columns
            let drift = drifts[index]
            let pace = speed * Self.columnPaces[column % Self.columnPaces.count]
            let start = (Double(row) + drift.lift) / Double(inColumn) + Double(column) * Self.columnOffset
            let progress = (start + elapsed * pace / rise).truncatingRemainder(dividingBy: 1)

            let diameter = Double(sizes[index].width)
            let sway = min(max((columnWidth - diameter) / 2 - 2, 0), Self.maximumSway)
            let swing = sin(elapsed * drift.wobbleRate * 2 * .pi + drift.wobbleOffset)
            let x = Double(bounds.minX) + columnWidth * (Double(column) + 0.5) + swing * sway
            let y = bottom - progress * rise
            return CGPoint(x: x, y: y)
        }
    }

    /// Centers for bubbles in rows that wrap at `width`, each row centered,
    /// relative to the top leading corner; the widest row; and the height of
    /// all the rows.
    private func grid(for sizes: [CGSize], width: Double) -> (centers: [CGPoint], width: Double, height: Double) {
        var rows: [[Int]] = []
        var rowWidth = 0.0
        for index in sizes.indices {
            let bubbleWidth = Double(sizes[index].width)
            if let last = rows.indices.last, rowWidth + spacing + bubbleWidth <= width {
                rows[last].append(index)
                rowWidth += spacing + bubbleWidth
            } else {
                rows.append([index])
                rowWidth = bubbleWidth
            }
        }

        var centers = Array(repeating: CGPoint.zero, count: sizes.count)
        var widest = 0.0
        var y = 0.0
        for row in rows {
            let rowHeight = Double(row.map { sizes[$0].height }.max() ?? 0)
            let bubblesWidth = row.reduce(0.0) { $0 + Double(sizes[$1].width) } + spacing * Double(row.count - 1)
            widest = max(widest, bubblesWidth)
            // Centered in the row, or from the leading edge when unbounded.
            var x = width.isFinite ? (width - bubblesWidth) / 2 : 0
            for index in row {
                let bubbleWidth = Double(sizes[index].width)
                centers[index] = CGPoint(x: x + bubbleWidth / 2, y: y + rowHeight / 2)
                x += bubbleWidth + spacing
            }
            y += rowHeight + spacing
        }
        return (centers, widest, max(y - spacing, 0))
    }
}
