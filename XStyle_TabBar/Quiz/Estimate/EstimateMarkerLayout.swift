import SwiftUI

/// Centers each subview at a fraction of the width, read from its
/// `EstimateMarkerPosition`, and vertically in the middle.
struct EstimateMarkerLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let fraction = subview[EstimateMarkerPosition.self]
            subview.place(
                at: CGPoint(x: bounds.minX + bounds.width * fraction, y: bounds.midY),
                anchor: .center,
                proposal: .unspecified
            )
        }
    }
}
