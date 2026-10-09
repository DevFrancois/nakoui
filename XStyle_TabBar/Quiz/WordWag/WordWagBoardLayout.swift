import SwiftUI

/// Places each subview at the spot its `WordWagSpotKey` names, sized to a
/// tile, or to the whole slot row for the guess. Tiles stay the same views
/// wherever they sit, so moving one between tray and slot animates its
/// position, and its glass glides and blends along the way.
struct WordWagBoardLayout: Layout {
    let letterCount: Int
    let preferredTileSize: Double
    let minimumTileSize: Double
    let tileSpacing: Double
    let traySpacing: Double
    let showsTray: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // An unbounded width, such as inside a horizontal scroll view, would
        // center rows at infinity, so it gets the ideal width instead.
        let width = proposal.width.flatMap { $0.isFinite ? Double($0) : nil } ?? idealWidth
        return grid(width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = grid(width: bounds.width)
        for subview in subviews {
            let frame = grid.frame(for: subview[WordWagSpotKey.self])
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Every tile at its preferred size in one row.
    private var idealWidth: Double {
        Double(letterCount) * preferredTileSize + Double(max(letterCount - 1, 0)) * tileSpacing
    }

    private func grid(width: Double) -> WordWagBoardGrid {
        WordWagBoardGrid(
            width: width,
            letterCount: letterCount,
            preferredTileSize: preferredTileSize,
            minimumTileSize: minimumTileSize,
            tileSpacing: tileSpacing,
            traySpacing: traySpacing,
            showsTray: showsTray
        )
    }
}
