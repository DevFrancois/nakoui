import SwiftUI

/// Stacks cards front to back: the front one at its natural height, and each
/// one behind it at the front card's height, shifted down so only its bottom
/// edge shows. Draw order is left to the cards' `zIndex`.
///
/// Cards are placed by their `TaskStackDepth`, not their position among the
/// subviews: a card being removed can stay among them until its transition
/// ends, and the cards behind should move forward at once.
struct TaskStackLayout: Layout {
    /// How far each card behind shows below the one in front of it.
    var peek: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let front = front(of: subviews) else { return .zero }
        let frontSize = front.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let deepest = subviews.map { $0[TaskStackDepth.self] }.max() ?? 0
        return CGSize(
            width: proposal.width ?? frontSize.width,
            height: frontSize.height + peek * CGFloat(deepest)
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let front = front(of: subviews) else { return }
        let frontHeight = front.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height

        for subview in subviews {
            let depth = subview[TaskStackDepth.self]
            subview.place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + peek * CGFloat(depth)),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: depth == 0 ? nil : frontHeight)
            )
        }
    }

    /// The front card. One that's leaving keeps depth 0 until it's gone, and
    /// comes before its replacement, so the last card at depth 0 is the front.
    private func front(of subviews: Subviews) -> LayoutSubview? {
        subviews.last { $0[TaskStackDepth.self] == 0 }
    }
}
