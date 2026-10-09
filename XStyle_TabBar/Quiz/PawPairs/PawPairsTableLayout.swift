import SwiftUI

/// Places cards in equal columns and rows of one height, in order. Changing
/// the columns or the order glides each card to its new place, which is how
/// a cleared board lines up two by two.
struct PawPairsTableLayout: Layout {
    var columns: Int
    var rowHeight: Double
    var columnSpacing: Double
    var rowSpacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let columns = max(columns, 1)
        let rows = (subviews.count + columns - 1) / columns
        let height = Double(rows) * rowHeight + Double(max(rows - 1, 0)) * rowSpacing
        return CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = max(columns, 1)
        let cellWidth = (bounds.width - Double(columns - 1) * columnSpacing) / Double(columns)
        let cellSize = ProposedViewSize(width: cellWidth, height: rowHeight)

        for (index, subview) in subviews.enumerated() {
            let column = Double(index % columns)
            let row = Double(index / columns)
            subview.place(
                at: CGPoint(
                    x: bounds.minX + column * (cellWidth + columnSpacing),
                    y: bounds.minY + row * (rowHeight + rowSpacing)
                ),
                anchor: .topLeading,
                proposal: cellSize
            )
        }
    }
}
