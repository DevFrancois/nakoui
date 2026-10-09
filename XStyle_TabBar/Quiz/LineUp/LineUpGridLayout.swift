import SwiftUI

/// Lays out cells in equal-width columns, row by row, each row as tall as
/// its tallest cell. Unlike a lazy grid, it builds every cell up front, so
/// glass can morph in and out of any of them.
struct LineUpGridLayout: Layout {
    let columns: Int
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = Double(proposal.replacingUnspecifiedDimensions().width)
        let heights = rowHeights(of: subviews, cellWidth: cellWidth(in: width))
        let height = heights.reduce(0, +) + spacing * Double(max(heights.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cellWidth = cellWidth(in: Double(bounds.width))
        var y = Double(bounds.minY)
        for (row, height) in rowHeights(of: subviews, cellWidth: cellWidth).enumerated() {
            for column in 0..<columnCount {
                let index = row * columnCount + column
                guard index < subviews.count else { break }
                let x = Double(bounds.minX) + Double(column) * (cellWidth + spacing)
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: cellWidth, height: height)
                )
            }
            y += height + spacing
        }
    }

    private var columnCount: Int {
        max(columns, 1)
    }

    private func cellWidth(in width: Double) -> Double {
        let count = Double(columnCount)
        return max((width - spacing * (count - 1)) / count, 0)
    }

    /// Each row's height: its tallest cell at the column width.
    private func rowHeights(of subviews: Subviews, cellWidth: Double) -> [Double] {
        stride(from: 0, to: subviews.count, by: columnCount).map { start in
            subviews[start..<min(start + columnCount, subviews.count)]
                .map { Double($0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height) }
                .max() ?? 0
        }
    }
}
