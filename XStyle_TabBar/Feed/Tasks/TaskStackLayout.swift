import SwiftUI

/// Stacks cards front to back: the first at its natural height, and each one
/// behind it at the front card's height, shifted down so only its bottom edge
/// shows. Draw order is left to the cards' `zIndex`.
struct TaskStackLayout: Layout {
    /// How far each card behind shows below the one in front of it.
    var peek: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let front = subviews.first else { return .zero }
        let frontSize = front.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(
            width: proposal.width ?? frontSize.width,
            height: frontSize.height + peek * CGFloat(subviews.count - 1)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let front = subviews.first else { return }
        let frontHeight = front.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height

        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + peek * CGFloat(index)),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: index == 0 ? nil : frontHeight)
            )
        }
    }
}
