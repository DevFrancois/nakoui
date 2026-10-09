import SwiftUI

/// Sets the clue button beside the points meter when both fit at their
/// natural widths, the button taking any room to spare, and stacks them full
/// width when they don't: in narrow windows, on iPhone Duo's outer display
/// and at large text sizes. Unlike `ViewThatFits`, it keeps a single copy of
/// each control, so their glass IDs stay unique and each control keeps its
/// identity, and its glass, when the arrangement changes or the button goes.
struct MysteryPetControlsLayout: Layout {
    let spacing: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let naturalWidths = naturalWidths(of: subviews)
        let width = proposal.width.map(Double.init) ?? naturalWidths.reduce(0, +) + gaps(between: subviews)

        if let widths = rowWidths(of: subviews, naturalWidths: naturalWidths, in: width) {
            let height = zip(subviews, widths)
                .map { Double($0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height) }
                .max() ?? 0
            return CGSize(width: width, height: height)
        }

        let heights = subviews.map { Double($0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height) }
        return CGSize(width: width, height: heights.reduce(0, +) + gaps(between: subviews))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = Double(bounds.width)

        if let widths = rowWidths(of: subviews, naturalWidths: naturalWidths(of: subviews), in: width) {
            // Centered, which only shows once the button has gone.
            var x = Double(bounds.minX) + (width - widths.reduce(0, +) - gaps(between: subviews)) / 2
            for (subview, subviewWidth) in zip(subviews, widths) {
                subview.place(
                    at: CGPoint(x: x, y: Double(bounds.midY)),
                    anchor: .leading,
                    proposal: ProposedViewSize(width: subviewWidth, height: nil)
                )
                x += subviewWidth + spacing
            }
        } else {
            var y = Double(bounds.minY)
            for subview in subviews {
                let height = Double(subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height)
                subview.place(
                    at: CGPoint(x: Double(bounds.midX), y: y),
                    anchor: .top,
                    proposal: ProposedViewSize(width: width, height: height)
                )
                y += height + spacing
            }
        }
    }

    private func naturalWidths(of subviews: Subviews) -> [Double] {
        subviews.map { Double($0.sizeThatFits(.unspecified).width) }
    }

    private func gaps(between subviews: Subviews) -> Double {
        spacing * Double(max(subviews.count - 1, 0))
    }

    /// Each control's width side by side, with flexible ones, such as the
    /// clue button, sharing the room to spare; nil when they don't fit.
    private func rowWidths(of subviews: Subviews, naturalWidths: [Double], in width: Double) -> [Double]? {
        let spare = width - naturalWidths.reduce(0, +) - gaps(between: subviews)
        guard spare >= 0 else { return nil }

        let isFlexible = zip(subviews, naturalWidths).map { subview, natural in
            Double(subview.sizeThatFits(ProposedViewSize(width: .infinity, height: nil)).width) > natural
        }
        let flexibleCount = isFlexible.count { $0 }
        guard flexibleCount > 0 else { return naturalWidths }

        let share = spare / Double(flexibleCount)
        return zip(naturalWidths, isFlexible).map { natural, flexible in
            flexible ? natural + share : natural
        }
    }
}
