import SwiftUI

/// Keeps a component's text and vertical geometry at the page's resting width.
/// Its surface still receives the current width as the page moves past the rail.
struct SettledWidthLayout: Layout {
    let width: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(ProposedViewSize(width: contentWidth(proposal.width), height: nil))
        let availableWidth = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        return CGSize(width: availableWidth ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: contentWidth(bounds.width), height: nil)
        )
    }

    private func contentWidth(_ proposed: CGFloat?) -> CGFloat? {
        (width ?? proposed).flatMap { $0.isFinite ? max(0, $0) : nil }
    }
}
